import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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

/// Member state provider
final memberStateProvider =
    StateNotifierProvider<MemberStateNotifier, MemberState>((ref) {
  return MemberStateNotifier();
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

    // Initialize receipt verification service
    // TODO: Replace with your actual backend URL
    _receiptService.initialize(baseUrl: 'https://api.your-domain.com');

    // Initialize payment service
    await _paymentService.initialize(
      onPurchaseComplete: _handlePurchaseComplete,
      onPurchaseError: _handlePurchaseError,
    );

    // Load cached state
    await _loadCachedState();

    // Check backend for actual subscription status
    await _syncWithBackend();
  }

  /// Load cached subscription state from local storage
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

    // Check if expired
    if (state.isExpired) {
      await _clearVipStatus();
    }
  }

  /// Sync with backend to get actual subscription status
  Future<void> _syncWithBackend() async {
    // TODO: Get user ID from auth provider
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
      // Local cache is valid, keep it
    } else {
      // Not a subscriber or expired
      await _clearVipStatus();
    }
  }

  /// Handle successful purchase
  Future<void> _handlePurchaseComplete(PurchaseDetails purchase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // Prepare receipt data for verification
      final receiptData = {
        'purchase_id': purchase.purchaseID,
        'product_id': purchase.productID,
        'status': purchase.status.name,
        'transaction_date': purchase.transactionDate,
        'data': purchase.verificationData.localVerificationData,
        'server_verification_data': purchase.verificationData.serverVerificationData,
      };

      // Verify with backend
      final result = await _receiptService.verifyReceipt(
        receiptData: receiptData,
        platform: _paymentService.currentPlatform == TargetPlatform.android
            ? 'google_play'
            : 'app_store',
        userId: _prefs?.getString('user_id'),
      );

      if (result.isValid) {
        await _updateVipStatus(
          isVip: true,
          expireDate: result.expireDate ?? _calculateExpireDate(purchase),
          type: result.subscriptionType ?? _inferTypeFromProductId(purchase.productID),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.message ?? 'Verification failed',
        );
      }
    } catch (e) {
      debugPrint('Error handling purchase: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to process purchase',
      );
    }
  }

  /// Handle purchase error
  void _handlePurchaseError(String error) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: error,
    );
  }

  /// Update VIP status locally and on backend
  Future<void> _updateVipStatus({
    required bool isVip,
    DateTime? expireDate,
    String? type,
  }) async {
    // Update local cache
    await _prefs?.setBool('is_vip', isVip);
    if (expireDate != null) {
      await _prefs?.setString('vip_expire_date', expireDate.toIso8601String());
    }
    if (type != null) {
      await _prefs?.setString('subscription_type', type);
    }

    // Update state
    state = state.copyWith(
      isVip: isVip,
      expireDate: expireDate,
      subscriptionType: type,
      isLoading: false,
      errorMessage: null,
    );

    // Report to backend
    final userId = _prefs?.getString('user_id');
    if (userId != null && isVip) {
      await _receiptService.reportEvent(
        userId: userId,
        event: 'subscription_activated',
        data: {
          'type': type,
          'expire_date': expireDate?.toIso8601String(),
        },
      );
    }
  }

  /// Clear VIP status
  Future<void> _clearVipStatus() async {
    await _prefs?.remove('is_vip');
    await _prefs?.remove('vip_expire_date');
    await _prefs?.remove('subscription_type');

    state = const MemberState();
  }

  /// Restore purchases (for when user reinstalls app)
  Future<bool> restorePurchases() async {
    state = state.copyWith(isRestoring: true, errorMessage: null);

    try {
      final success = await _paymentService.restorePurchases();

      if (success) {
        // Wait a bit for the restore to process
        await Future.delayed(const Duration(seconds: 2));
        await _syncWithBackend();
      }

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

  /// Check if user can access a feature
  bool canAccess(Feature feature) {
    switch (feature) {
      case Feature.premiumContent:
      case Feature.adFree:
      case Feature.hdQuality:
      case Feature.offlineDownload:
      case Feature.earlyAccess:
        return state.isVip && !state.isExpired;
      case Feature.trialContent:
        return true; // Everyone can access trial content
    }
  }

  /// Get available products
  Future<List<ProductDetails>> getProducts() async {
    final productIds = SubscriptionProducts.products
        .map((p) => p.getProductId(_paymentService.currentPlatform))
        .toList();

    return await _paymentService.getProducts(productIds: productIds);
  }

  /// Make a purchase
  Future<bool> purchase(ProductDetails product) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    return await _paymentService.purchase(product: product);
  }

  /// Calculate expiration date from purchase
  DateTime _calculateExpireDate(PurchaseDetails purchase) {
    // TODO: Parse actual expiration from purchase data
    // For now, estimate based on product ID
    final type = _inferTypeFromProductId(purchase.productID);
    final days = _getDaysForType(type);
    return DateTime.now().add(Duration(days: days));
  }

  /// Infer subscription type from product ID
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

/// Features that require membership
enum Feature {
  premiumContent,
  adFree,
  hdQuality,
  offlineDownload,
  earlyAccess,
  trialContent,
}

/// Extension for feature descriptions
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

/// Provider for checking feature access
final featureAccessProvider = Provider.family<bool, Feature>((ref, feature) {
  final memberState = ref.watch(memberStateProvider);
  return memberState.isVip && !memberState.isExpired ||
      feature == Feature.trialContent;
});
