import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/monitoring/postdee_analytics.dart';
import 'package:postdee_mobile/features/auth/auth_controller.dart';
import 'package:postdee_mobile/features/auth/auth_status_bar.dart';

class FakeGoogleAuthGateway implements GoogleAuthGateway {
  @override
  Future<AuthSession> signIn() async => const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      );

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('signs in with Google and shows the signed-in seller',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore();
    final events = <RecordedAnalyticsEvent>[];
    final analytics = PostDeeAnalytics(
      isEnabled: true,
      logEvent: (event) async => events.add(event),
    );
    final controller = PostDeeAuthController(
      googleAuthGateway: FakeGoogleAuthGateway(),
      sessionStore: sessionStore,
      analytics: analytics,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthStatusBar(controller: controller),
        ),
      ),
    );

    expect(find.text('เข้าสู่ระบบ Google'), findsOneWidget);

    await tester.tap(find.text('เข้าสู่ระบบ Google'));
    await tester.pumpAndSettle();

    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(sessionStore.session.idToken, 'firebase-id-token');
    expect(
      events.map((event) => event.name),
      ['auth_sign_in_started', 'auth_sign_in_succeeded'],
    );
    expect(events.first.parameters, {'provider': 'google'});
  });

  testWidgets('shows the current auth setup message before sign-in',
      (tester) async {
    final controller = PostDeeAuthController(
      setupMessage: 'Local mock auth is active.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthStatusBar(controller: controller),
        ),
      ),
    );

    expect(find.text('กำลังใช้ระบบบัญชีจำลองสำหรับทดสอบ'), findsOneWidget);
  });
}
