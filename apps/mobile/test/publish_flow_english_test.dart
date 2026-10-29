import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/publish_flow_screen.dart';

import 'post_video_preview_english_test.dart' show expectPreviewEnglishReadable;

QueuedPostResult publishEnglishPost(
        {String status = 'QUEUED',
        List<PostPlatformResult> results = const [],
        bool replay = false,
        String id = 'โพสต์จำลอง-private-id'}) =>
    QueuedPostResult(
        id: id,
        videoS3Key: 'uploads/private-customer-object.mp4',
        platforms: const ['TIKTOK', 'YOUTUBE_SHORTS'],
        status: status,
        platformResults: results,
        idempotentReplay: replay);

class PublishEnglishFixture {
  PublishEnglishFixture(
      {Locale locale = const Locale('en'), this.dark = false, this.scale = 1})
      : language = ValueNotifier(locale);
  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final boundaryKey = GlobalKey();
  final reporters = <PublishProgressReporter>[];
  final actions = <PublishFlowAction?>[];
  final viewedPosts = <String>[];
  List<SocialPlatform> platforms = const [
    SocialPlatform.tiktok,
    SocialPlatform.youtubeShorts
  ];
  bool scheduled = false;
  bool bareMaterialApp = false;
  bool reducedMotion = true;
  bool tickerEnabled = true;
  int attempts = 0;
  QueuedPostResult? post = publishEnglishPost();
  Object? error;
  Future<QueuedPostResult?>? gate;
  Future<QueuedPostResult?> Function(PublishProgressReporter, int)? operation;

  PublishFlowScreen screen() => PublishFlowScreen(
      platforms: platforms,
      isScheduled: scheduled,
      onViewPost: viewedPosts.add,
      publish: (reporter) async {
        attempts++;
        reporters.add(reporter);
        if (operation != null) return operation!(reporter, attempts);
        if (error != null) throw error!;
        return gate == null ? post : await gate!;
      });

  void report(PublishFlowStage stage, double fraction) =>
      reporters.last(PublishFlowProgress(stage: stage, fraction: fraction));

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                supportedLocales: PostDeeLocalizations.supportedLocales,
                localizationsDelegates: [
                  if (!bareMaterialApp) PostDeeLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        disableAnimations: reducedMotion,
                        textScaler: TextScaler.linear(scale)),
                    child: TickerMode(enabled: tickerEnabled, child: child!)),
                home: Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            key: const ValueKey('publish-english-open'),
                            child: const Text('Open publish fixture'),
                            onPressed: () async {
                              final action = await Navigator.of(context).push<
                                      PublishFlowAction>(
                                  MaterialPageRoute(builder: (_) => screen()));
                              actions.add(action);
                            })))));
      });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('publish-english-open')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory =
        Platform.environment['POSTDEE_PUBLISH_FLOW_ENGLISH_PREVIEW_DIR'];
    if (directory == null || directory.isEmpty) return;
    await tester.pump();
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  void dispose() => language.dispose();
}

