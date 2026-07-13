import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import 'auth_controller.dart';
import 'firebase_google_auth_gateway.dart' show FirebaseUserSnapshot;

/// Thin wrapper around the Firebase Apple Sign-In flow, abstracted so tests can
/// inject a fake instead of touching the real Firebase SDK or native sheet.
abstract class FirebaseAppleAuthClient {
  Future<FirebaseUserSnapshot> signInWithApple();

  Future<void> signOut();
}

/// Real Apple Sign-In gateway backed by Firebase. Mirrors
/// [FirebaseGoogleAuthGateway]: the platform call is hidden behind
/// [FirebaseAppleAuthClient] so the mapping logic stays unit-testable.
class FirebaseAppleAuthGateway implements AppleAuthGateway {
  const FirebaseAppleAuthGateway({
    required FirebaseAppleAuthClient firebaseAuthClient,
  }) : _firebaseAuthClient = firebaseAuthClient;

  final FirebaseAppleAuthClient _firebaseAuthClient;

  @override
  Future<AuthSession> signIn() async {
    final firebaseUser = await _firebaseAuthClient.signInWithApple();

    return AuthSession(
      idToken: firebaseUser.idToken,
      email: firebaseUser.email,
      displayName: firebaseUser.displayName,
      emailVerified: firebaseUser.emailVerified,
    );
  }

  @override
  Future<void> signOut() => _firebaseAuthClient.signOut();
}

/// Real implementation using FlutterFire's provider sign-in. On iOS/macOS this
/// presents the native Apple sheet; on Android/web it uses the OAuth redirect
/// flow. Requires the Apple provider enabled in Firebase and the "Sign in with
/// Apple" capability on the iOS app (see ROADMAP store-compliance notes).
class FirebaseAppleAuthPackageClient implements FirebaseAppleAuthClient {
  FirebaseAppleAuthPackageClient({
    firebase_auth.FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  @override
  Future<FirebaseUserSnapshot> signInWithApple() async {
    final provider = firebase_auth.OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    final userCredential = await _firebaseAuth.signInWithProvider(provider);
    final user = userCredential.user ?? _firebaseAuth.currentUser;

    if (user == null) {
      throw const AuthUnavailableException(
          'Firebase Auth did not return a signed-in user');
    }

    final idToken = (await user.getIdToken())?.trim();

    if (idToken == null || idToken.isEmpty) {
      throw const AuthUnavailableException(
          'Firebase Auth did not return an ID token');
    }

    return FirebaseUserSnapshot(
      idToken: idToken,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
    );
  }

  @override
  Future<void> signOut() => _firebaseAuth.signOut();
}

/// Local development gateway that returns a mock session so the Apple Sign-In
/// button is usable on the emulator without Apple Developer credentials.
class LocalMockAppleAuthGateway implements AppleAuthGateway {
  const LocalMockAppleAuthGateway();

  @override
  Future<AuthSession> signIn() async {
    return const AuthSession(
      idToken: 'local-mock-id-token',
      email: 'demo.apple@postdee.local',
      displayName: 'PostDee Demo',
    );
  }

  @override
  Future<void> signOut() async {}
}

/// Builds the Apple Sign-In gateway for the current configuration.
///
/// With Firebase Auth enabled and initialized this returns the real
/// [FirebaseAppleAuthGateway]. Without Firebase it uses a local mock in dev and
/// surfaces a clear setup message otherwise.
AppleAuthGateway createAppleAuthGatewayFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  bool allowLocalMockAuth = AppConfig.allowLocalMockAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
  bool? supportsNativeAppleTokenRevocation,
}) {
  if (!enableFirebaseAuth) {
    if (allowLocalMockAuth) {
      return const LocalMockAppleAuthGateway();
    }

    return const UnavailableAppleAuthGateway(
      message: 'Firebase Auth is disabled. Enable Firebase Auth for sign-in.',
    );
  }

  final bootstrap =
      firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!bootstrap.isInitialized) {
    return UnavailableAppleAuthGateway(
      message: bootstrap.errorMessage ?? 'Firebase Auth is not initialized',
    );
  }

  final supportsAppleDeletion = supportsNativeAppleTokenRevocation ??
      (Platform.isIOS || Platform.isMacOS);

  if (!supportsAppleDeletion) {
    return const UnavailableAppleAuthGateway(
      message:
          'Apple Sign-In is available on iPhone, iPad, and Mac while secure account deletion is being completed for other platforms.',
    );
  }

  return FirebaseAppleAuthGateway(
    firebaseAuthClient: FirebaseAppleAuthPackageClient(),
  );
}
