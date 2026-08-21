import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/home/home_screen.dart';

Finder _homeScrollable() => find.byType(Scrollable).first;

Future<void> _scrollHomeDown(WidgetTester tester) async {
  await tester.drag(_homeScrollable(), const Offset(0, -700));
  await tester.pumpAndSettle();
}

Future<void> _expectHomeTextAfterScrolling(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);

  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      return;
    }

    await tester.drag(_homeScrollable(), const Offset(0, -260));
    await tester.pumpAndSettle();
  }

  expect(finder, findsOneWidget);
}

Future<void> _tapHomeTextAfterScrolling(
  WidgetTester tester,
  String text,
) async {
  await _expectHomeTextAfterScrolling(tester, text);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _expectHomeTextsNeverAppearAfterScrolling(
  WidgetTester tester,
  List<String> texts,
) async {
  for (var attempt = 0; attempt < 12; attempt += 1) {
    for (final text in texts) {
      expect(find.text(text), findsNothing);
    }

    await tester.drag(_homeScrollable(), const Offset(0, -180));
    await tester.pumpAndSettle();
  }
}

void _expectNoDeveloperTools() {
  expect(find.text('Backend API'), findsNothing);
  expect(find.text('Check API connection'), findsNothing);
  expect(find.text('Test Gemini caption'), findsNothing);
  expect(find.text('Refresh plan'), findsNothing);
  expect(find.text('Phone verification'), findsNothing);
  expect(find.text('Phone number'), findsNothing);
  expect(find.text('Send OTP'), findsNothing);
  expect(find.text('Start Starter subscription'), findsNothing);
  expect(find.text('Start Pro subscription'), findsNothing);
  expect(find.text('Restore Pro purchase'), findsNothing);
  expect(find.text('Next step'), findsNothing);
}

Widget _homeTestApp(
  Widget child, {
  double textScale = 1,
}) {
  return MaterialApp(
    locale: const Locale('th'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    localizationsDelegates: const [
      PostDeeLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: PostDeeLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('does not call the user Free when subscription loading fails',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadSubscription: () async =>
              throw const SocketException('subscription offline'),
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบแพ็กเกจไม่ได้'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsNothing);
    expect(find.text('อัปเกรด'), findsNothing);
  });

  testWidgets('replaces the raw Pro analytics error with Thai UI copy',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => throw const ApiException(
            'Unified Analytics requires the Pro plan',
            statusCode: 402,
            code: 'PRO_REQUIRED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byTooltip('ลองใหม่'), findsNWidgets(2));
    for (final element in find.byTooltip('ลองใหม่').evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(find.textContaining('Unified Analytics'), findsNothing);
  });

  testWidgets('shows a latest-post load error instead of an empty account',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => throw const SocketException('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-latest-posts-error')),
      findsOneWidget,
    );
    expect(find.text('โหลดโพสต์ล่าสุดไม่สำเร็จ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
  });

  testWidgets('does not show demo home metrics when no real data exists',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
        ),
      ),
    );

    expect(find.text('128'), findsNothing);
    expect(find.text('45.2K'), findsNothing);
    expect(find.text('32.1K'), findsNothing);
    expect(find.text('18.7K'), findsNothing);
    expect(find.text('3.2K'), findsNothing);
    expect(find.text('แพ็กเกจโปร'), findsNothing);
    expect(find.text('คงเหลือ 23 วัน'), findsNothing);
  });

  testWidgets('shows both analytics cards as locked for non-Pro plans',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-basic',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byTooltip('ดู Pro'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'keeps home metrics compact at ${width}dp and ${textScale}x text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _homeTestApp(
            HomeScreen(
              key: ValueKey('metrics-$width-$textScale'),
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller-compact-metrics',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: () async => const [],
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();

        await _expectHomeTextAfterScrolling(tester, 'ยอดวิวเดือนนี้');
        await tester.ensureVisible(find.text('ยอดวิวเดือนนี้'));
        await tester.pumpAndSettle();

        final viewsCard = find.byKey(const ValueKey('home-views-metric-card'));
        final likesCard = find.byKey(const ValueKey('home-likes-metric-card'));
        expect(viewsCard, findsOneWidget);
        expect(likesCard, findsOneWidget);

        final viewsRect = tester.getRect(viewsCard);
        final likesRect = tester.getRect(likesCard);
        expect(viewsRect.right, lessThan(likesRect.left));
        expect((viewsRect.top - likesRect.top).abs(), lessThan(1));
        expect(viewsRect.height, lessThanOrEqualTo(96));
        expect(likesRect.height, lessThanOrEqualTo(96));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('loads real subscription status on the home plan card',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-starter',
            plan: 'STARTER',
            status: 'ACTIVE',
            remainingPostsThisMonth: 8,
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แพ็กเกจ Starter'), findsOneWidget);
    expect(find.text('เหลือ 8/120 หน่วย'), findsOneWidget);
    expect(find.text('แพ็กเกจโปร'), findsNothing);
    expect(find.text('คงเหลือ 23 วัน'), findsNothing);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets(
          'keeps the Pro plan readable at ${width}dp and ${textScale}x text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _homeTestApp(
            HomeScreen(
              key: ValueKey('$width-$textScale'),
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller-pro',
                plan: 'PRO',
                status: 'ACTIVE',
                remainingPostsThisMonth: 250,
                canSchedule: true,
                canUseAiCaptions: true,
                canUseAnalytics: true,
              ),
              loadRecentPosts: () async => const [],
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
        expect(find.text('เหลือ 250/250 หน่วย'), findsOneWidget);
        expect(find.text('อัปเกรด'), findsNothing);
        final title = tester.widget<Text>(
          find.byKey(const ValueKey('home-plan-title')),
        );
        final subtitle = tester.widget<Text>(
          find.byKey(const ValueKey('home-plan-subtitle')),
        );
        expect(title.overflow, isNull);
        expect(title.maxLines, isNull);
        expect(subtitle.overflow, isNull);
        expect(subtitle.maxLines, isNull);
        final planProgress = tester.widget<FractionallySizedBox>(
          find.byKey(const ValueKey('home-plan-progress-fill')),
        );
        expect(planProgress.widthFactor, 1);
        expect(tester.takeException(), isNull);

        for (var attempt = 0; attempt < 20; attempt += 1) {
          final scrollable = tester.state<ScrollableState>(_homeScrollable());
          if (scrollable.position.pixels >=
              scrollable.position.maxScrollExtent) {
            break;
          }
          await tester.drag(_homeScrollable(), const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('refreshes the home plan after returning from the paywall',
      (tester) async {
    var subscriptionLoadCalls = 0;

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async {
            subscriptionLoadCalls += 1;
            final isPro = subscriptionLoadCalls >= 3;
            return SubscriptionStatusResult(
              userId: 'seller-refresh',
              plan: isPro ? 'PRO' : 'BASIC',
              status: isPro ? 'ACTIVE' : 'INACTIVE',
              remainingPostsThisMonth: isPro ? 250 : 3,
              canSchedule: isPro,
              canUseAiCaptions: isPro,
              canUseAnalytics: isPro,
            );
          },
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);

    await tester.tap(find.text('แพ็กเกจฟรี'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกแพ็กเกจ'), findsOneWidget);

    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();

    expect(subscriptionLoadCalls, 3);
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
  });

  testWidgets('reloads stale Pro-required analytics after upgrading',
      (tester) async {
    var isPro = false;
    var analyticsLoadCalls = 0;

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async {
            analyticsLoadCalls += 1;
            if (analyticsLoadCalls == 1) {
              throw const ApiException(
                'Unified Analytics requires the Pro plan',
                statusCode: 402,
                code: 'PRO_REQUIRED',
              );
            }
            return const AnalyticsSummaryResult(
              totalViews: 4321,
              totalLikes: 321,
              platforms: [],
            );
          },
          loadSubscription: () async => SubscriptionStatusResult(
            userId: 'seller-upgrade-analytics',
            plan: isPro ? 'PRO' : 'BASIC',
            status: isPro ? 'ACTIVE' : 'INACTIVE',
            remainingPostsThisMonth: isPro ? 250 : 3,
            canSchedule: isPro,
            canUseAiCaptions: isPro,
            canUseAnalytics: isPro,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsNWidgets(2));
    await tester.tap(find.text('แพ็กเกจฟรี'));
    await tester.pumpAndSettle();
    isPro = true;
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();

    expect(analyticsLoadCalls, 2);
    expect(find.text('4321'), findsOneWidget);
    expect(find.text('321'), findsOneWidget);
    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsNothing);
  });

  testWidgets('stale analytics cannot overwrite fresh Pro analytics',
      (tester) async {
    final staleAnalytics = Completer<AnalyticsSummaryResult>();
    final freshAnalytics = Completer<AnalyticsSummaryResult>();
    var isPro = false;
    var analyticsLoadCalls = 0;

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () {
            analyticsLoadCalls += 1;
            return analyticsLoadCalls == 1
                ? staleAnalytics.future
                : freshAnalytics.future;
          },
          loadSubscription: () async => SubscriptionStatusResult(
            userId: 'seller-analytics-race',
            plan: isPro ? 'PRO' : 'BASIC',
            status: isPro ? 'ACTIVE' : 'INACTIVE',
            remainingPostsThisMonth: isPro ? 250 : 3,
            canSchedule: isPro,
            canUseAiCaptions: isPro,
            canUseAnalytics: isPro,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('แพ็กเกจฟรี'));
    await tester.pumpAndSettle();
    isPro = true;
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pump();
    await tester.pump();
    expect(analyticsLoadCalls, 2);

    freshAnalytics.complete(const AnalyticsSummaryResult(
      totalViews: 4321,
      totalLikes: 321,
      platforms: [],
    ));
    await tester.pumpAndSettle();
    expect(find.text('4321'), findsOneWidget);
    expect(find.text('321'), findsOneWidget);

    staleAnalytics.completeError(const ApiException(
      'Unified Analytics requires the Pro plan',
      statusCode: 402,
      code: 'PRO_REQUIRED',
    ));
    await tester.pumpAndSettle();

    expect(find.text('4321'), findsOneWidget);
    expect(find.text('321'), findsOneWidget);
    expect(find.text('เฉพาะแพ็กเกจ Pro'), findsNothing);
  });

  testWidgets('ignores a stale Basic plan after returning from the paywall',
      (tester) async {
    final initialLoad = Completer<SubscriptionStatusResult>();
    var subscriptionLoadCalls = 0;
    const basic = SubscriptionStatusResult(
      userId: 'seller-stale-home',
      plan: 'BASIC',
      status: 'INACTIVE',
      canSchedule: false,
      canUseAiCaptions: false,
      canUseAnalytics: false,
    );
    const pro = SubscriptionStatusResult(
      userId: 'seller-stale-home',
      plan: 'PRO',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: true,
    );

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () {
            subscriptionLoadCalls += 1;
            return switch (subscriptionLoadCalls) {
              1 => initialLoad.future,
              2 => Future.value(basic),
              _ => Future.value(pro),
            };
          },
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('อัปเกรด'), findsNothing);
    await tester.tap(find.text('กำลังโหลดแพ็กเกจ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);

    initialLoad.complete(basic);
    await tester.pumpAndSettle();

    expect(subscriptionLoadCalls, 3);
    expect(find.text('แพ็กเกจ Pro'), findsOneWidget);
  });

  testWidgets('shows only real user-facing home sections', (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(find.text('ยอดวิวเดือนนี้'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
    expect(find.text('128'), findsNothing);
    expect(find.text('โพสต์ล่าสุด'), findsOneWidget);
    expect(find.text('ดูทั้งหมด'), findsNothing);
    expect(find.text('TikTok'), findsNothing);
    expect(find.text('YouTube Shorts'), findsNothing);
    expect(find.text('Instagram Reels'), findsNothing);
    expect(find.text('Facebook Reels'), findsNothing);
    expect(find.text('โพสต์วันนี้ 2'), findsNothing);
    expect(find.text('กำลังประมวลผล'), findsNothing);
    expect(find.text('45.2K'), findsNothing);
    expect(find.text('3.2K'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsOneWidget,
    );
    _expectNoDeveloperTools();

    await _scrollHomeDown(tester);
    expect(find.text('ทางลัด'), findsNothing);
    expect(find.widgetWithText(TextButton, 'อัปโหลด'), findsNothing);
    expect(find.widgetWithText(TextButton, 'เทมเพลต'), findsNothing);
    _expectNoDeveloperTools();

    await _scrollHomeDown(tester);
    _expectNoDeveloperTools();
  });

  testWidgets('matches the reference home first screen', (tester) async {
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 1240,
            totalLikes: 328,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            remainingPostsThisMonth: 1,
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('แพ็กเกจฟรี'), findsOneWidget);
    expect(find.text('เหลือ 1/3 หน่วย'), findsOneWidget);
    final planProgress = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('home-plan-progress-fill')),
    );
    expect(planProgress.widthFactor, moreOrLessEquals(1 / 3));
    expect(find.text('อัปเกรด'), findsOneWidget);
    expect(find.text('ตัดต่อด้วย AI'), findsOneWidget);
    expect(
      find.text('ให้ AI ตัดคลิปให้กระชับ ใส่ซับ เป็นสไตล์ไวรัลอัตโนมัติ'),
      findsOneWidget,
    );
    expect(find.text('ยอดวิวเดือนนี้'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
    expect(find.text('สร้างโพสต์ใหม่'), findsOneWidget);
    expect(find.text('โพสต์ล่าสุด'), findsOneWidget);
    expect(find.text('ยังไม่มีโพสต์'), findsOneWidget);
    expect(
      find.text('เริ่มสร้างโพสต์แรกของร้านคุณ\nโพสต์คลิปเดียวไปได้ทุกช่องทาง'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'สร้างโพสต์'), findsNothing);

    await _expectHomeTextAfterScrolling(tester, 'เครื่องมือเติบโต');
    expect(find.text('ช่วยให้ขายดี'), findsOneWidget);
  });
  testWidgets('loads and displays total views on the home dashboard',
      (tester) async {
    final analyticsCompleter = Completer<AnalyticsSummaryResult>();

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () => analyticsCompleter.future,
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'PRO',
            status: 'ACTIVE',
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    // Analytics now loads on init, so the views card shows the loading label
    // without a manual refresh tap.
    await tester.pump();

    expect(find.text('...'), findsNWidgets(2));

    analyticsCompleter.complete(
      const AnalyticsSummaryResult(
        totalViews: 1200,
        totalLikes: 140,
        platforms: [
          PlatformAnalyticsResult(
            platform: 'TIKTOK',
            label: 'TikTok',
            views: 1200,
            likes: 140,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1200'), findsOneWidget);
    expect(find.text('140'), findsOneWidget);
    expect(find.text('ไลก์เดือนนี้'), findsOneWidget);
  });

  testWidgets('keeps very large analytics values on one fitted line',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const largeValue = '999999999999';

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 999999999999,
            totalLikes: 999999999999,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller-large-analytics',
            plan: 'PRO',
            status: 'ACTIVE',
            canSchedule: true,
            canUseAiCaptions: true,
            canUseAnalytics: true,
          ),
          loadRecentPosts: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(largeValue), findsNWidgets(2));
    for (final element in find.text(largeValue).evaluate()) {
      expect((element.widget as Text).maxLines, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows real latest posts on the home dashboard', (tester) async {
    final publishedAt = DateTime.now().subtract(const Duration(hours: 2));

    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'p1',
              caption: 'โปรโมตสินค้าใหม่',
              videoS3Key: 'clip.mp4',
              platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
              status: 'PUBLISHED',
              createdAt: publishedAt,
              publishedAt: publishedAt,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('โปรโมตสินค้าใหม่'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsOneWidget);
    expect(find.text('TikTok · YouTube Shorts'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-latest-posts-empty')),
      findsNothing,
    );
  });

  testWidgets('shows a provider draft outcome on the home dashboard',
      (tester) async {
    final deliveredAt = DateTime.now().subtract(const Duration(hours: 1));
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'draft-p1',
              caption: 'ส่งร่าง TikTok',
              videoS3Key: 'clip.mp4',
              platforms: const ['TIKTOK'],
              status: 'PUBLISHED',
              createdAt: deliveredAt,
              publishedAt: deliveredAt,
              platformResults: const [
                PostPlatformResult(
                  postId: 'draft-p1',
                  platform: 'TIKTOK',
                  status: 'PUBLISHED',
                  deliveryOutcome: 'DRAFT',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsNothing);
  });

  testWidgets('does not present an unknown provider outcome as published',
      (tester) async {
    final deliveredAt = DateTime.now().subtract(const Duration(hours: 1));
    await tester.pumpWidget(
      _homeTestApp(
        HomeScreen(
          loadAnalytics: () async => const AnalyticsSummaryResult(
            totalViews: 0,
            totalLikes: 0,
            platforms: [],
          ),
          loadSubscription: () async => const SubscriptionStatusResult(
            userId: 'seller',
            plan: 'BASIC',
            status: 'ACTIVE',
            canSchedule: false,
            canUseAiCaptions: false,
            canUseAnalytics: false,
          ),
          loadRecentPosts: () async => [
            PostSummaryResult(
              id: 'unknown-p1',
              caption: 'ผลใหม่จากผู้ให้บริการ',
              videoS3Key: 'clip.mp4',
              platforms: const ['TIKTOK'],
              status: 'PUBLISHED',
              createdAt: deliveredAt,
              publishedAt: deliveredAt,
              platformResults: const [
                PostPlatformResult(
                  postId: 'unknown-p1',
                  platform: 'TIKTOK',
                  status: 'PUBLISHED',
                  deliveryOutcome: 'FUTURE_OUTCOME',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.text('เผยแพร่'), findsNothing);
  });

  testWidgets(
      'loads latest posts only while home is active and refreshes on return',
      (tester) async {
    var loadCount = 0;
    var homeIsActive = false;
    late StateSetter setHostState;

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeScreen(
              isActive: homeIsActive,
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: () async {
                loadCount += 1;
                return const [];
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 0);

    setHostState(() => homeIsActive = true);
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = false);
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = true);
    await tester.pumpAndSettle();
    expect(loadCount, 2);
  });

  testWidgets('queues a home refresh instead of overlapping post loads',
      (tester) async {
    final firstLoad = Completer<List<PostSummaryResult>>();
    var loadCount = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    var homeIsActive = true;
    late StateSetter setHostState;

    Future<List<PostSummaryResult>> loadRecentPosts() async {
      loadCount += 1;
      inFlight += 1;
      if (inFlight > maxInFlight) {
        maxInFlight = inFlight;
      }

      try {
        if (loadCount == 1) {
          return await firstLoad.future;
        }
        return const [];
      } finally {
        inFlight -= 1;
      }
    }

    await tester.pumpWidget(
      _homeTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeScreen(
              isActive: homeIsActive,
              loadAnalytics: () async => const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              ),
              loadSubscription: () async => const SubscriptionStatusResult(
                userId: 'seller',
                plan: 'BASIC',
                status: 'ACTIVE',
                canSchedule: false,
                canUseAiCaptions: false,
                canUseAnalytics: false,
              ),
              loadRecentPosts: loadRecentPosts,
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(loadCount, 1);

    setHostState(() => homeIsActive = false);
    await tester.pump();
    setHostState(() => homeIsActive = true);
    await tester.pump();

    expect(loadCount, 1);
    expect(maxInFlight, 1);

    firstLoad.complete(const []);
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(maxInFlight, 1);
  });

  testWidgets('shows phase 2 growth tool previews on the home dashboard',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _expectHomeTextAfterScrolling(tester, 'เครื่องมือเติบโต');
    // Home shows two growth tools per the design handoff; "team" moved into
    // the growth detail screen.
    final toolTitles = [
      'ลิงก์หน้าโปรไฟล์',
      'แจ้งเตือนคลิปไวรัล',
    ];

    for (final title in toolTitles) {
      await _expectHomeTextAfterScrolling(tester, title);
    }
    expect(find.text('ทีมและผู้ช่วย'), findsNothing);
  });

  testWidgets('keeps upload and analytics growth tools off home dashboard',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _expectHomeTextsNeverAppearAfterScrolling(
      tester,
      [
        'ตัดคลิปเป็น EP',
        'ใส่ลายน้ำอัตโนมัติ',
        'เรดาร์แฮชแท็กฮิต',
        'ศูนย์คอมเมนต์ AI',
        'คอมเมนต์และคำตอบต้องให้เจ้าของร้านอนุมัติก่อนเผยแพร่',
      ],
    );
  });

  testWidgets('opens Link in Bio builder from the home growth card',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    await _tapHomeTextAfterScrolling(tester, 'ลิงก์หน้าโปรไฟล์');

    expect(find.text('สร้างหน้า Link in Bio'), findsOneWidget);
    expect(find.text('ตัวอย่าง: postdee.link/ร้านของคุณ'), findsOneWidget);
    expect(find.text('ลิงก์สินค้าและแคมเปญ'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('อัปเดตจากโพสต์ที่ตั้งเวลา'), findsOneWidget);
    expect(find.text('ดูตัวอย่างหน้า'), findsOneWidget);
    expect(find.text('บันทึกแบบร่าง'), findsOneWidget);
  });

  testWidgets('opens growth tool detail settings from home cards',
      (tester) async {
    await tester.pumpWidget(
      _homeTestApp(const HomeScreen()),
    );

    final toolTitles = [
      'แจ้งเตือนคลิปไวรัล',
    ];

    for (final title in toolTitles) {
      await _tapHomeTextAfterScrolling(tester, title);

      expect(find.text('รายละเอียดและตั้งค่า'), findsOneWidget);
      expect(find.text('ตั้งค่า: $title'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-real-status-note')),
        findsOneWidget,
      );
      expect(find.text('เร็ว ๆ นี้'), findsWidgets);
      expect(find.text('แบบร่างในเครื่อง'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-enabled-switch')),
        findsNothing,
      );
      expect(find.text('บันทึกแบบร่าง'), findsOneWidget);

      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
    }
  });
}
