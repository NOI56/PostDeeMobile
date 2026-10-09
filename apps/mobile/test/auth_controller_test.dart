import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/monitoring/postdee_analytics.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';

class _FailingGoogleGateway implements GoogleAuthGateway {
  @override
  Future<AuthSession> signIn() async => AuthSession.unauthenticated;

  @override
  Future<void> signOut() async => throw StateError('native sign-out failed');
}

class _ControlledGoogleGateway implements GoogleAuthGateway {
  final requests = <Completer<AuthSession>>[];

  @override
  Future<AuthSession> signIn() {
    final request = Completer<AuthSession>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> signOut() async {}
}

class _ImmediateEmailGateway implements EmailAuthGateway {
  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  }) async =>
      AuthSession.authenticated(userId: 'email-user', idToken: 'email-token');
}

class _RecoveryEmailGateway extends _ImmediateEmailGateway
    implements EmailAccountRecoveryGateway {
  final resets = <String>[];
  int verificationRequests = 0;
  final refresh = Completer<AuthSession>();
  @override
  Future<void> sendPasswordResetEmail(String email) async => resets.add(email);
  @override
  Future<void> sendEmailVerification() async => verificationRequests += 1;
  @override
  Future<AuthSession> reloadSession() => refresh.future;
}

class _StalledEmailGateway implements EmailAuthGateway {
  final request = Completer<AuthSession>();

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
    required bool createAccount,
  }) =>
      request.future;
}

class _ControlledSignOutGateway extends _ControlledGoogleGateway {
  final signOutRequest = Completer<void>();
  int signOutCalls = 0;

  @override
  Future<void> signOut() {
    ++signOutCalls;
    return signOutRequest.future;
  }
}

const _googleSession =
    AuthSession(userId: 'google-user', idToken: 'google-token');

