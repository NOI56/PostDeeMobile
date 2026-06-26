import 'package:flutter/foundation.dart';

import '../../core/auth/auth_session.dart';

abstract class GoogleAuthGateway {
  Future<AuthSession> signIn();

  Future<void> signOut();
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
    AppleAuthGateway appleAuthGateway = const UnavailableAppleAuthGateway(),
    PostDeeAuthSessionStore? sessionStore,
    this.setupMessage,
  })  : _googleAuthGateway = googleAuthGateway,
        _appleAuthGateway = appleAuthGateway,
        _sessionStore = sessionStore ?? PostDeeAuthSessionStore.instance {
    _sessionStore.addListener(_handleSessionChanged);
  }

  final GoogleAuthGateway _googleAuthGateway;
  final AppleAuthGateway _appleAuthGateway;
  final PostDeeAuthSessionStore _sessionStore;
  final String? setupMessage;

  bool _isSigningIn = false;
  String? _errorMessage;

  AuthSession get session => _sessionStore.session;
  bool get isSigningIn => _isSigningIn;
  String? get errorMessage => _errorMessage;

  Future<void> signInWithGoogle() => _signInWith(_googleAuthGateway.signIn);

  Future<void> signInWithApple() => _signInWith(_appleAuthGateway.signIn);

  Future<void> _signInWith(Future<AuthSession> Function() signIn) async {
    _isSigningIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _sessionStore.signIn(await signIn());
    } on AuthUnavailableException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = 'Sign in failed: $error';
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _googleAuthGateway.signOut();
    await _appleAuthGateway.signOut();
    _sessionStore.signOut();
    _errorMessage = null;
    notifyListeners();
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
