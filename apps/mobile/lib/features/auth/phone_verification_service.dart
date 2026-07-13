import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';
import 'auth_controller.dart';

typedef PhoneVerificationCodeSender = Future<PhoneVerificationStartResult>
    Function(String phoneNumber);
typedef PhoneVerificationCodeConfirmer = Future<AuthSession> Function({
  required String verificationId,
  required String smsCode,
});

class PhoneVerificationStartResult {
  const PhoneVerificationStartResult.codeSent({
    required this.verificationId,
  }) : autoVerifiedSession = null;

  const PhoneVerificationStartResult.autoVerified({
    required AuthSession session,
  })  : verificationId = '',
        autoVerifiedSession = session;

  final String verificationId;
  final AuthSession? autoVerifiedSession;

  bool get isAutoVerified => autoVerifiedSession != null;
}

class FirebasePhoneVerificationGateway {
  FirebasePhoneVerificationGateway({
    firebase_auth.FirebaseAuth? firebaseAuth,
    this.timeout = const Duration(seconds: 60),
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;
  final Duration timeout;

  Future<PhoneVerificationStartResult> sendCode(String phoneNumber) async {
    final completer = Completer<PhoneVerificationStartResult>();

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      verificationCompleted: (credential) async {
        try {
          final session = await _linkPhoneCredential(credential);

          if (!completer.isCompleted) {
            completer.complete(
              PhoneVerificationStartResult.autoVerified(session: session),
            );
          }
        } catch (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(
            AuthUnavailableException(
              error.message ?? 'Phone verification failed: ${error.code}',
            ),
          );
        }
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerificationStartResult.codeSent(
              verificationId: verificationId,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerificationStartResult.codeSent(
              verificationId: verificationId,
            ),
          );
        }
      },
    );

    return completer.future;
  }

  Future<AuthSession> confirmCode({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = firebase_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    return _linkPhoneCredential(credential);
  }

  Future<AuthSession> _linkPhoneCredential(
    firebase_auth.PhoneAuthCredential credential,
  ) async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const AuthUnavailableException(
        'Sign in with Google before verifying a phone number.',
      );
    }

    try {
      await user.linkWithCredential(credential);
    } on firebase_auth.FirebaseAuthException catch (error) {
      if (error.code != 'provider-already-linked') {
        throw AuthUnavailableException(
          error.message ?? 'Could not link phone number: ${error.code}',
        );
      }
    }

    await user.reload();
    final refreshedUser = _firebaseAuth.currentUser ?? user;
    final idToken = (await refreshedUser.getIdToken(true))?.trim();

    if (idToken == null || idToken.isEmpty) {
      throw const AuthUnavailableException(
        'Firebase Auth did not return a refreshed ID token.',
      );
    }

    return AuthSession(
      idToken: idToken,
      email: refreshedUser.email,
      displayName: refreshedUser.displayName,
      emailVerified: refreshedUser.emailVerified,
    );
  }
}
