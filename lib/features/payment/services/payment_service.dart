import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Payment service for handling in-app purchases
/// Uses in_app_purchase package for cross-platform support
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  bool _isInitialized = false;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Function(PurchaseDetails)? _onPurchaseComplete;
  Function(String)? _onPurchaseError;

  // Cached products
  List<ProductDetails> _availableProducts = [];

  /// Initialize the payment service
  Future<bool> initialize({
    Function(PurchaseDetails)? onPurchaseComplete,
    Function(String)? onPurchaseError,
  }) async {
    _onPurchaseComplete = onPurchaseComplete;
    _onPurchaseError = onPurchaseError;

    if (_isInitialized) return true;

    try {
      final isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        debugPrint('In-app purchases not available');
        _onPurchaseError?.call('Google Play billing is not available on this device.');
        return false;
      }

      // Listen to purchase updates
      _subscription ??= _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (error) {
          debugPrint('Purchase stream error: $error');
          _onPurchaseError?.call('Purchase stream error: $error');
        },
      );

      _isInitialized = true;
      debugPrint('PaymentService initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to initialize payment service: $e');
      _onPurchaseError?.call('Failed to initialize billing: $e');
      return false;
    }
  }

  /// Get available subscription products
  Future<List<ProductDetails>> getProducts({
    required List<String> productIds,
    bool requireSubscriptionOnAndroid = false,
  }) async {
    // Sanitize product IDs: trim whitespace, remove invisible chars
    final sanitizedIds = productIds.map((id) {
      final cleaned = id.replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E\s]'), '');
      final trimmed = cleaned.trim();
      if (trimmed != id) {
        debugPrint('IAP product ID sanitized: "$id" -> "$trimmed"');
      }
      return trimmed;
    }).toList();

    debugPrint(
      'IAP querying ${sanitizedIds.length} product IDs: $sanitizedIds',
    );

    try {
      debugPrint('IAP queryProductDetails: about to call store API...');
      final response = await _inAppPurchase.queryProductDetails(
        sanitizedIds.toSet(),
      );
      debugPrint('IAP queryProductDetails: store API returned');

      debugPrint('IAP queryProductDetails response:');
      debugPrint('  - error: ${response.error}');
      debugPrint('  - notFoundIDs count: ${response.notFoundIDs.length}');
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('  - notFoundIDs: ${response.notFoundIDs.join(', ')}');
      }
      debugPrint('  - productDetails count: ${response.productDetails.length}');

      if (response.error != null) {
        debugPrint('Error fetching products: ${response.error}');
        _onPurchaseError?.call(response.error!.message);
        return [];
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found: ${response.notFoundIDs.join(', ')}');
      }

      _availableProducts = response.productDetails;
      for (final product in _availableProducts) {
        final googlePlayType = product is GooglePlayProductDetails
            ? product.productDetails.productType
            : 'unknown';
        debugPrint(
          'IAP product loaded: id="${product.id}", title="${product.title}", '
          'price="${product.price}", type=$googlePlayType',
        );
      }

      if (requireSubscriptionOnAndroid && defaultTargetPlatform == TargetPlatform.android) {
        final invalidProducts = _availableProducts.where((product) {
          return product is! GooglePlayProductDetails ||
              product.productDetails.productType.toString() != 'ProductType.subs';
        }).toList();

        if (invalidProducts.isNotEmpty) {
          final invalidSummary = invalidProducts.map((product) {
            final type = product is GooglePlayProductDetails
                ? product.productDetails.productType
                : 'unknown';
            return '${product.id}($type)';
          }).join(', ');
          final message =
              'Google Play products must be subscriptions (subs), but got: $invalidSummary';
          debugPrint(message);
          _onPurchaseError?.call(message);
          return [];
        }
      }

      return _availableProducts;
    } catch (e) {
      debugPrint('Exception fetching products: $e');
      debugPrint('Stack trace: $e');
      _onPurchaseError?.call('Failed to fetch products: $e');
      return [];
    }
  }

  /// Check if user has active subscriptions
  Future<List<PurchaseDetails>> getPurchases() async {
    await restorePurchases();
    return [];
  }

  /// Initiate a subscription purchase flow (non-consumable)
  Future<bool> purchase({
    required ProductDetails product,
    String? applicationUserName,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        debugPrint('PaymentService not initialized');
        return false;
      }
    }

    try {
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );

      final googlePlayType = product is GooglePlayProductDetails
          ? product.productDetails.productType
          : 'unknown';
      debugPrint(
        'Starting purchase: id=${product.id}, type=$googlePlayType',
      );

      final success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        _onPurchaseError?.call('Failed to open Google Play purchase sheet.');
      }
      return success;
    } catch (e) {
      debugPrint('Purchase error: $e');
      _onPurchaseError?.call('Purchase failed: $e');
      return false;
    }
  }

  /// Initiate a consumable purchase flow (coins/recharges)
  /// Consumables need to be consumed after purchase to allow repurchase
  Future<bool> purchaseConsumable({
    required ProductDetails product,
    String? applicationUserName,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        debugPrint('PaymentService not initialized');
        return false;
      }
    }

    try {
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );

      debugPrint(
        'Starting consumable purchase: id=${product.id}',
      );

      final success = await _inAppPurchase.buyConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        _onPurchaseError?.call('Failed to open Google Play purchase sheet.');
      }
      return success;
    } catch (e) {
      debugPrint('Consumable purchase error: $e');
      _onPurchaseError?.call('Purchase failed: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        debugPrint('PaymentService not initialized');
        return false;
      }
    }

    try {
      await _inAppPurchase.restorePurchases(
        applicationUserName: null,
      );
      return true;
    } catch (e) {
      debugPrint('Restore purchases error: $e');
      _onPurchaseError?.call('Restore failed: $e');
      return false;
    }
  }

  /// Handle purchase update from the stream
  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchase in purchaseDetailsList) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // 方案A: 先 Acknowledge，等完成后再调 API 回调
          if (purchase.pendingCompletePurchase) {
            try {
              debugPrint('Acknowledging purchase before API callback: ${purchase.purchaseID}');
              await _inAppPurchase.completePurchase(purchase);
              debugPrint('Purchase acknowledged: ${purchase.purchaseID}');
            } catch (e) {
              debugPrint('Failed to acknowledge purchase: $e');
            }
          }
          _onPurchaseComplete?.call(purchase);
          break;
        case PurchaseStatus.pending:
          debugPrint('Purchase pending: ${purchase.purchaseID}');
          break;
        case PurchaseStatus.canceled:
          debugPrint('Purchase canceled: ${purchase.purchaseID}');
          _onPurchaseError?.call('Purchase was canceled');
          break;
        case PurchaseStatus.error:
          debugPrint('Purchase error: ${purchase.error}');
          _onPurchaseError?.call(purchase.error?.message ?? 'Unknown error');
          break;
      }
    }
  }

  /// Consume a purchase (for consumables like coins)
  /// This must be called after successful purchase to allow repurchasing
  Future<bool> consumePurchase(PurchaseDetails purchase) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      debugPrint('Consume only supported on Android');
      return false;
    }

    try {
      final androidAddition = _inAppPurchase.getPlatformAddition<
          InAppPurchaseAndroidPlatformAddition>();
      await androidAddition.consumePurchase(purchase);
      debugPrint('Purchase consumed: ${purchase.purchaseID}');
      return true;
    } catch (e) {
      debugPrint('Failed to consume purchase: $e');
      return false;
    }
  }

  /// Handle consumable purchase: consume then notify callback
  /// For consumables (payConfigType=1), consume after successful purchase
  Future<bool> handleConsumablePurchase(PurchaseDetails purchase) async {
    try {
      // Consume the purchase to allow future purchases
      final consumed = await consumePurchase(purchase);
      if (!consumed) {
        debugPrint('Failed to consume purchase: ${purchase.purchaseID}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error handling consumable purchase: $e');
      return false;
    }
  }

  /// Get the current platform type
  TargetPlatform get currentPlatform {
    if (kIsWeb) return defaultTargetPlatform;
    return defaultTargetPlatform;
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}

/// Local storage helper for caching purchase state
class PurchaseCache {
  static const _keyIsVip = 'is_vip';
  static const _keyVipExpireDate = 'vip_expire_date';
  static const _keySubscriptionType = 'subscription_type';

  final SharedPreferences _prefs;

  PurchaseCache(this._prefs);

  bool get isVip => _prefs.getBool(_keyIsVip) ?? false;
  DateTime? get vipExpireDate {
    final str = _prefs.getString(_keyVipExpireDate);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }
  String? get subscriptionType => _prefs.getString(_keySubscriptionType);

  Future<void> setVipStatus({
    required bool isVip,
    DateTime? expireDate,
    String? type,
  }) async {
    await _prefs.setBool(_keyIsVip, isVip);
    if (expireDate != null) {
      await _prefs.setString(_keyVipExpireDate, expireDate.toIso8601String());
    }
    if (type != null) {
      await _prefs.setString(_keySubscriptionType, type);
    }
  }

  Future<void> clearVipStatus() async {
    await _prefs.remove(_keyIsVip);
    await _prefs.remove(_keyVipExpireDate);
    await _prefs.remove(_keySubscriptionType);
  }
}
