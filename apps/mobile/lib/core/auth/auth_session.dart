import 'package:flutter/foundation.dart';

class AuthSession {
  const AuthSession({
    this.idToken,
    this.email,
    this.displayName,
    this.emailVerified = false,
  });

  static const unauthenticated = AuthSession();

  final String? idToken;
  final String? email;
  final String? displayName;
  final bool emailVerified;

  bool get isSignedIn => idToken != null && idToken!.trim().isNotEmpty;

  String get displayLabel {
    final name = displayName?.trim();
    final userEmail = email?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    if (userEmail != null && userEmail.isNotEmpty) {
      return userEmail;
    }

    return 'Signed in';
  }
}

/// Returns a freshly-minted ID token from the live auth provider (Firebase),
/// or null when there is no signed-in user. Injected from the feature layer so
/// `core/auth` stays free of a Firebase dependency.
typedef AuthIdTokenRefresher = Future<String?> Function();

class PostDeeAuthSessionStore extends ChangeNotifier {
  PostDeeAuthSessionStore({
    AuthSession initialSession = AuthSession.unauthenticated,
  }) : _session = initialSession;

  static final instance = PostDeeAuthSessionStore();

  AuthSession _session;
  AuthIdTokenRefresher? _idTokenRefresher;

  AuthSession get session => _session;

  /// Sets the live token source used by [currentIdToken]. With Firebase this is
  /// `FirebaseAuth.instance.currentUser.getIdToken()`, which auto-refreshes an
  /// expired token. When null (mock/dev), the cached session token is used.
  void setIdTokenRefresher(AuthIdTokenRefresher? refresher) {
    _idTokenRefresher = refresher;
  }

  Future<String?> currentIdToken() async {
    // Prefer a fresh token from the live provider so requests never send an
    // expired Firebase ID token (they expire ~1 hour after sign-in).
    final refresher = _idTokenRefresher;

    if (refresher != null) {
      try {
        final freshToken = (await refresher())?.trim();

        if (freshToken != null && freshToken.isNotEmpty) {
          return freshToken;
        }
      } catch (_) {
        // Fall through to the cached token on any refresh error.
      }
    }

    final token = _session.idToken?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  void signIn(AuthSession session) {
    _session = session;
    notifyListeners();
  }

  void updateDisplayName(String displayName) {
    if (!_session.isSignedIn) {
      return;
    }

    final normalizedName = displayName.trim();
    _session = AuthSession(
      idToken: _session.idToken,
      email: _session.email,
      displayName:
          normalizedName.isEmpty ? _session.displayName : normalizedName,
      emailVerified: _session.emailVerified,
    );
    notifyListeners();
  }

  void signOut() {
    clear();
  }

  void clear() {
    _session = AuthSession.unauthenticated;
    notifyListeners();
  }
}
