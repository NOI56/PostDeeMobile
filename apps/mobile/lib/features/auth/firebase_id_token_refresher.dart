import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';

/// Live ID-token source backed by Firebase. `getIdToken()` returns the cached
/// token while valid and transparently refreshes it once it is close to (or
/// past) its ~1 hour expiry, so API requests always carry a valid token.
///
/// Wired into [PostDeeAuthSessionStore.setAuthCredentialRefresher] when
/// Firebase Auth is enabled and initialized.
Future<AuthCredentialSnapshot?> firebaseAuthCredentialRefresher() async {
  final user = firebase_auth.FirebaseAuth.instance.currentUser;

  if (user == null) {
    return null;
  }

  String? token;
  try {
    token = (await user.getIdToken())?.trim();
  } catch (_) {
    // The session store may reuse its cached token only after the live uid is
    // confirmed below. This keeps temporary refresh failures usable without
    // ever crossing account boundaries.
  }

  if (firebase_auth.FirebaseAuth.instance.currentUser?.uid != user.uid) {
    throw const AuthSessionChangedException();
  }

  return AuthCredentialSnapshot(userId: user.uid, idToken: token);
}
