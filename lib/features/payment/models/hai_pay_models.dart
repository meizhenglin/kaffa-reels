import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Payment method from HaiPay backend (equivalent to Android's PaytypeBean)
class HaiPayMethod extends Equatable {
  const HaiPayMethod({
    required this.id,
    required this.name,
    required this.icon,
    required this.payType,
    required this.inBankCode,
    required this.countryCode,
    required this.description,
    required this.nameI18n,
    this.jumpType = 1,
  });

  /// Payment method ID
  final int id;

  /// Backend raw name (e.g. "STCPAY", "CARD_PAYMENT", "HAIPAY_STCPAY")
  final String name;

  /// Icon URL or asset path (relative to backend base, e.g. "/uploads/pay/stcpay.png")
  final String icon;

  /// Backend `payType` (e.g. "PAYMENT_GATEWAY")
  final String payType;

  /// Bank/channel identifier (e.g. "STCPAY", "CARD")
  final String inBankCode;

  /// ISO country code (e.g. "SAR")
  final String countryCode;

  /// Human-readable description
  final String description;

  /// Localized display names: { "zh-CN": ..., "en-US": ..., "ar-SA": ... }
  final Map<String, String> nameI18n;

  /// 1 = in-app WebView, 2 = external browser (kept for compat; backend
  /// currently has no `jumpType` so default to 1)
  final int jumpType;

  /// Whether this opens in external browser
  bool get isExternalBrowser => jumpType == 2;

  /// Whether this opens in in-app WebView
  bool get isInAppWebView => jumpType == 1;

  /// True when this backend method represents Google Play Billing.
  ///
  /// The backend may identify it through any of the payment method fields.
  /// Matching is intentionally limited to Google/Play/Billing tokens so a
  /// normal HaiPay method cannot be routed into native billing by accident.
  bool get isGooglePlay {
    final values = [name, payType, inBankCode].map(
      (value) => value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_'),
    );
    return values.any(
      (value) =>
          value.contains('google_play') ||
          value.contains('googleplay') ||
          value == 'google' ||
          value == 'play_billing' ||
          value == 'billing',
    );
  }

  /// True if this method is routed through HaiPay (`HAIPAY_*` ids in our backend)
  bool get isHaiPayRouted =>
      !isGooglePlay &&
      (name.startsWith('HAIPAY_') || inBankCode.startsWith('HAIPAY_'));

  /// Resolve the best display name for the given locale.
  /// Falls back to English, then backend raw name.
  String localizedName(Locale locale) {
    // Try exact language-region match first
    final tag = _tagFor(locale);
    final exact = nameI18n[tag];
    if (exact != null && exact.isNotEmpty) return exact;

    // Try language-only match (e.g. "ar")
    final lang = locale.languageCode;
    for (final entry in nameI18n.entries) {
      if (entry.key.toLowerCase().startsWith('${lang.toLowerCase()}-') ||
          entry.key.toLowerCase() == lang.toLowerCase()) {
        if (entry.value.isNotEmpty) return entry.value;
      }
    }

    // English fallback
    final en = nameI18n['en-US'] ?? nameI18n['en'];
    if (en != null && en.isNotEmpty) return en;

    return name;
  }

  String _tagFor(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    final region = (locale.countryCode ?? '').toUpperCase();
    switch (lang) {
      case 'zh':
        return region.isNotEmpty ? 'zh-$region' : 'zh-CN';
      case 'ar':
        return region.isNotEmpty ? 'ar-$region' : 'ar-SA';
      case 'en':
      default:
        return region.isNotEmpty ? 'en-$region' : 'en-US';
    }
  }

  factory HaiPayMethod.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String? ?? '';
    final rawI18n = json['nameI18n'];
    final i18n = <String, String>{};
    if (rawI18n is Map) {
      rawI18n.forEach((k, v) {
        if (k is String && v is String) i18n[k] = v;
      });
    }

    return HaiPayMethod(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: rawName,
      icon: json['icon'] as String? ?? json['img'] as String? ?? '',
      payType: json['payType'] as String? ?? '',
      inBankCode: json['inBankCode'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      description: json['description'] as String? ?? '',
      nameI18n: i18n,
      jumpType: (json['jumpType'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    icon,
    payType,
    inBankCode,
    countryCode,
    description,
  ];
}

/// HaiPay order response (returned by POST /api/pay/userRechange and /api/pay/initPay)
class HaiPayOrder extends Equatable {
  const HaiPayOrder({
    required this.payInfo,
    required this.orderNo,
    this.merchantOrderNo = '',
  });

  /// H5 payment URL to open (`payUrl` field from backend)
  final String payInfo;

  /// HaiPay (HiPay) platform order number
  final String orderNo;

  /// Merchant-side order number returned by backend
  final String merchantOrderNo;

  factory HaiPayOrder.fromJson(Map<String, dynamic> json) {
    return HaiPayOrder(
      payInfo: json['payUrl'] as String? ?? json['payInfo'] as String? ?? '',
      orderNo: json['orderNo'] as String? ?? '',
      merchantOrderNo: json['merchantOrderNo'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [payInfo, orderNo, merchantOrderNo];
}

/// HaiPay payment status poll result (equivalent to Android's PayReaBean)
class HaiPayStatus extends Equatable {
  const HaiPayStatus({required this.isPay});

  /// "1" = unpaid, "0" = paid
  final String isPay;

  /// 统一约定：isPay == '1' → 已支付（true），isPay == '0' → 未支付（false）
  /// 与后端 isPaid 惯例一致：isPaid=1 = paid，isPaid=0 = unpaid
  bool get isPaid => isPay == '1';
  bool get isUnpaid => isPay == '0';

  factory HaiPayStatus.fromJson(Map<String, dynamic> json) {
    // 优先取 isPay（字符串），fallback 到 isPaid（整数，0/1）
    final rawIsPay = json['isPay'] ?? json['isPaid'];
    if (rawIsPay == null) return const HaiPayStatus(isPay: '1');
    // isPaid 可能是 int (0/1) 也可能是 string ('0'/'1')，统一转 string
    return HaiPayStatus(isPay: rawIsPay.toString());
  }

  @override
  List<Object?> get props => [isPay];
}

/// Backend payment method list response
class HaiPayMethodsResponse extends Equatable {
  const HaiPayMethodsResponse({required this.methods});

  final List<HaiPayMethod> methods;

  /// Pre-defined payment methods that are always available as fallback
  static const List<HaiPayMethod> fallbackMethods = [
    HaiPayMethod(
      id: 1,
      name: 'CARD_PAYMENT',
      icon: '',
      payType: 'PAYMENT_GATEWAY',
      inBankCode: 'CARD',
      countryCode: 'SAR',
      description: 'Credit/Debit card payment',
      nameI18n: {'en-US': 'Credit/Debit Card', 'ar-SA': 'بطاقة ائتمان/خصم'},
    ),
    HaiPayMethod(
      id: 2,
      name: 'STCPAY',
      icon: '',
      payType: 'PAYMENT_GATEWAY',
      inBankCode: 'STCPAY',
      countryCode: 'SAR',
      description: 'STC Pay electronic payment',
      nameI18n: {'en-US': 'STC Pay', 'ar-SA': 'STC باي'},
    ),
  ];

  factory HaiPayMethodsResponse.fromJson(dynamic data) {
    List<HaiPayMethod> methods = [];
    if (data is List) {
      methods = data
          .map((e) => HaiPayMethod.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return HaiPayMethodsResponse(methods: methods);
  }

  @override
  List<Object?> get props => [methods];
}
