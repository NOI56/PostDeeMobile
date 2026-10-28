import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/analytics/analytics_screen.dart';

const analyticsEnglishOwner = 'english-analytics-owner';
const analyticsEnglishEmpty =
    AnalyticsSummaryResult(totalViews: 0, totalLikes: 0, platforms: []);

AnalyticsSummaryResult analyticsEnglishSummary() =>
    AnalyticsSummaryResult(totalViews: 1500, totalLikes: 150, platforms: const [
      PlatformAnalyticsResult(
          platform: 'YOUTUBE_SHORTS',
          label: 'YouTube Shorts',
          views: 500,
          likes: 50),
      PlatformAnalyticsResult(
          platform: 'TIKTOK', label: 'TikTok', views: 1000, likes: 100),
    ], daily: [
      for (var day = 1; day <= 7; day++)
        DailyAnalyticsResult(
            date: DateTime(2026, 10, day), views: day * 10, likes: day)
    ]);

class AnalyticsEnglishFixture {
  AnalyticsEnglishFixture(
      {Locale locale = const Locale('en'),
      this.dark = false,
      this.scale = 1,
      this.showTitle = true})
      : language = ValueNotifier(locale);

  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final bool showTitle;
  final ranges = <String>[];
  int subscriptionReads = 0;
  AnalyticsSummaryResult summary = analyticsEnglishSummary();
  Object? error;
  Object? subscriptionError;
  Future<AnalyticsSummaryResult> Function(String)? respond;
  Future<SubscriptionStatusResult> Function()? subscriptionRespond;
  SubscriptionStatusResult subscription = const SubscriptionStatusResult(
      userId: analyticsEnglishOwner,
      plan: 'PRO',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true);

  Future<SubscriptionStatusResult> loadSubscription() async {
    subscriptionReads++;
    if (subscriptionError != null) throw subscriptionError!;
    return subscriptionRespond == null
        ? subscription
        : await subscriptionRespond!();
  }

  Future<AnalyticsSummaryResult> loadAnalytics(String range) async {
    ranges.add(range);
    if (error != null) throw error!;
    return respond == null ? summary : await respond!(range);
  }

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return MaterialApp(
            locale: locale,
            supportedLocales: PostDeeLocalizations.supportedLocales,
            localizationsDelegates: const [
              PostDeeLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(),
            initialRoute: '/analytics',
            routes: {
              '/analytics': (_) => Scaffold(
                  body: SafeArea(
                      child: AnalyticsScreen(
                          showTitle: showTitle,
                          loadSubscription: loadSubscription,
                          loadAnalyticsForRange: loadAnalytics)))
            });
      });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(app());
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void dispose() => language.dispose();
}

Finder get analyticsEnglishScroll => find.descendant(
    of: find.byKey(const ValueKey('analytics-scroll')),
    matching: find.byWidgetPredicate((widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down));

Future<void> revealAnalyticsText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(finder, 160,
      scrollable: analyticsEnglishScroll);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> selectAnalyticsRange(WidgetTester tester, String range) async {
  final finder = find.byKey(ValueKey('analytics-range-$range'));
  final filters = find.descendant(
      of: find.byKey(const ValueKey('analytics-range-filters')),
      matching: find.byType(Scrollable));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 100, scrollable: filters);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _showAnalyticsHeader(WidgetTester tester) async {
  tester.state<ScrollableState>(analyticsEnglishScroll).position.jumpTo(0);
  await tester.pumpAndSettle();
}

String _englishCalendarDay(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${date.day} ${months[date.month - 1]}';
}

void expectAnalyticsTextReadable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse, reason: text.data);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5),
      reason: text.data);
}

