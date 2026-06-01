// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 视频信息数据类

/// 视频信息数据类
class VideoInfo {
  final int id;
  final String videoUrl;
  final String coverUrl;
  final String type;
  final bool isVip;
  final bool isCanPlay;

  const VideoInfo({
    required this.id,
    required this.videoUrl,
    required this.coverUrl,
    this.type = "video",
    this.isVip = false,
    this.isCanPlay = true,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      id: json['id'] as int,
      videoUrl: json['url'] as String,
      coverUrl: json['coverUrl'] as String,
      type: json['type'] as String? ?? 'video',
      isVip: json['isVip'] as bool? ?? false,
      isCanPlay: json['isCanPlay'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': videoUrl,
        'coverUrl': coverUrl,
        'type': type,
        'isVip': isVip,
        'isCanPlay': isCanPlay,
      };

  /// 从 recommend 模块的 VideoInfo 转换（字段名映射对齐）
  factory VideoInfo.fromRecommendVideoInfo(Map<String, dynamic> json) {
    return VideoInfo(
      id: (json['serialNum'] as int?) ?? 1,
      videoUrl: (json['videoUrl'] as String?) ?? '',
      coverUrl: (json['coverUrl'] as String?) ?? '',
      type: 'video',
      isVip: (json['isVip'] as bool?) ?? false,
      isCanPlay: (json['isCanPlay'] as bool?) ?? true,
    );
  }

  static List<VideoInfo> fromRecommendVideoInfoList(List<dynamic> jsonList) =>
      jsonList
          .map((json) => VideoInfo.fromRecommendVideoInfo(json as Map<String, dynamic>))
          .toList();

  VideoInfo copyWith({
    int? id,
    String? videoUrl,
    String? coverUrl,
    String? type,
    bool? isVip,
    bool? isCanPlay,
  }) {
    return VideoInfo(
      id: id ?? this.id,
      videoUrl: videoUrl ?? this.videoUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      type: type ?? this.type,
      isVip: isVip ?? this.isVip,
      isCanPlay: isCanPlay ?? this.isCanPlay,
    );
  }

  @override
  String toString() =>
      'VideoInfo{id: $id, videoUrl: $videoUrl, coverUrl: $coverUrl, type: $type, isVip: $isVip, isCanPlay: $isCanPlay}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          videoUrl == other.videoUrl &&
          coverUrl == other.coverUrl &&
          type == other.type &&
          isVip == other.isVip &&
          isCanPlay == other.isCanPlay;

  @override
  int get hashCode => Object.hash(id, videoUrl, coverUrl, type, isVip, isCanPlay);
}
