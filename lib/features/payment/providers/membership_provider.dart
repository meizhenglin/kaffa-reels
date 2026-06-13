import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/recharge_product.dart';
import '../models/subscription_product.dart';
import '../services/payment_service.dart';
import '../services/receipt_verification.dart';

export '../models/recharge_product.dart' show RechargeProduct, RechargeProductsState, CoinBalanceState;

/// Recharge purchase handler for consumables
class RechargePurchaseHandler {
  RechargePurchaseHandler(this._ref);

  final Ref _ref;

  /// Pending recharge product (set before purchase, cleared after)
  RechargeProduct? pendingProduct;

  /// Purchase a recharge product
  Future<bool> purchase(RechargeProduct product) async {
    // Set pending product before purchase
    pendingProduct = product;

    final paymentService = PaymentService.instance;

    // Get product details from store
    final products = await paymentService.getProducts(
      productIds: [product.googlePlayId],
    );

    if (products.isEmpty) {
      debugPrint('Product not found: ${product.googlePlayId}');
      pendingProduct = null;
      return false;
    }

    // Start consumable purchase
    final success = await paymentService.purchaseConsumable(
      product: products.first,
    );

    if (!success) {
      pendingProduct = null;
    }

    return success;
  }

  /// Handle successful consumable purchase
  Future<bool> handlePurchaseSuccess(PurchaseDetails purchase) async {
    if (pendingProduct == null) {
      debugPrint('No pending recharge product');
      return false;
    }

    final product = pendingProduct!;
    pendingProduct = null;

    final paymentService = PaymentService.instance;

    // Consume the purchase
    final consumed = await paymentService.handleConsumablePurchase(purchase);
    if (!consumed) {
      debugPrint('Failed to consume purchase');
      return false;
    }

    // Call backend API for recharge callback (payConfigType=1)
    final apiService = ApiService(dioClient: DioClient(), storage: StorageService());

    try {
      final callbackPayload = {
        'orderId': purchase.purchaseID ?? '',
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'purchaseData': purchase.verificationData.serverVerificationData,
        'payConfigType': 1, // Recharge/consumable
        'goodsId': product.goodsId,
      };

      final response = await apiService.request(
        'api/pay/callback/google',
        data: callbackPayload,
      );

      if (response.isSuccess) {
        debugPrint('Recharge callback successful');

        // Parse and update coin balance from response
        final responseData = response.data;
        if (responseData is Map) {
          final coinAmount = responseData['coinAmount'] ??
                             responseData['amount'] ??
                             responseData['rechargeAmount'] ?? 0;
          final coinNotifier = _ref.read(coinBalanceProvider.notifier);
          await coinNotifier.addCoins(coinAmount as int);
        }
        return true;
      } else {
        debugPrint('Recharge callback failed: ${response.error}');
      }
    } catch (e) {
      debugPrint('Error calling recharge callback: $e');
    }

    return false;
  }

  /// Clear pending product (on cancel/error)
  void clearPending() {
    pendingProduct = null;
  }
}

