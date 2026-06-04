import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../data/recommend_repository.dart';
import '../models/banner.dart';
import '../models/drama.dart';
import '../models/video_info.dart';

/// ============================================================================
/// 推荐模块状态管理
///
/// 【功能说明】
/// 管理推荐页面的所有数据状态：
/// - Banner 轮播数据
/// - 热门精选列表
/// - 排行榜列表
/// - 最新剧集列表（瀑布流）
/// - 分页加载状态
///
/// 【数据来源】
/// 数据从 /api/episodes/recommendIndex 获取
/// 参见 recommend_repository.dart
/// ============================================================================

/// 推荐数据加载状态枚举
enum RecommendStatus {
  /// 初始状态（未加载）
  initial,
  /// 加载中
  loading,
  /// 加载成功
  success,
  /// 加载失败
  error,
}

/// 推荐页面状态数据类
class RecommendState {
  const RecommendState({
    this.status = RecommendStatus.initial,
    this.banners = const [],
    this.hotPicks = const [],
    this.charts = const [],
    this.newEpisodes = const [],
    this.topRecommend = const [],
    this.newForThisMonth = const [],
    this.vipZone = const [],
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  // ==================== 数据状态 ====================
  /// 当前加载状态
  final RecommendStatus status;

  /// Banner 列表
  final List<BannerItem> banners;

  /// 热门精选列表
  final List<Drama> hotPicks;

  /// 排行榜列表
  final List<Drama> charts;

  /// 最新剧集列表（瀑布流）
  final List<Drama> newEpisodes;

  /// Top Recommend（videoHotListType=2）
  final List<Drama> topRecommend;

  /// New For This Month（videoHotListType=5）
  final List<Drama> newForThisMonth;

  /// VIP Zone（videoHotListType=6）
  final List<Drama> vipZone;

  // ==================== 加载状态标志 ====================
  /// 是否正在下拉刷新
  final bool isRefreshing;

  /// 是否正在加载更多（分页加载中）
  final bool isLoadingMore;

  /// 是否还有更多数据可加载
  final bool hasMore;

  /// 当前页码
  final int page;

  /// 错误信息（加载失败时）
  final String? errorMessage;

  // ==================== 便捷属性 ====================
  /// 是否处于加载中状态
  bool get isLoading => status == RecommendStatus.loading;

  /// 是否有错误
  bool get hasError => status == RecommendStatus.error;

  /// 是否有数据
  bool get hasData => status == RecommendStatus.success;

  /// 创建新的状态（不可变对象模式）
  RecommendState copyWith({
    RecommendStatus? status,
    List<BannerItem>? banners,
    List<Drama>? hotPicks,
    List<Drama>? charts,
    List<Drama>? newEpisodes,
    List<Drama>? topRecommend,
    List<Drama>? newForThisMonth,
    List<Drama>? vipZone,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RecommendState(
      status: status ?? this.status,
      banners: banners ?? this.banners,
      hotPicks: hotPicks ?? this.hotPicks,
      charts: charts ?? this.charts,
      newEpisodes: newEpisodes ?? this.newEpisodes,
      topRecommend: topRecommend ?? this.topRecommend,
      newForThisMonth: newForThisMonth ?? this.newForThisMonth,
      vipZone: vipZone ?? this.vipZone,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Repository Provider
final recommendRepositoryProvider = Provider<RecommendRepository>((ref) {
  return RecommendRepository(
    dioClient: ref.read(dioClientProvider),
    storageService: ref.read(storageServiceProvider),
  );
});

/// 推荐状态 Provider
final recommendProvider =
    StateNotifierProvider<RecommendNotifier, RecommendState>((ref) {
  return RecommendNotifier(ref.read(recommendRepositoryProvider));
});

/// ============================================================================
/// 推荐数据状态管理器
///
/// 【功能】
/// - 初始加载推荐数据
/// - 下拉刷新
/// - 分页加载更多
/// - 根据 ID 获取短剧详情
/// ============================================================================
class RecommendNotifier extends StateNotifier<RecommendState> {
  RecommendNotifier(this._repository) : super(const RecommendState());

  final RecommendRepository _repository;

  Future<({List<Drama> topRecommend, List<Drama> newForThisMonth, List<Drama> vipZone})>
  _fetchHomeHotSections() async {
    final results = await Future.wait([
      _repository.fetchVideoHotPicks(videoHotListType: 2),
      _repository.fetchVideoHotPicks(videoHotListType: 5),
      _repository.fetchVideoHotPicks(videoHotListType: 6),
    ]);

    return (
      topRecommend: results[0],
      newForThisMonth: results[1],
      vipZone: results[2],
    );
  }

  /// 加载首页展示数据（不包含 Recommend Tab 的 recommendIndex）
  Future<void> loadHomeSections({bool refresh = false}) async {
    if (refresh && state.isRefreshing) return;

    state = state.copyWith(
      status: RecommendStatus.loading,
      isRefreshing: refresh,
      clearError: true,
    );

    try {
      final bannerResp = await apiServiceProvider.getTheaterBanner();
      List<BannerItem> banners = [];
      if (bannerResp.isSuccess && bannerResp.data != null) {
        final list = bannerResp.data as List;
        banners = list
            .map((json) => BannerItem.fromJson(json as Map<String, dynamic>))
            .toList()
            .reversed
            .toList();
      }

      final sections = await _fetchHomeHotSections();

      state = state.copyWith(
        status: RecommendStatus.success,
        banners: banners,
        topRecommend: sections.topRecommend,
        newForThisMonth: sections.newForThisMonth,
        vipZone: sections.vipZone,
        isRefreshing: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: RecommendStatus.error,
        isRefreshing: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 加载推荐页数据（包含 recommendIndex + 首页列表）
  Future<void> loadInitial() async {
    state = state.copyWith(
      status: RecommendStatus.loading,
      clearError: true,
    );
    try {
      final feed = await _repository.fetchFeed(page: 1);
      final sections = await _fetchHomeHotSections();
      state = state.copyWith(
        status: RecommendStatus.success,
        banners: feed.banners,
        hotPicks: feed.hotPicks,
        charts: feed.charts,
        newEpisodes: feed.newEpisodes,
        topRecommend: sections.topRecommend,
        newForThisMonth: sections.newForThisMonth,
        vipZone: sections.vipZone,
        hasMore: feed.hasMore,
        page: 1,
      );
    } catch (e) {
      state = state.copyWith(
        status: RecommendStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // ==================== 下拉刷新 ====================
  /// 刷新数据
  Future<void> refresh() async {
    await loadHomeSections(refresh: true);
  }

  // ==================== 分页加载 ====================
  /// 加载更多数据（分页）
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || !state.hasData) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final feed = await _repository.fetchFeed(page: nextPage);
      state = state.copyWith(
        newEpisodes: [
          ...state.newEpisodes,
          ...feed.newEpisodes,
        ],
        hasMore: feed.hasMore,
        page: nextPage,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ==================== 获取短剧详情 ====================
  /// 根据 ID 获取短剧详情
  Future<Drama?> getDramaById(String id) async {
    try {
      final resp = await apiServiceProvider.getVideoListByVideoId(videoId: id);
      debugPrint('[getDramaById] videoId=$id isSuccess=${resp.isSuccess} data=${resp.data}');
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        debugPrint('[getDramaById] parsed drama: $data');
        return Drama.fromJson(data);
      }
    } catch (e) {
      debugPrint('[getDramaById] error=$e');
    }
    return null;
  }
}

/// ==================== 沉浸式视频流 Provider ====================

/// 沉浸式视频流加载状态
enum VideoFeedStatus {
  initial,
  loading,
  success,
  error,
}

/// 沉浸式视频流状态
class VideoFeedState {
  const VideoFeedState({
    this.status = VideoFeedStatus.initial,
    this.videos = const [],
    this.errorMessage,
  });

  final VideoFeedStatus status;
  final List<VideoInfo> videos;
  final String? errorMessage;

  bool get isLoading => status == VideoFeedStatus.loading;
  bool get hasError => status == VideoFeedStatus.error;
  bool get hasData => status == VideoFeedStatus.success && videos.isNotEmpty;

  VideoFeedState copyWith({
    VideoFeedStatus? status,
    List<VideoInfo>? videos,
    String? errorMessage,
  }) {
    return VideoFeedState(
      status: status ?? this.status,
      videos: videos ?? this.videos,
      errorMessage: errorMessage,
    );
  }
}

/// 沉浸式视频流 Notifier
class VideoFeedNotifier extends StateNotifier<VideoFeedState> {
  VideoFeedNotifier(this._repository) : super(const VideoFeedState());

  final RecommendRepository _repository;

  Future<void> loadVideos() async {
    if (state.isLoading) return;

    state = state.copyWith(status: VideoFeedStatus.loading);
    try {
      final videos = await _repository.fetchRecommendVideos();
      state = state.copyWith(
        status: VideoFeedStatus.success,
        videos: videos,
      );
    } catch (e) {
      state = state.copyWith(
        status: VideoFeedStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(status: VideoFeedStatus.loading);
    try {
      final videos = await _repository.fetchRecommendVideos();
      state = state.copyWith(
        status: VideoFeedStatus.success,
        videos: videos,
      );
    } catch (e) {
      state = state.copyWith(
        status: VideoFeedStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

class MembershipDramaState {
  const MembershipDramaState({
    this.status = RecommendStatus.initial,
    this.topRecommend = const [],
    this.vipZone = const [],
    this.errorMessage,
  });

  final RecommendStatus status;
  final List<Drama> topRecommend;
  final List<Drama> vipZone;
  final String? errorMessage;

  bool get isLoading => status == RecommendStatus.loading;
  bool get hasError => status == RecommendStatus.error;

  MembershipDramaState copyWith({
    RecommendStatus? status,
    List<Drama>? topRecommend,
    List<Drama>? vipZone,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MembershipDramaState(
      status: status ?? this.status,
      topRecommend: topRecommend ?? this.topRecommend,
      vipZone: vipZone ?? this.vipZone,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class MembershipDramaNotifier extends StateNotifier<MembershipDramaState> {
  MembershipDramaNotifier(this._repository)
      : super(const MembershipDramaState());

  final RecommendRepository _repository;

  Future<({List<Drama> topRecommend, List<Drama> vipZone})>
  _fetchMembershipSections() async {
    final results = await Future.wait([
      _repository.fetchVideoHotPicks(videoHotListType: 2),
      _repository.fetchVideoHotPicks(videoHotListType: 6),
    ]);

    return (
      topRecommend: results[0],
      vipZone: results[1],
    );
  }

  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(
      status: RecommendStatus.loading,
      clearError: true,
    );

    try {
      final sections = await _fetchMembershipSections();

      state = state.copyWith(
        status: RecommendStatus.success,
        topRecommend: sections.topRecommend,
        vipZone: sections.vipZone,
      );
    } catch (e) {
      state = state.copyWith(
        status: RecommendStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final membershipDramaProvider =
    StateNotifierProvider<MembershipDramaNotifier, MembershipDramaState>((ref) {
  final repository = ref.read(recommendRepositoryProvider);
  return MembershipDramaNotifier(repository);
});

/// 沉浸式视频流 Provider
final videoFeedProvider =
    StateNotifierProvider<VideoFeedNotifier, VideoFeedState>((ref) {
  final repository = ref.read(recommendRepositoryProvider);
  return VideoFeedNotifier(repository);
});
