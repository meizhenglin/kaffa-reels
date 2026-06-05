import 'dart:async';
import 'package:flutter/foundation.dart';
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
  AuthNotifier(this._ref) : super(const AuthState()) { _configureGuestLoginCallback(); _startInit(); }
  final Ref _ref;
  StreamSubscription<dynamic>? _authSubscription;
  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  void _configureGuestLoginCallback() {
    _ref.read(dioClientProvider).setOnGuestLogin(() async {
      debugPrint('[AuthNotifier] Dio requested guest login callback');
      final result = await _ref.read(authServiceProvider).ensureGuestLogin();
      final token = result?.token ?? await _ref.read(storageServiceProvider).getToken();
      debugPrint('[AuthNotifier] guest login callback resolved tokenPresent=${token != null && token.isNotEmpty}');
      return token;
    });
  }

  /// 启动初始化（不阻塞 Provider 创建）
  void _startInit() {
    _init().catchError((e) {
      debugPrint('[AuthNotifier] _init error: $e');
    });
  }

  /// 初始化：检查缓存用户 + 监听 Firebase 状态变化
  ///
  /// 统一认证入口：
  /// 1. 若存在自动登录凭证，则优先恢复邮箱正式登录态；
  /// 2. 若本地仍有后端 token，则优先按后端正式用户恢复；
  /// 3. 若 Firebase 当前仍有第三方登录用户，再从 Firebase 恢复；
  /// 4. 否则执行游客初始化。
  ///
  /// 注意：main.dart 不再提前做游客登录，避免启动阶段出现两套认证决策来源。
  Future<void> _init() async {
    final storage = _ref.read(storageServiceProvider);
    final authService = _ref.read(authServiceProvider);
    final hasAutoLogin = await _repository.hasAutoLoginCredentials();
    final storedToken = await storage.getToken();
    final storedUserData = await authService.getUserData();
    final firebaseUser = _repository.currentFirebaseUser;

    debugPrint(
      '[AuthNotifier] _init start '
      'hasAutoLogin=$hasAutoLogin '
      'hasStoredToken=${storedToken != null && storedToken.isNotEmpty} '
      'hasStoredUserData=${storedUserData != null} '
      'firebaseCurrentUser=$firebaseUser',
    );

    if (hasAutoLogin) {
      debugPrint('[AuthNotifier] auto-login credentials found, performing auto-login...');
      state = state.copyWith(status: AuthStatus.authenticating, isLoading: true, clearError: true);
      try {
        final user = await _repository.performAutoLogin();
        state = state.copyWith(status: AuthStatus.authenticated, user: user, isLoading: false);
        debugPrint('[AuthNotifier] auto-login succeeded');
        _subscribeFirebaseAuth();
        return;
      } catch (e) {
        debugPrint('[AuthNotifier] auto-login failed: $e, clearing credentials');
        await _repository.clearAutoLoginCredentials();
        state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      }
    }

    final restoredStoredUser = await _restoreStoredAuthenticatedUser(
      storedToken: storedToken,
      storedUserData: storedUserData,
    );
    if (restoredStoredUser) {
      return;
    }

    if (firebaseUser != null) {
      debugPrint('[AuthNotifier] falling back to Firebase authenticated user restore');
      _subscribeFirebaseAuth();
      await _onFirebaseAuthChanged(firebaseUser);
      return;
    }

    await initAsGuest();
  }

  Future<bool> _restoreStoredAuthenticatedUser({
    required String? storedToken,
    required Map<String, dynamic>? storedUserData,
  }) async {
    final hasToken = storedToken != null && storedToken.isNotEmpty;
    if (!hasToken) {
      return false;
    }

    if (storedUserData == null) {
      debugPrint('[AuthNotifier] stored token found but userData missing, cannot restore authenticated user');
      return false;
    }

    final user = UserModel.fromJson(storedUserData);
    if (user.isTourist) {
      debugPrint('[AuthNotifier] stored token belongs to tourist identity, skip authenticated restore');
      return false;
    }

    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: user,
      isLoading: false,
      clearError: true,
    );
    debugPrint('[AuthNotifier] restored authenticated user from storage: ${user.userNickname}');
    return true;
  }

  /// 订阅 Firebase Auth 状态变化（用于 Google/Apple 登录后的登出监听）
  void _subscribeFirebaseAuth() {
    _authSubscription?.cancel();
    _authSubscription = _repository.authStateChanges.listen(
      _onFirebaseAuthChanged,
      onError: (Object e) => state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
        isLoading: false,
      ),
    );
  }

  /// 初始化为游客（仅在未登录时调用，防止覆盖已有登录态）
  ///
  /// 这里既负责真正的 guest token 获取，也负责在游客接口失败时提供本地 guest UI fallback。
  /// 游客/后端登录态统一只看 user_token；auth_token 仅表示 Firebase 身份，不代表后端接口已可用。
  /// 这样可以避免 user_token 丢失但 auth_token 仍存在时，UI 与网络层判断不一致。
  Future<void> initAsGuest() async {
    debugPrint('[AuthNotifier] initAsGuest called, currentFirebaseUser: ${_repository.currentFirebaseUser}');

    final restoredStoredUser = await _restoreStoredAuthenticatedUser(
      storedToken: await _ref.read(storageServiceProvider).getToken(),
      storedUserData: await _ref.read(authServiceProvider).getUserData(),
    );
    if (restoredStoredUser) {
      debugPrint('[AuthNotifier] initAsGuest aborted because authenticated user was restored from storage');
      return;
    }

    final firebaseUser = _repository.currentFirebaseUser;
    if (firebaseUser != null) {
      debugPrint('[AuthNotifier] Firebase user exists, restoring third-party session');
      _subscribeFirebaseAuth();
      await _onFirebaseAuthChanged(firebaseUser);
      return;
    }

    debugPrint('[AuthNotifier] no authenticated session, creating guest user and fetching guest token...');
    final authService = _ref.read(authServiceProvider);
    final loginResult = await authService.ensureGuestLogin();
    final currentToken = await _ref.read(storageServiceProvider).getToken();
    debugPrint(
      '[AuthNotifier] guest login result: $loginResult tokenPresent=${currentToken != null && currentToken.isNotEmpty}',
    );
    final guestId = loginResult?.uuid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guestUser = UserModel.guest(guestId);
    state = state.copyWith(status: AuthStatus.authenticated, user: guestUser);
  }

  /// Firebase 认证状态变化回调
  Future<void> _onFirebaseAuthChanged(dynamic user) async {
    debugPrint('[AuthNotifier] _onFirebaseAuthChanged user: $user, current status: ${state.status}');
    if (user == null) {
      final storedToken = await _ref.read(storageServiceProvider).getToken();
      final storedUserData = await _ref.read(authServiceProvider).getUserData();
      final restoredStoredUser = await _restoreStoredAuthenticatedUser(
        storedToken: storedToken,
        storedUserData: storedUserData,
      );
      if (restoredStoredUser) {
        debugPrint('[AuthNotifier] Firebase user is null but backend-authenticated email user was restored from storage');
        return;
      }
      // Firebase 用户登出时，清本地状态（邮箱登录/注册若仍有后端 token，会在上面被恢复）
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
  Future<bool> checkAuthState() async {
    state = state.copyWith(status: AuthStatus.authenticating, isLoading: true, clearError: true);
    try {
      final user = await _repository.resolveCurrentUser() ?? await _repository.resolveStoredUser();
      if (user != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isLoading: false,
        );
      } else {
        // 不再从缓存恢复游客；未命中正式登录态时交给后续游客初始化流程处理
        state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        errorMessage: _mapError(e),
      );
    }
    return state.user != null && !state.user!.isTourist;
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
  ///
  /// 清理正式登录态后，立即补做游客初始化，保证 Web 刷新前后与 App 重启后的体验一致。
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final storage = _ref.read(storageServiceProvider);
      debugPrint(
        '[AuthNotifier.signOut] before logout '
        'userToken=${await storage.getToken()} '
        'authToken=${await storage.getAuthTokenAsync()} '
        'userData=${await storage.getUserData()} '
        'autoLogin=${await storage.getAutoLogin()} '
        'autoLoginEmail=${await storage.getAutoLoginEmail()} '
        'currentUser=${state.user?.toJson()}',
      );

      // 先清自动登录，避免冷启动时先被自动登录分支重新拉回正式账号。
      await _repository.clearAutoLoginCredentials();

      // AuthService 负责清理本地后端 token / 用户缓存；
      // Repository 负责清理 Firebase / Google 登录态及其缓存。
      await _ref.read(authServiceProvider).logout();
      await _repository.signOut();

      debugPrint(
        '[AuthNotifier.signOut] after clear '
        'userToken=${await storage.getToken()} '
        'authToken=${await storage.getAuthTokenAsync()} '
        'userData=${await storage.getUserData()} '
        'autoLogin=${await storage.getAutoLogin()} '
        'autoLoginEmail=${await storage.getAutoLoginEmail()} '
        'firebaseCurrentUser=${_repository.currentFirebaseUser}',
      );

      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        clearUser: true,
        clearError: true,
      );
      debugPrint('[AuthNotifier.signOut] local auth state cleared successfully');

      await initAsGuest();
      debugPrint('[AuthNotifier.signOut] guest session restored immediately after logout');
    } catch (e) {
      debugPrint('[AuthNotifier.signOut] error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        clearUser: true,
        errorMessage: _mapError(e),
      );
    }
  }

  /// 清除游客登录状态（注册完成后调用，防止游客身份残留）
  void clearGuestLoginStatus() {
    // ignore: deprecated_member_use_from_same_package
    _ref.read(guestLoginProvider.notifier).state = GuestLoginStatus.initial;
  }

  /// 更新头像（本地 + 后端）
  Future<void> updateAvatar(String avatarUrl) async {
    final currentUser = state.user;
    if (currentUser != null) {
      state = state.copyWith(
        user: currentUser.copyWith(avatar: avatarUrl, photoURL: avatarUrl, isGuest: false),
      );
      await _repository.saveUserData(state.user!.toJson());
    }
    await apiServiceProvider.updateUserSettings(setId: 2, avatarUrl: avatarUrl);
  }

  /// 从后端 /api/user/userPersonalCenter 返回的数据更新用户信息
  Future<void> updateUserFromData(Map<String, dynamic> data) async {
    final currentUser = state.user;
    final rawPassportType = data['passportType'];
    final nextPassportType = rawPassportType is int
        ? rawPassportType
        : int.tryParse(rawPassportType?.toString() ?? '');
    final hasExplicitLoggedInIdentity =
        (data['email']?.toString().trim().isNotEmpty ?? false) ||
        (nextPassportType != null && nextPassportType != 0);
    final shouldDiscardGuestBase =
        currentUser != null && currentUser.isTourist && hasExplicitLoggedInIdentity;

    final mergedData = <String, dynamic>{
      if (currentUser != null && !shouldDiscardGuestBase) ...currentUser.toJson(),
      ...data,
    };

    if (hasExplicitLoggedInIdentity) {
      mergedData['isGuest'] = false;
    } else if (currentUser?.isTourist ?? false) {
      mergedData['isGuest'] = true;
    }

    final currentPassportType = shouldDiscardGuestBase ? null : currentUser?.passportType;
    final shouldPreserveLoggedInPassportType =
        currentPassportType != null &&
        currentPassportType != 0 &&
        (nextPassportType == null || nextPassportType == 0);

    if (shouldPreserveLoggedInPassportType) {
      mergedData['passportType'] = currentPassportType;
    }

    mergedData['userId'] =
        data['userId']?.toString() ??
        data['id']?.toString() ??
        currentUser?.id ??
        '';

    final user = UserModel.fromJson(mergedData);
    final shouldWriteUserCache = !user.isTourist;
    if (shouldWriteUserCache) {
      await _repository.saveUserData(user.toJson());
    }
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: user,
      clearError: true,
    );
  }

  /// 更新昵称（本地 + 后端）
  Future<void> updateNickname(String nickname) async {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(nickname: nickname, displayName: nickname, isGuest: false),
      );
      await _repository.saveUserData(state.user!.toJson());
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

    final errorString = error.toString();
    if (errorString.contains('invalid-email')) return 'Invalid email address';
    if (errorString.contains('user-disabled')) return 'This account has been disabled';
    if (errorString.contains('user-not-found')) return 'No account found with this email';
    if (errorString.contains('wrong-password')) return 'Incorrect password';
    if (errorString.contains('email-already-in-use')) return 'Email is already registered';
    if (errorString.contains('weak-password')) return 'Password is too weak';
    if (errorString.contains('operation-not-allowed')) return 'This sign-in method is not enabled';
    if (errorString.contains('invalid-credential')) return 'Invalid credentials';
    if (errorString.contains('network-request-failed')) return 'Network error. Please check your connection';

    return errorString;
  }

  @override void dispose() { _authSubscription?.cancel(); super.dispose(); }
}
