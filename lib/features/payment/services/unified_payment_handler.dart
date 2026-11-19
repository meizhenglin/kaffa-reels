import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/payment_channel.dart';
import '../models/hai_pay_models.dart';
import '../models/unlock_product.dart';
import '../models/recharge_product.dart';
import '../models/subscription_product.dart';
import '../services/hai_pay_service.dart';
import '../services/payment_service.dart';
import '../pages/hai_pay_webview_page.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/service/pay_service.dart';
import '../../../app/providers/app_providers.dart';

/// Unified payment handler that orchestrates both Google Play and HaiPay flows.
///
/// HaiPay flow (two-step):
///   1. payType is the method id from getPayMethods
///   2. POST /api/pay/userRechange  -> merchantOrderNo
///   3. POST /api/pay/initPay        -> { payUrl, orderNo, merchantOrderNo }
///   4. Open H5 page in WebView
///   5. Poll /api/pay/getOrderIsPay on resume
class UnifiedPaymentHandler {
  UnifiedPaymentHandler({
    required DioClient dioClient,
    required StorageService storage,
  })  : _haiPayService = HaiPayService(
          dioClient: dioClient,
          storage: storage,
        ),
        _storage = storage;

  final HaiPayService _haiPayService;
  final StorageService _storage;
  final PaymentService _paymentService = PaymentService.instance;

  String? lastError;

  Future<List<HaiPayMethod>> fetchHaiPayMethods({
    required String price,
    required String productName,
    String currency = 'USD',
  }) {
    return _haiPayService.getPaymentMethods(
      currency: currency,
      price: price.replaceAll(RegExp(r'[^\\d.]'), ''),
      productName: productName,
    );
  }

