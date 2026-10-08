import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/app.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'postdee_onboarding_seen': true});
    PostDeeAuthSessionStore.instance.clear();
  });

  tearDown(PostDeeAuthSessionStore.instance.clear);

  test('Staging identity is explicit and the normal build defaults off', () {
    expect(
      AppConfig.isStagingBuild,
      const bool.fromEnvironment('POSTDEE_STAGING_BUILD', defaultValue: false),
    );
    final staging = jsonDecode(
      File('staging.local.example.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final production = jsonDecode(
      File('production.local.example.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(staging['POSTDEE_STAGING_BUILD'], isTrue);
    expect(production['POSTDEE_STAGING_BUILD'], isNot(isTrue));
  });

  testWidgets('normal app has no Staging strip or title', (tester) async {
    await tester.pumpWidget(const PostDeeApp(showStagingBadge: false));
    await tester.pumpAndSettle();
    expect(find.text('STAGING'), findsNothing);
    expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'PostDee');
  });

  testWidgets('Staging strip stays outside login controls on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PostDeeApp(showStagingBadge: true));
    await tester.pumpAndSettle();
    expect(find.text('STAGING'), findsOneWidget);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'PostDee Staging');
    final badge = tester.getRect(
      find.byKey(const ValueKey('postdee-staging-badge')),
    );
    final email = find.byKey(const ValueKey('login-email-sign-in'));
    await tester.ensureVisible(email);
    await tester.pumpAndSettle();
    expect(badge.overlaps(tester.getRect(email)), isFalse);
    await tester.tap(email);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Staging strip preserves dock, composer close and account taps',
      (tester) async {
    PostDeeAuthSessionStore.instance.signIn(const AuthSession(
      userId: 'staging-badge-test',
      idToken: 'test-id-token',
      email: 'badge@example.com',
      displayName: 'Badge Test',
    ));
    await tester.pumpWidget(
      const PostDeeApp(locale: Locale('en'), showStagingBadge: true),
    );
    await tester.pumpAndSettle();

    final nav = find.byKey(const ValueKey('postdee-reference-bottom-nav'));
    Finder tab(String label) =>
        find.descendant(of: nav, matching: find.bySemanticsLabel(label));
    final badge = tester.getRect(
      find.byKey(const ValueKey('postdee-staging-badge')),
    );
    expect(badge.overlaps(tester.getRect(nav)), isFalse);
    expect(
        badge.overlaps(tester.getRect(find.bySemanticsLabel('Notifications'))),
        isFalse);
    await tester.tap(tab('Create post'));
    await tester.pumpAndSettle();
    expect(nav, findsNothing);
    final close = find.byKey(const ValueKey('uploader-close'));
    expect(badge.overlaps(tester.getRect(close)), isFalse);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(nav, findsOneWidget);
    await tester.tap(tab('Account'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Semantics>(tab('Account')).properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
