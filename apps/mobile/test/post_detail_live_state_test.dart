import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';

PostSummaryResult _post(String status,
        {String caption = 'Original owned clip',
        List<PostPlatformResult> results = const []}) =>
    PostSummaryResult(
        id: 'live-post',
        caption: caption,
        videoS3Key: 'uploads/owner/clip/video.mp4',
        platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
        status: status,
        createdAt: DateTime(2026, 10, 21),
        scheduledAt: status == 'QUEUED' ? DateTime(2026, 10, 22) : null,
        platformResults: results);

class _ReadClient extends PostDeeApiClient {
  _ReadClient(this.latest);
  PostSummaryResult? latest;
  Future<PostSummaryResult?>? gate;
  Object? readError;
  Object? cancelError;
  int reads = 0;
  int writes = 0;
  @override
  Future<PostSummaryResult?> getPostById(String postId,
      {bool includeMedia = false}) async {
    reads++;
    if (readError != null) throw readError!;
    if (gate != null) return await gate!;
    return latest;
  }

  @override
  Future<void> cancelPost(String postId) async {
    writes++;
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> publishPostNow(String postId) async {
    writes++;
  }
}

void main() {
  final sessions = PostDeeAuthSessionStore.instance;
  late AuthSession original;
  setUp(() {
    original = sessions.session;
    sessions.signIn(
        AuthSession.authenticated(userId: 'owner', idToken: 'owner-token'));
  });
  tearDown(() {
    sessions.signIn(original);
  });

  testWidgets('loads the owned current result without repeating publication',
      (tester) async {
    final api = _ReadClient(_post('PUBLISHED'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHING'), apiClient: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.reads, 1);
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsNothing);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets('polls pending visible details and stops after a terminal result',
      (tester) async {
    final api = _ReadClient(_post('PUBLISHING'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHING'), apiClient: api)));
    await tester.pump();
    expect(api.reads, 1);
    api.latest = _post('PUBLISHED');
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(api.reads, 2);
    expect(find.byKey(const ValueKey('post-detail-publishing-rail')),
        findsNothing);
    await tester.pump(const Duration(seconds: 60));
    expect(api.reads, 2);
    expect(api.writes, 0);
  });

  testWidgets(
      'background stops detail polling and resume checks the current state',
      (tester) async {
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final api = _ReadClient(_post('PUBLISHING'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHING'), apiClient: api)));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(api.reads, 1);
    api.latest = _post('PUBLISHED');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.reads, 2);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
  });

  testWidgets('late detail reads cannot reveal the previous owners result',
      (tester) async {
    final gate = Completer<PostSummaryResult?>();
    final api = _ReadClient(_post('PUBLISHING'))..gate = gate.future;
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHING'), apiClient: api)));
    await tester.pump();
    sessions.signIn(
        AuthSession.authenticated(userId: 'other', idToken: 'other-token'));
    gate.complete(_post('PUBLISHED', caption: 'Late private caption'));
    await tester.pumpAndSettle();
    expect(find.text('Late private caption'), findsNothing);
    expect(find.text('Original owned clip'), findsNothing);
    expect(api.writes, 0);
  });

  testWidgets(
      'covered details do not poll and check again when their route returns',
      (tester) async {
    final api = _ReadClient(_post('PUBLISHING'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHING'), apiClient: api)));
    await tester.pump();
    final navigator =
        Navigator.of(tester.element(find.byType(PostDetailScreen)));
    unawaited(navigator.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Covered')))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(api.reads, 1);
    api.latest = _post('PUBLISHED');
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.reads, 2);
    expect(find.text('เผยแพร่แล้ว'), findsOneWidget);
  });

  testWidgets(
      'failed refresh keeps the old result with an explicit stale notice',
      (tester) async {
    final api = _ReadClient(_post('PUBLISHED'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('PUBLISHED'), apiClient: api)));
    await tester.pumpAndSettle();
    api.readError = const ApiException('Offline');
    await tester.tap(find.byKey(const ValueKey('post-detail-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Original owned clip'), findsOneWidget);
    expect(find.textContaining('กำลังแสดงข้อมูลเดิม'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets(
      'missing media uses an honest unavailable preview without a play affordance',
      (tester) async {
    final api = _ReadClient(_post('FAILED'));
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('FAILED'), apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-detail-preview-unavailable')),
        findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets(
      'failed-channel review offers instructions without sending any channel again',
      (tester) async {
    final post = _post('PARTIAL_PUBLISHED', results: const [
      PostPlatformResult(
          postId: 'live-post',
          platform: 'TIKTOK',
          status: 'FAILED',
          errorMessage: 'Review settings'),
      PostPlatformResult(
          postId: 'live-post',
          platform: 'YOUTUBE_SHORTS',
          status: 'PUBLISHED',
          deliveryOutcome: 'PRIVATE'),
    ]);
    final api = _ReadClient(post);
    await tester.pumpWidget(
        MaterialApp(home: PostDetailScreen(post: post, apiClient: api)));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('post-detail-review-TIKTOK')));
    await tester.tap(find.byKey(const ValueKey('post-detail-review-TIKTOK')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตรวจสอบช่องทางก่อนสร้างโพสต์ใหม่'),
        findsOneWidget);
    expect(find.textContaining('ช่องทางที่ส่งสำเร็จแล้วจะไม่ถูกส่งซ้ำ'),
        findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets(
      'cancel conflict reconciles a started post instead of keeping stale queue actions',
      (tester) async {
    final api = _ReadClient(_post('QUEUED'))
      ..cancelError =
          const ApiException('Scheduled post not found', statusCode: 404);
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('QUEUED'), apiClient: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    api.latest = _post('PUBLISHING');
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.reads, 2);
    expect(find.byKey(const ValueKey('post-detail-publish-now')), findsNothing);
    expect(find.textContaining('โพสต์เริ่มส่งแล้ว'), findsOneWidget);
    expect(api.writes, 1);
  });

  testWidgets(
      'lost cancel response followed by verified absence does not retain destructive actions',
      (tester) async {
    final api = _ReadClient(_post('QUEUED'))
      ..cancelError = TimeoutException('Response lost');
    await tester.pumpWidget(MaterialApp(
        home: PostDetailScreen(post: _post('QUEUED'), apiClient: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    api.latest = null;
    await tester.tap(find.text('ยกเลิกโพสต์').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-detail-post-unavailable')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('post-detail-publish-now')), findsNothing);
    expect(api.writes, 1);
  });
}
