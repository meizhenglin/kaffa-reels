import 'package:equatable/equatable.dart';

/// Payment channel types supported by the app
enum PaymentChannel {
  /// Google Play Billing (in-app purchase)
  googlePlay,

  /// HaiPay H5 payment (web-based payment page)
  haiPay,
}

/// Extension to provide display information for payment channels
extension PaymentChannelExtension on PaymentChannel {
  String get id {
    switch (this) {
      case PaymentChannel.googlePlay:
        return 'google_play';
      case PaymentChannel.haiPay:
        return 'hai_pay';
    }
  }

  String get displayName {
    switch (this) {
      case PaymentChannel.googlePlay:
        return 'Google Play';
      case PaymentChannel.haiPay:
        return 'HaiPay';
    }
  }

  String get description {
    switch (this) {
      case PaymentChannel.googlePlay:
        return 'Pay securely via Google Play';
      case PaymentChannel.haiPay:
        return 'Local payment methods (Mada, STCPay, etc.)';
    }
  }

  String get iconAsset {
    switch (this) {
      case PaymentChannel.googlePlay:
        return 'assets/images/payment_google_play.png';
      case PaymentChannel.haiPay:
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
