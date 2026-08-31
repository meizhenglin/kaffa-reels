import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Subscription period type
enum SubscriptionPeriod { monthly, quarterly, yearly }

/// Subscription tier/level
enum SubscriptionTier { none, monthly, quarterly, yearly }

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
    this.displayName,
    this.isPopular = false,
    this.isBestValue = false,
    this.goodsId,
    this.sort,
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

  /// Display name from backend
  final String? displayName;

  /// Whether this is a popular choice
  final bool isPopular;

  /// Whether this offers the best value
  final bool isBestValue;

  /// Backend goods id
  final int? goodsId;

  /// Backend sort order
  final int? sort;

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

  SubscriptionProduct copyWith({
    String? id,
    SubscriptionPeriod? type,
    String? googlePlayId,
    String? appStoreId,
    String? price,
    String? priceCn,
    String? originalPrice,
    String? originalPriceCn,
    List<String>? benefits,
    String? displayName,
    bool? isPopular,
    bool? isBestValue,
    int? goodsId,
    int? sort,
  }) {
    return SubscriptionProduct(
      id: id ?? this.id,
      type: type ?? this.type,
      googlePlayId: googlePlayId ?? this.googlePlayId,
      appStoreId: appStoreId ?? this.appStoreId,
      price: price ?? this.price,
      priceCn: priceCn ?? this.priceCn,
      originalPrice: originalPrice ?? this.originalPrice,
      originalPriceCn: originalPriceCn ?? this.originalPriceCn,
      benefits: benefits ?? this.benefits,
      displayName: displayName ?? this.displayName,
      isPopular: isPopular ?? this.isPopular,
      isBestValue: isBestValue ?? this.isBestValue,
      goodsId: goodsId ?? this.goodsId,
      sort: sort ?? this.sort,
    );
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
    displayName,
    isPopular,
    isBestValue,
    goodsId,
    sort,
  ];
}

class RechargeGoodsConfigItem extends Equatable {
  const RechargeGoodsConfigItem({
    required this.goodsId,
    required this.rechargeGoodsType,
    required this.goodsName,
    required this.goodsGoogleId,
    required this.goodsIosId,
    required this.price,
    required this.originalPrice,
    required this.sort,
    required this.isEnable,
    this.rechargeGoodsGive = 0,
    this.description,
    this.goodsCode,
  });

  final int goodsId;
  final int rechargeGoodsType;
  final String goodsName;
  final String goodsGoogleId;
  final String goodsIosId;
  final String price;
  final String originalPrice;
  final int sort;
  final bool isEnable;
  final int rechargeGoodsGive;
  final String? description;
  final String? goodsCode;

