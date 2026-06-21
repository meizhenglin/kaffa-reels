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
import '../../../core/network/api_service.dart';
import '../../../core/storage/storage_service.dart';
import '../models/user_model.dart';

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
      return UserModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
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

  Future<UserModel> _userModelFromFirebaseUser(User user, {bool refreshFirebaseIdToken = true}) async {
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
          membershipType: isVip == 1 ? MembershipType.premium : MembershipType.regular,
          membershipExpiryDate: vipEndTime != null ? DateTime.tryParse(vipEndTime) : null,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[AuthRepo] Failed to refresh VIP status from backend: $e');
      _logger.e('[AuthRepo] Failed to refresh VIP status from backend', error: e, stackTrace: stackTrace);
    }
    return model;
  }

  Future<void> warmUpGoogleSignIn() async {
    if (!isGoogleSignInSupported) {
      _logger.i('[AuthRepo] Google sign-in warm-up skipped: unsupported on current platform/config');
      return;
    }

    _initializeGoogleSignInIfSupported();

    debugPrint(
      '[GoogleLoginFlow] googleSignIn config scopes=$_googleScopes serverClientId=$_googleServerClientId',
    );
    _logger.i('[AuthRepo] Google sign-in warm-up skipped on Android to avoid chooser startup delay');
  }

  /// 调用后端登录接口，同步 Firebase Token 到后端
  Future<bool> _syncBackendToken(Future<ApiResponse> Function() apiCall) async {
    try {
      final resp = await apiCall();
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final backendToken = data['token'] as String?;
        if (backendToken != null && backendToken.isNotEmpty) {
          await _storage.saveToken(backendToken);
          return true;
        }
      }
      return false;
    } catch (e) {
      _logger.e('[_syncBackendToken] error: $e');
      return false;
    }
  }

  Future<void> _ensureFirebaseAuthReady() async {
    if (!FirebaseService.isInitialized) {
      throw StateError('Firebase Auth is unavailable because Firebase is not initialized.');
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
      final message = (error.message ?? error.details?.toString() ?? error.toString()).toLowerCase();

      if (code.contains('sign_in_canceled') || code.contains('canceled') || code.contains('cancelled')) {
        return AuthCancelledException();
      }

      if (code.contains('network_error') || message.contains('apiexception: 7') || message.contains('network error')) {
        return GoogleSignInException(
          'google-network-error',
          'Google services network request failed.',
        );
      }

      if (code.contains('sign_in_failed') || message.contains('12500') || message.contains('10:')) {
        return GoogleSignInException(
          'google-sign-in-config-error',
          'Google Sign-In configuration is invalid on this device/build.',
        );
      }

      if (message.contains('12501')) {
        return AuthCancelledException();
      }

      if (message.contains('play services') || message.contains('developer_error')) {
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
          error.message ?? 'Firebase network request failed during Google sign-in.',
        );
      }
      if (error.code == 'invalid-credential' || error.code == 'invalid-verification-code') {
        return GoogleSignInException(
          'google-sign-in-config-error',
          error.message ?? 'Google credential verification failed.',
        );
      }
    }

    final errorString = error.toString().toLowerCase();
    if (errorString.contains('apiexception: 7') || errorString.contains('network_error')) {
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

    final userId = data?['userId']?.toString() ?? data?['id']?.toString() ?? email;
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
      _logger.d('[AuthRepo] registration succeeded without token, will sign in next');
    }

    final userId = data?['userId']?.toString() ?? data?['id']?.toString() ?? email;
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
    debugPrint('[GoogleLoginFlow] launching account chooser (force sign-out first to show picker)');
    _logger.i('[AuthRepo] Force sign-out then launching Google account chooser');

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
    debugPrint('[GoogleLoginFlow] selected email=${googleUser.email} displayName=${googleUser.displayName}');
    _logger.i('[AuthRepo] Google user selected email=${googleUser.email} displayName=${googleUser.displayName}');

    final authStopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] fetching google tokens');
    GoogleSignInAuthenticationClient googleAuth;
    try {
      googleAuth = await googleUser.authentication.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Fetching Google authentication tokens timed out after 30 seconds.');
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
      userCredential = await _auth.signInWithCredential(credential).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Firebase credential sign-in timed out after 30 seconds.');
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
    debugPrint('[GoogleLoginFlow] firebase sign-in completed in ${firebaseStopwatch.elapsedMilliseconds}ms');
    _logger.i('[AuthRepo] Firebase credential sign-in completed in ${firebaseStopwatch.elapsedMilliseconds}ms');
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
    debugPrint('[GoogleLoginFlow] syncing backend token passportName=idTokenCodeMessageWrapped');
    final backendSynced = await _syncBackendToken(() => apiServiceProvider.googleLogin(
      passportName: googlePassportPayload,
      idToken: googleAuth.idToken!,
      accessToken: googleAuth.accessToken,
      email: googleUser!.email,
      displayName: googleUser.displayName ?? user.displayName,
      avatar: googleUser.photoUrl ?? user.photoURL,
    ));
    debugPrint(
      '[GoogleLoginFlow] backend sync completed in ${backendStopwatch.elapsedMilliseconds}ms success=$backendSynced',
    );
    _logger.i('[AuthRepo] Backend Google token sync completed in ${backendStopwatch.elapsedMilliseconds}ms success=$backendSynced passportName=idTokenCodeMessageWrapped');
    if (!backendSynced) {
      throw StateError('Google sign-in succeeded, but backend token sync failed.');
    }

    final refreshStopwatch = Stopwatch()..start();
    debugPrint('[GoogleLoginFlow] refreshing firebase id token');
    await refreshIdToken();
    debugPrint('[GoogleLoginFlow] refresh id token completed in ${refreshStopwatch.elapsedMilliseconds}ms');
    _logger.i('[AuthRepo] Firebase ID token refresh completed in ${refreshStopwatch.elapsedMilliseconds}ms');

    final model = await _userModelFromFirebaseUser(user, refreshFirebaseIdToken: false);
    final updatedModel = await _refreshVipStatusFromBackend(model);
    await cacheUser(updatedModel);
    debugPrint('[GoogleLoginFlow] finished total=${stopwatch.elapsedMilliseconds}ms');
    _logger.i('[AuthRepo] Google sign-in finished in ${stopwatch.elapsedMilliseconds}ms');
    return updatedModel;
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
    final backendSynced = await _syncBackendToken(() => apiServiceProvider.appleLogin(
      identityToken: appleCredential.identityToken ?? '',
      authorizationCode: appleCredential.authorizationCode,
      fullName: [
        appleCredential.givenName,
        if (appleCredential.familyName != null) appleCredential.familyName,
      ].join(' ').trim().isEmpty ? null : [
        appleCredential.givenName,
        if (appleCredential.familyName != null) appleCredential.familyName,
      ].join(' '),
    ));
    if (!backendSynced) {
      throw StateError('Apple sign-in succeeded, but backend token sync failed.');
    }

    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    if (givenName != null && user.displayName == null) {
      final fullName = [
        givenName,
        familyName,
      ].whereType<String>().join(' ');
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
    await _storage.setString(
      AppConstants.userCacheKey,
      jsonEncode(userData),
    );
  }

  Future<void> clearAutoLoginCredentials() async {
    await _storage.clearAutoLoginCredentials();
  }

  /// 自动登录：检查是否开启了自动登录且有保存的凭证（同时检查30天有效期）
  Future<bool> hasAutoLoginCredentials() async {
    final enabled = await _storage.getAutoLogin();
    final email = await _storage.getAutoLoginEmail();
    final password = await _storage.getAutoLoginPassword();
    if (!enabled || email == null || email.isEmpty || password == null || password.isEmpty) {
      return false;
    }
    // 检查30天有效期，过期则清除并返回 false
    if (!_storage.isAutoLoginValid()) {
      debugPrint('[AuthRepository] auto-login expired (30 days), clearing credentials');
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

class AuthCancelledException implements Exception {
  @override
  String toString() => 'Sign in cancelled by user';
}

class GoogleSignInException implements Exception {
  GoogleSignInException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
