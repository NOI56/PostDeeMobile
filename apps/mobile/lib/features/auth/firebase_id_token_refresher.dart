import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

/// Live ID-token source backed by Firebase. `getIdToken()` returns the cached
/// token while valid and transparently refreshes it once it is close to (or
/// past) its ~1 hour expiry, so API requests always carry a valid token.
///
/// Wired into [PostDeeAuthSessionStore.setIdTokenRefresher] when Firebase Auth
/// is enabled and initialized.
Future<String?> firebaseIdTokenRefresher() async {
  final user = firebase_auth.FirebaseAuth.instance.currentUser;

  if (user == null) {
    return null;
  }

  return (await user.getIdToken())?.trim();
}
