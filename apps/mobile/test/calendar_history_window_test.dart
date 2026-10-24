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

  testWidgets(
      'calendar loads history back to 31 days before the oldest viewed period',
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
    // A post shown in October was created no earlier than 31 days before it.
    expect(requestedSince, [DateTime(2026, 8, 31)]);

    // Earlier weeks inside the loaded month need no further history.
    await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('calendar-month-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-previous-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, [DateTime(2026, 8, 31), DateTime(2026, 8, 1)]);

    // Returning to a period already covered needs no further history.
    await tester.tap(find.byKey(const ValueKey('calendar-next-period')));
    await tester.pumpAndSettle();
    expect(requestedSince, hasLength(2));
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
