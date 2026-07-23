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

  test('rejects a clip without audio before running FFmpeg', () async {
    var runnerCalled = false;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => false,
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
