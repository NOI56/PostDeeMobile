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
          publish: (reportProgress) {
            reportProgress(
              const PublishFlowProgress(
                stage: PublishFlowStage.uploadingVideo,
                fraction: 0.55,
              ),
            );
            return operation.future;
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('publish-flow-posting')),
      findsOneWidget,
    );
    expect(find.text('กำลังอัปโหลดวิดีโอ'), findsOneWidget);
    expect(find.text('55% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);
    expect(find.text('กำลังดำเนินการสำหรับ 2 ช่องทาง'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('publish-flow-progress')),
          )
          .value,
      0.55,
    );

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
    expect(find.text('รับรายการแล้ว'), findsOneWidget);
    expect(
      find.text('ระบบรับรายการ 2 ช่องทางแล้ว กำลังส่ง'),
      findsOneWidget,
    );
    expect(find.text('โพสต์สำเร็จ!'), findsNothing);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('YouTube Shorts'), findsOneWidget);
    expect(find.text('เสร็จสิ้น'), findsOneWidget);
    expect(find.text('ดูสถิติโพสต์'), findsOneWidget);
  });

  for (final testCase in const [
    (
      status: 'PUBLISHING',
      title: 'กำลังส่ง',
      body: 'ระบบกำลังส่ง 1 ช่องทาง กรุณาตรวจผลอีกครั้งในหน้ารายการโพสต์',
    ),
    (
      status: 'PUBLISHED',
      title: 'ส่งสำเร็จ',
      body: 'ส่ง 1 ช่องทางสำเร็จแล้ว',
    ),
    (
      status: 'PARTIAL_PUBLISHED',
      title: 'ส่งสำเร็จบางช่องทาง',
      body:
          'ส่งสำเร็จเพียงบางช่องทาง กรุณาเปิดรายละเอียดเพื่อตรวจช่องทางที่ไม่สำเร็จ',
    ),
  ]) {
    testWidgets('shows truthful ${testCase.status} replay outcome',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PublishFlowScreen(
            platforms: const [SocialPlatform.youtubeShorts],
            isScheduled: false,
            publish: (_) async => QueuedPostResult(
              id: 'post-replay',
              videoS3Key: 'uploads/video.mp4',
              platforms: const ['YOUTUBE_SHORTS'],
              status: testCase.status,
              idempotentReplay: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(testCase.title), findsOneWidget);
      expect(find.text('พบรายการเดิม · ${testCase.body}'), findsOneWidget);
      expect(find.text('ส่งเข้าคิวแล้ว'), findsNothing);
    });
  }

  testWidgets('uses provider delivery outcomes on the done screen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [SocialPlatform.tiktok],
          isScheduled: false,
          publish: (_) async => const QueuedPostResult(
            id: 'post-draft',
            videoS3Key: 'uploads/video.mp4',
            platforms: ['TIKTOK'],
            status: 'PUBLISHED',
            platformResults: [
              PostPlatformResult(
                postId: 'post-draft',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('ส่งเป็นร่างแล้ว'), findsWidgets);
    expect(find.textContaining('ส่งออกจริงและใช้โควตาโพสต์'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsNothing);
  });

  testWidgets('reports mixed provider success and failure as partial',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [
            SocialPlatform.tiktok,
            SocialPlatform.youtubeShorts,
          ],
          isScheduled: false,
          publish: (_) async => const QueuedPostResult(
            id: 'post-partial',
            videoS3Key: 'uploads/video.mp4',
            platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
            status: 'PUBLISHED',
            platformResults: [
              PostPlatformResult(
                postId: 'post-partial',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT',
              ),
              PostPlatformResult(
                postId: 'post-partial',
                platform: 'YOUTUBE_SHORTS',
                status: 'FAILED',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('ส่งสำเร็จบางช่องทาง'), findsOneWidget);
    expect(find.textContaining('ส่งสำเร็จเพียงบางช่องทาง'), findsOneWidget);
    expect(find.textContaining('TikTok · ส่งเป็นร่างแล้ว'), findsOneWidget);
  });

  testWidgets('does not call an unknown provider outcome successful',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [SocialPlatform.tiktok],
          isScheduled: false,
          publish: (_) async => const QueuedPostResult(
            id: 'post-unknown',
            videoS3Key: 'uploads/video.mp4',
            platforms: ['TIKTOK'],
            status: 'PUBLISHED',
            platformResults: [
              PostPlatformResult(
                postId: 'post-unknown',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'FUTURE_OUTCOME',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('ผลยังไม่ยืนยัน'), findsOneWidget);
    expect(find.textContaining('ยังยืนยันรูปแบบปลายทางไม่ได้'), findsOneWidget);
    expect(find.text('ส่งสำเร็จ'), findsNothing);
  });

  testWidgets('renders reported stage progress without inventing byte progress',
      (tester) async {
    final operation = Completer<QueuedPostResult?>();
    late PublishProgressReporter reportProgress;

    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [SocialPlatform.tiktok],
          isScheduled: false,
          publish: (reporter) {
            reportProgress = reporter;
            return operation.future;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('กำลังเตรียมข้อมูล'), findsOneWidget);
    expect(find.text('5% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    reportProgress(
      const PublishFlowProgress(
        stage: PublishFlowStage.checkingPlan,
        fraction: 0.28,
      ),
    );
    await tester.pump();
    expect(find.text('กำลังตรวจสอบแพ็กเกจ'), findsOneWidget);
    expect(find.text('28% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    reportProgress(
      const PublishFlowProgress(
        stage: PublishFlowStage.creatingPost,
        fraction: 0.9,
      ),
    );
    await tester.pump();
    expect(find.text('กำลังสร้างคิวโพสต์'), findsOneWidget);
    expect(find.text('90% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    operation.complete(
      const QueuedPostResult(
        id: 'post-progress',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['TIKTOK'],
        status: 'QUEUED',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
  });

  testWidgets('shows a retryable error when the publish operation throws',
      (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [SocialPlatform.tiktok],
          isScheduled: false,
          publish: (reportProgress) async {
            attempts += 1;
            if (attempts == 1) {
              throw const ApiException('เครือข่ายไม่พร้อม');
            }
            reportProgress(
              const PublishFlowProgress(
                stage: PublishFlowStage.creatingPost,
                fraction: 0.9,
              ),
            );
            return const QueuedPostResult(
              id: 'post-retry',
              videoS3Key: 'uploads/video.mp4',
              platforms: ['TIKTOK'],
              status: 'QUEUED',
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('publish-flow-error')), findsOneWidget);
    expect(find.text('ส่งโพสต์ไม่สำเร็จ'), findsOneWidget);
    expect(find.text('เครือข่ายไม่พร้อม'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('publish-flow-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
  });

  testWidgets('blocks back while publishing and explains cancellation limits',
      (tester) async {
    final operation = Completer<QueuedPostResult?>();

    await tester.pumpWidget(
      MaterialApp(
        home: PublishFlowScreen(
          platforms: const [SocialPlatform.tiktok],
          isScheduled: false,
          publish: (_) => operation.future,
        ),
      ),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const ValueKey('publish-flow-posting')), findsOneWidget);
    expect(
      find.text('ยังยกเลิกไม่ได้ระหว่างส่งข้อมูล กรุณารอจนจบขั้นตอน'),
      findsOneWidget,
    );

    operation.complete(
      const QueuedPostResult(
        id: 'post-after-back',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['TIKTOK'],
        status: 'QUEUED',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('publish-flow-done')), findsOneWidget);
  });

  testWidgets('progress remains usable at 393dp with 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(393, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final operation = Completer<QueuedPostResult?>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: PublishFlowScreen(
              platforms: const [
                SocialPlatform.tiktok,
                SocialPlatform.youtubeShorts,
              ],
              isScheduled: false,
              publish: (_) => operation.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('5% · ความคืบหน้าตามขั้นตอน'), findsOneWidget);

    operation.complete(
      const QueuedPostResult(
        id: 'post-large-text',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['TIKTOK', 'YOUTUBE_SHORTS'],
        status: 'QUEUED',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
