import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/storage_service.dart';
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
    await _storage.clearAuthToken();
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
    return UserModel.fromFirebaseUser(
      user,
      membershipType: cached?.membershipType ?? MembershipType.regular,
      membershipExpiryDate: cached?.membershipExpiryDate,
    );
  }

  Future<UserModel> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    final model = await _userModelFromFirebaseUser(user);
    await cacheUser(model);
    return model;
  }

  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'operation-not-allowed');
    }

    await user.updateDisplayName(username.trim());
    await user.sendEmailVerification();

    final model = await _userModelFromFirebaseUser(
      await _reloadUser(user),
    );
    await cacheUser(model);
    return model;
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

    // 首次登录时 Apple 可能返回姓名，需手动更新 displayName
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

  /// 创建游客用户
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

  // ========== Profile Update Methods ==========
  Future<void> saveLanguage(String languageCode) async {
    await _storage.setString('language_code', languageCode);
  }

  Future<void> saveUserData(Map<String, dynamic> userData) async {
    await _storage.setString(
      AppConstants.userCacheKey,
      jsonEncode(userData),
    );
  }
}

class AuthCancelledException implements Exception {
  @override
  String toString() => 'Sign in cancelled by user';
}
