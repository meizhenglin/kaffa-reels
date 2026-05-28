import 'package:equatable/equatable.dart';

import 'banner.dart';
import 'drama.dart';

class RecommendFeed extends Equatable {
  const RecommendFeed({
    required this.banners,
    required this.hotDramas,
    required this.recommendedDramas,
    required this.hasMore,
    required this.page,
  });

  final List<BannerItem> banners;
  final List<Drama> hotDramas;
  final List<Drama> recommendedDramas;
  final bool hasMore;
  final int page;

  RecommendFeed copyWith({
    List<BannerItem>? banners,
    List<Drama>? hotDramas,
    List<Drama>? recommendedDramas,
    bool? hasMore,
    int? page,
  }) {
    return RecommendFeed(
      banners: banners ?? this.banners,
      hotDramas: hotDramas ?? this.hotDramas,
      recommendedDramas: recommendedDramas ?? this.recommendedDramas,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
    );
  }

  @override
  List<Object?> get props =>
      [banners, hotDramas, recommendedDramas, hasMore, page];
}
