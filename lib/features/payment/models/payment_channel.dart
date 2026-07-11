import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'hai_pay_models.dart';

/// Payment channel types supported by the app
enum PaymentChannelKind {
  googlePlay,
  haiPay,
}

/// Payment channel that carries the chosen sub-method for HaiPay
class PaymentChannel extends Equatable {
  const PaymentChannel._({required this.kind, this.haiPayMethod});

  /// Google Play Billing (in-app purchase)
  const PaymentChannel.googlePlay() : this._(kind: PaymentChannelKind.googlePlay);

  /// HaiPay with a specific sub-method (Mada / STCPay / Credit Card / ...)
  factory PaymentChannel.haiPay(HaiPayMethod method) =>
      PaymentChannel._(kind: PaymentChannelKind.haiPay, haiPayMethod: method);

  /// Convenience factory preserved for backward compatibility (no method attached)
  factory PaymentChannel.haiPayLegacy() =>
      const PaymentChannel._(kind: PaymentChannelKind.haiPay);

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
  List<Object?> get props => [success, channel, orderId, errorMessage, transactionId];
}
