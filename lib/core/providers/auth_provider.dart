import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/app_providers.dart';
import '../auth/auth_service.dart';
import '../network/api_service.dart';
export '../auth/auth_service.dart' show AuthService, RegisterResult, CheckCodeResult;

/// AuthService 全局单例 Provider（必须先调用 init() 加载缓存 token）
final apiServiceProviderRef = Provider<ApiService>((ref) {
  return ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
});

/// AuthService 全局单例 Provider（必须先调用 init() 加载缓存 token）
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    apiService: ref.read(apiServiceProviderRef),
    storage: ref.read(storageServiceProvider),
  );
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

    state = GuestLoginStatus.loading;
    final result = await _authService.ensureGuestLogin();
    state = result != null ? GuestLoginStatus.success : GuestLoginStatus.failure;
  }
}

final guestLoginProvider =
    StateNotifierProvider<GuestLoginNotifier, GuestLoginStatus>((ref) {
  final authService = ref.watch(authServiceProvider);
  return GuestLoginNotifier(authService);
});
