import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';

export '../auth/auth_service.dart' show AuthService, RegisterResult, CheckCodeResult;

/// AuthService 全局单例 Provider（必须先调用 init() 加载缓存 token）
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// 匿名游客登录状态
enum GuestLoginStatus {
  initial,
  loading,
  success,
  failure,
}

class GuestLoginNotifier extends StateNotifier<GuestLoginStatus> {
  GuestLoginNotifier(this._authService) : super(GuestLoginStatus.initial);

  final AuthService _authService;

  Future<void> login() async {
    if (state == GuestLoginStatus.loading) return;

    // 强制发起请求，确保使用新的 /api/user/userAuthorization 接口
    state = GuestLoginStatus.loading;
    final result = await _authService.login(forceLogin: true);
    state = result != null ? GuestLoginStatus.success : GuestLoginStatus.failure;
  }
}

final guestLoginProvider =
    StateNotifierProvider<GuestLoginNotifier, GuestLoginStatus>((ref) {
  final authService = ref.watch(authServiceProvider);
  return GuestLoginNotifier(authService);
});
