import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_audio_extractor.dart';

void main() {
  late Directory root;
  late File source;
  var directorySequence = 0;

  Future<Directory> createWorkingDirectory() async {
    directorySequence += 1;
    return Directory(
      '${root.path}${Platform.pathSeparator}working-$directorySequence',
    ).create();
  }

  setUp(() async {
    root =
        await Directory.systemTemp.createTemp('postdee-audio-extractor-test-');
    source = File('${root.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('extracts bounded mono AAC and cleans its temporary directory',
      () async {
    List<String>? capturedArguments;
    var probeCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async {
        probeCalls += 1;
        return true;
      },
      runFfmpeg: (arguments) async {
        capturedArguments = arguments;
        await File(arguments.last).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
    );

    final artifact = await extractor.extract(source);

    expect(capturedArguments, [
      '-y',
      '-i',
      source.path,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'aac',
      '-b:a',
      '64k',
      artifact.file.path,
    ]);
    expect(probeCalls, 2, reason: 'source and output must both contain audio');
    expect(artifact.file.path, endsWith('.m4a'));

    final workingDirectory = artifact.file.parent;
    await artifact.cleanup();
    await artifact.cleanup();
    expect(await workingDirectory.exists(), isFalse);
  });

  test('extracts long audio into balanced chunks no longer than 30 seconds',
      () async {
    List<String>? capturedArguments;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async => 75,
      runFfmpeg: (arguments) async {
        capturedArguments = arguments;
        final pattern = arguments.last;
        for (var index = 0; index < 3; index += 1) {
          final path = pattern.replaceFirst(
            '%03d',
            index.toString().padLeft(3, '0'),
          );
          await File(path).writeAsBytes([4, 5, 6]);
        }
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
    );

    final artifact = await extractor.extractChunks(source);

    expect(
        capturedArguments,
        containsAllInOrder([
          '-f',
          'segment',
          '-segment_times',
          '25.000,50.000',
          '-reset_timestamps',
          '1',
        ]));
    expect(artifact.chunks, hasLength(3));
    expect(
      artifact.chunks.map((chunk) => chunk.startSeconds),
      [0, 25, 50],
    );
    expect(
      artifact.chunks.map((chunk) => chunk.file.path),
      everyElement(endsWith('.m4a')),
    );

    final workingDirectory = artifact.chunks.first.file.parent;
    await artifact.cleanup();
    await artifact.cleanup();
    expect(await workingDirectory.exists(), isFalse);
  });

  test('balances a 2:30 clip without producing a tiny final chunk', () {
    final seconds = balancedAiEditAudioChunkSeconds(150.635);

    expect(seconds, closeTo(25.1058, 0.0001));
    expect(seconds, lessThanOrEqualTo(aiEditAudioChunkSeconds));
    expect(150.635 / seconds, closeTo(6, 0.0001));
    expect(
      balancedAiEditAudioSegmentTimes(150.635),
      hasLength(5),
    );
    expect(
      balancedAiEditAudioSegmentTimes(150.635).last,
      closeTo(125.5292, 0.0001),
    );
  });

  test('retries a transient source audio inspection once', () async {
    var sourceProbeCalls = 0;
    var runnerCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (candidate) async {
        if (candidate.path == source.path) {
          sourceProbeCalls += 1;
          if (sourceProbeCalls == 1) {
            throw StateError('transient FFprobe failure');
          }
        }
        return true;
      },
      probeDuration: (_) async => 12,
      runFfmpeg: (arguments) async {
        runnerCalls += 1;
        final outputPath = arguments.last.replaceFirst('%03d', '000');
        await File(outputPath).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    final artifact = await extractor.extractChunks(source);

    expect(sourceProbeCalls, 2);
    expect(runnerCalls, 1);
    expect(artifact.chunks, hasLength(1));
    await artifact.cleanup();
  });

  test('retries an invalid duration once before continuing', () async {
    var durationProbeCalls = 0;
    List<String>? capturedArguments;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async {
        durationProbeCalls += 1;
        return durationProbeCalls == 1 ? null : 12;
      },
      runFfmpeg: (arguments) async {
        capturedArguments = arguments;
        final outputPath = arguments.last.replaceFirst('%03d', '000');
        await File(outputPath).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    final artifact = await extractor.extractChunks(source);

    expect(durationProbeCalls, 2);
    expect(
      capturedArguments,
      containsAllInOrder(['-segment_time', '13.000']),
    );
    await artifact.cleanup();
  });

  test('retries a duration exception once before continuing', () async {
    var durationProbeCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async {
        durationProbeCalls += 1;
        if (durationProbeCalls == 1) {
          throw StateError('transient duration failure');
        }
        return 12;
      },
      runFfmpeg: (arguments) async {
        final outputPath = arguments.last.replaceFirst('%03d', '000');
        await File(outputPath).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    final artifact = await extractor.extractChunks(source);

    expect(durationProbeCalls, 2);
    await artifact.cleanup();
  });

  test('uses a valid known duration without probing it again', () async {
    var durationProbeCalls = 0;
    List<String>? capturedArguments;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async {
        durationProbeCalls += 1;
        throw StateError('duration probe should not run');
      },
      runFfmpeg: (arguments) async {
        capturedArguments = arguments;
        final outputPath = arguments.last.replaceFirst('%03d', '000');
        await File(outputPath).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    final artifact = await extractor.extractChunks(
      source,
      knownDurationSeconds: 12,
    );

    expect(durationProbeCalls, 0);
    expect(
      capturedArguments,
      containsAllInOrder(['-segment_time', '13.000']),
    );
    await artifact.cleanup();
  });

  test('falls back to probing when a known duration is invalid', () async {
    var durationProbeCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async {
        durationProbeCalls += 1;
        return 12;
      },
      runFfmpeg: (arguments) async {
        final outputPath = arguments.last.replaceFirst('%03d', '000');
        await File(outputPath).writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    final artifact = await extractor.extractChunks(
      source,
      knownDurationSeconds: double.nan,
    );

    expect(durationProbeCalls, 1);
    await artifact.cleanup();
  });

  test('reports inspection failure after one audio probe retry', () async {
    var sourceProbeCalls = 0;
    var runnerCalled = false;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async {
        sourceProbeCalls += 1;
        throw StateError('persistent FFprobe failure');
      },
      runFfmpeg: (_) async {
        runnerCalled = true;
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    await expectLater(
      extractor.extractChunks(source),
      throwsA(
        isA<AiEditAudioExtractionException>().having(
          (error) => error.failure,
          'failure',
          AiEditAudioExtractionFailure.inspectionFailed,
        ),
      ),
    );

    expect(sourceProbeCalls, 2);
    expect(runnerCalled, isFalse);
  });

  test('reports inspection failure after one duration probe retry', () async {
    var durationProbeCalls = 0;
    var runnerCalled = false;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      probeDuration: (_) async {
        durationProbeCalls += 1;
        return null;
      },
      runFfmpeg: (_) async {
        runnerCalled = true;
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
      probeRetryDelay: Duration.zero,
    );

    await expectLater(
      extractor.extractChunks(source),
      throwsA(
        isA<AiEditAudioExtractionException>().having(
          (error) => error.failure,
          'failure',
          AiEditAudioExtractionFailure.inspectionFailed,
        ),
      ),
    );

    expect(durationProbeCalls, 2);
    expect(runnerCalled, isFalse);
  });

  test('rejects a clip without audio before running FFmpeg', () async {
    var runnerCalled = false;
    var probeCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async {
        probeCalls += 1;
        return false;
      },
      runFfmpeg: (_) async {
        runnerCalled = true;
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
    );

    await expectLater(
      extractor.extract(source),
      throwsA(
        isA<AiEditAudioExtractionException>().having(
          (error) => error.failure,
          'failure',
          AiEditAudioExtractionFailure.noAudioStream,
        ),
      ),
    );
    expect(probeCalls, 1);
    expect(runnerCalled, isFalse);
  });

  test('rejects and cleans an invalid FFmpeg output', () async {
    Directory? workingDirectory;
    var probeCalls = 0;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async {
        probeCalls += 1;
        return probeCalls == 1;
      },
      runFfmpeg: (arguments) async {
        final output = File(arguments.last);
        workingDirectory = output.parent;
        await output.writeAsBytes([4, 5, 6]);
        return true;
      },
      createWorkingDirectory: createWorkingDirectory,
    );

    await expectLater(
      extractor.extract(source),
      throwsA(
        isA<AiEditAudioExtractionException>().having(
          (error) => error.failure,
          'failure',
          AiEditAudioExtractionFailure.emptyOutput,
        ),
      ),
    );
    expect(await workingDirectory!.exists(), isFalse);
  });
}
