import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'subscription_product.dart';

/// Recharge product model for coins/purchases
class RechargeProduct extends Equatable {
  const RechargeProduct({
    required this.goodsId,
    required this.googlePlayId,
    required this.iosProductId,
    required this.price,
    required this.coinAmount,
    required this.name,
    required this.sort,
    required this.isEnable,
    this.bonusAmount = 0,
    this.isPopular = false,
    this.isBestValue = false,
    this.description,
    this.displayAmount,
  });

  final int goodsId;
  final String googlePlayId;
  final String iosProductId;
  final String price;
  final int coinAmount;
  final int bonusAmount;
  final String name;
  final String? description;
  final String? displayAmount;
  final int sort;
  final bool isEnable;
  final bool isPopular;
  final bool isBestValue;

  int get totalAmount => coinAmount + bonusAmount;

  String getProductId(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return googlePlayId;
      case TargetPlatform.iOS:
        // 后台 goodsIosId 没配时兜底 Google ID：
        // App Store / Google Play 两边用的是同一套产品 ID。
        return iosProductId.isNotEmpty ? iosProductId : googlePlayId;
      default:
        return googlePlayId;
    }
  }

  factory RechargeProduct.fromGoodsConfig(RechargeGoodsConfigItem item) {
    return RechargeProduct(
      goodsId: item.goodsId,
      googlePlayId: item.goodsGoogleId,
      // iOS ID 缺省时兜底 Google ID（两边商店同 ID），避免 iOS 端查不到商品
      iosProductId: item.goodsIosId.isNotEmpty
          ? item.goodsIosId
          : item.goodsGoogleId,
      price: item.price,
      coinAmount: _parseCoinAmount(item),
      bonusAmount: item.rechargeGoodsGive,
      name: item.goodsName,
      description: item.description,
      displayAmount: item.description?.isNotEmpty == true
          ? item.description
          : item.goodsName,
      sort: item.sort,
      isEnable: item.isEnable,
    );
  }

  static int _parseCoinAmount(RechargeGoodsConfigItem item) {
    final sources = [item.description, item.goodsCode, item.goodsName];

    for (final source in sources) {
      if (source == null || source.isEmpty) continue;
      final match = RegExp(
        r'(\d+)\s*(?:coin|币|k)',
      ).firstMatch(source.toLowerCase());
      if (match != null) {
        return int.tryParse(match.group(1) ?? '') ?? 0;
      }
    }
    return 0;
  }

  @override
  List<Object?> get props => [
    goodsId,
    googlePlayId,
    iosProductId,
    price,
    coinAmount,
    bonusAmount,
    name,
    description,
    displayAmount,
  ];
}

/// Recharge products state
class RechargeProductsState {
  const RechargeProductsState({
    this.products = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hasLoaded = false,
  });

  final List<RechargeProduct> products;
  final bool isLoading;
  final String? errorMessage;
  final bool hasLoaded;

  RechargeProductsState copyWith({
    List<RechargeProduct>? products,
    bool? isLoading,
    String? errorMessage,
    bool? hasLoaded,
  }) {
    return RechargeProductsState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

/// Coin balance state
class CoinBalanceState {
  const CoinBalanceState({this.balance = 0, this.isLoading = false});

  final int balance;
  final bool isLoading;

  CoinBalanceState copyWith({int? balance, bool? isLoading}) {
    return CoinBalanceState(
      balance: balance ?? this.balance,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
