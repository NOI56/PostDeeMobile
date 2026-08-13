import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/auth/phone_verification_screen.dart';

void main() {
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
