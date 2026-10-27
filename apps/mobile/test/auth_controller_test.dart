import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';

class _FailingGoogleGateway implements GoogleAuthGateway {
  @override
  Future<AuthSession> signIn() async => AuthSession.unauthenticated;

  @override
  Future<void> signOut() async => throw StateError('native sign-out failed');
}

class _HeldGoogleGateway implements GoogleAuthGateway {
  final signOutStarted = Completer<void>();
  final signedOut = Completer<void>();
  var signInCalls = 0;
  var signOutCalls = 0;

  @override
  Future<AuthSession> signIn() async {
    signInCalls += 1;
    return const AuthSession(idToken: 'account-b-token');
  }

  @override
  Future<void> signOut() {
    signOutCalls += 1;
    signOutStarted.complete();
    return signedOut.future;
  }
}

class _HeldAppleGateway implements AppleAuthGateway {
  final signOutStarted = Completer<void>();
  final signedOut = Completer<void>();
  var signOutCalls = 0;

  @override
  Future<AuthSession> signIn() async => AuthSession.unauthenticated;

  @override
  Future<void> signOut() {
    signOutCalls += 1;
    signOutStarted.complete();
    return signedOut.future;
  }
}

class _HeldSignInGoogleGateway implements GoogleAuthGateway {
  final signInStarted = Completer<void>();
  final signedIn = Completer<AuthSession>();
  var signOutCalls = 0;

  @override
  Future<AuthSession> signIn() {
    signInStarted.complete();
    return signedIn.future;
  }

  @override
  Future<void> signOut() async => signOutCalls += 1;
}

class _RecordingAppleGateway implements AppleAuthGateway {
  var signOutCalls = 0;

  @override
  Future<AuthSession> signIn() async => AuthSession.unauthenticated;

  @override
  Future<void> signOut() async => signOutCalls += 1;
}

