import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';
import '../../core/monitoring/postdee_analytics.dart';

/// All local auth gateways represent the same development-only demo account.
/// Keeping one stable ID mirrors Firebase phone linking and prevents local
/// per-account data from changing scope when the mock sign-in method changes.
const localMockAuthUserId = 'local-mock-user';

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

/// Optional Firebase-backed self-service actions; unavailable/mock gateways do
/// not advertise actions they cannot carry out.
abstract interface class EmailAccountRecoveryGateway {
  Future<void> sendPasswordResetEmail(String email);
  Future<void> sendEmailVerification();
  Future<AuthSession> reloadSession();
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
    Duration signInTimeout = const Duration(seconds: 30),
    Duration interactiveSignInTimeout = const Duration(seconds: 150),
    this.setupMessage,
  })  : assert(signInTimeout > Duration.zero),
        assert(interactiveSignInTimeout > Duration.zero),
        _googleAuthGateway = googleAuthGateway,
        _emailAuthGateway = emailAuthGateway,
        _appleAuthGateway = appleAuthGateway,
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance,
        _analytics = analytics ?? PostDeeAnalytics.instance,
        _signInTimeout = signInTimeout,
        _interactiveSignInTimeout = interactiveSignInTimeout {
    _sessionStore.addListener(_handleSessionChanged);
  }

  final GoogleAuthGateway _googleAuthGateway;
  final EmailAuthGateway _emailAuthGateway;
  final AppleAuthGateway _appleAuthGateway;
  final PostDeeAuthSessionStore _sessionStore;
  final PostDeeAnalytics _analytics;
  final Duration _signInTimeout;
  final Duration _interactiveSignInTimeout;
  final String? setupMessage;

  bool _isSigningIn = false;
  bool _isDisposed = false;
  int _signInAttempt = 0;
  Future<void>? _signOutFuture;
  String? _errorMessage;

  AuthSession get session => _sessionStore.session;
  bool get isSigningIn => _isSigningIn;
  String? get errorMessage => _errorMessage;
  bool get supportsEmailRecovery =>
      _emailAuthGateway is EmailAccountRecoveryGateway;

  Future<bool> resetEmailPassword(String email) async {
    final normalized = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      _errorMessage = 'กรอกอีเมลให้ถูกต้อง';
      notifyListeners();
      return false;
    }
    return _recoverEmail(
        (gateway) => gateway.sendPasswordResetEmail(normalized));
  }

  Future<bool> sendEmailVerification() => _recoverEmail(
        (gateway) => gateway.sendEmailVerification(),
      );

  Future<bool> refreshEmailVerification() async {
    final owner = _sessionStore.session.stableUserId;
    final attempt = _signInAttempt;
    AuthSession? refreshed;
    final success = await _recoverEmail((gateway) async {
      refreshed = await gateway.reloadSession();
    });
    if (!success ||
        _isDisposed ||
        attempt != _signInAttempt ||
        owner == null ||
        owner != _sessionStore.session.stableUserId ||
        refreshed?.stableUserId != owner) {
      return false;
    }
    final current = _sessionStore.session;
    _sessionStore.signIn(AuthSession(
      userId: current.userId,
      idToken: refreshed!.idToken,
      email: refreshed!.email,
      displayName: current.displayName,
      emailVerified: refreshed!.emailVerified,
    ));
    return true;
  }

  Future<bool> _recoverEmail(
      Future<void> Function(EmailAccountRecoveryGateway) action) async {
    final gateway = _emailAuthGateway;
    if (_isDisposed || gateway is! EmailAccountRecoveryGateway) return false;
    _errorMessage = null;
    try {
      await action(gateway as EmailAccountRecoveryGateway)
          .timeout(_signInTimeout);
      return !_isDisposed;
    } on AuthUnavailableException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'ดำเนินการไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    }
    if (!_isDisposed) notifyListeners();
    return false;
  }

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
    if (_isDisposed || _isSigningIn || _signOutFuture != null) {
      return;
    }

    final attempt = ++_signInAttempt;
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    // Optional telemetry must not delay authentication or keep buttons locked.
    unawaited(_analytics.logSignInStarted(provider));

    try {
      final timeout =
          provider == 'email' ? _signInTimeout : _interactiveSignInTimeout;
      final signedInSession = await signIn().timeout(timeout);
      if (!_isCurrentSignIn(attempt)) return;

      _sessionStore.signIn(signedInSession);
      unawaited(_analytics.logSignInSucceeded(provider));
    } on TimeoutException {
      if (!_isCurrentSignIn(attempt)) return;
      _errorMessage = provider == 'google'
          ? 'Google ตอบกลับช้าเกินไป กรุณาลองใหม่ หรือเข้าสู่ระบบด้วยอีเมล'
          : 'เข้าสู่ระบบใช้เวลานานเกินไป กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
      unawaited(_analytics.logSignInFailed(
        provider: provider,
        reason: 'network',
      ));
    } on AuthUnavailableException catch (error) {
      if (!_isCurrentSignIn(attempt)) return;
      _errorMessage = error.message;
      unawaited(_analytics.logSignInFailed(
        provider: provider,
        reason: 'unavailable',
      ));
    } catch (_) {
      if (!_isCurrentSignIn(attempt)) return;
      _errorMessage = 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      unawaited(_analytics.logSignInFailed(
        provider: provider,
        reason: 'unknown',
      ));
    } finally {
      if (_isCurrentSignIn(attempt)) {
        _isSigningIn = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentSignIn(int attempt) =>
      !_isDisposed && attempt == _signInAttempt;

  Future<void> signOut() {
    return _signOutFuture ??= _performSignOut().whenComplete(() {
      _signOutFuture = null;
    });
  }

  Future<void> _performSignOut() async {
    ++_signInAttempt;
    try {
      await _googleAuthGateway.signOut();
    } finally {
      try {
        await _appleAuthGateway.signOut();
      } finally {
        _sessionStore.signOut();
        unawaited(_analytics.logSignOut());
        _isSigningIn = false;
        _errorMessage = null;
        if (!_isDisposed) notifyListeners();
      }
    }
  }

  void _handleSessionChanged() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    ++_signInAttempt;
    _sessionStore.removeListener(_handleSessionChanged);
    super.dispose();
  }
}
