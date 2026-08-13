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
  _FakePostApiClient({this.publishNowError});

  final ApiException? publishNowError;
  final List<String> cancelledPostIds = [];
  final List<String> publishedNowPostIds = [];

  @override
  Future<void> cancelPost(String postId) async {
    cancelledPostIds.add(postId);
  }

  @override
  Future<void> publishPostNow(String postId) async {
    publishedNowPostIds.add(postId);
    final error = publishNowError;
    if (error != null) {
      throw error;
    }
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
    expect(find.text('รอส่งตามเวลา'), findsWidgets);
    expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('YouTube Shorts'), findsOneWidget);
    expect(find.text('รอส่งตามเวลา'), findsWidgets);
    expect(
        find.byKey(const ValueKey('post-detail-publish-now')), findsOneWidget);
    expect(find.bySemanticsLabel('ยกเลิกโพสต์'), findsOneWidget);
  });

  testWidgets('publish now uses the dedicated publish command', (tester) async {
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

    expect(apiClient.publishedNowPostIds, ['post-1']);
    // Popped back with a "changed" result so the caller reloads its list.
    expect(popResult, isTrue);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('publish now explains when publishing is disabled',
      (tester) async {
    final apiClient = _FakePostApiClient(
      publishNowError: const ApiException(
        'Social publishing is temporarily unavailable. Please try again later.',
        statusCode: 503,
        code: socialPublishingUnavailableCode,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(scheduledAt: DateTime(2026, 7, 10, 18, 30)),
          apiClient: apiClient,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('post-detail-publish-now')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์เลย').last);
    await tester.pumpAndSettle();

    expect(apiClient.publishedNowPostIds, ['post-1']);
    expect(
      find.text('ระบบรับงานโพสต์ยังไม่เปิดใช้งาน กรุณาลองใหม่ภายหลัง'),
      findsOneWidget,
    );
    expect(find.text('โพสต์เลยไม่สำเร็จ ลองใหม่อีกครั้ง'), findsNothing);
  });

  for (final errorCase in [
    (
      code: scheduledPostNotFoundCode,
      message: 'ไม่พบโพสต์ที่ตั้งเวลาไว้ กรุณากลับไปตรวจสอบรายการโพสต์',
    ),
    (
      code: publishQueueUnavailableCode,
      message: 'ระบบคิวโพสต์ยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
    ),
  ]) {
    testWidgets('publish now explains ${errorCase.code}', (tester) async {
      final apiClient = _FakePostApiClient(
        publishNowError: ApiException(
          'Publish now failed',
          statusCode: 503,
          code: errorCase.code,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PostDetailScreen(
            post: _post(scheduledAt: DateTime(2026, 7, 10, 18, 30)),
            apiClient: apiClient,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('post-detail-publish-now')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('โพสต์เลย').last);
      await tester.pumpAndSettle();

      expect(apiClient.publishedNowPostIds, ['post-1']);
      expect(find.text(errorCase.message), findsOneWidget);
    });
  }

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

  testWidgets('shows provider draft delivery without calling it published',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(
            status: 'PUBLISHED',
            publishedAt: DateTime(2026, 7, 2, 9),
            platforms: const ['TIKTOK'],
            platformResults: const [
              PostPlatformResult(
                postId: 'post-1',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT',
              ),
            ],
          ),
          apiClient: _FakePostApiClient(),
        ),
      ),
    );

    expect(find.text('ส่งเป็นร่างแล้ว'), findsWidgets);
    expect(find.text('เผยแพร่สำเร็จ'), findsNothing);
    expect(
      find.byKey(const ValueKey('post-detail-open-analytics')),
      findsNothing,
    );
  });

  testWidgets('keeps an unknown provider outcome neutral and non-actionable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          post: _post(
            status: 'PUBLISHED',
            publishedAt: DateTime(2026, 7, 2, 9),
            platforms: const ['TIKTOK'],
            platformResults: const [
              PostPlatformResult(
                postId: 'post-1',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'FUTURE_OUTCOME',
                externalPostId: 'https://tiktok.test/unknown',
              ),
            ],
          ),
          apiClient: _FakePostApiClient(),
        ),
      ),
    );

    expect(find.text('ผลยังไม่ยืนยัน'), findsWidgets);
    expect(find.textContaining('tiktok.test/unknown'), findsNothing);
    expect(
      find.byKey(const ValueKey('post-detail-open-analytics')),
      findsNothing,
    );
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

    expect(find.text('ส่งสำเร็จบางช่องทาง'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsOneWidget);
    expect(
      find.text('ลิงก์โพสต์: https://tiktok.test/post-1'),
      findsOneWidget,
    );
    expect(find.text('ส่งไม่สำเร็จ'), findsWidgets);
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
