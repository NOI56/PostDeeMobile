import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/auth/auth_session.dart';
import 'package:postdee_mobile/core/localization/postdee_localizations.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/platforms/social_platform.dart';
import 'package:postdee_mobile/features/uploader/post_video_preview_screen.dart';
import 'package:postdee_mobile/features/uploader/publish_post_preview.dart';
// Replaces video_player's native platform implementation for these tests.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class PreviewEnglishPlatform extends VideoPlayerPlatform {
  bool failFirstInitialization = false;
  bool failNextPlay = false;
  bool failNextVolume = false;
  Completer<void>? firstCreationGate;
  Completer<void>? volumeGate;
  Completer<void>? seekGate;
  Duration duration = const Duration(seconds: 30);
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final disposeCounts = <int, int>{};
  final positions = <int, Duration>{};
  final played = <int>[];
  final paused = <int>[];
  final seeks = <Duration>[];
  final volumes = <({int playerId, double volume})>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = sources.length + 1;
    sources.add(options.dataSource);
    if (playerId == 1) await firstCreationGate?.future;
    positions[playerId] = Duration.zero;
    events[playerId] = StreamController<VideoEvent>(onListen: () {
      if (failFirstInitialization && playerId == 1) {
        events[playerId]!.addError(PlatformException(
            code: 'fake-invalid-video', message: 'Fake invalid video'));
      } else {
        events[playerId]!.add(VideoEvent(
            eventType: VideoEventType.initialized,
            duration: duration,
            size: const Size(1080, 1920)));
      }
    });
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
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add((playerId: playerId, volume: volume));
    if (failNextVolume) {
      failNextVolume = false;
      throw StateError('fake volume unavailable');
    }
    await volumeGate?.future;
  }

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
    if (failNextPlay) {
      failNextPlay = false;
      throw StateError('fake play unavailable');
    }
  }

  @override
  Future<void> pause(int playerId) async => paused.add(playerId);
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    await seekGate?.future;
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
      key: ValueKey('preview-english-player-${options.playerId}'),
      color: Colors.blue);
}

final previewEnglishData =
    PublishPostPreviewData(caption: 'แคปชันหลักของลูกค้า', channels: [
  PublishPostPreviewChannel(
      platform: SocialPlatform.tiktok,
      caption: 'แคปชัน TikTok ของลูกค้า',
      displayName: 'ร้าน TikTok ภาษาไทย'),
  PublishPostPreviewChannel(
      platform: SocialPlatform.youtubeShorts,
      caption: 'คำอธิบาย YouTube ภาษาไทย',
      displayName: 'ช่องของลูกค้า',
      title: 'ชื่อวิดีโอที่ลูกค้าตั้งเอง'),
]);

class PreviewEnglishFixture {
  PreviewEnglishFixture(
      {Locale locale = const Locale('en'),
      this.dark = false,
      this.scale = 1,
      this.immersive = false})
      : language = ValueNotifier(locale);
  final ValueNotifier<Locale> language;
  final bool dark;
  final double scale;
  final bool immersive;
  final platform = PreviewEnglishPlatform();
  String localPath = 'fake-selected-preview.mp4';
  String videoName = 'คลิปสินค้าของฉัน.mp4';
  Uri? networkUrl;
  AuthSessionBinding? ownerSession;
  bool reducedMotion = true;
  bool tickerEnabled = true;
  bool bareMaterialApp = false;
  PublishPostPreviewData data = previewEnglishData;
  VideoPlayerPlatform? _previousPlatform;

  Widget screen() => networkUrl == null
      ? PostVideoPreviewScreen(
          videoFile: File(localPath),
          videoName: videoName,
          postPreview: immersive ? data : null,
          ownerSession: ownerSession)
      : PostVideoPreviewScreen.network(
          videoUrl: networkUrl!, videoName: videoName);

  Widget app() => ValueListenableBuilder<Locale>(
      valueListenable: language,
      builder: (_, locale, __) {
        AppTheme.applyThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        return MaterialApp(
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
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: reducedMotion),
                child: TickerMode(enabled: tickerEnabled, child: child!)),
            home: screen());
      });

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    _previousPlatform ??= VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(app());
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  void dispose() {
    if (_previousPlatform != null) {
      VideoPlayerPlatform.instance = _previousPlatform!;
    }
    language.dispose();
  }
}

