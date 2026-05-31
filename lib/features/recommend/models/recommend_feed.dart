import 'package:equatable/equatable.dart';

import 'banner.dart';
import 'drama.dart';

/// 首页推荐数据模型
/// 字段对应 /api/episodes/recommendIndex 返回的 bannerList / hotPicksList / chartsList / newEpisodesList
class RecommendFeed extends Equatable {
  const RecommendFeed({
    required this.banners,
    required this.hotPicks,
    required this.charts,
    required this.newEpisodes,
    required this.hasMore,
    required this.page,
  });

  /// 轮播图列表
  final List<BannerItem> banners;
  /// 热门精选列表
  final List<Drama> hotPicks;
  /// 排行榜列表
  final List<Drama> charts;
  /// 最新剧集列表
  final List<Drama> newEpisodes;
  final bool hasMore;
  final int page;

  RecommendFeed copyWith({
    List<BannerItem>? banners,
    List<Drama>? hotPicks,
    List<Drama>? charts,
    List<Drama>? newEpisodes,
    bool? hasMore,
    int? page,
  }) {
    return RecommendFeed(
      banners: banners ?? this.banners,
      hotPicks: hotPicks ?? this.hotPicks,
      charts: charts ?? this.charts,
      newEpisodes: newEpisodes ?? this.newEpisodes,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
    );
  }

  @override
  List<Object?> get props => [banners, hotPicks, charts, newEpisodes, hasMore, page];
}
