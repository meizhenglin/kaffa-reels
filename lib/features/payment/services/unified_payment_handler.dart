import 'package:flutter/material.dart';
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
import '../widgets/payment_channel_selector.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/service/pay_service.dart';
import '../../../app/providers/app_providers.dart';

/// Unified payment handler that orchestrates both Google Play and HaiPay flows
/// Provides a clean abstraction for all payment scenarios in the app
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

  /// Last error message
  String? lastError;

  /// Purchase a VIP subscription
  /// [product] - The subscription product to purchase
  /// [price] - Display price (e.g., "$24.99")
  /// Returns true if payment is successful
  Future<bool> purchaseVip({
    required SubscriptionProduct product,
    required String price,
    required BuildContext context,
  }) async {
    lastError = null;

    // Show channel selector
    final channel = await PaymentChannelSelector.show(
      context: context,
      price: price,
      productName: product.displayName ?? product.id,
    );

    if (channel == null) {
      lastError = 'Payment cancelled';
      return false;
    }

    switch (channel) {
      case PaymentChannel.googlePlay:
        return _purchaseVipViaGooglePlay(product: product, context: context);
      case PaymentChannel.haiPay:
        return _purchaseVipViaHaiPay(
          product: product,
          price: price,
          context: context,
        );
    }
  }

  /// Purchase coins (recharge)
  Future<bool> purchaseRecharge({
    required RechargeProduct product,
    required String price,
    required BuildContext context,
  }) async {
    lastError = null;

    final channel = await PaymentChannelSelector.show(
      context: context,
      price: price,
      productName: product.name,
    );

    if (channel == null) {
      lastError = 'Payment cancelled';
      return false;
    }

    switch (channel) {
      case PaymentChannel.googlePlay:
        return _purchaseRechargeViaGooglePlay(product: product, context: context);
      case PaymentChannel.haiPay:
        return _purchaseRechargeViaHaiPay(
          product: product,
          price: price,
          context: context,
        );
    }
  }

  /// Unlock an episode or drama
  Future<bool> unlockEpisode({
    required UnlockProduct product,
    required String price,
    required BuildContext context,
    String? videoId,
    String? episodeId,
    int? episodesNum,
  }) async {
    lastError = null;

    final channel = await PaymentChannelSelector.show(
      context: context,
      price: price,
      productName: product.goodsName,
    );

    if (channel == null) {
      lastError = 'Payment cancelled';
      return false;
    }

    switch (channel) {
      case PaymentChannel.googlePlay:
        return _unlockViaGooglePlay(product: product, context: context);
      case PaymentChannel.haiPay:
        return _unlockViaHaiPay(
          product: product,
          price: price,
          context: context,
          videoId: videoId,
          episodeId: episodeId,
          episodesNum: episodesNum,
        );
    }
  }

  // ==================== Google Play Flows ====================

  Future<bool> _purchaseVipViaGooglePlay({
    required SubscriptionProduct product,
    required BuildContext context,
  }) async {
    try {
      final productId = product.googlePlayId;

      final products = await _paymentService.getProducts(
        productIds: [productId],
        requireSubscriptionOnAndroid: true,
      );

      if (products.isEmpty) {
        lastError = 'Product not available in Google Play';
        return false;
      }

      final userId = _storage.getString('user_id');
      final success = await _paymentService.purchase(
        product: products.first,
        applicationUserName: userId,
      );

      return success;
    } catch (e) {
      lastError = 'Purchase failed: $e';
      return false;
    }
  }

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

      final success = await _paymentService.purchaseConsumable(
        product: products.first,
      );

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

      final products = await _paymentService.getProducts(
        productIds: [productId],
      );

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

  // ==================== HaiPay Flows ====================

  Future<bool> _purchaseVipViaHaiPay({
    required SubscriptionProduct product,
    required String price,
    required BuildContext context,
  }) async {
    try {
      // Step 1: Get payment methods from backend
      final methods = await _haiPayService.getPaymentMethods(
        currency: 'USD',
        price: price.replaceAll(RegExp(r'[^\d.]'), ''),
        productName: product.displayName ?? product.id,
      );

      if (methods.isEmpty) {
        lastError = 'No payment methods available';
        return false;
      }

      // Step 2: User selects a payment method
      final selectedMethod = await _showHaiPayMethodSelector(
        context: context,
        methods: methods,
        price: price,
      );

      if (selectedMethod == null) {
        lastError = 'Payment cancelled';
        return false;
      }

      // Step 3: Create order and get H5 payment URL
      final order = await _haiPayService.createVipOrder(
        payMethodId: selectedMethod.id,
        vipId: product.goodsId?.toString() ?? product.id,
        money: price.replaceAll(RegExp(r'[^\d.]'), ''),
        currency: 'USD',
      );

      if (order == null || order.payInfo.isEmpty) {
        lastError = 'Failed to create order';
        return false;
      }

      // Step 4: Open payment page
      final success = await _openPaymentPage(
        context: context,
        order: order,
        productType: '1', // VIP
        isExternal: selectedMethod.isExternalBrowser,
      );

      return success;
    } catch (e) {
      lastError = 'HaiPay purchase failed: $e';
      return false;
    }
  }

  Future<bool> _purchaseRechargeViaHaiPay({
    required RechargeProduct product,
    required String price,
    required BuildContext context,
  }) async {
    try {
      final methods = await _haiPayService.getPaymentMethods(
        currency: 'USD',
        price: price.replaceAll(RegExp(r'[^\d.]'), ''),
        productName: product.name,
      );

      if (methods.isEmpty) {
        lastError = 'No payment methods available';
        return false;
      }

      final selectedMethod = await _showHaiPayMethodSelector(
        context: context,
        methods: methods,
        price: price,
      );

      if (selectedMethod == null) {
        lastError = 'Payment cancelled';
        return false;
      }

      final order = await _haiPayService.createRechargeOrder(
        payMethodId: selectedMethod.id,
        goodsId: product.goodsId,
        amount: price.replaceAll(RegExp(r'[^\d.]'), ''),
        currency: 'USD',
      );

      if (order == null || order.payInfo.isEmpty) {
        lastError = 'Failed to create order';
        return false;
      }

      final success = await _openPaymentPage(
        context: context,
        order: order,
        productType: '2', // Recharge
        isExternal: selectedMethod.isExternalBrowser,
      );

      return success;
    } catch (e) {
      lastError = 'HaiPay purchase failed: $e';
      return false;
    }
  }

  Future<bool> _unlockViaHaiPay({
    required UnlockProduct product,
    required String price,
    required BuildContext context,
    String? videoId,
    String? episodeId,
    int? episodesNum,
  }) async {
    try {
      final methods = await _haiPayService.getPaymentMethods(
        currency: 'USD',
        price: price.replaceAll(RegExp(r'[^\d.]'), ''),
        productName: product.goodsName,
      );

      if (methods.isEmpty) {
        lastError = 'No payment methods available';
        return false;
      }

      final selectedMethod = await _showHaiPayMethodSelector(
        context: context,
        methods: methods,
        price: price,
      );

      if (selectedMethod == null) {
        lastError = 'Payment cancelled';
        return false;
      }

      final order = await _haiPayService.createEpisodeUnlockOrder(
        payMethodId: selectedMethod.id,
        videoId: videoId ?? '',
        episodeId: episodeId ?? '',
        episodesNum: episodesNum ?? 1,
        goodsId: product.goodsId,
        amount: price.replaceAll(RegExp(r'[^\d.]'), ''),
        currency: 'USD',
      );

      if (order == null || order.payInfo.isEmpty) {
        lastError = 'Failed to create order';
        return false;
      }

      final success = await _openPaymentPage(
        context: context,
        order: order,
        productType: '3', // Episode unlock
        isExternal: selectedMethod.isExternalBrowser,
      );

      return success;
    } catch (e) {
      lastError = 'HaiPay purchase failed: $e';
      return false;
    }
  }

  // ==================== Helper Methods ====================

  Future<HaiPayMethod?> _showHaiPayMethodSelector({
    required BuildContext context,
    required List<HaiPayMethod> methods,
    required String price,
  }) async {
    return showModalBottomSheet<HaiPayMethod>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HaiPayMethodSelector(
        methods: methods,
        price: price,
        onMethodSelected: (method) => Navigator.of(ctx).pop(method),
      ),
    );
  }

  Future<bool> _openPaymentPage({
    required BuildContext context,
    required HaiPayOrder order,
    required String productType,
    required bool isExternal,
  }) async {
    if (isExternal) {
      // Open in external browser
      final uri = Uri.parse(order.payInfo);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        lastError = 'Failed to open payment page';
        return false;
      }
      // Poll in background after returning
      return true;
    } else {
      // Open in WebView
      final success = await HaiPayWebViewPage.show(
        context: context,
        paymentUrl: order.payInfo,
        orderNo: order.orderNo,
        productType: productType,
      );
      return success == true;
    }
  }
}

