import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';

void main() {
  testWidgets('loads scheduled posts into the calendar', (tester) async {
    final scheduledPosts = Completer<List<ScheduledPostResult>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () => scheduledPosts.future,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('calendar-loading')), findsOneWidget);

    scheduledPosts.complete([
      ScheduledPostResult(
        id: 'post-1',
        caption: 'Launch clip',
        videoS3Key: 'uploads/launch.mp4',
        platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
        scheduledAt: DateTime(2026, 6, 7, 18, 30),
        status: 'QUEUED',
        createdAt: DateTime(2026, 6, 1),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-loading')), findsNothing);
    // The first scheduled day is auto-selected, so its posts show below the
    // grid with the prototype's "status · time" line.
    expect(find.text('Launch clip'), findsOneWidget);
    expect(find.text('7 มิ.ย. 2026'), findsOneWidget);
    expect(find.text('ตั้งเวลา · 18:30'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-empty')), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-platform-filters')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.text('Shopee'), findsNothing);
    expect(find.text('Lazada'), findsNothing);
  });

  testWidgets('reloads scheduled posts when the refresh token changes',
      (tester) async {
    var loadCount = 0;
    var posts = <ScheduledPostResult>[];

    Future<List<ScheduledPostResult>> loadScheduledPosts() async {
      loadCount += 1;
      return posts;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            refreshToken: 0,
            loadScheduledPosts: loadScheduledPosts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.byKey(const ValueKey('calendar-empty')), findsOneWidget);

    posts = [
      ScheduledPostResult(
        id: 'post-2',
        caption: 'Fresh scheduled clip',
        videoS3Key: 'uploads/fresh.mp4',
        platforms: const ['INSTAGRAM_REELS'],
        scheduledAt: DateTime(2026, 6, 8, 11),
        status: 'QUEUED',
        createdAt: DateTime(2026, 6, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            refreshToken: 1,
            loadScheduledPosts: loadScheduledPosts,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(find.text('Fresh scheduled clip'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-empty')), findsNothing);
  });
}
