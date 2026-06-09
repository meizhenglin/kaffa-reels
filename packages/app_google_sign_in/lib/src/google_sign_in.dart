import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in_android/google_sign_in_android.dart';
import 'package:google_sign_in_ios/google_sign_in_ios.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

export 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    show SignInOption;

class AppGoogleSignInPlugin {
  static void registerWith() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      GoogleSignInPlatform.instance = GoogleSignInAndroid();
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      GoogleSignInPlatform.instance = GoogleSignInIOS();
    }
  }
}

class GoogleSignInAuthentication {
  GoogleSignInAuthentication._(this._data);

  final GoogleSignInTokenData _data;

  String? get idToken => _data.idToken;
  String? get accessToken => _data.accessToken;
  String? get serverAuthCode => _data.serverAuthCode;
}

@immutable
class GoogleSignInAccount {
  GoogleSignInAccount._(this._googleSignIn, GoogleSignInUserData data)
      : displayName = data.displayName,
        email = data.email,
        id = data.id,
        photoUrl = data.photoUrl,
        serverAuthCode = data.serverAuthCode,
        _idToken = data.idToken;

  final String? displayName;
  final String email;
  final String id;
  final String? photoUrl;
  final String? serverAuthCode;
  final String? _idToken;
  final GoogleSignIn _googleSignIn;

  Future<GoogleSignInAuthentication> get authentication async {
    if (_googleSignIn.currentUser != this) {
      throw StateError('User is no longer signed in.');
    }

    final response = await GoogleSignInPlatform.instance.getTokens(
      email: email,
      shouldRecoverAuth: true,
    );

    response.idToken ??= _idToken;
    return GoogleSignInAuthentication._(response);
  }
}

class GoogleSignIn {
  GoogleSignIn({
    this.signInOption = SignInOption.standard,
    this.scopes = const <String>[],
    this.hostedDomain,
    this.clientId,
    this.serverClientId,
    this.forceCodeForRefreshToken = false,
    this.forceAccountName,
  });

  final SignInOption signInOption;
  final List<String> scopes;
  final String? hostedDomain;
  final String? clientId;
  final String? serverClientId;
  final bool forceCodeForRefreshToken;
  final String? forceAccountName;

  GoogleSignInAccount? _currentUser;
  Future<void>? _initialization;

  GoogleSignInAccount? get currentUser => _currentUser;

  Future<void> _ensureInitialized() {
    return _initialization ??= GoogleSignInPlatform.instance.initWithParams(
      SignInInitParameters(
        signInOption: signInOption,
        scopes: scopes,
        hostedDomain: hostedDomain,
        clientId: clientId,
        serverClientId: serverClientId,
        forceCodeForRefreshToken: forceCodeForRefreshToken,
        forceAccountName: forceAccountName,
      ),
    );
  }

  Future<GoogleSignInAccount?> signIn() async {
    await _ensureInitialized();
    final data = await GoogleSignInPlatform.instance.signIn();
    if (data == null) {
      _currentUser = null;
      return null;
    }
    final account = GoogleSignInAccount._(this, data);
    _currentUser = account;
    return account;
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    _currentUser = null;
    await GoogleSignInPlatform.instance.signOut();
  }

  Future<void> disconnect() async {
    await _ensureInitialized();
    _currentUser = null;
    await GoogleSignInPlatform.instance.disconnect();
  }
}
