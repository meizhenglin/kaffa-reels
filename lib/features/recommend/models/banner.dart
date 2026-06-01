import 'package:equatable/equatable.dart';

import 'drama.dart';
import '../utils/drama_navigation.dart';

/// Banner数据模型
/// 用于首页和推荐页顶部的轮播图
class BannerItem extends Equatable {
  const BannerItem({
    required this.id,
    required this.imageUrl,
    required this.dramaId,
    this.title,
    this.videoId,
    this.bannerEpisodesId,
    this.bannerEpisodesName,
    this.total,
    this.platformId,
  });

  final String id;                    // Banner唯一ID
  final String imageUrl;              // 图片地址
  final String dramaId;               // 关联的短剧ID
  final String? title;                // 标题（可选）
  final String? videoId;             // 视频ID（与 dramaId 相同）
  final String? bannerEpisodesId;     // 剧集ID
  final String? bannerEpisodesName;   // 剧集名称
  final int? total;                  // 总集数
  final int? platformId;             // 平台ID

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
    id: (json['bannerId'] ?? json['id'] ?? '').toString(),
    imageUrl: json['bannerPicture'] ?? json['imageUrl'] ?? '',
    dramaId: (json['videoId'] ?? json['dramaId'] ?? '').toString(),
    title: json['bannerEpisodesName'] ?? json['title'],
    videoId: json['videoId']?.toString(),
    bannerEpisodesId: json['bannerEpisodesId']?.toString(),
    bannerEpisodesName: json['bannerEpisodesName'],
    total: json['total'] as int?,
    platformId: json['platformId'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'imageUrl': imageUrl,
    'dramaId': dramaId,
    'title': title,
    'videoId': videoId,
    'bannerEpisodesId': bannerEpisodesId,
    'bannerEpisodesName': bannerEpisodesName,
    'total': total,
    'platformId': platformId,
  };

  /// 从 Banner 数据构建 Drama 对象（用于跳转播放器）
  Drama toDrama() {
    return Drama(
      id: dramaId,
      title: bannerEpisodesName ?? title ?? '',
      coverUrl: imageUrl,
      views: 0,
      rating: 0.0,
      description: '',
      episodeCount: total ?? 1,
      isVipOnly: false,
      videoUrl: null,
      badge: null,
      aspectRatio: 0.72,
    );
  }

  @override
  List<Object?> get props => [id, imageUrl, dramaId];
}
