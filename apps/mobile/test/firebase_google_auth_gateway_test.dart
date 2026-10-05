import 'dart:async';

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

class PendingGoogleIdentityClient implements GoogleIdentityClient {
  final requests = <Completer<GoogleAccountSnapshot>>[];

  @override
  Future<GoogleAccountSnapshot> signIn() {
    final request = Completer<GoogleAccountSnapshot>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> signOut() async {}
}

class PendingFirebaseAuthClient implements FirebaseAuthClient {
  final requests = <Completer<FirebaseUserSnapshot>>[];
  final googleIdTokens = <String>[];

  @override
  Future<FirebaseUserSnapshot> signInWithGoogleIdToken(String googleIdToken) {
    final request = Completer<FirebaseUserSnapshot>();
    requests.add(request);
    googleIdTokens.add(googleIdToken);
    return request.future;
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('times out when Google identity never responds', (tester) async {
    const timeout = Duration(seconds: 2);
    final googleClient = PendingGoogleIdentityClient();
    final firebaseClient = PendingFirebaseAuthClient();
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: googleClient,
      firebaseAuthClient: firebaseClient,
      googleSignInTimeout: timeout,
    );

    final assertion = expectLater(
      gateway.signIn(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(timeout);
    await assertion;

    expect(googleClient.requests, hasLength(1));
    expect(firebaseClient.requests, isEmpty);
  });

  testWidgets('ignores a late Google result and allows a fresh sign-in',
      (tester) async {
    const timeout = Duration(seconds: 2);
    final googleClient = PendingGoogleIdentityClient();
    final firebaseClient = FakeFirebaseAuthClient(
      const FirebaseUserSnapshot(
        userId: 'retry-user',
        idToken: 'retry-firebase-token',
      ),
    );
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: googleClient,
      firebaseAuthClient: firebaseClient,
      googleSignInTimeout: timeout,
    );

    final assertion = expectLater(
      gateway.signIn(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(timeout);
    await assertion;

    final retry = gateway.signIn();
    expect(googleClient.requests, hasLength(2));
    googleClient.requests.first.complete(
      const GoogleAccountSnapshot(idToken: 'expired-google-token'),
    );
    await tester.pump();
    expect(firebaseClient.signedInWithGoogleIdToken, isNull);

    googleClient.requests.last.complete(
      const GoogleAccountSnapshot(idToken: 'retry-google-token'),
    );
    await tester.pump();
    final session = await retry;

    expect(firebaseClient.signedInWithGoogleIdToken, 'retry-google-token');
    expect(session.userId, 'retry-user');
  });

  testWidgets('times out when Firebase credential or ID token never responds',
      (tester) async {
    const timeout = Duration(seconds: 1);
    final firebaseClient = PendingFirebaseAuthClient();
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: FakeGoogleIdentityClient(
        const GoogleAccountSnapshot(idToken: 'google-id-token'),
      ),
      firebaseAuthClient: firebaseClient,
      firebaseSignInTimeout: timeout,
    );

    final assertion = expectLater(
      gateway.signIn(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(timeout);
    await assertion;

    expect(firebaseClient.googleIdTokens, ['google-id-token']);
  });

  testWidgets('a late Firebase result cannot replace a retry result',
      (tester) async {
    const timeout = Duration(seconds: 1);
    final firebaseClient = PendingFirebaseAuthClient();
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: FakeGoogleIdentityClient(
        const GoogleAccountSnapshot(idToken: 'google-id-token'),
      ),
      firebaseAuthClient: firebaseClient,
      firebaseSignInTimeout: timeout,
    );

    final assertion = expectLater(
      gateway.signIn(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(timeout);
    await assertion;

    final retry = gateway.signIn();
    await tester.pump();
    expect(firebaseClient.requests, hasLength(2));
    firebaseClient.requests.first.complete(
      const FirebaseUserSnapshot(
        userId: 'expired-user',
        idToken: 'expired-firebase-token',
      ),
    );
    await tester.pump();
    firebaseClient.requests.last.complete(
      const FirebaseUserSnapshot(
        userId: 'retry-user',
        idToken: 'retry-firebase-token',
      ),
    );
    await tester.pump();

    final session = await retry;
    expect(session.userId, 'retry-user');
    expect(session.idToken, 'retry-firebase-token');
  });

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
        userId: 'firebase-user-123',
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
    expect(session.userId, 'firebase-user-123');
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
        const FirebaseUserSnapshot(
          userId: 'firebase-user-123',
          idToken: 'firebase-id-token',
        ),
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
        const FirebaseUserSnapshot(
          userId: 'firebase-user-123',
          idToken: 'firebase-id-token',
        ),
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

  test('FirebaseGoogleAuthGateway explains when no Google account is available',
      () async {
    final gateway = FirebaseGoogleAuthGateway(
      googleClient: FakeGoogleIdentityClient(
        const GoogleAccountSnapshot(),
        error: const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'No credential available: no eligible accounts',
        ),
      ),
      firebaseAuthClient: FakeFirebaseAuthClient(
        const FirebaseUserSnapshot(
          userId: 'firebase-user-123',
          idToken: 'firebase-id-token',
        ),
      ),
    );

    expect(
      gateway.signIn,
      throwsA(
        isA<AuthUnavailableException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('บัญชี Google'),
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
      const FirebaseUserSnapshot(
        userId: 'firebase-user-123',
        idToken: 'firebase-id-token',
      ),
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
    expect(session.userId, 'local-mock-user');
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
