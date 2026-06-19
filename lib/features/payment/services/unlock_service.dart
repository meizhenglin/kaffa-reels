import 'package:dio/dio.dart';

/// 解锁服务
class UnlockService {
  UnlockService({
    required Dio dio,
  }) : _dio = dio;

  final Dio _dio;

  /// 解锁剧集
  /// 
  /// [videoId] - 视频ID
  /// [episodesId] - 剧集ID
  /// [goodsId] - 商品ID
  /// [price] - 价格
  /// [episodeIndex] - 剧集索引
  Future<UnlockResponse> unlockEpisode({
    required String videoId,
    required String episodesId,
    required int goodsId,
    required int price,
    int? episodeIndex,
  }) async {
    try {
      final response = await _dio.post(
        'api/unlock/episode',
        data: {
          'videoId': videoId,
          'episodesId': episodesId,
          'goodsId': goodsId,
          'price': price,
          if (episodeIndex != null) 'episodeIndex': episodeIndex,
        },
      );

      if (response.statusCode == 200 && response.data['code'] == 0) {
        return UnlockResponse.success();
      } else {
        return UnlockResponse.failed(
          message: response.data['msg'] ?? '解锁失败',
        );
      }
    } on DioException catch (e) {
      return UnlockResponse.failed(
        message: e.message ?? '网络错误',
      );
    } catch (e) {
      return UnlockResponse.failed(
        message: '未知错误: $e',
      );
    }
  }
}

/// 解锁响应
class UnlockResponse {
  UnlockResponse._({
    required this.success,
    this.errorMessage,
  });

  factory UnlockResponse.success() {
    return UnlockResponse._(success: true);
  }

  factory UnlockResponse.failed({String? message}) {
    return UnlockResponse._(success: false, errorMessage: message);
  }

  final bool success;
  final String? errorMessage;
}
