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
    expect(find.text('รอส่งตามเวลา · 18:30'), findsOneWidget);
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

  testWidgets('shows busy feedback while a reschedule is being saved',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final pendingReschedule = Completer<ScheduledPostResult>();
    final post = ScheduledPostResult(
      id: 'busy-reschedule',
      caption: 'โพสต์ที่กำลังเลื่อนเวลา',
      videoS3Key: 'uploads/busy-reschedule.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [post],
            reschedulePost: (_, __) => pendingReschedule.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsOneWidget,
    );
    expect(find.text('กำลังเลื่อนเวลา...'), findsOneWidget);

    pendingReschedule.complete(post);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsNothing,
    );
  });

  testWidgets('shows busy feedback while a cancellation is being saved',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final pendingCancel = Completer<void>();
    final post = ScheduledPostResult(
      id: 'busy-cancel',
      caption: 'โพสต์ที่กำลังยกเลิก',
      videoS3Key: 'uploads/busy-cancel.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2)),
      status: 'QUEUED',
      createdAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [post],
            cancelPost: (_) => pendingCancel.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('calendar-post-action-progress')),
      findsOneWidget,
    );
    expect(find.text('กำลังยกเลิก...'), findsOneWidget);

    pendingCancel.complete();
    await tester.pumpAndSettle();
    expect(find.text(post.caption), findsNothing);
  });

  testWidgets('queues a fresh load after rescheduling during a stale refresh',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    late ScheduledPostResult updatedPost;
    final originalPost = ScheduledPostResult(
      id: 'reschedule-during-refresh',
      caption: 'โพสต์ก่อนเลื่อนเวลา',
      videoS3Key: 'uploads/reschedule-during-refresh.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return switch (loadCalls) {
        1 => Future.value([originalPost]),
        2 => staleRefresh.future,
        _ => Future.value([updatedPost]),
      };
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              reschedulePost: (postId, next) async {
                updatedPost = ScheduledPostResult(
                  id: postId,
                  caption: 'โพสต์หลังเลื่อนเวลา',
                  videoS3Key: originalPost.videoS3Key,
                  platforms: originalPost.platforms,
                  scheduledAt: next,
                  status: 'QUEUED',
                  createdAt: originalPost.createdAt,
                );
                return updatedPost;
              },
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(originalPost.caption));
    await tester.tap(find.text(originalPost.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();

    staleRefresh.complete([originalPost]);
    await tester.pumpAndSettle();

    expect(loadCalls, 3);
    expect(find.text('โพสต์หลังเลื่อนเวลา'), findsOneWidget);
    expect(find.text(originalPost.caption), findsNothing);
  });

  testWidgets('keeps the local reschedule when the queued reload fails',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    final originalPost = ScheduledPostResult(
      id: 'reschedule-reload-failure',
      caption: 'โพสต์ก่อนเลื่อนและรีโหลดล้มเหลว',
      videoS3Key: 'uploads/reschedule-reload-failure.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2, hours: 7)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return switch (loadCalls) {
        1 => Future.value([originalPost]),
        2 => staleRefresh.future,
        _ => Future.error(StateError('queued reload failed')),
      };
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              reschedulePost: (postId, next) async => ScheduledPostResult(
                id: postId,
                caption: 'โพสต์หลังเลื่อนจากผลตอบกลับ',
                videoS3Key: originalPost.videoS3Key,
                platforms: originalPost.platforms,
                scheduledAt: next,
                status: 'QUEUED',
                createdAt: originalPost.createdAt,
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(originalPost.caption));
    await tester.tap(find.text(originalPost.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pump();

    staleRefresh.complete([originalPost]);
    await tester.pumpAndSettle();

    expect(loadCalls, 3);
    expect(find.text('โพสต์หลังเลื่อนจากผลตอบกลับ'), findsOneWidget);
    expect(find.text(originalPost.caption), findsNothing);
  });

  testWidgets('a stale refresh cannot restore a canceled post', (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    final staleRefresh = Completer<List<ScheduledPostResult>>();
    var loadCalls = 0;
    final post = ScheduledPostResult(
      id: 'cancel-during-refresh',
      caption: 'โพสต์ที่ยกเลิกระหว่างรีเฟรช',
      videoS3Key: 'uploads/cancel-during-refresh.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: now.add(const Duration(days: 2)),
      status: 'QUEUED',
      createdAt: now,
    );

    Future<List<ScheduledPostResult>> loadPosts() {
      loadCalls += 1;
      return loadCalls == 1 ? Future.value([post]) : staleRefresh.future;
    }

    Widget app(int refreshToken) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CalendarScreen(
              refreshToken: refreshToken,
              now: () => now,
              loadScheduledPosts: loadPosts,
              cancelPost: (_) async {},
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(1));
    await tester.pump();

    await tester.ensureVisible(find.text(post.caption));
    await tester.tap(find.text(post.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pumpAndSettle();
    expect(find.text(post.caption), findsNothing);

    staleRefresh.complete([post]);
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.text(post.caption), findsNothing);
  });

  for (final width in const [360.0, 393.0]) {
    for (final textScale in const [1.45, 2.0]) {
      testWidgets('calendar controls fit ${width}dp with ${textScale}x text',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: MediaQueryData.fromView(tester.view).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: CalendarScreen(
                  now: () => DateTime(2026, 2, 14),
                  loadScheduledPosts: () async => const [],
                  onAddPost: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final monthButton = find.ancestor(
          of: find.byIcon(Icons.chevron_left),
          matching: find.byType(InkWell),
        );
        final filter = find.ancestor(
          of: find.text('ทั้งหมด'),
          matching: find.byType(InkWell),
        );
        final addButton = find.ancestor(
          of: find.byIcon(Icons.add_rounded),
          matching: find.byType(InkWell),
        );
        final selectedDay = find.ancestor(
          of: find.text('14'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(monthButton).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(filter).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(addButton).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(selectedDay).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(selectedDay).height, greaterThanOrEqualTo(48));
      });
    }
  }

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

  testWidgets('limits the reschedule date picker to the shared 30-day window',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'bounded-reschedule',
                caption: 'โพสต์ภายในกรอบเวลา',
                videoS3Key: 'uploads/bounded.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: now.add(const Duration(days: 2)),
                status: 'QUEUED',
                createdAt: now,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ภายในกรอบเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ภายในกรอบเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();

    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, DateTime(2026, 8, 11));
    expect(picker.lastDate, DateTime(2026, 9, 10));
  });

  testWidgets('blocks a past reschedule before it reaches the API',
      (tester) async {
    final now = DateTime(2026, 8, 11, 12);
    var rescheduleCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            now: () => now,
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'past-reschedule',
                caption: 'โพสต์ที่ห้ามเลื่อนไปอดีต',
                videoS3Key: 'uploads/past.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: now.subtract(const Duration(hours: 1)),
                status: 'QUEUED',
                createdAt: now.subtract(const Duration(days: 1)),
              ),
            ],
            reschedulePost: (postId, next) async {
              rescheduleCalls += 1;
              return ScheduledPostResult(
                id: postId,
                caption: 'ไม่ควรถูกเรียก',
                videoS3Key: 'uploads/past.mp4',
                platforms: const ['YOUTUBE_SHORTS'],
                scheduledAt: next,
                status: 'QUEUED',
                createdAt: now,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โพสต์ที่ห้ามเลื่อนไปอดีต'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์ที่ห้ามเลื่อนไปอดีต'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(rescheduleCalls, 0);
    expect(find.text('เวลาที่เลื่อนต้องเป็นเวลาในอนาคต'), findsOneWidget);
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
    expect(find.text('ส่งสำเร็จ · 01:30'), findsOneWidget);
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

    expect(find.text('ส่งสำเร็จบางช่องทาง · 09:05'), findsOneWidget);
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

  testWidgets('shows an unknown provider outcome as unconfirmed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CalendarScreen(
            loadScheduledPosts: () async => [
              ScheduledPostResult(
                id: 'unknown-outcome',
                caption: 'Future provider result',
                videoS3Key: 'uploads/future.mp4',
                platforms: const ['TIKTOK'],
                scheduledAt: DateTime(2026, 6, 10, 9),
                publishedAt: DateTime(2026, 6, 10, 9, 5),
                status: 'PUBLISHED',
                createdAt: DateTime(2026, 6, 1),
                platformResults: const [
                  PostPlatformResult(
                    postId: 'unknown-outcome',
                    platform: 'TIKTOK',
                    status: 'PUBLISHED',
                    deliveryOutcome: 'FUTURE_OUTCOME',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผลยังไม่ยืนยัน · 09:05'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ · 09:05'), findsNothing);
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
    expect(find.text('กำลังส่ง · 10:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(loadCount, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(loadCount, 3);
    expect(find.text('ส่งสำเร็จ · 10:01'), findsOneWidget);
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
