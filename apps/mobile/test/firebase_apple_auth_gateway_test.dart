import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/firebase_bootstrap.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/firebase_apple_auth_gateway.dart';
import 'package:postdee_mobile/features/auth/firebase_google_auth_gateway.dart';

class FakeFirebaseAppleAuthClient implements FirebaseAppleAuthClient {
  FakeFirebaseAppleAuthClient(this.user);

  final FirebaseUserSnapshot user;
  var didSignIn = false;
  var didSignOut = false;

  @override
  Future<FirebaseUserSnapshot> signInWithApple() async {
    didSignIn = true;
    return user;
  }

  @override
  Future<void> signOut() async {
    didSignOut = true;
  }
}

void main() {
  test(
      'FirebaseAppleAuthGateway signs in with Apple and returns a Firebase session',
      () async {
    final firebaseClient = FakeFirebaseAppleAuthClient(
      const FirebaseUserSnapshot(
        idToken: 'firebase-id-token',
        email: 'apple-seller@example.com',
        displayName: 'Apple Seller',
        emailVerified: true,
      ),
    );
    final gateway =
        FirebaseAppleAuthGateway(firebaseAuthClient: firebaseClient);

    final session = await gateway.signIn();

    expect(firebaseClient.didSignIn, isTrue);
    expect(session.idToken, 'firebase-id-token');
    expect(session.email, 'apple-seller@example.com');
    expect(session.displayName, 'Apple Seller');
    expect(session.emailVerified, isTrue);
  });

  test('FirebaseAppleAuthGateway signs out from Firebase', () async {
    final firebaseClient = FakeFirebaseAppleAuthClient(
      const FirebaseUserSnapshot(idToken: 'firebase-id-token'),
    );
    final gateway =
        FirebaseAppleAuthGateway(firebaseAuthClient: firebaseClient);

    await gateway.signOut();

    expect(firebaseClient.didSignOut, isTrue);
  });

  test(
      'createAppleAuthGatewayFromConfig falls back when Firebase bootstrap fails',
      () async {
    final gateway = createAppleAuthGatewayFromConfig(
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

  test('createAppleAuthGatewayFromConfig uses local mock auth when allowed',
      () async {
    final gateway = createAppleAuthGatewayFromConfig(
      enableFirebaseAuth: false,
      allowLocalMockAuth: true,
    );

    final session = await gateway.signIn();

    expect(session.isSignedIn, isTrue);
    expect(session.email, 'demo.apple@postdee.local');
  });

  test('createAppleAuthGatewayFromConfig blocks local mock auth when disabled',
      () async {
    final gateway = createAppleAuthGatewayFromConfig(
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
