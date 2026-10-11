import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/home/home_draft_thumbnail.dart';
import 'package:video_player/video_player.dart';

class _DraftController extends VideoPlayerController {
  _DraftController({this.gate, this.fail = false})
      : super.asset('test-draft.mp4');
  final Completer<void>? gate;
  final bool fail;
  var disposed = false;
  var playCalls = 0;
  double? volume;
  Duration? sought;

  @override
  Future<void> initialize() async {
    await gate?.future;
    if (disposed) return;
    if (fail) throw StateError('decoder failed');
    value = const VideoPlayerValue(
      duration: Duration(seconds: 32),
      size: Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> setVolume(double nextVolume) async {
    volume = nextVolume;
    value = value.copyWith(volume: nextVolume);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async {
    sought = position;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await super.dispose();
  }
}

Widget _app(HomeDraftThumbnail child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 320, height: 128, child: child)),
    );

void main() {
  testWidgets('saved covers skip native decoding completely', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/own/clip.mp4',
      coverPath: '/drafts/own/cover.png',
      createController: (_) {
        calls++;
        return _DraftController();
      },
    )));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, '/drafts/own/cover.png');
    expect(calls, 0);
    // Dispose before nonexistent test-only image decoding finishes.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('draft preview uses its local file, muted and paused first frame',
      (tester) async {
    final controller = _DraftController();
    File? source;
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/own/clip.mp4',
      createController: (file) {
        source = file;
        return controller;
      },
    )));
    await tester.pumpAndSettle();
    expect(source?.path, '/drafts/own/clip.mp4');
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(controller.volume, 0);
    expect(controller.sought, Duration.zero);
    expect(controller.playCalls, 0);
    expect(controller.value.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.disposed, isTrue);
  });

  testWidgets('a corrupt saved cover falls back to the muted local frame',
      (tester) async {
    final fixture = await tester.runAsync(
        () => Directory.systemTemp.createTemp('postdee-home-bad-cover-'));
    final cover = File('${fixture!.path}/cover.png');
    await tester.runAsync(() => cover.writeAsString('not an image'));
    final controller = _DraftController();
    var calls = 0;
    File? source;
    try {
      await tester.pumpWidget(_app(HomeDraftThumbnail(
        videoPath: '${fixture.path}/clip.mp4',
        coverPath: cover.path,
        createController: (file) {
          calls++;
          source = file;
          return controller;
        },
      )));
      // FileImage decodes through real I/O rather than the widget fake clock.
      for (var attempt = 0; attempt < 50 && calls == 0; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(source?.path, '${fixture.path}/clip.mp4');
      expect(find.byKey(const ValueKey('home-draft-cover')), findsNothing);
      expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          same(controller));
      expect(controller.volume, 0);
      expect(controller.sought, Duration.zero);
      expect(controller.value.isPlaying, isFalse);
      expect(controller.playCalls, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await cover.delete();
        await fixture.delete();
      });
    }
    expect(controller.disposed, isTrue);
  });

  testWidgets('background disposes pending frames and resume starts a new one',
      (tester) async {
    final pendingFrame = Completer<void>();
    final oldController = _DraftController(gate: pendingFrame);
    final resumedController = _DraftController();
    var calls = 0;
    try {
      await tester.pumpWidget(_app(HomeDraftThumbnail(
        videoPath: '/drafts/own/clip.mp4',
        createController: (_) =>
            ++calls == 1 ? oldController : resumedController,
      )));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(oldController.disposed, isTrue);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          same(resumedController));
      expect(resumedController.volume, 0);
      expect(resumedController.sought, Duration.zero);
      expect(resumedController.value.isPlaying, isFalse);
      expect(resumedController.playCalls, 0);

      pendingFrame.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          same(resumedController));
      expect(oldController.volume, isNull);
      expect(oldController.sought, isNull);
      expect(tester.takeException(), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(resumedController.disposed, isTrue);
      // A paused app stops painting frames; disposal is the resource guarantee.
      expect(calls, 2);
    } finally {
      if (!pendingFrame.isCompleted) pendingFrame.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }
  });

  testWidgets('decoder errors and timeouts leave a usable static fallback',
      (tester) async {
    for (final timedOut in [false, true]) {
      final gate = timedOut ? Completer<void>() : null;
      final controller = _DraftController(gate: gate, fail: !timedOut);
      await tester.pumpWidget(_app(HomeDraftThumbnail(
        key: ValueKey(timedOut),
        videoPath: '/drafts/own/clip.mp4',
        createController: (_) => controller,
      )));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byIcon(Icons.video_file_outlined), findsOneWidget);
      expect(controller.disposed, isTrue);
      gate?.complete();
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('inactive home disposes decoder and ignores late frame',
      (tester) async {
    final gate = Completer<void>();
    final controller = _DraftController(gate: gate);
    VideoPlayerController factory(File _) => controller;
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/own/clip.mp4',
      createController: factory,
    )));
    await tester.pump();
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/own/clip.mp4',
      isActive: false,
      createController: factory,
    )));
    expect(controller.disposed, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed owner or draft never renders a late old frame',
      (tester) async {
    final gate = Completer<void>();
    final oldController = _DraftController(gate: gate);
    final currentController = _DraftController();
    VideoPlayerController factory(File file) =>
        file.path.contains('/old/') ? oldController : currentController;
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/old/clip.mp4',
      createController: factory,
    )));
    await tester.pump();
    await tester.pumpWidget(_app(HomeDraftThumbnail(
      videoPath: '/drafts/new/clip.mp4',
      createController: factory,
    )));
    await tester.pumpAndSettle();
    expect(oldController.disposed, isTrue);
    expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(currentController));
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(currentController));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
