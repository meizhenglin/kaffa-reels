import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Subscription period type
enum SubscriptionPeriod {
  monthly,
  quarterly,
  yearly,
}

/// Subscription tier/level
enum SubscriptionTier {
  none,
  monthly,
  quarterly,
  yearly,
}

extension SubscriptionPeriodExt on SubscriptionPeriod {
  String get displayName {
    switch (this) {
      case SubscriptionPeriod.monthly:
        return 'Monthly';
      case SubscriptionPeriod.quarterly:
        return 'Quarterly';
      case SubscriptionPeriod.yearly:
        return 'Yearly';
    }
  }

  String get displayNameCn {
    switch (this) {
      case SubscriptionPeriod.monthly:
        return '月卡';
      case SubscriptionPeriod.quarterly:
        return '季卡';
      case SubscriptionPeriod.yearly:
        return '年卡';
    }
  }

  int get durationInDays {
    switch (this) {
      case SubscriptionPeriod.monthly:
        return 30;
      case SubscriptionPeriod.quarterly:
        return 90;
      case SubscriptionPeriod.yearly:
        return 365;
    }
  }
}

extension SubscriptionTierExt on SubscriptionTier {
  int get priority {
    switch (this) {
      case SubscriptionTier.none:
        return 0;
      case SubscriptionTier.monthly:
        return 1;
      case SubscriptionTier.quarterly:
        return 2;
      case SubscriptionTier.yearly:
        return 3;
    }
  }

  bool get isVip => this != SubscriptionTier.none;
}

/// Subscription product definition
class SubscriptionProduct extends Equatable {
  const SubscriptionProduct({
    required this.id,
    required this.type,
    required this.googlePlayId,
    required this.appStoreId,
    required this.price,
    required this.priceCn,
    required this.originalPrice,
    required this.originalPriceCn,
    required this.benefits,
    this.isPopular = false,
    this.isBestValue = false,
  });

  /// Unique product identifier
  final String id;

  /// Subscription period type
  final SubscriptionPeriod type;

  /// Google Play product ID (must match Play Console)
  final String googlePlayId;

  /// App Store product ID (must match App Store Connect)
  final String appStoreId;

  /// Price string (e.g., "$4.99")
  final String price;

  /// Price in CNY
  final String priceCn;

  /// Original price (for showing discount)
  final String originalPrice;

  /// Original price in CNY
  final String originalPriceCn;

  /// List of benefits for this tier
  final List<String> benefits;

  /// Whether this is a popular choice
  final bool isPopular;

  /// Whether this offers the best value
  final bool isBestValue;

  /// Get platform-specific product ID
  String getProductId(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return googlePlayId;
      case TargetPlatform.iOS:
        return appStoreId;
      default:
        return googlePlayId;
    }
  }

  @override
  List<Object?> get props => [
        id,
        type,
        googlePlayId,
        appStoreId,
        price,
        priceCn,
        originalPrice,
        originalPriceCn,
        benefits,
        isPopular,
        isBestValue,
      ];
}

/// Member benefits configuration
class MemberBenefits {
  static const freeTier = [
    'Watch ad-supported content',
    'Standard video quality (480p)',
    'Limited drama library',
    'No downloads',
  ];

  static const vipTier = [
    'Ad-free viewing experience',
    'HD/4K video quality',
    'Full drama library access',
    'Exclusive member-only content',
    'Early access to new releases',
    'Offline downloads',
    'Priority customer support',
  ];

  static const freeTierCn = [
    '观看广告内容',
    '标准画质 (480p)',
    '有限剧库',
    '不支持下载',
  ];

  static const vipTierCn = [
    '无广告观看体验',
    '高清/4K 画质',
    '完整剧库访问',
    '会员专享内容',
    '新剧抢先看',
    '离线下载',
    '优先客服支持',
  ];
}

/// Default subscription products
class SubscriptionProducts {
  SubscriptionProducts._();

  // NOTE: Replace these IDs with your actual product IDs from Play Console/App Store Connect
  static const _googlePlayBase = 'com.qahwatv.vip.';
  static const _appStoreBase = 'com.qahwatv.vip.';

  static final List<SubscriptionProduct> products = [
    SubscriptionProduct(
      id: 'monthly',
      type: SubscriptionPeriod.monthly,
      googlePlayId: '${_googlePlayBase}monthly',
      appStoreId: '${_appStoreBase}monthly',
      price: '\$4.99',
      priceCn: '¥30',
      originalPrice: '\$9.99',
      originalPriceCn: '¥60',
      benefits: const [
        'Ad-free for 1 month',
        'HD quality',
        'Full library access',
      ],
      isPopular: true,
    ),
    SubscriptionProduct(
      id: 'quarterly',
      type: SubscriptionPeriod.quarterly,
      googlePlayId: '${_googlePlayBase}quarterly',
      appStoreId: '${_appStoreBase}quarterly',
      price: '\$12.99',
      priceCn: '¥78',
      originalPrice: '\$24.99',
      originalPriceCn: '¥150',
      benefits: const [
        'Ad-free for 3 months',
        'HD quality',
        'Full library access',
        'Save 40%',
      ],
      isBestValue: true,
    ),
    SubscriptionProduct(
      id: 'yearly',
      type: SubscriptionPeriod.yearly,
      googlePlayId: '${_googlePlayBase}yearly',
      appStoreId: '${_appStoreBase}yearly',
      price: '\$39.99',
      priceCn: '¥258',
      originalPrice: '\$99.99',
      originalPriceCn: '¥598',
      benefits: const [
        'Ad-free for 12 months',
        '4K quality',
        'Full library access',
        'Save 60%',
      ],
    ),
  ];

  static SubscriptionProduct? getById(String id) {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  static SubscriptionProduct? getBestValue() {
    try {
      return products.firstWhere((p) => p.isBestValue);
    } catch (_) {
      return products.isNotEmpty ? products.first : null;
    }
  }
}
