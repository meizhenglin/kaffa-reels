import 'package:flutter/material.dart';

/// ============================================================================
/// 认证表单输入框组件
///
/// 【功能说明】
/// 用于登录/注册页面的文本输入框，基于 TextFormField 封装：
/// - 支持邮箱、密码、确认密码等输入
/// - 支持显示/隐藏密码（通过 suffixIcon）
/// - 支持输入验证和错误提示
/// - 支持自动填充提示
///
/// 【使用场景】
/// - LoginPage（登录页）的邮箱、密码输入
/// - RegisterPage（注册页）的邮箱、密码、确认密码输入
///
/// 【参数说明】
/// - controller: TextEditingController，用于获取/设置输入值
/// - label: 输入框标签文字
/// - hint: 提示文字（可选）
/// - errorText: 错误提示文字（可选）
/// - obscureText: 是否隐藏输入（如密码）
/// - keyboardType: 键盘类型（邮箱、数字等）
/// - textInputAction: 键盘动作按钮
/// - prefixIcon: 左侧图标
/// - suffixIcon: 右侧图标（用于显示/隐藏密码）
/// - onChanged: 输入变化回调
/// - validator: 验证函数
/// - autofillHints: 自动填充提示
///
/// 【如何修改】
/// - 修改边框圆角：OutlineInputBorder 的 borderRadius
/// - 修改输入框高度：通过 contentPadding 调整
/// - 添加新属性：在构造函数中添加新的可选参数
/// ============================================================================
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.validator,
    this.autofillHints,
  });

  /// 文本控制器，用于获取和设置输入值
  final TextEditingController controller;
  /// 输入框标签（如"邮箱"、"密码"）
  final String label;
  /// 提示文字
  final String? hint;
  /// 错误提示文字
  final String? errorText;
  /// 是否隐藏输入（用于密码）
  final bool obscureText;
  /// 键盘类型
  final TextInputType? keyboardType;
  /// 键盘动作按钮（下一步、完成等）
  final TextInputAction? textInputAction;
  /// 左侧图标
  final IconData? prefixIcon;
  /// 右侧图标（如密码显示/隐藏按钮）
  final Widget? suffixIcon;
  /// 输入变化回调
  final ValueChanged<String>? onChanged;
  /// 验证函数，返回错误提示或null
  final String? Function(String?)? validator;
  /// 自动填充提示
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
            errorText: errorText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    );
  }
}
