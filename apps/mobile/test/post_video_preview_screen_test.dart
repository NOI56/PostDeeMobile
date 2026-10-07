import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/theme/app_theme.dart';
import 'package:postdee_mobile/features/uploader/post_video_preview_screen.dart';
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
  Future<void> setVolume(int playerId, double volume) async {}

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
  double textScale = 1,
  String videoPath = 'local-selected-clip.mp4',
}) =>
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: PostVideoPreviewScreen(
        videoFile: File(videoPath),
        videoName: 'คลิปสินค้าของฉัน.mp4',
      ),
    );

Future<void> _settleNativeDisposal(WidgetTester tester) async {
  // video_player cancels its event subscription asynchronously on disposal.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
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
