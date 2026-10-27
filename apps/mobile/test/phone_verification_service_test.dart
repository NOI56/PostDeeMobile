import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/phone_verification_service.dart';

const _sessionA = AuthSession(userId: 'account-a', idToken: 'token-a');
const _sessionB = AuthSession(userId: 'account-b', idToken: 'token-b');

class _FakePhoneUser implements FirebasePhoneAuthUser {
  _FakePhoneUser(this.uid);

  @override
  final String uid;
  @override
  String? get email => '$uid@example.test';
  @override
  String? get displayName => uid;
  @override
  bool get emailVerified => true;

  int linkCalls = 0;
  int reloadCalls = 0;
  int tokenCalls = 0;
  Completer<void>? pendingLink;
  Completer<void>? pendingReload;
  Completer<String?>? pendingToken;
  Object? linkError;

  @override
  Future<void> linkWithCredential(
    firebase_auth.PhoneAuthCredential credential,
  ) async {
    linkCalls += 1;
    final error = linkError;
    if (error != null) throw error;
    await pendingLink?.future;
  }

  @override
  Future<void> reload() async {
    reloadCalls += 1;
    await pendingReload?.future;
  }

  @override
  Future<String?> getIdToken(bool forceRefresh) async {
    tokenCalls += 1;
    return pendingToken == null ? 'refreshed-$uid' : pendingToken!.future;
  }
}

class _VerificationCallbacks {
  _VerificationCallbacks({
    required this.completed,
    required this.failed,
    required this.sent,
    required this.timedOut,
  });

  final firebase_auth.PhoneVerificationCompleted completed;
  final firebase_auth.PhoneVerificationFailed failed;
  final firebase_auth.PhoneCodeSent sent;
  final firebase_auth.PhoneCodeAutoRetrievalTimeout timedOut;
}

class _FakePhoneAuth implements FirebasePhoneAuthAdapter {
  _FakePhoneAuth(this.currentUser);

  @override
  FirebasePhoneAuthUser? currentUser;
  final callbacks = <_VerificationCallbacks>[];

  @override
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Duration timeout,
    required firebase_auth.PhoneVerificationCompleted verificationCompleted,
    required firebase_auth.PhoneVerificationFailed verificationFailed,
    required firebase_auth.PhoneCodeSent codeSent,
    required firebase_auth.PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
  }) async {
    callbacks.add(_VerificationCallbacks(
      completed: verificationCompleted,
      failed: verificationFailed,
      sent: codeSent,
      timedOut: codeAutoRetrievalTimeout,
    ));
  }
}

class _FakeGoogleAuth implements GoogleAuthGateway {
  _FakeGoogleAuth(this.auth, this.userB);

  final _FakePhoneAuth auth;
  final _FakePhoneUser userB;
  int signOutCalls = 0;
  int signInCalls = 0;

  @override
  Future<AuthSession> signIn() async {
    signInCalls += 1;
    auth.currentUser = userB;
    return _sessionB;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    auth.currentUser = null;
  }
}

class _Fixture {
  _Fixture() {
    googleAuth = _FakeGoogleAuth(auth, userB);
    controller = PostDeeAuthController(
      sessionStore: store,
      googleAuthGateway: googleAuth,
    );
    gateway = FirebasePhoneVerificationGateway(
      phoneAuthAdapter: auth,
      sessionStore: store,
      runNativeAuthOperation: controller.runBoundNativeAuthOperation,
    );
  }

  final store = PostDeeAuthSessionStore(initialSession: _sessionA);
  final userA = _FakePhoneUser('account-a');
  final userB = _FakePhoneUser('account-b');
  late final auth = _FakePhoneAuth(userA);
  late final PostDeeAuthController controller;
  late final _FakeGoogleAuth googleAuth;
  late final FirebasePhoneVerificationGateway gateway;

  void switchToB({bool updateStore = true}) {
    auth.currentUser = userB;
    if (updateStore) {
      store.clear();
      store.signIn(_sessionB);
    }
  }

  Future<void> sendSms() async {
    final sent = gateway.sendCode('+66812345678');
    auth.callbacks.last.sent('verification-a', null);
    await sent;
  }
}

firebase_auth.PhoneAuthCredential _credential() =>
    firebase_auth.PhoneAuthProvider.credential(
      verificationId: 'verification-a',
      smsCode: '123456',
    );

Future<void> _flushAsync() async {
  for (var index = 0; index < 20; index += 1) {
    await Future<void>.value();
  }
}

