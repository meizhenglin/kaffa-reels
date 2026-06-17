import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show ProductType, ReplacementMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Local storage helper for caching purchase state
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

  // Cached purchases for quick lookup
  List<PurchaseDetails> _cachedPurchases = [];
  DateTime? _lastPurchaseQueryTime;

  static const Duration _purchaseQueryCacheTtl = Duration(seconds: 30);

  Completer<bool>? _pendingPurchaseCompleter;
  String? _pendingPurchaseProductId;

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
        _onPurchaseError?.call('Google Play billing is not available on this device.');
        return false;
      }

      // Listen to purchase updates
      _subscription ??= _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (error) {
          _onPurchaseError?.call('Purchase stream error: $error');
        },
      );

      _isInitialized = true;
      return true;
    } catch (e) {
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
      return cleaned.trim();
    }).toList();

    try {
      final response = await _inAppPurchase.queryProductDetails(
        sanitizedIds.toSet(),
      );

      if (response.error != null) {
        _onPurchaseError?.call(response.error!.message);
        return [];
      }

      _availableProducts = response.productDetails;

      if (requireSubscriptionOnAndroid && defaultTargetPlatform == TargetPlatform.android) {
        final invalidProducts = _availableProducts.where((product) {
          if (product is! GooglePlayProductDetails) {
            return true;
          }

          final productType = product.productDetails.productType;
          return productType != ProductType.subs;
        }).toList();

        if (invalidProducts.isEmpty) {
          return _availableProducts;
        }

        final subscriptionProducts = _availableProducts.where((product) {
          if (product is! GooglePlayProductDetails) {
            return false;
          }

          final productType = product.productDetails.productType;
          return productType == ProductType.subs;
        }).toList();

        if (subscriptionProducts.isNotEmpty) {
          _availableProducts = subscriptionProducts;
          return _availableProducts;
        }

        final invalidSummary = invalidProducts.map((product) {
          final type = product is GooglePlayProductDetails
              ? product.productDetails.productType
              : 'unknown';
          return '${product.id}($type)';
        }).join(', ');
        final message =
            'Google Play products must be subscriptions (subs), but got: $invalidSummary';
        _onPurchaseError?.call(message);
        return [];
      }

      return _availableProducts;
    } catch (e) {
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
    /// Existing purchase to upgrade/downgrade from
    PurchaseDetails? oldPurchaseDetails,
    /// Replacement mode for subscription changes (Android only)
    ReplacementMode replacementMode = ReplacementMode.withTimeProration,
    /// Whether to query for existing purchases for upgrade/downgrade
    /// Set to false when user is buying the same product (e.g., retry after cancel)
    bool checkForExistingPurchases = true,
    /// Force a fresh Google Play query instead of using cached purchases.
    bool forceRefreshCache = false,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        return false;
      }
    }

    try {
      final isAndroid = defaultTargetPlatform == TargetPlatform.android;

      debugPrint(
        '[PaymentService] purchase() called, _pastPurchases count: ${_pastPurchases.length}, '
        'checkForExisting=$checkForExistingPurchases, forceRefresh=$forceRefreshCache',
      );

      PurchaseDetails? cachedOldPurchase = oldPurchaseDetails;

      if (isAndroid && cachedOldPurchase == null && checkForExistingPurchases) {
        debugPrint('[PaymentService] Checking for existing purchases...');

        if (forceRefreshCache) {
          debugPrint('[PaymentService] Force refreshing purchase cache');
          clearCachedPurchases();
        }

        final candidates = <PurchaseDetails>[];

        if (_pastPurchases.isNotEmpty && !forceRefreshCache) {
          debugPrint('[PaymentService] Found ${_pastPurchases.length} cached purchases');
          candidates.addAll(
            _pastPurchases.where((purchase) {
              final active = purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored;
              debugPrint(
                '[PaymentService] Cached purchase: ${purchase.productID}, status: ${purchase.status}, active=$active',
              );
              return active && purchase.productID != product.id;
            }),
          );
        }

        if (candidates.isEmpty) {
          debugPrint('[PaymentService] No cached purchases found, querying...');
          try {
            final androidAddition = _inAppPurchase.getPlatformAddition<
                InAppPurchaseAndroidPlatformAddition>();
            final response = await androidAddition.queryPastPurchases(
              applicationUserName: _resolveUserId(),
            );
            debugPrint(
              '[PaymentService] queryPastPurchases returned ${response.pastPurchases.length} purchases',
            );
            for (final p in response.pastPurchases) {
              cachePastPurchase(p);
              debugPrint(
                '[PaymentService] Past purchase: ${p.productID}, status: ${p.status}',
              );
              final active = p.status == PurchaseStatus.purchased ||
                  p.status == PurchaseStatus.restored;
              if (active && p.productID != product.id) {
                candidates.add(p);
              }
            }
          } catch (e) {
            debugPrint('[PaymentService] queryPastPurchases error: $e');
            clearCachedPurchases();
            _onPurchaseError?.call('Purchase failed: unable to load purchase history');
            return false;
          }
        }

        if (candidates.isNotEmpty) {
          cachedOldPurchase = _pickBestOldPurchase(candidates);
          debugPrint(
            '[PaymentService] Selected for upgrade: ${cachedOldPurchase!.productID}',
          );
        }
      } else if (!checkForExistingPurchases) {
        debugPrint('[PaymentService] Skipping existing purchase check for fresh buy');
      }

      if (isAndroid && cachedOldPurchase != null) {
        if (cachedOldPurchase.productID == product.id) {
          debugPrint(
            '[PaymentService] Ignoring same-product old purchase to avoid ITEM_ALREADY_OWNED',
          );
          cachedOldPurchase = null;
        }
      }

      final completer = Completer<bool>();
      _pendingPurchaseCompleter = completer;
      _pendingPurchaseProductId = product.id;

      Future<void> finalizePendingPurchase() async {
        if (_pendingPurchaseCompleter != completer) {
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        _pendingPurchaseCompleter = null;
        _pendingPurchaseProductId = null;
      }

      if (isAndroid && cachedOldPurchase != null) {
        final googlePlayDetails = product as GooglePlayProductDetails;
        final oldGooglePurchase = cachedOldPurchase as GooglePlayPurchaseDetails;

        ReplacementMode effectiveReplacementMode = replacementMode;
        if (_isDowngrade(googlePlayDetails, oldGooglePurchase)) {
          effectiveReplacementMode = ReplacementMode.deferred;
          debugPrint(
            '[PaymentService] Downgrade detected from ${oldGooglePurchase.productID} '
            'to ${googlePlayDetails.id}, using deferred replacement',
          );
        } else {
          debugPrint(
            '[PaymentService] Upgrade detected from ${oldGooglePurchase.productID} '
            'to ${googlePlayDetails.id}',
          );
        }

        final changeSubscriptionParam = ChangeSubscriptionParam(
          oldPurchaseDetails: oldGooglePurchase,
          replacementMode: effectiveReplacementMode,
        );

        final purchaseParam = GooglePlayPurchaseParam(
          productDetails: googlePlayDetails,
          applicationUserName: applicationUserName,
          changeSubscriptionParam: changeSubscriptionParam,
        );

        debugPrint(
          '[PaymentService] Launching subscription change from ${oldGooglePurchase.productID} '
          'to ${googlePlayDetails.id} with mode=$effectiveReplacementMode',
        );

        try {
          await _inAppPurchase.buyNonConsumable(
            purchaseParam: purchaseParam,
          );
        } catch (e) {
          final message = e.toString();
          debugPrint('[PaymentService] buyNonConsumable error: $message');
          if (message.contains('ITEM_ALREADY_OWNED')) {
            debugPrint(
              '[PaymentService] Detected ITEM_ALREADY_OWNED, clearing cache and refreshing purchase state',
            );
            clearCachedPurchases();
          }
          _onPurchaseError?.call('Purchase failed: $message');
          await finalizePendingPurchase();
          return completer.future;
        }
      } else {
        final purchaseParam = PurchaseParam(
          productDetails: product,
          applicationUserName: applicationUserName,
        );

        debugPrint(
          '[PaymentService] Launching normal purchase for ${product.id}',
        );

        try {
          await _inAppPurchase.buyNonConsumable(
            purchaseParam: purchaseParam,
          );
        } catch (e) {
          final message = e.toString();
          debugPrint('[PaymentService] buyNonConsumable error: $message');
          if (message.contains('ITEM_ALREADY_OWNED')) {
            debugPrint(
              '[PaymentService] Detected ITEM_ALREADY_OWNED on normal purchase, clearing cache',
            );
            clearCachedPurchases();
          }
          _onPurchaseError?.call('Purchase failed: $message');
          await finalizePendingPurchase();
          return completer.future;
        }
      }

      return completer.future;
    } catch (e) {
      final message = e.toString();
      debugPrint('[PaymentService] Purchase flow error: $message');
      clearCachedPurchases();
      _onPurchaseError?.call('Purchase failed: $message');
      return Future.value(false);
    }
  }

  static int _subscriptionPriority(ProductDetails product) {
    final id = product.id.toLowerCase();
    if (id.contains('year')) {
      return 3;
    }
    if (id.contains('quarter') || id.contains('season')) {
      return 2;
    }
    if (id.contains('month')) {
      return 1;
    }
    return 0;
  }

  static int _subscriptionPriorityById(String productId) {
    final id = productId.toLowerCase();
    if (id.contains('year')) {
      return 3;
    }
    if (id.contains('quarter') || id.contains('season')) {
      return 2;
    }
    if (id.contains('month')) {
      return 1;
    }
    return 0;
  }

  bool _isDowngrade(ProductDetails newProduct, PurchaseDetails oldPurchase) {
    return _subscriptionPriority(newProduct) <
        _subscriptionPriorityById(oldPurchase.productID);
  }

  PurchaseDetails? _pickBestOldPurchase(List<PurchaseDetails> candidates) {
    if (candidates.isEmpty) return null;

    final autoRenewing = <PurchaseDetails>[];
    final nonRenewing = <PurchaseDetails>[];

    for (final purchase in candidates) {
      final isAutoRenewing = purchase is GooglePlayPurchaseDetails
          ? purchase.billingClientPurchase.isAutoRenewing
          : null;
      debugPrint(
        '[PaymentService] Candidate ${purchase.productID} autoRenewing=$isAutoRenewing',
      );

      if (isAutoRenewing == true) {
        autoRenewing.add(purchase);
      } else {
        nonRenewing.add(purchase);
      }
    }

    final pool = autoRenewing.isNotEmpty ? autoRenewing : candidates;

    pool.sort(
      (a, b) {
        final aTime = a is GooglePlayPurchaseDetails
            ? a.billingClientPurchase.purchaseTime
            : 0;
        final bTime = b is GooglePlayPurchaseDetails
            ? b.billingClientPurchase.purchaseTime
            : 0;
        return bTime.compareTo(aTime);
      },
    );

    return pool.first;
  }

  /// Cached past purchases for upgrade/downgrade scenarios
  final List<PurchaseDetails> _pastPurchases = [];

  /// User ID for purchase association
  String? _userId;

  /// Set user ID for purchase association
  void setUserId(String? userId) {
    _userId = userId;
  }

  String? _resolveUserId() => _userId;

  /// Store mapping of subscriptionType to productId
  final Map<String, String> _subscriptionTypeToProductId = {};

  /// Store a mapping from subscription type to product ID
  void registerSubscriptionProduct(String subscriptionType, String productId) {
    _subscriptionTypeToProductId[subscriptionType] = productId;
  }

  /// Get the product ID for a given subscription type
  String? getProductIdForType(String subscriptionType) {
    return _subscriptionTypeToProductId[subscriptionType];
  }

  /// Store past purchase for later use in upgrades.
  void cachePastPurchase(PurchaseDetails purchase) {
    _pastPurchases.removeWhere((p) => p.productID == purchase.productID);
    _pastPurchases.add(purchase);

    _cachedPurchases.removeWhere((p) => p.productID == purchase.productID);
    _cachedPurchases.add(purchase);
  }

  /// Get cached purchase for a specific product type
  /// Get the cached purchase for a specific subscription type
  /// Uses productId mapping to find the correct purchase
  PurchaseDetails? getCachedPurchase(String subscriptionType) {
    // First try to match by productId mapping
    final expectedProductId = _subscriptionTypeToProductId[subscriptionType];
    if (expectedProductId != null) {
      for (final purchase in _pastPurchases) {
        if (purchase.productID == expectedProductId &&
            (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored)) {
          return purchase;
        }
      }
    }

    // Fallback: try to match by name contains (for backwards compatibility)
    for (final purchase in _pastPurchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final productId = purchase.productID.toLowerCase();
        final type = subscriptionType.toLowerCase();
        if ((type.contains('month') && productId.contains('month')) ||
            (type.contains('quarter') && productId.contains('quarter')) ||
            (type.contains('year') && productId.contains('year'))) {
          return purchase;
        }
      }
    }
    return null;
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
        return false;
      }
    }

    try {
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );

      return await _inAppPurchase.buyConsumable(
        purchaseParam: purchaseParam,
      );
    } catch (e) {
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
        return false;
      }
    }

    try {
      // Use the same applicationUserName as when purchasing
      await _inAppPurchase.restorePurchases(
        applicationUserName: _resolveUserId(),
      );
      return true;
    } catch (e) {
      _onPurchaseError?.call('Restore failed: $e');
      return false;
    }
  }

  /// Query existing purchases from Google Play (for upgrade/downgrade)
  /// Returns list of active purchases that can be used for subscription changes
  Future<List<PurchaseDetails>> queryExistingPurchases({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedPurchases.isNotEmpty &&
        _lastPurchaseQueryTime != null &&
        DateTime.now().difference(_lastPurchaseQueryTime!) < _purchaseQueryCacheTtl) {
      debugPrint(
        '[PaymentService] Returning cached purchases from ${_lastPurchaseQueryTime!.toIso8601String()}',
      );
      return _cachedPurchases;
    }

    if (!_isInitialized) {
      await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
    }

    try {
      final androidAddition = _inAppPurchase.getPlatformAddition<
          InAppPurchaseAndroidPlatformAddition>();

      // Query all purchases including expired ones
      final response = await androidAddition.queryPastPurchases(
        applicationUserName: _resolveUserId(),
      );

      if (response.error != null) {
        return _cachedPurchases.isNotEmpty ? _cachedPurchases : [];
      }

      // Update cache
      _cachedPurchases = response.pastPurchases;
      _lastPurchaseQueryTime = DateTime.now();

      for (final purchase in response.pastPurchases) {
        cachePastPurchase(purchase);
      }

      return response.pastPurchases;
    } catch (e) {
      return _cachedPurchases.isNotEmpty ? _cachedPurchases : [];
    }
  }

  /// Handle purchase update from the stream
  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchase in purchaseDetailsList) {
      final bool isPendingProduct = purchase.productID == _pendingPurchaseProductId;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          cachePastPurchase(purchase);

          if (purchase.pendingCompletePurchase) {
            try {
              await _inAppPurchase.completePurchase(purchase);
            } catch (e) {
              // Silently handle acknowledge errors
            }
          }

          if (isPendingProduct) {
            _pendingPurchaseCompleter?.complete(true);
            _pendingPurchaseCompleter = null;
            _pendingPurchaseProductId = null;
          }

          _onPurchaseComplete?.call(purchase);
          break;
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          debugPrint('[PaymentService] Purchase canceled by user: ${purchase.productID}');
          if (isPendingProduct) {
            _pendingPurchaseCompleter?.complete(false);
            _pendingPurchaseCompleter = null;
            _pendingPurchaseProductId = null;
          }
          break;
        case PurchaseStatus.error:
          final errorMsg = purchase.error?.message ?? '';
          final errorCode = purchase.error?.code ?? 'unknown';
          debugPrint('[PaymentService] Purchase error: code=$errorCode, message=$errorMsg');
          final userFriendlyMsg = _mapPurchaseErrorToUserMessage(errorMsg);
          _onPurchaseError?.call(userFriendlyMsg);
          if (isPendingProduct) {
            _pendingPurchaseCompleter?.complete(false);
            _pendingPurchaseCompleter = null;
            _pendingPurchaseProductId = null;
          }
          break;
      }
    }
  }

  /// Maps Google Play error messages to user-friendly messages
  String _mapPurchaseErrorToUserMessage(String errorMsg) {
    if (errorMsg.contains('itemAlreadyOwned') || 
        errorMsg.contains('BillingResponse.itemAlreadyOwned')) {
      return 'itemAlreadyOwned'; // Special code for UI to show localized message
    }
    if (errorMsg.contains('SERVICE_UNAVAILABLE')) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    if (errorMsg.contains('NETWORK_ERROR')) {
      return 'Network error. Please check your internet connection.';
    }
    if (errorMsg.contains('USER_CANCELED')) {
      return 'Purchase was canceled.';
    }
    if (errorMsg.contains('DEVELOPER_ERROR')) {
      return 'Product configuration error. Please try again later.';
    }
    if (errorMsg.contains('BILLING_UNAVAILABLE')) {
      return 'Google Play billing is unavailable. Please try again later.';
    }
    if (errorMsg.contains('ITEM_UNAVAILABLE')) {
      return 'This product is currently unavailable.';
    }
    // Default: return original message
    return 'Purchase failed. Please try again.';
  }

  /// Consume a purchase (for consumables like coins)
  /// This must be called after successful purchase to allow repurchasing
  Future<bool> consumePurchase(PurchaseDetails purchase) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final androidAddition = _inAppPurchase.getPlatformAddition<
          InAppPurchaseAndroidPlatformAddition>();
      await androidAddition.consumePurchase(purchase);
      return true;
    } catch (e) {
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
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get the current platform type
  TargetPlatform get currentPlatform {
    if (kIsWeb) return defaultTargetPlatform;
    return defaultTargetPlatform;
  }

  /// Clear cached purchases - needed when user cancels and wants to buy again
  void clearCachedPurchases() {
    _cachedPurchases.clear();
    _pastPurchases.clear();
    _lastPurchaseQueryTime = null;
    debugPrint('[PaymentService] Cached purchases cleared');
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
