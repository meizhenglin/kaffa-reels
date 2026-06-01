import 'package:dio/dio.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/network/dio_client.dart';
import '../models/drama.dart';
import '../models/recommend_feed.dart';
import '../models/banner.dart';
import '../models/video_info.dart';
import 'comprehensive_mock_data.dart';
import 'recommend_mock_data.dart';

/// 单集播放地址缓存，避免同一集重复请求
class EpisodeUrlCache {
  final String videoUrl;
  final String? videoUrlOne;
  final String? videoUrlTwo;
  final int isCanPlay;
  final int isVip;
  final DateTime fetchTime;

  EpisodeUrlCache({
    required this.videoUrl,
    this.videoUrlOne,
    this.videoUrlTwo,
    required this.isCanPlay,
    required this.isVip,
  }) : fetchTime = DateTime.now();

  bool get isExpired => DateTime.now().difference(fetchTime).inMinutes > 5;
}

final Map<String, EpisodeUrlCache> _episodeUrlCache = {};

class RecommendRepository {
  RecommendRepository({
    required DioClient dioClient,
    required AuthService authService,
  })  : _dioClient = dioClient,
        _authService = authService;

  final DioClient _dioClient;
  final AuthService _authService;

  // ==================== 沉浸式视频流 API ====================

  /// 获取推荐视频列表（沉浸式播放页使用）
  ///
  /// 复用 /api/episodes/recommendIndex，取 hotPicksList 字段
  Future<List<VideoInfo>> fetchRecommendVideos() async {
    final token = await _authService.ensureToken();
    if (token == null) {
      return _mockVideos();
    }

    try {
      _dioClient.setAuthToken(token);
      final response = await _dioClient.dio.post(
        '/api/episodes/recommendIndex',
        data: {'pageSize': 10},
      );
      final data = response.data as Map<String, dynamic>;

      if (data['code'] == 0) {
        return _extractVideoListFromRecommend(data);
      } else {
        await _authService.login(forceLogin: true);
        final newToken = _authService.currentToken;
        if (newToken != null) {
          _dioClient.setAuthToken(newToken);
          final retryResp = await _dioClient.dio.post(
            '/api/episodes/recommendIndex',
            data: {'pageSize': 10},
          );
          final retryData = retryResp.data as Map<String, dynamic>;
          if (retryData['code'] == 0) {
            return _extractVideoListFromRecommend(retryData);
          }
        }
        return _mockVideos();
      }
    } on DioException {
      return _mockVideos();
    }
  }

  List<VideoInfo> _extractVideoListFromRecommend(Map<String, dynamic> data) {
    final records = data['data']?['records'];
    if (records is! List) return _mockVideos();
    return records
        .map((json) => VideoInfo.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  List<VideoInfo> _mockVideos() {
    return RecommendMockData.videos();
  }

  // ==================== 首页推荐 API ====================

  /// 获取首页推荐数据
  /// 对应 /api/episodes/recommendIndex
  /// 返回: bannerList / hotPicksList / chartsList / newEpisodesList
  Future<RecommendFeed> fetchFeed({int page = 1, int pageSize = 10}) async {
    final token = await _authService.ensureToken();

    if (token != null) {
      try {
        _dioClient.setAuthToken(token);
        final response = await _dioClient.dio.post(
          '/api/episodes/recommendIndex',
          data: {'pageSize': pageSize},
        );
        final data = response.data as Map<String, dynamic>;

        if (data['code'] == 0) {
          return _parseRecommendFeed(data, page);
        }
      } on DioException {
        // 网络错误，降级到模拟数据
      }
    }

    return _mockFeed(page);
  }

  RecommendFeed _parseRecommendFeed(Map<String, dynamic> data, int page) {
    final d = data['data'] as Map<String, dynamic>? ?? {};

    List<Drama> parseList(dynamic list) {
      if (list is! List) return [];
      return list
          .map((json) => Drama.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return RecommendFeed(
      banners: parseBanners(d['bannerList']),
      hotPicks: parseList(d['hotPicksList']),
      charts: parseList(d['chartsList']),
      newEpisodes: parseList(d['newEpisodesList']),
      hasMore: true,
      page: page,
    );
  }

  List<BannerItem> parseBanners(dynamic list) {
    if (list is! List) return [];
    return list
        .map((json) => BannerItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  RecommendFeed _mockFeed(int page) {
    return RecommendFeed(
      banners: ComprehensiveMockData.banners(),
      hotPicks: ComprehensiveMockData.hotDramas(),
      charts: ComprehensiveMockData.hotDramas(),
      newEpisodes: ComprehensiveMockData.newUpdates(),
      hasMore: page < 3,
      page: page,
    );
  }

  // ==================== 其他接口 ====================

  Future<Drama> getDramaById(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return ComprehensiveMockData.dramaById(id);
  }

  Future<List<Drama>> fetchHotList() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ComprehensiveMockData.hotDramas();
  }

  Future<List<Drama>> fetchAllRecommended() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final dramas = <Drama>[];
    for (int i = 1; i <= 5; i++) {
      dramas.addAll(ComprehensiveMockData.recommendedPage(i, pageSize: 12));
    }
    return dramas;
  }

  Future<List<Drama>> fetchByCategory(String categoryId, {int page = 1, int pageSize = 12}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ComprehensiveMockData.dramasByCategory(categoryId, page: page, pageSize: pageSize);
  }

  Future<List<Drama>> searchDramas(String query, {int page = 1, int pageSize = 12}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ComprehensiveMockData.search(query, page: page, pageSize: pageSize);
  }

  Future<List<Drama>> fetchVipDramas() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ComprehensiveMockData.vipDramas();
  }

  Future<List<Drama>> fetchNewUpdates() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ComprehensiveMockData.newUpdates();
  }

  // ==================== 单集播放地址 ====================

  /// 根据 videoId + episodesId 获取单集真实播放地址
  ///
  /// recommendIndex 返回的 episodesUrl 可能无效，每次滑动都应重新请求。
  /// 结果会被缓存 5 分钟，同一集不会重复请求。
  Future<EpisodeUrlCache?> fetchEpisodeUrl({
    required int videoId,
    required int episodesId,
  }) async {
    final cacheKey = '${videoId}_$episodesId';

    // 缓存未过期直接返回
    final cached = _episodeUrlCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    final token = await _authService.ensureToken();
    if (token == null) return null;

    try {
      _dioClient.setAuthToken(token);
      final response = await _dioClient.dio.post(
        '/api/episodes/getEpisodeInfo',
        data: {'videoId': videoId, 'episodesId': episodesId},
      );
      final data = response.data as Map<String, dynamic>;

      if (data['code'] == 0) {
        final episodeData = data['data'] as Map<String, dynamic>;
        final cache = EpisodeUrlCache(
          videoUrl: episodeData['episodesUrl'] as String? ?? '',
          videoUrlOne: episodeData['vipEpisodesUrl1080'] as String?,
          videoUrlTwo: episodeData['vipEpisodesUrl1440'] as String?,
          isCanPlay: episodeData['isCanPlay'] as int? ?? 1,
          isVip: episodeData['isVip'] as int? ?? 0,
        );
        _episodeUrlCache[cacheKey] = cache;
        return cache;
      }
    } on DioException {
      // ignore
    }
    return null;
  }
}