void main() {
  test('automatic verification stays bound to the requesting UID', () async {
    final fixture = _Fixture();
    final sent = fixture.gateway.sendCode('+66812345678');
    final expectation = expectLater(
      sent,
      throwsA(isA<AuthSessionChangedException>()),
    );
    fixture.switchToB();
    fixture.auth.callbacks.single.completed(_credential());
    await expectation;

    expect(fixture.userA.linkCalls, 0);
    expect(fixture.userB.linkCalls, 0);
    expect(fixture.userB.tokenCalls, 0);
  });

  test('native UID changes are rejected even before the store changes', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.switchToB(updateStore: false);

    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userA.linkCalls, 0);
    expect(fixture.userB.linkCalls, 0);
  });

  test('an old SMS verification ID cannot confirm after A signs in as B',
      () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.switchToB();

    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userB.linkCalls, 0);
  });

  test('automatic callbacks after codeSent never start linking', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.auth.callbacks.single.completed(_credential());
    fixture.auth.callbacks.single.completed(_credential());
    await _flushAsync();

    expect(fixture.userA.linkCalls, 0);
  });

  test('automatic callbacks after retrieval timeout never start linking',
      () async {
    final fixture = _Fixture();
    final sent = fixture.gateway.sendCode('+66812345678');
    fixture.auth.callbacks.single.timedOut('verification-a');
    expect((await sent).verificationId, 'verification-a');
    fixture.auth.callbacks.single.completed(_credential());
    await _flushAsync();

    expect(fixture.userA.linkCalls, 0);
  });

  test('duplicate automatic callbacks link once and preserve same UID',
      () async {
    final fixture = _Fixture();
    fixture.userA.pendingLink = Completer<void>();
    final sent = fixture.gateway.sendCode('+66812345678');
    final callbacks = fixture.auth.callbacks.single;
    callbacks.completed(_credential());
    callbacks.completed(_credential());
    callbacks.sent('late-sms-id', null);
    await _flushAsync();
    expect(fixture.userA.linkCalls, 1);
    fixture.userA.pendingLink!.complete();
    final result = await sent;

    expect(result.isAutoVerified, isTrue);
    expect(result.autoVerifiedSession!.userId, 'account-a');
    expect(result.autoVerifiedSession!.idToken, 'refreshed-account-a');
    expect(fixture.userA.linkCalls, 1);
  });

  test('cancel closes a pending automatic request and late callbacks', () async {
    final fixture = _Fixture();
    final sent = fixture.gateway.sendCode('+66812345678');
    final expectation = expectLater(
      sent,
      throwsA(isA<AuthSessionChangedException>()),
    );
    fixture.gateway.cancelVerification();
    fixture.auth.callbacks.single.completed(_credential());
    await expectation;
    expect(fixture.userA.linkCalls, 0);
  });

  test('cancel invalidates a previously issued manual verification ID',
      () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.gateway.cancelVerification();

    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userA.linkCalls, 0);
  });

  test('resend invalidates old verification IDs and callbacks', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    final next = fixture.gateway.sendCode('+66898765432');
    fixture.auth.callbacks.last.sent('verification-new', null);
    await next;
    fixture.auth.callbacks.first.completed(_credential());

    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userA.linkCalls, 0);
  });

  test('manual confirmation links and returns only the original UID', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    final session = await fixture.gateway.confirmCode(
      verificationId: 'verification-a',
      smsCode: '123456',
    );

    expect(session.userId, 'account-a');
    expect(session.idToken, 'refreshed-account-a');
    expect(fixture.userA.linkCalls, 1);
    expect(fixture.userA.reloadCalls, 1);
    expect(fixture.userA.tokenCalls, 1);
    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userA.linkCalls, 1);
  });

  test('overlapping manual confirmation does not link twice', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.userA.pendingLink = Completer<void>();
    final first = fixture.gateway.confirmCode(
      verificationId: 'verification-a',
      smsCode: '123456',
    );
    await _flushAsync();
    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    fixture.userA.pendingLink!.complete();
    await first;
    expect(fixture.userA.linkCalls, 1);
  });

  for (final stage in ['link', 'reload', 'token']) {
    test('switching account during $stage cannot return B credentials', () async {
      final fixture = _Fixture();
      await fixture.sendSms();
      final pending = Completer<void>();
      final token = Completer<String?>();
      if (stage == 'link') fixture.userA.pendingLink = pending;
      if (stage == 'reload') fixture.userA.pendingReload = pending;
      if (stage == 'token') fixture.userA.pendingToken = token;
      final confirmed = fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      );
      final expectation = expectLater(
        confirmed,
        throwsA(isA<AuthSessionChangedException>()),
      );
      await _flushAsync();
      if (stage == 'link') expect(fixture.userA.linkCalls, 1);
      if (stage == 'reload') expect(fixture.userA.reloadCalls, 1);
      if (stage == 'token') expect(fixture.userA.tokenCalls, 1);
      fixture.switchToB();
      if (stage == 'token') {
        token.complete('a-token-after-switch');
      } else {
        pending.complete();
      }
      await expectation;

      expect(fixture.userB.linkCalls, 0);
      expect(fixture.userB.reloadCalls, 0);
      expect(fixture.userB.tokenCalls, 0);
      if (stage == 'link') expect(fixture.userA.reloadCalls, 0);
      if (stage == 'reload') expect(fixture.userA.tokenCalls, 0);
    });
  }

  test('failed verification closes later automatic callbacks', () async {
    final fixture = _Fixture();
    final sent = fixture.gateway.sendCode('+66812345678');
    final expectation = expectLater(
      sent,
      throwsA(isA<AuthUnavailableException>()),
    );
    fixture.auth.callbacks.single.failed(
      firebase_auth.FirebaseAuthException(code: 'invalid-phone-number'),
    );
    fixture.auth.callbacks.single.completed(_credential());
    await expectation;
    expect(fixture.userA.linkCalls, 0);
  });

  test('Firebase linking requires the shared native auth queue', () async {
    final fixture = _Fixture();
    final gateway = FirebasePhoneVerificationGateway(
      phoneAuthAdapter: fixture.auth,
      sessionStore: fixture.store,
    );

    await expectLater(
      gateway.sendCode('+66812345678'),
      throwsA(isA<AuthUnavailableException>()),
    );
    expect(fixture.auth.callbacks, isEmpty);
    expect(fixture.userA.linkCalls, 0);
  });

  test('invalid SMS can retry for the same original session', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.userA.linkError = firebase_auth.FirebaseAuthException(
      code: 'invalid-verification-code',
    );
    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '000000',
      ),
      throwsA(isA<AuthUnavailableException>()),
    );
    fixture.userA.linkError = null;
    final session = await fixture.gateway.confirmCode(
      verificationId: 'verification-a',
      smsCode: '123456',
    );
    expect(session.userId, 'account-a');
    expect(fixture.userA.linkCalls, 2);
  });

  test('logout and B login wait for an in-flight native phone operation',
      () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.userA.pendingLink = Completer<void>();
    final confirmed = fixture.gateway.confirmCode(
      verificationId: 'verification-a',
      smsCode: '123456',
    );
    final expectation = expectLater(
      confirmed,
      throwsA(isA<AuthSessionChangedException>()),
    );
    await _flushAsync();
    expect(fixture.userA.linkCalls, 1);
    final signedOut = fixture.controller.signOut();
    final signedIn = fixture.controller.signInWithGoogle();
    await _flushAsync();
    expect(fixture.googleAuth.signOutCalls, 0);
    expect(fixture.googleAuth.signInCalls, 0);
    expect(fixture.auth.currentUser?.uid, 'account-a');

    fixture.userA.pendingLink!.complete();
    await expectation;
    await signedOut;
    await signedIn;
    expect(fixture.googleAuth.signOutCalls, 1);
    expect(fixture.googleAuth.signInCalls, 1);
    expect(fixture.store.session.userId, 'account-b');
    expect(fixture.userA.reloadCalls, 0);
    expect(fixture.userB.linkCalls, 0);
  });

  test('initial native and app UID mismatch fails before sending SMS', () async {
    final fixture = _Fixture();
    fixture.switchToB(updateStore: false);
    await expectLater(
      fixture.gateway.sendCode('+66812345678'),
      throwsA(isA<AuthSessionChangedException>()),
    );
    fixture.gateway.cancelVerification();
    expect(fixture.auth.callbacks, isEmpty);
  });

  test('a claimed automatic callback is abandoned when its session changes',
      () async {
    final fixture = _Fixture();
    fixture.userA.pendingLink = Completer<void>();
    final sent = fixture.gateway.sendCode('+66812345678');
    final expectation = expectLater(
      sent,
      throwsA(isA<AuthSessionChangedException>()),
    );
    fixture.auth.callbacks.single.completed(_credential());
    await _flushAsync();
    expect(fixture.userA.linkCalls, 1);
    fixture.switchToB();
    fixture.userA.pendingLink!.complete();
    await expectation;
    expect(fixture.userA.reloadCalls, 0);
    expect(fixture.userB.linkCalls, 0);
    expect(fixture.userB.tokenCalls, 0);
  });

  test('signing out and back into the same UID invalidates its old SMS',
      () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.store.clear();
    fixture.store.signIn(_sessionA);
    await expectLater(
      fixture.gateway.confirmCode(
        verificationId: 'verification-a',
        smsCode: '123456',
      ),
      throwsA(isA<AuthSessionChangedException>()),
    );
    expect(fixture.userA.linkCalls, 0);
  });

  test('profile edits preserve the requesting session and UID', () async {
    final fixture = _Fixture();
    await fixture.sendSms();
    fixture.store.updateDisplayName('Updated profile');
    final session = await fixture.gateway.confirmCode(
      verificationId: 'verification-a',
      smsCode: '123456',
    );
    expect(session.userId, 'account-a');
    expect(fixture.userA.linkCalls, 1);
  });
}
