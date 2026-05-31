import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart';
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
  AuthNotifier(this._ref) : super(const AuthState()) { _init(); }
  final Ref _ref;
  StreamSubscription<User?>? _authSubscription;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  /// 初始化：检查缓存用户 + 监听 Firebase 状态变化
  Future<void> _init() async {
    final cached = await _repository.getCachedUser();
    if (cached != null) state = state.copyWith(status: AuthStatus.authenticated, user: cached);

    _authSubscription = _repository.authStateChanges.listen(
      _onFirebaseAuthChanged,
      onError: (Object e) => state = state.copyWith(status: AuthStatus.error, errorMessage: e.toString(), isLoading: false),
    );
    await checkAuthState();
  }

  /// 初始化为游客
  Future<void> initAsGuest() async {
    final cached = await _repository.getCachedUser();
    if (cached != null) { state = state.copyWith(status: AuthStatus.authenticated, user: cached); return; }
    final guestUser = await _repository.createGuestUser();
    state = state.copyWith(status: AuthStatus.authenticated, user: guestUser);
  }

  /// Firebase 认证状态变化回调
  Future<void> _onFirebaseAuthChanged(User? user) async {
    if (user == null) {
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
        final cached = await _repository.getCachedUser();
        state = state.copyWith(status: cached != null ? AuthStatus.authenticated : AuthStatus.unauthenticated, user: cached, isLoading: false);
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
      await _repository.signOut();
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true, isLoading: false, clearError: true);
    } catch (e) { state = state.copyWith(isLoading: false, errorMessage: _mapError(e)); }
  }

  /// 更新头像
  void updateAvatar(String path) {
    if (state.user != null) {
      state = state.copyWith(user: state.user!.copyWith(avatar: path));
      _repository.saveUserData(state.user!.toJson());
    }
  }

  /// 从后端 /api/user/userPersonalCenter 返回的数据更新用户信息
  void updateUserFromData(Map<String, dynamic> data) {
    final user = UserModel.fromJson(data);
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }

  /// 更新昵称
  void updateNickname(String nickname) {
    if (state.user != null) {
      state = state.copyWith(user: state.user!.copyWith(nickname: nickname));
      _repository.saveUserData(state.user!.toJson());
    }
  }

  /// 设置语言
  void setLanguage(String languageCode) => _repository.saveLanguage(languageCode);

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