  /// Purchase a VIP subscription.
  Future<bool> purchaseVip({
    required SubscriptionProduct product,
    required String price,
    required BuildContext context,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    lastError = null;

    if (channel.isGooglePlay) {
      // For Google Play, we need to pass the onPaymentComplete callback
      // but since _purchaseVipViaGooglePlay doesn't support it directly,
      // we handle it through the memberStateProvider in the UI layer
      return _purchaseVipViaGooglePlay(
        product: product,
        context: context,
        onPaymentComplete: onPaymentComplete,
      );
    }
    return _purchaseVipViaHaiPay(
      product: product,
      price: price,
      context: context,
      channel: channel,
      onPaymentComplete: onPaymentComplete,
    );
  }

  Future<bool> purchaseRecharge({
    required RechargeProduct product,
    required String price,
    required BuildContext context,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    lastError = null;

    if (channel.isGooglePlay) {
      return _purchaseRechargeViaGooglePlay(product: product, context: context);
    }
    return _purchaseRechargeViaHaiPay(
      product: product,
      price: price,
      context: context,
      channel: channel,
      onPaymentComplete: onPaymentComplete,
    );
  }

  Future<bool> unlockEpisode({
    required UnlockProduct product,
    required String price,
    required BuildContext context,
    String? videoId,
    String? episodeId,
    int? episodesNum,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    lastError = null;

    if (channel.isGooglePlay) {
      return _unlockViaGooglePlay(product: product, context: context);
    }
    return _unlockViaHaiPay(
      product: product,
      price: price,
      context: context,
      videoId: videoId,
      episodeId: episodeId,
      episodesNum: episodesNum,
      channel: channel,
      onPaymentComplete: onPaymentComplete,
    );
  }

  // ============== Google Play (unchanged) ==============

  Future<bool> _purchaseRechargeViaGooglePlay({
    required RechargeProduct product,
    required BuildContext context,
  }) async {
    try {
      final products = await _paymentService.getProducts(
        productIds: [product.googlePlayId],
      );
      if (products.isEmpty) {
        lastError = 'Product not available in Google Play';
        return false;
      }
      // 注意：这里只负责把购买流程跑完，**不会**给后端发 pay/callback/google。
      // Google Play 的 K币 充值请走 recharge_provider.dart 的
      // RechargePurchaseHandler —— 它负责建订单、发回调、刷新服务端余额。
      // 当前 UI 里的 Google Play 充值走的正是那条路径，这里只是兜底。
      final success =
          await _paymentService.purchaseConsumable(product: products.first);
      return success;
    } catch (e) {
      lastError = 'Purchase failed: $e';
      return false;
    }
  }

  Future<bool> _unlockViaGooglePlay({
    required UnlockProduct product,
    required BuildContext context,
  }) async {
    try {
      final productId = product.googlePlayId ?? '';
      if (productId.isEmpty) {
        lastError = 'Product not configured';
        return false;
      }
      final products = await _paymentService.getProducts(productIds: [productId]);
      if (products.isEmpty) {
        lastError = 'Product not available in Google Play';
        return false;
      }
      final success = await _paymentService.purchase(product: products.first);
      return success;
    } catch (e) {
      lastError = 'Purchase failed: $e';
      return false;
    }
  }

  Future<bool> _purchaseVipViaGooglePlay({
    required SubscriptionProduct product,
    required BuildContext context,
    void Function(bool success)? onPaymentComplete,
  }) async {
    try {
      final products = await _paymentService.getProducts(
        productIds: [product.googlePlayId],
        requireSubscriptionOnAndroid: true,
      );
      if (products.isEmpty) {
        lastError = 'Product not available in Google Play';
        return false;
      }
      final userId = await _storage.getUserIdAsync();
      final success = await _paymentService.purchase(
        product: products.first,
        applicationUserName: userId,
      );
      // Call the callback if provided
      onPaymentComplete?.call(success);
      return success;
    } catch (e) {
      lastError = 'Purchase failed: $e';
      onPaymentComplete?.call(false);
      return false;
    }
  }

  // ============== HaiPay new flow ==============

  /// Resolve HaiPay method: prefer the one selected upstream, otherwise fetch
  /// the first available (legacy behavior). Caller might choose to abort
  /// when channel.haiPayMethod is null — see callers.
  Future<HaiPayMethod?> _resolveHaiPayMethod({
    required PaymentChannel channel,
    required String price,
    required String productName,
  }) async {
    if (channel.haiPayMethod != null) return channel.haiPayMethod;
    final methods = await _haiPayService.getPaymentMethods(
      currency: 'USD',
      price: price.replaceAll(RegExp(r'[^\\d.]'), ''),
      productName: productName,
    );
    return methods.isEmpty ? null : methods.first;
  }

  /// PayConfig id (payConfigId) used in /api/pay/userRechange.
  /// Identifies VIP / recharge / unlock item — backend resolves the rest.
  int? _payConfigIdForVip(SubscriptionProduct product) => product.goodsId;
  int? _payConfigIdForRecharge(RechargeProduct product) => product.goodsId;
  int? _payConfigIdForUnlock(UnlockProduct product) => product.goodsId;

  /// Common two-step HaiPay flow shared by VIP / recharge / unlock.
  ///
  /// Returns true if the order was created AND the payment page was pushed
  /// onto the navigator. The onPaymentComplete callback (if provided) will be
  /// invoked when the user completes payment in the WebView.
  Future<bool> _runHaiPayFlow({
    required BuildContext context,
    required HaiPayMethod method,
    required int payConfigId,
    required String productType,
    String? videoId,
    void Function(bool success)? onPaymentComplete,
  }) async {
    try {
      final order = await _haiPayService.createAndInit(
        payType: method.id,
        payConfigId: payConfigId,
        videoId: videoId,
      );

      if (order == null || order.payInfo.isEmpty) {
        lastError = 'Failed to initialize payment';
        return false;
      }

      debugPrint(
          '[UnifiedPayment] _runHaiPayFlow order=${order.orderNo} payUrl=${order.payInfo} isExternal=${method.isExternalBrowser} mounted=${context.mounted} jumpType=${method.jumpType}');
      // ignore: avoid_print
      print('[UnifiedPayment] _runHaiPayFlow order=${order.orderNo} payUrl=${order.payInfo} isExternal=${method.isExternalBrowser} mounted=${context.mounted} jumpType=${method.jumpType}');

      if (method.isExternalBrowser) {
        // External URL: dispatch and return immediately.
        // The user pays in the external browser and we poll on resume.
        // The caller must NOT close the bottom sheet / pop, because the
        // WebView / external flow is responsible for its own lifecycle.
        return _openExternal(context: context, order: order);
      }

      // In-app WebView: push the page and return.
      // The WebView page handles its own Navigator.pop() on completion.
      // Caller must not pop the bottom sheet.
      return _openWebView(
        context: context,
        order: order,
        productType: productType,
        methodName: method.localizedName(Localizations.localeOf(context)),
        onPaymentComplete: onPaymentComplete,
      );
    } catch (e) {
      lastError = 'HaiPay purchase failed: $e';
      debugPrint('[UnifiedPaymentHandler] hai pay error: $e');
      return false;
    }
  }

  /// Open the payment URL in the system browser.
  /// Caller should NOT pop the calling sheet on success.
  Future<bool> _openExternal({
    required BuildContext context,
    required HaiPayOrder order,
  }) async {
    debugPrint(
        '[UnifiedPayment] _openExternal payInfo=${order.payInfo}');
    // ignore: avoid_print
    print('[UnifiedPayment] _openExternal payInfo=${order.payInfo}');
    try {
      final uri = Uri.parse(order.payInfo);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
        ),
      );
      if (!launched) {
        lastError = 'Failed to open payment page';
        return false;
      }
      return true;
    } catch (e) {
      lastError = 'Failed to launch payment URL: $e';
      debugPrint('[UnifiedPayment] launchUrl error: $e');
      return false;
    }
  }

  /// Push the in-app HaiPay WebView page.
  /// The WebView page is self-managing: it pops itself when the user
  /// completes (or cancels) the payment. Caller must NOT pop the calling
  /// sheet on success — only on failure (and only with an error toast).
  ///
  /// The onPaymentComplete callback will be invoked when payment is confirmed.
  Future<bool> _openWebView({
    required BuildContext context,
    required HaiPayOrder order,
    required String productType,
    required String methodName,
    void Function(bool success)? onPaymentComplete,
  }) async {
    debugPrint(
        '[UnifiedPayment] _openWebView payInfo=${order.payInfo} orderNo=${order.orderNo} methodName=$methodName');
    // ignore: avoid_print
    print('[UnifiedPayment] _openWebView payInfo=${order.payInfo} orderNo=${order.orderNo} methodName=$methodName');
    try {
      if (!context.mounted) {
        lastError = 'UI no longer available';
        return false;
      }
      // Push the WebView and await its result. The future resolves when the
      // WebView pops (after user completes or cancels payment).
      final result = await HaiPayWebViewPage.show(
        context: context,
        paymentUrl: order.payInfo,
        orderNo: order.orderNo,
        productType: productType,
        methodName: methodName,
        onPaymentComplete: onPaymentComplete,
      );
      // Return true if user completed payment (result == true)
      return result == true;
    } catch (e, st) {
      lastError = 'Failed to open webview: $e';
      debugPrint('[UnifiedPayment] show webview error: $e\n$st');
      return false;
    }
  }

  // Kept for backwards compatibility. The new flow prefers _openExternal /
  Future<bool> _purchaseVipViaHaiPay({
    required SubscriptionProduct product,
    required String price,
    required BuildContext context,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    final selectedMethod = await _resolveHaiPayMethod(
      channel: channel,
      price: price,
      productName: product.displayName ?? product.id,
    );
    // ignore: avoid_print
    print('[UnifiedPayment] _purchaseVipViaHaiPay method=$selectedMethod product=${product.id} goodsId=${product.goodsId}');
    if (selectedMethod == null) {
      lastError = 'No payment methods available';
      print('[UnifiedPayment] _purchaseVipViaHaiPay ABORT: selectedMethod=null');
      return false;
    }

    final payConfigId = _payConfigIdForVip(product);
    if (payConfigId == null || payConfigId == 0) {
      lastError = 'Invalid VIP product';
      print('[UnifiedPayment] _purchaseVipViaHaiPay ABORT: payConfigId=$payConfigId');
      return false;
    }

    return _runHaiPayFlow(
      context: context,
      method: selectedMethod,
      payConfigId: payConfigId,
      productType: '1',
      onPaymentComplete: onPaymentComplete,
    );
  }

  Future<bool> _purchaseRechargeViaHaiPay({
    required RechargeProduct product,
    required String price,
    required BuildContext context,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    final selectedMethod = await _resolveHaiPayMethod(
      channel: channel,
      price: price,
      productName: product.name,
    );
    // ignore: avoid_print
    print('[UnifiedPayment] _purchaseRechargeViaHaiPay method=$selectedMethod goodsId=${product.goodsId}');
    if (selectedMethod == null) {
      lastError = 'No payment methods available';
      print('[UnifiedPayment] _purchaseRechargeViaHaiPay ABORT: selectedMethod=null');
      return false;
    }

    final payConfigId = _payConfigIdForRecharge(product);
    if (payConfigId == null || payConfigId == 0) {
      lastError = 'Invalid recharge product';
      print('[UnifiedPayment] _purchaseRechargeViaHaiPay ABORT: payConfigId=$payConfigId');
      return false;
    }

    return _runHaiPayFlow(
      context: context,
      method: selectedMethod,
      payConfigId: payConfigId,
      productType: '2',
      onPaymentComplete: onPaymentComplete,
    );
  }

  Future<bool> _unlockViaHaiPay({
    required UnlockProduct product,
    required String price,
    required BuildContext context,
    String? videoId,
    String? episodeId,
    int? episodesNum,
    required PaymentChannel channel,
    void Function(bool success)? onPaymentComplete,
  }) async {
    final selectedMethod = await _resolveHaiPayMethod(
      channel: channel,
      price: price,
      productName: product.goodsName,
    );
    // ignore: avoid_print
    print('[UnifiedPayment] _unlockViaHaiPay method=$selectedMethod product=${product.goodsName} goodsId=${product.goodsId}');
    if (selectedMethod == null) {
      lastError = 'No payment methods available';
      print('[UnifiedPayment] _unlockViaHaiPay ABORT: selectedMethod=null');
      return false;
    }

    final payConfigId = _payConfigIdForUnlock(product);
    if (payConfigId == null || payConfigId == 0) {
      lastError = 'Invalid unlock product';
      print('[UnifiedPayment] _unlockViaHaiPay ABORT: payConfigId=$payConfigId');
      return false;
    }

    return _runHaiPayFlow(
      context: context,
      method: selectedMethod,
      payConfigId: payConfigId,
      productType: '3',
      // 【整剧/单集解锁】订单里必须带 videoId，后端收到 HiPay 回调时
      // 按订单的 videoId 决定解锁哪部剧。之前这里把它丢了，
      // 导致 HaiPay 支付的解锁订单 videoId=null，和谷歌端同一个坑。
      videoId: videoId,
      onPaymentComplete: onPaymentComplete,
    );
  }
}

/// Provider for UnifiedPaymentHandler
final unifiedPaymentHandlerProvider = Provider<UnifiedPaymentHandler>((ref) {
  return UnifiedPaymentHandler(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
});