  factory RechargeGoodsConfigItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, [int fallback = 0]) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    String readString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        final str = value?.toString().trim();
        if (str != null && str.isNotEmpty && str.toLowerCase() != 'null') {
          return str;
        }
      }
      return '';
    }

    return RechargeGoodsConfigItem(
      goodsId: parseInt(json['goodsId'] ?? json['id']),
      rechargeGoodsType: parseInt(json['rechargeGoodsType']),
      goodsName: readString([
        'rechargeGoodsName',
        'goodsName',
        'title',
        'name',
      ]),
      goodsGoogleId: readString([
        'remarks',
        'goodsGoogleId',
        'googlePlayId',
        'googleProductId',
        'productId',
      ]),
      goodsIosId: readString(['goodsIosId', 'appStoreId', 'iosProductId']),
      price: readString([
        'rechargeGoodsPrice',
        'price',
        'goodsPrice',
        'amount',
      ]),
      originalPrice: readString([
        'rechargeGoodsSubname',
        'originalPrice',
        'linePrice',
        'goodsOriginalPrice',
      ]),
      sort: parseInt(json['rechargeGoodsSort'] ?? json['sort'], 999),
      isEnable: parseBool(
        json['isEnable'] ??
            json['status'] ??
            ((json['isDelete'] ?? 0) == 0 ? 1 : 0),
      ),
      rechargeGoodsGive: parseInt(json['rechargeGoodsGive']),
      description:
          readString([
            'rechargeGoodsSubname2',
            'description',
            'desc',
            'remark',
          ]).isEmpty
          ? null
          : readString([
              'rechargeGoodsSubname2',
              'description',
              'desc',
              'remark',
            ]),
      goodsCode: readString(['goodsCode', 'code', 'remarks']).isEmpty
          ? null
          : readString(['goodsCode', 'code', 'remarks']),
    );
  }

  @override
  List<Object?> get props => [
    goodsId,
    rechargeGoodsType,
    goodsName,
    goodsGoogleId,
    goodsIosId,
    price,
    originalPrice,
    sort,
    isEnable,
    rechargeGoodsGive,
    description,
    goodsCode,
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

  static const freeTierCn = ['观看广告内容', '标准画质 (480p)', '有限剧库', '不支持下载'];

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

  // Google Play Console 产品 ID（必须和 Google Play 后台一致）
  static const _googlePlayBase = 'com.qahwa.vip';
  static const _appStoreBase = 'com.qahwa.vip';

  static final List<SubscriptionProduct> fallbackProducts = [
    SubscriptionProduct(
      id: 'vip1',
      type: SubscriptionPeriod.monthly,
      googlePlayId: '$_googlePlayBase.1', // com.qahwa.vip.1
      appStoreId: '$_appStoreBase.1',
      price: r'$24.99',
      priceCn: '¥30',
      originalPrice: r'$39.99',
      originalPriceCn: '¥60',
      benefits: const [
        'Ad-free for 1 month',
        'HD quality',
        'Full library access',
      ],
      isPopular: true,
      displayName: 'Monthly VIP',
    ),
    SubscriptionProduct(
      id: 'vip2',
      type: SubscriptionPeriod.quarterly,
      googlePlayId: '$_googlePlayBase.2', // com.qahwa.vip.2
      appStoreId: '$_appStoreBase.2',
      price: r'$32.99',
      priceCn: '¥78',
      originalPrice: r'$59.99',
      originalPriceCn: '¥150',
      benefits: const [
        'Ad-free for 3 months',
        'HD quality',
        'Full library access',
        'Save 40%',
      ],
      isBestValue: true,
      displayName: 'Quarterly VIP',
    ),
    SubscriptionProduct(
      id: 'vip3',
      type: SubscriptionPeriod.yearly,
      googlePlayId: '$_googlePlayBase.3', // com.qahwa.vip.3
      appStoreId: '$_appStoreBase.3',
      price: r'$99.99',
      priceCn: '¥258',
      originalPrice: r'$159.99',
      originalPriceCn: '¥598',
      benefits: const [
        'Ad-free for 12 months',
        '4K quality',
        'Full library access',
        'Save 60%',
      ],
      displayName: 'Yearly VIP',
    ),
  ];

  static List<SubscriptionProduct> fromRechargeGoods(
    List<RechargeGoodsConfigItem> items,
  ) {
    if (items.isEmpty) return fallbackProducts;

    final enabledItems = items.where((item) => item.isEnable).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));

    if (enabledItems.isEmpty) return fallbackProducts;

    return List<SubscriptionProduct>.generate(enabledItems.length, (index) {
      final item = enabledItems[index];
      final type = _inferPeriod(item);
      return SubscriptionProduct(
        id: item.goodsCode?.isNotEmpty == true
            ? item.goodsCode!
            : _buildId(item, type, index),
        type: type,
        googlePlayId: item.goodsGoogleId,
        appStoreId: item.goodsIosId.isNotEmpty
            ? item.goodsIosId
            : item.goodsGoogleId,
        price: _formatPrice(item.price),
        priceCn: _formatPrice(item.price),
        originalPrice: item.originalPrice.isNotEmpty
            ? _formatPrice(item.originalPrice)
            : '',
        originalPriceCn: item.originalPrice.isNotEmpty
            ? _formatPrice(item.originalPrice)
            : '',
        benefits: _buildBenefits(type),
        displayName: item.goodsName.isNotEmpty ? item.goodsName : null,
        isPopular: index == 0,
        isBestValue: index == 1 || type == SubscriptionPeriod.quarterly,
        goodsId: item.goodsId,
        sort: item.sort,
      );
    });
  }

  static SubscriptionPeriod _inferPeriod(RechargeGoodsConfigItem item) {
    final source = [
      item.goodsName,
      item.goodsCode ?? '',
      item.goodsGoogleId,
      item.goodsIosId,
      item.description ?? '',
    ].join(' ').toLowerCase();

    if (source.contains('year') ||
        source.contains('annual') ||
        source.contains('12')) {
      return SubscriptionPeriod.yearly;
    }
    if (source.contains('quarter') ||
        source.contains('season') ||
        source.contains('3 month')) {
      return SubscriptionPeriod.quarterly;
    }
    return SubscriptionPeriod.monthly;
  }

  static String _buildId(
    RechargeGoodsConfigItem item,
    SubscriptionPeriod type,
    int index,
  ) {
    if (item.goodsId > 0) return 'goods_${item.goodsId}';
    switch (type) {
      case SubscriptionPeriod.monthly:
        return 'monthly_$index';
      case SubscriptionPeriod.quarterly:
        return 'quarterly_$index';
      case SubscriptionPeriod.yearly:
        return 'yearly_$index';
    }
  }

  static String _formatPrice(String value) {
    final cleaned = value.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E]'),
      '',
    );
    final trimmed = cleaned.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith(r'$') ||
        trimmed.startsWith('¥') ||
        trimmed.startsWith('€') ||
        trimmed.startsWith('£')) {
      return trimmed;
    }
    return r'$' + trimmed;
  }

  static List<String> _buildBenefits(SubscriptionPeriod type) {
    switch (type) {
      case SubscriptionPeriod.monthly:
        return const [
          'Ad-free for 1 month',
          'HD quality',
          'Full library access',
        ];
      case SubscriptionPeriod.quarterly:
        return const [
          'Ad-free for 3 months',
          'HD quality',
          'Full library access',
          'Save more',
        ];
      case SubscriptionPeriod.yearly:
        return const [
          'Ad-free for 12 months',
          '4K quality',
          'Full library access',
          'Best annual price',
        ];
    }
  }
}
