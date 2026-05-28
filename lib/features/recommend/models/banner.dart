import 'package:equatable/equatable.dart';

/// Banner数据模型
/// 用于首页和推荐页顶部的轮播图
class BannerItem extends Equatable {
  const BannerItem({required this.id, required this.imageUrl, required this.dramaId, this.title});

  final String id;      // Banner唯一ID
  final String imageUrl; // 图片地址
  final String dramaId;  // 关联的短剧ID
  final String? title;   // 标题（可选）

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
    id: json['id'], imageUrl: json['imageUrl'],
    dramaId: json['dramaId'], title: json['title'],
  );

  Map<String, dynamic> toJson() => {'id': id, 'imageUrl': imageUrl, 'dramaId': dramaId, 'title': title};

  @override List<Object?> get props => [id, imageUrl, dramaId];
}
