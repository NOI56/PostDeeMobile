import 'dart:async';

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

Widget _homeTestApp(Widget child) {
  return MaterialApp(
    locale: const Locale('th'),
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
    expect(planProgress.widthFactor, moreOrLessEquals(2 / 3));
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
    expect(find.widgetWithText(FilledButton, 'สร้างโพสต์'), findsOneWidget);

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
    expect(find.text('postdee.link/ร้านของคุณ'), findsOneWidget);
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
      expect(find.text('ตั้งค่าในเครื่องนี้'), findsOneWidget);
      expect(find.text('ยังไม่เชื่อมระบบจริง'), findsNothing);

      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
    }
  });
}
