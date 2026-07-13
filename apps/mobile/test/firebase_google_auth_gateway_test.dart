import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/firebase_google_auth_gateway.dart';

class FakeGoogleIdentityClient implements GoogleIdentityClient {
  FakeGoogleIdentityClient(this.account, {this.error});

  final GoogleAccountSnapshot account;
  final Object? error;
  var didSignOut = false;

  @override
  Future<GoogleAccountSnapshot> signIn() async {
    final error = this.error;
    if (error != null) {
      throw error;
    }

    return account;
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}

class FakeFirebaseAuthClient implements FirebaseAuthClient {
  FakeFirebaseAuthClient(this.user);

  final FirebaseUserSnapshot user;
  String? signedInWithGoogleIdToken;
  var didSignOut = false;

  @override
  Future<FirebaseUserSnapshot> signInWithGoogleIdToken(
      String googleIdToken) async {
    signedInWithGoogleIdToken = googleIdToken;
    return user;
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}

void main() {
  test(
      'FirebaseGoogleAuthGateway signs in with Google and returns a Firebase session',
      () async {
    final googleClient = FakeGoogleIdentityClient(
      const GoogleAccountSnapshot(
        idToken: 'google-id-token',
        email: 'google-seller@example.com',
        displayName: 'Google Seller',
      ),
    );
    final firebaseClient = FakeFirebaseAuthClient(
      const FirebaseUserSnapshot(
        idToken: 'firebase-id-token',
        email: 'firebase-seller@example.com',
        displayName: 'Firebase Seller',
        emailVerified: true,
      ),
    );
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: googleClient,
      firebaseAuthClient: firebaseClient,
    );

    final session = await gateway.signIn();

    expect(firebaseClient.signedInWithGoogleIdToken, 'google-id-token');
    expect(session.idToken, 'firebase-id-token');
    expect(session.email, 'firebase-seller@example.com');
    expect(session.displayName, 'Firebase Seller');
    expect(session.emailVerified, isTrue);
  });

  test('FirebaseGoogleAuthGateway rejects Google sign-in without an ID token',
      () async {
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: FakeGoogleIdentityClient(
        const GoogleAccountSnapshot(
          email: 'seller@example.com',
          displayName: 'Seller',
        ),
      ),
      firebaseAuthClient: FakeFirebaseAuthClient(
        const FirebaseUserSnapshot(idToken: 'firebase-id-token'),
      ),
    );

    expect(
      gateway.signIn,
      throwsA(isA<AuthUnavailableException>()),
    );
  });

  test('FirebaseGoogleAuthGateway explains Google account reauth failures',
      () async {
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: FakeGoogleIdentityClient(
        const GoogleAccountSnapshot(),
        error: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: '[16] Account reauth failed',
        ),
      ),
      firebaseAuthClient: FakeFirebaseAuthClient(
        const FirebaseUserSnapshot(idToken: 'firebase-id-token'),
      ),
    );

    expect(
      gateway.signIn,
      throwsA(
        isA<AuthUnavailableException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('Google account signed in again'),
            contains('Google Play'),
          ),
        ),
      ),
    );
  });
  test('FirebaseGoogleAuthGateway signs out from Firebase and Google',
      () async {
    final googleClient = FakeGoogleIdentityClient(
      const GoogleAccountSnapshot(idToken: 'google-id-token'),
    );
    final firebaseClient = FakeFirebaseAuthClient(
      const FirebaseUserSnapshot(idToken: 'firebase-id-token'),
    );
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: googleClient,
      firebaseAuthClient: firebaseClient,
    );

    await gateway.signOut();

    expect(firebaseClient.didSignOut, isTrue);
    expect(googleClient.didSignOut, isTrue);
  });

  test(
      'createGoogleAuthGatewayFromConfig falls back when Firebase bootstrap fails',
      () async {
    final gateway = createGoogleAuthGatewayFromConfig(
      enableFirebaseAuth: true,
      firebaseBootstrapResult: const FirebaseBootstrapResult.setupError(
        'Firebase Auth is enabled but Firebase is not configured.',
      ),
    );

    expect(
      gateway.signIn,
      throwsA(
        isA<AuthUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('Firebase Auth is enabled'),
        ),
      ),
    );
  });

  test('createGoogleAuthGatewayFromConfig uses local mock auth when disabled',
      () async {
    final gateway = createGoogleAuthGatewayFromConfig(
      enableFirebaseAuth: false,
      allowLocalMockAuth: true,
    );

    final session = await gateway.signIn();

    expect(session.isSignedIn, isTrue);
    expect(session.email, 'demo@postdee.local');
    expect(session.displayName, 'PostDee Demo');
  });

  test('createGoogleAuthGatewayFromConfig blocks local mock auth when disabled',
      () async {
    final gateway = createGoogleAuthGatewayFromConfig(
      enableFirebaseAuth: false,
      allowLocalMockAuth: false,
    );

    expect(
      gateway.signIn,
      throwsA(
        isA<AuthUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('Firebase Auth is disabled'),
        ),
      ),
    );
  });
}
