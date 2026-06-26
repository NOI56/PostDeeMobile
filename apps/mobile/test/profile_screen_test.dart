import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/language_controller.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/theme_controller.dart';
import 'package:postdee_mobile/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows package comparison, quotas, and Pro team access',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-package-comparison')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-starter')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-plan-pro')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-quota-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-plan-quota-starter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-plan-quota-pro')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-post-quota-summary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('profile-ai-caption-quota-summary')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('profile-team-access-pro')), findsOneWidget);
  });

  testWidgets('does not fake social platform connections before OAuth exists',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    final tiktokConnect =
        find.byKey(const ValueKey('profile-platform-connect-TIKTOK'));

    await tester.scrollUntilVisible(
      tiktokConnect,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    expect(tiktokConnect, findsOneWidget);
    expect(tester.widget<OutlinedButton>(tiktokConnect).onPressed, isNull);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows the signed-in account instead of test profile copy',
      (tester) async {
    final sessionStore = PostDeeAuthSessionStore.instance;
    sessionStore.signIn(
      const AuthSession(
        idToken: 'firebase-id-token',
        email: 'seller@example.com',
        displayName: 'PostDee Seller',
      ),
    );
    addTearDown(sessionStore.clear);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    expect(find.text('PostDee Seller'), findsOneWidget);
    expect(find.text('seller@example.com'), findsOneWidget);
    expect(find.text('บัญชีทดลองสำหรับทดสอบ UI และ flow หลักของ PostDee'),
        findsNothing);
    expect(find.text('โหมดทดสอบ'), findsNothing);
    expect(find.text('พร้อมลอง UI'), findsNothing);
  });

  testWidgets('does not add fake AI editing minutes from top-up',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('th'),
        localizationsDelegates: const [
          PostDeeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: PostDeeLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileScreen(
            languageController: PostDeeLanguageController(),
            themeController: PostDeeThemeController(),
            onOpenTemplates: () {},
            onDeleteAccount: () {},
          ),
        ),
      ),
    );

    final topUpButton =
        find.widgetWithText(OutlinedButton, 'เติม 120 นาที · 49 บาท');

    await tester.scrollUntilVisible(
      topUpButton,
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();

    await tester.tap(topUpButton);
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('320'), findsNothing);
  });
}
