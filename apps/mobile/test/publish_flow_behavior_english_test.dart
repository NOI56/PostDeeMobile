import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';
// The fake replaces the existing URL launcher seam; it opens no application.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'publish_flow_english_test.dart'
    show PublishEnglishFixture, publishEnglishPost, loadPublishEnglishFonts;

const _owner =
    AuthSession(userId: 'publish-behavior-owner', idToken: 'fake-token');

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    return true;
  }
}

PublishEnglishFixture _fixture(WidgetTester tester) {
  final fixture = PublishEnglishFixture();
  addTearDown(fixture.dispose);
  addTearDown(() => fixture.close(tester));
  return fixture;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _noPrivateMetadata() {
  expect(find.textContaining('uploads/'), findsNothing);
  expect(find.textContaining('provider-private'), findsNothing);
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  late AuthSession previous;
  setUpAll(loadPublishEnglishFonts);
  setUp(() {
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance.signIn(_owner);
  });
  tearDown(() {
    PostDeeAuthSessionStore.instance.signIn(previous);
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  testWidgets(
      'English provider draft receipt opens the original id without replaying publish',
      (tester) async {
    final fixture = _fixture(tester)
      ..platforms = const [SocialPlatform.tiktok]
      ..post = publishEnglishPost(
          status: 'PUBLISHED',
          replay: true,
          id: 'original-provider-draft',
          results: const [
            PostPlatformResult(
                postId: 'original-provider-draft',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT',
                externalPostId: 'provider-private-id')
          ]);
    await fixture.mount(tester);
    expect(find.text('Sent as draft'), findsOneWidget);
    expect(
        find.text(
            'Existing post found · Sent as a draft to 1 channel · Data was sent and post quota was used.'),
        findsOneWidget);
    expect(find.text('TikTok · Sent as draft'), findsOneWidget);
    expect(find.text('Continue in TikTok'), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['original-provider-draft']);
    expect(fixture.attempts, 1);
    _noPrivateMetadata();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English timeout error follows locale without another publish attempt',
      (tester) async {
    final fixture = _fixture(tester)
      ..error = TimeoutException('provider-private timeout details');
    await fixture.mount(tester);
    expect(find.text('The request took too long. Please try again.'),
        findsOneWidget);
    fixture.language.value = const Locale('th');
    await tester.pump();
    expect(
        find.text('ระบบตอบกลับช้าเกินไป กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(find.text('The request took too long. Please try again.'),
        findsOneWidget);
    expect(fixture.attempts, 1);
    _noPrivateMetadata();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English pending flow blocks Back and keeps its foreground notice',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final fixture = _fixture(tester)..gate = pending.future;
    await fixture.mount(tester);
    expect(
        find.text(
            'Keep this screen open while your post is prepared and sent. You cannot cancel until this step finishes.'),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
        find.text(
            'You cannot cancel while data is being sent. Wait for this step to finish.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('publish-flow-posting')), findsOneWidget);
    expect(fixture.actions, isEmpty);
    expect(fixture.attempts, 1);
    pending.complete(publishEnglishPost(id: 'same-attempt-after-back'));
    await tester.pumpAndSettle();
    expect(find.text('Post received'), findsOneWidget);
    expect(fixture.attempts, 1);
    expect(tester.takeException(), isNull);
  });

  for (final sample in [
    (outcome: 'PRIVATE', title: 'Private'),
    (outcome: 'UNLISTED', title: 'Unlisted'),
    (outcome: 'LIVE', title: 'Published'),
  ]) {
    testWidgets(
        'English ${sample.outcome} delivery preserves original post action',
        (tester) async {
      final id = 'original-${sample.outcome}';
      final fixture = _fixture(tester)
        ..platforms = const [SocialPlatform.youtubeShorts]
        ..post = publishEnglishPost(
            status: 'PUBLISHED',
            replay: true,
            id: id,
            results: [
              PostPlatformResult(
                  postId: id,
                  platform: 'YOUTUBE_SHORTS',
                  status: 'PUBLISHED',
                  deliveryOutcome: sample.outcome,
                  externalPostId: 'provider-private-id')
            ]);
      await fixture.mount(tester);
      expect(find.text(sample.title), findsOneWidget);
      expect(find.text('YouTube Shorts · ${sample.title}'), findsOneWidget);
      expect(
          find.text(
              'Existing post found · Delivered to 1 channel · ${sample.title}'),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('tiktok-draft-next-step')), findsNothing);
      await _tap(tester, 'publish-flow-view-post');
      expect(fixture.viewedPosts, [id]);
      expect(fixture.attempts, 1);
      _noPrivateMetadata();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'mixed provider visibility keeps draft and private outcomes distinct',
      (tester) async {
    final fixture = _fixture(tester)
      ..post = publishEnglishPost(
          status: 'PUBLISHED',
          id: 'mixed-visibility',
          results: const [
            PostPlatformResult(
                postId: 'mixed-visibility',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT'),
            PostPlatformResult(
                postId: 'mixed-visibility',
                platform: 'YOUTUBE_SHORTS',
                status: 'PUBLISHED',
                deliveryOutcome: 'PRIVATE')
          ]);
    await fixture.mount(tester);
    expect(find.text('Delivered with different visibility'), findsOneWidget);
    expect(
        find.text(
            'Delivered to 2 channels · Delivered with different visibility'),
        findsOneWidget);
    expect(find.text('TikTok · Sent as draft'), findsOneWidget);
    expect(find.text('YouTube Shorts · Private'), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(
        find.byKey(const ValueKey('tiktok-draft-next-step')), findsOneWidget);
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['mixed-visibility']);
    expect(fixture.attempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mixed provider success and failure overrides an aggregate published status',
      (tester) async {
    final fixture = _fixture(tester)
      ..post = publishEnglishPost(
          status: 'PUBLISHED',
          id: 'partial-providers',
          results: const [
            PostPlatformResult(
                postId: 'partial-providers',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'DRAFT'),
            PostPlatformResult(
                postId: 'partial-providers',
                platform: 'YOUTUBE_SHORTS',
                status: 'FAILED',
                errorMessage: 'provider-private failure')
          ]);
    await fixture.mount(tester);
    expect(find.text('Delivered to some channels'), findsOneWidget);
    expect(
        find.text(
            'Only some channels succeeded. Open the post details to check the channels that failed.'),
        findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(
        find.byKey(const ValueKey('tiktok-draft-next-step')), findsOneWidget);
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['partial-providers']);
    expect(fixture.attempts, 1);
    _noPrivateMetadata();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unknown delivery outcome stays unconfirmed rather than successful',
      (tester) async {
    final fixture = _fixture(tester)
      ..platforms = const [SocialPlatform.tiktok]
      ..post = publishEnglishPost(
          status: 'PUBLISHED',
          id: 'unknown-provider',
          results: const [
            PostPlatformResult(
                postId: 'unknown-provider',
                platform: 'TIKTOK',
                status: 'PUBLISHED',
                deliveryOutcome: 'FUTURE_PROVIDER_OUTCOME',
                externalPostId: 'provider-private-id')
          ]);
    await fixture.mount(tester);
    expect(find.text('Delivery unconfirmed'), findsOneWidget);
    expect(
        find.text(
            'Results received from 1 channel, but the delivery outcome is not confirmed.'),
        findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(find.text('Post sent'), findsNothing);
    expect(find.byKey(const ValueKey('tiktok-draft-next-step')), findsNothing);
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['unknown-provider']);
    expect(fixture.attempts, 1);
    _noPrivateMetadata();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English typed API errors use safe messages without raw provider output',
      (tester) async {
    for (final sample in [
      (
        error: const ApiException('<html>provider-private</html>',
            statusCode: 401),
        message: 'Please sign in again and retry.'
      ),
      (
        error: const ApiException('provider-private', statusCode: 429),
        message: 'Too many requests. Wait a moment and try again.'
      ),
      (
        error: const ApiException('<html>provider-private</html>',
            statusCode: 503),
        message: 'PostDee is temporarily unavailable. Please try again later.'
      ),
      (
        error:
            const ApiException('provider-private', code: apiRequestTimeoutCode),
        message: 'The request took too long. Please try again.'
      ),
      (
        error: const ApiException('provider-private', statusCode: 408),
        message: 'The request took too long. Please try again.'
      ),
    ]) {
      final fixture = _fixture(tester)..error = sample.error;
      await fixture.mount(tester);
      expect(find.text(sample.message), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(fixture.attempts, 1);
      _noPrivateMetadata();
      await fixture.close(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'English transport and unknown provider errors remain safely generic',
      (tester) async {
    for (final sample in [
      (
        error: const SocketException('provider-private socket'),
        message:
            'Cannot connect to PostDee. Check your internet connection and try again.'
      ),
      (
        error: const HttpException('provider-private http'),
        message:
            'Cannot connect to PostDee. Check your internet connection and try again.'
      ),
      (
        error: const HandshakeException('provider-private handshake'),
        message:
            'Cannot connect to PostDee. Check your internet connection and try again.'
      ),
      (
        error: const ApiException('<html>provider-private message</html>',
            statusCode: 400),
        message:
            'An error occurred while sending your post. Check your connection and try again.'
      ),
      (
        error: const ApiException('ข้อความผู้ให้บริการที่ไม่ควรแสดงเป็นอังกฤษ',
            code: 'UNKNOWN_PROVIDER'),
        message:
            'An error occurred while sending your post. Check your connection and try again.'
      ),
    ]) {
      final fixture = _fixture(tester)..error = sample.error;
      await fixture.mount(tester);
      expect(find.text(sample.message), findsOneWidget);
      expect(find.textContaining('ข้อความผู้ให้บริการ'), findsNothing);
      expect(fixture.attempts, 1);
      _noPrivateMetadata();
      await fixture.close(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retry runs once and ignores the previous attempt progress reporter',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final fixture = _fixture(tester);
    fixture.operation = (reporter, attempt) async {
      if (attempt == 1) {
        throw const ApiException('fake network', statusCode: 503);
      }
      reporter(const PublishFlowProgress(
          stage: PublishFlowStage.checkingPlan, fraction: .2));
      return pending.future;
    };
    await fixture.mount(tester);
    final oldReporter = fixture.reporters.single;
    final retry = find.byKey(const ValueKey('publish-flow-retry'));
    await tester.tap(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(fixture.attempts, 2);
    oldReporter(const PublishFlowProgress(
        stage: PublishFlowStage.finalizing, fraction: .99));
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('publish-flow-progress')))
            .value,
        .2);
    expect(find.text('Checking plan'), findsOneWidget);
    pending.complete(publishEnglishPost(id: 'retried-original-post'));
    await tester.pumpAndSettle();
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['retried-original-post']);
    expect(fixture.attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'original post accepts credential refresh and blocks the old owner lifetime',
      (tester) async {
    final fixture = _fixture(tester)
      ..post = publishEnglishPost(id: 'owner-bound-post');
    await fixture.mount(tester);
    final sessions = PostDeeAuthSessionStore.instance;
    sessions.updateCredentials(const AuthSession(
        userId: 'publish-behavior-owner', idToken: 'refreshed-token'));
    await _tap(tester, 'publish-flow-view-post');
    expect(fixture.viewedPosts, ['owner-bound-post']);
    sessions.signIn(
        const AuthSession(userId: 'other-owner', idToken: 'other-token'));
    sessions.signIn(_owner);
    await _tap(tester, 'publish-flow-view-post');
    expect(find.text('Your account has changed. Reopen the post list.'),
        findsOneWidget);
    expect(fixture.viewedPosts, ['owner-bound-post']);
    expect(fixture.attempts, 1);
    expect(tester.takeException(), isNull);
  });

  for (final action in [
    PublishFlowAction.finish,
    PublishFlowAction.analytics
  ]) {
    testWidgets(
        'English ${action.name} exits with its action without publishing again',
        (tester) async {
      final fixture = _fixture(tester);
      await fixture.mount(tester);
      await _tap(
          tester,
          action == PublishFlowAction.finish
              ? 'publish-flow-finish'
              : 'publish-flow-analytics');
      expect(fixture.actions, [action]);
      expect(fixture.attempts, 1);
      expect(fixture.viewedPosts, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'late progress and success after unmount cannot navigate or set state',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final fixture = _fixture(tester)..gate = pending.future;
    await fixture.mount(tester);
    final reporter = fixture.reporters.single;
    await fixture.close(tester);
    reporter(const PublishFlowProgress(
        stage: PublishFlowStage.finalizing, fraction: .99));
    pending.complete(publishEnglishPost(id: 'late-private-post'));
    await tester.pump();
    expect(fixture.attempts, 1);
    expect(fixture.viewedPosts, isEmpty);
    expect(fixture.actions, isEmpty);
    expect(find.byKey(const ValueKey('publish-flow-done')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'confirmed TikTok draft opens only its public homepage without replay',
      (tester) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
    final fixture = _fixture(tester)
      ..platforms = const [SocialPlatform.tiktok]
      ..post = publishEnglishPost(status: 'PUBLISHED', results: const [
        PostPlatformResult(
            postId: 'draft',
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            deliveryOutcome: 'DRAFT',
            externalPostId: 'https://provider-private.test/not-a-launch-url')
      ]);
    await fixture.mount(tester);
    expect(find.text('Continue in TikTok'), findsOneWidget);
    await _tap(tester, 'tiktok-draft-open');
    expect(launcher.urls, ['https://www.tiktok.com/']);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    expect(fixture.attempts, 1);
    await fixture.close(tester);
    for (final status in ['QUEUED', 'PUBLISHING', 'FAILED']) {
      final unconfirmed = _fixture(tester)
        ..platforms = const [SocialPlatform.tiktok]
        ..post = publishEnglishPost(status: status, results: [
          PostPlatformResult(
              postId: 'not-confirmed',
              platform: 'TIKTOK',
              status: status,
              deliveryOutcome: 'DRAFT')
        ]);
      await unconfirmed.mount(tester);
      expect(
          find.byKey(const ValueKey('tiktok-draft-next-step')), findsNothing);
      expect(unconfirmed.attempts, 1);
      await unconfirmed.close(tester);
    }
    expect(launcher.urls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'background completion returns to its English error without replay',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final fixture = _fixture(tester)
      ..gate = pending.future
      ..reducedMotion = false;
    addTearDown(() => _resume(tester));
    await fixture.mount(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('publish-flow-orbit')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pending.completeError(TimeoutException('provider-private timeout'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(fixture.attempts, 1);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(find.text('The request took too long. Please try again.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('publish-flow-posting')), findsNothing);
    expect(find.byKey(const ValueKey('publish-flow-retry')).hitTestable(),
        findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(fixture.attempts, 1);
    expect(tester.takeException(), isNull);
  });
}
