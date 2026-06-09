class GoogleSignInClient {
  GoogleSignInClient({
    required List<String> scopes,
    String? serverClientId,
  });

  Future<GoogleSignInAccountClient?> signIn() async {
    throw UnsupportedError('Google Sign-In is unavailable on Web in this build.');
  }

  Future<void> signOut() async {}

  Future<void> disconnect() async {}
}

class GoogleSignInAccountClient {
  String get email => '';
  String? get displayName => null;
  String? get photoUrl => null;

  Future<GoogleSignInAuthenticationClient> get authentication async {
    throw UnsupportedError('Google Sign-In is unavailable on Web in this build.');
  }
}

class GoogleSignInAuthenticationClient {
  String? get accessToken => null;
  String? get idToken => null;
}

GoogleSignInClient createGoogleSignInClient({
  required List<String> scopes,
  String? serverClientId,
}) {
  return GoogleSignInClient(
    scopes: scopes,
    serverClientId: serverClientId,
  );
}
