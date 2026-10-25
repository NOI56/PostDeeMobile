import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';

void main() {
  final now = DateTime(2026, 10, 21, 10);
  final post = CalendarPostResult(
      id: 'october-post',
      caption: 'October clip',
      videoS3Key: 'uploads/owner/video.mp4',
      platforms: const ['TIKTOK'],
      status: 'PUBLISHED',
      publishedAt: DateTime(2026, 10, 5, 9),
      createdAt: DateTime(2026, 10, 5, 8));

  testWidgets('calendar loads posts active since the oldest viewed period',
      (tester) async {
    final requestedSince = <DateTime>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadCalendarPostsSince: (since) async {
        requestedSince.add(since);
        return [post];
      },
    ))));
    await tester.pumpAndSettle();
    expect(requestedSince, [DateTime(2026, 10, 1)]);

    // Earlier weeks inside the loaded month need no further history.
    await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, [DateTime(2026, 10, 1), DateTime(2026, 9, 1)]);

    // Returning to a period already covered needs no further history.
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the first load covers a week that starts in the previous month',
      (tester) async {
    final requestedSince = <DateTime>[];
    // Thursday 1 October 2026: the default week view starts on Monday 28 September.
    final firstOfMonth = DateTime(2026, 10, 1, 10);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => firstOfMonth,
      loadCalendarPostsSince: (since) async {
        requestedSince.add(since);
        return [post];
      },
    ))));
    await tester.pumpAndSettle();
    expect(requestedSince, [DateTime(2026, 9, 28)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching from week to month view widens the history window',
      (tester) async {
    final requestedSince = <DateTime>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadCalendarPostsSince: (since) async {
        requestedSince.add(since);
        return [post];
      },
    ))));
    await tester.pumpAndSettle();
    // Back three weeks: the week of 28 September starts before October.
    for (var week = 0; week < 3; week += 1) {
      await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
      await tester.pumpAndSettle();
    }
    expect(requestedSince, [DateTime(2026, 10, 1), DateTime(2026, 9, 28)]);

    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    expect(requestedSince,
        [DateTime(2026, 10, 1), DateTime(2026, 9, 28), DateTime(2026, 9, 1)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a complete-history loader is not asked again when browsing back',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async {
        loads += 1;
        return [post];
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    for (var month = 0; month < 2; month += 1) {
      await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
      await tester.pumpAndSettle();
    }
    expect(loads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
