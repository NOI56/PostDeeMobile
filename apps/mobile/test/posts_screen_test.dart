import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/posts/post_detail_screen.dart';
import 'package:postdee_mobile/features/posts/posts_screen.dart';

PostSummaryResult _post(String id, String status) => PostSummaryResult(
    id: id,
    caption: 'Caption $id',
    videoS3Key: 'uploads/$id.mp4',
    platforms: const ['TIKTOK'],
    status: status,
    createdAt: DateTime(2026, 10, 9));

class _SinglePostClient extends PostDeeApiClient {
  int reads = 0;
  int historyLoads = 0;
  String status = 'FAILED';
  final List<bool> mediaRequests = [];
  @override
  Future<PostSummaryResult?> getPostById(String id,
      {bool includeMedia = false}) async {
    reads++;
    mediaRequests.add(includeMedia);
    return _post(id, status);
  }

  @override
  Future<List<PostSummaryResult>> listRecentPosts({int limit = 3}) async {
    historyLoads++;
    throw StateError('Notification must not scan the full history');
  }
}

void main() {
  testWidgets(
      'notification detail signs media on open but status polling reads no media',
      (tester) async {
    final api = _SinglePostClient()..status = 'PUBLISHING';
    await tester.pumpWidget(MaterialApp(
        home: PostDetailLoaderScreen(postId: 'target', apiClient: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.mediaRequests, [true]);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(api.mediaRequests, [true, false]);
    expect(api.historyLoads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'default notification loader reads its exact id once without loading history',
      (tester) async {
    final api = _SinglePostClient();
    await tester.pumpWidget(MaterialApp(
        home: PostDetailLoaderScreen(postId: 'target', apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Caption target'), findsOneWidget);
    expect(api.reads, 1);
    expect(api.historyLoads, 0);
  });

  testWidgets(
      'status, supported platform and created-date filters select the matching rows',
      (tester) async {
    final now = DateTime.now();
    PostSummaryResult item(
            String id, String status, String platform, DateTime createdAt) =>
        PostSummaryResult(
            id: id,
            caption: 'Filter $id',
            videoS3Key: 'uploads/owner/$id.mp4',
            platforms: [platform],
            status: status,
            createdAt: createdAt);
    await tester.pumpWidget(MaterialApp(
        home: PostsScreen(
            loadPosts: () async => [
                  item('youtube-today', 'FAILED', 'YOUTUBE_SHORTS', now),
                  item('tiktok-today', 'FAILED', 'TIKTOK', now),
                  item('youtube-old', 'FAILED', 'YOUTUBE_SHORTS',
                      DateTime(2020)),
                  item('youtube-done', 'PUBLISHED', 'YOUTUBE_SHORTS', now),
                ])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posts-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ส่งไม่สำเร็จ').last);
    await tester.pumpAndSettle();
    expect(find.text('Filter youtube-done'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('posts-platform-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YouTube Shorts').last);
    await tester.pumpAndSettle();
    expect(find.text('Filter tiktok-today'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('posts-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('วันนี้').last);
    await tester.pumpAndSettle();
    expect(find.text('Filter youtube-today'), findsOneWidget);
    expect(find.text('Filter youtube-old'), findsNothing);
    expect(find.text('Shopee Video'), findsNothing);
    expect(find.text('Lazada Video'), findsNothing);
  });

  testWidgets(
      'all posts exposes search and platform/status/date context and reloads after ordinary back',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: PostsScreen(loadPosts: () async {
      loads++;
      return [_post('published', 'PUBLISHED'), _post('failed', 'FAILED')];
    })));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('posts-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('posts-status-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('posts-platform-filter')), findsOneWidget);
    expect(find.textContaining('9 ต.ค. 2026'), findsWidgets);
    await tester.enterText(
        find.byKey(const ValueKey('posts-search')), 'failed');
    await tester.pump();
    expect(find.text('Caption published'), findsNothing);
    await tester.tap(find.text('Caption failed'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets(
      'lists immediate and scheduled posts and opens the existing detail',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostsScreen(
            loadPosts: () async => [
                  _post('published', 'PUBLISHED'),
                  _post('failed', 'FAILED'),
                  _post('queued', 'QUEUED')
                ])));
    await tester.pumpAndSettle();
    expect(find.text('Caption published'), findsOneWidget);
    expect(find.text('Caption failed'), findsOneWidget);
    expect(find.text('Caption queued'), findsOneWidget);
    await tester.tap(find.text('Caption failed'));
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets(
      'a notification loader shows unavailable for an absent owned post',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PostDetailLoaderScreen(
            postId: 'missing', loadPosts: () async => [])));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('post-detail-unavailable')), findsOneWidget);
    expect(find.byType(PostDetailScreen), findsNothing);
  });

  testWidgets(
      'never applies a prior owners pending post detail after account switch',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(AuthSession.authenticated(userId: 'owner-a', idToken: 'a'));
    final result = Completer<List<PostSummaryResult>>();
    await tester.pumpWidget(MaterialApp(
        home: PostDetailLoaderScreen(
            postId: 'private', loadPosts: () => result.future)));
    await tester.pump();
    sessions.signIn(AuthSession.authenticated(userId: 'owner-b', idToken: 'b'));
    result.complete([_post('private', 'PUBLISHED')]);
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsNothing);
    expect(find.text('Caption private'), findsNothing);
  });
}
