import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/auth/phone_verification_screen.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/features/auth/phone_verification_service.dart';

void main() {
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
}
