import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/analytics/analytics_error_message.dart';

import 'analytics_english_test.dart'
    show
        AnalyticsEnglishFixture,
        analyticsEnglishOwner,
        analyticsEnglishSummary,
        selectAnalyticsRange;

const _ownerChanged = 'Your account has changed. Please reopen Analytics.';
const _proLock = 'Unified analytics is available on the Pro plan.';

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(userId: analyticsEnglishOwner, idToken: 'fake-token')));
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  final failures = <String, (Object, String, String)>{
    'signed out': (
      const ApiException('Private API message', statusCode: 401),
      'กรุณาเข้าสู่ระบบใหม่',
      'Please sign in again.'
    ),
    'forbidden': (
      const ApiException('Private API message', statusCode: 403),
      'บัญชีนี้ยังไม่มีสิทธิ์ดูข้อมูลวิเคราะห์',
      'This account cannot access analytics.'
    ),
    'server unavailable': (
      const ApiException('Private API message', statusCode: 503),
      'โหลดข้อมูลวิเคราะห์ไม่สำเร็จ ลองใหม่อีกครั้ง',
      'Could not load analytics. Please try again.'
    ),
    'unrelated payment': (
      const ApiException('Payment required',
          statusCode: 402, code: 'PAYMENT_REQUIRED'),
      'โหลดข้อมูลวิเคราะห์ไม่สำเร็จ ลองใหม่อีกครั้ง',
      'Could not load analytics. Please try again.'
    ),
    'network': (
      const SocketException('offline'),
      'เชื่อมต่อ PostDee API ไม่ได้',
      'Could not connect to PostDee.'
    ),
    'unexpected': (
      StateError('Private local message'),
      'เกิดข้อผิดพลาดระหว่างโหลดข้อมูลวิเคราะห์',
      'An error occurred while loading analytics.'
    )
  };
  for (final entry in failures.entries) {
    testWidgets('stored ${entry.key} error translates and Retry recovers once',
        (tester) async {
      final fixture = AnalyticsEnglishFixture(locale: const Locale('th'))
        ..error = entry.value.$1;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(find.text(entry.value.$2), findsOneWidget);
      fixture.language.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text(entry.value.$3), findsOneWidget);
      expect(find.text(_proLock), findsNothing);
      expect(find.textContaining('Private'), findsNothing);
      expect(find.textContaining('No analytics data yet'), findsNothing);
      expect(fixture.ranges, ['30d']);
      expect(fixture.subscriptionReads, 1);
      fixture.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('1.5K'), findsOneWidget);
      expect(find.byKey(const ValueKey('analytics-load-error')), findsNothing);
      expect(fixture.ranges, ['30d', '30d']);
      expect(fixture.subscriptionReads, 2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final entry in {
    '402 code': const ApiException('Requires Pro',
        statusCode: 402, code: 'PRO_REQUIRED'),
    '403 code': const ApiException('Requires Pro',
        statusCode: 403, code: 'PRO_REQUIRED'),
    'legacy message': const ApiException(
        'Unified Analytics requires the Pro plan',
        statusCode: 402)
  }.entries) {
    testWidgets('English plan lock respects ${entry.key} without a raw error',
        (tester) async {
      final fixture = AnalyticsEnglishFixture()..error = entry.value;
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(find.text(_proLock), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('No analytics data yet'), findsNothing);
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text('ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro'),
          findsOneWidget);
      fixture.language.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text(_proLock), findsOneWidget);
      expect(fixture.ranges, ['30d']);
      expect(fixture.subscriptionReads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Basic preflight locks analytics before requesting a summary',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()
      ..subscription = const SubscriptionStatusResult(
          userId: analyticsEnglishOwner,
          plan: 'BASIC',
          status: 'INACTIVE',
          canSchedule: false,
          canUseAiCaptions: false,
          canUseAnalytics: false);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text(_proLock), findsOneWidget);
    expect(fixture.ranges, isEmpty);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(
        find.text('ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro'), findsOneWidget);
    expect(fixture.ranges, isEmpty);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preflight access failure translates before any analytics request',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()
      ..subscriptionError = const ApiException('Unauthorized', statusCode: 401);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Please sign in again.'), findsOneWidget);
    expect(fixture.ranges, isEmpty);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('กรุณาเข้าสู่ระบบใหม่'), findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    fixture.subscriptionError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(fixture.subscriptionReads, 2);
    expect(fixture.ranges, ['30d']);
    expect(find.text('1.5K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final alreadyLoaded in [false, true]) {
    testWidgets('owner replacement invalidates analytics loaded=$alreadyLoaded',
        (tester) async {
      final pending = Completer<AnalyticsSummaryResult>();
      final fixture = AnalyticsEnglishFixture()
        ..respond = (_) => pending.future;
      addTearDown(fixture.dispose);
      await fixture.mount(tester, settle: false);
      if (alreadyLoaded) {
        pending.complete(analyticsEnglishSummary());
        await tester.pumpAndSettle();
        expect(find.text('1.5K'), findsOneWidget);
      }
      PostDeeAuthSessionStore.instance.signIn(
          const AuthSession(userId: 'another-owner', idToken: 'next-token'));
      if (!alreadyLoaded) pending.complete(analyticsEnglishSummary());
      await tester.pumpAndSettle();
      expect(find.text(_ownerChanged), findsOneWidget);
      expect(find.text('1.5K'), findsNothing);
      fixture.language.value = const Locale('th');
      await tester.pumpAndSettle();
      expect(find.text('บัญชีที่ใช้งานเปลี่ยนแล้ว กรุณาเปิดหน้าวิเคราะห์ใหม่'),
          findsOneWidget);
      fixture.language.value = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text(_ownerChanged), findsOneWidget);
      expect(fixture.ranges, ['30d']);
      expect(fixture.subscriptionReads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'fresh sign-in to the same user invalidates old analytics binding',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    PostDeeAuthSessionStore.instance.signIn(
        const AuthSession(userId: analyticsEnglishOwner, idToken: 'new-login'));
    await tester.pumpAndSettle();
    expect(find.text(_ownerChanged), findsOneWidget);
    expect(find.text('1.5K'), findsNothing);
    expect(fixture.ranges, ['30d']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credential and display-name refresh retain loaded analytics',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    PostDeeAuthSessionStore.instance.updateCredentials(const AuthSession(
        userId: analyticsEnglishOwner, idToken: 'refreshed-token'));
    PostDeeAuthSessionStore.instance.updateDisplayName('ชื่อผู้ใช้ภาษาไทย');
    await tester.pumpAndSettle();
    expect(find.text('1.5K'), findsOneWidget);
    expect(find.text(_ownerChanged), findsNothing);
    expect(fixture.ranges, ['30d']);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final nextOwner in ['another-owner', analyticsEnglishOwner]) {
    testWidgets('late preflight never dispatches data after sign-in $nextOwner',
        (tester) async {
      final pending = Completer<SubscriptionStatusResult>();
      final fixture = AnalyticsEnglishFixture()
        ..subscriptionRespond = () => pending.future;
      addTearDown(fixture.dispose);
      await fixture.mount(tester, settle: false);
      expect(fixture.ranges, isEmpty);
      PostDeeAuthSessionStore.instance
          .signIn(AuthSession(userId: nextOwner, idToken: 'new-login'));
      pending.complete(fixture.subscription);
      await tester.pumpAndSettle();
      expect(find.text(_ownerChanged), findsOneWidget);
      expect(fixture.ranges, isEmpty);
      expect(fixture.subscriptionReads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late data after closing the route cannot restore analytics',
      (tester) async {
    final pending = Completer<AnalyticsSummaryResult>();
    final fixture = AnalyticsEnglishFixture()..respond = (_) => pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester, settle: false);
    Navigator.of(tester.element(find.byKey(const ValueKey('analytics-scroll'))))
        .pop();
    await tester.pumpAndSettle();
    pending.complete(analyticsEnglishSummary());
    await tester.pumpAndSettle();
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('1.5K'), findsNothing);
    expect(fixture.ranges, ['30d']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed new range clears old totals and Retry reloads that range',
      (tester) async {
    var fail = true;
    final fixture = AnalyticsEnglishFixture()
      ..respond = (range) async {
        if (range == '7d' && fail) throw const SocketException('offline');
        return AnalyticsSummaryResult(
            range: range,
            totalViews: range == '7d' ? 70 : 1500,
            totalLikes: 7,
            platforms: const []);
      };
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('1.5K'), findsOneWidget);
    await selectAnalyticsRange(tester, '7d');
    expect(find.text('1.5K'), findsNothing);
    expect(find.text('Could not connect to PostDee.'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อ PostDee API ไม่ได้'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('70'), findsOneWidget);
    expect(fixture.ranges, ['30d', '7d', '7d']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('range taps during a pending request cannot dispatch duplicates',
      (tester) async {
    final pending = Completer<AnalyticsSummaryResult>();
    final fixture = AnalyticsEnglishFixture()..respond = (_) => pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester, settle: false);
    await tester.tap(find.byKey(const ValueKey('analytics-range-7d')));
    await tester.pump();
    expect(fixture.ranges, ['30d']);
    pending.complete(analyticsEnglishSummary());
    await tester.pumpAndSettle();
    final chart = find.byKey(const ValueKey('analytics-daily-chart'));
    expect(find.descendant(of: chart, matching: find.text('30 days')),
        findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale refresh cannot overwrite a newer successful response',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final old = Completer<AnalyticsSummaryResult>();
    final newer = Completer<AnalyticsSummaryResult>();
    var refresh = 0;
    fixture.respond = (_) => ++refresh == 1 ? old.future : newer.future;
    final indicator =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final first = indicator.onRefresh();
    await tester.pump();
    final second = indicator.onRefresh();
    await tester.pump();
    newer.complete(const AnalyticsSummaryResult(
        totalViews: 222, totalLikes: 22, platforms: []));
    await second;
    await tester.pumpAndSettle();
    expect(find.text('222'), findsOneWidget);
    old.completeError(
        const ApiException('Old request failed', statusCode: 503));
    await first;
    await tester.pumpAndSettle();
    expect(find.text('222'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-load-error')), findsNothing);
    expect(fixture.ranges, ['30d', '30d', '30d']);
    expect(tester.takeException(), isNull);
  });

  test('legacy analytics error formatter remains Thai for existing callers',
      () {
    expect(
        analyticsErrorMessage(
            const ApiException('Unauthorized', statusCode: 401)),
        'กรุณาเข้าสู่ระบบใหม่');
    expect(
        analyticsErrorMessage(const ApiException('Forbidden', statusCode: 403)),
        'บัญชีนี้ยังไม่มีสิทธิ์ดูข้อมูลวิเคราะห์');
    expect(
        analyticsErrorMessage(
            const ApiException('Unavailable', statusCode: 503)),
        'โหลดข้อมูลวิเคราะห์ไม่สำเร็จ ลองใหม่อีกครั้ง');
  });
}
