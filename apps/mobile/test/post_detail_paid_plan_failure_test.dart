import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';

const _paidPlanReason =
    'สาเหตุ: แพ็กเกจหมดอายุก่อนถึงเวลาโพสต์ จึงยังไม่ได้ส่งโพสต์นี้ ต่ออายุแพ็กเกจ Starter หรือ Pro แล้วสร้างโพสต์ใหม่';

PostSummaryResult _failedPost(List<PostPlatformResult> results) =>
    PostSummaryResult(
      id: 'post-plan',
      caption: 'โพสต์ที่ตั้งเวลาไว้',
      videoS3Key: 'uploads/clip.mp4',
      platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
      status: 'FAILED',
      createdAt: DateTime(2026, 10, 1, 10),
      scheduledAt: DateTime(2026, 10, 20, 9),
      platformResults: results,
    );

void main() {
  testWidgets(
      'explains in Thai that an expired plan stopped a scheduled post, without channel review',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
      refreshOnOpen: false,
      post: _failedPost(const [
        PostPlatformResult(
            postId: 'post-plan',
            platform: 'TIKTOK',
            status: 'FAILED',
            errorMessage: 'PAID_PLAN_REQUIRED'),
        PostPlatformResult(
            postId: 'post-plan',
            platform: 'YOUTUBE_SHORTS',
            status: 'FAILED',
            errorMessage: 'PAID_PLAN_REQUIRED'),
      ]),
    )));
    await tester.pumpAndSettle();

    expect(find.text(_paidPlanReason), findsNWidgets(2));
    expect(find.textContaining('PAID_PLAN_REQUIRED'), findsNothing);
    // Reviewing the account connection cannot fix an expired plan.
    expect(find.byKey(const ValueKey('post-detail-review-TIKTOK')), findsNothing);
    expect(find.byKey(const ValueKey('post-detail-review-YOUTUBE_SHORTS')),
        findsNothing);
  });

  testWidgets('keeps channel review for other platform failures',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
      refreshOnOpen: false,
      post: _failedPost(const [
        PostPlatformResult(
            postId: 'post-plan',
            platform: 'TIKTOK',
            status: 'FAILED',
            errorMessage:
                'Publishing to this platform failed. Please try again later.'),
      ]),
    )));
    await tester.pumpAndSettle();

    expect(find.text(_paidPlanReason), findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-review-TIKTOK')), findsOneWidget);
  });
}
