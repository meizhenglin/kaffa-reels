import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/subscription_product.dart';
import '../services/payment_service.dart';
import '../services/receipt_verification.dart';

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
    bool clearError = false,
  }) {
    return MemberState(
      purchaseToken: clearPendingOrder ? null : (purchaseToken ?? this.purchaseToken),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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

  /// 清理待处理订单状态（用户取消购买时调用）
  void clearPendingOrder() {
    state = state.copyWith(clearPendingOrder: true, clearError: true);
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
          await Future.delayed(delay);
        }

        try {
          confirmed = await _payService.confirmGooglePurchase(
            params: callbackPayload,
          );
        } catch (e) {
          if (retryCount == maxRetries - 1) {
            // 最后一次重试也失败了，保存到本地待处理
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
      state = state.copyWith(isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final pendingPayments = await _storage.getPendingPayments();
      if (pendingPayments.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final successfulOrderIds = <String>[];

      for (final payment in pendingPayments) {
        final orderId = payment['orderId'] as String?;
        if (orderId == null) continue;

        bool success = false;

        // 重试3次，指数退避
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            success = await _payService.confirmGooglePurchase(params: payment);
            if (success) {
              successfulOrderIds.add(orderId);
              break;
            }
          } catch (e) {
            if (attempt < 3) {
              final delay = Duration(seconds: (2 << (attempt - 1)));
              await Future.delayed(delay);
            }
          }
        }
      }

      // 移除成功的支付记录
      for (final orderId in successfulOrderIds) {
        await _storage.removePendingPayment(orderId);
      }

      // 如果有支付成功了，刷新VIP状态
      if (successfulOrderIds.isNotEmpty) {
        await _refreshVipStatus();
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
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
      state = state.copyWith(isLoading: false);
    }
  }

  void _handlePurchaseError(String error) {
    // Don't show error dialog for user cancellation
    if (error == 'Purchase was canceled') {
      debugPrint('[MembershipProvider] Purchase canceled by user, ignoring');
      state = state.copyWith(
        isLoading: false,
        clearPendingOrder: true,
        errorMessage: null,
      );
      return;
    }
    
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
      // Silently handle refresh errors
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
      // Silently handle query errors
    }
    return false;
  }

  Future<List<ProductDetails>> getProducts(List<SubscriptionProduct> products) async {
    final productIds = products
        .map((p) => p.getProductId(_paymentService.currentPlatform).trim())
        .where((id) => id.isNotEmpty)
        .toList();

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
      debugPrint('[Purchase] Step 1: Creating order with goodsId=${selectedProduct.goodsId}');
      final order = await _payService.createOrder(payConfigId: selectedProduct.goodsId!);
      final orderId = order?.orderId;
      debugPrint('[Purchase] Step 1: Order created, orderId=$orderId');
      if (orderId == null || orderId.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to create order',
          clearPendingOrder: true,
        );
        return false;
      }

      debugPrint('[Purchase] Step 2: Querying Google Play products');
      final products = await getProducts([selectedProduct]);
      debugPrint('[Purchase] Step 2: Found ${products.length} products');
      final platformProductId = selectedProduct.getProductId(_paymentService.currentPlatform).trim();

      if (products.isEmpty) {
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

      debugPrint('[Purchase] Step 3: Starting Google Play purchase flow');
      state = state.copyWith(
        pendingOrderId: orderId,
        pendingProductId: productDetails.id,
        pendingSubscriptionType: selectedProduct.id,
      );

      // 标准订阅购买：允许 Google Play 查询现有订阅并自动处理升级/降级
      final success = await _paymentService.purchase(
        product: productDetails,
        applicationUserName: _resolveUserId(),
        checkForExistingPurchases: true,
      );
      debugPrint('[Purchase] Step 3: Purchase flow returned success=$success');

      if (!success) {
        state = state.copyWith(
          isLoading: false,
          clearPendingOrder: true,
        );
      }
      return success;
    } catch (e, stack) {
      debugPrint('[Purchase] Error: $e\n$stack');
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

      final storeProducts = await _paymentService.getProducts(
        productIds: sanitizedIds,
        requireSubscriptionOnAndroid: defaultTargetPlatform == TargetPlatform.android,
      );

      if (storeProducts.isEmpty) {
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
        }

        // For display: keep API's price and originalPrice as-is.
        // Store price is only used for the purchase transaction, not for UI display.
        return product;
      }).toList();
    } catch (e) {
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
  final isVip = ref.watch(isVipProvider);
  return isVip || feature == Feature.trialContent;
});

/// Provider that checks actual VIP status from the authenticated user's info.
/// VIP status is determined by the backend user center response (isVip field + vipEndTime).
/// This provider watches authProvider, so it auto-updates when user info refreshes
/// (e.g., after a purchase triggers a backend webhook → authProvider.refreshUserInfo).
final isVipProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  final user = auth.user;
  if (user == null || user.isGuest) return false;
  return user.isVip && (user.vipExpireDate == null || user.vipExpireDate!.isAfter(DateTime.now()));
});

/// Provider that checks if the user has an active VIP subscription (including expired = false).
/// Convenience wrapper around isVipProvider.
final isActiveVipProvider = Provider<bool>((ref) {
  return ref.watch(isVipProvider);
});
