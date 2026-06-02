import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_service.dart';
import '../../../core/storage/storage_service.dart';
import '../models/user_model.dart';
import '../models/user_model.dart';

class AuthRepository {
  AuthRepository(this._storage);

  final StorageService _storage;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Logger _logger = Logger();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

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

  Future<UserModel> _userModelFromFirebaseUser(User user) async {
    await refreshIdToken();
    final cached = await getCachedUser();

    // 补充获取后端用户中心数据（昵称、头像等）
    try {
      final centerResp = await apiServiceProvider.getUserCenter();
      debugPrint('[AuthRepo] getUserCenter (firebase user) resp: ${centerResp.data}');
      if (centerResp.isSuccess && centerResp.data != null) {
        final centerData = centerResp.data as Map<String, dynamic>;
        await _storage.saveUserData(centerData);
        return UserModel.fromJson(centerData);
      }
    } catch (_) {}

    return UserModel.fromFirebaseUser(
      user,
      membershipType: cached?.membershipType ?? MembershipType.regular,
      membershipExpiryDate: cached?.membershipExpiryDate,
    );
  }

  /// 调用后端登录接口，同步 Firebase Token 到后端
  Future<bool> _syncBackendToken(Future<ApiResponse> Function() apiCall) async {
    try {
      final resp = await apiCall();
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final backendToken = data['token'] as String?;
        if (backendToken != null) {
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

    // 保存后端返回的 Token
    final token = data?['token'] as String?;
    if (token != null) {
      await _storage.saveToken(token);
    }

    // 登录接口只返回 userId 和 token，昵称/头像需要从用户中心获取
    final centerResp = await apiServiceProvider.getUserCenter();
    debugPrint('[AuthRepo] getUserCenter resp: ${centerResp.data}');
    final centerData = (centerResp.isSuccess && centerResp.data != null)
        ? centerResp.data as Map<String, dynamic>
        : null;

    // 合并登录接口和用户中心的数据，用户中心的字段优先
    final userData = {
      ...?data,
      if (centerData != null) ...centerData,
    };

    // 保存到 user_data（头像、昵称等展示数据）和 cached_user（完整 UserModel）
    await _storage.saveUserData(userData);

    final userId = userData['userId']?.toString() ?? userData['id']?.toString() ?? email;
    final user = UserModel.fromJson({
      ...userData,
      'userId': userId,
      'email': email.trim(),
    });
    await cacheUser(user);
    return user;
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

    // 保存后端返回的 Token
    final data = resp.data as Map<String, dynamic>?;
    final token = data?['token'] as String?;
    if (token != null) {
      await _storage.saveToken(token);
    }

    // 用后端数据构建用户模型（优先用后端返回的字段）
    final userId = data?['userId']?.toString() ?? data?['id']?.toString() ?? email;
    final user = UserModel.fromJson({
      ...?data,
      'userId': userId,
      'email': email.trim(),
      'nickName': data?['nickName'] ?? username.trim(),
    });
    await _storage.saveUserData(user.toJson());
    await cacheUser(user);
    return user;
  }

  Future<User> _reloadUser(User user) async {
    await user.reload();
    return _auth.currentUser ?? user;
  }

  Future<UserModel> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw AuthCancelledException();
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }

    // 同步 Firebase Token 到后端，获取后端 Token
    await _syncBackendToken(() => apiServiceProvider.googleIdToken(
      idToken: googleAuth.idToken ?? '',
    ));

    final model = await _userModelFromFirebaseUser(user);
    await cacheUser(model);
    return model;
  }

  Future<UserModel> signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
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
    await _syncBackendToken(() => apiServiceProvider.appleLogin(
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

    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    if (givenName != null && user.displayName == null) {
      final fullName = [
        givenName,
        if (familyName != null) familyName,
      ].join(' ');
      await user.updateDisplayName(fullName);
      user = await _reloadUser(user);
    }

    final model = await _userModelFromFirebaseUser(user);
    await cacheUser(model);
    return model;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
    await clearCache();
  }

  Future<UserModel> createGuestUser() async {
    final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guestUser = UserModel.guest(guestId);
    await cacheUser(guestUser);
    return guestUser;
  }

  Future<UserModel?> resolveCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final model = await _userModelFromFirebaseUser(user);
    await cacheUser(model);
    return model;
  }

  Future<void> saveLanguage(String languageCode) async {
    await _storage.setString('language_code', languageCode);
  }

  Future<void> saveUserData(Map<String, dynamic> userData) async {
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
