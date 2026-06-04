import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart' show GuestLoginStatus, guestLoginProvider, authServiceProvider, apiServiceProviderRef;
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_service.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

export '../../../core/providers/auth_provider.dart' show AuthService, RegisterResult, CheckCodeResult, authServiceProvider;

/// ============================================================================
/// 认证状态管理
///
/// 【功能】
/// - 管理用户登录/注册状态
/// - 支持邮箱、Google、Apple 登录
/// - 支持游客模式
/// - Firebase Auth 集成
/// ============================================================================

/// 认证状态枚举
enum AuthStatus {
  unauthenticated,   // 未认证
  authenticating,    // 认证中
  authenticated,     // 已认证
  error,             // 认证错误
}

/// 认证状态数据类
class AuthState {
  const AuthState({
    this.status = AuthStatus.authenticating,
    this.user, this.isLoading = false, this.errorMessage,
  });

  final AuthStatus status;    // 当前状态
  final UserModel? user;     // 用户信息
  final bool isLoading;      // 是否加载中
  final String? errorMessage; // 错误信息

  /// 是否已登录
  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status, UserModel? user, bool? isLoading,
    String? errorMessage, bool clearUser = false, bool clearError = false,
  }) => AuthState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(storageServiceProvider)));
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));

/// 认证状态管理器
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) { _startInit(); }
  final Ref _ref;
  StreamSubscription<User?>? _authSubscription;
  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  /// 启动初始化（不阻塞 Provider 创建）
  void _startInit() {
    _init().catchError((e) {
      debugPrint('[AuthNotifier] _init error: $e');
    });
  }

  /// 初始化：检查缓存用户 + 监听 Firebase 状态变化
  ///
  /// 注意：邮箱登录不走 Firebase Auth，初始化阶段只有一件事：
  /// 如果有 auto-login 凭证就自动登录；否则不改变状态，交给 splash_page 的 initAsGuest。
  Future<void> _init() async {
    // 自动登录：检查是否有保存的凭证，有则自动登录
    if (await _repository.hasAutoLoginCredentials()) {
      debugPrint('[AuthNotifier] auto-login credentials found, performing auto-login...');
      state = state.copyWith(status: AuthStatus.authenticating, isLoading: true, clearError: true);
      try {
        final user = await _repository.performAutoLogin();
        state = state.copyWith(status: AuthStatus.authenticated, user: user, isLoading: false);
        debugPrint('[AuthNotifier] auto-login succeeded');
        // auto-login 成功后才订阅 Firebase stream，用于监听 Google/Apple 的登出事件
        _subscribeFirebaseAuth();
        return;
      } catch (e) {
        debugPrint('[AuthNotifier] auto-login failed: $e, clearing credentials');
        await _repository.clearAutoLoginCredentials();
        state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
        // 没有 Firebase 用户，stream 订阅无意义，跳过
        return;
      }
    }

    // 无 auto-login 凭证：不做任何状态操作，splash_page 的 initAsGuest 会接管
    debugPrint('[AuthNotifier] no auto-login credentials, waiting for initAsGuest');
  }

  /// 订阅 Firebase Auth 状态变化（用于 Google/Apple 登录后的登出监听）
  void _subscribeFirebaseAuth() {
    _authSubscription?.cancel();
    _authSubscription = _repository.authStateChanges.listen(
      _onFirebaseAuthChanged,
      onError: (Object e) => state = state.copyWith(status: AuthStatus.error, errorMessage: e.toString(), isLoading: false),
    );
  }

  /// 初始化为游客（仅在未登录时调用，防止覆盖已有登录态）
  Future<void> initAsGuest() async {
    debugPrint('[AuthNotifier] initAsGuest called, currentFirebaseUser: ${_repository.currentFirebaseUser}');
    final firebaseUser = _repository.currentFirebaseUser;
    // Firebase 已登录（Google/Apple 用户），订阅状态变化并恢复用户
    if (firebaseUser != null) {
      debugPrint('[AuthNotifier] Firebase user exists, restoring session');
      _subscribeFirebaseAuth();
      await _onFirebaseAuthChanged(firebaseUser);
      return;
    }
    // 直接查 storage，不依赖 authService.init() 的 microtask 时序
    final storedToken = await _ref.read(storageServiceProvider).getToken();
    final storedAuthToken = await _ref.read(storageServiceProvider).getAuthTokenAsync();
    final hasToken = (storedToken != null && storedToken.isNotEmpty) ||
        (storedAuthToken != null && storedAuthToken.isNotEmpty);
    if (hasToken) {
      debugPrint('[AuthNotifier] token found in storage, skip initAsGuest, restoring user...');
      // 有 token 但没有缓存用户（App 重启后第一次），从 storage 恢复用户数据
      final userData = await _ref.read(authServiceProvider).getUserData();
      if (userData != null) {
        final user = UserModel.fromJson(userData);
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
        debugPrint('[AuthNotifier] user restored from storage: ${user.userNickname}');
      }
      return;
    }
    debugPrint('[AuthNotifier] no token, creating guest user and fetching guest token...');
    final authService = _ref.read(authServiceProvider);
    final loginResult = await authService.login();
    debugPrint('[AuthNotifier] guest login result: $loginResult');
    final guestId = loginResult?.uuid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guestUser = UserModel.guest(guestId);
    state = state.copyWith(status: AuthStatus.authenticated, user: guestUser);
  }

  /// Firebase 认证状态变化回调
  Future<void> _onFirebaseAuthChanged(User? user) async {
    debugPrint('[AuthNotifier] _onFirebaseAuthChanged user: $user, current status: ${state.status}');
    if (user == null) {
      // Firebase 用户登出时，清本地状态（邮箱登录退出由 signOut() 处理）
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true, isLoading: false, clearError: true);
      return;
    }
    try {
      final model = await _repository.resolveCurrentUser();
      state = state.copyWith(status: AuthStatus.authenticated, user: model, isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _mapError(e), isLoading: false);
    }
  }

  /// 检查认证状态
  Future<void> checkAuthState() async {
    state = state.copyWith(status: AuthStatus.authenticating, isLoading: true, clearError: true);
    try {
      final user = await _repository.resolveCurrentUser();
      if (user != null) state = state.copyWith(status: AuthStatus.authenticated, user: user, isLoading: false);
      else {
        // 不再从缓存恢复用户——邮箱登录不走 Firebase Auth，
        // 退出后 token 已清，直接标记未登录，由 initAsGuest 创建游客
        state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      }
    } catch (e) { state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false, errorMessage: _mapError(e)); }
  }

  /// 邮箱登录
  Future<bool> signInWithEmail(String email, String password) => _runAuth(() => _repository.signInWithEmail(email, password));

  /// 邮箱注册
  Future<bool> signUpWithEmail({required String email, required String password, required String username}) =>
      _runAuth(() => _repository.signUpWithEmail(email: email, password: password, username: username));

  /// Google 登录
  Future<bool> signInWithGoogle() => _runAuth(_repository.signInWithGoogle);

  /// Apple 登录
  Future<bool> signInWithApple() => _runAuth(_repository.signInWithApple);

  /// 发送重置密码邮件
  Future<bool> sendPasswordResetEmail(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try { await _repository.sendPasswordResetEmail(email); state = state.copyWith(isLoading: false); return true; }
    catch (e) { state = state.copyWith(isLoading: false, errorMessage: _mapError(e)); return false; }
  }

  /// 登出
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      // 同步清掉 AuthService 内存中的 token，防止重启后被复用
      await _ref.read(authServiceProvider).logout();
      await _repository.signOut();
      await _repository.clearAutoLoginCredentials();
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true, isLoading: false, clearError: true);
    } catch (e) { state = state.copyWith(isLoading: false, errorMessage: _mapError(e)); }
  }

  /// 清除游客登录状态（注册完成后调用，防止游客身份残留）
  void clearGuestLoginStatus() {
    // ignore: deprecated_member_use_from_same_package
    _ref.read(guestLoginProvider.notifier).state = GuestLoginStatus.initial;
  }

  /// 更新头像（本地 + 后端）
  Future<void> updateAvatar(String avatarUrl) async {
    if (state.user != null) {
      state = state.copyWith(user: state.user!.copyWith(avatar: avatarUrl));
      _repository.saveUserData(state.user!.toJson());
        await apiServiceProvider.updateUserSettings(setId: 2, avatarUrl: avatarUrl);
    }
  }

  /// 从后端 /api/user/userPersonalCenter 返回的数据更新用户信息
  void updateUserFromData(Map<String, dynamic> data) {
    final user = UserModel.fromJson(data);
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }

  /// 更新昵称（本地 + 后端）
  Future<void> updateNickname(String nickname) async {
    if (state.user != null) {
      state = state.copyWith(user: state.user!.copyWith(nickname: nickname));
      _repository.saveUserData(state.user!.toJson());
      await apiServiceProvider.updateUserSettings(setId: 1, nickName: nickname);
    }
  }

  /// 设置语言（本地 + 后端）
  Future<void> setLanguage(String languageCode) async {
    final response = await _ref.read(apiServiceProviderRef).updateUserSettings(
      setId: 3,
      language: languageCode,
    );

    if (!response.isSuccess) {
      throw Exception(response.error ?? 'Failed to update language');
    }

    final normalizedLanguage = languageCode.toLowerCase().startsWith('ar')
        ? 'ar-SA'
        : 'en-US';
    final normalizedLanguageCode = normalizedLanguage.startsWith('ar')
        ? 'ar'
        : 'en';
    final storage = _ref.read(storageServiceProvider);
    await storage.setString(AppConstants.deviceLangKey, normalizedLanguage);
    await storage.setString(AppConstants.localeKey, normalizedLanguageCode);
    await _repository.saveLanguage(normalizedLanguageCode);
    debugPrint(
      '[AuthNotifier] setLanguage persisted deviceLang=${storage.getString(AppConstants.deviceLangKey)} '
      'appLocale=${storage.getString(AppConstants.localeKey)} '
      'languageCode=${await storage.getLanguage()}',
    );
  }

  /// 执行认证操作（统一处理）
  Future<bool> _runAuth(Future<UserModel> Function() action) async {
    state = state.copyWith(status: AuthStatus.authenticating, isLoading: true, clearError: true);
    try {
      final user = await action();
      state = state.copyWith(status: AuthStatus.authenticated, user: user, isLoading: false);
      return true;
    } on AuthCancelledException {
      state = state.copyWith(status: state.user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated, isLoading: false);
      return false;
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: _mapError(e), isLoading: false);
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// 错误码映射
  String _mapError(Object error) {
    if (error is AuthCancelledException) return 'Sign in cancelled';
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email': return 'Invalid email address';
        case 'user-disabled': return 'This account has been disabled';
        case 'user-not-found': return 'No account found with this email';
        case 'wrong-password': return 'Incorrect password';
        case 'email-already-in-use': return 'Email is already registered';
        case 'weak-password': return 'Password is too weak';
        case 'operation-not-allowed': return 'This sign-in method is not enabled';
        case 'invalid-credential': return 'Invalid credentials';
        case 'network-request-failed': return 'Network error. Please check your connection';
        default: return error.message ?? 'Authentication failed';
      }
    }
    return error.toString();
  }

  @override void dispose() { _authSubscription?.cancel(); super.dispose(); }
}
