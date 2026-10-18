import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
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
  _FakePostApiClient({this.publishNowError, this.operationGate});

  final ApiException? publishNowError;
  final Future<void>? operationGate;
  final List<String> cancelledPostIds = [];
  final List<String> publishedNowPostIds = [];

  @override
  Future<void> cancelPost(String postId) async {
    cancelledPostIds.add(postId);
    await operationGate;
  }

  @override
  Future<void> publishPostNow(String postId) async {
    publishedNowPostIds.add(postId);
    await operationGate;
    final error = publishNowError;
    if (error != null) {
      throw error;
    }
  }
}

void main() {
  testWidgets(
      'sending detail animates while preserving each real channel result',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PostDetailScreen(
        post: _post(status: 'PUBLISHING', platforms: const [
          'TIKTOK',
          'YOUTUBE_SHORTS',
          'INSTAGRAM_REELS',
          'FACEBOOK_REELS',
        ], platformResults: const [
          PostPlatformResult(
              postId: 'post-1',
              platform: 'TIKTOK',
              status: 'PUBLISHED',
              deliveryOutcome: 'DRAFT'),
          PostPlatformResult(
              postId: 'post-1',
              platform: 'YOUTUBE_SHORTS',
              status: 'PUBLISHING'),
          PostPlatformResult(
              postId: 'post-1', platform: 'INSTAGRAM_REELS', status: 'FAILED'),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsOneWidget);
    expect(find.text('กำลังส่ง'), findsNWidgets(2));
    expect(find.text('ส่งเป็นร่างแล้ว'), findsOneWidget);
    expect(find.text('ส่งไม่สำเร็จ'), findsOneWidget);
    expect(find.text('รอผล'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion sending detail stays readable without a ticker',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: PostDetailScreen(post: _post(status: 'PUBLISHING')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsOneWidget);
    expect(find.text('กำลังส่ง'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing channel result never inherits another channel success',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
      post: _post(status: 'PUBLISHED', platformResults: const [
        PostPlatformResult(
            postId: 'post-1',
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            deliveryOutcome: 'DRAFT'),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('รอผล'), findsOneWidget);
    expect(find.text('เผยแพร่สำเร็จ'), findsNothing);
    expect(find.text('ส่งเป็นร่างแล้ว'), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'failed channel result takes priority over a stale delivery receipt',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
      post: _post(status: 'FAILED', platforms: const [
        'TIKTOK'
      ], platformResults: const [
        PostPlatformResult(
            postId: 'post-1',
            platform: 'TIKTOK',
            status: 'FAILED',
            deliveryOutcome: 'LIVE'),
      ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('ส่งไม่สำเร็จ'), findsNWidgets(2));
    expect(find.text('เผยแพร่แล้ว'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-open-analytics')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('sending channel ignores a stale live receipt until confirmed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: PostDetailScreen(
        post: _post(status: 'PUBLISHING', platforms: const [
          'TIKTOK'
        ], platformResults: const [
          PostPlatformResult(
              postId: 'post-1',
              platform: 'TIKTOK',
              status: 'PUBLISHING',
              deliveryOutcome: 'LIVE'),
        ]),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('กำลังส่ง'), findsNWidgets(2));
    expect(find.text('เผยแพร่แล้ว'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-detail-open-analytics')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final outcome in const [
    'DRAFT',
    'PRIVATE',
    'UNLISTED',
    'LIVE',
    'FUTURE'
  ]) {
    testWidgets('terminal $outcome detail never replays sending motion',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: PostDetailScreen(
        post: _post(status: 'PUBLISHED', platforms: const [
          'TIKTOK'
        ], platformResults: [
          PostPlatformResult(
              postId: 'post-1',
              platform: 'TIKTOK',
              status: 'PUBLISHED',
              deliveryOutcome: outcome),
        ]),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
          findsNothing);
      expect(find.text('กำลังส่ง'), findsNothing);
      expect(
          find.text(switch (outcome) {
            'DRAFT' => 'ส่งเป็นร่างแล้ว',
            'PRIVATE' => 'ส่วนตัว',
            'UNLISTED' => 'ไม่แสดงในรายการ',
            'LIVE' => 'เผยแพร่แล้ว',
            _ => 'ผลยังไม่ยืนยัน',
          }),
          findsWidgets);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'same-owner token refresh keeps details but UID change hides all private content and actions',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(AuthSession.authenticated(userId: 'owner-a', idToken: 'a'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
            post: _post(scheduledAt: DateTime(2026, 10, 10)),
            apiClient: _FakePostApiClient())));
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner-a', idToken: 'refreshed'));
    await tester.pumpAndSettle();
    expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsOneWidget);
    sessions.signIn(AuthSession.authenticated(userId: 'owner-b', idToken: 'b'));
    await tester.pumpAndSettle();
    expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsNothing);
    expect(find.byKey(const ValueKey('post-detail-publish-now')), findsNothing);
    expect(find.byKey(const ValueKey('post-detail-owner-changed')),
        findsOneWidget);
    sessions
        .signIn(AuthSession.authenticated(userId: 'owner-a', idToken: 'again'));
    await tester.pumpAndSettle();
    expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsNothing);
  });

  testWidgets(
      'owner transition during confirmation blocks the original publish command',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(AuthSession.authenticated(userId: 'owner-a', idToken: 'a'));
    final api = _FakePostApiClient();
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
            post: _post(scheduledAt: DateTime(2026, 10, 10)), apiClient: api)));
    await tester.tap(find.byKey(const ValueKey('post-detail-publish-now')));
    await tester.pumpAndSettle();
    sessions.signIn(AuthSession.authenticated(userId: 'owner-b', idToken: 'b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โพสต์เลย').last);
    await tester.pumpAndSettle();
    expect(api.publishedNowPostIds, isEmpty);
    expect(find.byKey(const ValueKey('post-detail-owner-changed')),
        findsOneWidget);
  });

  for (final cancel in [false, true]) {
    for (final fails in [false, true]) {
      testWidgets(
          'ignores late ${cancel ? 'cancel' : 'publish'} ${fails ? 'failure' : 'completion'} after the owner changed',
          (tester) async {
        final sessions = PostDeeAuthSessionStore.instance;
        final original = sessions.session;
        addTearDown(() => sessions.signIn(original));
        sessions
            .signIn(AuthSession.authenticated(userId: 'owner-a', idToken: 'a'));
        final gate = Completer<void>();
        final api = _FakePostApiClient(operationGate: gate.future);
        await tester.pumpWidget(MaterialApp(
            home: PostDetailScreen(
                post: _post(scheduledAt: DateTime(2026, 10, 10)),
                apiClient: api)));
        await tester.tap(cancel
            ? find.bySemanticsLabel('ยกเลิกโพสต์')
            : find.byKey(const ValueKey('post-detail-publish-now')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(cancel ? 'ยกเลิกโพสต์' : 'โพสต์เลย').last);
        await tester.pump();
        sessions
            .signIn(AuthSession.authenticated(userId: 'owner-b', idToken: 'b'));
        await tester.pump();
        if (fails) {
          gate.completeError(const ApiException('Operation failed'));
        } else {
          gate.complete();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('post-detail-owner-changed')),
            findsOneWidget);
        expect(find.text('โปรโมตครีมกันแดดตัวใหม่'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
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

  testWidgets('shows a specific Thai frame-rate rejection without retrying',
      (tester) async {
    final api = _FakePostApiClient();
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(
            apiClient: api,
            post: _post(
                status: 'FAILED',
                platforms: const ['TIKTOK'],
                platformResults: const [
                  PostPlatformResult(
                      postId: 'post-1',
                      platform: 'TIKTOK',
                      status: 'FAILED',
                      errorMessage:
                          'TikTok rejected this video because its frame rate validation failed. Export the video again before retrying.')
                ]))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'สาเหตุ: TikTok ตรวจสอบอัตราเฟรมของคลิปนี้ไม่ผ่าน กรุณาส่งออกวิดีโอใหม่ก่อนลองอีกครั้ง'),
        findsOneWidget);
    expect(find.textContaining('frame rate validation'), findsNothing);
    expect(api.publishedNowPostIds, isEmpty);
    expect(api.cancelledPostIds, isEmpty);
  });

  for (final error in const {
    'TikTok publishing options changed. Review the account and publishing settings before trying again.':
        'สิทธิ์หรือตัวเลือกการโพสต์ TikTok เปลี่ยนไป กรุณาเปิดการตั้งค่าช่องทางและทบทวนก่อนลองอีกครั้ง',
    'TikTok publishing options could not be checked. No video was sent to TikTok. Review the settings before trying again.':
        'ตรวจสอบสิทธิ์การโพสต์ TikTok ไม่ได้ ยังไม่ได้ส่งคลิปไปยัง TikTok กรุณาทบทวนการตั้งค่าแล้วลองใหม่',
  }.entries) {
    testWidgets('localizes safe TikTok capability error without retry: ${error.key}', (tester) async {
      final api = _FakePostApiClient();
      await tester.pumpWidget(MaterialApp(home: PostDetailScreen(
        apiClient: api,
        post: _post(status: 'FAILED', platforms: const ['TIKTOK'], platformResults: [
          PostPlatformResult(postId: 'post-1', platform: 'TIKTOK', status: 'FAILED', errorMessage: error.key),
        ]),
      )));
      await tester.pumpAndSettle();
      expect(find.text('สาเหตุ: ${error.value}'), findsOneWidget);
      expect(find.textContaining(error.key), findsNothing);
      expect(api.publishedNowPostIds, isEmpty);
      expect(api.cancelledPostIds, isEmpty);
      expect(find.byKey(const ValueKey('post-detail-publish-now')), findsNothing);
    });
  }

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
