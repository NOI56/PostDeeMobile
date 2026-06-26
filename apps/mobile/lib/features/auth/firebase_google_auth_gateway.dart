import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/firebase_bootstrap.dart';
import '../../core/config/app_config.dart';
import 'auth_controller.dart';

class GoogleAccountSnapshot {
  const GoogleAccountSnapshot({
    this.idToken,
    this.email,
    this.displayName,
  });

  final String? idToken;
  final String? email;
  final String? displayName;
}

class FirebaseUserSnapshot {
  const FirebaseUserSnapshot({
    required this.idToken,
    this.email,
    this.displayName,
  });

  final String idToken;
  final String? email;
  final String? displayName;
}

abstract class GoogleIdentityClient {
  Future<GoogleAccountSnapshot> signIn();

  Future<void> signOut();
}

abstract class FirebaseAuthClient {
  Future<FirebaseUserSnapshot> signInWithGoogleIdToken(String googleIdToken);

  Future<void> signOut();
}

class FirebaseGoogleAuthGateway implements GoogleAuthGateway {
  const FirebaseGoogleAuthGateway({
    required GoogleIdentityClient googleClient,
    required FirebaseAuthClient firebaseAuthClient,
  })  : _googleClient = googleClient,
        _firebaseAuthClient = firebaseAuthClient;

  final GoogleIdentityClient _googleClient;
  final FirebaseAuthClient _firebaseAuthClient;

  @override
  Future<AuthSession> signIn() async {
    final googleAccount = await _googleClient.signIn();
    final googleIdToken = googleAccount.idToken?.trim();

    if (googleIdToken == null || googleIdToken.isEmpty) {
      throw const AuthUnavailableException(
          'Google Sign-In did not return an ID token');
    }

    final firebaseUser =
        await _firebaseAuthClient.signInWithGoogleIdToken(googleIdToken);

    return AuthSession(
      idToken: firebaseUser.idToken,
      email: firebaseUser.email ?? googleAccount.email,
      displayName: firebaseUser.displayName ?? googleAccount.displayName,
    );
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuthClient.signOut();
    await _googleClient.signOut();
  }
}

class GoogleSignInPackageClient implements GoogleIdentityClient {
  GoogleSignInPackageClient({
    GoogleSignIn? googleSignIn,
    this.clientId,
    this.serverClientId,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;
  final String? clientId;
  final String? serverClientId;
  var _isInitialized = false;

  @override
  Future<GoogleAccountSnapshot> signIn() async {
    await _ensureInitialized();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw const AuthUnavailableException(
        'Google Sign-In authenticate is not supported on this platform',
      );
    }

    final account = await _googleSignIn.authenticate();
    final authentication = account.authentication;

    return GoogleAccountSnapshot(
      idToken: authentication.idToken,
      email: account.email,
      displayName: account.displayName,
    );
  }

  @override
  Future<void> signOut() async {
    if (!_isInitialized) {
      return;
    }

    await _googleSignIn.signOut();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    await _googleSignIn.initialize(
      clientId: _readOptional(clientId),
      serverClientId: _readOptional(serverClientId),
    );
    _isInitialized = true;
  }
}

class FirebaseAuthPackageClient implements FirebaseAuthClient {
  FirebaseAuthPackageClient({
    firebase_auth.FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  @override
  Future<FirebaseUserSnapshot> signInWithGoogleIdToken(
      String googleIdToken) async {
    final credential =
        firebase_auth.GoogleAuthProvider.credential(idToken: googleIdToken);
    final userCredential = await _firebaseAuth.signInWithCredential(credential);
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
    );
  }

  @override
  Future<void> signOut() => _firebaseAuth.signOut();
}

class LocalMockGoogleAuthGateway implements GoogleAuthGateway {
  const LocalMockGoogleAuthGateway();

  @override
  Future<AuthSession> signIn() async {
    return const AuthSession(
      idToken: 'local-mock-id-token',
      email: 'demo@postdee.local',
      displayName: 'PostDee Demo',
    );
  }

  @override
  Future<void> signOut() async {}
}

GoogleAuthGateway createGoogleAuthGatewayFromConfig({
  bool enableFirebaseAuth = AppConfig.enableFirebaseAuth,
  bool allowLocalMockAuth = AppConfig.allowLocalMockAuth,
  FirebaseBootstrapResult? firebaseBootstrapResult,
}) {
  if (!enableFirebaseAuth) {
    if (allowLocalMockAuth) {
      return const LocalMockGoogleAuthGateway();
    }

    return const UnavailableGoogleAuthGateway(
      message: 'Firebase Auth is disabled. Enable Firebase Auth for sign-in.',
    );
  }

  final bootstrap =
      firebaseBootstrapResult ?? FirebaseBootstrapResult.initialized;

  if (!bootstrap.isInitialized) {
    return UnavailableGoogleAuthGateway(
      message: bootstrap.errorMessage ?? 'Firebase Auth is not initialized',
    );
  }

  return FirebaseGoogleAuthGateway(
    googleClient: GoogleSignInPackageClient(
      clientId: AppConfig.googleClientId,
      serverClientId: AppConfig.googleServerClientId,
    ),
    firebaseAuthClient: FirebaseAuthPackageClient(),
  );
}

String? _readOptional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
