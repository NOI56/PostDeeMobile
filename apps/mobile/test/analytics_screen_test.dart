import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/analytics/analytics_screen.dart';

Future<void> _expectTextAfterScrolling(
  WidgetTester tester,
  Finder scrollable,
  String text,
) async {
  final finder = find.text(text);

  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      expect(finder, findsOneWidget);
      return;
    }

    await tester.drag(scrollable, const Offset(0, -260));
    await tester.pumpAndSettle();
  }

  expect(finder, findsOneWidget);
}

Future<void> _tapTextAfterScrolling(
  WidgetTester tester,
  Finder scrollable,
  String text,
) async {
  await _expectTextAfterScrolling(tester, scrollable, text);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  final analyticsScroll = find.descendant(
    of: find.byKey(const ValueKey('analytics-scroll')),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          widget.axisDirection == AxisDirection.down &&
          widget.restorationId == null,
    ),
  );

  testWidgets('shows a Thai Pro lock instead of the raw backend error',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadAnalytics: () async => throw const ApiException(
              'Unified Analytics requires the Pro plan',
              statusCode: 402,
              code: 'PRO_REQUIRED',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro'),
      findsOneWidget,
    );
    expect(find.textContaining('Unified Analytics'), findsNothing);
  });

  testWidgets('locks Basic users before requesting analytics', (tester) async {
    var analyticsCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadSubscription: () async => const SubscriptionStatusResult(
              userId: 'basic-user',
              plan: 'BASIC',
              status: 'INACTIVE',
              canSchedule: false,
              canUseAiCaptions: false,
              canUseAnalytics: false,
            ),
            loadAnalytics: () async {
              analyticsCalls += 1;
              return const AnalyticsSummaryResult(
                totalViews: 0,
                totalLikes: 0,
                platforms: [],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(analyticsCalls, 0);
    expect(
      find.text('ข้อมูลวิเคราะห์รวมเปิดให้ใช้ในแพ็กเกจ Pro'),
      findsOneWidget,
    );
    expect(find.textContaining('โหลดข้อมูลวิเคราะห์ไม่สำเร็จ'), findsNothing);
  });

  testWidgets('shows the refreshed analytics dashboard sections',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadAnalytics: () async => AnalyticsSummaryResult(
              totalViews: 150,
              totalLikes: 15,
              platforms: [
                PlatformAnalyticsResult(
                  platform: 'TIKTOK',
                  label: 'TikTok',
                  views: 150,
                  likes: 15,
                ),
              ],
              daily: [
                DailyAnalyticsResult(
                  date: DateTime(2026, 7, 9),
                  views: 50,
                  likes: 5,
                ),
                DailyAnalyticsResult(
                  date: DateTime(2026, 7, 10),
                  views: 100,
                  likes: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('วิเคราะห์'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-range-30d')), findsOneWidget);
    expect(find.text('ยอดวิวรายวัน'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-daily-chart')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ช่องทางที่ทำผลงานดีสุด'),
      500,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('ช่องทางที่ทำผลงานดีสุด'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('รายงานเชิงลึก (Pro)'), findsNothing);
  });

  testWidgets('reloads real analytics when the date range changes',
      (tester) async {
    final requestedRanges = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadAnalyticsForRange: (range) async {
              requestedRanges.add(range);
              return AnalyticsSummaryResult(
                range: range,
                totalViews: 10,
                totalLikes: 1,
                platforms: const [],
                daily: const [],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedRanges, ['30d']);
    await tester.tap(find.byKey(const ValueKey('analytics-range-7d')));
    await tester.pumpAndSettle();
    expect(requestedRanges, ['30d', '7d']);
  });

  testWidgets('does not fall back to demo analytics when summary is empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadAnalytics: () async => const AnalyticsSummaryResult(
              totalViews: 0,
              totalLikes: 0,
              platforms: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('128.0K'), findsNothing);
    expect(find.text('9.4K'), findsNothing);
    expect(find.text('62.0K'), findsNothing);
  });

  testWidgets('shows analytics growth tools for hashtags and comments',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(),
        ),
      ),
    );

    await _expectTextAfterScrolling(
      tester,
      analyticsScroll,
      'เรดาร์แฮชแท็กฮิต',
    );
    await _expectTextAfterScrolling(
      tester,
      analyticsScroll,
      'ศูนย์คอมเมนต์ AI',
    );
    expect(find.text('เร็ว ๆ นี้'), findsNWidgets(2));
    expect(find.text('บันทึกชุดคีย์เวิร์ดสำหรับทีม'), findsNothing);
    expect(
      find.text('คอมเมนต์และคำตอบต้องให้เจ้าของร้านอนุมัติก่อนเผยแพร่'),
      findsNothing,
    );
  });

  testWidgets('opens analytics growth tool detail settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(),
        ),
      ),
    );

    final toolTitles = [
      'เรดาร์แฮชแท็กฮิต',
      'ศูนย์คอมเมนต์ AI',
    ];

    for (final title in toolTitles) {
      await _tapTextAfterScrolling(tester, analyticsScroll, title);

      expect(find.text('รายละเอียดและตั้งค่า'), findsOneWidget);
      expect(find.text('ตั้งค่า: $title'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('growth-tool-real-status-note')),
        findsOneWidget,
      );
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

  testWidgets('auto-loads and displays unified analytics summary',
      (tester) async {
    final summaryCompleter = Completer<AnalyticsSummaryResult>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyticsScreen(
            loadAnalytics: () => summaryCompleter.future,
          ),
        ),
      ),
    );

    // Auto-load runs on init; the dashboard stays empty until real data arrives.
    await tester.pump();

    summaryCompleter.complete(
      const AnalyticsSummaryResult(
        totalViews: 150,
        totalLikes: 15,
        platforms: [
          PlatformAnalyticsResult(
            platform: 'TIKTOK',
            label: 'TikTok',
            views: 100,
            likes: 10,
          ),
          PlatformAnalyticsResult(
            platform: 'YOUTUBE_SHORTS',
            label: 'YouTube Shorts',
            views: 50,
            likes: 5,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('ยอดวิวรวม'),
      -500,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('150'), findsWidgets);
    expect(find.text('10.0%'), findsOneWidget);
    expect(find.text('ยอดวิวรวม'), findsOneWidget);
    expect(find.text('เอนเกจเมนต์'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ช่องทางที่ทำผลงานดีสุด'),
      500,
      scrollable: analyticsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('10 ไลก์'), findsOneWidget);
    expect(find.text('YouTube Shorts'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('5 ไลก์'), findsOneWidget);
  });
}
