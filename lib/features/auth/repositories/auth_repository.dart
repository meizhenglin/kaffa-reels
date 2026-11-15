import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'google_sign_in_client_stub.dart'
    if (dart.library.io) 'google_sign_in_client_mobile.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/firebase/firebase_service.dart';
import '../../../core/model/api_endpoints.dart' show PassportType;
import '../../../core/network/api_service.dart';
import '../../../core/network/retry_helper.dart';
import '../../../core/storage/storage_service.dart';
import '../models/user_model.dart';
import '../services/tiktok_auth_service.dart'
    show TiktokAuthService, TiktokLoginResult, TiktokSignInException;
import '../exceptions/auth_exceptions.dart';

/// [DEBUG] Facebook 登录 Mock 开关。
///
/// 仅当：
///   1. kDebugMode = true（debug 构建）
///   2. kEnableFacebookMock = true（手动开启）
/// 时会走 Mock 流程，绕过 Facebook 服务器端拒绝。
///
/// 上线前请确保 kEnableFacebookMock = false。
const bool kEnableFacebookMock = false;

class AuthRepository {
  AuthRepository(this._storage, this._apiService);

  static const List<String> _googleScopes = <String>['email', 'profile'];
  static const String _googleServerClientId =
      '278933660671-jrqbp7tau6kofqgnar97qrat346uv0kp.apps.googleusercontent.com';

  final StorageService _storage;
  final ApiService _apiService;
  ApiService get apiService => _apiService;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  GoogleSignInClient? _googleSignIn;
  final Logger _logger = Logger();

  bool get _isFirebaseAuthAvailable => FirebaseService.isInitialized;

  Stream<User?> get authStateChanges {
    if (!_isFirebaseAuthAvailable) {
      return const Stream<User?>.empty();
    }
    return _auth.authStateChanges();
  }

  User? get currentFirebaseUser {
    if (!_isFirebaseAuthAvailable) {
      return null;
    }
    try {
      return _auth.currentUser;
    } catch (e) {
      _logger.w('[AuthRepo] currentFirebaseUser unavailable: $e');
      return null;
    }
  }

  Future<UserModel?> getCachedUser() async {
    final json = _storage.getString(AppConstants.userCacheKey);
    if (json == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      _logger.w('Failed to parse cached user: $e');
      return null;
    }
  }

  Future<void> cacheUser(UserModel user) async {
    await _storage.setString(
      AppConstants.userCacheKey,
      jsonEncode(user.toJson()),
    );
  }

  Future<void> clearCache() async {
    await _storage.remove(AppConstants.userCacheKey);
    await _storage.removeUserData();
    await _storage.clearAuthToken();
    await _storage.removeToken();
  }

