/// ============================================================================
/// 共享认证异常定义
///
/// 【位置】lib/features/auth/exceptions/auth_exceptions.dart
/// 【用途】解决 auth_repository.dart 和 tiktok_auth_service.dart 之间的
///         循环 import 问题；这里集中定义所有登录流程共用的异常。
/// ============================================================================

/// 用户主动取消登录（适用于所有登录方式：Google/Facebook/Apple/TikTok）
class AuthCancelledException implements Exception {
  const AuthCancelledException();
  @override
  String toString() => 'Sign in cancelled by user';
}
