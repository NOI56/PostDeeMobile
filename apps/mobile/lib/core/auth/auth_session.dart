import 'package:flutter/foundation.dart';

class AuthSession {
  const AuthSession({
    this.userId,
    this.idToken,
    this.email,
    this.displayName,
    this.emailVerified = false,
  });

  factory AuthSession.authenticated({
    required String userId,
    required String idToken,
    String? email,
    String? displayName,
    bool emailVerified = false,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedIdToken = idToken.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(
        userId,
        'userId',
        'A signed-in session requires a stable user id',
      );
    }

    if (normalizedIdToken.isEmpty) {
      throw ArgumentError.value(
        idToken,
        'idToken',
        'A signed-in session requires an ID token',
      );
    }

    return AuthSession(
      userId: normalizedUserId,
      idToken: normalizedIdToken,
      email: email,
      displayName: displayName,
      emailVerified: emailVerified,
    );
  }

  static const unauthenticated = AuthSession();

  /// Stable identity supplied by Firebase Auth. Unlike [idToken], this value
  /// does not rotate and can safely scope local per-account app data.
  final String? userId;
  final String? idToken;
  final String? email;
  final String? displayName;
  final bool emailVerified;

  bool get isSignedIn => idToken != null && idToken!.trim().isNotEmpty;

  String? get stableUserId {
    final normalizedUserId = userId?.trim();
    return normalizedUserId == null || normalizedUserId.isEmpty
        ? null
        : normalizedUserId;
  }

  bool get hasStableUserId => stableUserId != null;

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

class AuthCredentialSnapshot {
  const AuthCredentialSnapshot({required this.userId, this.idToken});

  final String userId;
  final String? idToken;
}

class AuthSessionChangedException implements Exception {
  const AuthSessionChangedException();

  @override
  String toString() =>
      'AuthSessionChangedException: The signed-in Firebase user changed.';
}

/// Returns a freshly-minted ID token from the live auth provider (Firebase),
/// or null when there is no signed-in user. Injected from the feature layer so
/// `core/auth` stays free of a Firebase dependency.
typedef AuthIdTokenRefresher = Future<String?> Function();
typedef AuthCredentialRefresher = Future<AuthCredentialSnapshot?> Function();

class PostDeeAuthSessionStore extends ChangeNotifier {
  PostDeeAuthSessionStore({
    AuthSession initialSession = AuthSession.unauthenticated,
  }) : _session = initialSession;

  static final instance = PostDeeAuthSessionStore();

  AuthSession _session;
  AuthIdTokenRefresher? _idTokenRefresher;
  AuthCredentialRefresher? _authCredentialRefresher;

  AuthSession get session => _session;

  /// Sets the live token source used by [currentIdToken]. With Firebase this is
  /// `FirebaseAuth.instance.currentUser.getIdToken()`, which auto-refreshes an
  /// expired token. When null (mock/dev), the cached session token is used.
  void setIdTokenRefresher(AuthIdTokenRefresher? refresher) {
    _idTokenRefresher = refresher;
    if (refresher != null) _authCredentialRefresher = null;
  }

  /// Sets a live credential source that binds the token to the Firebase uid
  /// observed in the same refresh operation. Production Firebase auth uses
  /// this path so a token from a newly switched account cannot be paired with
  /// local state that still belongs to the previous account.
  void setAuthCredentialRefresher(AuthCredentialRefresher? refresher) {
    _authCredentialRefresher = refresher;
    if (refresher != null) _idTokenRefresher = null;
  }

  Future<String?> currentIdToken() async {
    final credentialRefresher = _authCredentialRefresher;
    if (credentialRefresher != null) {
      final expectedUserId = _session.stableUserId;
      if (expectedUserId == null) return null;

      final credential = await credentialRefresher();
      final liveUserId = credential?.userId.trim();
      if (credential == null ||
          liveUserId == null ||
          liveUserId.isEmpty ||
          liveUserId != expectedUserId ||
          _session.stableUserId != expectedUserId) {
        throw const AuthSessionChangedException();
      }

      final freshToken = credential.idToken?.trim();
      if (freshToken != null && freshToken.isNotEmpty) {
        return freshToken;
      }

      final cachedToken = _session.idToken?.trim();
      return cachedToken == null || cachedToken.isEmpty ? null : cachedToken;
    }

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
    _session = AuthSession.unauthenticated;
    notifyListeners();
  }
}
