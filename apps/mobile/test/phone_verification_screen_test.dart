import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/phone_verification_screen.dart';
import 'package:postdee_mobile/features/auth/phone_verification_service.dart';

const _sessionA = AuthSession(userId: 'account-a', idToken: 'token-a');
const _sessionB = AuthSession(userId: 'account-b', idToken: 'token-b');

Future<void> _requestCode(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('phone-verification-phone-field')),
    '+66812345678',
  );
  await tester.tap(find.byKey(const ValueKey('phone-verification-send-code')));
  await tester.pump();
}

Future<void> _confirmCode(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('phone-verification-code-field')),
    '123456',
  );
  await tester.tap(find.byKey(const ValueKey('phone-verification-confirm-code')));
  await tester.pump();
}

void main() {
  testWidgets('verified credentials refresh keeps the phone success screen and binding', (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final binding = store.captureSession();
    await tester.pumpWidget(MaterialApp(home: PhoneVerificationScreen(
      sessionStore: store,
      sendCode: (_) async => const PhoneVerificationStartResult.codeSent(verificationId: 'a'),
      confirmCode: ({required verificationId, required smsCode}) async => const AuthSession(userId: 'account-a', idToken: 'fresh-a'),
      onVerified: store.updateCredentials,
    )));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    await _confirmCode(tester);
    await tester.pumpAndSettle();
    expect(binding.isCurrent, isTrue);
    expect(store.session.idToken, 'fresh-a');
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsOneWidget);
  });

  testWidgets('late phone verification cannot finish for a switched account',
      (tester) async {
    final store = PostDeeAuthSessionStore.instance;
    store.signIn(const AuthSession(userId: 'owner', idToken: 'token'));
    addTearDown(store.clear);
    final pending = Completer<PhoneVerificationStartResult>();
    AuthSession? verified;
    await tester.pumpWidget(MaterialApp(
        home: PhoneVerificationScreen(
      sendCode: (_) => pending.future,
      onVerified: (session) => verified = session,
    )));
    await tester.enterText(
        find.byKey(const ValueKey('phone-verification-phone-field')),
        '+66812345678');
    await tester
        .tap(find.byKey(const ValueKey('phone-verification-send-code')));
    await tester.pump();
    store.signIn(const AuthSession(userId: 'other', idToken: 'other-token'));
    pending.complete(const PhoneVerificationStartResult.autoVerified(
      session: AuthSession(userId: 'owner', idToken: 'fresh-token'),
    ));
    await tester.pumpAndSettle();
    expect(verified, isNull);
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsNothing);
    expect(find.textContaining('บัญชีเปลี่ยน'), findsOneWidget);
  });
  test('local mock verification returns a stable demo user id', () async {
    final session = await DevMockPhoneVerification.confirmCode(
      verificationId: 'dev-mock-verification-id',
      smsCode: DevMockPhoneVerification.demoCode,
    );

    expect(session.userId, 'local-mock-user');
  });
  testWidgets(
      'does not expose demo OTP when local mock verification is disabled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhoneVerificationScreen(
            enableFirebaseAuth: false,
            allowLocalMockVerification: false,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('phone-verification-phone-field')),
      '+66812345678',
    );
    await tester
        .tap(find.byKey(const ValueKey('phone-verification-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('123456'), findsNothing);
    expect(find.textContaining('Firebase Auth'), findsOneWidget);
  });

  testWidgets('late automatic result cannot update a new account',
      (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final sent = Completer<PhoneVerificationStartResult>();
    final verified = <AuthSession>[];
    await tester.pumpWidget(MaterialApp(
      home: PhoneVerificationScreen(
        sessionStore: store,
        sendCode: (_) => sent.future,
        onVerified: verified.add,
      ),
    ));
    await _requestCode(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(
              const ValueKey('phone-verification-phone-field')))
          .controller!
          .text,
      '+66812345678',
    );
    store.clear();
    store.signIn(_sessionB);
    sent.complete(const PhoneVerificationStartResult.autoVerified(
      session: _sessionA,
    ));
    await tester.pumpAndSettle();

    expect(verified, isEmpty);
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(
              const ValueKey('phone-verification-phone-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('switching account invalidates the SMS screen before dispatch',
      (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    var confirmCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: PhoneVerificationScreen(
        sessionStore: store,
        sendCode: (_) async => const PhoneVerificationStartResult.codeSent(
          verificationId: 'verification-a',
        ),
        confirmCode: ({required verificationId, required smsCode}) async {
          confirmCalls += 1;
          return _sessionA;
        },
      ),
    ));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    store.clear();
    store.signIn(_sessionB);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('phone-verification-code-field')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('phone-verification-send-code')));
    await tester.pumpAndSettle();
    expect(confirmCalls, 0);
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsNothing);
  });

  testWidgets('a pending manual result cannot update a new account',
      (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final confirmed = Completer<AuthSession>();
    final verified = <AuthSession>[];
    await tester.pumpWidget(MaterialApp(
      home: PhoneVerificationScreen(
        sessionStore: store,
        sendCode: (_) async => const PhoneVerificationStartResult.codeSent(
          verificationId: 'verification-a',
        ),
        confirmCode: ({required verificationId, required smsCode}) =>
            confirmed.future,
        onVerified: verified.add,
      ),
    ));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    await _confirmCode(tester);
    store.clear();
    store.signIn(_sessionB);
    confirmed.complete(_sessionA);
    await tester.pumpAndSettle();

    expect(verified, isEmpty);
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsNothing);
  });

  testWidgets('disposed screen ignores an automatic completion', (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final sent = Completer<PhoneVerificationStartResult>();
    final verified = <AuthSession>[];
    await tester.pumpWidget(MaterialApp(
      home: PhoneVerificationScreen(
        sessionStore: store,
        sendCode: (_) => sent.future,
        onVerified: verified.add,
      ),
    ));
    await _requestCode(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    sent.complete(const PhoneVerificationStartResult.autoVerified(
      session: _sessionA,
    ));
    await tester.pumpAndSettle();

    expect(verified, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same account SMS completion still reaches the callback',
      (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final verified = <AuthSession>[];
    await tester.pumpWidget(MaterialApp(
      home: PhoneVerificationScreen(
        sessionStore: store,
        sendCode: (_) async => const PhoneVerificationStartResult.codeSent(
          verificationId: 'verification-a',
        ),
        confirmCode: ({required verificationId, required smsCode}) async =>
            _sessionA,
        onVerified: verified.add,
      ),
    ));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    await _confirmCode(tester);
    await tester.pumpAndSettle();

    expect(verified, [_sessionA]);
    expect(find.text('ยืนยันเบอร์เรียบร้อย'), findsOneWidget);
  });
}