void main() {
  test('bound revocation settles before logout and the next native login',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final apple = _HeldAppleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      appleAuthGateway: apple,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();
    final revocationStarted = Completer<void>();
    final revoked = Completer<void>();
    var deleteCalls = 0;
    final deletion = () async {
      await controller.runBoundNativeAuthOperation(
        sessionBinding: binding,
        operation: () {
          revocationStarted.complete();
          return revoked.future;
        },
      );
      deleteCalls += 1;
    }();
    final deletionExpectation = expectLater(
      deletion,
      throwsA(isA<AuthSessionChangedException>()),
    );
    await revocationStarted.future;

    final logout = controller.signOut();
    final login = controller.signInWithGoogle();
    await Future<void>.value();
    expect(binding.isCurrent, isFalse);
    expect(google.signOutCalls, 0);
    expect(google.signInCalls, 0);
    revoked.complete();
    await google.signOutStarted.future;
    expect(google.signInCalls, 0);
    google.signedOut.complete();
    await apple.signOutStarted.future;
    expect(google.signInCalls, 0);
    apple.signedOut.complete();
    await deletionExpectation;
    await logout;
    await login;

    expect(deleteCalls, 0);
    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('bound native work continues for its unchanged signed-in session',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final controller = PostDeeAuthController(sessionStore: sessionStore);
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();
    final calls = <String>[];

    await controller.runBoundNativeAuthOperation(
      sessionBinding: binding,
      operation: () async {
        calls.add('revoke');
        sessionStore.updateDisplayName('New name');
      },
    );
    calls.add('delete');

    expect(calls, ['revoke', 'delete']);
    expect(binding.isCurrent, isTrue);
    expect(sessionStore.session.idToken, 'account-a-token');
  });

  test('failed bound native work releases the next sign-in', () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final started = Completer<void>();
    final failed = Completer<void>();
    final operationExpectation = expectLater(
      controller.runBoundNativeAuthOperation(
        sessionBinding: sessionStore.captureSession(),
        operation: () {
          started.complete();
          return failed.future;
        },
      ),
      throwsStateError,
    );
    await started.future;
    final login = controller.signInWithGoogle();
    await Future<void>.value();
    expect(google.signInCalls, 0);
    failed.completeError(StateError('revocation failed'));
    await operationExpectation;
    await login;

    expect(google.signInCalls, 1);
    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('stale queued native work never dispatches and releases logout/login',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();
    final started = Completer<void>();
    final held = Completer<void>();
    var queuedCalls = 0;
    final heldExpectation = expectLater(
      controller.runBoundNativeAuthOperation(
        sessionBinding: binding,
        operation: () {
          started.complete();
          return held.future;
        },
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    await started.future;
    final queuedExpectation = expectLater(
      controller.runBoundNativeAuthOperation(
        sessionBinding: binding,
        operation: () async => queuedCalls += 1,
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    final logout = controller.signOut();
    final login = controller.signInWithGoogle();
    held.complete();
    await google.signOutStarted.future;
    expect(queuedCalls, 0);
    expect(google.signInCalls, 0);
    google.signedOut.complete();
    await heldExpectation;
    await queuedExpectation;
    await logout;
    await login;

    expect(queuedCalls, 0);
    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('an already stale binding cannot register native work', () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final controller = PostDeeAuthController(sessionStore: sessionStore);
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();
    var operationCalls = 0;
    sessionStore.signOut();

    await expectLater(
      controller.runBoundNativeAuthOperation(
        sessionBinding: binding,
        operation: () async => operationCalls += 1,
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );

    expect(operationCalls, 0);
  });

  test('new sign-in waits for native logout and duplicate logout shares it',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final apple = _HeldAppleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      appleAuthGateway: apple,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();

    final logout = controller.signOut();
    final duplicateLogout = controller.signOut();
    final login = controller.signInWithGoogle();
    await google.signOutStarted.future;
    await Future<void>.value();

    expect(binding.isCurrent, isFalse);
    expect(sessionStore.session.isSignedIn, isFalse);
    expect(google.signInCalls, 0);
    expect(google.signOutCalls, 1);
    google.signedOut.complete();
    await apple.signOutStarted.future;
    expect(google.signInCalls, 0);
    apple.signedOut.complete();
    await logout;
    await duplicateLogout;
    await login;

    expect(google.signInCalls, 1);
    expect(apple.signOutCalls, 1);
    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('logout waits for native sign-in and discards its obsolete session',
      () async {
    final sessionStore = PostDeeAuthSessionStore();
    final google = _HeldSignInGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final login = controller.signInWithGoogle();
    await google.signInStarted.future;

    final logout = controller.signOut();
    expect(google.signOutCalls, 0);
    google.signedIn.complete(
      const AuthSession(idToken: 'abandoned-login-token'),
    );
    await login;
    await logout;

    expect(google.signOutCalls, 1);
    expect(sessionStore.session.isSignedIn, isFalse);
    expect(controller.errorMessage, isNull);
  });

  test('a failed native logout still releases the next native sign-in',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final apple = _RecordingAppleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      appleAuthGateway: apple,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final logoutExpectation = expectLater(controller.signOut(), throwsStateError);
    final login = controller.signInWithGoogle();
    await google.signOutStarted.future;
    expect(google.signInCalls, 0);
    google.signedOut.completeError(StateError('native sign-out failed'));
    await logoutExpectation;
    await login;

    expect(apple.signOutCalls, 1);
    expect(google.signInCalls, 1);
    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('an old deletion binding cannot sign out the current account', () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final binding = sessionStore.captureSession();
    final controller = PostDeeAuthController(sessionStore: sessionStore);
    addTearDown(controller.dispose);
    sessionStore.signIn(const AuthSession(idToken: 'account-b-token'));

    await expectLater(
      controller.signOut(sessionBinding: binding),
      throwsA(isA<AuthSessionChangedException>()),
    );

    expect(sessionStore.session.idToken, 'account-b-token');
  });

  test('pending native sign-out does not clear a later signed-in session',
      () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'account-a-token'),
    );
    final google = _HeldGoogleGateway();
    final apple = _RecordingAppleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: google,
      appleAuthGateway: apple,
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);
    final binding = sessionStore.captureSession();

    final signOut = controller.signOut();
    expect(binding.isCurrent, isFalse);
    expect(sessionStore.session.isSignedIn, isFalse);
    await google.signOutStarted.future;
    sessionStore.signIn(const AuthSession(idToken: 'account-b-token'));
    google.signedOut.complete();
    await signOut;

    expect(sessionStore.session.idToken, 'account-b-token');
    expect(apple.signOutCalls, 0);
  });

  test('clears the local session even when native sign-out fails', () async {
    final sessionStore = PostDeeAuthSessionStore(
      initialSession: const AuthSession(idToken: 'deleted-user-token'),
    );
    final controller = PostDeeAuthController(
      googleAuthGateway: _FailingGoogleGateway(),
      sessionStore: sessionStore,
    );
    addTearDown(controller.dispose);

    await expectLater(controller.signOut(), throwsStateError);

    expect(sessionStore.session.isSignedIn, isFalse);
  });
}
