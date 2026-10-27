import 'package:flutter/foundation.dart';

class AuthSession {
  const AuthSession({
    this.userId,
    this.idToken,
    this.email,
    this.displayName,
    this.emailVerified = false,
  });

  static const unauthenticated = AuthSession();

  final String? idToken;

  /// Stable Firebase UID (or the configured mock principal), never a token/email.
  final String? userId;
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

class AuthSessionChangedException implements Exception {
  const AuthSessionChangedException();

  @override
  String toString() => 'The authenticated session changed';
}

/// Binds an operation to one sign-in lifecycle, including while it awaits I/O.
/// Profile edits and token refresh keep this binding; sign-in/out invalidate it.
class AuthSessionBinding {
  const AuthSessionBinding._(this._store, this._generation);

  final PostDeeAuthSessionStore _store;
  final int _generation;

  bool get isCurrent => _store._generation == _generation;

  void ensureCurrent() {
    if (!isCurrent) {
      throw const AuthSessionChangedException();
    }
  }

  Future<String?> currentIdToken() => _store._currentIdTokenFor(this);
}

class PostDeeAuthSessionStore extends ChangeNotifier {
  PostDeeAuthSessionStore({
    AuthSession initialSession = AuthSession.unauthenticated,
  }) : _session = initialSession;

  static final instance = PostDeeAuthSessionStore();

  AuthSession _session;
  int _generation = 0;
  AuthIdTokenRefresher? _idTokenRefresher;

  AuthSession get session => _session;

  AuthSessionBinding captureSession() => AuthSessionBinding._(this, _generation);

  /// Sets the live token source used by [currentIdToken]. With Firebase this is
  /// `FirebaseAuth.instance.currentUser.getIdToken()`, which auto-refreshes an
  /// expired token. When null (mock/dev), the cached session token is used.
  void setIdTokenRefresher(AuthIdTokenRefresher? refresher) {
    _idTokenRefresher = refresher;
  }

  Future<String?> currentIdToken() => captureSession().currentIdToken();

  Future<String?> _currentIdTokenFor(AuthSessionBinding binding) async {
    binding.ensureCurrent();
    final cachedToken = _session.idToken?.trim();
    // Prefer a fresh token from the live provider so requests never send an
    // expired Firebase ID token (they expire ~1 hour after sign-in).
    final refresher = _idTokenRefresher;

    if (refresher != null) {
      String? freshToken;
      try {
        freshToken = (await refresher())?.trim();
      } catch (_) {
        // Fall through to the cached token on any refresh error.
      }
      // A refresh failure must not fall back to a later user's cached token.
      binding.ensureCurrent();
      if (freshToken != null && freshToken.isNotEmpty) {
        return freshToken;
      }
    }

    binding.ensureCurrent();
    return cachedToken == null || cachedToken.isEmpty ? null : cachedToken;
  }

  void signIn(AuthSession session) {
    _generation += 1;
    _session = session;
    notifyListeners();
  }

  void updateDisplayName(String displayName) {
    if (!_session.isSignedIn) {
      return;
    }

    final normalizedName = displayName.trim();
    _session = AuthSession(
      userId: _session.userId,
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
    _generation += 1;
    _session = AuthSession.unauthenticated;
    notifyListeners();
  }
}
