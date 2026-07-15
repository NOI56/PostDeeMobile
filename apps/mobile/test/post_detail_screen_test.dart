import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';

PostSummaryResult _post({
  String status = 'QUEUED',
  DateTime? scheduledAt,
  DateTime? publishedAt,
  List<String> platforms = const ['TIKTOK', 'YOUTUBE_SHORTS'],
  List<PostPlatformResult> platformResults = const [],
}) {
  return PostSummaryResult(
    id: 'post-1',
    caption: 'โปรโมตครีมกันแดดตัวใหม่',
    videoS3Key: 'uploads/clip.mp4',
    platforms: platforms,
    status: status,
    createdAt: DateTime(2026, 7, 1, 10),
    scheduledAt: scheduledAt,
    publishedAt: publishedAt,
    platformResults: platformResults,
  );
}

class _FakePostApiClient extends PostDeeApiClient {
  final List<String> cancelledPostIds = [];
  final List<(String, DateTime)> rescheduled = [];

  @override
  Future<void> cancelPost(String postId) async {
    cancelledPostIds.add(postId);
  }

  @override
  Future<ScheduledPostResult> reschedulePost(
    String postId,
    DateTime scheduledAt,
  ) async {
    rescheduled.add((postId, scheduledAt));
    return ScheduledPostResult(
      id: postId,
      caption: 'โปรโมตครีมกันแดดตัวใหม่',
      videoS3Key: 'uploads/clip.mp4',
      platforms: const ['TIKTOK'],
      scheduledAt: scheduledAt,
      status: 'QUEUED',
      createdAt: DateTime(2026, 7, 1, 10),
    );
  }
}

void main() {
  testWidgets('shows scheduled post details with honest actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(scheduledAt: DateTime(2026, 7, 10, 18, 30)),
          apiClient: _FakePostApiClient(),
        ),
      ),
    );

    expect(find.text('รายละเอียดโพสต์'), findsOneWidget);
    expect(find.text('ตั้งเวลาไว้'), findsOneWidget);
    expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('YouTube Shorts'), findsOneWidget);
    expect(find.text('รอเผยแพร่ตามเวลา'), findsNWidgets(2));
    expect(
        find.byKey(const ValueKey('post-detail-publish-now')), findsOneWidget);
    expect(find.bySemanticsLabel('ยกเลิกโพสต์'), findsOneWidget);
  });

  testWidgets('publish now reschedules the post to the current time',
      (tester) async {
    final apiClient = _FakePostApiClient();
    bool? popResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popResult = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (context) => PostDetailScreen(
                        post: _post(
                          scheduledAt: DateTime(2026, 7, 10, 18, 30),
                        ),
                        apiClient: apiClient,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('post-detail-publish-now')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์เลย').last);
    await tester.pumpAndSettle();

    expect(apiClient.rescheduled, hasLength(1));
    expect(apiClient.rescheduled.single.$1, 'post-1');
    // Popped back with a "changed" result so the caller reloads its list.
    expect(popResult, isTrue);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('published post offers analytics instead of publish actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(
            status: 'PUBLISHED',
            publishedAt: DateTime(2026, 7, 2, 9),
          ),
          apiClient: _FakePostApiClient(),
        ),
      ),
    );

    expect(find.text('เผยแพร่แล้ว'), findsWidgets);
    expect(find.byKey(const ValueKey('post-detail-open-analytics')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('post-detail-publish-now')), findsNothing);
  });

  testWidgets('shows each platform result, failure reason, and real reference',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(
            status: 'PARTIAL_PUBLISHED',
            publishedAt: DateTime(2026, 7, 2, 9),
            platforms: const [
              'TIKTOK',
              'YOUTUBE_SHORTS',
              'INSTAGRAM_REELS',
            ],
            platformResults: const [
              PostPlatformResult(
                postId: 'post-1',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                externalPostId: 'https://tiktok.test/post-1',
              ),
              PostPlatformResult(
                postId: 'post-1',
                platform: 'YOUTUBE_SHORTS',
                status: 'FAILED',
                errorMessage:
                    'Publishing result could not be confirmed. Check the platform before trying again.',
              ),
              PostPlatformResult(
                postId: 'post-1',
                platform: 'INSTAGRAM_REELS',
                status: 'FAILED',
                errorMessage:
                    'Publishing to this platform failed. Please try again later.',
              ),
            ],
          ),
          apiClient: _FakePostApiClient(),
        ),
      ),
    );

    expect(find.text('สำเร็จบางช่องทาง'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsOneWidget);
    expect(
      find.text('ลิงก์โพสต์: https://tiktok.test/post-1'),
      findsOneWidget,
    );
    expect(find.text('โพสต์ไม่สำเร็จ'), findsWidgets);
    expect(
      find.text(
        'สาเหตุ: ยังยืนยันผลการโพสต์ไม่ได้ กรุณาตรวจสอบช่องทางนี้ก่อนลองใหม่ เพื่อป้องกันโพสต์ซ้ำ',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'สาเหตุ: โพสต์ไปยังช่องทางนี้ไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('post-detail-open-analytics')),
        findsOneWidget);
  });
}
