import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';

/// Restores a previously signed-in Firebase user into the app session at
/// startup. Firebase persists the signed-in user across app restarts, but the
/// in-app [PostDeeAuthSessionStore] starts empty — without this the user is sent
/// to the login gate on every launch. Call after Firebase is initialized.
Future<void> restoreFirebaseSession({
  PostDeeAuthSessionStore? sessionStore,
}) async {
  final store = sessionStore ?? PostDeeAuthSessionStore.instance;
  final user = firebase_auth.FirebaseAuth.instance.currentUser;

  if (user == null) {
    return;
  }

  final token = (await user.getIdToken())?.trim();

  if (token == null || token.isEmpty) {
    return;
  }

  store.signIn(
    AuthSession(
      idToken: token,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
    ),
  );
}