/// Provider for recharge purchase handler
final rechargePurchaseHandlerProvider = Provider<RechargePurchaseHandler>((ref) {
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
}

/// Recharge products provider
final rechargeProductsProvider =
    StateNotifierProvider<RechargeProductsNotifier, RechargeProductsState>((ref) {
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
        'api/app/rechargeGoods',
        method: 'POST',
        data: {'rechargeGoodsType': 1}, // 1 = K币充值
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

        final products = items
            .where((item) => item.isEnable && item.goodsGoogleId.isNotEmpty)
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
      debugPrint('Error loading recharge products: $e');
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

/// Member subscription state - simplified to only track purchase token
class MemberState {
  const MemberState({
    this.purchaseToken,
    this.isLoading = false,
    this.errorMessage,
    this.pendingOrderId,
    this.pendingProductId,
    this.pendingSubscriptionType,
  });

  final String? purchaseToken;
  final bool isLoading;
  final String? errorMessage;
  final String? pendingOrderId;
  final String? pendingProductId;
  final String? pendingSubscriptionType;

  MemberState copyWith({
    String? purchaseToken,
    bool? isLoading,
    String? errorMessage,
    String? pendingOrderId,
    String? pendingProductId,
    String? pendingSubscriptionType,
    bool clearPendingOrder = false,
  }) {
    return MemberState(
      purchaseToken: clearPendingOrder ? null : (purchaseToken ?? this.purchaseToken),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      pendingOrderId: clearPendingOrder ? null : (pendingOrderId ?? this.pendingOrderId),
      pendingProductId: clearPendingOrder ? null : (pendingProductId ?? this.pendingProductId),
      pendingSubscriptionType: clearPendingOrder
          ? null
          : (pendingSubscriptionType ?? this.pendingSubscriptionType),
    );
  }
}

class MembershipProductsState {
  const MembershipProductsState({
    this.products = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hasLoaded = false,
  });

  final List<SubscriptionProduct> products;
  final bool isLoading;
  final String? errorMessage;
  final bool hasLoaded;

  MembershipProductsState copyWith({
    List<SubscriptionProduct>? products,
    bool? isLoading,
    String? errorMessage,
    bool? hasLoaded,
    bool clearError = false,
  }) {
    return MembershipProductsState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

/// Member state provider
final memberStateProvider =
    StateNotifierProvider<MemberStateNotifier, MemberState>((ref) {
  final notifier = MemberStateNotifier(ref);
  Future.microtask(notifier.initialize);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final membershipProductsProvider = StateNotifierProvider<MembershipProductsNotifier,
    MembershipProductsState>((ref) {
  return MembershipProductsNotifier(ref.read(dioClientProvider), ref.read(storageServiceProvider));
});

class MemberStateNotifier extends StateNotifier<MemberState> {
  MemberStateNotifier(this._ref) : super(const MemberState());

  final Ref _ref;
  PayService get _payService => payServiceProvider;
  PaymentService get _paymentService => PaymentService.instance;
  ReceiptVerificationService get _receiptService =>
      ReceiptVerificationService.instance;
  StorageService get _storage => _ref.read(storageServiceProvider);

  /// Initialize the provider
  Future<void> initialize() async {
    _receiptService.initialize(baseUrl: 'https://api.your-domain.com');

    // Set user ID for purchase association
    final userId = _storage.getString('user_id');
    _paymentService.setUserId(userId);

    await _paymentService.initialize(
      onPurchaseComplete: _handlePurchaseComplete,
      onPurchaseError: _handlePurchaseError,
    );

    // Load cached purchase token (only thing we persist locally)
    final token = _storage.getString('purchase_token');
    if (token != null && token.isNotEmpty) {
      state = state.copyWith(purchaseToken: token);
    }

    // Check and retry pending payments
    await checkAndRetryPendingPayments();
  }

  Future<void> refreshStatus() async {
    await checkAndRetryPendingPayments();
  }

  Future<void> _handlePurchaseComplete(PurchaseDetails purchase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final purchaseToken = purchase.verificationData.serverVerificationData;
      final orderId = state.pendingOrderId;
      final productId = state.pendingProductId ?? purchase.productID;

      if (orderId == null || orderId.isEmpty) {
        throw StateError('Missing pending order id for purchase callback');
      }
      if (purchaseToken.isEmpty) {
        throw StateError('Missing Google purchase token');
      }

      final callbackPayload = <String, dynamic>{
        'orderId': orderId,
        'productId': productId,
        'purchaseId': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        'status': purchase.status.name,
        'pendingCompletePurchase': purchase.pendingCompletePurchase,
        'verificationData': {
          'localVerificationData': purchase.verificationData.localVerificationData,
          'serverVerificationData': purchase.verificationData.serverVerificationData,
          'source': purchase.verificationData.source,
        },
        'error': purchase.error == null
            ? null
            : {
                'source': purchase.error!.source,
                'code': purchase.error!.code,
                'message': purchase.error!.message,
                'details': purchase.error!.details?.toString(),
              },
      };

      // 重试逻辑：最多重试3次，指数退避
      bool confirmed = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries && !confirmed) {
        if (retryCount > 0) {
          // 指数退避: 2s, 4s, 8s
          final delay = Duration(seconds: (2 << (retryCount - 1)));
          debugPrint('Retrying Google Pay callback, attempt $retryCount/$maxRetries, waiting $delay');
          await Future.delayed(delay);
        }

        try {
          confirmed = await _payService.confirmGooglePurchase(
            params: callbackPayload,
          );
          debugPrint('Google Pay callback result: confirmed=$confirmed, attempt=${retryCount + 1}');
        } catch (e) {
          debugPrint('Google Pay callback error: $e, attempt=${retryCount + 1}');
          if (retryCount == maxRetries - 1) {
            // 最后一次重试也失败了，保存到本地待处理
            debugPrint('All retries failed, saving pending payment');
            await _savePendingPayment(callbackPayload);
          }
        }
        retryCount++;
      }

      if (confirmed) {
        await _updateVipStatus(purchaseToken: purchaseToken);
        // Invalidate isVipProvider to force refresh
        _ref.invalidate(isVipProvider);
        state = state.copyWith(clearPendingOrder: true);
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Purchase verification failed',
        );
      }
    } catch (e) {
      debugPrint('Error handling purchase completion: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to process purchase',
      );
    }
  }

  /// 保存待处理的支付回调到本地
  Future<void> _savePendingPayment(Map<String, dynamic> paymentData) async {
    await _storage.savePendingPayment(paymentData);
  }

  /// 检查并重试所有待处理的支付回调
  Future<void> checkAndRetryPendingPayments() async {
    // 检查是否已登录
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      debugPrint('User not logged in, skipping pending payments retry');
      state = state.copyWith(isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final pendingPayments = await _storage.getPendingPayments();
      if (pendingPayments.isEmpty) {
        debugPrint('No pending payments to retry');
        state = state.copyWith(isLoading: false);
        return;
      }

      debugPrint('Found ${pendingPayments.length} pending payments, retrying...');

      final successfulOrderIds = <String>[];

      for (final payment in pendingPayments) {
        final orderId = payment['orderId'] as String?;
        if (orderId == null) continue;

        bool success = false;

        // 重试3次，指数退避
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            debugPrint('Retrying pending payment: orderId=$orderId, attempt=$attempt');
            success = await _payService.confirmGooglePurchase(params: payment);
            if (success) {
              debugPrint('Pending payment succeeded: orderId=$orderId');
              successfulOrderIds.add(orderId);
              break;
            }
          } catch (e) {
            debugPrint('Retry failed for orderId=$orderId, attempt=$attempt: $e');
            if (attempt < 3) {
              final delay = Duration(seconds: (2 << (attempt - 1)));
              await Future.delayed(delay);
            }
          }
        }

        if (!success) {
          debugPrint('Pending payment permanently failed: orderId=$orderId');
        }
      }

      // 移除成功的支付记录
      for (final orderId in successfulOrderIds) {
        await _storage.removePendingPayment(orderId);
      }

      final remaining = await _storage.getPendingPayments();
      debugPrint('Pending payments retry complete. Remaining: ${remaining.length}');

      // 如果有支付成功了，刷新VIP状态
      if (successfulOrderIds.isNotEmpty) {
        await _refreshVipStatus();
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('Error checking pending payments: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// 刷新VIP状态 - just reload purchase token
  Future<void> _refreshVipStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final purchaseToken = _storage.getString('purchase_token');
      state = state.copyWith(
        purchaseToken: purchaseToken,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error refreshing VIP status: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void _handlePurchaseError(String error) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: error,
    );
  }

  Future<void> _updateVipStatus({
    required String purchaseToken,
  }) async {
    state = state.copyWith(
      purchaseToken: purchaseToken,
      isLoading: false,
      errorMessage: null,
    );

    // Only persist the purchase token (needed for backend verification)
    await _storage.setString('purchase_token', purchaseToken);

    // Refresh auth user info so profile page shows updated VIP expiry date
    try {
      await _ref.read(authProvider.notifier).refreshUserInfo();
    } catch (e) {
      debugPrint('[MemberStateNotifier] refreshUserInfo failed: $e');
    }
  }

  String? getPurchaseToken() {
    return _storage.getString('purchase_token');
  }

  Future<void> _clearVipStatus() async {
    state = const MemberState();

    // Only clear the purchase token
    await _storage.remove('purchase_token');
  }

  /// Clear all VIP/membership data (called on logout)
  Future<void> clearAll() async {
    await _clearVipStatus();
    state = state.copyWith(clearPendingOrder: true);
  }

  Future<bool> restorePurchases() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final success = await _paymentService.restorePurchases();
      if (!success) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to restore purchases',
        );
        return false;
      }

      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to restore purchases',
      );
      return false;
    }
  }

  bool canAccess(Feature feature) {
    switch (feature) {
      case Feature.premiumContent:
      case Feature.adFree:
      case Feature.hdQuality:
      case Feature.offlineDownload:
      case Feature.earlyAccess:
        // Check if user has active subscription via Google Play
        return _hasActiveSubscription();
      case Feature.trialContent:
        return true;
    }
  }

  bool _hasActiveSubscription() {
    // Check if we have a purchase token - that means user has purchased before
    // The actual validity is verified by Google Play query
    return state.purchaseToken != null;
  }

  /// Check if user is VIP by querying Google Play
  Future<bool> checkIsVip() async {
    if (state.purchaseToken == null) return false;

    try {
      final purchases = await _paymentService.queryExistingPurchases();
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('[checkIsVip] queryExistingPurchases error: $e');
    }
    return false;
  }

  Future<List<ProductDetails>> getProducts(List<SubscriptionProduct> products) async {
    final productIds = products
        .map((p) => p.getProductId(_paymentService.currentPlatform).trim())
        .where((id) => id.isNotEmpty)
        .toList();

    debugPrint('IAP getProducts: querying $productIds');

    return _paymentService.getProducts(
      productIds: productIds,
      requireSubscriptionOnAndroid: true,
    );
  }

  Future<bool> purchase({
    required SubscriptionProduct selectedProduct,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final order = await _payService.createOrder(payConfigId: selectedProduct.goodsId!);
      final orderId = order?.orderId;
      if (orderId == null || orderId.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to create order',
          clearPendingOrder: true,
        );
        return false;
      }

      final products = await getProducts([selectedProduct]);
      final platformProductId = selectedProduct.getProductId(_paymentService.currentPlatform).trim();

      debugPrint(
        'IAP purchase flow: platformProductId="$platformProductId", '
        'requestedProductIds=[${[selectedProduct].map((p) => p.getProductId(_paymentService.currentPlatform).trim()).join(', ')}]',
      );

      if (products.isEmpty) {
        debugPrint('IAP purchase error: storeProducts list is EMPTY for product IDs: [${[selectedProduct].map((p) => p.getProductId(_paymentService.currentPlatform).trim()).join(', ')}]');
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Subscription product is unavailable or not configured as subs in Google Play.',
          clearPendingOrder: true,
        );
        return false;
      }

      ProductDetails? productDetails;
      try {
        productDetails = products.firstWhere((p) => p.id == platformProductId);
      } catch (_) {
        try {
          productDetails = products.firstWhere((p) => p.id.contains(selectedProduct.id));
        } catch (_) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Product not available in Google Play: $platformProductId',
            clearPendingOrder: true,
          );
          return false;
        }
      }

      state = state.copyWith(
        pendingOrderId: orderId,
        pendingProductId: productDetails.id,
        pendingSubscriptionType: selectedProduct.id,
      );

      // 查询并缓存现有订阅（用于升级/降级）
      final purchases = await _paymentService.queryExistingPurchases();
      debugPrint('[IAP] queryExistingPurchases returned: ${purchases.length} purchases');
      for (final p in purchases) {
        debugPrint('  - ${p.productID}: ${p.status}');
      }

      // 如果 Google Play 查询不到购买但服务器有订阅，说明是同一商品续费
      // Google Play 会自动处理，不传 oldPurchaseDetails 也没问题
      final success = await _paymentService.purchase(
        product: productDetails,
        applicationUserName: _resolveUserId(),
      );

      if (!success) {
        state = state.copyWith(
          isLoading: false,
          clearPendingOrder: true,
        );
      }
      return success;
    } catch (e) {
      debugPrint('Error creating order: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
        clearPendingOrder: true,
      );
      return false;
    }
  }

  String? _resolveUserId() {
    return _storage.getString('user_id');
  }

  @override
  void dispose() {
    _paymentService.dispose();
    super.dispose();
  }
}

