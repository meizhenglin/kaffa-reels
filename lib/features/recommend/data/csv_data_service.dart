import 'dart:io';

import 'package:flutter/services.dart';

import '../models/banner.dart';
import '../models/drama.dart';

/// CSV数据模型 - 对应CSV文件的列结构
class CsvDramaData {
  const CsvDramaData({
    required this.title,
    required this.description,
    required this.videoId,
    required this.episodeCount,
    required this.coverUrl,
  });

  final String title;
  final String description;
  final String videoId;
  final int episodeCount;
  final String coverUrl;

  /// 将CSV数据转换为Drama对象
  Drama toDrama({String? videoUrl, bool isVipOnly = false}) {
    return Drama(
      id: videoId,
      title: title,
      coverUrl: coverUrl,
      views: 0,
      rating: 0.0,
      description: description,
      episodeCount: episodeCount,
      isVipOnly: isVipOnly,
      videoUrl: videoUrl ?? VideoUrlService.instance.getVideoUrl(videoId),
      aspectRatio: 0.72,
    );
  }

  /// 转换为BannerItem
  BannerItem toBannerItem() {
    return BannerItem(
      id: 'banner_$videoId',
      imageUrl: coverUrl,
      dramaId: videoId,
      title: title,
    );
  }
}

/// CSV数据加载服务
class CsvDataService {
  CsvDataService._();
  static final CsvDataService instance = CsvDataService._();

  List<CsvDramaData>? _cachedData;

  /// 从CSV文件加载数据
  Future<List<CsvDramaData>> loadFromCsv(String filePath) async {
    if (_cachedData != null) return _cachedData!;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('CSV file not found: $filePath');
      }

      final content = await file.readAsString();
      _cachedData = _parseCsv(content);
      return _cachedData!;
    } catch (e) {
      print('Error loading CSV: $e');
      return [];
    }
  }

  /// 从assets加载CSV
  Future<List<CsvDramaData>> loadFromAssets(String assetPath) async {
    if (_cachedData != null) return _cachedData!;

    try {
      final content = await rootBundle.loadString(assetPath);
      _cachedData = _parseCsv(content);
      return _cachedData!;
    } catch (e) {
      print('Error loading CSV from assets: $e');
      return [];
    }
  }

  /// 解析CSV内容
  List<CsvDramaData> _parseCsv(String content) {
    final lines = content.split('\n');
    final dramas = <CsvDramaData>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 跳过第一行（如果有标题）
      if (i == 0 && _isHeaderLine(line)) continue;

      final drama = _parseCsvLine(line);
      if (drama != null) {
        dramas.add(drama);
      }
    }

    return dramas;
  }

  bool _isHeaderLine(String line) {
    return line.contains('标题') ||
        line.contains('名称') ||
        line.contains('name') ||
        line.contains('title');
  }

  CsvDramaData? _parseCsvLine(String line) {
    // CSV格式: 标题,简介,视频ID,集数,图片URL
    final fields = _splitCsvLine(line);

    if (fields.length < 5) return null;

    final title = fields[0].trim();
    final description = fields[1].trim();
    final videoId = fields[2].trim();
    final episodeStr = fields[3].trim();
    final coverUrl = fields[4].trim();

    if (title.isEmpty || videoId.isEmpty || coverUrl.isEmpty) return null;

    // 跳过无效的视频ID
    if (videoId.length < 5) return null;

    final episodeCount = int.tryParse(episodeStr) ?? 1;

    return CsvDramaData(
      title: title,
      description: description,
      videoId: videoId,
      episodeCount: episodeCount,
      coverUrl: coverUrl,
    );
  }

  List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    fields.add(buffer.toString());

    return fields;
  }

  /// 清除缓存
  void clearCache() {
    _cachedData = null;
  }
}

/// 视频URL转换服务
class VideoUrlService {
  VideoUrlService._();
  static final VideoUrlService instance = VideoUrlService._();

  /// 华为云OBS视频基础URL
  /// 注意：需要将 {videoId}.mp4 替换为实际的视频文件名
  /// 视频文件名格式需与后端确认（可能是 {videoId}.mp4 / {videoId}.m3u8 等）
  static const String _videoBaseUrl =
      'https://qahwa-tv-bucket.obs.me-east-1.myhuaweicloud.com/videos';

  /// 将视频ID转换为播放URL
  ///
  /// 当前：使用测试用 .m3u8 地址（后端视频上传后可改为实际地址）
  String getVideoUrl(String videoId) {
    return 'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8';
  }

  /// 测试视频URL（开发阶段用）
  static const _testVideoUrls = [
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
  ];

  String _getTestVideoUrl(String videoId) {
    final hash = videoId.hashCode.abs();
    return _testVideoUrls[hash % _testVideoUrls.length];
  }

  /// 批量获取视频URL（供后端API使用）
  Future<Map<String, String>> batchGetVideoUrls(List<String> videoIds) async {
    return {for (var id in videoIds) id: getVideoUrl(id)};
  }
}
