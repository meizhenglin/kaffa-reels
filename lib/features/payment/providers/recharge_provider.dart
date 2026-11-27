import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/recharge_product.dart';
import '../models/subscription_product.dart';
import '../services/payment_service.dart';
import '../services/receipt_verification.dart';
// 带前缀导入：本文件自己也定义了 CoinBalanceNotifier（本地余额那份），
// 不加前缀会和这里的 CoinBalanceNotifier 撞名。
import 'coin_record_provider.dart' as coin_record;

export '../models/recharge_product.dart'
    show RechargeProduct, RechargeProductsState, CoinBalanceState;
export '../models/subscription_product.dart' show RechargeGoodsConfigItem;

/// Recharge purchase handler for consumables
class RechargePurchaseHandler {
  RechargePurchaseHandler(this._ref);

  final Ref _ref;

  /// Last error message from purchase attempt
  String? lastError;

  /// Pending recharge product (set before purchase, cleared after)
  RechargeProduct? pendingProduct;

  /// Pending backend order id (the callback needs it to credit the coins)
  String? pendingOrderId;

  /// Purchase a recharge product
  Future<bool> purchase(RechargeProduct product) async {
    lastError = null;
    pendingProduct = product;
    pendingOrderId = null;

    final paymentService = PaymentService.instance;

    // Step 1: 先查商店商品。商品都查不到就别建订单了，
    // 否则会留下一笔永远不会被支付的订单。
    // 【按平台取商品 ID】iOS 取 iosProductId（后台没配则兜底 Google ID，
    // 两边商店用的是同一套 ID），Android 取 googlePlayId。
    final platformProductId = product.getProductId(defaultTargetPlatform);
    final products = await paymentService.getProducts(
      productIds: [platformProductId],
    );

    if (products.isEmpty) {
      // 同会员链路：用商店返回的真实原因，不要笼统地让用户去查网络。
      // 【按平台取失败码】之前固定取 Play 的失败码，iOS 上 Play 码永远是
      // null → 落到 'play-item-not-found' → 页面弹「Google Play 不可用」，
      // 真实的 StoreKit 失败原因（商品没批准 / ID 不匹配）全被掩盖了。
      lastError = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? (paymentService.lastIosFailureCode ?? 'ios-item-not-found')
          : (paymentService.lastPlayFailureCode ?? 'play-item-not-found');
      pendingProduct = null;
      return false;
    }

    // Step 2: 建订单。后端回调要靠 orderId 才能把这笔支付对到账上，
    // 少了它服务端认不出这笔 K币 充值。
    final String orderId;
    try {
      final order = await payServiceProvider.createOrder(
        payConfigId: product.goodsId,
      );
      final id = order?.orderId;
      if (id == null || id.isEmpty) {
        lastError = 'Failed to create order';
        pendingProduct = null;
        return false;
      }
      orderId = id;
    } catch (e) {
      debugPrint('[Recharge] createOrder failed: $e');
      lastError = 'Failed to create order';
      pendingProduct = null;
      return false;
    }
    pendingOrderId = orderId;

    // Step 3: 发起一次性商品购买。
    // 插件会在把 purchase 投递给 stream 之前自动 consume 掉这个商品，
    // 所以用户可以反复买同一个币包。
    final success = await paymentService.purchaseConsumable(
      product: products.first,
      applicationUserName: await _ref.read(storageServiceProvider).getUserIdAsync(),
      onComplete: (purchase) => _handlePurchaseSuccess(purchase, orderId),
    );

    if (!success) {
      lastError =
          paymentService.lastError ??
          'Google Play purchase failed. Please try again.';
      pendingProduct = null;
      pendingOrderId = null;
    }

    return success;
  }

