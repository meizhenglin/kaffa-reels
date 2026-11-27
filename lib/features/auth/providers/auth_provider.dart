import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart'
    show
        GuestLoginStatus,
        guestLoginProvider,
        authServiceProvider,
        apiServiceProviderRef;
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/session_expired_bus.dart';
import '../../payment/providers/coin_record_provider.dart' as coin_record;
import '../../payment/providers/membership_provider.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../services/tiktok_auth_service.dart' show TiktokSignInException;
import '../exceptions/auth_exceptions.dart';

export '../../../core/providers/auth_provider.dart'
    show AuthService, RegisterResult, CheckCodeResult, authServiceProvider;

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
  unauthenticated, // 未认证
  authenticating, // 认证中
  authenticated, // 已认证
  error, // 认证错误
}

class RegistrationSession {
  const RegistrationSession({required this.userId, required this.email});

  final String userId;
  final String email;

  RegistrationSession copyWith({String? userId, String? email}) =>
      RegistrationSession(
        userId: userId ?? this.userId,
        email: email ?? this.email,
      );
}

/// 认证状态数据类
class AuthState {
  const AuthState({
    this.status = AuthStatus.authenticating,
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.registrationSession,
  });

  final AuthStatus status; // 当前状态
  final UserModel? user; // 用户信息
  final bool isLoading; // 是否加载中
  final String? errorMessage; // 错误信息
  final RegistrationSession? registrationSession;

  /// 是否已登录
  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isLoading,
    String? errorMessage,
    RegistrationSession? registrationSession,
    bool clearUser = false,
    bool clearError = false,
    bool clearRegistrationSession = false,
  }) => AuthState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    registrationSession: clearRegistrationSession
        ? null
        : (registrationSession ?? this.registrationSession),
  );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(storageServiceProvider),
    ref.watch(apiServiceProviderRef),
  ),
);
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);

