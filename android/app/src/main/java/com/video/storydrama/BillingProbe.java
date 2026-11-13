package com.video.storydrama;

import android.content.Context;
import android.util.Log;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingConfig;
import com.android.billingclient.api.BillingConfigResponseListener;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.GetBillingConfigParams;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.ProductDetailsResponseListener;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryProductDetailsResult;
import com.android.billingclient.api.UnfetchedProduct;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 直接向 Google Play 查询商品详情，并把 **每个商品各自的失败原因码** 带回来。
 *
 * <p>为什么必须有这个类：flutter 的 {@code in_app_purchase_android} 插件在
 * {@code Translator.fromUnfetchedProduct} 里只保留了 productId，把
 * {@code UnfetchedProduct.getStatusCode()} 直接丢掉了。于是 App 侧只看到
 * "unfetched"，无法区分下面两种完全不同的失败：
 *
 * <ul>
 *   <li>{@code statusCode = 3 PRODUCT_NOT_FOUND}：这个商品在**当前这个 Play 应用**下
 *       根本不存在（建在了另一个 Play 应用下 / 建成了另一种商品类型 / ID 拼错 / 未激活）。
 *   <li>{@code statusCode = 4 NO_ELIGIBLE_OFFER}：商品**确实存在**，但当前账号 / 国家
 *       没有可购买的 offer（基础方案没配价、没激活、区域不匹配、账号国家与 Play 区域不符）。
 * </ul>
 *
 * 这两种情况的排查与修复方式完全不同，必须在原生层区分开。
 */
public class BillingProbe {

    private static final String TAG = "BillingProbe";

    /** 探针结果回调。 */
    public interface Callback {
        void onResult(Map<String, Object> data);
    }

    private interface TypeCallback {
        void onType(Map<String, Object> query);
    }

    private final Context appContext;

    public BillingProbe(Context context) {
        this.appContext = context.getApplicationContext();
    }

    /**
     * 查询 [productIds]，分别按「订阅(subs)」和「一次性商品(inapp)」各查一次。
     *
     * @param productIds 要查询的商品 ID
     * @param callback   结果回调，保证且只会被调用一次
     */
    public void probe(final List<String> productIds, final Callback callback) {
        final List<String> ids = new ArrayList<>();
        if (productIds != null) {
            for (String id : productIds) {
                if (id == null) {
                    continue;
                }
                String trimmed = id.trim();
                if (!trimmed.isEmpty() && !ids.contains(trimmed)) {
                    ids.add(trimmed);
                }
            }
        }
        if (ids.isEmpty()) {
            callback.onResult(new HashMap<String, Object>());
            return;
        }

        // 参数与插件（BillingClientFactoryImpl）保持一致，避免因为构造方式不同
        // 而导致 Play 返回不同的结果。
        final BillingClient client =
                BillingClient.newBuilder(appContext)
                        .enablePendingPurchases(
                                PendingPurchasesParams.newBuilder()
                                        .enableOneTimeProducts()
                                        .build())
                        .setListener(
                                new PurchasesUpdatedListener() {
                                    @Override
                                    public void onPurchasesUpdated(
                                            BillingResult billingResult, List<Purchase> purchases) {
                                        // 探针只查询，不发起购买。
                                    }
                                })
                        .build();

        client.startConnection(
                new BillingClientStateListener() {
                    @Override
                    public void onBillingSetupFinished(BillingResult billingResult) {
                        if (billingResult.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                            Log.w(
                                    TAG,
                                    "billing setup failed: "
                                            + billingResult.getResponseCode()
                                            + " / "
                                            + billingResult.getDebugMessage());
                            Map<String, Object> data = new HashMap<>();
                            data.put("setupCode", billingResult.getResponseCode());
                            data.put("setupDebugMessage", billingResult.getDebugMessage());
                            data.put("countryCode", null);
                            data.put("queries", new ArrayList<Object>());
                            callback.onResult(data);
                            client.endConnection();
                            return;
                        }

                        // 结算国家（Play 账号所在国家），用于判断「区域不匹配」这类问题。
                        client.getBillingConfigAsync(
                                GetBillingConfigParams.newBuilder().build(),
                                new BillingConfigResponseListener() {
                                    @Override
                                    public void onBillingConfigResponse(
                                            BillingResult result, BillingConfig config) {
                                        String countryCode = null;
                                        if (result != null
                                                && result.getResponseCode()
                                                        == BillingClient.BillingResponseCode.OK
                                                && config != null) {
                                            countryCode = config.getCountryCode();
                                        }
                                        queryBothTypes(client, ids, countryCode, callback);
                                    }
                                });
                    }

                    @Override
                    public void onBillingServiceDisconnected() {
                        Map<String, Object> data = new HashMap<>();
                        data.put(
                                "setupCode",
                                BillingClient.BillingResponseCode.SERVICE_DISCONNECTED);
                        data.put("setupDebugMessage", "billing service disconnected");
                        data.put("countryCode", null);
                        data.put("queries", new ArrayList<Object>());
                        callback.onResult(data);
                    }
                });
    }

