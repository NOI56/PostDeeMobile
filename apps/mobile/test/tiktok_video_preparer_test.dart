import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';

void main() {
  test('reads fractional FPS and rejects missing or invalid frame rates', () {
    expect(readVideoFrameRate('30000/1001'), closeTo(29.97003, .00001));
    expect(readVideoFrameRate('60000/1001'), closeTo(59.94006, .00001));
    expect(readVideoFrameRate('30'), 30);
    for (final value in [null, '', '0/0', '30/0', '-24', 'NaN', 'Infinity']) {
      expect(readVideoFrameRate(value), isNull, reason: '$value');
    }
  });

  const source = TikTokVideoMetadata(
    videoCodec: 'mpeg4',
    averageFrameRate: 6,
    realFrameRate: 6,
    width: 720,
    height: 1280,
    durationSeconds: 1,
    hasAudio: true,
    audioCodec: 'mp3',
  );
  const valid = TikTokVideoMetadata(
    videoCodec: 'h264',
    averageFrameRate: 30,
    realFrameRate: 30,
    width: 720,
    height: 1280,
    durationSeconds: 1,
    hasAudio: true,
    audioCodec: 'aac',
    decodedPrefixFrameCount: 30,
  );

  test(
      'probe rejects audio-only output and reads display rotation plus stream rates',
      () {
    expect(
        readTikTokVideoMetadata({
          'streams': [
            {'codec_type': 'audio', 'codec_name': 'aac'}
          ]
        }),
        isNull);
    final metadata = readTikTokVideoMetadata({
      'format': {'duration': '2.0'},
      'streams': [
        {
          'codec_type': 'video',
          'codec_name': 'h264',
          'width': 1280,
          'height': 720,
          'avg_frame_rate': '30000/1001',
          'r_frame_rate': '30/1',
          'side_data_list': [
            {'rotation': -90}
          ]
        },
        {'codec_type': 'audio', 'codec_name': 'aac'},
      ],
    });
    expect(metadata!.width, 720);
    expect(metadata.height, 1280);
    expect(metadata.durationSeconds, 2);
    expect(metadata.averageFrameRate, closeTo(29.97003, .00001));
    expect(metadata.realFrameRate, 30);
    expect(metadata.hasAudio, isTrue);
    expect(metadata.audioCodec, 'aac');
  });

  test('prepared output requires real H264 CFR30 and preserves source audio',
      () {
    expect(isCompatibleTikTokPreparedVideo(valid, source: source), isTrue);
    for (final output in [
      const TikTokVideoMetadata(
          videoCodec: 'mpeg4',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          decodedPrefixFrameCount: 30),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 6,
          realFrameRate: 6,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          decodedPrefixFrameCount: 30),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 60,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          decodedPrefixFrameCount: 30),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          decodedPrefixFrameCount: 30),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 721,
          height: 1280,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: 'aac',
          decodedPrefixFrameCount: 30),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: .1,
          hasAudio: true,
          audioCodec: 'aac',
          decodedPrefixFrameCount: 3),
    ]) {
      expect(isCompatibleTikTokPreparedVideo(output, source: source), isFalse);
    }
  });

  test(
      'requires enough actually decoded prefix frames despite valid H264 stream headers',
      () {
    TikTokVideoMetadata output({int? frames, double duration = 1}) =>
        readTikTokVideoMetadata({
          'streams': [
            {
              'codec_type': 'video',
              'codec_name': 'h264',
              'width': 720,
              'height': 1280,
              'duration': '$duration',
              'avg_frame_rate': '30/1',
              'r_frame_rate': '30/1',
              'nb_frames': '${(duration * 30).round()}',
              if (frames != null) 'nb_read_frames': '$frames'
            },
            {'codec_type': 'audio', 'codec_name': 'aac'},
          ],
        })!;
    expect(isCompatibleTikTokPreparedVideo(output(frames: 2), source: source),
        isFalse);
    expect(isCompatibleTikTokPreparedVideo(output(), source: source), isFalse);
    expect(isCompatibleTikTokPreparedVideo(output(frames: 30), source: source),
        isTrue);
    expect(isCompatibleTikTokPreparedVideo(output(frames: 28), source: source),
        isTrue);
    expect(isCompatibleTikTokPreparedVideo(output(frames: 27), source: source),
        isFalse);
    expect(isCompatibleTikTokPreparedVideo(output(frames: -1), source: source),
        isFalse);
    expect(isCompatibleTikTokPreparedVideo(output(frames: 33), source: source),
        isFalse);
    for (final duration in [2.0, 120.0]) {
      final longerSource = TikTokVideoMetadata(
          videoCodec: 'mpeg4',
          averageFrameRate: 6,
          realFrameRate: 6,
          width: 720,
          height: 1280,
          durationSeconds: duration,
          hasAudio: true,
          audioCodec: 'aac');
      expect(
          isCompatibleTikTokPreparedVideo(
              output(frames: 60, duration: duration),
              source: longerSource),
          isTrue);
      expect(
          isCompatibleTikTokPreparedVideo(
              output(frames: 57, duration: duration),
              source: longerSource),
          isFalse);
    }
  });

  test(
      'non-finite or non-positive output durations fail before frame-count arithmetic',
      () {
    for (final duration in [double.nan, double.infinity, 0.0, -1.0]) {
      final output = TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: duration,
          decodedPrefixFrameCount: 30,
          hasAudio: true,
          audioCodec: 'aac');
      expect(isCompatibleTikTokPreparedVideo(output, source: source), isFalse);
    }
  });

  test(
      'silent clips remain valid while an existing audio stream must become AAC',
      () {
    const silent = TikTokVideoMetadata(
        videoCodec: 'h264',
        averageFrameRate: 30,
        realFrameRate: 30,
        width: 720,
        height: 1280,
        durationSeconds: 1,
        decodedPrefixFrameCount: 30);
    const mp3 = TikTokVideoMetadata(
        videoCodec: 'h264',
        averageFrameRate: 30,
        realFrameRate: 30,
        width: 720,
        height: 1280,
        durationSeconds: 1,
        hasAudio: true,
        audioCodec: 'mp3',
        decodedPrefixFrameCount: 30);
    expect(isCompatibleTikTokPreparedVideo(silent, source: silent), isTrue);
    expect(isCompatibleTikTokPreparedVideo(mp3, source: source), isFalse);
  });

  group('on-device preparation', () {
    late Directory root;
    late File input;
    late Directory temporary;
    late List<List<String>> commands;
    late List<String> probes;

    setUp(() {
      root =
          Directory.systemTemp.createTempSync('postdee-tiktok-prepare-test-');
      input = File('${root.path}/original.mp4')..writeAsBytesSync([1, 2, 3]);
      temporary = Directory('${root.path}/prepared');
      commands = [];
      probes = [];
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    FfmpegTikTokVideoPreparer processor({
      TikTokVideoMetadata? output = valid,
      TikTokVideoRunner? run,
      TikTokVideoProbe? probe,
      bool isAndroid = true,
      bool isIOS = false,
      Duration timeout = const Duration(seconds: 1),
    }) =>
        FfmpegTikTokVideoPreparer(
          isAndroid: isAndroid,
          isIOS: isIOS,
          createTemporaryDirectory: (_) async => temporary..createSync(),
          probe: probe ??
              (path) async {
                probes.add(path);
                return TikTokVideoTask(
                    result: Future.value(path == input.path ? source : output),
                    cancel: () async {});
              },
          run: run ??
              (arguments) async {
                commands.add(arguments);
                File(arguments.last).writeAsBytesSync([3, 2, 1, 4]);
                return TikTokVideoTask(
                    result: Future.value(true), cancel: () async {});
              },
          renderTimeout: timeout,
          probeTimeout: timeout,
          cancelTimeout: const Duration(milliseconds: 50),
          cancellationPollInterval: const Duration(milliseconds: 2),
        );

    test(
        'normalizes after watermark to H264 AAC CFR30 and validates actual output',
        () async {
      final result = await processor().call(TikTokVideoPreparationRequest(
          inputFile: input, fileName: 'seller_watermarked.mp4'));
      expect(
          commands.single,
          containsAllInOrder([
            '-i',
            input.path,
            '-map',
            '0:v:0',
            '-map',
            '0:a?',
            '-vf',
            'fps=30,scale=trunc(iw/2)*2:trunc(ih/2)*2',
            '-c:v',
            'h264_mediacodec',
          ]));
      expect(commands.single, containsAllInOrder(['-c:a', 'aac']));
      expect(
          commands.single,
          containsAllInOrder([
            '-flags:v',
            '-global_header',
            '-bsf:v',
            'extract_extradata',
          ]),
          reason:
              'Android encoders cannot resume reliably after the MP4 global-header dummy frame/EOS flush');
      expect(commands.single, isNot(contains('mpeg4')));
      expect(probes, [input.path, result.file.path]);
      expect(result.fileName, 'seller_watermarked_tiktok.mp4');
      expect(result.videoPreparationPolicy, tikTokVideoPreparationPolicy);
      expect(result.width, 720);
      expect(result.height, 1280);
      expect(result.sizeBytes, 4);
      expect(temporary.existsSync(), isTrue);
      await result.cleanupTemporaryFiles();
      expect(temporary.existsSync(), isFalse);
      expect(input.readAsBytesSync(), [1, 2, 3]);
    });

    test('iOS uses platform H264 without adding a GPL encoder', () async {
      final result = await processor(isAndroid: false, isIOS: true).call(
          TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4'));
      expect(commands.single, contains('h264_videotoolbox'));
      expect(commands.single, isNot(contains('libx264')));
      expect(commands.single, isNot(contains('-global_header')));
      expect(commands.single, isNot(contains('extract_extradata')));
      await result.cleanupTemporaryFiles();
    });

    test(
        'unsupported hardware fails before running instead of falling back to MPEG4',
        () async {
      await expectLater(
          processor(isAndroid: false).call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(commands, isEmpty);
      expect(temporary.existsSync(), isFalse);
    });

    for (final output in <TikTokVideoMetadata?>[
      null,
      const TikTokVideoMetadata(
          videoCodec: 'mpeg4',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: 'aac'),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 6,
          realFrameRate: 6,
          width: 720,
          height: 1280,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: 'aac'),
      const TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 720,
          height: 1280,
          durationSeconds: 1),
    ]) {
      test(
          'rejects unsafe native output ${output?.videoCodec}/${output?.averageFrameRate}/${output?.hasAudio}',
          () async {
        await expectLater(
            processor(output: output).call(TikTokVideoPreparationRequest(
                inputFile: input, fileName: 'seller.mp4')),
            throwsA(isA<TikTokVideoPreparationException>()));
        expect(temporary.existsSync(), isFalse);
        expect(input.existsSync(), isTrue);
      });
    }

    test('nonzero native result never becomes a prepared receipt', () async {
      await expectLater(
          processor(
              run: (_) async => TikTokVideoTask(
                  result: Future.value(false),
                  cancel: () async {})).call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(temporary.existsSync(), isFalse);
    });

    test('timeout cancels only its own render and removes temporary output',
        () async {
      final done = Completer<bool>();
      var cancellations = 0;
      await expectLater(
          processor(
              timeout: const Duration(milliseconds: 15),
              run: (_) async => TikTokVideoTask(
                  result: done.future,
                  cancel: () async {
                    cancellations += 1;
                    done.complete(false);
                  })).call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(cancellations, 1);
      expect(temporary.existsSync(), isFalse);
    });

    test(
        'output probe timeout cancels its own probe and deletes unverified output',
        () async {
      final done = Completer<TikTokVideoMetadata?>();
      var cancellations = 0;
      await expectLater(
          processor(
            timeout: const Duration(milliseconds: 15),
            probe: (path) async => path == input.path
                ? TikTokVideoTask(
                    result: Future.value(source), cancel: () async {})
                : TikTokVideoTask(
                    result: done.future,
                    cancel: () async {
                      cancellations += 1;
                      done.complete(null);
                    }),
          ).call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(cancellations, 1);
      expect(temporary.existsSync(), isFalse);
    });

    test(
        'late native startup is cancelled after the timeout without returning a receipt',
        () async {
      final started = Completer<TikTokVideoTask<bool>>();
      var cancellations = 0;
      await expectLater(
          processor(
                  timeout: const Duration(milliseconds: 15),
                  run: (_) => started.future)
              .call(TikTokVideoPreparationRequest(
                  inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      started.complete(TikTokVideoTask(
          result: Future.value(false),
          cancel: () async {
            cancellations += 1;
          }));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cancellations, 1);
      expect(temporary.existsSync(), isFalse);
    });

    test('owner change cancels render and cannot return a ready result',
        () async {
      final done = Completer<bool>();
      var owned = true;
      var cancellations = 0;
      final pending = processor(run: (_) async {
        scheduleMicrotask(() => owned = false);
        return TikTokVideoTask(
            result: done.future,
            cancel: () async {
              cancellations += 1;
              done.complete(false);
            });
      }).call(TikTokVideoPreparationRequest(
          inputFile: input, fileName: 'seller.mp4', isCancelled: () => !owned));
      await expectLater(
          pending, throwsA(isA<TikTokVideoPreparationException>()));
      expect(cancellations, 1);
      expect(temporary.existsSync(), isFalse);
    });

    test('missing input does not allocate temporary files', () async {
      input.deleteSync();
      await expectLater(
          processor().call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'seller.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(commands, isEmpty);
      expect(temporary.existsSync(), isFalse);
    });
  });
}