void main() {
  test('email recovery validates input and uses the existing gateway',
      () async {
    final gateway = _RecoveryEmailGateway();
    final controller = PostDeeAuthController(
        emailAuthGateway: gateway, sessionStore: PostDeeAuthSessionStore());
    addTearDown(controller.dispose);
    expect(await controller.resetEmailPassword('invalid'), isFalse);
    expect(gateway.resets, isEmpty);
    expect(await controller.resetEmailPassword(' seller@example.com '), isTrue);
    expect(gateway.resets, ['seller@example.com']);
  });

  test('verification refresh does not replace a newer account', () async {
    final gateway = _RecoveryEmailGateway();
    final store = PostDeeAuthSessionStore(
        initialSession: const AuthSession(userId: 'owner', idToken: 'token'));
    final controller =
        PostDeeAuthController(emailAuthGateway: gateway, sessionStore: store);
    addTearDown(controller.dispose);
    final refresh = controller.refreshEmailVerification();
    store.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    gateway.refresh.complete(const AuthSession(
        userId: 'owner', idToken: 'new-token', emailVerified: true));
    expect(await refresh, isFalse);
    expect(store.session.userId, 'other');
    expect(store.session.emailVerified, isFalse);
  });
  testWidgets('email login stops waiting after thirty seconds', (tester) async {
    final gateway = _StalledEmailGateway();
    final controller = PostDeeAuthController(
      emailAuthGateway: gateway,
      sessionStore: PostDeeAuthSessionStore(),
    );
    addTearDown(controller.dispose);

    final login = controller.signInWithEmail(
      email: 'seller@example.com',
      password: 'test-password',
      createAccount: false,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(controller.isSigningIn, isFalse);
    expect(controller.errorMessage, contains('เข้าสู่ระบบใช้เวลานานเกินไป'));
    expect(controller.session.isSignedIn, isFalse);
    await login;
  });

  testWidgets('releases a stalled Google login and permits an email retry',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final store = PostDeeAuthSessionStore();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      emailAuthGateway: _ImmediateEmailGateway(),
      sessionStore: store,
    );
    addTearDown(controller.dispose);

    final login = controller.signInWithGoogle();
    await tester.pump();
    expect(controller.isSigningIn, isTrue);

    await tester.pump(const Duration(minutes: 3));
    // Assert the visible state before awaiting a potentially unbounded login.
    expect(controller.isSigningIn, isFalse);
    expect(controller.errorMessage, contains('เข้าสู่ระบบ'));
    expect(controller.errorMessage, contains('อีเมล'));
    expect(store.session.isSignedIn, isFalse);
    await login;

    await controller.signInWithEmail(
      email: 'seller@example.com',
      password: 'test-password',
      createAccount: false,
    );
    expect(store.session.userId, 'email-user');
    expect(controller.errorMessage, isNull);

    gateway.requests.single.complete(_googleSession);
    await tester.pump();
    expect(store.session.userId, 'email-user');
  });

  testWidgets('analytics that never returns cannot block login success',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: PostDeeAuthSessionStore(),
      analytics: PostDeeAnalytics(
        isEnabled: true,
        logEvent: (_) => Completer<void>().future,
      ),
    );
    addTearDown(controller.dispose);

    final login = controller.signInWithGoogle();
    await tester.pump();
    expect(gateway.requests, hasLength(1));
    gateway.requests.single.complete(_googleSession);
    await tester.pump();
    expect(controller.isSigningIn, isFalse);
    expect(controller.session.userId, 'google-user');
    await login;
  });

  testWidgets('analytics that never returns cannot block login failure',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: PostDeeAuthSessionStore(),
      analytics: PostDeeAnalytics(
        isEnabled: true,
        logEvent: (_) => Completer<void>().future,
      ),
    );
    addTearDown(controller.dispose);

    final login = controller.signInWithGoogle();
    await tester.pump();
    expect(gateway.requests, hasLength(1));
    gateway.requests.single.completeError(
      const AuthUnavailableException('กรุณาลองเข้าสู่ระบบอีกครั้ง'),
    );
    await tester.pump();
    expect(controller.isSigningIn, isFalse);
    expect(controller.errorMessage, 'กรุณาลองเข้าสู่ระบบอีกครั้ง');
    await login;
  });

  testWidgets('ignores a second login while the first request is active',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: PostDeeAuthSessionStore(),
    );
    addTearDown(controller.dispose);

    final first = controller.signInWithGoogle();
    final duplicate = controller.signInWithGoogle();
    await tester.pump();
    expect(gateway.requests, hasLength(1));
    gateway.requests.single.complete(_googleSession);
    await tester.pump();
    await Future.wait([first, duplicate]);
    expect(controller.session.userId, 'google-user');
  });

  testWidgets('a late failed login cannot unlock or overwrite its retry',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: PostDeeAuthSessionStore(),
    );
    addTearDown(controller.dispose);

    final first = controller.signInWithGoogle();
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(controller.isSigningIn, isFalse);
    await first;

    final retry = controller.signInWithGoogle();
    await tester.pump();
    gateway.requests.first.completeError(StateError('late native failure'));
    await tester.pump();
    expect(controller.isSigningIn, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.session.isSignedIn, isFalse);

    gateway.requests.last.complete(_googleSession);
    await tester.pump();
    await retry;
    expect(controller.session.userId, 'google-user');
  });

  testWidgets('ignores a login result after the controller is disposed',
      (tester) async {
    final gateway = _ControlledGoogleGateway();
    final store = PostDeeAuthSessionStore();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: store,
    );

    final login = controller.signInWithGoogle();
    await tester.pump();
    controller.dispose();
    gateway.requests.single.complete(_googleSession);
    await tester.pump();
    await login;
    expect(store.session.isSignedIn, isFalse);
  });

  testWidgets('signing out invalidates a pending login result', (tester) async {
    final gateway = _ControlledGoogleGateway();
    final store = PostDeeAuthSessionStore();
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      sessionStore: store,
    );
    addTearDown(controller.dispose);

    final login = controller.signInWithGoogle();
    await tester.pump();
    await controller.signOut();
    gateway.requests.single.complete(_googleSession);
    await tester.pump();
    await login;
    expect(store.session.isSignedIn, isFalse);
    expect(controller.isSigningIn, isFalse);
  });

  testWidgets('shares pending sign-out and prevents login until it finishes',
      (tester) async {
    final gateway = _ControlledSignOutGateway();
    final store = PostDeeAuthSessionStore(initialSession: _googleSession);
    final controller = PostDeeAuthController(
      googleAuthGateway: gateway,
      emailAuthGateway: _ImmediateEmailGateway(),
      sessionStore: store,
    );
    addTearDown(controller.dispose);

    var secondSignOutFinished = false;
    final first = controller.signOut();
    final second = controller.signOut().then((_) {
      secondSignOutFinished = true;
    });
    await tester.pump();
    expect(gateway.signOutCalls, 1);
    expect(secondSignOutFinished, isFalse);

    await controller.signInWithEmail(
      email: 'seller@example.com',
      password: 'test-password',
      createAccount: false,
    );
    expect(store.session.userId, 'google-user');

    gateway.signOutRequest.complete();
    await tester.pump();
    await Future.wait([first, second]);
    expect(store.session.isSignedIn, isFalse);
    expect(secondSignOutFinished, isTrue);

    await controller.signInWithEmail(
      email: 'seller@example.com',
      password: 'test-password',
      createAccount: false,
    );
    expect(store.session.userId, 'email-user');
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
