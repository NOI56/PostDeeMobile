import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/tiktok_video_preparer.dart';

void main() {
  test('dimension-safe preparation uses a new receipt policy version', () {
    expect(tikTokVideoPreparationPolicy, 'tiktok-cfr30-h264-aac-v2');
  });

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
      TikTokVideoMetadata sourceVideo = source,
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
                    result:
                        Future.value(path == input.path ? sourceVideo : output),
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

    TikTokVideoMetadata dimensionVideo(int width, int height,
            {bool prepared = false}) =>
        TikTokVideoMetadata(
          videoCodec: prepared ? 'h264' : 'mpeg4',
          averageFrameRate: prepared ? 30 : 6,
          realFrameRate: prepared ? 30 : 6,
          width: width,
          height: height,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: prepared ? 'aac' : 'mp3',
          decodedPrefixFrameCount: prepared ? 30 : null,
        );

    test('upscales a small portrait upload copy to TikTok minimum dimensions',
        () async {
      const smallSource = TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 180,
          height: 320,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: 'aac');
      const enlargedOutput = TikTokVideoMetadata(
          videoCodec: 'h264',
          averageFrameRate: 30,
          realFrameRate: 30,
          width: 360,
          height: 640,
          durationSeconds: 1,
          hasAudio: true,
          audioCodec: 'aac',
          decodedPrefixFrameCount: 30);

      final result =
          await processor(sourceVideo: smallSource, output: enlargedOutput)
              .call(TikTokVideoPreparationRequest(
                  inputFile: input, fileName: 'small.mp4'));

      expect(result.width, 360);
      expect(result.height, 640);
      expect(
          commands.single, containsAllInOrder(['-vf', 'fps=30,scale=360:640']));
      expect(input.readAsBytesSync(), [1, 2, 3]);
      await result.cleanupTemporaryFiles();
    });

    for (final dimensions in [
      (
        label: 'small landscape',
        width: 320,
        height: 180,
        outWidth: 640,
        outHeight: 360
      ),
      (
        label: 'small odd portrait',
        width: 181,
        height: 321,
        outWidth: 360,
        outHeight: 638
      ),
      (
        label: 'odd standard portrait',
        width: 721,
        height: 1281,
        outWidth: 720,
        outHeight: 1280
      ),
      (
        label: 'valid portrait',
        width: 1080,
        height: 1920,
        outWidth: 1080,
        outHeight: 1920
      ),
      (
        label: 'minimum boundary',
        width: 360,
        height: 640,
        outWidth: 360,
        outHeight: 640
      ),
      (
        label: 'maximum boundary',
        width: 4096,
        height: 360,
        outWidth: 4096,
        outHeight: 360
      ),
      (
        label: 'large portrait',
        width: 4500,
        height: 8000,
        outWidth: 2304,
        outHeight: 4096
      ),
      (
        label: 'large landscape',
        width: 8000,
        height: 4500,
        outWidth: 4096,
        outHeight: 2304
      ),
      (
        label: 'large at minimum scaled edge',
        width: 8192,
        height: 720,
        outWidth: 4096,
        outHeight: 360
      ),
    ]) {
      test('prepares ${dimensions.label} within even TikTok dimension limits',
          () async {
        final result = await processor(
          sourceVideo: dimensionVideo(dimensions.width, dimensions.height),
          output: dimensionVideo(dimensions.outWidth, dimensions.outHeight,
              prepared: true),
        ).call(TikTokVideoPreparationRequest(
            inputFile: input, fileName: 'dimensions.mp4'));

        expect(result.width, dimensions.outWidth);
        expect(result.height, dimensions.outHeight);
        expect(
            commands.single,
            containsAllInOrder([
              '-vf',
              'fps=30,scale=${dimensions.outWidth}:${dimensions.outHeight}',
            ]));
        expect(commands.single,
            containsAllInOrder(['-b:v', '6M', '-pix_fmt', 'yuv420p']));
        expect(input.readAsBytesSync(), [1, 2, 3]);
        expect(probes, [input.path, result.file.path]);
        await result.cleanupTemporaryFiles();
      });
    }

    test('sizes a rotated phone video using its displayed portrait dimensions',
        () async {
      final rotatedSource = readTikTokVideoMetadata({
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 320,
            'height': 180,
            'duration': '1',
            'avg_frame_rate': '30/1',
            'r_frame_rate': '30/1',
            'side_data_list': [
              {'rotation': -90}
            ],
          },
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
      })!;

      final result = await processor(
        sourceVideo: rotatedSource,
        output: dimensionVideo(360, 640, prepared: true),
      ).call(TikTokVideoPreparationRequest(
          inputFile: input, fileName: 'rotated.mp4'));

      expect(result.width, 360);
      expect(result.height, 640);
      expect(
          commands.single, containsAllInOrder(['-vf', 'fps=30,scale=360:640']));
      expect(input.readAsBytesSync(), [1, 2, 3]);
      await result.cleanupTemporaryFiles();
    });

    for (final dimensions in [(2, 8192), (8192, 2), (4097, 360)]) {
      test(
          'rejects impossible aspect ${dimensions.$1}x${dimensions.$2} '
          'before allocating or rendering', () async {
        final incompatibleSource = dimensionVideo(dimensions.$1, dimensions.$2);
        expect(
            isCompatibleTikTokPreparedVideo(valid, source: incompatibleSource),
            isFalse);
        await expectLater(
          processor(sourceVideo: incompatibleSource).call(
              TikTokVideoPreparationRequest(
                  inputFile: input, fileName: 'extreme.mp4')),
          throwsA(isA<TikTokVideoPreparationException>().having(
              (error) => error.message, 'message', contains('สัดส่วน'))),
        );

        expect(commands, isEmpty);
        expect(probes, [input.path]);
        expect(temporary.existsSync(), isFalse);
        expect(input.readAsBytesSync(), [1, 2, 3]);
      });
    }

    test(
        'validates the required enlarged dimensions instead of source size '
        'or any in-range render', () async {
      final smallSource = dimensionVideo(180, 320);
      expect(
          isCompatibleTikTokPreparedVideo(
              dimensionVideo(360, 640, prepared: true),
              source: smallSource),
          isTrue);
      for (final wrongDimensions in [(180, 320), (360, 642), (720, 1280)]) {
        final wrongOutput = dimensionVideo(
            wrongDimensions.$1, wrongDimensions.$2,
            prepared: true);
        expect(
            isCompatibleTikTokPreparedVideo(wrongOutput, source: smallSource),
            isFalse);
        await expectLater(
          processor(sourceVideo: smallSource, output: wrongOutput).call(
              TikTokVideoPreparationRequest(
                  inputFile: input, fileName: 'wrong.mp4')),
          throwsA(isA<TikTokVideoPreparationException>()),
        );
        expect(temporary.existsSync(), isFalse);
        expect(input.readAsBytesSync(), [1, 2, 3]);
      }
    });

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
            'fps=30,scale=720:1280',
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

    test('exposes the verified output duration rather than a default value',
        () async {
      const output = TikTokVideoMetadata(
        videoCodec: 'h264',
        averageFrameRate: 30,
        realFrameRate: 30,
        width: 720,
        height: 1280,
        durationSeconds: 1.2,
        hasAudio: true,
        audioCodec: 'aac',
        decodedPrefixFrameCount: 36,
      );
      final result = await processor(output: output).call(
          TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'clip.mp4'));
      expect(result.durationSeconds, 1.2);
      await result.cleanupTemporaryFiles();
    });

    test(
        'rejects a direct clip beyond its current duration limit before render',
        () async {
      const longSource = TikTokVideoMetadata(
        videoCodec: 'h264',
        averageFrameRate: 30,
        realFrameRate: 30,
        width: 720,
        height: 1280,
        durationSeconds: 601,
      );
      await expectLater(
          processor(sourceVideo: longSource).call(TikTokVideoPreparationRequest(
              inputFile: input, fileName: 'long.mp4', maxDurationSeconds: 600)),
          throwsA(isA<TikTokVideoPreparationException>()));
      expect(commands, isEmpty);
      expect(temporary.existsSync(), isFalse);
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
