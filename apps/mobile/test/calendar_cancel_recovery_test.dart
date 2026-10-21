import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/calendar/calendar_screen.dart';

void main() {
  for (final state in ['PUBLISHING', 'REMOVED']) {
    testWidgets(
        'calendar reconciles $state after an ambiguous cancellation without sending again',
        (tester) async {
      final now = DateTime(2026, 10, 21, 10);
      final queued = CalendarPostResult(
          id: 'cancel-race',
          caption: 'Queued race',
          videoS3Key: 'uploads/owner/video.mp4',
          platforms: const ['TIKTOK'],
          status: 'QUEUED',
          scheduledAt: now.add(const Duration(hours: 2)),
          createdAt: now);
      var cancels = 0;
      var reads = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CalendarScreen(
        now: () => now,
        loadCalendarPosts: () async => [queued],
        cancelPost: (_) async {
          cancels++;
          throw TimeoutException('Response lost');
        },
        loadPost: (_) async {
          reads++;
          return state == 'REMOVED'
              ? null
              : PostSummaryResult(
                  id: queued.id,
                  caption: queued.caption,
                  videoS3Key: queued.videoS3Key,
                  platforms: queued.platforms,
                  status: 'PUBLISHING',
                  scheduledAt: queued.scheduledAt,
                  createdAt: now);
        },
      ))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(queued.caption));
      await tester.tap(find.text(queued.caption));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิกโพสต์').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิกโพสต์').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(reads, 1);
      expect(cancels, 1);
      if (state == 'REMOVED') {
        expect(find.text(queued.caption), findsNothing);
        expect(
            find.textContaining('ไม่พบโพสต์นี้ในรายการแล้ว'), findsOneWidget);
      } else {
        expect(find.textContaining('โพสต์เริ่มส่งแล้ว'), findsOneWidget);
        expect(find.text('กำลังส่ง'), findsWidgets);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
