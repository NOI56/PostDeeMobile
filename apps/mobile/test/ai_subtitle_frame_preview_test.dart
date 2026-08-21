import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_subtitle_frame_preview.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';

class _FakeFrameController implements AiSubtitleFrameController {
  _FakeFrameController({
    required this.id,
    required this.fakeDuration,
    this.fakeEncodedSize = const Size(1080, 1920),
    this.fakeRotationCorrectionDegrees = 0,
    this.initializeGate,
    this.disposeGate,
    this.failInitialize = false,
  });

  final String id;
  final Duration fakeDuration;
  final Size fakeEncodedSize;
  final int fakeRotationCorrectionDegrees;
  final Completer<void>? initializeGate;
  final Completer<void>? disposeGate;
  final bool failInitialize;

  final List<Duration> seeks = <Duration>[];
  final List<String> calls = <String>[];
  Completer<void>? nextSeekGate;
  bool disposed = false;
  int disposeCalls = 0;
  int activeSeeks = 0;
  int maximumActiveSeeks = 0;

  @override
  Duration get duration => fakeDuration;

  @override
  Size get encodedSize => fakeEncodedSize;

  @override
  int get rotationCorrectionDegrees => fakeRotationCorrectionDegrees;

  @override
  Widget buildView() => ColoredBox(
        key: ValueKey('fake-frame-view-$id'),
        color: Colors.blue,
      );

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    await initializeGate?.future;
    if (failInitialize) throw StateError('initialize failed');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    seeks.add(position);
    activeSeeks += 1;
    if (activeSeeks > maximumActiveSeeks) {
      maximumActiveSeeks = activeSeeks;
    }
    final gate = nextSeekGate;
    nextSeekGate = null;
    try {
      await gate?.future;
    } finally {
      activeSeeks -= 1;
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    calls.add('dispose');
    await disposeGate?.future;
    disposed = true;
  }
}

Widget _testApp({
  required File source,
  required AiSubtitleFrameControllerFactory controllerFactory,
  AiSubtitleFramePreviewSession? session,
  String? sourceFingerprint,
  Size? displaySizeHint,
  Duration seekThrottle = const Duration(milliseconds: 110),
  AiSubtitleFrameOverlayBuilder? overlayBuilder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          child: AiSubtitleFramePreview(
            sourceFile: source,
            sourceFingerprint: sourceFingerprint,
            controllerFactory: controllerFactory,
            session: session,
            displaySizeHint: displaySizeHint,
            seekThrottle: seekThrottle,
            overlayBuilder: overlayBuilder,
          ),
        ),
      ),
    ),
  );
}

Slider _slider(WidgetTester tester) => tester.widget<Slider>(
      find.byKey(const ValueKey('ai-subtitle-frame-slider')),
    );

