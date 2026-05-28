import 'package:flutter/material.dart';

/// 短剧标签枚举
/// 用于在卡片上显示 HOT、NEW、VIP 等标签
enum DramaBadge {
  hot,     // 热门
  newDrama,  // 新剧
  vip,     // VIP专属
  update,  // 更新中
  exclusive, // 独家
}

extension DramaBadgeExtension on DramaBadge {
  /// 标签颜色
  Color get color {
    switch (this) {
      case DramaBadge.hot:
        return Colors.red;
      case DramaBadge.newDrama:
        return Colors.blue;
      case DramaBadge.vip:
        return const Color(0xFFFFD700);
      case DramaBadge.update:
        return Colors.green;
      case DramaBadge.exclusive:
        return Colors.purple;
    }
  }

  /// 标签文字（根据语言）
  String label(bool isArabic) {
    switch (this) {
      case DramaBadge.hot:
        return isArabic ? 'ساخن' : 'HOT';
      case DramaBadge.newDrama:
        return isArabic ? 'جديد' : 'NEW';
      case DramaBadge.vip:
        return 'VIP';
      case DramaBadge.update:
        return isArabic ? 'مستمر' : 'UPDATE';
      case DramaBadge.exclusive:
        return isArabic ? 'حصري' : 'EXCLUSIVE';
    }
  }
}
