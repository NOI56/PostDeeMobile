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
  await tester
      .tap(find.byKey(const ValueKey('phone-verification-confirm-code')));
  await tester.pump();
}

void main() {
  for (final entry in {
    '081-234 5678': '+66812345678',
    '  +66 81-234-5678  ': '+66812345678',
    '+1 415-555-2671': '+14155552671',
    '+44 7700-900123': '+447700900123',
  }.entries) {
    testWidgets('normalizes ${entry.key} before requesting SMS',
        (tester) async {
      final sentTo = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: PhoneVerificationScreen(
        sessionStore: PostDeeAuthSessionStore(initialSession: _sessionA),
        sendCode: (phone) async {
          sentTo.add(phone);
          return const PhoneVerificationStartResult.codeSent(
              verificationId: 'normalized');
        },
      )));
      await tester.enterText(
          find.byKey(const ValueKey('phone-verification-phone-field')),
          entry.key);
      await tester
          .tap(find.byKey(const ValueKey('phone-verification-send-code')));
      await tester.pumpAndSettle();
      expect(sentTo, [entry.value]);
      expect(find.text('ส่งรหัส 6 หลักไปที่ ${entry.value}'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    });
  }

  for (final phone in [
    '081234567',
    '08123456789',
    '+660812345678',
    '081+2345678',
    '+000123456789',
    '+1234567890123456',
    '081abc2345678',
  ]) {
    testWidgets('does not dispatch malformed phone $phone', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: PhoneVerificationScreen(
        sessionStore: PostDeeAuthSessionStore(initialSession: _sessionA),
        sendCode: (_) async {
          calls++;
          return const PhoneVerificationStartResult.codeSent(
              verificationId: 'unexpected');
        },
      )));
      await tester.enterText(
          find.byKey(const ValueKey('phone-verification-phone-field')), phone);
      await tester
          .tap(find.byKey(const ValueKey('phone-verification-send-code')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.textContaining('เบอร์โทร'), findsWidgets);
    });
  }

  testWidgets(
      'resend sends again after cooldown and uses the new verification ID',
      (tester) async {
    final sends = <String>[];
    final confirmationIds = <String>[];
    final second = Completer<PhoneVerificationStartResult>();
    await tester.pumpWidget(MaterialApp(
        home: PhoneVerificationScreen(
      sessionStore: PostDeeAuthSessionStore(initialSession: _sessionA),
      sendCode: (phone) async {
        sends.add(phone);
        return sends.length == 1
            ? const PhoneVerificationStartResult.codeSent(
                verificationId: 'first')
            : second.future;
      },
      confirmCode: ({required verificationId, required smsCode}) async {
        confirmationIds.add(verificationId);
        return _sessionA;
      },
    )));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    final resend = find.byKey(const ValueKey('phone-verification-resend-code'));
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('phone-verification-code-field')), '111111');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pump();
    expect(sends, ['+66812345678', '+66812345678']);
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    second.complete(
        const PhoneVerificationStartResult.codeSent(verificationId: 'second'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('phone-verification-code-field')))
            .controller!
            .text,
        isEmpty);
    await _confirmCode(tester);
    await tester.pumpAndSettle();
    expect(confirmationIds, ['second']);
  });

  testWidgets('changing the phone does not resend or bypass the send cooldown',
      (tester) async {
    var sends = 0;
    await tester.pumpWidget(MaterialApp(
        home: PhoneVerificationScreen(
      sessionStore: PostDeeAuthSessionStore(initialSession: _sessionA),
      sendCode: (_) async {
        sends++;
        return const PhoneVerificationStartResult.codeSent(verificationId: 'a');
      },
    )));
    await _requestCode(tester);
    await tester.pumpAndSettle();
    final change =
        find.byKey(const ValueKey('phone-verification-change-phone'));
    await tester.ensureVisible(change);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(find.byKey(const ValueKey('phone-verification-code-field')),
        findsNothing);
    final phone = find.byKey(const ValueKey('phone-verification-phone-field'));
    await tester.enterText(phone, '0891234567');
    await tester
        .tap(find.byKey(const ValueKey('phone-verification-send-code')));
    await tester.pump();
    expect(sends, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'verified credentials refresh keeps the phone success screen and binding',
      (tester) async {
    final store = PostDeeAuthSessionStore(initialSession: _sessionA);
    final binding = store.captureSession();
    await tester.pumpWidget(MaterialApp(
        home: PhoneVerificationScreen(
      sessionStore: store,
      sendCode: (_) async =>
          const PhoneVerificationStartResult.codeSent(verificationId: 'a'),
      confirmCode: ({required verificationId, required smsCode}) async =>
          const AuthSession(userId: 'account-a', idToken: 'fresh-a'),
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
          .widget<TextField>(
              find.byKey(const ValueKey('phone-verification-phone-field')))
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
          .widget<TextField>(
              find.byKey(const ValueKey('phone-verification-phone-field')))
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
    await tester
        .tap(find.byKey(const ValueKey('phone-verification-send-code')));
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

  testWidgets('disposed screen ignores an automatic completion',
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
