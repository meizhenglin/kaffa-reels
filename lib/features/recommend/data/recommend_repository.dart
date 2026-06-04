import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/model/api_endpoints.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/storage_service.dart';
import '../models/banner.dart';
import '../models/drama.dart';
import '../models/recommend_feed.dart';
import '../models/video_info.dart';

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
    required StorageService storageService,
  })  : _dioClient = dioClient,
        _storageService = storageService;

  final DioClient _dioClient;
  final StorageService _storageService;

  // ==================== 沉浸式视频流 API ====================

  /// 获取推荐视频列表（沉浸式播放页使用）
  Future<List<VideoInfo>> fetchRecommendVideos() async {
    try {
      final response = await _dioClient.dio.post(
        '/api/episodes/recommendIndex',
        data: {'pageSize': 10},
      );
      final data = response.data as Map<String, dynamic>;

      if (data['code'] == 0) {
        return _extractVideoListFromRecommend(data);
      }
    } on DioException {
      // ignore
    }
    return [];
  }

  List<VideoInfo> _extractVideoListFromRecommend(Map<String, dynamic> data) {
    final records = data['data']?['records'];
    if (records is! List) return [];
    return records
        .map((json) => VideoInfo.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ==================== 首页推荐 API ====================

  /// 获取首页推荐数据
  /// 对应 /api/banner/list + /api/episodes/recommendIndex
  Future<RecommendFeed> fetchFeed({int page = 1, int pageSize = 10}) async {
    List<BannerItem> banners = [];

    try {
      // 单独请求 /api/banner/list
      final bannerResp = await apiServiceProvider.getTheaterBanner();
      debugPrint('[Banner] isSuccess=${bannerResp.isSuccess} data=${bannerResp.data}');
      if (bannerResp.isSuccess && bannerResp.data != null) {
        final list = bannerResp.data as List;
        banners = list
            .map((json) => BannerItem.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      // 请求推荐数据
      final response = await _dioClient.dio.post(
        '/api/episodes/recommendIndex',
        data: {'pageSize': pageSize},
      );
      final data = response.data as Map<String, dynamic>;
      debugPrint('[Recommend] code=${data['code']} data=${data['data']}');

      if (data['code'] == 0) {
        return _parseRecommendFeed(data, page, banners);
      }
    } on DioException {
      // ignore
    }

    return RecommendFeed(
      banners: banners,
      hotPicks: [],
      charts: [],
      newEpisodes: [],
      hasMore: false,
      page: page,
    );
  }

  RecommendFeed _parseRecommendFeed(Map<String, dynamic> data, int page, List<BannerItem> banners) {
    final d = data['data'] as Map<String, dynamic>? ?? {};

    List<Drama> parseList(dynamic list) {
      if (list is! List) return [];
      return list
          .map((json) => Drama.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return RecommendFeed(
      banners: banners.isNotEmpty ? banners : parseBanners(d['bannerList']),
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

  // ==================== 热门精选 API ====================

  /// 获取热门精选列表
  /// 对应 /api/videoHotPicks/list
  /// [videoHotListType] 2=Top Recommend  5=New For This Month  6=VIP Zone
  Future<List<Drama>> fetchVideoHotPicks({required int videoHotListType}) async {
    final token = await _authService.ensureToken();
    if (token == null) return [];

    try {
      _dioClient.setAuthToken(token);
      final response = await _dioClient.dio.post(
        ApiEndpoints.videoHotPicks,
        data: {'videoHotListType': videoHotListType},
      );
      final data = response.data as Map<String, dynamic>;
      debugPrint('[VideoHotPicks] type=$videoHotListType code=${data['code']} data=${data['data']}');

      if (data['code'] == 0 || data['code'] == 200) {
        // API 返回结构：{ code, msg, data: { records: [...] } }
        final records = data['data']?['records'] as List? ?? [];
        return records
            .map((json) => Drama.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } on DioException {
      // ignore
    }
    return [];
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

    final cached = _episodeUrlCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    try {
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
