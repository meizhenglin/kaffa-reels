// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/3/12
// Brief: 短视频工具类

import 'package:short_video_player/drama_info.dart';
import 'package:short_video_player/http_util.dart';
import 'package:short_video_player/video_info.dart';
import 'package:flutter/cupertino.dart';

/// 短视频工具类
class ShortVideoUtil {
  ShortVideoUtil._();

  static Future<List<VideoInfo>> loadVideoInfoList(String url) async {
    try {
      final response = await HTTPUtil.instance.get(url);
      if (response == null) {
        debugPrint("Error: Video info response is null for URL: $url");
        return [];
      }
      if (response is List) {
        final List<dynamic> jsonData = response;
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
      final response = await HTTPUtil.instance.get(url);
      if (response == null) {
        debugPrint("Error: Drama info response is null for URL: $url");
        return [];
      }
      if (response is List && response.isNotEmpty) {
        return response
            .map((dramaJson) => DramaInfo.fromJson(dramaJson))
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
      if (dramaInfo == null || dramaInfo.dramas.isEmpty) return [];
      return dramaInfo.dramas;
    } catch (e) {
      debugPrint("Error extracting video info from drama info: $e");
      return [];
    }
  }
}
