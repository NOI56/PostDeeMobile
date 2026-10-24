import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/post_video_preview_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_post_preview.dart';
import 'package:video_player/video_player.dart';
// The fake replaces the platform interface already used by video_player.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PreviewVideoPlatform extends VideoPlayerPlatform {
  _PreviewVideoPlatform({
    this.failFirstInitialization = false,
    this.failFirstPlay = false,
    this.firstCreationGate,
  });

  final bool failFirstInitialization;
  final bool failFirstPlay;
  final Completer<void>? firstCreationGate;
  final List<DataSource> sources = [];
  final Map<int, StreamController<VideoEvent>> events = {};
  final Map<int, int> disposeCounts = {};
  final Map<int, Duration> positions = {};
  final List<int> played = [];
  final List<int> paused = [];
  final List<Duration> seeks = [];
  final List<({int playerId, double volume})> volumes = [];
  Completer<void>? volumeGate;
  bool failNextVolume = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = sources.length + 1;
    sources.add(options.dataSource);
    if (playerId == 1) await firstCreationGate?.future;
    positions[playerId] = Duration.zero;
    events[playerId] = StreamController<VideoEvent>(
      onListen: () {
        if (failFirstInitialization && playerId == 1) {
          events[playerId]!.addError(
            PlatformException(code: 'invalid-video', message: 'Invalid video'),
          );
        } else {
          events[playerId]!.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 30),
              size: const Size(1080, 1920),
            ),
          );
        }
      },
    );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposeCounts.update(playerId, (count) => count + 1, ifAbsent: () => 1);
    await events[playerId]?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add((playerId: playerId, volume: volume));
    if (failNextVolume) {
      failNextVolume = false;
      throw StateError('Volume unavailable');
    }
    await volumeGate?.future;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
    if (failFirstPlay && played.length == 1) throw StateError('Play failed');
  }

  @override
  Future<void> pause(int playerId) async => paused.add(playerId);

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
        key: ValueKey('fake-preview-video-${options.playerId}'),
        color: Colors.blue,
      );
}

Widget _testApp({
  ThemeData? theme,
  double textScale = 1,
  String videoPath = 'local-selected-clip.mp4',
  bool reducedMotion = false,
  bool tickerEnabled = true,
  PublishPostPreviewData? postPreview,
  AuthSessionBinding? ownerSession,
}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: PostVideoPreviewScreen(
        videoFile: File(videoPath),
        videoName: 'คลิปสินค้าของฉัน.mp4',
        postPreview: postPreview,
        ownerSession: ownerSession,
      ),
    );

