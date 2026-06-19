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
export '../models/subscription_product.dart' show RechargeGoodsConfigItem;

/// Recharge purchase handler for consumables
class RechargePurchaseHandler {
  RechargePurchaseHandler(this._ref);

  final Ref _ref;

  /// Last error message
  String? lastError;

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
      lastError = 'Product not available in Google Play';
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
      return false;
    }

    final product = pendingProduct!;
    pendingProduct = null;

    final paymentService = PaymentService.instance;

    // Consume the purchase
    final consumed = await paymentService.handleConsumablePurchase(purchase);
    if (!consumed) {
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
        // Recharge callback successful - parse coin amount from response
        final responseData = response.data;
        if (responseData is Map) {
          final coinAmount = responseData['coinAmount'] ??
                             responseData['amount'] ??
                             responseData['rechargeAmount'] ?? 0;
          final coinNotifier = _ref.read(coinBalanceProvider.notifier);
          await coinNotifier.addCoins(coinAmount as int);
        }
        return true;
      }
    } catch (e) {
      // Silently handle callback errors
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

  Future<void> deductCoins(int amount) async {
    final newBalance = (state.balance - amount).clamp(0, state.balance);
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
