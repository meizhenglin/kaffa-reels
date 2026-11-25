import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/build_flavor.dart';
import 'hai_pay_models.dart';

/// 当前环境是否应跳过渠道选择器、直接走应用商店内购。
///
/// 【为什么 iOS 也要跳过】
/// iOS 包用的是 platform 渠道，以前会弹「Google Play / HaiPay」选择器，
/// 用户选 HaiPay 就拉起 H5 支付 —— 虚拟商品绕开苹果支付违反 App Store
/// 审核 3.1.1，而且 App Store 收据链路（/notice/apple）也对不上。
/// 现在 iOS 的 StoreKit 内购已接通，所以 iOS 一律直接走内购：
///   - 会员：memberStateProvider.purchase → buyNonConsumable
///   - K币/解锁：rechargePurchaseHandler / GooglePlay 分支
///     （这两个在 iOS 上都会经 confirmStorePurchase 路由到 /notice/apple）
///
/// Android 平台渠道包与 Web 保持原有选择器（HaiPay 与商店并存）。
bool shouldUseStoreDirectly() {
  if (kIsWeb) return false;
  if (BuildFlavor.isGoogle) return true;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Payment channel types supported by the app
enum PaymentChannelKind { googlePlay, haiPay }

/// Payment channel that carries the chosen sub-method for HaiPay
class PaymentChannel extends Equatable {
  const PaymentChannel._({required this.kind, this.haiPayMethod});

  /// Google Play Billing (in-app purchase)
  const PaymentChannel.googlePlay()
    : this._(kind: PaymentChannelKind.googlePlay);

  /// HaiPay with a specific sub-method (Mada / STCPay / Credit Card / ...)
  factory PaymentChannel.haiPay(HaiPayMethod method) =>
      PaymentChannel._(kind: PaymentChannelKind.haiPay, haiPayMethod: method);

  /// Convenience factory preserved for backward compatibility (no method attached)
  factory PaymentChannel.haiPayLegacy() =>
      const PaymentChannel._(kind: PaymentChannelKind.haiPay);

  /// Creates the native or WebView channel represented by a backend method.
  factory PaymentChannel.fromHaiPayMethod(HaiPayMethod method) {
    if (method.isGooglePlay) return const PaymentChannel.googlePlay();
    return PaymentChannel.haiPay(method);
  }

  final PaymentChannelKind kind;
  final HaiPayMethod? haiPayMethod;

  bool get isGooglePlay => kind == PaymentChannelKind.googlePlay;
  bool get isHaiPay => kind == PaymentChannelKind.haiPay;

  /// Backwards-compat predicates
  // ignore: unused_element
  bool _matchGooglePlay() => isGooglePlay;
  // ignore: unused_element
  bool _matchHaiPay() => isHaiPay;

  @override
  List<Object?> get props => [kind, haiPayMethod];
}

/// Extension to provide display information for payment channels
extension PaymentChannelDisplay on PaymentChannel {
  String get id {
    switch (kind) {
      case PaymentChannelKind.googlePlay:
        return 'google_play';
      case PaymentChannelKind.haiPay:
        return 'hai_pay_${haiPayMethod?.id ?? 'unknown'}';
    }
  }

  String get displayName {
    switch (kind) {
      case PaymentChannelKind.googlePlay:
        return 'Google Play';
      case PaymentChannelKind.haiPay:
        final method = haiPayMethod;
        if (method == null) return 'HaiPay';
        return method.localizedName(_currentLocale);
    }
  }

  Locale get _currentLocale {
    // Best-effort: read locale from system without adding a context dependency
    try {
      return PlatformDispatcher.instance.locale;
    } catch (_) {
      return const Locale('en');
    }
  }

  String get description {
    switch (kind) {
      case PaymentChannelKind.googlePlay:
        return 'Pay securely via Google Play';
      case PaymentChannelKind.haiPay:
        final method = haiPayMethod;
        if (method == null) return 'Local payment methods';
        if (method.description.isNotEmpty) return method.description;
        return method.isExternalBrowser ? 'Opens in browser' : 'Opens in app';
    }
  }

  String get iconAsset {
    switch (kind) {
      case PaymentChannelKind.googlePlay:
        return 'assets/images/payment_google_play.png';
      case PaymentChannelKind.haiPay:
        return 'assets/images/payment_hai_pay.png';
    }
  }
}

/// Unified payment request that abstracts both Google Play and HaiPay
class UnifiedPaymentRequest extends Equatable {
  const UnifiedPaymentRequest({
    required this.channel,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.productName,
    this.productId,
    this.goodsId,
    this.videoId,
    this.episodeId,
    this.episodesNum,
  });

  /// Selected payment channel
  final PaymentChannel channel;

  /// Backend order ID (created before payment)
  final String orderId;

  /// Payment amount
  final String amount;

  /// Currency code (USD, SAR, AED, etc.)
  final String currency;

  /// Product name for display
  final String productName;

  /// Google Play product ID (for googlePlay channel)
  final String? productId;

  /// Backend goods ID
  final int? goodsId;

  /// Video ID (for episode unlock)
  final String? videoId;

  /// Episode ID (for episode unlock)
  final String? episodeId;

  /// Number of episodes (for episode unlock)
  final int? episodesNum;

  @override
  List<Object?> get props => [
    channel,
    orderId,
    amount,
    currency,
    productName,
    productId,
    goodsId,
    videoId,
    episodeId,
    episodesNum,
  ];
}

/// Unified payment result
class UnifiedPaymentResult extends Equatable {
  const UnifiedPaymentResult({
    required this.success,
    required this.channel,
    this.orderId,
    this.errorMessage,
    this.transactionId,
  });

  final bool success;
  final PaymentChannel channel;
  final String? orderId;
  final String? errorMessage;
  final String? transactionId;

  factory UnifiedPaymentResult.success({
    required PaymentChannel channel,
    required String orderId,
    String? transactionId,
  }) {
    return UnifiedPaymentResult(
      success: true,
      channel: channel,
      orderId: orderId,
      transactionId: transactionId,
    );
  }

  factory UnifiedPaymentResult.failed({
    required PaymentChannel channel,
    required String errorMessage,
    String? orderId,
  }) {
    return UnifiedPaymentResult(
      success: false,
      channel: channel,
      orderId: orderId,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    success,
    channel,
    orderId,
    errorMessage,
    transactionId,
  ];
}