Future<void> _settleNativeDisposal(WidgetTester tester) async {
  // video_player cancels its event subscription asynchronously on disposal.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void _resumePreviewMotion(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  late VideoPlayerPlatform previousPlatform;
  late _PreviewVideoPlatform platform;

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    platform = _PreviewVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    AppTheme.applyThemeMode(ThemeMode.light);
  });

  tearDown(() {
    VideoPlayerPlatform.instance = previousPlatform;
  });

  PublishPostPreviewData previewData() => PublishPostPreviewData(
        caption: 'แคปชันหลัก',
        channels: [
          const PublishPostPreviewChannel(
            platform: SocialPlatform.tiktok,
            caption: 'ข้อความเฉพาะ TikTok',
            displayName: '@seller',
            publishingNote: 'ส่งเป็นร่างเข้า TikTok',
          ),
          const PublishPostPreviewChannel(
            platform: SocialPlatform.youtubeShorts,
            caption: 'คำอธิบาย YouTube',
            displayName: 'Seller channel',
            title: 'ชื่อคลิป YouTube',
          ),
        ],
      );

  testWidgets('post preview switches captions while keeping one local player',
      (tester) async {
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    expect(find.text('พรีวิว'), findsOneWidget);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsOneWidget);
    expect(platform.sources.single.sourceType, DataSourceType.file);
    expect(platform.played, isEmpty);
    await tester
        .tap(find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')));
    await tester.pumpAndSettle();
    expect(find.text('คำอธิบาย YouTube'), findsOneWidget);
    expect(find.text('ชื่อคลิป YouTube'), findsOneWidget);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(platform.sources, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    expect(platform.played, [1]);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
  });

  testWidgets('post preview fills the screen without a bottom control panel',
      (tester) async {
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('post-video-preview-immersive'));
    final systemBar = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find
        .ancestor(
            of: canvas,
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
        .first);
    expect(
        systemBar.value.statusBarIconBrightness,
        const bool.fromEnvironment('POSTDEE_STAGING_BUILD')
            ? Brightness.dark
            : Brightness.light);
    expect(
        tester.getRect(canvas),
        Offset.zero &
            (tester.view.physicalSize / tester.view.devicePixelRatio));
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('เริ่มคลิปใหม่'), findsNothing);
    expect(find.text('0:00 / 0:30'), findsNothing);
    expect(platform.played, isEmpty);
    final tap = find.byKey(const ValueKey('post-video-preview-play'));
    await tester.tap(tap);
    await tester.pump();
    expect(platform.played, [1]);
    final pauses = platform.paused.length;
    await tester.tap(tap);
    await tester.pumpAndSettle();
    expect(platform.paused.length, greaterThan(pauses));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
  });

  testWidgets('immersive status icons remain readable in the outer dark theme',
      (tester) async {
    await tester
        .pumpWidget(_testApp(theme: AppTheme.dark, postPreview: previewData()));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('post-video-preview-immersive'));
    final systemBar = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find
        .ancestor(
            of: canvas,
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
        .first);
    expect(systemBar.value.statusBarIconBrightness, Brightness.light);
    expect(systemBar.value.statusBarBrightness, Brightness.dark);
    expect(systemBar.value.systemNavigationBarIconBrightness, Brightness.light);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
  });

  testWidgets('immersive information pauses without resuming on text or close',
      (tester) async {
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<VideoPlayer>(
            find.byKey(const ValueKey('post-video-preview-player')))
        .controller;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    expect(controller.value.isPlaying, isTrue);
    expect(platform.played, [1]);
    final pausesBeforeInformation = platform.paused.length;

    await tester.tap(find.byKey(const ValueKey('preview-info-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-info-panel')), findsOneWidget);
    expect(controller.value.isPlaying, isFalse);
    expect(platform.paused.length, greaterThan(pausesBeforeInformation));
    await tester.tap(find.text('ส่งเป็นร่างเข้า TikTok'));
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    expect(platform.played, [1]);

    await tester.tap(find.byKey(const ValueKey('preview-info-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-info-panel')), findsNothing);
    expect(controller.value.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(platform.played, [1]);
    expect(platform.sources, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
  });

  testWidgets(
      'immersive volume appears only on demand and closes on canvas tap',
      (tester) async {
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    final volume = find.byKey(const ValueKey('post-video-preview-volume'));
    expect(volume.hitTestable(), findsOneWidget);
    tester.widget<Slider>(volume).onChangeEnd!(.45);
    await tester.pumpAndSettle();
    expect(platform.volumes.last.volume, .45);
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pumpAndSettle();
    expect(volume, findsNothing);
    expect(platform.played, isEmpty);
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(volume).value, .45);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
  });

  testWidgets('immersive volume and metadata disappear after owner revocation',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions
        .signIn(AuthSession.authenticated(userId: 'immersive-a', idToken: 'a'));
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    sessions
        .signIn(AuthSession.authenticated(userId: 'immersive-b', idToken: 'b'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const ValueKey('post-video-preview-immersive')),
        findsNothing);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
  });

  testWidgets('post preview hides local clip and captions after owner ABA',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    final owner = AuthSession.authenticated(
        userId: 'preview-local-owner', idToken: 'local-token');
    sessions.signIn(owner);
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    sessions.signIn(AuthSession.authenticated(
        userId: 'preview-other-owner', idToken: 'other-token'));
    sessions.signIn(owner);
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(find.text('@seller'), findsNothing);
    expect(find.byType(PublishPostPreviewPane), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-player')), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
    expect(platform.disposeCounts, {1: 1});
  });

  testWidgets('post preview rejects a stale caller before creating a player',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    final owner = AuthSession.authenticated(
        userId: 'preview-delayed-owner', idToken: 'local-token');
    sessions.signIn(owner);
    final binding = sessions.captureSession();
    sessions.signIn(AuthSession.authenticated(
        userId: 'preview-other-owner', idToken: 'other-token'));
    sessions.signIn(owner);
    await tester.pumpWidget(
        _testApp(postPreview: previewData(), ownerSession: binding));
    await tester.pumpAndSettle();
    expect(platform.sources, isEmpty);
    expect(find.byType(PublishPostPreviewPane), findsNothing);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
  });

  testWidgets('owner ABA during local post initialization cannot restore media',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    final owner = AuthSession.authenticated(
        userId: 'preview-waiting-owner', idToken: 'local-token');
    sessions.signIn(owner);
    final gate = Completer<void>();
    platform = _PreviewVideoPlatform(firstCreationGate: gate);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pump();
    expect(platform.sources, hasLength(1));
    sessions.signIn(AuthSession.authenticated(
        userId: 'preview-other-owner', idToken: 'other-token'));
    sessions.signIn(owner);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.byType(PublishPostPreviewPane), findsNothing);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(find.text('@seller'), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-player')), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
    expect(platform.disposeCounts, {1: 1});
    expect(platform.played, isEmpty);
  });

  testWidgets('viewing a cover pauses and resuming restores the actual clip',
      (tester) async {
    final data = previewData();
    await tester.pumpWidget(_testApp(
      postPreview: PublishPostPreviewData(
        channels: data.channels,
        caption: data.caption,
        coverImageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),
      ),
    ));
    await tester.pumpAndSettle();
    final video = tester.widget<VideoPlayer>(
        find.byKey(const ValueKey('post-video-preview-player')));
    await video.controller.seekTo(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    expect(video.controller.value.isPlaying, isTrue);
    final pausesBeforeCover = platform.paused.length;
    await tester
        .ensureVisible(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.tap(find.byKey(const ValueKey('preview-cover-toggle')));
    await tester.pumpAndSettle();
    expect(platform.paused.length, greaterThan(pausesBeforeCover));
    expect(video.controller.value.isPlaying, isFalse);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    expect(video.controller.value.isPlaying, isTrue);
    expect(find.byKey(const ValueKey('preview-cover-image')), findsNothing);
    expect(platform.sources, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
  });

  testWidgets('rotating a post preview keeps the same playing controller',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    final controller = tester
        .widget<VideoPlayer>(
            find.byKey(const ValueKey('post-video-preview-player')))
        .controller;
    tester.view.physicalSize = const Size(740, 360);
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(1));
    expect(
        tester
            .widget<VideoPlayer>(
                find.byKey(const ValueKey('post-video-preview-player')))
            .controller,
        same(controller));
    expect(controller.value.isPlaying, isTrue);
    expect(find.byKey(const ValueKey('preview-caption')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(430, 900);
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
  });

  for (final size in [const Size(320, 568), const Size(740, 360)]) {
    testWidgets('post preview keeps playback reachable at $size and text 2',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(_testApp(textScale: 2, postPreview: previewData()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-video-preview-play')),
          findsOneWidget);
      await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('post-video-preview-volume')).hitTestable(),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('post-video-preview-mute')).hitTestable(),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
      await tester.pump();
      expect(platform.played, [1]);
      await tester.pumpWidget(const SizedBox());
      await _settleNativeDisposal(tester);
    });
  }

  testWidgets(
      'network preview plays a verified URL without autoplay and disposes on exit',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(
        AuthSession.authenticated(userId: 'preview-owner', idToken: 'token'));
    final url =
        Uri.parse('https://private-media.test/owned-video?signature=test');
    await tester.pumpWidget(MaterialApp(
        home: PostVideoPreviewScreen.network(
      videoUrl: url,
      videoName: 'คลิปที่ส่งแล้ว',
    )));
    await tester.pumpAndSettle();
    expect(platform.sources.single.sourceType, DataSourceType.network);
    expect(platform.sources.single.uri, url.toString());
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts[1], 1);
  });

  for (final rawUrl in [
    'javascript:alert(1)',
    'https://user:secret@media.test/video',
    'file:///private/video.mp4'
  ]) {
    testWidgets(
        'network preview refuses unsafe media without creating a player: $rawUrl',
        (tester) async {
      final sessions = PostDeeAuthSessionStore.instance;
      final original = sessions.session;
      addTearDown(() => sessions.signIn(original));
      sessions.signIn(
          AuthSession.authenticated(userId: 'preview-owner', idToken: 'token'));
      await tester.pumpWidget(MaterialApp(
          home: PostVideoPreviewScreen.network(
        videoUrl: Uri.parse(rawUrl),
        videoName: 'Owned preview',
      )));
      await tester.pumpAndSettle();
      expect(platform.sources, isEmpty);
      expect(find.text('ยังเปิดคลิปไม่ได้'), findsOneWidget);
    });
  }

  testWidgets(
      'network preview revokes playback and retry after the owner changes',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    sessions.signIn(
        AuthSession.authenticated(userId: 'preview-owner', idToken: 'token'));
    await tester.pumpWidget(MaterialApp(
        home: PostVideoPreviewScreen.network(
      videoUrl: Uri.parse('https://media.test/owned?signature=test'),
      videoName: 'Owned preview',
    )));
    await tester.pumpAndSettle();
    sessions.signIn(AuthSession.authenticated(
        userId: 'another-owner', idToken: 'other-token'));
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(
        find.byKey(const ValueKey('post-video-preview-player')), findsNothing);
    expect(
        find.byKey(const ValueKey('post-video-preview-retry')), findsNothing);
    expect(platform.disposeCounts[1], 1);
  });

  for (final mode in ['reduced', 'ticker', 'background']) {
    for (final phase in ['waiting', 'created']) {
      testWidgets('motion audit $mode keeps $phase preview loading static',
          (tester) async {
        addTearDown(() => _resumePreviewMotion(tester));
        _resumePreviewMotion(tester);
        final gate = Completer<void>();
        platform = _PreviewVideoPlatform(firstCreationGate: gate);
        VideoPlayerPlatform.instance = platform;
        if (phase == 'created' && mode == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        }
        await tester.pumpWidget(_testApp(
            reducedMotion: phase == 'created' && mode == 'reduced',
            tickerEnabled: phase != 'created' || mode != 'ticker'));
        if (phase == 'created' && mode == 'background') {
          // The binding suppresses new frames while paused. Force only the
          // mounting frame to exercise a screen created in that lifecycle.
          tester.binding.scheduleForcedFrame();
        }
        await tester.pump();
        if (phase == 'waiting') {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 40));
          if (mode == 'background') {
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.paused);
            await tester.pump();
          } else {
            await tester.pumpWidget(_testApp(
                reducedMotion: mode == 'reduced',
                tickerEnabled: mode != 'ticker'));
          }
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
        expect(find.text('กำลังเปิดคลิป…'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(platform.sources, hasLength(1));
        expect(platform.played, isEmpty);
        if (mode == 'background') {
          _resumePreviewMotion(tester);
          await tester.pump();
        } else {
          await tester.pumpWidget(_testApp());
        }
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(platform.sources, hasLength(1),
            reason: 'A motion setting must not recreate the video controller.');
        gate.complete();
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('fake-preview-video-1')), findsOneWidget);
        expect(platform.played, isEmpty);
        await tester.tap(find.byTooltip('เล่นคลิป'));
        await tester.pump();
        expect(platform.played, [1]);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _settleNativeDisposal(tester);
        expect(platform.disposeCounts, {1: 1});
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opens the local file fitted without autoplay and plays on tap',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(platform.sources.single.sourceType, DataSourceType.file);
    expect(platform.sources.single.uri, contains('local-selected-clip.mp4'));
    expect(platform.played, isEmpty);
    expect(find.text('ดูคลิป'), findsOneWidget);
    expect(find.text('คลิปสินค้าของฉัน.mp4'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-preview-video-1')), findsOneWidget);
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, 9 / 16);

    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    expect(platform.played, [1]);
    expect(find.byTooltip('หยุดคลิป'), findsOneWidget);
    await tester.tap(find.byTooltip('หยุดคลิป'));
    await tester.pump();
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
  });

  testWidgets('seeks and restarts without automatically playing',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('post-video-preview-seek')),
    );
    expect(slider.max, 30000);
    slider.onChangeStart!(15000);
    slider.onChanged!(15000);
    slider.onChangeEnd!(15000);
    await tester.pumpAndSettle();
    expect(platform.seeks.last, const Duration(seconds: 15));
    expect(find.text('0:15 / 0:30'), findsOneWidget);
    expect(platform.played, isEmpty);

    await tester.tap(find.byTooltip('เริ่มคลิปใหม่'));
    await tester.pumpAndSettle();
    expect(platform.seeks.last, Duration.zero);
    expect(find.text('0:00 / 0:30'), findsOneWidget);
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('preview volume commits one slider value and mute restores it',
      (tester) async {
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    final initialCalls = platform.volumes.length;
    final volume = find.byKey(const ValueKey('post-video-preview-volume'));
    var slider = tester.widget<Slider>(volume);
    slider.onChanged!(.65);
    slider.onChanged!(.35);
    await tester.pump();
    expect(platform.volumes.length, initialCalls);
    expect(tester.widget<Slider>(volume).value, .35);
    slider.onChangeEnd!(.35);
    await tester.pumpAndSettle();
    expect(platform.volumes.last, (playerId: 1, volume: .35));
    expect(find.text('35%'), findsOneWidget);
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(platform.volumes.last.volume, 0);
    expect(tester.widget<Slider>(volume).value, 0);
    await tester.tap(find.byTooltip('เปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(platform.volumes.last.volume, .35);
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(volume).value, .35);
    expect(platform.sources, hasLength(1));
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('muted preview stays muted after decoder retry', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    platform.events[1]!.addError(
        PlatformException(code: 'decoder-error', message: 'Decoder stopped'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลองเปิดคลิปอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(platform.volumes.last, (playerId: 2, volume: 0.0));
    expect(find.byTooltip('เปิดเสียงพรีวิว'), findsOneWidget);
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('failed volume change pauses and leaves controls recoverable',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    platform.failNextVolume = true;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(find.text('ยังปรับเสียงไม่ได้ ลองอีกครั้ง'), findsOneWidget);
    expect(find.byTooltip('ปิดเสียงพรีวิว'), findsOneWidget);
    expect(platform.paused, contains(1));
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('เปิดเสียงพรีวิว'), findsOneWidget);
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('late volume completion cannot change a replacement clip',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    platform.volumeGate = gate;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pump();
    platform.volumeGate = null;
    await tester.pumpWidget(_testApp(videoPath: 'replacement-clip.mp4'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('ปิดเสียงพรีวิว'), findsOneWidget);
    expect(
        tester
            .widget<Slider>(
                find.byKey(const ValueKey('post-video-preview-volume')))
            .value,
        1);
    expect(platform.sources, hasLength(2));
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1, 2: 1});
  });

  testWidgets('stalled volume times out and can be retried without playback',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    platform.volumeGate = gate;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('ยังปรับเสียงไม่ได้ ลองอีกครั้ง'), findsOneWidget);
    expect(
        tester
            .widget<Slider>(
                find.byKey(const ValueKey('post-video-preview-volume')))
            .onChanged,
        isNotNull);
    platform.volumeGate = null;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('เปิดเสียงพรีวิว'), findsOneWidget);
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('owner ABA revokes controls during a pending volume request',
      (tester) async {
    final sessions = PostDeeAuthSessionStore.instance;
    final original = sessions.session;
    addTearDown(() => sessions.signIn(original));
    final owner = AuthSession.authenticated(
        idToken: 'volume-token', userId: 'volume-owner', displayName: 'A');
    sessions.signIn(owner);
    await tester.pumpWidget(_testApp(postPreview: previewData()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ปรับเสียงพรีวิว'));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    platform.volumeGate = gate;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pump();
    sessions.signIn(AuthSession.authenticated(
        idToken: 'other-token', userId: 'other', displayName: 'B'));
    sessions.signIn(owner);
    gate.complete();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(
        find.byKey(const ValueKey('post-video-preview-volume')), findsNothing);
    expect(find.text('ข้อความเฉพาะ TikTok'), findsNothing);
    expect(platform.disposeCounts, {1: 1});
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a timed out volume restore cannot start playing later',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    platform.failNextVolume = true;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    platform.volumeGate = gate;
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('ยังเล่นคลิปไม่ได้ ลองอีกครั้ง'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(platform.played, isEmpty);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'backgrounding permanently cancels a pending playback continuation',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    platform.failNextVolume = true;
    await tester.tap(find.byTooltip('ปิดเสียงพรีวิว'));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    platform.volumeGate = gate;
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(platform.played, isEmpty);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('background pauses playback and retains preview volume on resume',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    final volume = find.byKey(const ValueKey('post-video-preview-volume'));
    tester.widget<Slider>(volume).onChangeEnd!(.4);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.widget<Slider>(volume).onChanged, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.widget<Slider>(volume).value, .4);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    expect(platform.played, [1]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('pauses in the background and stays paused after returning',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    expect(platform.paused, contains(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.played, [1]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('shows an actionable initialization failure and retries locally',
      (tester) async {
    platform = _PreviewVideoPlatform(failFirstInitialization: true);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    expect(find.text('ยังเปิดคลิปไม่ได้'), findsOneWidget);
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});

    await tester.tap(find.text('ลองเปิดคลิปอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);
    expect(platform.sources, hasLength(2));
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1, 2: 1});
  });

  testWidgets('times out a stalled player and ignores its late result on retry',
      (tester) async {
    final creationGate = Completer<void>();
    platform = _PreviewVideoPlatform(firstCreationGate: creationGate);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text('ยังเปิดคลิปไม่ได้'), findsOneWidget);
    await tester.tap(find.text('ลองเปิดคลิปอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);

    creationGate.complete();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.byKey(const ValueKey('fake-preview-video-1')), findsNothing);
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);
    expect(platform.disposeCounts[1], 1);
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1, 2: 1});
  });

  testWidgets('releases a player that finishes initializing after exit once',
      (tester) async {
    final creationGate = Completer<void>();
    platform = _PreviewVideoPlatform(firstCreationGate: creationGate);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    creationGate.complete();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
    expect(platform.played, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'replaces the local file without allowing a stale player to return',
      (tester) async {
    final creationGate = Completer<void>();
    platform = _PreviewVideoPlatform(firstCreationGate: creationGate);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pumpWidget(_testApp(videoPath: 'replacement-clip.mp4'));
    await tester.pumpAndSettle();
    expect(platform.sources.last.uri, contains('replacement-clip.mp4'));
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);

    creationGate.complete();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.byKey(const ValueKey('fake-preview-video-1')), findsNothing);
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);
    expect(platform.disposeCounts, {1: 1});
    expect(platform.played, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1, 2: 1});
  });

  testWidgets('recovers from a decoder error while playing without autoplay',
      (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    platform.events[1]!.addError(
      PlatformException(code: 'decoder-error', message: 'Decoder stopped'),
    );
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.text('ยังเปิดคลิปไม่ได้'), findsOneWidget);
    expect(platform.disposeCounts, {1: 1});

    await tester.tap(find.text('ลองเปิดคลิปอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-preview-video-2')), findsOneWidget);
    expect(platform.played, [1]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1, 2: 1});
  });

  testWidgets('keeps controls usable when a play command fails',
      (tester) async {
    platform = _PreviewVideoPlatform(failFirstPlay: true);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pumpAndSettle();
    expect(find.text('ยังเล่นคลิปไม่ได้ ลองอีกครั้ง'), findsOneWidget);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);

    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    expect(platform.played, [1, 1]);
    expect(find.byTooltip('หยุดคลิป'), findsOneWidget);
    expect(find.text('ยังเล่นคลิปไม่ได้ ลองอีกครั้ง'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(platform.disposeCounts, {1: 1});
  });

  testWidgets('stays usable on a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_testApp(textScale: 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    expect(find.byTooltip('เริ่มคลิปใหม่'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('post-video-preview-seek')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'back returns to the composer and pauses then disposes the player',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PostVideoPreviewScreen(
                      videoFile: File('local-selected-clip.mp4'),
                      videoName: 'คลิป.mp4',
                    ),
                  )),
                  child: const Text('สร้างโพสต์'),
                ),
              )),
    ));
    await tester.tap(find.text('สร้างโพสต์'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('เล่นคลิป'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _settleNativeDisposal(tester);
    expect(find.text('สร้างโพสต์'), findsOneWidget);
    expect(platform.paused, contains(1));
    expect(platform.disposeCounts, {1: 1});
  });
}