Future<void> loadPreviewEnglishFonts() async {
  final loader = FontLoader('Anuphan');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/anuphan/Anuphan-$weight.ttf'));
  }
  await loader.load();
}

void expectPreviewEnglishReadable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first);
  final details =
      '${tester.widget<Text>(finder).data}: size=${paragraph.size}, '
      'intrinsicWidth=${paragraph.getMaxIntrinsicWidth(double.infinity)}, '
      'rect=${tester.getRect(finder)}';
  expect(paragraph.didExceedMaxLines, isFalse, reason: details);
  expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width) - .5),
      reason: details);
}

void main() {
  late AuthSession previous;
  setUpAll(loadPreviewEnglishFonts);
  setUp(() {
    previous = PostDeeAuthSessionStore.instance.session;
    PostDeeAuthSessionStore.instance
        .signIn(const AuthSession(userId: 'preview-english-owner'));
  });
  tearDown(() => PostDeeAuthSessionStore.instance.signIn(previous));

  testWidgets(
      'English basic preview labels controls and keeps the raw Thai filename',
      (tester) async {
    final fixture = PreviewEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Watch video'), findsOneWidget);
    expect(find.text('คลิปสินค้าของฉัน.mp4'), findsOneWidget);
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(find.byTooltip('Restart video'), findsOneWidget);
    expect(find.byTooltip('Mute preview'), findsOneWidget);
    expect(fixture.platform.sources.single.sourceType, DataSourceType.file);
    expect(fixture.platform.played, isEmpty);
  });

  testWidgets('English loading follows locale without creating another player',
      (tester) async {
    final gate = Completer<void>();
    final fixture = PreviewEnglishFixture(locale: const Locale('th'));
    fixture.platform.firstCreationGate = gate;
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester, settle: false);
    expect(find.text('กำลังเปิดคลิป…'), findsOneWidget);
    fixture.language.value = const Locale('en');
    await tester.pump();
    expect(find.text('Opening video…'), findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-video-preview-player')),
        findsOneWidget);
  });

  testWidgets('English initialization failure offers an actionable local retry',
      (tester) async {
    final fixture = PreviewEnglishFixture();
    fixture.platform.failFirstInitialization = true;
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Could not open this video'), findsOneWidget);
    expect(
        find.text('Try opening it again, or go back and choose another video.'),
        findsOneWidget);
    expect(find.text('Try opening the video again'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-video-preview-retry')));
    await tester.pumpAndSettle();
    expect(fixture.platform.sources, hasLength(2));
    expect(find.byKey(const ValueKey('post-video-preview-player')),
        findsOneWidget);
    expect(fixture.platform.played, isEmpty);
  });

  testWidgets(
      'English play and pause names follow actual playback without autoplay',
      (tester) async {
    final fixture = PreviewEnglishFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    await tester.tap(find.byTooltip('Play video'));
    await tester.pump();
    expect(fixture.platform.played, [1]);
    expect(find.byTooltip('Pause video'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause video'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(fixture.platform.paused, contains(1));
    expect(fixture.platform.sources, hasLength(1));
  });

  testWidgets(
      'ready controls change locale while keeping the same player and filename',
      (tester) async {
    final fixture = PreviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    final calls = fixture.platform.volumes.length;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(find.byTooltip('Mute preview'), findsOneWidget);
    expect(find.text('คลิปสินค้าของฉัน.mp4'), findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    expect(fixture.platform.volumes.length, calls);
    expect(fixture.platform.disposeCounts, isEmpty);
    expect(fixture.platform.played, isEmpty);
  });

  testWidgets(
      'English timeline semantics preserve exact duration and restart without playing',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = PreviewEnglishFixture();
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      final seek = find.byKey(const ValueKey('post-video-preview-seek'));
      var slider = tester.widget<Slider>(seek);
      expect(tester.getSemantics(seek).label, contains('Seek video'));
      expect(slider.max, 30000);
      expect(slider.semanticFormatterCallback!(15000), '0:15');
      slider.onChangeStart!(15000);
      slider.onChanged!(15000);
      slider.onChangeEnd!(15000);
      await tester.pumpAndSettle();
      expect(fixture.platform.seeks.last, const Duration(seconds: 15));
      expect(find.text('0:15 / 0:30'), findsOneWidget);
      await tester.tap(find.byTooltip('Restart video'));
      await tester.pumpAndSettle();
      expect(fixture.platform.seeks.last, Duration.zero);
      expect(find.text('0:00 / 0:30'), findsOneWidget);
      slider = tester.widget<Slider>(seek);
      expect(slider.value, 0);
      expect(fixture.platform.played, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'English volume semantics and mute restore the committed per-player gain',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = PreviewEnglishFixture();
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      final volume = find.byKey(const ValueKey('post-video-preview-volume'));
      final slider = tester.widget<Slider>(volume);
      expect(tester.getSemantics(volume).label, contains('Preview volume'));
      expect(slider.semanticFormatterCallback!(0), '0 percent');
      expect(slider.semanticFormatterCallback!(1), '100 percent');
      final calls = fixture.platform.volumes.length;
      slider.onChanged!(.35);
      await tester.pump();
      expect(fixture.platform.volumes.length, calls);
      slider.onChangeEnd!(.35);
      await tester.pumpAndSettle();
      expect(fixture.platform.volumes.last, (playerId: 1, volume: .35));
      expect(find.text('35%'), findsOneWidget);
      await tester.tap(find.byTooltip('Mute preview'));
      await tester.pumpAndSettle();
      expect(fixture.platform.volumes.last, (playerId: 1, volume: 0));
      expect(find.byTooltip('Unmute preview'), findsOneWidget);
      await tester.tap(find.byTooltip('Unmute preview'));
      await tester.pumpAndSettle();
      expect(fixture.platform.volumes.last, (playerId: 1, volume: .35));
      expect(fixture.platform.played, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'stored play failure changes language without another play command',
      (tester) async {
    final fixture = PreviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    fixture.platform.failNextPlay = true;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pumpAndSettle();
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not play this video. Try again.'), findsOneWidget);
    expect(find.text('คลิปสินค้าของฉัน.mp4'), findsOneWidget);
    expect(fixture.platform.played, [1]);
    expect(fixture.platform.sources, hasLength(1));
    expect(find.byTooltip('Play video'), findsOneWidget);
  });

  testWidgets(
      'stored volume failure changes language without another volume command',
      (tester) async {
    final fixture = PreviewEnglishFixture(locale: const Locale('th'));
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    fixture.platform.failNextVolume = true;
    await tester.tap(find.byKey(const ValueKey('post-video-preview-mute')));
    await tester.pumpAndSettle();
    final calls = fixture.platform.volumes.length;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Could not adjust the preview volume. Try again.'),
        findsOneWidget);
    expect(fixture.platform.volumes.length, calls);
    expect(fixture.platform.sources, hasLength(1));
    expect(fixture.platform.played, isEmpty);
  });

  testWidgets('plain MaterialApp retains original Thai player controls',
      (tester) async {
    final fixture = PreviewEnglishFixture()..bareMaterialApp = true;
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('ดูคลิป'), findsOneWidget);
    expect(find.byTooltip('เล่นคลิป'), findsOneWidget);
    expect(find.byTooltip('ปิดเสียงพรีวิว'), findsOneWidget);
    expect(find.text('Watch video'), findsNothing);
  });

  testWidgets(
      'immersive English controls preserve raw channel caption and title',
      (tester) async {
    final fixture = PreviewEnglishFixture(immersive: true);
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('แคปชัน TikTok ของลูกค้า'), findsOneWidget);
    expect(find.byTooltip('Adjust preview volume'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-video-preview-seek')), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('preview-platform-YOUTUBE_SHORTS')));
    await tester.pumpAndSettle();
    expect(find.text('คำอธิบาย YouTube ภาษาไทย'), findsOneWidget);
    expect(find.text('ชื่อวิดีโอที่ลูกค้าตั้งเอง'), findsOneWidget);
    expect(fixture.platform.sources, hasLength(1));
    expect(fixture.platform.played, isEmpty);
  });

  testWidgets(
      'immersive locale switch preserves playing state and preview gain',
      (tester) async {
    final fixture =
        PreviewEnglishFixture(locale: const Locale('th'), immersive: true);
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    await tester
        .tap(find.byKey(const ValueKey('post-video-preview-volume-toggle')));
    await tester.pumpAndSettle();
    final volume = tester.widget<Slider>(
        find.byKey(const ValueKey('post-video-preview-volume')));
    volume.onChanged!(.45);
    volume.onChangeEnd!(.45);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('post-video-preview-volume-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-video-preview-play')));
    await tester.pump();
    final calls = fixture.platform.volumes.length;
    fixture.language.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    expect(fixture.platform.played, [1]);
    expect(fixture.platform.volumes.length, calls);
    expect(fixture.platform.volumes.last, (playerId: 1, volume: .45));
    expect(fixture.platform.sources, hasLength(1));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == 'Pause video'),
        findsOneWidget);
  });

  testWidgets(
      'long numeric durations preserve the existing minute-second format',
      (tester) async {
    final fixture = PreviewEnglishFixture();
    fixture.platform.duration =
        const Duration(hours: 1, minutes: 1, seconds: 1);
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('0:00 / 61:01'), findsOneWidget);
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('post-video-preview-seek')));
    expect(slider.max, 3661000);
    expect(slider.semanticFormatterCallback!(3661000), '61:01');
  });

  testWidgets(
      'a raw filename equal to a Thai interface key is never translated',
      (tester) async {
    final fixture = PreviewEnglishFixture()..videoName = 'ดูคลิป';
    addTearDown(fixture.dispose);
    addTearDown(() => fixture.close(tester));
    await fixture.mount(tester);
    expect(find.text('Watch video'), findsOneWidget);
    expect(find.text('ดูคลิป'), findsOneWidget);
    expect(fixture.platform.sources.single.uri, contains(fixture.localPath));
  });

  for (final dark in [false, true]) {
    for (final immersive in [false, true]) {
      testWidgets(
          'narrow real-font 2x ${immersive ? 'immersive' : 'basic'} controls remain readable ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture =
            PreviewEnglishFixture(dark: dark, scale: 2, immersive: immersive);
        addTearDown(fixture.dispose);
        addTearDown(() => fixture.close(tester));
        await fixture.mount(tester);
        expectPreviewEnglishReadable(
            tester, find.text(immersive ? 'Preview' : 'Watch video'));
        if (immersive) {
          await tester.tap(find.byTooltip('Adjust preview volume'));
          await tester.pumpAndSettle();
        } else {
          expectPreviewEnglishReadable(tester, find.text('0:00 / 0:30'));
          final seek = find.byKey(const ValueKey('post-video-preview-seek'));
          expect(seek.hitTestable(), findsOneWidget);
          expect(tester.getSize(seek).height, greaterThanOrEqualTo(48));
          await tester.drag(seek, const Offset(45, 0));
          await tester.pumpAndSettle();
          expect(fixture.platform.seeks.last, greaterThan(Duration.zero));
          await tester.tap(find.byTooltip('Restart video'));
          await tester.pumpAndSettle();
        }
        expectPreviewEnglishReadable(tester, find.text('100%'));
        final percent = tester.getRect(find.text('100%'));
        expect(percent.left, greaterThanOrEqualTo(0));
        expect(percent.right, lessThanOrEqualTo(320));
        final volume = find.byKey(const ValueKey('post-video-preview-volume'));
        expect(volume.hitTestable(), findsOneWidget);
        expect(tester.getSize(volume).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(volume).width, greaterThanOrEqualTo(48));
        await tester.drag(volume, const Offset(-45, 0));
        await tester.pumpAndSettle();
        expect(fixture.platform.volumes.last.playerId, 1);
        expect(fixture.platform.volumes.last.volume, inInclusiveRange(0, 1));
        expect(fixture.platform.volumes.last.volume, lessThan(1));
        expect(fixture.platform.sources, hasLength(1));
        expect(fixture.platform.played, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'narrow real-font 2x initialization error is actionable ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = PreviewEnglishFixture(dark: dark, scale: 2);
      fixture.platform.failFirstInitialization = true;
      addTearDown(fixture.dispose);
      addTearDown(() => fixture.close(tester));
      await fixture.mount(tester);
      for (final value in [
        'Could not open this video',
        'Try opening it again, or go back and choose another video.',
        'Try opening the video again'
      ]) {
        final text = find.text(value);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expectPreviewEnglishReadable(tester, text);
      }
      final retry = find.byKey(const ValueKey('post-video-preview-retry'));
      expect(retry.hitTestable(), findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-video-preview-player')),
          findsOneWidget);
      expect(fixture.platform.sources, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }
}
