// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/3/12
// Brief: 剧集信息数据类

import 'video_info.dart';

/// 剧集信息数据类
class DramaInfo {
  final int id;
  final String title;
  final String cover;
  final VideoInfo drama;
  final List<VideoInfo> dramas;

  const DramaInfo({
    required this.id,
    required this.title,
    required this.cover,
    required this.drama,
    required this.dramas,
  });

  factory DramaInfo.fromJson(Map<String, dynamic> json) {
    return DramaInfo(
      id: json['id'] as int,
      title: json['title'] as String,
      cover: json['cover'] as String,
      drama: VideoInfo.fromJson(json['drama'] as Map<String, dynamic>),
      dramas: VideoInfo.fromJsonList(json['dramas'] as List<dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cover': cover,
        'drama': drama.toJson(),
        'dramas': dramas.map((video) => video.toJson()).toList(),
      };

  static List<DramaInfo> fromJsonList(List<dynamic> jsonList) =>
      jsonList
          .map((json) => DramaInfo.fromJson(json as Map<String, dynamic>))
          .toList();

  DramaInfo copyWith({
    int? id,
    String? title,
    String? cover,
    VideoInfo? drama,
    List<VideoInfo>? dramas,
  }) {
    return DramaInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      drama: drama ?? this.drama,
      dramas: dramas ?? this.dramas,
    );
  }

  VideoInfo? getDramaById(int videoId) {
    try {
      return dramas.firstWhere((video) => video.id == videoId);
    } catch (_) {
      return null;
    }
  }

  int get dramaCount => dramas.length;

  @override
  String toString() =>
      'DramaInfo{id: $id, title: $title, cover: $cover, drama: $drama, dramas: $dramaCount videos}';
}