/// Bottom sheet for selecting a HaiPay payment method
class _HaiPayMethodSelector extends StatelessWidget {
  const _HaiPayMethodSelector({
    required this.methods,
    required this.price,
    required this.onMethodSelected,
  });

  final List<HaiPayMethod> methods;
  final String price;
  final void Function(HaiPayMethod method) onMethodSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF2D2440),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select Payment Method',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    price,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: methods.map((method) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HaiPayMethodItem(
                      method: method,
                      onTap: () => onMethodSelected(method),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _HaiPayMethodItem extends StatelessWidget {
  const _HaiPayMethodItem({
    required this.method,
    required this.onTap,
  });

  final HaiPayMethod method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getMethodColor(method.name).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _getMethodIcon(method.name),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    method.isExternalBrowser ? 'Opens in browser' : 'Opens in app',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Color _getMethodColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('mada')) return const Color(0xFF00A651);
    if (lower.contains('stc') || lower.contains('stcpay')) return const Color(0xFFFFC107);
    if (lower.contains('credit') || lower.contains('card')) return const Color(0xFF4285F4);
    if (lower.contains('apple')) return Colors.black;
    return const Color(0xFF6C63FF);
  }

  String _getMethodIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('mada')) return '💳';
    if (lower.contains('stc') || lower.contains('stcpay')) return '📱';
    if (lower.contains('credit') || lower.contains('card')) return '💳';
    if (lower.contains('apple')) return '🍎';
    if (lower.contains('fawry')) return '🛒';
    return '💰';
  }
}

/// Provider for UnifiedPaymentHandler
final unifiedPaymentHandlerProvider = Provider<UnifiedPaymentHandler>((ref) {
  return UnifiedPaymentHandler(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
});
