import 'package:equatable/equatable.dart';

import 'drama_badge.dart';

/// ============================================================================
/// 短剧数据模型
///
/// 【功能】定义短剧/短视频的完整数据结构
/// 【如何修改】添加新字段时需在构造函数和 fromJson/toJson 中同步添加
/// ============================================================================
class Drama extends Equatable {
  const Drama({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.views,
    required this.rating,
    required this.description,
    required this.episodeCount,
    required this.isVipOnly,
    this.videoUrl,
    this.badge,
    this.aspectRatio = 0.72,
    this.videoAccessType = 0,
    this.videoLabelNames = const [],
    this.hotIndex = 0,
  });

  /// 唯一标识符
  final String id;
  /// 标题
  final String title;
  /// 封面图片 URL
  final String coverUrl;
  /// 播放量
  final int views;
  /// 评分（0-10）
  final double rating;
  /// 描述
  final String description;
  /// 集数
  final int episodeCount;
  /// 是否 VIP 专属
  final bool isVipOnly;
  /// 视频地址
  final String? videoUrl;
  /// 标签（Hot/New/VIP）
  final DramaBadge? badge;
  /// 瀑布流卡片比例
  final double aspectRatio;
  /// 访问类型：0 免费，1 VIP，2 整集解锁
  final int videoAccessType;
  /// 视频标签名列表
  final List<String> videoLabelNames;
  /// 热度指数
  final int hotIndex;

  /// 播放量
  String get formattedViews => views.toString();

  /// 从 JSON 创建 Drama 对象
  /// API 返回字段映射：
  ///   videoId       → id
  ///   videoName     → title
  ///   videoPicture  → coverUrl
  ///   videoIntroduce → description
  ///   videoEpisodes → episodeCount
  factory Drama.fromJson(Map<String, dynamic> json) {
    final rawLabelList = json['videoLabelList'];
    final videoLabelNames = rawLabelList is List
        ? rawLabelList
              .map(
                (item) => (item as Map<String, dynamic>)['videoLabelName']?.toString() ?? '',
              )
              .where((name) => name.isNotEmpty)
              .toList()
        : <String>[];

    return Drama(
      id: '${json['videoId'] ?? 0}',
      title: json['videoName'] as String? ?? '',
      coverUrl: json['videoPicture'] as String? ?? '',
      views: int.tryParse('${json['videoPlayNum'] ?? json['views'] ?? 0}') ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      description: json['videoIntroduce'] as String? ?? '',
      episodeCount: json['videoEpisodes'] as int? ?? 0,
      isVipOnly: json['isVipOnly'] as bool? ?? false,
      videoUrl: json['videoUrl'] as String?,
      badge: null,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? 0.72,
      videoAccessType: int.tryParse('${json['videoAccessType'] ?? 0}') ?? 0,
      videoLabelNames: videoLabelNames,
      hotIndex: int.tryParse('${json['hotIndex'] ?? 0}') ?? 0,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'views': views,
    'rating': rating,
    'description': description,
    'episodeCount': episodeCount,
    'isVipOnly': isVipOnly,
    'videoUrl': videoUrl,
    'badge': badge?.name,
    'aspectRatio': aspectRatio,
    'videoAccessType': videoAccessType,
    'videoLabelNames': videoLabelNames,
    'hotIndex': hotIndex,
  };

  @override
  List<Object?> get props => [
    id,
    title,
    coverUrl,
    views,
    rating,
    videoAccessType,
    videoLabelNames,
    hotIndex,
  ];
}