void main() {
  test('normalizes display size after clockwise rotation metadata', () {
    expect(
      displayOrientedFrameSize(const Size(1920, 1080), 90),
      const Size(1080, 1920),
    );
    expect(
      displayOrientedFrameSize(const Size(1920, 1080), -90),
      const Size(1080, 1920),
    );
    expect(
      displayOrientedFrameSize(const Size(1920, 1080), 180),
      const Size(1920, 1080),
    );
    expect(
      subtitleAssCanvasSizeForDisplay(
        displayOrientedFrameSize(const Size(1920, 1080), 90),
      ),
      postDeeSubtitleAssCanvasSize,
    );
    expect(
      subtitleAssCanvasSizeForDisplay(
        displayOrientedFrameSize(const Size(1920, 1080), -90),
      ),
      postDeeSubtitleAssCanvasSize,
    );
  });

  test('uses zero for clips at most 100 ms and keeps an end-frame margin', () {
    expect(maxSelectableSubtitleFramePosition(const Duration(milliseconds: 80)),
        Duration.zero);
    expect(
      maxSelectableSubtitleFramePosition(const Duration(seconds: 20)),
      const Duration(milliseconds: 19900),
    );
  });

  testWidgets('pauses at the midpoint and exposes display-oriented content',
      (tester) async {
    final controller = _FakeFrameController(
      id: 'rotated',
      fakeDuration: const Duration(seconds: 20),
      fakeEncodedSize: const Size(1920, 1080),
      fakeRotationCorrectionDegrees: 90,
    );
    final session = AiSubtitleFramePreviewSession();
    Size? overlayDisplaySize;

    await tester.pumpWidget(
      _testApp(
        source: File('rotated.mp4'),
        sourceFingerprint: 'rotated-v1',
        controllerFactory: (_) => controller,
        session: session,
        overlayBuilder: (context, displaySize, position) {
          overlayDisplaySize = displaySize;
          return const SizedBox(
            key: ValueKey('subtitle-frame-test-overlay'),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.calls.take(3), ['initialize', 'pause', 'seek:10000']);
    expect(controller.seeks, [const Duration(seconds: 10)]);
    expect(
      session.positionForSource('rotated-v1'),
      const Duration(seconds: 10),
    );
    expect(overlayDisplaySize, const Size(1080, 1920));
    expect(find.byKey(const ValueKey('subtitle-frame-test-overlay')),
        findsOneWidget);
    expect(_slider(tester).value, 10000);

    final contentSize = tester.getSize(
      find.byKey(const ValueKey('ai-subtitle-frame-content')),
    );
    expect(contentSize.width / contentSize.height, closeTo(9 / 16, 0.001));
  });

  testWidgets(
      'keeps the verified display size when the player reports applied rotation',
      (tester) async {
    final controller = _FakeFrameController(
      id: 'device-rotated',
      fakeDuration: const Duration(seconds: 20),
      fakeEncodedSize: const Size(1080, 1920),
      fakeRotationCorrectionDegrees: 90,
    );
    Size? overlayDisplaySize;

    await tester.pumpWidget(
      _testApp(
        source: File('device-rotated.mp4'),
        displaySizeHint: const Size(1080, 1920),
        controllerFactory: (_) => controller,
        overlayBuilder: (context, displaySize, position) {
          overlayDisplaySize = displaySize;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(overlayDisplaySize, const Size(1080, 1920));
    final contentSize = tester.getSize(
      find.byKey(const ValueKey('ai-subtitle-frame-content')),
    );
    expect(contentSize.width / contentSize.height, closeTo(9 / 16, 0.001));
  });

  testWidgets('serializes live seeks and applies only the latest release',
      (tester) async {
    final controller = _FakeFrameController(
      id: 'seek',
      fakeDuration: const Duration(seconds: 20),
    );
    final session = AiSubtitleFramePreviewSession();

    await tester.pumpWidget(
      _testApp(
        source: File('seek.mp4'),
        sourceFingerprint: 'seek-v1',
        controllerFactory: (_) => controller,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final firstLiveSeek = Completer<void>();
    controller.nextSeekGate = firstLiveSeek;
    _slider(tester).onChanged!(1000);
    _slider(tester).onChanged!(2000);
    await tester.pump(const Duration(milliseconds: 109));
    expect(controller.seeks, [const Duration(seconds: 10)]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.seeks.last, const Duration(seconds: 2));

    _slider(tester).onChanged!(4000);
    _slider(tester).onChanged!(6000);
    _slider(tester).onChangeEnd!(7000);
    await tester.pump();
    expect(controller.seeks.last, const Duration(seconds: 2));

    firstLiveSeek.complete();
    await tester.pump();
    await tester.pump();

    expect(
      controller.seeks,
      [
        const Duration(seconds: 10),
        const Duration(seconds: 2),
        const Duration(seconds: 7),
      ],
    );
    expect(controller.maximumActiveSeeks, 1);
    expect(session.positionForSource('seek-v1'), const Duration(seconds: 7));
  });

  testWidgets('a stale source cannot replace a newer initialized source',
      (tester) async {
    final oldInitialization = Completer<void>();
    final oldController = _FakeFrameController(
      id: 'old',
      fakeDuration: const Duration(seconds: 20),
      initializeGate: oldInitialization,
    );
    final newController = _FakeFrameController(
      id: 'new',
      fakeDuration: const Duration(seconds: 30),
    );
    var source = File('old.mp4');
    var fingerprint = 'old-v1';
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AiSubtitleFramePreview(
                sourceFile: source,
                sourceFingerprint: fingerprint,
                controllerFactory: (file) =>
                    file.path == 'old.mp4' ? oldController : newController,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(oldController.calls, contains('initialize'));

    rebuild(() {
      source = File('new.mp4');
      fingerprint = 'new-v1';
    });
    await tester.pump();
    await tester.pump();

    expect(oldController.disposed, isFalse);
    expect(newController.calls, isEmpty);

    oldInitialization.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(oldController.seeks, isEmpty);
    expect(oldController.disposeCalls, 1);
    expect(oldController.disposed, isTrue);
    expect(newController.seeks, [const Duration(seconds: 15)]);
    expect(_slider(tester).value, 15000);
    expect(newController.disposed, isFalse);
    expect(find.byKey(const ValueKey('fake-frame-view-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-frame-view-old')), findsNothing);
  });

  testWidgets(
      'waits for an active seek and disposal before initializing a replacement',
      (tester) async {
    final seekGate = Completer<void>();
    final disposeGate = Completer<void>();
    final oldController = _FakeFrameController(
      id: 'old-active',
      fakeDuration: const Duration(seconds: 20),
      disposeGate: disposeGate,
    );
    final newController = _FakeFrameController(
      id: 'new-after-barrier',
      fakeDuration: const Duration(seconds: 30),
    );
    var source = File('old-active.mp4');
    var fingerprint = 'old-active-v1';
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AiSubtitleFramePreview(
                sourceFile: source,
                sourceFingerprint: fingerprint,
                seekThrottle: Duration.zero,
                controllerFactory: (file) => file.path == 'old-active.mp4'
                    ? oldController
                    : newController,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    oldController.nextSeekGate = seekGate;
    _slider(tester).onChangeEnd!(
      const Duration(seconds: 7).inMilliseconds.toDouble(),
    );
    await tester.pump();
    expect(oldController.activeSeeks, 1);

    rebuild(() {
      source = File('new-after-barrier.mp4');
      fingerprint = 'new-after-barrier-v1';
    });
    await tester.pump();

    expect(oldController.disposeCalls, 0);
    expect(newController.calls, isEmpty);

    seekGate.complete();
    await tester.pump();
    await tester.pump();

    expect(oldController.activeSeeks, 0);
    expect(oldController.disposeCalls, 1);
    expect(oldController.disposed, isFalse);
    expect(newController.calls, isEmpty);

    disposeGate.complete();
    await tester.pump();
    await tester.pump();

    expect(oldController.disposeCalls, 1);
    expect(oldController.disposed, isTrue);
    expect(newController.calls.take(3), [
      'initialize',
      'pause',
      'seek:15000',
    ]);
    expect(find.byKey(const ValueKey('fake-frame-view-new-after-barrier')),
        findsOneWidget);
  });

  testWidgets('transient session survives collapse but resets for a new source',
      (tester) async {
    final session = AiSubtitleFramePreviewSession();
    final controllers = <_FakeFrameController>[];

    _FakeFrameController factory(File file) {
      final controller = _FakeFrameController(
        id: '${file.path}-${controllers.length}',
        fakeDuration: file.path == 'a.mp4'
            ? const Duration(seconds: 10)
            : const Duration(seconds: 8),
      );
      controllers.add(controller);
      return controller;
    }

    await tester.pumpWidget(
      _testApp(
        source: File('a.mp4'),
        sourceFingerprint: 'a-v1',
        controllerFactory: factory,
        session: session,
        seekThrottle: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    _slider(tester).onChangeEnd!(3000);
    await tester.pumpAndSettle();
    expect(session.positionForSource('a-v1'), const Duration(seconds: 3));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(controllers.first.disposed, isTrue);

    await tester.pumpWidget(
      _testApp(
        source: File('a.mp4'),
        sourceFingerprint: 'a-v1',
        controllerFactory: factory,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    expect(controllers[1].seeks.first, const Duration(seconds: 3));

    await tester.pumpWidget(
      _testApp(
        source: File('b.mp4'),
        sourceFingerprint: 'b-v1',
        controllerFactory: factory,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    expect(controllers[1].disposed, isTrue);
    expect(controllers[2].seeks.first, const Duration(seconds: 4));
    expect(session.positionForSource('a-v1'), isNull);
    expect(session.positionForSource('b-v1'), const Duration(seconds: 4));
  });

  testWidgets('initialization failure leaves a usable placeholder',
      (tester) async {
    final controller = _FakeFrameController(
      id: 'broken',
      fakeDuration: const Duration(seconds: 20),
      failInitialize: true,
    );

    await tester.pumpWidget(
      _testApp(
        source: File('broken.mp4'),
        controllerFactory: (_) => controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ai-subtitle-frame-error')), findsOneWidget);
    expect(_slider(tester).onChanged, isNull);
    expect(controller.disposed, isTrue);
  });

  testWidgets('a clip no longer than the end margin selects frame zero',
      (tester) async {
    final controller = _FakeFrameController(
      id: 'short',
      fakeDuration: const Duration(milliseconds: 80),
    );

    await tester.pumpWidget(
      _testApp(
        source: File('short.mp4'),
        controllerFactory: (_) => controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.seeks, [Duration.zero]);
    expect(_slider(tester).value, 0);
  });
}
