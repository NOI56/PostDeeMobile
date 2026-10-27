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
    root = await Directory.systemTemp.createTemp('postdee-audio-extractor-test-');
    source = File('${root.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('extracts a non-empty AAC M4A with the bounded audio arguments', () async {
    List<String>? capturedArguments;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
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
    expect(artifact.file.path, endsWith('.m4a'));
    expect(await artifact.file.length(), 3);

    final workingDirectory = artifact.file.parent;
    await artifact.cleanup();
    await artifact.cleanup();
    expect(await workingDirectory.exists(), isFalse);
  });

  test('rejects a missing source before probing or running FFmpeg', () async {
    await source.delete();
    var probeCalled = false;
    var runnerCalled = false;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async {
        probeCalled = true;
        return true;
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
          AiEditAudioExtractionFailure.sourceMissing,
        ),
      ),
    );
    expect(probeCalled, isFalse);
    expect(runnerCalled, isFalse);
  });

  test('rejects video with no audio stream before running FFmpeg', () async {
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

  test('cleans its working directory when FFmpeg returns failure', () async {
    Directory? workingDirectory;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      runFfmpeg: (arguments) async {
        workingDirectory = File(arguments.last).parent;
        return false;
      },
      createWorkingDirectory: createWorkingDirectory,
    );

    await expectLater(
      extractor.extract(source),
      throwsA(
        isA<AiEditAudioExtractionException>().having(
          (error) => error.failure,
          'failure',
          AiEditAudioExtractionFailure.ffmpegFailed,
        ),
      ),
    );
    expect(workingDirectory, isNotNull);
    expect(await workingDirectory!.exists(), isFalse);
  });

  test('rejects and cleans an empty output file', () async {
    Directory? workingDirectory;
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => true,
      runFfmpeg: (arguments) async {
        final output = File(arguments.last);
        workingDirectory = output.parent;
        await output.create();
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

  test('maps an audio probe error without exposing native details', () async {
    final extractor = AiEditAudioExtractor(
      hasAudioStream: (_) async => throw StateError('native probe details'),
      runFfmpeg: (_) async => true,
      createWorkingDirectory: createWorkingDirectory,
    );

    await expectLater(
      extractor.extract(source),
      throwsA(
        isA<AiEditAudioExtractionException>()
            .having(
              (error) => error.failure,
              'failure',
              AiEditAudioExtractionFailure.inspectionFailed,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('native probe details')),
            ),
      ),
    );
  });
}
