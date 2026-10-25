import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';

const _coverKey = 'covers/owner/chosen-cover.jpg';
const _coverUrl = 'https://media.example.com/chosen-cover.jpg';

CalendarPostResult _queuedPost(DateTime now, String id) => CalendarPostResult(
      id: id,
      caption: 'Chosen cover clip',
      videoS3Key: 'uploads/owner/video.mp4',
      coverImageS3Key: _coverKey,
      platforms: const ['TIKTOK'],
      status: 'QUEUED',
      scheduledAt: now.add(const Duration(hours: 2)),
      createdAt: now,
    );

PostSummaryResult _coverPost(CalendarPostResult post) => PostSummaryResult(
      id: post.id,
      caption: post.caption,
      videoS3Key: post.videoS3Key,
      coverImageS3Key: _coverKey,
      coverImageUrl: Uri.parse(_coverUrl),
      platforms: post.platforms,
      status: post.status,
      scheduledAt: post.scheduledAt,
      createdAt: post.createdAt,
    );

Widget _host(CalendarScreen calendar) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: calendar),
    );

void main() {
  testWidgets(
      'keeps chosen cover after rescheduling when the follow-up calendar refresh fails',
      (tester) async {
    final now = DateTime(2026, 10, 21, 10);
    final queued = _queuedPost(now, 'rescheduled-cover');
    var listReads = 0;
    var coverReads = 0;
    var reschedules = 0;
    await tester.pumpWidget(_host(CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async {
        listReads++;
        if (listReads > 1) throw TimeoutException('Refresh offline');
        return [queued];
      },
      loadCoverPost: (_) async {
        coverReads++;
        return _coverPost(queued);
      },
      loadSubscription: () async => SubscriptionStatusResult(
        userId: 'calendar-user',
        plan: 'PRO',
        status: 'ACTIVE',
        canSchedule: true,
        canUseAiCaptions: false,
        canUseAnalytics: false,
      ),
      reschedulePost: (id, next) async {
        reschedules++;
        return ScheduledPostResult(
          id: id,
          caption: queued.caption,
          videoS3Key: queued.videoS3Key,
          platforms: queued.platforms,
          status: 'QUEUED',
          scheduledAt: next,
          createdAt: queued.createdAt,
        );
      },
    )));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('calendar-post-cover-image-${queued.id}')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text(queued.caption));
    await tester.tap(find.text(queued.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลื่อนเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('postdee-time-confirm')));
    await tester.pumpAndSettle();

    expect(reschedules, 1);
    expect(listReads, 2);
    expect(coverReads, greaterThanOrEqualTo(1));
    expect(
      find.byKey(ValueKey('calendar-post-cover-image-${queued.id}')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'keeps chosen cover metadata when an ambiguous cancellation reconciles a published post',
      (tester) async {
    final now = DateTime(2026, 10, 21, 10);
    final queued = _queuedPost(now, 'reconciled-cover');
    var cancellations = 0;
    var reconciliations = 0;
    CalendarPostResult? opened;
    await tester.pumpWidget(_host(CalendarScreen(
      now: () => now,
      loadCalendarPosts: () async => [queued],
      loadCoverPost: (_) async => _coverPost(queued),
      cancelPost: (_) async {
        cancellations++;
        throw TimeoutException('Cancellation response lost');
      },
      loadPost: (_) async {
        reconciliations++;
        return PostSummaryResult(
          id: queued.id,
          caption: queued.caption,
          videoS3Key: queued.videoS3Key,
          coverImageS3Key: _coverKey,
          platforms: queued.platforms,
          status: 'PUBLISHED',
          createdAt: queued.createdAt,
          scheduledAt: queued.scheduledAt,
          publishedAt: now,
        );
      },
      onOpenCalendarPostDetail: (post) => opened = post,
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(queued.caption));
    await tester.tap(find.text(queued.caption));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pumpAndSettle();
    expect(cancellations, 1);
    expect(reconciliations, 1);
    await tester.ensureVisible(find.text(queued.caption));
    await tester.tap(find.text(queued.caption));
    await tester.pump();

    expect(opened?.coverImageS3Key, _coverKey);
    expect(
      find.byKey(ValueKey('calendar-post-cover-image-${queued.id}')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