/// 认证状态管理器
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) {
    _configureGuestLoginCallback();
    _subscribeSessionExpired();
    _startInit();
  }
  final Ref _ref;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<SessionExpiredReason>? _sessionExpiredSubscription;
  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  void _configureGuestLoginCallback() {
    _ref.read(dioClientProvider).setOnGuestLogin(() async {
      debugPrint('[AuthNotifier] Dio requested guest login callback');
      final result = await _ref.read(authServiceProvider).ensureGuestLogin();
      final token =
          result?.token ?? await _ref.read(storageServiceProvider).getToken();
      debugPrint(
        '[AuthNotifier] guest login callback resolved tokenPresent=${token != null && token.isNotEmpty}',
      );
      return token;
    });
  }

  /// 订阅全局"会话失效"事件
  ///
  /// dio_client 在收到 code=23 / HTTP 401 时会触发该事件；
  /// AuthNotifier 收到后清空本地状态 + 触发 App 跳登录页。
  void _subscribeSessionExpired() {
    _sessionExpiredSubscription?.cancel();
    _sessionExpiredSubscription = SessionExpiredBus().onSessionExpired.listen(
      _handleSessionExpired,
    );
    debugPrint('[AuthNotifier] subscribed to SessionExpiredBus');
  }

  /// 处理会话失效：清空 token + 状态，让 UI 走匿名/重新登录路径
  Future<void> _handleSessionExpired(SessionExpiredReason reason) async {
    debugPrint('[AuthNotifier] _handleSessionExpired: $reason');
    // 已经是 unauthenticated 就不重复处理
    if (state.status == AuthStatus.unauthenticated) {
      debugPrint('[AuthNotifier] already unauthenticated, skip');
      return;
    }

    try {
      // 清掉本地 token / userData
      await _ref.read(storageServiceProvider).removeToken();
      await _ref.read(storageServiceProvider).removeUserData();
      // 通知后端登出（如有需要），但不阻塞
      unawaited(
        _repository.signOut().catchError((e) {
          debugPrint('[AuthNotifier] signOut on session expired error: $e');
        }),
      );
    } catch (e) {
      debugPrint('[AuthNotifier] _handleSessionExpired error: $e');
    }

    // 更新状态为 unauthenticated + 显示友好提示
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      isLoading: false,
      clearUser: true,
      errorMessage: 'Your session has expired. Please log in again.',
      clearError: false,
    );
  }

  /// 启动初始化（不阻塞 Provider 创建）
  void _startInit() {
    _init().catchError((e) {
      debugPrint('[AuthNotifier] _init error: $e');
    });
  }

  /// 初始化：检查 token 并恢复登录状态
  ///
  /// 统一认证入口：
  /// 1. 有 token → 用 token 从后端获取用户信息
  /// 2. 无 token → 进入游客模式
  ///
  /// 注意：游客和正式账号共享同一套 token/userData 存储，
  /// 区别只在于 isGuest 标记和后端返回的用户信息。
  Future<void> _init() async {
    final storage = _ref.read(storageServiceProvider);
    final authService = _ref.read(authServiceProvider);
    final storedToken = await storage.getToken();
    final storedUserData = await authService.getUserData();

    debugPrint(
      '[AuthNotifier] _init start '
      'hasStoredToken=${storedToken != null && storedToken.isNotEmpty} '
      'storedTokenPreview=${storedToken != null && storedToken.isNotEmpty ? '${storedToken.substring(0, storedToken.length > 12 ? 12 : storedToken.length)}...' : 'null'} '
      'hasStoredUserData=${storedUserData != null}',
    );

    if (storedToken != null && storedToken.isNotEmpty) {
      debugPrint(
        '[AuthNotifier] token found, fetching user info from backend...',
      );
      state = state.copyWith(
        status: AuthStatus.authenticating,
        isLoading: true,
        clearError: true,
      );
      // 后端是否**明确拒绝**了这张 token（401 / token 过期）。
      // 只有"明确拒绝"才可以登出；超时、断网、5xx 都是临时故障。
      var tokenRejected = false;
      try {
        final resp = await apiServiceProvider.getUserCenter();
        if (resp.isSuccess && resp.data != null) {
          await updateUserFromData(resp.data as Map<String, dynamic>);
          debugPrint(
            '[AuthNotifier] user info fetched from backend successfully',
          );
          return;
        }
        tokenRejected = resp.isExpired || resp.code == 401;
        if (tokenRejected) {
          debugPrint(
            '[AuthNotifier] token rejected by backend '
            'code=${resp.code} expired=${resp.isExpired}',
          );
        }
      } catch (e) {
        debugPrint('[AuthNotifier] failed to fetch user info from backend: $e');
      }

      // token 被明确拒绝：没有任何"缓存兜底"的余地，清数据进游客态。
      if (tokenRejected) {
        await _clearAllAuthData();
        await _enterGuestMode();
        return;
      }

      // API 调用失败时，不要直接清除数据
      // 检查 Firebase Auth 是否有用户（热重载时 Firebase Auth 状态可能还在）
      final firebaseUser = _repository.currentFirebaseUser;
      if (firebaseUser != null) {
        debugPrint(
          '[AuthNotifier] Firebase user still logged in, trying to refresh...',
        );
        try {
          await _repository.refreshIdToken(forceRefresh: true);
          final resp = await apiServiceProvider.getUserCenter();
          if (resp.isSuccess && resp.data != null) {
            await updateUserFromData(resp.data as Map<String, dynamic>);
            debugPrint('[AuthNotifier] user info fetched after token refresh');
            return;
          }
        } catch (e) {
          debugPrint(
            '[AuthNotifier] failed to refresh and fetch user info: $e',
          );
        }
        // Firebase Auth 有用户但无法恢复登录，保留 Firebase 状态
        final userModel = await _repository.getUserModelFromFirebaseUser();
        if (userModel != null) {
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: userModel,
            isLoading: false,
          );
          debugPrint(
            '[AuthNotifier] restored user from Firebase (API unavailable)',
          );
          return;
        }
      }

      // 【兜底】Firebase 也没有用户时，仍然不能把"请求失败"当成"未登录"：
      // 只要本地有正式账号的缓存资料，就用它恢复登录态（数据可能略旧），
      // token 保留不动，网络恢复后由 refreshUserInfo / ProfileTab 自动校正。
      if (await _restoreStoredUserData(storedUserData)) return;

      // 确实没有任何可恢复的身份 → 清除所有数据进入游客态
      await _clearAllAuthData();
    }

    // 无 token，进入游客模式
    await _enterGuestMode();
  }

  /// 用本地缓存的用户资料恢复登录态（网络/服务端临时故障时的兜底）。
  ///
  /// 只在缓存里是**正式账号**时生效：游客缓存没有恢复价值，反而会把
  /// 已登录用户降级成游客。
  /// 故意不清 token —— token 本身可能仍然有效，只是这一次请求失败了。
  Future<bool> _restoreStoredUserData(
    Map<String, dynamic>? storedUserData,
  ) async {
    if (storedUserData == null) return false;
    try {
      // 401 / code=23 时 dio 拦截器会先清掉本地 token 并广播"会话失效"。
      // token 已经不存在，说明这次失败是身份失效而不是断网——
      // 此时绝不能再用缓存把用户"恢复"成已登录。
      final token = await _ref.read(storageServiceProvider).getToken();
      if (token == null || token.isEmpty) {
        debugPrint(
          '[AuthNotifier] token already cleared (session expired), '
          'skip offline restore',
        );
        return false;
      }

      final cachedUser = UserModel.fromJson(storedUserData);
      if (cachedUser.id.isEmpty || cachedUser.isTourist) {
        debugPrint(
          '[AuthNotifier] cached user data is tourist/empty, '
          'skip offline restore',
        );
        return false;
      }
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: cachedUser,
        isLoading: false,
        clearError: true,
      );
      debugPrint(
        '[AuthNotifier] restored login from cached user data '
        '(network unavailable) id=${cachedUser.id}',
      );
      unawaited(_retryRefreshAfterOfflineRestore());
      return true;
    } catch (e) {
      debugPrint('[AuthNotifier] offline restore from cache failed: $e');
      return false;
    }
  }

  /// 离线兜底恢复后，延迟重试一次后端刷新，把可能过期的数据校正回来。
  ///
  /// 失败无副作用（refreshUserInfo 内部已吞掉异常，保留当前状态）。
  Future<void> _retryRefreshAfterOfflineRestore() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!state.isAuthenticated) return;
    await refreshUserInfo();
  }

  Future<void> _clearAllAuthData() async {
    debugPrint('[AuthNotifier] clearing all auth data...');
    await _repository.clearAutoLoginCredentials();
    await _ref.read(authServiceProvider).logout();
    await _repository.signOut();

    // Clear VIP/membership state for the old account
    try {
      await _ref.read(memberStateProvider.notifier).clearAll();
    } catch (_) {}

    // 【K币余额清零】重置余额状态与节流时间戳，避免旧账号余额串到
    // 游客视角，也保证重新登录后的余额刷新不会被 TTL 节流跳过。
    try {
      _ref.read(coin_record.coinBalanceInfoProvider.notifier).reset();
    } catch (_) {}

    state = state.copyWith(clearRegistrationSession: true);
    debugPrint('[AuthNotifier] all auth data cleared');
  }

  /// 初始化为游客
  Future<void> initAsGuest() async {
    await _enterGuestMode();
  }

  /// 进入游客模式
  Future<void> _enterGuestMode() async {
    debugPrint('[AuthNotifier] entering guest mode...');
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
    );

    final authService = _ref.read(authServiceProvider);
    final loginResult = await authService.ensureGuestLogin();
    final storage = _ref.read(storageServiceProvider);
    final currentToken = await storage.getToken();
    final hasGuestToken = currentToken != null && currentToken.isNotEmpty;

    debugPrint(
      '[AuthNotifier] guest login result: '
      'uuid=${loginResult?.uuid} '
      'resultTokenPresent=${loginResult?.token.isNotEmpty == true} '
      'storedTokenPresent=$hasGuestToken',
    );

    if (!hasGuestToken) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        errorMessage: 'Guest login failed',
        clearUser: true,
      );
      debugPrint(
        '[AuthNotifier] failed to enter guest mode because no token was obtained',
      );
      return;
    }

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final userData = resp.data as Map<String, dynamic>;
        final fetchedUser = UserModel.fromJson(
          userData,
        ).copyWith(isGuest: false);
        if (!fetchedUser.isTourist) {
          await updateUserFromData(userData);
          debugPrint(
            '[AuthNotifier] guest fallback resolved to formal user, skip guest overwrite '
            'userId=${fetchedUser.id}',
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] guest mode verification failed: $e');
    }

    final currentUser = state.user;
    if (currentUser != null && !currentUser.isTourist) {
      debugPrint(
        '[AuthNotifier] skip guest overwrite because formal user already active '
        'userId=${currentUser.id}',
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
        clearError: true,
      );
      return;
    }

    final guestId =
        loginResult?.uuid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guestUser = UserModel.guest(guestId);

    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: guestUser,
      isLoading: false,
      clearRegistrationSession: true,
    );
    debugPrint(
      '[AuthNotifier] guest mode entered '
      'userId: $guestId '
      'tokenPresent=$hasGuestToken '
      'isTourist=${guestUser.isTourist}',
    );
  }

  /// 检查认证状态并刷新用户信息
  Future<bool> checkAuthState() async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
    );
    try {
      final storage = _ref.read(storageServiceProvider);
      final token = await storage.getToken();

      if (token == null || token.isEmpty) {
        // 无 token，进入游客模式
        await _enterGuestMode();
        return false;
      }

      // 有 token，从后端获取最新用户信息
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        await updateUserFromData(resp.data as Map<String, dynamic>);
        return true;
      } else {
        // 后端请求失败，清除 token 进入游客模式
        await _clearAllAuthData();
        await _enterGuestMode();
        return false;
      }
    } catch (e) {
      debugPrint('[AuthNotifier] checkAuthState error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        errorMessage: _mapError(e),
      );
      return false;
    }
  }

  /// 邮箱登录
  Future<bool> signInWithEmail(String email, String password) async {
    final success = await _runAuth(
      () => _repository.signInWithEmail(email, password),
    );
    if (!success) return false;

    state = state.copyWith(clearRegistrationSession: true);

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        await updateUserFromData(resp.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint(
        '[AuthNotifier] signInWithEmail post-login profile refresh failed: $e',
      );
    }

    return true;
  }

  /// 注册流程内使用的邮箱登录。
  /// 只更新认证状态与用户信息，不承担页面跳转职责，避免与普通登录流程冲突。
  Future<bool> signInWithEmailForRegistration(
    String email,
    String password,
  ) async {
    final success = await _runAuth(
      () => _repository.signInWithEmail(email, password),
    );
    if (!success) return false;

    final currentUser = state.user;
    state = state.copyWith(
      registrationSession: RegistrationSession(
        userId: currentUser?.id ?? '',
        email: (currentUser?.email ?? email).trim(),
      ),
    );

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        await updateUserFromData(resp.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint(
        '[AuthNotifier] signInWithEmailForRegistration post-login profile refresh failed: $e',
      );
    }

    return true;
  }

  /// 邮箱注册
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    final success = await _runAuth(
      () => _repository.signUpWithEmail(
        email: email,
        password: password,
        username: username,
      ),
    );
    if (!success) return false;

    final currentUser = state.user;
    state = state.copyWith(
      registrationSession: RegistrationSession(
        userId: currentUser?.id ?? '',
        email: (currentUser?.email ?? email).trim(),
      ),
    );

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        await updateUserFromData(resp.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint(
        '[AuthNotifier] signUpWithEmail post-login profile refresh failed: $e',
      );
    }

    return true;
  }

  /// Google 登录
  ///
  /// 【不再 post-login 刷新】repository.signInWithGoogle 内部
  /// （_userModelFromFirebaseUser → _refreshVipStatusFromBackend）已经拉过
  /// 一次 userPersonalCenter 并把结果合进返回的 UserModel，_runAuth 会把
  /// 它写进 state。这里原来又 refreshUserInfo 风格地打一遍同一接口，纯属重复。
  Future<bool> signInWithGoogle() async {
    final success = await _runAuth(_repository.signInWithGoogle);
    if (!success) return false;

    state = state.copyWith(clearRegistrationSession: true);
    return true;
  }

  /// Facebook 登录（理由同 signInWithGoogle，repository 内部已拉过用户信息）
  Future<bool> signInWithFacebook() async {
    final success = await _runAuth(_repository.signInWithFacebook);
    if (!success) return false;

    state = state.copyWith(clearRegistrationSession: true);
    return true;
  }

  /// TikTok 登录（理由同 signInWithGoogle，TikTokLoginFlow 内部已拉过用户信息）
  Future<bool> signInWithTikTok() async {
    final success = await _runAuth(_repository.signInWithTikTok);
    if (!success) return false;

    state = state.copyWith(clearRegistrationSession: true);
    return true;
  }

  /// Apple 登录（理由同 signInWithGoogle，AppleLoginFlow 内部已拉过用户信息）
  Future<bool> signInWithApple() async {
    final success = await _runAuth(_repository.signInWithApple);
    if (!success) return false;

    state = state.copyWith(clearRegistrationSession: true);
    return true;
  }

  /// 发送重置密码邮件
  Future<bool> sendPasswordResetEmail(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.sendPasswordResetEmail(email);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _mapError(e));
      return false;
    }
  }

  /// 登出
  ///
  /// 完全退出：清空所有登录信息，然后进入游客模式。
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final storage = _ref.read(storageServiceProvider);
      debugPrint(
        '[AuthNotifier.signOut] clearing all auth data before logout '
        'userToken=${await storage.getToken()} '
        'userData=${await storage.getUserData()}',
      );

      // 清除所有认证数据
      await _clearAllAuthData();

      // 进入游客模式
      await _enterGuestMode();

      debugPrint('[AuthNotifier.signOut] logout completed, entered guest mode');
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

  void clearRegistrationSession() {
    state = state.copyWith(clearRegistrationSession: true);
  }

  /// 更新头像（本地 + 后端）
  Future<void> updateAvatar(String avatarUrl) async {
    final currentUser = state.user;
    if (currentUser != null) {
      state = state.copyWith(
        user: currentUser.copyWith(
          avatar: avatarUrl,
          photoURL: avatarUrl,
          isGuest: false,
        ),
      );
      await _repository.saveUserData(state.user!.toJson());
    }
    await apiServiceProvider.updateUserSettings(setId: 2, avatarUrl: avatarUrl);
  }

  /// 从后端 /api/user/userPersonalCenter 返回的数据更新用户信息
  ///
  /// 登录正式账号时调用，直接使用后端返回的数据，不与旧游客数据混合。
  Future<void> updateUserFromData(Map<String, dynamic> data) async {
    final incomingUser = UserModel.fromJson(data).copyWith(isGuest: false);
    final currentUser = state.user;

    if (currentUser != null &&
        !currentUser.isTourist &&
        incomingUser.isTourist &&
        incomingUser.id != currentUser.id) {
      debugPrint(
        '[AuthNotifier] ignore tourist overwrite '
        'currentId=${currentUser.id} incomingId=${incomingUser.id}',
      );
      state = state.copyWith(isLoading: false, clearError: true);
      return;
    }

    await _repository.saveUserData(incomingUser.toJson());
    await _repository.cacheUser(incomingUser);

    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: incomingUser,
      clearError: true,
      isLoading: false,
    );

    // 【K币余额同步刷新】这里的数据来自 userPersonalCenter，顺带把
    // K币余额也更新了 —— 以前只有 ProfileTab._loadUserInfo 会更新余额，
    // 而它有 15 秒 TTL 节流，登出后马上重新登录时刷新会被跳过，
    // 个人中心就显示 0。登录路径在这里直接同步，不再依赖节流窗口。
    try {
      _ref.read(coin_record.coinBalanceInfoProvider.notifier).updateFromData(
        data,
      );
    } catch (e) {
      debugPrint('[AuthNotifier] update coin balance from data failed: $e');
    }

    debugPrint(
      '[AuthNotifier] user data updated from backend: '
      'nickname=${incomingUser.userNickname} '
      'id=${incomingUser.id} '
      'isTourist=${incomingUser.isTourist}',
    );
  }

  /// 正在进行中的 refreshUserInfo。并发调用共享同一次请求。
  Future<void>? _refreshUserInfoInFlight;

  /// 从后端刷新用户信息（用于订阅购买后更新 VIP 到期时间）
  ///
  /// 【并发去重】购买成功后 `purchase()` 末尾和 purchaseStream 回调
  /// （`_handlePurchaseComplete`）会几乎同时触发刷新，
  /// 会员页的购买回调也会再触发一次。以前这些调用各自打一遍
  /// `/api/user/userPersonalCenter`；现在同一时刻的调用共享同一个请求。
  Future<void> refreshUserInfo() {
    final inFlight = _refreshUserInfoInFlight;
    if (inFlight != null) return inFlight;

    final future = _doRefreshUserInfo();
    _refreshUserInfoInFlight = future;
    return future.whenComplete(() {
      _refreshUserInfoInFlight = null;
    });
  }

  Future<void> _doRefreshUserInfo() async {
    if (state.user == null || state.user!.isTourist) return;

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        await updateUserFromData(resp.data as Map<String, dynamic>);
        debugPrint('[AuthNotifier] refreshUserInfo succeeded');
      } else {
        debugPrint('[AuthNotifier] refreshUserInfo failed: ${resp.error}');
      }
    } catch (e) {
      debugPrint('[AuthNotifier] refreshUserInfo error: $e');
    }
  }

  /// 直接更新用户信息（不经过后端，用于本地状态同步）
  void updateUserDirectly(UserModel user) {
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: user,
      clearError: true,
      isLoading: false,
    );
    debugPrint(
      '[AuthNotifier] user data updated directly: '
      'nickname=${user.userNickname} '
      'id=${user.id} '
      'membershipExpiryDate=${user.membershipExpiryDate}',
    );
  }

  /// 更新昵称（本地 + 后端）
  Future<void> updateNickname(String nickname) async {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(
          nickname: nickname,
          displayName: nickname,
          isGuest: false,
        ),
      );
      await _repository.saveUserData(state.user!.toJson());
      await apiServiceProvider.updateUserSettings(setId: 1, nickName: nickname);
    }
  }

  /// 设置语言（本地 + 后端）
  Future<void> setLanguage(String languageCode) async {
    final response = await _ref
        .read(apiServiceProviderRef)
        .updateUserSettings(setId: 3, language: languageCode);

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
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
    );
    try {
      final user = await action();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      return true;
    } on AuthCancelledException {
      state = state.copyWith(
        status: state.user != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        isLoading: false,
      );
      return false;
    } catch (e, stackTrace) {
      debugPrint('[AuthNotifier] auth action failed (${e.runtimeType})');
      debugPrint('$stackTrace');
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _mapError(e),
        isLoading: false,
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// 从 TikTok 错误详情里抽出 `logid=...`，拼到用户可见的提示后面。
  ///
  /// 【为什么要把 logid 给用户看】
  /// logid 是 TikTok 支持团队定位服务端日志的**唯一**凭据。
  /// 之前它只写在 debugPrint 里，release 包看不到、用户也没法复制，
  /// 导致每次失败都只能靠猜。放到弹窗文案里，用户截图即可拿到。
  String _tiktokLogIdSuffix(String detail) {
    final match = RegExp(r'logid=([A-Za-z0-9]+)').firstMatch(detail);
    if (match == null) return '';
    return ' (logid: ${match.group(1)})';
  }

  /// 错误码映射
  String _mapError(Object error) {
    if (error is AuthCancelledException) return 'Sign in cancelled';
    if (error is GoogleSignInException) {
      switch (error.code) {
        case 'google-network-error':
          return 'Google sign-in could not reach Google services. Please check your network and Google Play services, then try again.';
        case 'google-sign-in-timeout':
          return 'Google sign-in timed out. Please retry on a more stable network.';
        case 'google-play-services-unavailable':
          return 'Google Play services is unavailable or outdated on this device. Please update it and try again.';
        case 'google-sign-in-config-error':
          return 'Google sign-in configuration is invalid for this build. Please verify Firebase/Google sign-in setup.';
      }
      return _normalizeErrorMessage(error.message);
    }
    if (error is TiktokSignInException) {
      switch (error.code) {
        case 'tiktok-platform-unsupported':
          return 'TikTok sign-in is not supported on this device.';
        case 'tiktok-authorize-code-refused':
          return 'TikTok accepted your login but refused to authorize this app. The redirect URI is most likely not registered in Login Kit → Web (or the change was not submitted as a new revision) — please contact support.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-app-product-not-enabled':
          return 'TikTok rejected the request before validating the redirect URI. This usually means Login Kit → Web is not enabled or not yet approved for this app, or the signed-in account is not a Sandbox Target User.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-invalid-client-key':
          return 'TikTok rejected the Client Key. Please verify it in TikTok Developer Portal → Login Kit.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-invalid-scope':
          return 'TikTok rejected the requested scope. Please verify the scopes enabled for Login Kit.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-redirect-uri-mismatch':
          return 'TikTok redirect URI is not registered. Please add it in TikTok Developer Portal → Login Kit → Web → Redirect URI.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-missing-auth-code':
          return 'TikTok did not return an authorization code. Please verify Login Kit is enabled and Client Key is correct.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-access-denied':
          return 'Authorization was denied. Please try again.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-server-error':
          return 'TikTok is temporarily unavailable. Please try again later.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-network-error':
          return 'TikTok sign-in could not reach TikTok services. Please try again on a stable network.';
        case 'tiktok-config-error':
          return 'TikTok Client Key is invalid. Please verify the configuration in TikTok Developer Portal.';
        case 'tiktok-authorize-rejected':
          return 'TikTok rejected the login request. Please try again, or contact support with the log ID if the problem persists.${_tiktokLogIdSuffix(error.message)}';
        case 'tiktok-not-configured':
          return 'TikTok Login Kit is not yet approved. Please check back later.';
        case 'tiktok-state-mismatch':
          return 'TikTok authorization state mismatch (CSRF detected). Please try again.';
        case 'tiktok-timeout':
          return 'TikTok login timed out. Please try again.';
        case 'tiktok-no-navigator':
          return 'TikTok login page failed to open. Please restart the app.';
        case 'tiktok-unknown-error':
        default:
          return _normalizeErrorMessage(error.message);
      }
    }

    final errorString = _normalizeErrorMessage(error.toString());
    final normalizedLower = errorString.toLowerCase();

    if (normalizedLower.contains('invalid-email'))
      return 'Invalid email address';
    if (normalizedLower.contains('user-disabled'))
      return 'This account has been disabled';
    if (normalizedLower.contains('user-not-found'))
      return 'No account found with this email';
    if (normalizedLower.contains('wrong-password')) return 'Incorrect password';
    if (normalizedLower.contains('email-already-in-use'))
      return 'Email is already registered';
    if (normalizedLower.contains('weak-password'))
      return 'Password is too weak';
    if (normalizedLower.contains('operation-not-allowed'))
      return 'This sign-in method is not enabled';
    if (normalizedLower.contains('invalid-credential'))
      return 'Invalid credentials';
    if (normalizedLower.contains('network-request-failed'))
      return 'Network error. Please check your connection';
    if (normalizedLower.contains('token is missing'))
      return 'Login failed. Please try again.';
    if (normalizedLower.contains('guest login failed'))
      return 'Unable to enter guest mode. Please try again.';
    if (normalizedLower.contains('login failed'))
      return 'Login failed. Please check your account and password.';
    if (normalizedLower.contains('registration failed'))
      return 'Registration failed. Please try again.';
    if (normalizedLower.contains('email is already registered'))
      return 'Email is already registered';
    if (normalizedLower.contains('passwords do not match'))
      return 'Passwords do not match';
    if (normalizedLower.contains('apiexception: 7') ||
        normalizedLower.contains('network_error')) {
      return 'Google sign-in could not reach Google services. Please check your network and Google Play services, then try again.';
    }

    return errorString.isEmpty
        ? 'Something went wrong. Please try again.'
        : errorString;
  }

  String _normalizeErrorMessage(String message) {
    final normalized = message
        .replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^FirebaseAuthException\([^)]+\):\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
        .trim();
    return normalized;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _sessionExpiredSubscription?.cancel();
    super.dispose();
  }
}
