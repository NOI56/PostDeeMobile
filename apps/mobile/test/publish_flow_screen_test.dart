import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';

void main() {
  testWidgets('shows posting progress and an honest queued screen',
      (tester) async {
    final operation = Completer<QueuedPostResult?>();

    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
          ],
          isScheduled: false,
          publish: () => operation.future,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('publish-flow-posting')),
      findsOneWidget,
    );
    expect(find.text('กำลังส่งเข้าคิว...'), findsOneWidget);
    expect(find.text('กำลังเตรียมโพสต์สำหรับ 2 ช่องทาง'), findsOneWidget);

    operation.complete(
      const QueuedPostResult(
        id: 'post-1',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        status: 'QUEUED',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
    expect(find.text('ส่งเข้าคิวแล้ว'), findsOneWidget);
    expect(
      find.text('ระบบรับโพสต์ 2 ช่องทางแล้ว กำลังเผยแพร่'),
      findsOneWidget,
    );
    expect(find.text('โพสต์สำเร็จ!'), findsNothing);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('YouTube Shorts'), findsOneWidget);
    expect(find.text('เสร็จสิ้น'), findsOneWidget);
    expect(find.text('ดูสถิติโพสต์'), findsOneWidget);
  });
}
