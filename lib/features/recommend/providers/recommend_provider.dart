import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart';
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
/// - 热门短剧列表
/// - 为你推荐列表（瀑布流）
/// - 分页加载状态
///
/// 【数据来源】
/// 数据从 RecommendRepository 获取，默认使用模拟数据
/// 参见 recommend_repository.dart
///
/// 【如何修改】
/// - 修改初始加载逻辑：修改 loadInitial() 方法
/// - 修改刷新逻辑：修改 refresh() 方法
/// - 修改加载更多逻辑：修改 loadMore() 方法
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
    this.hotDramas = const [],
    this.recommendedDramas = const [],
    this.newThisMonthDramas = const [],
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
  
  /// 热门短剧列表
  final List<Drama> hotDramas;

  /// 为你推荐列表（瀑布流数据）
  final List<Drama> recommendedDramas;

  /// 本月新增短剧列表
  final List<Drama> newThisMonthDramas;

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
    List<Drama>? hotDramas,
    List<Drama>? recommendedDramas,
    List<Drama>? newThisMonthDramas,
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
      hotDramas: hotDramas ?? this.hotDramas,
      recommendedDramas: recommendedDramas ?? this.recommendedDramas,
      newThisMonthDramas: newThisMonthDramas ?? this.newThisMonthDramas,
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
    authService: ref.read(authServiceProvider),
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
  RecommendNotifier(this._repository) : super(const RecommendState()) {
    // 构造函数中自动加载初始数据
    loadInitial();
  }

  final RecommendRepository _repository;

  // ==================== 初始加载 ====================
  /// 加载初始数据
  /// 【调用时机】
  /// - 页面首次打开时
  /// - Provider 创建时自动调用
  Future<void> loadInitial() async {
    state = state.copyWith(
      status: RecommendStatus.loading,
      clearError: true,
    );
    try {
      final feed = await _repository.fetchFeed(page: 1);
      final newUpdates = await _repository.fetchNewUpdates();
      state = state.copyWith(
        status: RecommendStatus.success,
        banners: feed.banners,
        hotDramas: feed.hotDramas,
        recommendedDramas: feed.recommendedDramas,
        newThisMonthDramas: newUpdates,
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
  /// 【调用时机】用户下拉刷新时
  Future<void> refresh() async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final feed = await _repository.fetchFeed(page: 1);
      final newUpdates = await _repository.fetchNewUpdates();
      state = state.copyWith(
        status: RecommendStatus.success,
        banners: feed.banners,
        hotDramas: feed.hotDramas,
        recommendedDramas: feed.recommendedDramas,
        newThisMonthDramas: newUpdates,
        hasMore: feed.hasMore,
        page: 1,
        isRefreshing: false,
      );
    } catch (e) {
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: e.toString(),
      );
    }
  }

  // ==================== 分页加载 ====================
  /// 加载更多数据（分页）
  /// 【调用时机】用户滚动到列表底部时
  Future<void> loadMore() async {
    // 防止重复加载
    if (state.isLoadingMore || !state.hasMore || !state.hasData) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final feed = await _repository.fetchFeed(page: nextPage);
      state = state.copyWith(
        // 追加新数据到现有列表
        recommendedDramas: [
          ...state.recommendedDramas,
          ...feed.recommendedDramas,
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
  /// 【用途】Banner 点击、卡片点击时获取完整短剧信息
  Future<Drama?> getDramaById(String id) async {
    try {
      return await _repository.getDramaById(id);
    } catch (_) {
      return null;
    }
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

/// 沉浸式视频流 Provider
final videoFeedProvider =
    StateNotifierProvider<VideoFeedNotifier, VideoFeedState>((ref) {
  final repository = ref.read(recommendRepositoryProvider);
  return VideoFeedNotifier(repository);
});