Future<void> revealPublishEnglish(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> loadPublishEnglishFonts() async {
  final loader = FontLoader('Anuphan');
  // Explicit null-font styles retain the tester fallback, so their screenshots
  // are diagnostic artifacts rather than native platform-font proof.
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  late AuthSession previous;
  setUpAll(loadPublishEnglishFonts);
  setUp(() {
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'publish-english-owner'));
  });
  tearDown(() => PostDeeAuthSessionStore.instance.signIn(previous));
  Future<PublishEnglishFixture> mount(WidgetTester tester,
      [PublishEnglishFixture? value]) async {
    final fixture = value ?? PublishEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    return fixture;
  }

  testWidgets(
      'English reported progress retains its exact fraction and runs once',
      (tester) async {
    final pending = Completer<QueuedPostResult?>();
    final fixture = PublishEnglishFixture()..gate = pending.future;
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    fixture.report(PublishFlowStage.uploadingVideo, .55);
    await tester.pump();
    expect(find.text('Uploading video'), findsOneWidget);
    expect(find.text('55% · Step progress'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('publish-flow-progress')))
            .value,
        .55);
    expect(fixture.attempts, 1);
    await fixture.capture(tester, 'progress-55-en-1x');
  });

  testWidgets('English send failure safely hides raw implementation errors',
      (tester) async {
    final fixture = PublishEnglishFixture()
      ..error = StateError('<html>raw private adapter details</html>');
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Could not send post'), findsOneWidget);
    expect(
        find.text(
            'An error occurred while sending your post. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('raw private adapter'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(fixture.attempts, 1);
    await fixture.capture(tester, 'error-en-1x');
  });

  testWidgets('English queued receipt offers Done without claiming publication',
      (tester) async {
    final fixture = PublishEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Post received'), findsOneWidget);
    expect(find.text('Post received for 2 channels. Delivery is in progress.'),
        findsOneWidget);
    expect(find.text('View this post'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Published'), findsNothing);
    expect(fixture.attempts, 1);
    await fixture.capture(tester, 'received-en-1x');
    await tester.tap(find.byKey(const ValueKey('publish-flow-finish')));
    await tester.pumpAndSettle();
    expect(fixture.actions, [PublishFlowAction.finish]);
    expect(fixture.attempts, 1);
  });

  for (final status in const {
    'PUBLISHING': (
      'Sending post',
      'Sending to 2 channels. Check the result again in your post list.'
    ),
    'PUBLISHED': ('Post sent', 'Sent to 2 channels.'),
    'PARTIAL_PUBLISHED': (
      'Delivered to some channels',
      'Only some channels succeeded. Open the post details to check the channels that failed.'
    ),
    'FAILED': (
      'Post not sent',
      'This post was not sent. Open the details to see what needs fixing.'
    ),
  }.entries) {
    testWidgets('English ${status.key} receipt keeps its truthful result',
        (tester) async {
      final fixture = await mount(
          tester,
          PublishEnglishFixture()
            ..post = publishEnglishPost(status: status.key));
      expect(find.text(status.value.$1), findsOneWidget);
      expect(find.text(status.value.$2), findsOneWidget);
      expect(find.text('Published'), findsNothing);
      expect(fixture.attempts, 1);
      expect(find.byKey(const ValueKey('publish-flow-posting')), findsNothing);
    });
  }

  testWidgets(
      'English scheduled receipt claims scheduling rather than delivery',
      (tester) async {
    final fixture =
        await mount(tester, PublishEnglishFixture()..scheduled = true);
    expect(find.text('Post scheduled'), findsOneWidget);
    expect(
        find.text('Scheduled post received for 2 channels.'), findsOneWidget);
    expect(find.text('Post sent'), findsNothing);
    expect(fixture.attempts, 1);
  });

  testWidgets(
      'all nine reported stages preserve fractions and untranslated model titles',
      (tester) async {
    final fixture = await mount(tester,
        PublishEnglishFixture()..gate = Completer<QueuedPostResult?>().future);
    const stages = [
      (PublishFlowStage.preparing, 'Preparing post', .08),
      (
        PublishFlowStage.checkingAvailability,
        'Checking publishing service',
        .18
      ),
      (PublishFlowStage.checkingPlan, 'Checking plan', .28),
      (PublishFlowStage.applyingWatermark, 'Applying watermark', .38),
      (PublishFlowStage.uploadingVideo, 'Uploading video', .55),
      (PublishFlowStage.retryingUpload, 'Reconnecting upload', .56),
      (PublishFlowStage.uploadingCover, 'Uploading cover', .65),
      (PublishFlowStage.creatingPost, 'Creating post', .9),
      (PublishFlowStage.finalizing, 'Finalizing post', .98),
    ];
    for (final stage in stages) {
      fixture.report(stage.$1, stage.$3);
      await tester.pump();
      expect(find.text(stage.$2), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byKey(const ValueKey('publish-flow-progress')))
              .value,
          stage.$3);
      expect(find.text('${(stage.$3 * 100).round()}% · Step progress'),
          findsOneWidget);
    }
    expect(
        const PublishFlowProgress(
                stage: PublishFlowStage.preparing, fraction: .08)
            .title,
        'กำลังเตรียมข้อมูล');
    expect(fixture.attempts, 1);
    expect(fixture.reporters, hasLength(1));
  });

  testWidgets('English progress rail semantics follow stages rather than time',
      (tester) async {
    final fixture = await mount(tester,
        PublishEnglishFixture()..gate = Completer<QueuedPostResult?>().future);
    Semantics step(String id) =>
        tester.widget<Semantics>(find.byKey(ValueKey('publish-flow-step-$id')));
    expect(step('prepare').properties.label, 'Prepare');
    expect(step('prepare').properties.value, 'In progress');
    expect(step('upload').properties.value, 'Waiting');
    fixture.report(PublishFlowStage.creatingPost, .9);
    await tester.pump();
    expect(step('prepare').properties.value, 'Done');
    expect(step('upload').properties.label, 'Upload');
    expect(step('upload').properties.value, 'Done');
    expect(step('queue').properties.label, 'Queue');
    expect(step('queue').properties.value, 'In progress');
    final rail = tester.widget<Semantics>(find
        .ancestor(
            of: find.byKey(const ValueKey('publish-flow-progress')),
            matching: find.byType(Semantics))
        .first);
    expect(rail.properties.label, 'Step progress');
    expect(rail.properties.value, '90%');
    await tester.pump(const Duration(seconds: 12));
    expect(step('queue').properties.value, 'In progress');
    expect(fixture.attempts, 1);
  });

  testWidgets('changing locale retains reported progress and never republishes',
      (tester) async {
    final fixture = await mount(
        tester,
        PublishEnglishFixture(locale: const Locale('th'))
          ..gate = Completer<QueuedPostResult?>().future);
    fixture.report(PublishFlowStage.uploadingCover, .65);
    await tester.pump();
    expect(find.text('กำลังอัปโหลดหน้าปก'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Uploading cover'), findsOneWidget);
    expect(find.text('Processing 2 channels'), findsOneWidget);
    expect(find.text('65% · Step progress'), findsOneWidget);
    expect(fixture.attempts, 1);
    expect(fixture.reporters, hasLength(1));
  });

  testWidgets('receipt keeps private post metadata out of visible copy',
      (tester) async {
    final post = publishEnglishPost();
    final fixture = await mount(tester, PublishEnglishFixture()..post = post);
    expect(find.textContaining(post.id), findsNothing);
    expect(find.textContaining(post.videoS3Key), findsNothing);
    expect(find.text('View this post'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('publish-flow-view-post')));
    await tester.pump();
    expect(fixture.viewedPosts, [post.id]);
    expect(fixture.attempts, 1);
  });

  testWidgets('plain MaterialApp keeps the original Thai receipt fallback',
      (tester) async {
    final fixture =
        await mount(tester, PublishEnglishFixture()..bareMaterialApp = true);
    expect(find.text('รับรายการแล้ว'), findsOneWidget);
    expect(find.text('เสร็จสิ้น'), findsOneWidget);
    expect(find.text('ดูโพสต์นี้'), findsOneWidget);
    expect(find.text('Post received'), findsNothing);
    expect(fixture.attempts, 1);
  });

  QueuedPostResult draft() => const QueuedPostResult(
      id: 'draft-fixture-id',
      videoS3Key: 'uploads/private-draft.mp4',
      platforms: ['TIKTOK'],
      status: 'PUBLISHED',
      platformResults: [
        PostPlatformResult(
            postId: 'draft-fixture-id',
            platform: 'TIKTOK',
            status: 'PUBLISHED',
            deliveryOutcome: 'DRAFT')
      ]);
  Future<void> readable(WidgetTester tester, String value) async {
    final finder = find.text(value);
    await revealPublishEnglish(tester, finder);
    expectPreviewEnglishReadable(tester, finder);
  }

  for (final dark in [false, true]) {
    testWidgets(
        'narrow 2x real-font progress is fully readable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await mount(
          tester,
          PublishEnglishFixture(dark: dark, scale: 2)
            ..gate = Completer<QueuedPostResult?>().future);
      fixture.report(PublishFlowStage.checkingAvailability, .18);
      await tester.pump();
      for (final value in [
        'Checking publishing service',
        'Processing 2 channels',
        '18% · Step progress',
        'Prepare',
        'Upload',
        'Queue',
        'This percentage shows progress through the steps, not uploaded bytes.',
        'Keep this screen open while your post is prepared and sent. You cannot cancel until this step finishes.'
      ]) {
        await readable(tester, value);
      }
      expect(fixture.attempts, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow 2x real-font error actions retry once into pending ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await mount(
          tester,
          PublishEnglishFixture(dark: dark, scale: 2)
            ..error = StateError('fake adapter unavailable'));
      for (final value in [
        'Could not send post',
        'An error occurred while sending your post. Check your connection and try again.',
        'Try again',
        'Go back and check'
      ]) {
        await readable(tester, value);
      }
      fixture.error = null;
      fixture.gate = Completer<QueuedPostResult?>().future;
      final retry = find.byKey(const ValueKey('publish-flow-retry'));
      await revealPublishEnglish(tester, retry);
      expect(retry.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('publish-flow-posting')), findsOneWidget);
      expect(fixture.attempts, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow 2x draft card and receipt actions are usable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await mount(
          tester,
          PublishEnglishFixture(dark: dark, scale: 2)
            ..platforms = [SocialPlatform.tiktok]
            ..post = draft());
      for (final value in [
        'Sent as draft',
        'Sent as a draft to 1 channel · Data was sent and post quota was used.',
        'Continue in TikTok',
        'A draft is not published to viewers. Open the TikTok app with your connected account, go to Inbox, and tap the notification to review, edit, and publish it yourself.',
        'Open TikTok',
        'This button may open a website. If it does, open the TikTok app yourself. This does not send your video again.',
        'View this post',
        'Done',
        'View post analytics'
      ]) {
        await readable(tester, value);
      }
      final viewPost = find.byKey(const ValueKey('publish-flow-view-post'));
      await revealPublishEnglish(tester, viewPost);
      expect(viewPost.hitTestable(), findsOneWidget);
      await tester.tap(viewPost);
      await tester.pump();
      expect(fixture.viewedPosts, ['draft-fixture-id']);
      final analytics = find.byKey(const ValueKey('publish-flow-analytics'));
      await revealPublishEnglish(tester, analytics);
      expect(analytics.hitTestable(), findsOneWidget);
      await fixture.capture(tester, 'draft-en-2x-${dark ? 'dark' : 'light'}');
      await tester.tap(analytics);
      await tester.pumpAndSettle();
      expect(fixture.actions, [PublishFlowAction.analytics]);
      expect(fixture.attempts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('optional local outcome screenshots use only fake operations',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cases = <String, QueuedPostResult>{
      'confirmed-draft-en-1x': draft(),
      'partial-en-1x': publishEnglishPost(status: 'PARTIAL_PUBLISHED'),
      'unconfirmed-en-1x':
          publishEnglishPost(status: 'PUBLISHED', results: const [
        PostPlatformResult(
            postId: 'unknown-fixture-id',
            platform: 'YOUTUBE_SHORTS',
            status: 'PUBLISHED',
            deliveryOutcome: 'FUTURE_OUTCOME')
      ]),
      'sent-en-1x': publishEnglishPost(status: 'PUBLISHED'),
    };
    for (final entry in cases.entries) {
      final fixture = PublishEnglishFixture()..post = entry.value;
      if (entry.key.startsWith('confirmed-draft')) {
        fixture.platforms = [SocialPlatform.tiktok];
      }
      try {
        await fixture.mount(tester);
        await fixture.capture(tester, entry.key);
        expect(fixture.attempts, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
        fixture.dispose();
      }
    }
  },
      skip: Platform.environment['POSTDEE_PUBLISH_FLOW_ENGLISH_PREVIEW_DIR']
              ?.isNotEmpty !=
          true);
}
