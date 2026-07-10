import 'package:equatable/equatable.dart';
import 'payment_channel.dart';

/// Payment method from HaiPay backend (equivalent to Android's PaytypeBean)
class HaiPayMethod extends Equatable {
  const HaiPayMethod({
    required this.id,
    required this.name,
    required this.img,
    required this.jumpType,
  });

  /// Payment method ID
  final int id;

  /// Display name (e.g., "Mada", "STCPay", "Credit Card")
  final String name;

  /// Icon URL or asset path
  final String img;

  /// 1 = in-app WebView, 2 = external browser
  final int jumpType;

  /// Whether this opens in external browser
  bool get isExternalBrowser => jumpType == 2;

  /// Whether this opens in in-app WebView
  bool get isInAppWebView => jumpType == 1;

  factory HaiPayMethod.fromJson(Map<String, dynamic> json) {
    return HaiPayMethod(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      img: json['img'] as String? ?? '',
      jumpType: json['jumpType'] as int? ?? 1,
    );
  }

  @override
  List<Object?> get props => [id, name, img, jumpType];
}

/// HaiPay order response (equivalent to Android's PayInfoBean)
class HaiPayOrder extends Equatable {
  const HaiPayOrder({
    required this.payInfo,
    required this.orderNo,
  });

  /// H5 payment URL to open
  final String payInfo;

  /// Backend order number
  final String orderNo;

  factory HaiPayOrder.fromJson(Map<String, dynamic> json) {
    return HaiPayOrder(
      payInfo: json['payInfo'] as String? ?? '',
      orderNo: json['orderNo'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [payInfo, orderNo];
}

/// HaiPay payment status poll result (equivalent to Android's PayReaBean)
class HaiPayStatus extends Equatable {
  const HaiPayStatus({
    required this.isPay,
  });

  /// "1" = unpaid, "0" = paid
  final String isPay;

  bool get isPaid => isPay == '0';
  bool get isUnpaid => isPay == '1';

  factory HaiPayStatus.fromJson(Map<String, dynamic> json) {
    return HaiPayStatus(
      isPay: json['isPay'] as String? ?? '1',
    );
  }

  @override
  List<Object?> get props => [isPay];
}

/// Backend payment method list response
class HaiPayMethodsResponse extends Equatable {
  const HaiPayMethodsResponse({
    required this.methods,
  });

  final List<HaiPayMethod> methods;

  /// Pre-defined payment methods that are always available as fallback
  static const List<HaiPayMethod> fallbackMethods = [
    HaiPayMethod(
      id: 1,
      name: 'Credit Card',
      img: '',
      jumpType: 1,
    ),
    HaiPayMethod(
      id: 2,
      name: 'Mada',
      img: '',
      jumpType: 1,
    ),
    HaiPayMethod(
      id: 3,
      name: 'STCPay',
      img: '',
      jumpType: 1,
    ),
  ];

  factory HaiPayMethodsResponse.fromJson(dynamic data) {
    List<HaiPayMethod> methods = [];
    if (data is List) {
      methods = data.map((e) => HaiPayMethod.fromJson(e as Map<String, dynamic>)).toList();
    }
    return HaiPayMethodsResponse(methods: methods);
  }

  @override
  List<Object?> get props => [methods];
}
