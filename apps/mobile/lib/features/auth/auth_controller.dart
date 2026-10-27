import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/monitoring/postdee_analytics.dart';

abstract class GoogleAuthGateway {
  Future<AuthSession> signIn();

  Future<void> signOut();
}

abstract class EmailAuthGateway {
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  });
}

class UnavailableEmailAuthGateway implements EmailAuthGateway {
  const UnavailableEmailAuthGateway({
    this.message = 'Email sign-in is not configured yet',
  });

  final String message;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  }) async {
    throw AuthUnavailableException(message);
  }
}

abstract class AppleAuthGateway {
  Future<AuthSession> signIn();

  Future<void> signOut();
}

class UnavailableAppleAuthGateway implements AppleAuthGateway {
  const UnavailableAppleAuthGateway({
    this.message = 'Apple Sign-In is not configured yet',
  });

  final String message;

  @override
  Future<AuthSession> signIn() async {
    throw AuthUnavailableException(message);
  }

  @override
  Future<void> signOut() async {}
}

class AuthUnavailableException implements Exception {
  const AuthUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UnavailableGoogleAuthGateway implements GoogleAuthGateway {
  const UnavailableGoogleAuthGateway({
    this.message = 'Firebase Google Sign-In is not configured yet',
  });

  final String message;

  @override
  Future<AuthSession> signIn() async {
    throw AuthUnavailableException(message);
  }

  @override
  Future<void> signOut() async {}
}

class PostDeeAuthController extends ChangeNotifier {
  PostDeeAuthController({
    GoogleAuthGateway googleAuthGateway = const UnavailableGoogleAuthGateway(),
    EmailAuthGateway emailAuthGateway = const UnavailableEmailAuthGateway(),
    AppleAuthGateway appleAuthGateway = const UnavailableAppleAuthGateway(),
    PostDeeAuthSessionStore? sessionStore,
    PostDeeAnalytics? analytics,
    this.setupMessage,
  })  : _googleAuthGateway = googleAuthGateway,
        _emailAuthGateway = emailAuthGateway,
        _appleAuthGateway = appleAuthGateway,
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _analytics = analytics ?? PostDeeAnalytics.instance {
    _sessionStore.addListener(_handleSessionChanged);
  }

  final GoogleAuthGateway _googleAuthGateway;
  final EmailAuthGateway _emailAuthGateway;
  final AppleAuthGateway _appleAuthGateway;
  final PostDeeAuthSessionStore _sessionStore;
  final PostDeeAnalytics _analytics;
  final String? setupMessage;

  bool _isSigningIn = false;
  String? _errorMessage;
  Future<void> _nativeAuthQueue = Future<void>.value();
  Future<void>? _pendingSignOut;

  AuthSession get session => _sessionStore.session;
  bool get isSigningIn => _isSigningIn;
  String? get errorMessage => _errorMessage;

  Future<void> signInWithGoogle() =>
      _signInWith('google', _googleAuthGateway.signIn);

  Future<void> signInWithEmail({
    required String email,
    required String password,
    required bool createAccount,
  }) =>
      _signInWith(
        'email',
        () => _emailAuthGateway.signIn(
          email: email,
          password: password,
          createAccount: createAccount,
        ),
      );

  Future<void> signInWithApple() =>
      _signInWith('apple', _appleAuthGateway.signIn);

  Future<void> _signInWith(
    String provider,
    Future<AuthSession> Function() signIn,
  ) async {
    final signInSession = _sessionStore.captureSession();
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    await _analytics.logSignInStarted(provider);

    try {
      await _serializeNativeAuth(() async {
        signInSession.ensureCurrent();
        final session = await signIn();
        signInSession.ensureCurrent();
        _sessionStore.signIn(session);
      });
      await _analytics.logSignInSucceeded(provider);
    } on AuthSessionChangedException {
      // A later logout/sign-in superseded this attempt while native I/O waited.
    } on AuthUnavailableException catch (error) {
      _errorMessage = error.message;
      await _analytics.logSignInFailed(
        provider: provider,
        reason: 'unavailable',
      );
    } catch (error) {
      _errorMessage = 'Sign in failed: $error';
      await _analytics.logSignInFailed(
        provider: provider,
        reason: 'unknown',
      );
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  /// Keeps account-bound native work, such as Apple reauthentication/revocation,
  /// from overlapping provider logout or a later sign-in.
  Future<void> runBoundNativeAuthOperation({
    required AuthSessionBinding sessionBinding,
    required Future<void> Function() operation,
  }) async {
    sessionBinding.ensureCurrent();
    await _serializeNativeAuth(() async {
      sessionBinding.ensureCurrent();
      await operation();
      sessionBinding.ensureCurrent();
    });
  }

  Future<T> _serializeNativeAuth<T>(Future<T> Function() operation) {
    final result = _nativeAuthQueue.then((_) => operation());
    // A failed provider operation must still release later authentication work.
    _nativeAuthQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<void> signOut({AuthSessionBinding? sessionBinding}) async {
    sessionBinding?.ensureCurrent();
    final pendingSignOut = _pendingSignOut;
    if (pendingSignOut != null) {
      await pendingSignOut;
      return;
    }

    late final AuthSessionBinding signedOutSession;
    late final Future<void> operation;
    // Reserve the native queue before exposing the login gate. New sign-ins and
    // duplicate sign-outs cannot overlap the old providers' global logout.
    operation = _serializeNativeAuth(
      () => _signOutProviders(signedOutSession),
    ).whenComplete(() {
      if (identical(_pendingSignOut, operation)) {
        _pendingSignOut = null;
      }
    });
    _pendingSignOut = operation;
    // Invalidate pending authenticated operations before waiting for native I/O.
    _sessionStore.signOut();
    signedOutSession = _sessionStore.captureSession();
    await operation;
  }

  Future<void> _signOutProviders(AuthSessionBinding signedOutSession) async {
    if (!signedOutSession.isCurrent) return;
    try {
      await _googleAuthGateway.signOut();
    } finally {
      try {
        if (signedOutSession.isCurrent) {
          await _appleAuthGateway.signOut();
        }
      } finally {
        await _analytics.logSignOut();
        if (signedOutSession.isCurrent) {
          _errorMessage = null;
          notifyListeners();
        }
      }
    }
  }

  void _handleSessionChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionStore.removeListener(_handleSessionChanged);
    super.dispose();
  }
}
