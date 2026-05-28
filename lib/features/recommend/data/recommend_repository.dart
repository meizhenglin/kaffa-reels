import 'package:dio/dio.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/network/dio_client.dart';
import '../models/drama.dart';
import '../models/recommend_feed.dart';
import '../models/video_info.dart';
import 'comprehensive_mock_data.dart';
import 'recommend_mock_data.dart';

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
  /// 流程：确保登录 → 带 Token 请求 → 解析返回
  /// 失败时自动降级为模拟数据
  Future<List<VideoInfo>> fetchRecommendVideos() async {
    final token = await _authService.ensureToken();
    if (token == null) {
      return _mockVideos();
    }

    try {
      _dioClient.setAuthToken(token);
      final response = await _dioClient.dio.get('/video/recommendVideo');
      final data = response.data as Map<String, dynamic>;

      if (data['code'] == 200) {
        final list = _extractVideoList(data);
        return list;
      } else {
        // Token 过期，重新登录后重试
        await _authService.login(forceLogin: true);
        final newToken = _authService.currentToken;
        if (newToken != null) {
          _dioClient.setAuthToken(newToken);
          final retryResp = await _dioClient.dio.get('/video/recommendVideo');
          final retryData = retryResp.data as Map<String, dynamic>;
          if (retryData['code'] == 200) {
            return _extractVideoList(retryData);
          }
        }
        return _mockVideos();
      }
    } on DioException catch (e) {
      // 网络错误，降级到模拟数据
      return _mockVideos();
    }
  }

  List<VideoInfo> _extractVideoList(Map<String, dynamic> data) {
    final wrapper = data['data'];
    if (wrapper is Map) {
      final list = wrapper['list'];
      if (list is List) {
        return list
            .map((json) => VideoInfo.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } else if (wrapper is List) {
      return wrapper
          .map((json) => VideoInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    return _mockVideos();
  }

  List<VideoInfo> _mockVideos() {
    return RecommendMockData.videos();
  }

  // ==================== 推荐 Feed API（Banners / 热门 / 推荐）====================

  /// 获取推荐 Feed（首页用）
  Future<RecommendFeed> fetchFeed({int page = 1, int pageSize = 6}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final recommended = ComprehensiveMockData.recommendedPage(page, pageSize: pageSize);

    if (page == 1) {
      return RecommendFeed(
        banners: ComprehensiveMockData.banners(),
        hotDramas: ComprehensiveMockData.hotDramas(),
        recommendedDramas: recommended,
        hasMore: true,
        page: page,
      );
    }

    return RecommendFeed(
      banners: const [],
      hotDramas: const [],
      recommendedDramas: recommended,
      hasMore: page < 10,
      page: page,
    );
  }

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
}
