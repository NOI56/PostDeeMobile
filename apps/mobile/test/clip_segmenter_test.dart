import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_segmenter.dart';
import 'package:postdee_mobile/features/uploader/platform_publish_preflight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late File input;
  late Directory temporary;
  late List<List<String>> commands;
  late Map<String, double> durations;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('postdee-clip-segment-test-');
    input = File('${fixture.path}/original.mp4')..writeAsBytesSync([1, 2, 3]);
    temporary = Directory('${fixture.path}/parts');
    commands = [];
    durations = {};
  });
  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  ClipSegmentProbeResult media({
    double duration = 10,
    bool output = false,
    bool hasAudio = true,
    String videoCodec = 'h264',
    int? frames,
    int width = 720,
  }) =>
      ClipSegmentProbeResult(
        metadata: PublishMediaMetadata(
          durationSeconds: duration,
          width: width,
          height: 1280,
          sizeBytes: output ? 4 : 3,
          hasAudio: hasAudio,
          videoCodec: videoCodec,
          audioCodec: hasAudio ? 'aac' : null,
          fps: 30,
          container: 'mov,mp4,m4a,3gp,3g2,mj2',
        ),
        decodedPrefixFrameCount:
            frames ?? (output ? (duration.clamp(0, 2) * 30).round() : null),
      );

  ClipSegmentRequest request({
    List<ClipSegmentRange>? ranges,
    bool Function()? isCancelled,
    void Function(int, int)? onProgress,
    String name = 'original.mp4',
  }) =>
      ClipSegmentRequest(
        inputFile: input,
        fileName: name,
        ranges: ranges ??
            const [
              ClipSegmentRange(
                  index: 0,
                  startSeconds: 0,
                  endSeconds: 5,
                  minimumDurationSeconds: 3,
                  maximumDurationSeconds: 5),
              ClipSegmentRange(
                  index: 1,
                  startSeconds: 5,
                  endSeconds: 10,
                  minimumDurationSeconds: 3,
                  maximumDurationSeconds: 5),
            ],
        isCancelled: isCancelled,
        onProgress: onProgress,
      );

  FfmpegClipSegmenter processor({
    ClipSegmentRunner? run,
    ClipSegmentProbe? probe,
    ClipSegmentProbeResult? source,
    ClipSegmentProbeResult Function(double)? output,
    bool isAndroid = true,
    bool isIOS = false,
    Future<Directory> Function(String)? createTemporaryDirectory,
    Duration timeout = const Duration(seconds: 2),
  }) =>
      FfmpegClipSegmenter(
        isAndroid: isAndroid,
        isIOS: isIOS,
        createTemporaryDirectory:
            createTemporaryDirectory ?? (_) async => temporary..createSync(),
        run: run ??
            (args) async {
              commands.add(args);
              durations[args.last] = double.parse(args[args.indexOf('-t') + 1]);
              File(args.last).writeAsBytesSync([4, 3, 2, 1]);
              return ClipSegmentTask(
                  result: Future.value(true), cancel: () async {});
            },
        probe: probe ??
            (path) async => ClipSegmentTask(
                  result: Future.value(path == input.path
                      ? source ?? media()
                      : output?.call(durations[path]!) ??
                          media(duration: durations[path]!, output: true)),
                  cancel: () async {},
                ),
        renderTimeout: timeout,
        probeTimeout: timeout,
        cancelTimeout: const Duration(milliseconds: 20),
        cancellationPollInterval: const Duration(milliseconds: 2),
      );

  test('renders every requested range into verified independent files',
      () async {
    final progress = <(int, int)>[];
    final result = await processor().call(
        request(onProgress: (done, total) => progress.add((done, total))));
    expect(result.parts, hasLength(2));
    expect(progress, [(1, 2), (2, 2)]);
    expect(
        commands[0],
        containsAllInOrder(
            ['-i', input.path, '-ss', '0.000000', '-t', '5.000000']));
    expect(
        commands[1], containsAllInOrder(['-ss', '5.000000', '-t', '5.000000']));
    expect(commands[0], containsAllInOrder(['-c:v', 'h264_mediacodec']));
    expect(commands[0], containsAllInOrder(['-c:a', 'aac']));
    expect(
        commands[0],
        containsAllInOrder(
            ['-flags:v', '-global_header', '-bsf:v', 'extract_extradata']));
    expect(commands[0], isNot(contains('-c:v copy')));
    expect(result.parts.first.metadata.durationSeconds, 5);
    expect(result.parts.first.metadata.sizeBytes, 4);
    expect(result.parts.last.index, 1);
    expect(result.parts.last.startSeconds, 5);
    expect(result.parts.last.endSeconds, 10);
    expect(result.parts.first.fileName, 'original_part_1.mp4');
    expect(input.readAsBytesSync(), [1, 2, 3]);
    await result.cleanupTemporaryFiles();
    await result.cleanupTemporaryFiles();
    expect(temporary.existsSync(), isFalse);
    expect(input.existsSync(), isTrue);
  });

  test('accepts overlapping ranges from different channel plans', () async {
    final result = await processor().call(request(ranges: const [
      ClipSegmentRange(
          index: 4,
          startSeconds: 5,
          endSeconds: 10,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 5),
      ClipSegmentRange(
          index: 2,
          startSeconds: 0,
          endSeconds: 8,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 9),
    ]));
    expect(result.parts.map((part) => part.index), [4, 2]);
    await result.cleanupTemporaryFiles();
  });

  test(
      'microsecond boundaries exactly at the limit do not fail from floating subtraction',
      () async {
    // Both values come from exact planner ticks. Binary double subtraction
    // yields 90.00000000000003 for this valid ninety-second interval.
    final result = await processor(source: media(duration: 260.666667))
        .call(request(ranges: const [
      ClipSegmentRange(
          index: 2,
          startSeconds: 170.666667,
          endSeconds: 260.666667,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 90),
    ]));
    expect(commands.single, containsAllInOrder(['-t', '90.000000']));
    expect(result.parts.single.metadata.durationSeconds, 90);
    await result.cleanupTemporaryFiles();
  });

  test('uses generated paths and keeps unsafe source names out of output paths',
      () async {
    final result =
        await processor().call(request(name: '../../seller; clip.mp4'));
    for (final part in result.parts) {
      expect(part.file.parent.path, temporary.path);
      expect(part.file.path, isNot(contains('seller')));
      expect(part.fileName, isNot(contains('/')));
      expect(part.fileName, isNot(contains('\\')));
    }
    expect(input.readAsBytesSync(), [1, 2, 3]);
    await result.cleanupTemporaryFiles();
  });

  test('iOS uses its platform encoder without reviving the retired editor',
      () async {
    final result =
        await processor(isAndroid: false, isIOS: true).call(request());
    expect(commands.first, contains('h264_videotoolbox'));
    expect(commands.first, isNot(contains('libx264')));
    expect(commands.first, isNot(contains('-global_header')));
    await result.cleanupTemporaryFiles();
  });

  test('silent sources remain silent and never fabricate audio', () async {
    final result = await processor(
            source: media(hasAudio: false),
            output: (duration) =>
                media(duration: duration, output: true, hasAudio: false))
        .call(request());
    expect(result.parts.first.metadata.hasAudio, isFalse);
    await result.cleanupTemporaryFiles();
  });

  for (final ranges in <List<ClipSegmentRange>>[
    [],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: -1,
          endSeconds: 5,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 6)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 5,
          endSeconds: 5,
          minimumDurationSeconds: 0,
          maximumDurationSeconds: 6)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 0,
          endSeconds: double.nan,
          minimumDurationSeconds: 0,
          maximumDurationSeconds: 6)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 0,
          endSeconds: 5,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 4)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 0,
          endSeconds: 2,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 6)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 8,
          endSeconds: 11,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 6)
    ],
    [
      const ClipSegmentRange(
          index: 0,
          startSeconds: 0,
          endSeconds: 5,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 6),
      const ClipSegmentRange(
          index: 0,
          startSeconds: 5,
          endSeconds: 10,
          minimumDurationSeconds: 3,
          maximumDurationSeconds: 6),
    ],
  ]) {
    test('invalid ranges fail before rendering $ranges', () async {
      await expectLater(processor().call(request(ranges: ranges)),
          throwsA(isA<ClipSegmentException>()));
      expect(commands, isEmpty);
      expect(temporary.existsSync(), isFalse);
      expect(input.readAsBytesSync(), [1, 2, 3]);
    });
  }

  test('caps work before allocating any output directory', () async {
    final ranges = List.generate(
        65,
        (index) => ClipSegmentRange(
            index: index,
            startSeconds: 0,
            endSeconds: 5,
            minimumDurationSeconds: 3,
            maximumDurationSeconds: 5));
    await expectLater(processor().call(request(ranges: ranges)),
        throwsA(isA<ClipSegmentException>()));
    expect(commands, isEmpty);
    expect(temporary.existsSync(), isFalse);
  });

  for (final invalid in [
    'too long',
    'too short',
    'audio missing',
    'wrong codec',
    'no decoded frames',
    'wrong dimensions'
  ]) {
    test('rejects $invalid output and discards the complete batch', () async {
      await expectLater(
          processor(
              output: (duration) => media(
                    duration: invalid == 'too long'
                        ? duration + .01
                        : invalid == 'too short'
                            ? duration - 1
                            : duration,
                    output: true,
                    hasAudio: invalid != 'audio missing',
                    videoCodec: invalid == 'wrong codec' ? 'mpeg4' : 'h264',
                    frames: invalid == 'no decoded frames' ? 0 : null,
                    width: invalid == 'wrong dimensions' ? 800 : 720,
                  )).call(request()),
          throwsA(isA<ClipSegmentException>()));
      expect(temporary.existsSync(), isFalse);
      expect(input.readAsBytesSync(), [1, 2, 3]);
    });
  }

  test('a second-part failure discards the earlier successful part', () async {
    var calls = 0;
    await expectLater(
        processor(run: (args) async {
          File(args.last).writeAsBytesSync([4, 3, 2, 1]);
          durations[args.last] = 5;
          return ClipSegmentTask(
              result: Future.value(++calls == 1), cancel: () async {});
        }).call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(calls, 2);
    expect(temporary.existsSync(), isFalse);
    expect(input.readAsBytesSync(), [1, 2, 3]);
  });

  test('refuses a directory containing the source without deleting anything',
      () async {
    await expectLater(
        processor(createTemporaryDirectory: (_) async => fixture)
            .call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(input.readAsBytesSync(), [1, 2, 3]);
    expect(commands, isEmpty);
  });

  test(
      'refuses nonempty temporary directories without deleting unrelated files',
      () async {
    final other = File('${temporary.path}/keep.txt');
    temporary.createSync();
    other.writeAsStringSync('keep');
    await expectLater(
        processor(createTemporaryDirectory: (_) async => temporary)
            .call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(other.readAsStringSync(), 'keep');
    expect(commands, isEmpty);
  });

  test('source changes while rendering invalidate the batch', () async {
    await expectLater(
        processor(run: (args) async {
          input.writeAsBytesSync([1, 2, 3, 4]);
          File(args.last).writeAsBytesSync([4, 3, 2, 1]);
          durations[args.last] = 5;
          return ClipSegmentTask(
              result: Future.value(true), cancel: () async {});
        }).call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(temporary.existsSync(), isFalse);
    expect(input.readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('cancelled requests allocate no files and report cancellation',
      () async {
    await expectLater(
        processor().call(request(isCancelled: () => true)),
        throwsA(isA<ClipSegmentException>()
            .having((error) => error.isCancelled, 'cancelled', isTrue)));
    expect(commands, isEmpty);
    expect(temporary.existsSync(), isFalse);
  });

  test('render timeout cancels only its task and deletes unverified output',
      () async {
    final done = Completer<bool>();
    var cancellations = 0;
    await expectLater(
        processor(
            timeout: const Duration(milliseconds: 15),
            run: (_) async => ClipSegmentTask(
                result: done.future,
                cancel: () async {
                  cancellations++;
                  done.complete(false);
                })).call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(cancellations, 1);
    expect(temporary.existsSync(), isFalse);
    expect(input.readAsBytesSync(), [1, 2, 3]);
  });

  test('late native startup after timeout is cancelled with its own handle',
      () async {
    final started = Completer<ClipSegmentTask<bool>>();
    var cancellations = 0;
    await expectLater(
        processor(
            timeout: const Duration(milliseconds: 15),
            run: (_) => started.future).call(request()),
        throwsA(isA<ClipSegmentException>()));
    started.complete(ClipSegmentTask(
        result: Future.value(false),
        cancel: () async {
          cancellations++;
        }));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cancellations, 1);
    expect(temporary.existsSync(), isFalse);
  });

  test('owner change cancels an active render and cannot return ready parts',
      () async {
    var cancelled = false;
    var cancellations = 0;
    final done = Completer<bool>();
    await expectLater(
        processor(run: (_) async {
          scheduleMicrotask(() => cancelled = true);
          return ClipSegmentTask(
              result: done.future,
              cancel: () async {
                cancellations++;
                done.complete(false);
              });
        }).call(request(isCancelled: () => cancelled)),
        throwsA(isA<ClipSegmentException>()
            .having((error) => error.isCancelled, 'cancelled', isTrue)));
    expect(cancellations, 1);
    expect(temporary.existsSync(), isFalse);
  });

  test('unsupported devices fail before probing or creating output', () async {
    await expectLater(processor(isAndroid: false).call(request()),
        throwsA(isA<ClipSegmentException>()));
    expect(commands, isEmpty);
    expect(temporary.existsSync(), isFalse);
  });

  group('native session adapters', () {
    const channel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
    const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
    late _NativeSessions native;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      native = _NativeSessions(input.path);
      messenger.setMockMethodCallHandler(channel, native.handle);
      // Completion events may belong to another Flutter engine. These tests
      // deliberately only return each native MethodChannel execution result.
      messenger.setMockMethodCallHandler(events, (_) async => null);
    });
    tearDown(() {
      native.releasePending();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    });

    FfmpegClipSegmenter nativeProcessor() => FfmpegClipSegmenter(
          isAndroid: true,
          isIOS: false,
          createTemporaryDirectory: (_) => temporary.create(),
          renderTimeout: const Duration(milliseconds: 100),
          probeTimeout: const Duration(milliseconds: 100),
          cancelTimeout: const Duration(milliseconds: 20),
          cancellationPollInterval: const Duration(milliseconds: 2),
        );

    test(
        'finishes source, render and decoded output probes without global events',
        () async {
      final result = await nativeProcessor().call(request());
      expect(result.parts, hasLength(2));
      expect(native.executions, [
        'ffprobeSessionExecute',
        'ffmpegSessionExecute',
        'ffprobeSessionExecute',
        'ffmpegSessionExecute',
        'ffprobeSessionExecute',
      ]);
      final probes =
          native.sessions.values.where((session) => session.isProbe).toList();
      expect(probes.first.arguments, isNot(contains('-count_frames')));
      expect(probes[1].arguments,
          containsAllInOrder(['-count_frames', '-read_intervals', '0%+2']));
      expect(probes[2].arguments, contains('-count_frames'));
      expect(native.cancelled, isEmpty);
      expect(native.globalCancels, 0);
      expect(result.parts.first.metadata.container, contains('mp4'));
      await result.cleanupTemporaryFiles();
    });

    test('pending render cancels only its session and deletes batch files',
        () async {
      native.pendingRender = true;
      await expectLater(nativeProcessor().call(request()),
          throwsA(isA<ClipSegmentException>()));
      expect(native.cancelled, [native.sessions.values.last.id]);
      expect(native.globalCancels, 0);
      expect(temporary.existsSync(), isFalse);
      expect(input.readAsBytesSync(), [1, 2, 3]);
    });

    test(
        'pending output probe cancels only its session and deletes batch files',
        () async {
      native.pendingOutputProbe = true;
      await expectLater(nativeProcessor().call(request()),
          throwsA(isA<ClipSegmentException>()));
      expect(native.cancelled, [native.sessions.values.last.id]);
      expect(native.sessions.values.last.arguments, contains('-count_frames'));
      expect(native.globalCancels, 0);
      expect(temporary.existsSync(), isFalse);
    });

    test('missing native session ID never triggers global cancellation',
        () async {
      native.missingSessionId = true;
      await expectLater(nativeProcessor().call(request()),
          throwsA(isA<ClipSegmentException>()));
      expect(native.executions, isEmpty);
      expect(native.cancelled, isEmpty);
      expect(native.globalCancels, 0);
      expect(temporary.existsSync(), isFalse);
    });

    test('failed native render cannot become a saved receipt', () async {
      native.renderReturnCode = 1;
      await expectLater(nativeProcessor().call(request()),
          throwsA(isA<ClipSegmentException>()));
      expect(
          native.executions, ['ffprobeSessionExecute', 'ffmpegSessionExecute']);
      expect(temporary.existsSync(), isFalse);
      expect(native.globalCancels, 0);
    });
  });
}

class _NativeSession {
  _NativeSession(this.id, this.isProbe, this.arguments, this.returnCode);
  final int id;
  final bool isProbe;
  final List<String> arguments;
  int? returnCode;
  final completion = Completer<void>();
  bool completed = false;
}

class _NativeSessions {
  _NativeSessions(this.inputPath);
  final String inputPath;
  final sessions = <int, _NativeSession>{};
  final executions = <String>[];
  final cancelled = <int>[];
  final durations = <String, double>{};
  var globalCancels = 0;
  var pendingRender = false;
  var pendingOutputProbe = false;
  var missingSessionId = false;
  int? renderReturnCode = 0;
  var nextId = 501;

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'getLogLevel':
        return 32;
      case 'getPlatform':
        return 'android';
      case 'getArch':
        return 'x86_64';
      case 'getPackageName':
        return 'video';
      case 'isLTSBuild':
        return false;
      case 'setLogLevel':
      case 'enableRedirection':
        return null;
      case 'ffprobeSession':
      case 'ffmpegSession':
        final isProbe = call.method == 'ffprobeSession';
        final session = _NativeSession(
            nextId++,
            isProbe,
            List<String>.from(args['arguments'] as List),
            isProbe ? 0 : renderReturnCode);
        sessions[session.id] = session;
        return {
          'sessionId': missingSessionId ? null : session.id,
          'command': session.arguments.join(' ')
        };
      case 'ffprobeSessionExecute':
      case 'ffmpegSessionExecute':
        executions.add(call.method);
        final session = sessions[args['sessionId']]!;
        final pending = session.isProbe
            ? pendingOutputProbe && session.arguments.contains('-count_frames')
            : pendingRender;
        if (!pending) finish(session);
        await session.completion.future;
        return null;
      case 'abstractSessionGetReturnCode':
        final session = sessions[args['sessionId']]!;
        return session.completed ? session.returnCode : null;
      case 'abstractSessionGetAllLogsAsString':
        final session = sessions[args['sessionId']]!;
        final duration = session.arguments.last == inputPath
            ? 10.0
            : durations[session.arguments.last]!;
        return jsonEncode({
          'format': {
            'duration': '$duration',
            'format_name': 'mov,mp4,m4a,3gp,3g2,mj2'
          },
          'streams': [
            {
              'codec_type': 'video',
              'codec_name': 'h264',
              'width': 720,
              'height': 1280,
              'duration': '$duration',
              'avg_frame_rate': '30/1',
              if (session.arguments.contains('-count_frames'))
                'nb_read_frames': '60'
            },
            {'codec_type': 'audio', 'codec_name': 'aac'},
          ],
        });
      case 'cancelSession':
        final session = sessions[args['sessionId']]!;
        cancelled.add(session.id);
        session.returnCode = 255;
        finish(session);
        return null;
      case 'cancel':
        globalCancels++;
        return null;
      default:
        throw StateError('Unexpected native call: ${call.method}');
    }
  }

  void finish(_NativeSession session) {
    if (session.completed) return;
    session.completed = true;
    if (!session.isProbe && session.returnCode == 0) {
      durations[session.arguments.last] =
          double.parse(session.arguments[session.arguments.indexOf('-t') + 1]);
      File(session.arguments.last).writeAsBytesSync([1, 2, 3, 4]);
    }
    session.completion.complete();
  }

  void releasePending() {
    for (final session in sessions.values) {
      if (!session.completed) {
        session.returnCode = 255;
        finish(session);
      }
    }
  }
}