  /// Handle successful consumable purchase: tell the backend, then refresh
  /// the server-side balance.
  ///
  /// 【为什么必须在客户端回调后端】
  /// K币 是账号内的虚拟币，只有服务端记账才算数。
  /// 这条回调以前压根没被调用过（handlePurchaseSuccess 是死代码），
  /// 结果是钱付了、后端没收到通知、币也不会到账。
  Future<bool> _handlePurchaseSuccess(
    PurchaseDetails purchase,
    String orderId,
  ) async {
    final product = pendingProduct;
    pendingProduct = null;
    pendingOrderId = null;
    if (product == null) return false;

    // 参数结构和会员订阅那条链路保持一致（后端是同一个回调接口
    // `/notice/google`），额外带上 payConfigType=1 表示这是 K币 充值
    // 而不是开通会员。
    final callbackPayload = <String, dynamic>{
      // 后端订单字段名是 orderNo（/api/pay/userRechange 返回 orderNo），
      // 两个都带上，兼容后端两种读法。
      'orderNo': orderId,
      'orderId': orderId,
      'productId': purchase.productID,
      'purchaseId': purchase.purchaseID,
      'transactionDate': purchase.transactionDate,
      'status': purchase.status.name,
      'payConfigType': 1, // 1 = K币充值（一次性消耗）
      'goodsId': product.goodsId,
      'purchaseToken': purchase.verificationData.serverVerificationData,
      'verificationData': {
        'localVerificationData':
            purchase.verificationData.localVerificationData,
        'serverVerificationData':
            purchase.verificationData.serverVerificationData,
        'source': purchase.verificationData.source,
      },
    };

    // 【iOS 必须带 receipt】/notice/apple 的后端约定（见 api_service.appleCallBack
    // 的注释）：App Store 收据（Base64）要同时放在 receipt 字段里。
    // iOS 上 serverVerificationData 就是收据，补一个 receipt 键；
    // Android 多一个字段无副作用，统一加省去平台判断。
    callbackPayload['receipt'] = purchase.verificationData.localVerificationData;

    // 【先存后发】发送前先把回调参数落盘（同 orderId 去重），成功后再出队。
    // 和会员链路（membership_provider Step 4）同一套事务模式：
    // App 在发送过程中被杀/断网，下次启动或进入会员页时
    // checkAndRetryPendingPayments 看到这条记录（含 purchaseToken）
    // 会自动补发 /notice/google。
    final storage = _ref.read(storageServiceProvider);
    await storage.savePendingPayment(callbackPayload);

    // 最多重试 3 次，指数退避（和会员链路一致，避免弱网丢单）。
    var confirmed = false;
    var retryCount = 0;
    const maxRetries = 3;
    while (retryCount < maxRetries && !confirmed) {
      if (retryCount > 0) {
        final delay = Duration(seconds: (2 << (retryCount - 1)));
        await Future.delayed(delay);
      }
      try {
        // 【按平台路由回调】iOS → /notice/apple，Android → /notice/google。
        // 之前 iOS 的购买结果也被丢进 Google 回调，后端永远收不到。
        confirmed = await payServiceProvider.confirmStorePurchase(
          params: callbackPayload,
        );
      } catch (e) {
        debugPrint(
          '[Recharge] store callback failed (attempt ${retryCount + 1}): $e',
        );
      }
      retryCount++;
    }

    if (confirmed) {
      // 后端已确认，出队。
      await storage.removePendingPayment(orderId);
    }

    debugPrint(
      '[Recharge] Google callback confirmed=$confirmed for ${purchase.productID}',
    );

    // 余额以服务端为准。这里**不能**在本地加币 ——
    // 之前那段本地 addCoins 会和服务端记账重复，
    // 而且本地余额存在 SharedPreferences 里，清缓存就没了。
    final baselineBalance = _ref.read(coin_record.coinBalanceInfoProvider).balance;
    await _refreshServerBalance();

    // 【轮询刷新】confirm 返回成功 ≠ 后端账务已落库：实测 confirm 成功后
    // 立刻拉 userPersonalCenter 拿到的还是旧余额（购买完返回个人中心
    // 显示旧值，切 tab 之后才更新——切 tab 是 15 秒节流过期后重新拉才
    // 拿到新值，说明落库延迟 > 2 秒）。固定重试一次不够，改成轮询：
    // 每 2 秒强制刷一次，最多 6 次 / 12 秒，余额一变（到账）就提前收兵。
    // 个人中心 watch 余额 provider，数据落了 UI 自动更新，不用切 tab。
    if (confirmed) {
      final current = _ref.read(coin_record.coinBalanceInfoProvider).balance;
      // 第一次刷新就已经拿到新余额则无需轮询；否则轮询等后端落库。
      if (current == baselineBalance) {
        unawaited(_pollBalanceUntilCredited(baselineBalance));
      }
    }

    return confirmed;
  }

