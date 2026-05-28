import 'package:flutter/material.dart';

/// ============================================================================
/// 应用全局颜色配置文件
///
/// 【功能说明】
/// 定义应用中使用的所有颜色值，包括：主色、辅色、背景色、文字颜色、
/// 状态颜色、VIP 专属颜色、渐变色等。
///
/// 【如何修改】
/// - 主色调：修改 `primary`、`primaryLight`、`primaryDark`
/// - 背景色：修改 `background`、`backgroundDark`（暗色模式）
/// - VIP 颜色：修改 `vipGold`、`vipPurple`
/// ============================================================================
class AppColors {
  // 私有构造函数，防止外部实例化
  AppColors._();

  // ==================== 主色调 (Primary Colors) ====================
  /// 应用主色，用于按钮、强调元素、链接等
  /// 【修改提示】这是品牌色，更改后会影响整个应用的主要视觉风格
  static const Color primary = Color(0xFF6366F1);

  /// 主色浅色版本，用于渐变或高亮效果
  static const Color primaryLight = Color(0xFF818CF8);

  /// 主色深色版本，用于按压状态或阴影效果
  static const Color primaryDark = Color(0xFF4F46E5);

  // ==================== 次要色调 (Secondary Colors) ====================
  /// 次要色，用于辅助强调或特殊元素
  static const Color secondary = Color(0xFFEC4899);

  /// 次要色浅色版本
  static const Color secondaryLight = Color(0xFFF472B6);

  /// 次要色深色版本
  static const Color secondaryDark = Color(0xFFDB2777);

  // ==================== 背景色 (Background Colors) ====================
  /// 亮色模式背景色
  static const Color background = Color(0xFFF8FAFC);

  /// 暗色模式背景色
  static const Color backgroundDark = Color(0xFF0F172A);

  /// 卡片背景色（亮色模式）
  static const Color cardBackground = Colors.white;

  /// 卡片背景色（暗色模式）
  static const Color cardBackgroundDark = Color(0xFF1E293B);

  // ==================== 文字颜色 (Text Colors) ====================
  /// 主要文字颜色，用于标题和重要内容
  static const Color textPrimary = Color(0xFF1E293B);

  /// 次要文字颜色，用于辅助说明
  static const Color textSecondary = Color(0xFF64748B);

  /// 浅色文字颜色，用于占位符或禁用状态
  static const Color textLight = Color(0xFF94A3B8);

  // ==================== 状态颜色 (Status Colors) ====================
  /// 成功状态颜色，用于成功提示、通过验证等
  static const Color success = Color(0xFF22C55E);

  /// 警告状态颜色，用于警告提示等
  static const Color warning = Color(0xFFF59E0B);

  /// 错误状态颜色，用于错误提示、失败状态等
  static const Color error = Color(0xFFEF4444);

  /// 信息提示颜色，用于信息通知等
  static const Color info = Color(0xFF3B82F6);

  // ==================== VIP 专属颜色 (VIP Colors) ====================
  /// VIP 金色，用于 VIP 标识、会员卡片等
  static const Color vipGold = Color(0xFFFFD700);

  /// VIP 紫色，用于 VIP 渐变或特殊会员等级
  static const Color vipPurple = Color(0xFF9333EA);

  // ==================== 渐变色配置 (Gradient Colors) ====================
  /// 主色渐变，从 primary 到 secondary
  /// 【使用场景】按钮、卡片背景、启动页等
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// VIP 金色渐变，从 vipGold 到橙色
  /// 【使用场景】VIP 会员卡、VIP 按钮等
  static const LinearGradient vipGradient = LinearGradient(
    colors: [vipGold, Color(0xFFFFA500)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
