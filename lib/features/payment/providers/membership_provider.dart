import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
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
  });

  final bool isVip;
  final DateTime? expireDate;
  final String? subscriptionType;
  final bool isLoading;
  final String? errorMessage;
  final bool isRestoring;

  MemberState copyWith({
    bool? isVip,
    DateTime? expireDate,
    String? subscriptionType,
    bool? isLoading,
    String? errorMessage,
    bool? isRestoring,
  }) {
    return MemberState(
      isVip: isVip ?? this.isVip,
      expireDate: expireDate ?? this.expireDate,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isRestoring: isRestoring ?? this.isRestoring,
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
  return MemberStateNotifier();
});

final membershipProductsProvider = StateNotifierProvider<MembershipProductsNotifier,
    MembershipProductsState>((ref) {
  return MembershipProductsNotifier(ref.read(dioClientProvider), ref.read(storageServiceProvider));
});

class MemberStateNotifier extends StateNotifier<MemberState> {
  MemberStateNotifier() : super(const MemberState());

  SharedPreferences? _prefs;
  PaymentService get _paymentService => PaymentService.instance;
  ReceiptVerificationService get _receiptService =>
      ReceiptVerificationService.instance;

  /// Initialize the provider
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    _receiptService.initialize(baseUrl: 'https://api.your-domain.com');

    await _paymentService.initialize(
      onPurchaseComplete: _handlePurchaseComplete,
      onPurchaseError: _handlePurchaseError,
    );

    await _loadCachedState();
    await _syncWithBackend();
  }

  Future<void> _loadCachedState() async {
    if (_prefs == null) return;

    final isVip = _prefs!.getBool('is_vip') ?? false;
    final expireStr = _prefs!.getString('vip_expire_date');
    final type = _prefs!.getString('subscription_type');

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
    final userId = _prefs?.getString('user_id');
    if (userId == null) return;

    final status = await _receiptService.checkSubscriptionStatus(
      userId: userId,
    );

    if (status != null && status.isActive) {
      await _updateVipStatus(
        isVip: true,
        expireDate: status.expireDate,
        type: status.type,
      );
    } else if (state.isVip && !state.isExpired) {
    } else {
      await _clearVipStatus();
    }
  }

  Future<void> _handlePurchaseComplete(PurchaseDetails purchase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final receiptData = {
        'purchase_id': purchase.purchaseID,
        'product_id': purchase.productID,
        'status': purchase.status.name,
        'transaction_date': purchase.transactionDate,
        'data': purchase.verificationData.localVerificationData,
        'server_verification_data': purchase.verificationData.serverVerificationData,
      };

      final result = await _receiptService.verifyReceipt(
        receiptData: receiptData,
        platform: _paymentService.currentPlatform == TargetPlatform.android
            ? 'google_play'
            : 'app_store',
        userId: _prefs?.getString('user_id'),
      );

      if (result.success) {
        await _updateVipStatus(
          isVip: true,
          expireDate: result.expireDate ?? _calculateExpireDate(purchase),
          type: result.subscriptionType ?? _inferTypeFromProductId(purchase.productID),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.message ?? 'Purchase verification failed',
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

    if (_prefs != null) {
      await _prefs!.setBool('is_vip', isVip);
      if (expireDate != null) {
        await _prefs!.setString('vip_expire_date', expireDate.toIso8601String());
      }
      if (type != null) {
        await _prefs!.setString('subscription_type', type);
      }
    }
  }

  Future<void> _clearVipStatus() async {
    state = state.copyWith(
      isVip: false,
      expireDate: null,
      subscriptionType: null,
      isLoading: false,
    );

    if (_prefs != null) {
      await _prefs!.remove('is_vip');
      await _prefs!.remove('vip_expire_date');
      await _prefs!.remove('subscription_type');
    }
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

    return await _paymentService.getProducts(productIds: productIds);
  }

  Future<bool> purchase(ProductDetails product) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    return await _paymentService.purchase(product: product);
  }

  DateTime _calculateExpireDate(PurchaseDetails purchase) {
    final type = _inferTypeFromProductId(purchase.productID);
    final days = _getDaysForType(type);
    return DateTime.now().add(Duration(days: days));
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
}

class MembershipProductsNotifier extends StateNotifier<MembershipProductsState> {
  MembershipProductsNotifier(DioClient dioClient, StorageService storage)
      : _apiService = ApiService(dioClient: dioClient, storage: storage),
        super(const MembershipProductsState());

  final ApiService _apiService;

  Future<void> loadVipProducts() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, hasLoaded: true, clearError: true);

    try {
      final response = await _apiService.getRechargeGoodsConfig(rechargeGoodsType: 0);
      if (!response.isSuccess) {
        state = state.copyWith(
          isLoading: false,
          products: SubscriptionProducts.fallbackProducts,
          errorMessage: response.error,
        );
        return;
      }

      final items = _parseRechargeGoods(response.data);
      final products = SubscriptionProducts.fromRechargeGoods(items);
      state = state.copyWith(
        isLoading: false,
        products: products,
        clearError: true,
      );
    } catch (e) {
      debugPrint('Failed to load vip products: $e');
      state = state.copyWith(
        isLoading: false,
        products: SubscriptionProducts.fallbackProducts,
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
