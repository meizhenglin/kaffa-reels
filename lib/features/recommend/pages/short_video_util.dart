// Short video utility class (updated to use local types and app's dio)
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/video_info.dart';
import 'drama_info.dart';

class ShortVideoUtil {
  ShortVideoUtil._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 5000),
    receiveTimeout: const Duration(milliseconds: 3000),
    responseType: ResponseType.json,
  ));

  static Future<List<VideoInfo>> loadVideoInfoList(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.data == null) {
        debugPrint("Error: Video info response is null for URL: $url");
        return []; 
      }
      if (response.data is List) {
        final List<dynamic> jsonData = response.data;
        return jsonData.map((json) => VideoInfo.fromJson(json)).toList();
      } else {
        debugPrint("Error: Invalid video info list format for URL: $url");
        return [];
      }
    } catch (e) {
      debugPrint("Error loading video info list for URL: $url, Exception: $e");
      return [];
    }
  }

  static Future<List<DramaInfo>> loadDramaInfoList(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.data == null) {
        debugPrint("Error: Drama info response is null for URL: $url");
        return [];
      }
      if (response.data is List && (response.data as List).isNotEmpty) {
        return (response.data as List)
            .map((dramaJson) => DramaInfo.fromJson(dramaJson as Map<String, dynamic>))
            .toList();
      } else {
        debugPrint("Error: Invalid drama info list format for URL: $url");
        return [];
      }
    } catch (e) {
      debugPrint("Error loading drama info list for URL: $url, Exception: $e");
      return [];
    }
  }

  static List<VideoInfo> getVideoInfoListFromDramaInfo(DramaInfo? dramaInfo) {
    try {
      if (dramaInfo == null || dramaInfo.dramas.isEmpty) {
        return [];
      }
      return dramaInfo.dramas;
    } catch (e) {
      debugPrint("Error extracting video info from drama info: $e");
      return [];
    }
  }
}
