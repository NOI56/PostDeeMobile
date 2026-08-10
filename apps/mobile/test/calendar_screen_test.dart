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

  testWidgets('only shows actions supported by the scheduled-post API',
      (tester) async {
    var addPostCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'post-actions',
                caption: 'Scheduled actions clip',
                videoS3Key: 'uploads/actions.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: DateTime(2026, 6, 9, 19),
                status: 'QUEUED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
            onAddPost: () => addPostCalls += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Scheduled actions clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scheduled actions clip'));
    await tester.pumpAndSettle();

    expect(find.text('เลื่อนเวลา'), findsOneWidget);
    expect(find.text('ยกเลิกโพสต์'), findsOneWidget);
    expect(find.text('แก้ไขโพสต์'), findsNothing);
    expect(addPostCalls, 0);
  });

  testWidgets('explains when rescheduling is blocked by publishing config',
      (tester) async {
    final scheduledAt = DateTime.now().add(const Duration(days: 2));
    var rescheduleCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'disabled-reschedule',
                caption: 'โพสต์ที่ต้องการเลื่อนเวลา',
                videoS3Key: 'uploads/reschedule.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: scheduledAt,
                status: 'QUEUED',
                createdAt: DateTime.now(),
              ),
            ],
            reschedulePost: (postId, next) async {
              rescheduleCalls += 1;
              throw const ApiException(
                'Social publishing is temporarily unavailable. Please try again later.',
                statusCode: 503,
                code: socialPublishingUnavailableCode,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ที่ต้องการเลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ที่ต้องการเลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(rescheduleCalls, 1);
    expect(
      find.text('ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง'),
      findsOneWidget,
    );
  });

  testWidgets(
      'uses the real published time in Bangkok across a UTC day and month',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            toLocalTime: (value) => value.toUtc().add(const Duration(hours: 7)),
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'published-next-month',
                caption: 'Published after midnight',
                videoS3Key: 'uploads/published.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: DateTime.utc(2026, 1, 31, 16),
                publishedAt: DateTime.utc(2026, 1, 31, 18, 30),
                status: 'PUBLISHED',
                createdAt: DateTime.utc(2026, 1, 30),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 31 Jan 18:30 UTC is 1 Feb 01:30 in Asia/Bangkok.
    expect(find.text('1 ก.พ. 2026'), findsOneWidget);
    expect(find.text('เผยแพร่แล้ว · 01:30'), findsOneWidget);
    expect(find.text('Published after midnight'), findsOneWidget);
  });

  testWidgets('translates partial publish and hides queue-only actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'partial-post',
                caption: 'Published on one channel',
                videoS3Key: 'uploads/partial.mp4',
                platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
                scheduledAt: DateTime(2026, 6, 10, 9),
                publishedAt: DateTime(2026, 6, 10, 9, 5),
                status: 'PARTIAL_PUBLISHED',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เผยแพร่บางช่องทาง · 09:05'), findsOneWidget);
    // Only the month-navigation chevron remains; terminal post rows do not
    // show the queue-action chevron.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.ensureVisible(find.text('Published on one channel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Published on one channel'));
    await tester.pumpAndSettle();

    expect(find.text('เลื่อนเวลา'), findsNothing);
    expect(find.text('ยกเลิกโพสต์'), findsNothing);
  });

  for (final status in const [
    'PUBLISHED',
    'PARTIAL_PUBLISHED',
    'FAILED',
  ]) {
    testWidgets('$status opens post detail through the terminal-post callback',
        (tester) async {
      final post = ScheduledPostResult(
        id: 'terminal-$status',
        caption: 'Terminal $status clip',
        videoS3Key: 'uploads/terminal.mp4',
        platforms: const ['YOUTUBE_SHORTS'],
        scheduledAt: DateTime(2026, 6, 12, 10),
        publishedAt: status == 'FAILED' ? null : DateTime(2026, 6, 12, 10, 1),
        status: status,
        createdAt: DateTime(2026, 6, 1),
      );
      ScheduledPostResult? openedPost;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              loadScheduledPosts: () async => [post],
              onOpenPostDetail: (value) => openedPost = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(post.caption));
      await tester.tap(find.text(post.caption));
      await tester.pumpAndSettle();

      expect(openedPost, same(post));
      expect(find.text('เลื่อนเวลา'), findsNothing);
      expect(find.text('ยกเลิกโพสต์'), findsNothing);
    });
  }

  testWidgets('publishing post remains non-interactive', (tester) async {
    var detailCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'publishing-post',
                caption: 'Publishing clip',
                videoS3Key: 'uploads/publishing.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: DateTime(2026, 6, 12, 10),
                status: 'PUBLISHING',
                createdAt: DateTime(2026, 6, 1),
              ),
            ],
            onOpenPostDetail: (_) => detailCalls += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Publishing clip'));
    await tester.tap(find.text('Publishing clip'));
    await tester.pump();

    expect(detailCalls, 0);
    expect(find.text('เลื่อนเวลา'), findsNothing);
    expect(find.text('ยกเลิกโพสต์'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('refreshes queued and publishing posts every 30 seconds',
      (tester) async {
    var loadCount = 0;

    Future<List<ScheduledPostResult>> loadScheduledPosts() async {
      loadCount += 1;
      return [
        ScheduledPostResult(
          id: 'polling-post',
          caption: 'Polling clip',
          videoS3Key: 'uploads/polling.mp4',
          platforms: const ['YOUTUBE_SHORTS'],
          scheduledAt: DateTime(2026, 6, 11, 10),
          publishedAt: loadCount < 3 ? null : DateTime(2026, 6, 11, 10, 1),
          status: switch (loadCount) {
            1 => 'QUEUED',
            2 => 'PUBLISHING',
            _ => 'PUBLISHED',
          },
          createdAt: DateTime(2026, 6, 1),
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(loadScheduledPosts: loadScheduledPosts),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 2);
    expect(find.text('กำลังโพสต์ · 10:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 3);
    expect(find.text('เผยแพร่แล้ว · 10:01'), findsOneWidget);
  });

  testWidgets('refreshes after the app resumes', (tester) async {
    var loadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async {
              loadCount += 1;
              return const [];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(loadCount, 2);
  });

  testWidgets('refreshes when returning to the calendar tab', (tester) async {
    var loadCount = 0;
    var selectedIndex = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return Scaffold(
              body: IndexedStack(
                index: selectedIndex,
                children: [
                  CalendarScreen(
                    isActive: selectedIndex == 0,
                    loadScheduledPosts: () async {
                      loadCount += 1;
                      return const [];
                    },
                  ),
                  const SizedBox(key: ValueKey('another-tab')),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loadCount, 1);

    setHostState(() => selectedIndex = 1);
    await tester.pump();
    await tester.pump();
    expect(loadCount, 1);

    setHostState(() => selectedIndex = 0);
    await tester.pump();
    await tester.pump();

    expect(loadCount, 2);
  });
}