class MembershipProductsNotifier extends StateNotifier<MembershipProductsState> {
  MembershipProductsNotifier(DioClient dioClient, StorageService storage)
      : _apiService = ApiService(dioClient: dioClient, storage: storage),
        _paymentService = PaymentService.instance,
        super(const MembershipProductsState());

  final ApiService _apiService;
  final PaymentService _paymentService;

  Future<void> loadVipProducts() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, hasLoaded: true, clearError: true);

    try {
      final response = await _apiService.getRechargeGoodsConfig(rechargeGoodsType: 0);
      if (!response.isSuccess) {
        state = state.copyWith(
          isLoading: false,
          products: const [],
          errorMessage: response.error,
        );
        return;
      }

      final items = _parseRechargeGoods(response.data);
      final baseProducts = SubscriptionProducts.fromRechargeGoods(items);
      final products = await _syncStorePrices(baseProducts);
      state = state.copyWith(
        isLoading: false,
        products: products,
        clearError: true,
      );
    } catch (e) {
      debugPrint('Failed to load vip products: $e');
      state = state.copyWith(
        isLoading: false,
        products: const [],
        errorMessage: 'Failed to load products',
      );
    }
  }

  List<RechargeGoodsConfigItem> _parseRechargeGoods(dynamic data) {
    final rawList = switch (data) {
      {'list': final list} => list,
      {'rows': final rows} => rows,
      {'data': final nested} => nested,
      List<dynamic> list => list,
      _ => const <dynamic>[],
    };

    if (rawList is! List) return const [];

    return rawList
        .whereType<Map>()
        .map((item) => RechargeGoodsConfigItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<SubscriptionProduct>> _syncStorePrices(
    List<SubscriptionProduct> baseProducts,
  ) async {
    if (baseProducts.isEmpty || kIsWeb) return baseProducts;

    try {
      final rawIds = baseProducts
          .map((product) => product.getProductId(_paymentService.currentPlatform))
          .where((id) => id.isNotEmpty)
          .toList();

      final sanitizedIds = rawIds.map((id) => id.trim()).toList();

      debugPrint(
        'IAP _syncStorePrices: querying ${sanitizedIds.length} product IDs, '
        'rawIds=$rawIds',
      );

      final storeProducts = await _paymentService.getProducts(
        productIds: sanitizedIds,
        requireSubscriptionOnAndroid: defaultTargetPlatform == TargetPlatform.android,
      );

      debugPrint(
        'IAP _syncStorePrices: received ${storeProducts.length} store products',
      );

      if (storeProducts.isEmpty) {
        debugPrint(
          'IAP _syncStorePrices: WARNING - store returned 0 products. '
          'This usually means: (1) product IDs not configured in Play Console, '
          '(2) product IDs have extra spaces, or (3) Google Play Billing Library '
          'version mismatch. Check build.gradle.kts for Billing Library version.',
        );
        return baseProducts;
      }

      final storeProductMap = {
        for (final product in storeProducts) product.id: product,
      };

      return baseProducts.map((product) {
        final storeProduct = storeProductMap[product.getProductId(_paymentService.currentPlatform)];
        if (storeProduct == null) {
          return product;
        }

        // Register the mapping from subscriptionType to productId
        if (product.id.isNotEmpty) {
          _paymentService.registerSubscriptionProduct(
            product.id,
            storeProduct.id,
          );
          debugPrint('Registered subscription mapping: ${product.id} -> ${storeProduct.id}');
        }

        // For display: keep API's price and originalPrice as-is.
        // Store price is only used for the purchase transaction, not for UI display.
        return product;
      }).toList();
    } catch (e) {
      debugPrint('Failed to sync store prices: $e');
      return baseProducts;
    }
  }
}

/// Features that require membership
enum Feature {
  premiumContent,
  adFree,
  hdQuality,
  offlineDownload,
  earlyAccess,
  trialContent,
}

extension FeatureExt on Feature {
  String get displayName {
    switch (this) {
      case Feature.premiumContent:
        return 'Premium Content';
      case Feature.adFree:
        return 'Ad-free';
      case Feature.hdQuality:
        return 'HD Quality';
      case Feature.offlineDownload:
        return 'Offline Download';
      case Feature.earlyAccess:
        return 'Early Access';
      case Feature.trialContent:
        return 'Trial Content';
    }
  }
}

final featureAccessProvider = Provider.family<bool, Feature>((ref, feature) {
  final isVip = ref.watch(isVipProvider).valueOrNull ?? false;
  return isVip || feature == Feature.trialContent;
});

/// Provider that checks actual VIP status
/// Checks both Google Play purchases AND backend VIP status
final isVipProvider = FutureProvider<bool>((ref) async {
  final memberState = ref.watch(memberStateProvider);

  // If we have a purchase token, verify with Google Play
  if (memberState.purchaseToken != null) {
    try {
      final purchases = await PaymentService.instance.queryExistingPurchases();
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('[isVipProvider] queryExistingPurchases error: $e');
    }
  }

  // Also check backend VIP status via userPersonalCenter API
  try {
    final apiService = ApiService(
      dioClient: ref.read(dioClientProvider),
      storage: ref.read(storageServiceProvider),
    );
    final response = await apiService.getUserCenter();
    if (response.code == 0 && response.data != null) {
      final isVip = response.data['isVip'] ?? response.data['is_vip'] ?? 0;
      debugPrint('[isVipProvider] backend isVip: $isVip');
      if (isVip == 1 || isVip == true) {
        return true;
      }
    }
  } catch (e) {
    debugPrint('[isVipProvider] backend check error: $e');
  }

  return false;
});