  /// confirm 成功后轮询余额直到后端落库（余额变化）或超次放弃。
  Future<void> _pollBalanceUntilCredited(int baselineBalance) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refreshServerBalance();
      final current = _ref
          .read(coin_record.coinBalanceInfoProvider)
          .balance;
      if (current != baselineBalance) {
        debugPrint(
          '[Recharge] balance credited after polling '
          '(attempt ${attempt + 1}): $baselineBalance -> $current',
        );
        return;
      }
    }
    debugPrint('[Recharge] balance polling exhausted, backend may still be pending');
  }

  /// 刷新服务端余额
  Future<void> _refreshServerBalance() async {
    try {
      await _ref
          .read(coin_record.coinBalanceInfoProvider.notifier)
          .load(force: true);
    } catch (e) {
      debugPrint('[Recharge] refresh balance failed: $e');
    }
  }

  /// Clear pending product (on cancel/error)
  void clearPending() {
    pendingProduct = null;
    pendingOrderId = null;
  }
}

/// Provider for recharge purchase handler
final rechargePurchaseHandlerProvider = Provider<RechargePurchaseHandler>((
  ref,
) {
  return RechargePurchaseHandler(ref);
});

/// Coin balance provider
final coinBalanceProvider =
    StateNotifierProvider<CoinBalanceNotifier, CoinBalanceState>((ref) {
      return CoinBalanceNotifier(ref.read(storageServiceProvider));
    });

class CoinBalanceNotifier extends StateNotifier<CoinBalanceState> {
  CoinBalanceNotifier(this._storage) : super(const CoinBalanceState()) {
    _loadBalance();
  }

  final StorageService _storage;
  static const String _balanceKey = 'coin_balance';

  Future<void> _loadBalance() async {
    final balance = _storage.getInt(_balanceKey);
    state = state.copyWith(balance: balance);
  }

  Future<void> setBalance(int balance) async {
    await _storage.setInt(_balanceKey, balance);
    state = state.copyWith(balance: balance);
  }

  Future<void> addCoins(int amount) async {
    final newBalance = state.balance + amount;
    await setBalance(newBalance);
  }

  Future<void> deductCoins(int amount) async {
    final newBalance = (state.balance - amount).clamp(0, state.balance);
    await setBalance(newBalance);
  }
}

/// Recharge products provider
final rechargeProductsProvider =
    StateNotifierProvider<RechargeProductsNotifier, RechargeProductsState>((
      ref,
    ) {
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );
      return RechargeProductsNotifier(apiService);
    });

class RechargeProductsNotifier extends StateNotifier<RechargeProductsState> {
  RechargeProductsNotifier(this._apiService)
    : super(const RechargeProductsState());

  final ApiService _apiService;

  /// Load recharge products from backend
  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.request(
        'api/rechargeGoodsConfig/list',
        method: 'POST',
        data: {'rechargeGoodsType': 1}, // 1 = K币充值（与会员页共用同一接口，0 = VIP 会员）
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data;
        List<RechargeGoodsConfigItem> items = [];

        if (data is List) {
          items = data.map((e) => RechargeGoodsConfigItem.fromJson(e)).toList();
        } else if (data is Map && data['list'] is List) {
          items = (data['list'] as List)
              .map((e) => RechargeGoodsConfigItem.fromJson(e))
              .toList();
        }

        // 【过滤条件按平台取 ID，并互相兜底】
        // 之前只认 goodsGoogleId 非空 —— 后台如果只配了 iOS 商品 ID，
        // iOS 端会整页空白。两边商店用同一套产品 ID，缺一边时用另一边兜底。
        final products = items
            .where(
              (item) =>
                  item.isEnable &&
                  (item.goodsGoogleId.isNotEmpty || item.goodsIosId.isNotEmpty),
            )
            .map((item) => RechargeProduct.fromGoodsConfig(item))
            .toList()
          ..sort((a, b) => a.sort.compareTo(b.sort));

        state = state.copyWith(
          products: products,
          isLoading: false,
          hasLoaded: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: response.error ?? 'Failed to load recharge products',
          hasLoaded: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading products',
        hasLoaded: true,
      );
    }
  }

  /// Get platform-specific product IDs
  List<String> getProductIds() {
    return state.products.map((p) => p.googlePlayId).toList();
  }

  /// Find product by Google Play ID
  RechargeProduct? findByProductId(String productId) {
    try {
      return state.products.firstWhere((p) => p.googlePlayId == productId);
    } catch (_) {
      return null;
    }
  }
}