  Future<String?> refreshIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final token = await user.getIdToken(forceRefresh);
    if (token != null) {
      await _storage.saveAuthToken(token);
    }
    return token;
  }

  /// Get UserModel from current Firebase user (public method for hot reload recovery)
  Future<UserModel?> getUserModelFromFirebaseUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _userModelFromFirebaseUser(user, refreshFirebaseIdToken: false);
  }

  Future<UserModel> _userModelFromFirebaseUser(
    User user, {
    bool refreshFirebaseIdToken = true,
  }) async {
    if (refreshFirebaseIdToken) {
      await refreshIdToken();
    }
    final cached = await getCachedUser();

    return UserModel.fromFirebaseData(
      {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'createdAt': user.metadata.creationTime,
        'isEmailVerified': user.emailVerified,
      },
      membershipType: cached?.membershipType ?? MembershipType.regular,
      membershipExpiryDate: cached?.membershipExpiryDate,
    );
  }

  Future<UserModel> _refreshVipStatusFromBackend(UserModel model) async {
    try {
      final resp = await apiService.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final userCenterData = resp.data as Map<String, dynamic>;
        final isVip = userCenterData['isVip'] as int? ?? 0;
        final vipEndTime = userCenterData['vipEndTime'] as String?;
        return model.copyWith(
          membershipType: isVip == 1
              ? MembershipType.premium
              : MembershipType.regular,
          membershipExpiryDate: vipEndTime != null
              ? DateTime.tryParse(vipEndTime)
              : null,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[AuthRepo] Failed to refresh VIP status from backend: $e');
      _logger.e(
        '[AuthRepo] Failed to refresh VIP status from backend',
        error: e,
        stackTrace: stackTrace,
      );
    }
    return model;
  }

  Future<void> warmUpGoogleSignIn() async {
    if (!isGoogleSignInSupported) {
      _logger.i(
        '[AuthRepo] Google sign-in warm-up skipped: unsupported on current platform/config',
      );
      return;
    }

    _initializeGoogleSignInIfSupported();

    debugPrint(
      '[GoogleLoginFlow] googleSignIn config scopes=$_googleScopes serverClientId=$_googleServerClientId',
    );
    _logger.i(
      '[AuthRepo] Google sign-in warm-up skipped on Android to avoid chooser startup delay',
    );
  }

  /// 调用后端登录接口，同步 Firebase Token 到后端
  ///
  /// 【重试】最多 3 次，指数退避（800ms / 1600ms / 3200ms）
  /// - 重试：网络错误、超时、5xx
  /// - 不重试：4xx（401/403/400 都是用户/认证问题）
  Future<bool> _syncBackendToken(
    Future<ApiResponse> Function() apiCall, {
    bool retry = true,
  }) async {
    try {
      final response = retry
          ? await RetryHelper.retry(
              apiCall,
              maxAttempts: 3,
              baseDelay: const Duration(milliseconds: 800),
              onRetry: (attempt, error) {
                _logger.w(
                  '[_syncBackendToken] attempt $attempt failed; retrying with error type ${error.runtimeType}',
                );
              },
            )
          : await apiCall();
      if (response.isSuccess && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final backendToken = data['token'] as String?;
        if (backendToken != null && backendToken.isNotEmpty) {
          await _storage.saveToken(backendToken);
          return true;
        }
      }
      return false;
    } catch (e) {
      _logger.e(
        '[_syncBackendToken] retries exhausted; error type ${e.runtimeType}',
      );
      return false;
    }
  }

  Future<void> _ensureFirebaseAuthReady() async {
    if (!FirebaseService.isInitialized) {
      throw StateError(
        'Firebase Auth is unavailable because Firebase is not initialized.',
      );
    }
  }

  GoogleSignInClient get _requiredGoogleSignIn {
    final instance = _googleSignIn;
    if (instance == null) {
      throw GoogleSignInException(
        'google-sign-in-not-configured',
        'Google Sign-In is not configured for this platform.',
      );
    }
    return instance;
  }

  bool get isGoogleSignInSupported {
    if (!FirebaseService.isInitialized) {
      return false;
    }
    if (kIsWeb) {
      return false;
    }
    // Google Play 和平台端都支持 Google 登录
    return true;
  }

  void _initializeGoogleSignInIfSupported() {
    if (!isGoogleSignInSupported || _googleSignIn != null) {
      return;
    }

    _googleSignIn = createGoogleSignInClient(
      scopes: _googleScopes,
      serverClientId: _googleServerClientId,
    );
  }

  Exception _normalizeGoogleSignInError(Object error) {
    if (error is AuthCancelledException || error is GoogleSignInException) {
      return error as Exception;
    }

    if (error is TimeoutException) {
      return GoogleSignInException(
        'google-sign-in-timeout',
        'Google sign-in timed out. Please try again on a stable network.',
      );
    }

    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message =
          (error.message ?? error.details?.toString() ?? error.toString())
              .toLowerCase();

      if (code.contains('sign_in_canceled') ||
          code.contains('canceled') ||
          code.contains('cancelled')) {
        return AuthCancelledException();
      }

      if (code.contains('network_error') ||
          message.contains('apiexception: 7') ||
          message.contains('network error')) {
        return GoogleSignInException(
          'google-network-error',
          'Google services network request failed.',
        );
      }

      if (code.contains('sign_in_failed') ||
          message.contains('12500') ||
          message.contains('10:')) {
        return GoogleSignInException(
          'google-sign-in-config-error',
          'Google Sign-In configuration is invalid on this device/build.',
        );
      }

      if (message.contains('12501')) {
        return AuthCancelledException();
      }

      if (message.contains('play services') ||
          message.contains('developer_error')) {
        return GoogleSignInException(
          'google-play-services-unavailable',
          'Google Play services is unavailable or outdated.',
        );
      }
    }

    if (error is FirebaseAuthException) {
      if (error.code == 'network-request-failed') {
        return GoogleSignInException(
          'google-network-error',
          error.message ??
              'Firebase network request failed during Google sign-in.',
        );
      }
      if (error.code == 'invalid-credential' ||
          error.code == 'invalid-verification-code') {
        return GoogleSignInException(
          'google-sign-in-config-error',
          error.message ?? 'Google credential verification failed.',
        );
      }
    }

    final errorString = error.toString().toLowerCase();
    if (errorString.contains('apiexception: 7') ||
        errorString.contains('network_error')) {
      return GoogleSignInException(
        'google-network-error',
        'Google services network request failed.',
      );
    }

    return Exception(error.toString());
  }

  Future<UserModel> signInWithEmail(String email, String password) async {
    _logger.d('[AuthRepo] signInWithEmail: calling backend API...');
    final resp = await apiServiceProvider.login(
      email: email.trim(),
      passportPassword: password,
    );
    _logger.d('[AuthRepo] login resp: ${resp.data}');

    if (!resp.isSuccess) {
      throw Exception(resp.error ?? 'Login failed');
    }

    final data = resp.data as Map<String, dynamic>?;

    final token = data?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Login succeeded but token is missing');
    }
    await _storage.saveToken(token);

    final userId =
        data?['userId']?.toString() ?? data?['id']?.toString() ?? email;
    return UserModel.fromJson({
      ...?data,
      'userId': userId,
      'email': email.trim(),
      'passportType': data?['passportType'] ?? 1,
      'isGuest': false,
    });
  }

  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    _logger.d('[AuthRepo] signUpWithEmail: calling backend API...');
    final resp = await apiServiceProvider.register(
      email: email.trim(),
      passportPassword: password,
    );
    _logger.d('[AuthRepo] register resp: ${resp.data}');

    if (!resp.isSuccess) {
      throw Exception(resp.error ?? 'Registration failed');
    }

    final data = resp.data as Map<String, dynamic>?;
    final token = data?['token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _storage.saveToken(token);
    } else {
      _logger.d(
        '[AuthRepo] registration succeeded without token, will sign in next',
      );
    }

    final userId =
        data?['userId']?.toString() ?? data?['id']?.toString() ?? email;
    return UserModel.fromJson({
      ...?data,
      'userId': userId,
      'email': email.trim(),
      'nickName': data?['nickName'] ?? username.trim(),
      'passportType': data?['passportType'] ?? 1,
      'isGuest': false,
    });
  }

  Future<User> _reloadUser(User user) async {
    await user.reload();
    return _auth.currentUser ?? user;
  }

  Future<UserModel> signInWithGoogle() async {
    await _ensureFirebaseAuthReady();
    _initializeGoogleSignInIfSupported();
    final googleSignIn = _requiredGoogleSignIn;

    final stopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] start');
    _logger.i('[AuthRepo] Google sign-in started');
    debugPrint(
      '[GoogleLoginFlow] launching account chooser (force sign-out first to show picker)',
    );
    _logger.i(
      '[AuthRepo] Force sign-out then launching Google account chooser',
    );

    GoogleSignInAccountClient? googleUser;
    final chooserStopwatch = Stopwatch()..start();
    try {
      await googleSignIn.signOut();
      googleUser = await googleSignIn.signIn();
    } catch (e, stackTrace) {
      debugPrint(
        '[GoogleLoginFlow] chooser failed after ${chooserStopwatch.elapsedMilliseconds}ms error=$e',
      );
      _logger.e(
        '[AuthRepo] Google account chooser failed after ${chooserStopwatch.elapsedMilliseconds}ms: $e',
        error: e,
        stackTrace: stackTrace,
      );
      throw _normalizeGoogleSignInError(e);
    }
    debugPrint(
      '[GoogleLoginFlow] chooser completed in ${chooserStopwatch.elapsedMilliseconds}ms '
      'userSelected=${googleUser != null} total=${stopwatch.elapsedMilliseconds}ms',
    );
    _logger.i(
      '[AuthRepo] Google account chooser completed in ${chooserStopwatch.elapsedMilliseconds}ms '
      '(userSelected=${googleUser != null}, total=${stopwatch.elapsedMilliseconds}ms)',
    );
    if (googleUser == null) {
      debugPrint('[GoogleLoginFlow] chooser returned null user');
      throw AuthCancelledException();
    }
    debugPrint(
      '[GoogleLoginFlow] selected email=${googleUser.email} displayName=${googleUser.displayName}',
    );
    _logger.i(
      '[AuthRepo] Google user selected email=${googleUser.email} displayName=${googleUser.displayName}',
    );

    final authStopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] fetching google tokens');
    GoogleSignInAuthenticationClient googleAuth;
    try {
      googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'Fetching Google authentication tokens timed out after 30 seconds.',
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[GoogleLoginFlow] token fetch failed after ${authStopwatch.elapsedMilliseconds}ms error=$e',
      );
      _logger.e(
        '[AuthRepo] Google authentication fetch failed after ${authStopwatch.elapsedMilliseconds}ms: $e',
        error: e,
        stackTrace: stackTrace,
      );
      throw _normalizeGoogleSignInError(e);
    }
    debugPrint(
      '[GoogleLoginFlow] token fetch completed in ${authStopwatch.elapsedMilliseconds}ms '
      'hasAccessToken=${googleAuth.accessToken != null} hasIdToken=${googleAuth.idToken != null}',
    );
    _logger.i(
      '[AuthRepo] Google authentication fetched in ${authStopwatch.elapsedMilliseconds}ms '
      '(hasAccessToken=${googleAuth.accessToken != null}, hasIdToken=${googleAuth.idToken != null})',
    );
    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      debugPrint('[GoogleLoginFlow] missing idToken from googleAuth');
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google sign-in did not return an idToken.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final firebaseStopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] signing into firebase');
    UserCredential userCredential;
    try {
      userCredential = await _auth
          .signInWithCredential(credential)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException(
                'Firebase credential sign-in timed out after 30 seconds.',
              );
            },
          );
    } catch (e, stackTrace) {
      debugPrint(
        '[GoogleLoginFlow] firebase sign-in failed after ${firebaseStopwatch.elapsedMilliseconds}ms error=$e',
      );
      _logger.e(
        '[AuthRepo] Firebase credential sign-in failed after ${firebaseStopwatch.elapsedMilliseconds}ms: $e',
        error: e,
        stackTrace: stackTrace,
      );
      throw _normalizeGoogleSignInError(e);
    }
    debugPrint(
      '[GoogleLoginFlow] firebase sign-in completed in ${firebaseStopwatch.elapsedMilliseconds}ms',
    );
    _logger.i(
      '[AuthRepo] Firebase credential sign-in completed in ${firebaseStopwatch.elapsedMilliseconds}ms',
    );
    final user = userCredential.user;
    if (user == null) {
      debugPrint('[GoogleLoginFlow] firebase returned null user');
      throw FirebaseAuthException(code: 'user-not-found');
    }

    final backendStopwatch = Stopwatch()..start();
    final googlePassportPayload = jsonEncode({
      'idToken': googleAuth.idToken,
      'code': 0,
      'message': 'Sign in successful',
    });
    debugPrint(
      '[GoogleLoginFlow] syncing backend token passportName=idTokenCodeMessageWrapped',
    );
    final backendSynced = await _syncBackendToken(
      () => apiServiceProvider.googleLogin(
        passportName: googlePassportPayload,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
        email: googleUser!.email,
        displayName: googleUser.displayName ?? user.displayName,
        avatar: googleUser.photoUrl ?? user.photoURL,
      ),
    );
    debugPrint(
      '[GoogleLoginFlow] backend sync completed in ${backendStopwatch.elapsedMilliseconds}ms success=$backendSynced',
    );
    _logger.i(
      '[AuthRepo] Backend Google token sync completed in ${backendStopwatch.elapsedMilliseconds}ms success=$backendSynced passportName=idTokenCodeMessageWrapped',
    );
    if (!backendSynced) {
      throw StateError(
        'Google sign-in succeeded, but backend token sync failed.',
      );
    }

    final refreshStopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] refreshing firebase id token');
    await refreshIdToken();
    debugPrint(
      '[GoogleLoginFlow] refresh id token completed in ${refreshStopwatch.elapsedMilliseconds}ms',
    );
    _logger.i(
      '[AuthRepo] Firebase ID token refresh completed in ${refreshStopwatch.elapsedMilliseconds}ms',
    );

    final model = await _userModelFromFirebaseUser(
      user,
      refreshFirebaseIdToken: false,
    );
    final updatedModel = await _refreshVipStatusFromBackend(model);
    await cacheUser(updatedModel);
    debugPrint(
      '[GoogleLoginFlow] finished total=${stopwatch.elapsedMilliseconds}ms',
    );
    _logger.i(
      '[AuthRepo] Google sign-in finished in ${stopwatch.elapsedMilliseconds}ms',
    );
    return updatedModel;
  }

  Future<UserModel> signInWithFacebook() async {
    if (kIsWeb) {
      throw StateError(
        'Facebook sign-in is only available on mobile platforms.',
      );
    }

    // [DEBUG] Facebook 审核未通过时的 Mock 入口，仅 debug 模式生效
    // 临时验证：代码逻辑 → 后端调用 → UserModel → VIP 同步 → 缓存
    // 开启方式：app_config.dart 里设 kEnableFacebookMock = true
    if (kEnableFacebookMock && kDebugMode) {
      return _signInWithFacebookMock();
    }

    try {
      final result = await const MethodChannel(
        'com.video.storydrama/facebook_login',
      ).invokeMethod<Map<dynamic, dynamic>>('login');
      if (result == null) {
        throw AuthCancelledException();
      }

      final userData = Map<String, dynamic>.from(result);
      final accessToken = _firstString(userData, const [
        'access_token',
        'accessToken',
        'token',
      ]);
      final facebookId = _firstString(userData, const [
        'id',
        'userID',
        'userId',
      ]);
      if (accessToken == null ||
          accessToken.isEmpty ||
          facebookId == null ||
          facebookId.isEmpty) {
        throw StateError(
          'Facebook sign-in did not return a user ID and access token.',
        );
      }

      final email = _firstString(userData, const ['email']);
      final displayName = _firstString(userData, const ['name', 'nickname']);
      final avatar = _firstString(userData, const [
        'icon',
        'picture',
        'avatar',
      ]);
      final backendSynced = await _syncBackendToken(
        () => apiServiceProvider.facebookLogin(
          passportName: accessToken,
          accessToken: accessToken,
          email: email,
          displayName: displayName,
          avatar: avatar,
        ),
      );
      if (!backendSynced) {
        throw StateError(
          'Facebook sign-in succeeded, but backend token sync failed.',
        );
      }

      final model = UserModel.fromJson({
        ...userData,
        'userId': facebookId,
        if (email != null) 'email': email,
        if (displayName != null) 'nickName': displayName,
        if (avatar != null) 'userAvatar': avatar,
        'passportType': PassportType.facebook,
        'isGuest': false,
      });
      final updatedModel = await _refreshVipStatusFromBackend(model);
      await cacheUser(updatedModel);
      return updatedModel;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        throw AuthCancelledException();
      }
      throw StateError('Facebook sign-in failed: ${e.message ?? e.code}');
    } catch (e) {
      if (e is AuthCancelledException || e is StateError) rethrow;
      throw StateError('Facebook sign-in failed: $e');
    }
  }

  static String? _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }
    return null;
  }

  /// [DEBUG] Facebook 登录 Mock 实现，仅 kDebugMode + kEnableFacebookMock=true 时触发
  /// 用于绕过 Facebook 服务器端拒绝（Bussiness Verification 未通过），验证后续代码路径
  Future<UserModel> _signInWithFacebookMock() async {
    debugPrint('[FacebookLoginMock] ⚠️ Using mock data — NOT for production');
    final mockData = <String, dynamic>{
      'id': '1234567890',
      'name': 'Test User',
      'email': 'testuser@example.com',
      'access_token': 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      'picture': 'https://graph.facebook.com/1234567890/picture?type=large',
    };

    final accessToken = _firstString(mockData, const [
      'access_token',
      'accessToken',
      'token',
    ])!;
    final facebookId = _firstString(mockData, const [
      'id',
      'userID',
      'userId',
    ])!;
    final email = _firstString(mockData, const ['email']);
    final displayName = _firstString(mockData, const ['name', 'nickname']);
    final avatar = _firstString(mockData, const ['icon', 'picture', 'avatar']);

    final backendSynced = await _syncBackendToken(
      () => apiServiceProvider.facebookLogin(
        passportName: accessToken,
        accessToken: accessToken,
        email: email,
        displayName: displayName,
        avatar: avatar,
      ),
    );
    if (!backendSynced) {
      throw StateError('Facebook mock sign-in: backend token sync failed.');
    }

    final model = UserModel.fromJson({
      ...mockData,
      'userId': facebookId,
      if (email != null) 'email': email,
      if (displayName != null) 'nickName': displayName,
      if (avatar != null) 'userAvatar': avatar,
      'passportType': PassportType.facebook,
      'isGuest': false,
    });
    final updatedModel = await _refreshVipStatusFromBackend(model);
    await cacheUser(updatedModel);
    debugPrint('[FacebookLoginMock] ✅ Mock flow complete');
    return updatedModel;
  }

  /// TikTok 登录（应用内 WebView 方案）
  ///
  /// 流程：
  /// 1. 调 TiktokAuthService.login() 拉起应用内 WebView
  /// 2. WebView 加载 TikTok authorize URL，用户在 TikTok 页面完成授权
  /// 3. TikTok 302 到 redirect_uri?code=xxx&state=xxx
  /// 4. WebView 拦截 URL，提取 authCode，关闭 WebView
  /// 5. 调后端 /api/user/userAuthorization 用 passportType=tiktok
  /// 6. 后端用 authCode + redirectUri 换 TikTok access_token，再读取用户信息
  /// 7. 用后端返回的 token 同步到本地
  Future<UserModel> signInWithTikTok() async {
    // Web 端走浏览器弹窗 OAuth（Login Kit Web 流）；原生端走应用内 WebView。
    if (!kIsWeb && !TiktokAuthService.isSupported) {
      throw TiktokSignInException(
        'tiktok-platform-unsupported',
        'TikTok sign-in is only available on Android and iOS.',
      );
    }

    final stopwatch = Stopwatch()..start();
    debugPrint('[TikTokLoginFlow] start');
    _logger.i('[AuthRepo] TikTok sign-in started');

    // 1. 触发 TikTok 授权（原生：应用内 WebView；Web：浏览器弹窗。
    //    超时由 service 内部处理：5 分钟）
    final TiktokLoginResult tiktokResult;
    try {
      tiktokResult = kIsWeb
          ? await TiktokAuthService.loginOnWeb()
          : await TiktokAuthService.login();
    } on AuthCancelledException {
      debugPrint('[TikTokLoginFlow] user cancelled');
      _logger.i('[AuthRepo] TikTok sign-in cancelled by user');
      throw const AuthCancelledException();
    } catch (e, stackTrace) {
      debugPrint(
        '[TikTokLoginFlow] TikTok login failed after '
        '${stopwatch.elapsedMilliseconds}ms (${e.runtimeType})',
      );
      _logger.e(
        '[AuthRepo] TikTok login failed (${e.runtimeType})',
        stackTrace: stackTrace,
      );
      rethrow;
    }
    debugPrint(
      '[TikTokLoginFlow] auth code obtained after ${stopwatch.elapsedMilliseconds}ms '
      'len=${tiktokResult.authCode.length}',
    );
    _logger.i(
      '[AuthRepo] TikTok auth code obtained in ${stopwatch.elapsedMilliseconds}ms',
    );

    // 2. 同步后端 token（用 authCode 换 backend token）
    // TikTok 不返回 openId，passportName 传 authCode
    // 让后端用 authCode 换 token 后自行读取 openId
    //
    // 【必须带上 redirectUri】
    // TikTok 换 token 时要求 redirect_uri 与「请求 code 时用的」完全一致，
    // 后端拿不到就无从校验，所以必须原样透传。
    //
    // 【codeVerifier】
    // 只要授权 URL 带了 code_challenge，换 token 就必须带对应的 verifier，
    // 否则 TikTok 返回 invalid_grant。是否启用 PKCE 由
    // AppConfig.tiktokUsePkce 决定，这里只负责原样透传。
    final backendSynced = await _syncBackendToken(
      () => apiServiceProvider.tiktokLogin(
        code: tiktokResult.authCode,
        redirectUri: tiktokResult.redirectUri,
        codeVerifier: tiktokResult.codeVerifier,
      ),
      retry: false,
    );
    if (!backendSynced) {
      throw StateError(
        'TikTok sign-in succeeded, but backend token sync failed.',
      );
    }
    debugPrint(
      '[TikTokLoginFlow] backend sync completed in ${stopwatch.elapsedMilliseconds}ms',
    );

    // 3. 拉取最新用户信息（VIP 状态等）
    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final userData = resp.data as Map<String, dynamic>;
        final incomingUser = UserModel.fromJson(
          userData,
        ).copyWith(isGuest: false);
        final updatedModel = await _refreshVipStatusFromBackend(incomingUser);
        await cacheUser(updatedModel);
        debugPrint(
          '[TikTokLoginFlow] finished via getUserCenter total=${stopwatch.elapsedMilliseconds}ms',
        );
        _logger.i(
          '[AuthRepo] TikTok sign-in finished via getUserCenter in ${stopwatch.elapsedMilliseconds}ms',
        );
        return updatedModel;
      }
    } catch (e) {
      debugPrint(
        '[TikTokLoginFlow] getUserCenter failed: $e, fallback to local model',
      );
      _logger.w(
        '[AuthRepo] TikTok getUserCenter failed, fallback to local model: $e',
      );
    }

    // 4. 兜底：authCode 作为临时 userId（后端登录成功后通常会立刻有 userId）
    final fallback = UserModel.fromJson({
      'userId': 'tiktok_${DateTime.now().millisecondsSinceEpoch}',
      'passportType': PassportType.tiktok,
      'isGuest': false,
    });
    final updatedFallback = await _refreshVipStatusFromBackend(fallback);
    await cacheUser(updatedFallback);
    debugPrint(
      '[TikTokLoginFlow] finished via fallback total=${stopwatch.elapsedMilliseconds}ms',
    );
    return updatedFallback;
  }

  Future<UserModel> signInWithApple() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Apple Sign In is only available on Apple platforms',
      );
    }

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);
    var user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }

    // 同步 Apple Token 到后端
    final backendSynced = await _syncBackendToken(
      () => apiServiceProvider.appleLogin(
        identityToken: appleCredential.identityToken ?? '',
        authorizationCode: appleCredential.authorizationCode,
        fullName:
            [
              appleCredential.givenName,
              if (appleCredential.familyName != null)
                appleCredential.familyName,
            ].join(' ').trim().isEmpty
            ? null
            : [
                appleCredential.givenName,
                if (appleCredential.familyName != null)
                  appleCredential.familyName,
              ].join(' '),
      ),
    );
    if (!backendSynced) {
      throw StateError(
        'Apple sign-in succeeded, but backend token sync failed.',
      );
    }

    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    if (givenName != null && user.displayName == null) {
      final fullName = [givenName, familyName].whereType<String>().join(' ');
      await user.updateDisplayName(fullName);
      user = await _reloadUser(user);
    }

    final model = await _userModelFromFirebaseUser(user);
    final updatedModel = await _refreshVipStatusFromBackend(model);
    await cacheUser(updatedModel);
    return updatedModel;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    Object? signOutError;

    try {
      await _auth.signOut();
    } catch (e) {
      signOutError ??= e;
      _logger.w('[AuthRepo] Firebase signOut failed: $e');
    }

    try {
      await _requiredGoogleSignIn.disconnect();
    } catch (e) {
      signOutError ??= e;
      _logger.w('[AuthRepo] Google disconnect failed: $e');
    }

    try {
      await _requiredGoogleSignIn.signOut();
    } catch (e) {
      signOutError ??= e;
      _logger.w('[AuthRepo] Google signOut failed: $e');
    }

    // 清掉 TikTok WebView 残留的 cookies / cache，
    // 否则下次登录 TikTok 会被自动识别为上次用户（无法切账号）
    try {
      await TiktokAuthService.clearWebViewState();
    } catch (e) {
      signOutError ??= e;
      _logger.w('[AuthRepo] TikTok WebView clear failed: $e');
    }

    await clearCache();
    await clearAutoLoginCredentials();

    if (signOutError != null) {
      _logger.w('[AuthRepo] signOut completed with non-fatal provider errors');
    }
  }

  Future<UserModel> createGuestUser() async {
    final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guestUser = UserModel.guest(guestId);
    await cacheUser(guestUser);
    return guestUser;
  }

  Future<UserModel?> resolveCurrentUser() async {
    await _ensureFirebaseAuthReady();
    final user = _auth.currentUser;
    if (user == null) return null;
    final model = await _userModelFromFirebaseUser(user);
    final updatedModel = await _refreshVipStatusFromBackend(model);
    await cacheUser(updatedModel);
    return updatedModel;
  }

  Future<UserModel?> resolveStoredUser() async {
    final cached = await getCachedUser();
    if (cached != null && !cached.isTourist) {
      return cached;
    }

    final userData = await _storage.getUserData();
    if (userData == null) {
      return null;
    }

    final user = UserModel.fromJson(userData);
    if (user.isTourist) {
      return null;
    }

    final updatedModel = await _refreshVipStatusFromBackend(user);
    await cacheUser(updatedModel);
    return updatedModel;
  }

  Future<void> saveLanguage(String languageCode) async {
    await _storage.setString('language_code', languageCode);
  }

  Future<void> saveUserData(Map<String, dynamic> userData) async {
    await _storage.saveUserData(userData);
    await _storage.setString(AppConstants.userCacheKey, jsonEncode(userData));
  }

  Future<void> clearAutoLoginCredentials() async {
    await _storage.clearAutoLoginCredentials();
  }

  /// 自动登录：检查是否开启了自动登录且有保存的凭证（同时检查30天有效期）
  Future<bool> hasAutoLoginCredentials() async {
    final enabled = await _storage.getAutoLogin();
    final email = await _storage.getAutoLoginEmail();
    final password = await _storage.getAutoLoginPassword();
    if (!enabled ||
        email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return false;
    }
    // 检查30天有效期，过期则清除并返回 false
    if (!_storage.isAutoLoginValid()) {
      debugPrint(
        '[AuthRepository] auto-login expired (30 days), clearing credentials',
      );
      await clearAutoLoginCredentials();
      return false;
    }
    return true;
  }

  /// 自动登录：执行自动登录
  Future<UserModel> performAutoLogin() async {
    final email = await _storage.getAutoLoginEmail();
    final password = await _storage.getAutoLoginPassword();
    if (email == null || password == null) {
      throw Exception('No auto-login credentials found');
    }
    return signInWithEmail(email, password);
  }
}

class GoogleSignInException implements Exception {
  GoogleSignInException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
