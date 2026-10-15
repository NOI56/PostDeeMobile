import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';

const _channel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
const _events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeSessions native;
  late Directory fixtureDirectory;
  late File input;

  FfmpegTikTokVideoPreparer preparer({
    Duration probeTimeout = const Duration(milliseconds: 300),
    Duration renderTimeout = const Duration(milliseconds: 300),
  }) =>
      FfmpegTikTokVideoPreparer(
        isAndroid: true,
        isIOS: false,
        createTemporaryDirectory: (_) =>
            Directory('${fixtureDirectory.path}/prepared').create(),
        probeTimeout: probeTimeout,
        renderTimeout: renderTimeout,
        cancelTimeout: const Duration(milliseconds: 20),
        cancellationPollInterval: const Duration(milliseconds: 5),
      );

  TikTokVideoPreparationRequest request() => TikTokVideoPreparationRequest(
        inputFile: input,
        fileName: 'source.mp4',
      );

  setUp(() {
    native = _NativeSessions();
    fixtureDirectory = Directory.systemTemp.createTempSync('native-session-');
    input = File('${fixtureDirectory.path}/source.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, native.handle);
    // Accept the subscription, but deliberately never deliver completion
    // events: a second Flutter engine can own the plugin's global event sink.
    messenger.setMockMethodCallHandler(_events, (_) async => null);
  });

  tearDown(() {
    native.releasePending();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_events, null);
    fixtureDirectory.deleteSync(recursive: true);
  });

  test('source probe returns native result without any completion event',
      () async {
    native.pendingProbe = true;
    final task = await probeTikTokVideo('/video/source.mp4')
        .timeout(const Duration(seconds: 1));
    final session = native.sessions.values.single;
    expect(session.completed, isFalse);
    expect(native.returnCodeReads, isEmpty);

    native.finish(session);
    final metadata =
        await task.result.timeout(const Duration(milliseconds: 300));

    expect(metadata, isNotNull);
    expect(metadata!.videoCodec, 'h264');
    expect(metadata.width, 720);
    expect(metadata.height, 1280);
    expect(metadata.durationSeconds, 1);
    expect(metadata.averageFrameRate, 30);
    expect(metadata.hasAudio, isTrue);
    expect(native.returnCodeReads, [session.id]);
    expect(native.executions, ['ffprobeSessionExecute']);
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
  });

  test(
      'default preparer completes source, render, and decoded output probes '
      'without completion events', () async {
    final result = await preparer().call(request());

    expect(result.videoPreparationPolicy, tikTokVideoPreparationPolicy);
    expect(result.width, 720);
    expect(result.height, 1280);
    expect(result.fileName, 'source_tiktok.mp4');
    expect(await result.file.readAsBytes(), [1, 2, 3, 4]);
    expect(native.executions, [
      'ffprobeSessionExecute',
      'ffmpegSessionExecute',
      'ffprobeSessionExecute',
    ]);
    final sessions = native.sessions.values.toList();
    expect(sessions[0].arguments, isNot(contains('-count_frames')));
    expect(sessions[1].arguments.last, result.file.path);
    expect(
        sessions[2].arguments,
        containsAllInOrder([
          '-count_frames',
          '-read_intervals',
          '0%+2',
          '-i',
          result.file.path
        ]));
    expect(native.returnCodeReads, sessions.map((session) => session.id));
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
    await result.cleanupTemporaryFiles();
    expect(await result.file.exists(), isFalse);
    expect(await input.exists(), isTrue);
  });

  test('pending native probe times out and cancels only its known session',
      () async {
    native.pendingProbe = true;

    await expectLater(
      preparer(probeTimeout: const Duration(milliseconds: 30)).call(request()),
      throwsA(isA<TikTokVideoPreparationException>()),
    );

    final session = native.sessions.values.single;
    expect(session.isProbe, isTrue);
    expect(native.executions, ['ffprobeSessionExecute']);
    expect(native.cancelled, [session.id]);
    expect(native.globalCancels, 0);
    expect(
        await Directory('${fixtureDirectory.path}/prepared').exists(), isFalse);
    expect(await input.exists(), isTrue);
  });

  test('pending native render times out and cancels only the render session',
      () async {
    native.pendingRender = true;

    await expectLater(
      preparer(renderTimeout: const Duration(milliseconds: 30)).call(request()),
      throwsA(isA<TikTokVideoPreparationException>()),
    );

    final sessions = native.sessions.values.toList();
    expect(sessions, hasLength(2));
    expect(sessions.last.isProbe, isFalse);
    expect(
        native.executions, ['ffprobeSessionExecute', 'ffmpegSessionExecute']);
    expect(native.cancelled, [sessions.last.id]);
    expect(native.globalCancels, 0);
    expect(
        await Directory('${fixtureDirectory.path}/prepared').exists(), isFalse);
    expect(await input.exists(), isTrue);
  });

  test('nonzero or absent native probe return code rejects metadata', () async {
    for (final code in <int?>[1, null]) {
      native.probeReturnCode = code;
      final task = await probeTikTokVideo(input.path);
      expect(
          await task.result.timeout(const Duration(milliseconds: 300)), isNull);
    }

    expect(native.outputReads, isEmpty);
    expect(native.returnCodeReads, hasLength(2));
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
  });

  test('failed native source probe stops preparation before rendering',
      () async {
    native.probeReturnCode = 1;
    await expectLater(
      preparer().call(request()),
      throwsA(isA<TikTokVideoPreparationException>()
          .having((error) => error.message, 'message', contains('ต้นฉบับ'))),
    );

    expect(native.executions, ['ffprobeSessionExecute']);
    expect(native.outputReads, isEmpty);
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
  });

  test('nonzero or absent render return code never produces a prepared receipt',
      () async {
    for (final code in <int?>[1, null]) {
      native.renderReturnCode = code;
      await expectLater(preparer().call(request()),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(await Directory('${fixtureDirectory.path}/prepared').exists(),
          isFalse);
    }

    expect(native.executions, [
      'ffprobeSessionExecute',
      'ffmpegSessionExecute',
      'ffprobeSessionExecute',
      'ffmpegSessionExecute',
    ]);
    expect(
        native.sessions.values
            .where((s) => s.isProbe && s.arguments.contains('-count_frames')),
        isEmpty);
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
  });

  test('native render execution error fails closed and cancels its own session',
      () async {
    native.renderThrows = true;
    await expectLater(preparer().call(request()),
        throwsA(isA<TikTokVideoPreparationException>()));

    final sessions = native.sessions.values.toList();
    expect(sessions, hasLength(2));
    expect(sessions.last.isProbe, isFalse);
    expect(native.cancelled, [sessions.last.id]);
    expect(native.globalCancels, 0);
    expect(
        await Directory('${fixtureDirectory.path}/prepared').exists(), isFalse);
  });

  test(
      'missing native session ID fails before execution or global cancellation',
      () async {
    native.missingSessionId = true;

    await expectLater(probeTikTokVideo(input.path), throwsA(anything));

    expect(native.executions, isEmpty);
    expect(native.cancelled, isEmpty);
    expect(native.globalCancels, 0);
  });
}

