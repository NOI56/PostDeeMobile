import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';

/// Restores a previously signed-in Firebase user into the app session at
/// startup. Firebase persists the signed-in user across app restarts, but the
/// in-app [PostDeeAuthSessionStore] starts empty — without this the user is sent
/// to the login gate on every launch. Call after Firebase is initialized.
Future<void> restoreFirebaseSession({
  PostDeeAuthSessionStore? sessionStore,
  Future<AuthSession?> Function()? readSession,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final store = sessionStore ?? PostDeeAuthSessionStore.instance;
  // A session can return to unauthenticated while restore is pending, so use
  // a change counter rather than comparing only the current UID.
  var changed = false;
  void onChanged() => changed = true;
  store.addListener(onChanged);
  try {
    final session =
        await (readSession ?? _readFirebaseSession)().timeout(timeout);
    if (!changed && session != null) store.signIn(session);
  } catch (_) {
    // Offline, expired, or unavailable credentials must not block app startup.
    // The login screen remains usable and a late timed-out read has no effect.
  } finally {
    store.removeListener(onChanged);
  }
}

Future<AuthSession?> _readFirebaseSession() async {
  final auth = firebase_auth.FirebaseAuth.instance;
  final user = auth.currentUser;

  if (user == null) {
    return null;
  }

  final token = (await user.getIdToken())?.trim();

  if (token == null || token.isEmpty || auth.currentUser?.uid != user.uid) {
    return null;
  }

  return AuthSession.authenticated(
    userId: user.uid,
    idToken: token,
    email: user.email,
    displayName: user.displayName,
    emailVerified: user.emailVerified,
  );
}
