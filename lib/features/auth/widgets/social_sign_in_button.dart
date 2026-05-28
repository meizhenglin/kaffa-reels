import 'package:flutter/material.dart';

/// ============================================================================
/// 社交账号登录按钮组件
///
/// 【功能说明】
/// 用于第三方登录（如Google、Apple）的按钮：
/// - 显示社交登录图标和文字
/// - 支持加载状态显示
/// - 支持自定义背景色和前景色
///
/// 【使用场景】
/// - LoginPage（登录页）的 Google 登录按钮
/// - LoginPage（登录页）的 Apple 登录按钮
///
/// 【样式特点】
/// - 白色背景 + 边框
/// - 居中显示图标和文字
/// - 加载中显示 CircularProgressIndicator
///
/// 【如何修改】
/// - 修改按钮高度：minimumSize 的 height
/// - 修改圆角：borderRadius
/// - 修改边框颜色：borderSide 的 color
/// ============================================================================
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// 按钮文字（如 "Continue with Google"）
  final String label;
  /// 按钮图标（可以是 Icon 或 Image.network）
  final Widget icon;
  /// 点击回调
  final VoidCallback? onPressed;
  /// 是否显示加载状态
  final bool isLoading;
  /// 背景颜色（默认白色）
  final Color? backgroundColor;
  /// 前景颜色（图标和文字颜色）
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
    );
  }
}