class _NativeSession {
  _NativeSession(this.id, this.isProbe, this.arguments, this.returnCode);
  final int id;
  final bool isProbe;
  final List<String> arguments;
  final Completer<void> completion = Completer<void>();
  int? returnCode;
  bool completed = false;
}

/// Models native work and its MethodChannel reply separately from the absent
/// EventChannel notification. Uses the plugin's real Dart session adapters.
class _NativeSessions {
  final sessions = <int, _NativeSession>{};
  final executions = <String>[];
  final returnCodeReads = <int>[];
  final outputReads = <int>[];
  final cancelled = <int>[];
  var globalCancels = 0;
  var pendingProbe = false;
  var pendingRender = false;
  int? probeReturnCode = 0;
  int? renderReturnCode = 0;
  var renderThrows = false;
  var missingSessionId = false;
  var _nextId = 101;

  Future<Object?> handle(MethodCall call) async {
    final arguments = (call.arguments as Map?) ?? const {};
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
          _nextId++,
          isProbe,
          List<String>.from(arguments['arguments'] as List),
          isProbe ? probeReturnCode : renderReturnCode,
        );
        sessions[session.id] = session;
        return {
          'sessionId': missingSessionId ? null : session.id,
          'command': session.arguments.join(' '),
        };
      case 'ffprobeSessionExecute':
      case 'ffmpegSessionExecute':
      case 'asyncFFprobeSessionExecute':
      case 'asyncFFmpegSessionExecute':
        executions.add(call.method);
        final session = sessions[arguments['sessionId']]!;
        if (!session.isProbe && renderThrows) {
          throw PlatformException(code: 'native_execute_failed');
        }
        if (!(session.isProbe ? pendingProbe : pendingRender)) {
          finish(session);
        }
        // Legacy async calls acknowledge startup only. Their completion event
        // never arrives, even if native work has already finished successfully.
        if (!call.method.startsWith('async')) {
          await session.completion.future;
        }
        return null;
      case 'abstractSessionGetReturnCode':
        final session = sessions[arguments['sessionId']]!;
        returnCodeReads.add(session.id);
        return session.completed ? session.returnCode : null;
      case 'abstractSessionGetAllLogsAsString':
        final session = sessions[arguments['sessionId']]!;
        outputReads.add(session.id);
        return jsonEncode({
          'streams': [
            {
              'codec_type': 'video',
              'codec_name': 'h264',
              'width': 720,
              'height': 1280,
              'duration': '1.0',
              'avg_frame_rate': '30/1',
              'r_frame_rate': '30/1',
              if (session.arguments.contains('-count_frames'))
                'nb_read_frames': '30',
            },
            {'codec_type': 'audio', 'codec_name': 'aac'},
          ],
        });
      case 'cancelSession':
        final session = sessions[arguments['sessionId']]!;
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
      File(session.arguments.last).writeAsBytesSync([1, 2, 3, 4]);
    }
    session.completion.complete();
  }

  void releasePending() {
    for (final session in sessions.values) {
      finish(session);
    }
  }
}
