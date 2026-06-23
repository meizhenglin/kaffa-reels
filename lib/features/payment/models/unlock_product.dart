import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'recharge_product.dart';

/// 包含当前剧集的解锁价格信息和可选商品列表
class UnlockConfig extends Equatable {
  const UnlockConfig({
    required this.videoId,
    required this.episodeUnlockPrice,
    this.dramaUnlockPrice,
    this.episodeUnlockGoodsId,
    this.dramaUnlockGoodsId,
    this.vipProducts = const [],
    this.coinProducts = const [],
    this.episodeUnlockProducts = const [],
    this.dramaUnlockProducts = const [],
    this.allProducts = const [],
  });

  final String videoId;
  final double episodeUnlockPrice;
  final double? dramaUnlockPrice;
  final int? episodeUnlockGoodsId;
  final int? dramaUnlockGoodsId;
  final List<UnlockProduct> vipProducts;
  final List<UnlockProduct> coinProducts;
  final List<UnlockProduct> episodeUnlockProducts;
  final List<UnlockProduct> dramaUnlockProducts;
  final List<UnlockProduct> allProducts;

  @override
  List<Object?> get props => [
        videoId,
        episodeUnlockPrice,
        dramaUnlockPrice,
        episodeUnlockGoodsId,
        dramaUnlockGoodsId,
        vipProducts,
        coinProducts,
        episodeUnlockProducts,
        dramaUnlockProducts,
        allProducts,
      ];
}

/// 解锁商品类型
enum UnlockProductType {
  vip,
  episode,
  season,
}

/// 解锁商品模型
class UnlockProduct extends Equatable {
  const UnlockProduct({
    required this.goodsId,
    required this.goodsName,
    required this.price,
    required this.type,
    this.originalPrice,
    this.isBestValue = false,
    this.isPopular = false,
    this.googlePlayId,
    this.iosProductId,
  });

  final int goodsId;
  final String goodsName;
  final double price;
  final UnlockProductType type;
  final double? originalPrice;
  final bool isBestValue;
  final bool isPopular;

  /// Google Play 商品ID
  final String? googlePlayId;
  /// iOS 商品ID
  final String? iosProductId;

  bool get hasDiscount => originalPrice != null && originalPrice! > price;

  /// 从 RechargeProduct 转换
  factory UnlockProduct.fromRechargeProduct(RechargeProduct product, UnlockProductType type) {
    final priceValue = double.tryParse(product.price) ?? 0.0;
    return UnlockProduct(
      goodsId: product.goodsId,
      goodsName: product.name,
      price: priceValue,
      type: type,
      isBestValue: product.isBestValue,
      isPopular: product.isPopular,
      googlePlayId: product.googlePlayId,
      iosProductId: product.iosProductId,
    );
  }

  /// 转换为 RechargeProduct（用于走谷歌支付）
  RechargeProduct toRechargeProduct() {
    return RechargeProduct(
      goodsId: goodsId,
      googlePlayId: googlePlayId ?? '',
      iosProductId: iosProductId ?? '',
      price: price.toString(),
      coinAmount: price.toInt(),
      name: goodsName,
      sort: 0,
      isEnable: true,
    );
  }

  String getProductId(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return googlePlayId ?? '';
      case TargetPlatform.iOS:
        return iosProductId ?? '';
      default:
        return googlePlayId ?? '';
    }
  }

  @override
  List<Object?> get props => [goodsId, goodsName, price, type];
}

/// 解锁结果
enum UnlockResultType {
  success,
  failed,
  cancelled,
  loginRequired,  // 需要登录
}

class UnlockResult {
  const UnlockResult._({
    required this.resultType,
    this.episodeIndex,
    this.errorMessage,
  });

  factory UnlockResult.success({required int episodeIndex}) {
    return UnlockResult._(
      resultType: UnlockResultType.success,
      episodeIndex: episodeIndex,
    );
  }

  factory UnlockResult.failed({String? message}) {
    return UnlockResult._(
      resultType: UnlockResultType.failed,
      errorMessage: message,
    );
  }

  factory UnlockResult.cancelled() {
    return const UnlockResult._(resultType: UnlockResultType.cancelled);
  }

  factory UnlockResult.loginRequired() {
    return const UnlockResult._(resultType: UnlockResultType.loginRequired);
  }

  final UnlockResultType resultType;
  final int? episodeIndex;
  final String? errorMessage;

  bool get isSuccess => resultType == UnlockResultType.success;
  bool get isFailed => resultType == UnlockResultType.failed;
  bool get isCancelled => resultType == UnlockResultType.cancelled;
  bool get isLoginRequired => resultType == UnlockResultType.loginRequired;
}

/// 解锁商品列表状态
class UnlockProductsState {
  const UnlockProductsState({
    this.products = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<UnlockProduct> products;
  final bool isLoading;
  final String? errorMessage;

  UnlockProductsState copyWith({
    List<UnlockProduct>? products,
    bool? isLoading,
    String? errorMessage,
  }) {
    return UnlockProductsState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
