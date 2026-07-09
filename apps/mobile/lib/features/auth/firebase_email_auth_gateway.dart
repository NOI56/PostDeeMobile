import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import 'auth_controller.dart';

class FirebaseEmailAuthGateway implements EmailAuthGateway {
  FirebaseEmailAuthGateway({
    firebase_auth.FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  }) async {
    try {
      final credential = createAccount
          ? await _firebaseAuth.createUserWithEmailAndPassword(
              email: email,
              password: password,
            )
          : await _firebaseAuth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
      final user = credential.user ?? _firebaseAuth.currentUser;

      if (user == null) {
        throw const AuthUnavailableException(
          'Firebase Auth did not return a signed-in user',
        );
      }

      final idToken = (await user.getIdToken())?.trim();

      if (idToken == null || idToken.isEmpty) {
        throw const AuthUnavailableException(
          'Firebase Auth did not return an ID token',
        );
      }

      return AuthSession(
        idToken: idToken,
        email: user.email,
        displayName: user.displayName,
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthUnavailableException(
        error.message ?? 'Email sign-in could not be completed.',
      );
    }
  }
}

EmailAuthGateway createEmailAuthGatewayFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
}) {
  if (!enableFirebaseAuth) {
    return const UnavailableEmailAuthGateway(
      message: 'Firebase Auth is disabled. Enable Firebase Auth for sign-in.',
    );
  }

  final bootstrap =
      firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!bootstrap.isInitialized) {
    return UnavailableEmailAuthGateway(
      message: bootstrap.errorMessage ?? 'Firebase Auth is not initialized',
    );
  }

  return FirebaseEmailAuthGateway();
}
