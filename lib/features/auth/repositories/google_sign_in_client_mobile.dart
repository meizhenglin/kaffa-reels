import 'package:app_google_sign_in/app_google_sign_in.dart';

typedef GoogleSignInClient = GoogleSignIn;
typedef GoogleSignInAccountClient = GoogleSignInAccount;
typedef GoogleSignInAuthenticationClient = GoogleSignInAuthentication;

GoogleSignInClient createGoogleSignInClient({
  required List<String> scopes,
  String? serverClientId,
}) {
  return GoogleSignIn(
    scopes: scopes,
    serverClientId: serverClientId,
  );
}