    /** 先查 subs 再查 inapp，两次都完成后回调一次。 */
    private void queryBothTypes(
            final BillingClient client,
            final List<String> ids,
            final String countryCode,
            final Callback callback) {
        final List<Object> queries = new ArrayList<>();

        queryType(
                client,
                BillingClient.ProductType.SUBS,
                ids,
                new TypeCallback() {
                    @Override
                    public void onType(Map<String, Object> query) {
                        queries.add(query);
                        queryType(
                                client,
                                BillingClient.ProductType.INAPP,
                                ids,
                                new TypeCallback() {
                                    @Override
                                    public void onType(Map<String, Object> query2) {
                                        queries.add(query2);
                                        Map<String, Object> data = new HashMap<>();
                                        data.put(
                                                "setupCode",
                                                BillingClient.BillingResponseCode.OK);
                                        data.put("setupDebugMessage", null);
                                        data.put("countryCode", countryCode);
                                        data.put("queries", queries);
                                        callback.onResult(data);
                                        client.endConnection();
                                    }
                                });
                    }
                });
    }

    private void queryType(
            final BillingClient client,
            final String type,
            final List<String> ids,
            final TypeCallback callback) {
        List<QueryProductDetailsParams.Product> products = new ArrayList<>();
        for (String id : ids) {
            products.add(
                    QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(id)
                            .setProductType(type)
                            .build());
        }

        QueryProductDetailsParams params =
                QueryProductDetailsParams.newBuilder().setProductList(products).build();

        try {
            client.queryProductDetailsAsync(
                    params,
                    new ProductDetailsResponseListener() {
                        @Override
                        public void onProductDetailsResponse(
                                BillingResult billingResult, QueryProductDetailsResult result) {
                            Map<String, Object> query = new HashMap<>();
                            query.put("type", type);
                            query.put("responseCode", billingResult.getResponseCode());
                            query.put("debugMessage", billingResult.getDebugMessage());

                            List<Object> found = new ArrayList<>();
                            if (result != null && result.getProductDetailsList() != null) {
                                for (ProductDetails details : result.getProductDetailsList()) {
                                    Map<String, Object> item = new HashMap<>();
                                    item.put("productId", details.getProductId());
                                    item.put("title", details.getTitle());
                                    item.put("productType", details.getProductType());
                                    found.add(item);
                                }
                            }

                            List<Object> unfetched = new ArrayList<>();
                            if (result != null && result.getUnfetchedProductList() != null) {
                                for (UnfetchedProduct product : result.getUnfetchedProductList()) {
                                    Map<String, Object> item = new HashMap<>();
                                    item.put("productId", product.getProductId());
                                    item.put("productType", product.getProductType());
                                    item.put("statusCode", product.getStatusCode());
                                    item.put("statusName", statusName(product.getStatusCode()));
                                    unfetched.add(item);
                                }
                            }

                            query.put("found", found);
                            query.put("unfetched", unfetched);
                            Log.d(
                                    TAG,
                                    "query type="
                                            + type
                                            + " code="
                                            + billingResult.getResponseCode()
                                            + " found="
                                            + found.size()
                                            + " unfetched="
                                            + unfetched.size());
                            callback.onType(query);
                        }
                    });
        } catch (RuntimeException e) {
            Log.w(TAG, "queryProductDetailsAsync threw for type " + type, e);
            Map<String, Object> query = new HashMap<>();
            query.put("type", type);
            query.put(
                    "responseCode",
                    BillingClient.BillingResponseCode.DEVELOPER_ERROR);
            query.put("debugMessage", String.valueOf(e.getMessage()));
            query.put("found", new ArrayList<Object>());
            query.put("unfetched", new ArrayList<Object>());
            callback.onType(query);
        }
    }

    /** 把 Play 的 statusCode 翻译成可读的名称。 */
    public static String statusName(int statusCode) {
        switch (statusCode) {
            case 0:
                return "UNKNOWN";
            case 2:
                return "INVALID_PRODUCT_ID_FORMAT";
            case 3:
                return "PRODUCT_NOT_FOUND";
            case 4:
                return "NO_ELIGIBLE_OFFER";
            default:
                return "CODE_" + statusCode;
        }
    }
}
