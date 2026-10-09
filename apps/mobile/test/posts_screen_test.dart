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

void main() {
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
