import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/storage/storage_service.dart';
import '../models/subscription_product.dart';
import '../services/payment_service.dart';
import '../services/receipt_verification.dart';

/// Member subscription state
class MemberState {
  const MemberState({
    this.isVip = false,
    this.expireDate,
    this.subscriptionType,
    this.isLoading = false,
    this.errorMessage,
    this.isRestoring = false,
    this.pendingOrderId,
    this.pendingProductId,
    this.pendingSubscriptionType,
  });

  final bool isVip;
  final DateTime? expireDate;
  final String? subscriptionType;
  final bool isLoading;
  final String? errorMessage;
  final bool isRestoring;
  final String? pendingOrderId;
  final String? pendingProductId;
  final String? pendingSubscriptionType;

  MemberState copyWith({
    bool? isVip,
    DateTime? expireDate,
    String? subscriptionType,
    bool? isLoading,
    String? errorMessage,
    bool? isRestoring,
    String? pendingOrderId,
    String? pendingProductId,
    String? pendingSubscriptionType,
    bool clearPendingOrder = false,
  }) {
    return MemberState(
      isVip: isVip ?? this.isVip,
      expireDate: expireDate ?? this.expireDate,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isRestoring: isRestoring ?? this.isRestoring,
      pendingOrderId: clearPendingOrder ? null : (pendingOrderId ?? this.pendingOrderId),
      pendingProductId: clearPendingOrder ? null : (pendingProductId ?? this.pendingProductId),
      pendingSubscriptionType: clearPendingOrder
          ? null
          : (pendingSubscriptionType ?? this.pendingSubscriptionType),
    );
  }

  bool get isExpired {
    if (expireDate == null) return !isVip;
    return DateTime.now().isAfter(expireDate!);
  }

  int? get daysRemaining {
    if (expireDate == null) return null;
    final diff = expireDate!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
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

    await _paymentService.initialize(
      onPurchaseComplete: _handlePurchaseComplete,
      onPurchaseError: _handlePurchaseError,
    );

    await _loadCachedState();
    await _syncWithBackend();
  }

  Future<void> refreshStatus() async {
    await _loadCachedState();
    await _syncWithBackend();
  }

  Future<void> _loadCachedState() async {
    final isVip = _storage.getString('is_vip') == 'true';
    final expireStr = _storage.getString('vip_expire_date');
    final type = _storage.getString('subscription_type');

    state = state.copyWith(
      isVip: isVip,
      expireDate: expireStr != null ? DateTime.tryParse(expireStr) : null,
      subscriptionType: type,
    );

    if (state.isExpired) {
      await _clearVipStatus();
    }
  }

  Future<void> _syncWithBackend() async {
    final userId = _resolveUserId();
    if (userId == null || userId.isEmpty) return;

    final status = await _receiptService.checkSubscriptionStatus(
      userId: userId,
    );

    if (status != null && status.isActive) {
      await _updateVipStatus(
        isVip: true,
        expireDate: status.expireDate,
        type: status.type,
      );
    } else if (!state.isVip || state.isExpired) {
      await _clearVipStatus();
    }
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

      final confirmed = await _payService.confirmGooglePurchase(
        params: callbackPayload,
      );

      final productType = state.pendingSubscriptionType ?? _inferTypeFromProductId(productId);
      if (confirmed) {
        await _updateVipStatus(
          isVip: true,
          expireDate: DateTime.now().add(Duration(days: _getDaysForType(productType))),
          type: productType,
        );
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

  void _handlePurchaseError(String error) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: error,
    );
  }

  Future<void> _updateVipStatus({
    required bool isVip,
    DateTime? expireDate,
    String? type,
  }) async {
    state = state.copyWith(
      isVip: isVip,
      expireDate: expireDate,
      subscriptionType: type,
      isLoading: false,
      errorMessage: null,
    );

    await _storage.setString('is_vip', isVip.toString());
    if (expireDate != null) {
      await _storage.setString('vip_expire_date', expireDate.toIso8601String());
    } else {
      await _storage.remove('vip_expire_date');
    }
    if (type != null && type.isNotEmpty) {
      await _storage.setString('subscription_type', type);
    } else {
      await _storage.remove('subscription_type');
    }
  }

  Future<void> _clearVipStatus() async {
    state = state.copyWith(
      isVip: false,
      expireDate: null,
      subscriptionType: null,
      isLoading: false,
      errorMessage: null,
    );

    await _storage.remove('is_vip');
    await _storage.remove('vip_expire_date');
    await _storage.remove('subscription_type');
  }

  Future<bool> restorePurchases() async {
    state = state.copyWith(isRestoring: true, errorMessage: null);

    try {
      final success = await _paymentService.restorePurchases();
      if (!success) {
        state = state.copyWith(
          isRestoring: false,
          errorMessage: 'Failed to restore purchases',
        );
        return false;
      }

      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(isRestoring: false);
      return success;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      state = state.copyWith(
        isRestoring: false,
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
        return state.isVip && !state.isExpired;
      case Feature.trialContent:
        return true;
    }
  }

  Future<List<ProductDetails>> getProducts(List<SubscriptionProduct> products) async {
    final productIds = products
        .map((p) => p.getProductId(_paymentService.currentPlatform))
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
      final platformProductId = selectedProduct.getProductId(_paymentService.currentPlatform);

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

      state = state.copyWith(
        pendingOrderId: orderId,
        pendingProductId: productDetails.id,
        pendingSubscriptionType: selectedProduct.id,
      );

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

  String _inferTypeFromProductId(String productId) {
    if (productId.contains('yearly') || productId.contains('year')) {
      return 'yearly';
    } else if (productId.contains('quarterly') || productId.contains('quarter')) {
      return 'quarterly';
    }
    return 'monthly';
  }

  int _getDaysForType(String type) {
    switch (type) {
      case 'yearly':
        return 365;
      case 'quarterly':
        return 90;
      default:
        return 30;
    }
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
      final storeProducts = await _paymentService.getProducts(
        productIds: baseProducts
            .map((product) => product.getProductId(_paymentService.currentPlatform))
            .where((id) => id.isNotEmpty)
            .toList(),
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

        final storePrice = storeProduct.price.trim();
        final originalPrice = product.originalPrice.trim();
        final nextOriginalPrice =
            originalPrice.isEmpty || originalPrice == storePrice ? product.price : product.originalPrice;

        return product.copyWith(
          price: storePrice,
          priceCn: storePrice,
          originalPrice: nextOriginalPrice,
          originalPriceCn: nextOriginalPrice,
        );
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
  final memberState = ref.watch(memberStateProvider);
  return memberState.isVip && !memberState.isExpired ||
      feature == Feature.trialContent;
});
