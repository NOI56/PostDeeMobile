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
