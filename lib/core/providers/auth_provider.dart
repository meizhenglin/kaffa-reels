import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';

/// AuthService 全局单例 Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// 匿名游客登录状态
enum GuestLoginStatus {
  /// 初始状态（未登录）
  initial,
  /// 登录中
  loading,
  /// 登录成功
  success,
  /// 登录失败
  failure,
}

/// 匿名游客登录状态 Notifier
class GuestLoginNotifier extends StateNotifier<GuestLoginStatus> {
  GuestLoginNotifier(this._authService) : super(GuestLoginStatus.initial);

  final AuthService _authService;

  Future<void> login() async {
    if (state == GuestLoginStatus.loading) return;
    if (_authService.isLoggedIn) {
      state = GuestLoginStatus.success;
      return;
    }

    state = GuestLoginStatus.loading;
    final result = await _authService.login();
    state = result != null ? GuestLoginStatus.success : GuestLoginStatus.failure;
  }
}

/// 匿名游客登录状态 Provider
final guestLoginProvider =
    StateNotifierProvider<GuestLoginNotifier, GuestLoginStatus>((ref) {
  final authService = ref.read(authServiceProvider);
  return GuestLoginNotifier(authService);
});