void main() {
  setUp(() => PostDeeAuthSessionStore.instance.signIn(
      const AuthSession(userId: analyticsEnglishOwner, idToken: 'fake-token')));
  tearDown(() {
    PostDeeAuthSessionStore.instance.clear();
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets('English analytics labels real metrics and date range',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Total views'), findsOneWidget);
    expect(find.text('Engagement'), findsOneWidget);
    expect(find.text('1.5K'), findsOneWidget);
    expect(find.text('10.0%'), findsOneWidget);
    expect(find.text('Daily views'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-daily-chart')), findsOneWidget);
    expect(fixture.ranges, ['30d']);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English empty analytics never invents demonstration totals',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()..summary = analyticsEnglishEmpty;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(
        find.text(
            'No analytics data yet. Check back after your videos start getting views.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-daily-chart')), findsNothing);
    expect(find.text('Total views'), findsNothing);
    expect(find.text('128.0K'), findsNothing);
    expect(fixture.ranges, ['30d']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored analytics access error follows locale without reloading',
      (tester) async {
    final fixture = AnalyticsEnglishFixture(locale: const Locale('th'))
      ..error = const ApiException('Forbidden', statusCode: 403);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(
        find.text('บัญชีนี้ยังไม่มีสิทธิ์ดูข้อมูลวิเคราะห์'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('This account cannot access analytics.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(fixture.ranges, ['30d']);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  test('range API values and legacy Thai labels remain stable', () {
    expect(AnalyticsRangeOption.values.map((value) => value.apiValue),
        ['today', '7d', '30d', '90d', 'year']);
    expect(AnalyticsRangeOption.values.map((value) => value.label),
        ['วันนี้', '7 วัน', '30 วัน', '90 วัน', 'ปีนี้']);
  });

  testWidgets('English range controls preserve API values and calendar windows',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final starts = {
      'today': today,
      '7d': today.subtract(const Duration(days: 6)),
      '30d': today.subtract(const Duration(days: 29)),
      '90d': today.subtract(const Duration(days: 89)),
      'year': DateTime(today.year)
    };
    for (final entry in starts.entries) {
      await selectAnalyticsRange(tester, entry.key);
      await _showAnalyticsHeader(tester);
      final expected = entry.key == 'today'
          ? '${_englishCalendarDay(today)} ${today.year}'
          : '${_englishCalendarDay(entry.value)} – '
              '${_englishCalendarDay(today)} ${today.year}';
      expect(find.text(expected), findsOneWidget);
    }
    expect(fixture.ranges, ['30d', 'today', '7d', '30d', '90d', 'year']);
    await selectAnalyticsRange(tester, 'year');
    expect(fixture.ranges, hasLength(6));
    expect(fixture.subscriptionReads, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing locale retains selected range and loaded data',
      (tester) async {
    final fixture = AnalyticsEnglishFixture();
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await selectAnalyticsRange(tester, '7d');
    await _showAnalyticsHeader(tester);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('วิเคราะห์'), findsOneWidget);
    expect(find.text('ยอดวิวรวม'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Total views'), findsOneWidget);
    expect(find.text('1.5K'), findsOneWidget);
    final chart = find.byKey(const ValueKey('analytics-daily-chart'));
    expect(find.descendant(of: chart, matching: find.text('7 days')),
        findsOneWidget);
    expect(fixture.ranges, ['30d', '7d']);
    expect(fixture.subscriptionReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform order uses views and preserves raw Thai labels',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()
      ..summary = const AnalyticsSummaryResult(
          totalViews: 700,
          totalLikes: 70,
          platforms: [
            PlatformAnalyticsResult(
                platform: 'TIKTOK',
                label: 'ชื่อช่องของลูกค้า',
                views: 200,
                likes: 20),
            PlatformAnalyticsResult(
                platform: 'CUSTOM', label: 'ยอดวิวรวม', views: 500, likes: 50)
          ]);
    final original = fixture.summary.platforms;
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    await revealAnalyticsText(tester, 'Best-performing platforms');
    await revealAnalyticsText(tester, 'ชื่อช่องของลูกค้า');
    expect(find.text('ยอดวิวรวม'), findsOneWidget);
    expect(tester.getTopLeft(find.text('ยอดวิวรวม')).dy,
        lessThan(tester.getTopLeft(find.text('ชื่อช่องของลูกค้า')).dy));
    expect(find.text('20 likes'), findsOneWidget);
    expect(find.text('50 likes'), findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pumpAndSettle();
    expect(find.text('ชื่อช่องของลูกค้า'), findsOneWidget);
    expect(fixture.summary.platforms, same(original));
    expect(original.map((metric) => metric.views), [200, 500]);
    expect(fixture.ranges, ['30d']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'daily chart preserves seven aggregate buckets from longer ranges',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()
      ..summary = AnalyticsSummaryResult(
          totalViews: 105,
          totalLikes: 0,
          platforms: const [],
          daily: [
            for (var day = 1; day <= 14; day++)
              DailyAnalyticsResult(
                  date: DateTime(2026, 10, day), views: day, likes: 0)
          ]);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    final chart = find.byKey(const ValueKey('analytics-daily-chart'));
    for (final sum in ['3', '7', '11', '15', '19', '23', '27']) {
      expect(
          find.descendant(of: chart, matching: find.text(sum)), findsOneWidget);
    }
    expect(fixture.summary.daily, hasLength(14));
    expect(
        fixture.summary.daily.fold<int>(0, (sum, value) => sum + value.views),
        105);
    expect(tester.takeException(), isNull);
  });

  for (final entry in {1000: '1.0K', 1234567: '1.2M'}.entries) {
    testWidgets('English totals preserve compact view count ${entry.key}',
        (tester) async {
      final fixture = AnalyticsEnglishFixture()
        ..summary = AnalyticsSummaryResult(
            totalViews: entry.key, totalLikes: 100, platforms: const []);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Total views'), findsOneWidget);
      expect(fixture.summary.totalViews, entry.key);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'zero views with likes has zero engagement without fabricated views',
      (tester) async {
    final fixture = AnalyticsEnglishFixture()
      ..summary = const AnalyticsSummaryResult(
          totalViews: 0, totalLikes: 2, platforms: []);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('No analytics data yet'), findsNothing);
    expect(find.byKey(const ValueKey('analytics-daily-chart')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded analytics can omit its heading while retaining metrics',
      (tester) async {
    final fixture = AnalyticsEnglishFixture(showTitle: false);
    addTearDown(fixture.dispose);
    await fixture.mount(tester);
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Total views'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-range-30d')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain MaterialApp retains the existing Thai analytics fallback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AnalyticsScreen(loadAnalytics: () async {
      calls++;
      return analyticsEnglishSummary();
    }))));
    await tester.pumpAndSettle();
    expect(find.text('วิเคราะห์'), findsOneWidget);
    expect(find.text('ยอดวิวรวม'), findsOneWidget);
    expect(find.text('ยอดวิวรายวัน'), findsOneWidget);
    expect(find.text('Analytics'), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending analytics changes language without another load or totals',
      (tester) async {
    final pending = Completer<AnalyticsSummaryResult>();
    final fixture = AnalyticsEnglishFixture()..respond = (_) => pending.future;
    addTearDown(fixture.dispose);
    await fixture.mount(tester, settle: false);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('1.5K'), findsNothing);
    fixture.language.value = const Locale('th');
    await tester.pump();
    expect(find.text('วิเคราะห์'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(find.text('Analytics'), findsOneWidget);
    expect(fixture.ranges, ['30d']);
    pending.complete(analyticsEnglishSummary());
    await tester.pumpAndSettle();
    expect(find.text('1.5K'), findsOneWidget);
    expect(fixture.subscriptionReads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('analytics chart and controls fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dailyViews = [12345, 23456, 34567, 45678, 56789, 67890, 78901];
      final fixture = AnalyticsEnglishFixture(dark: dark, scale: 2)
        ..summary = AnalyticsSummaryResult(
            totalViews: 319626,
            totalLikes: 31963,
            platforms: const [
              PlatformAnalyticsResult(
                  platform: 'TIKTOK',
                  label: 'TikTok',
                  views: 200000,
                  likes: 20000),
              PlatformAnalyticsResult(
                  platform: 'YOUTUBE_SHORTS',
                  label: 'YouTube Shorts',
                  views: 119506,
                  likes: 11951),
              PlatformAnalyticsResult(
                  platform: 'CUSTOM',
                  label: 'ช่องร้านของลูกค้าสำหรับสินค้าขายดีประจำเดือน',
                  views: 120,
                  likes: 12)
            ],
            daily: [
              for (var index = 0; index < dailyViews.length; index++)
                DailyAnalyticsResult(
                    date: DateTime(2026, 10, index + 1),
                    views: dailyViews[index],
                    likes: 0)
            ]);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      expect(tester.takeException(), isNull);
      expectAnalyticsTextReadable(tester, find.text('Analytics'));
      for (final entry in {
        'today': 'Today',
        '7d': '7 days',
        '30d': '30 days',
        '90d': '90 days',
        'year': 'This year'
      }.entries) {
        await selectAnalyticsRange(tester, entry.key);
        final chip = find.byKey(ValueKey('analytics-range-${entry.key}'));
        expectAnalyticsTextReadable(tester,
            find.descendant(of: chip, matching: find.text(entry.value)));
        expect(
            tester.getSize(chip).height,
            greaterThanOrEqualTo(tester
                .getSize(
                    find.descendant(of: chip, matching: find.text(entry.value)))
                .height));
        expect(tester.takeException(), isNull);
      }
      for (final title in ['Trending hashtag radar', 'AI comment center']) {
        await revealAnalyticsText(tester, title);
        final card = find
            .ancestor(
                of: find.text(title), matching: find.byType(GestureDetector))
            .first;
        final status =
            find.descendant(of: card, matching: find.text('Coming soon'));
        await tester.ensureVisible(status);
        await tester.pumpAndSettle();
        expectAnalyticsTextReadable(tester, status);
      }
      await _showAnalyticsHeader(tester);
      for (final text in [
        'Total views',
        '319.6K',
        'Engagement',
        '10.0%',
        'Daily views',
        '12.3K',
        '23.5K',
        '34.6K',
        '45.7K',
        '56.8K',
        '67.9K',
        '78.9K',
        'Best-performing platforms',
        'TikTok',
        '20000 likes',
        'YouTube Shorts',
        '11951 likes',
        'ช่องร้านของลูกค้าสำหรับสินค้าขายดีประจำเดือน',
        '12 likes',
        'AI analytics tools',
        'Trending hashtag radar',
        'Find trending hashtags and keywords for your next video.',
        'AI comment center',
        'Summarize comments and prepare reply drafts for review.'
      ]) {
        await revealAnalyticsText(tester, text);
        expectAnalyticsTextReadable(tester, find.text(text));
        if (text == '319.6K' || text == '10.0%') {
          final paragraph = tester.renderObject<RenderParagraph>(find
              .descendant(of: find.text(text), matching: find.byType(RichText))
              .first);
          expect(
              paragraph.size.height,
              lessThanOrEqualTo(
                  paragraph.getMinIntrinsicHeight(double.infinity) + 0.5),
              reason: 'Keep the complete KPI value $text on one line; '
                  'available width ${paragraph.size.width}, '
                  'unwrapped width ${paragraph.getMaxIntrinsicWidth(double.infinity)}');
        }
        if (text == '78.9K') {
          expect(find.text(text).hitTestable(), findsOneWidget);
          expect(tester.getRect(find.text(text)).right, lessThanOrEqualTo(320));
        }
        expect(tester.takeException(), isNull);
      }
      expect(fixture.ranges, ['30d', 'today', '7d', '30d', '90d', 'year']);
    });

    testWidgets('analytics English error and Retry fit 320dp 2x (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = AnalyticsEnglishFixture(dark: dark, scale: 2)
        ..error = const ApiException('Unavailable', statusCode: 503);
      addTearDown(fixture.dispose);
      await fixture.mount(tester);
      for (final text in [
        'Could not load analytics. Please try again.',
        'Retry'
      ]) {
        await revealAnalyticsText(tester, text);
        expectAnalyticsTextReadable(tester, find.text(text));
      }
      expect(find.text('Retry').hitTestable(), findsOneWidget);
      fixture.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analytics-load-error')), findsNothing);
      expect(fixture.ranges, ['30d', '30d']);
      expect(tester.takeException(), isNull);
    });
  }
}
