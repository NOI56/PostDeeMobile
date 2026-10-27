import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_audio_extractor.dart';

void main() {
  test('rejects a non-empty M4A that has no output audio stream', () async {
    final root = await Directory.systemTemp.createTemp(
      'postdee-audio-output-probe-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final source = File('${root.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes([1, 2, 3]);
    var probeCalls = 0;
    Directory? workingDirectory;
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
      createWorkingDirectory: () async => Directory(
        '${root.path}${Platform.pathSeparator}working',
      ).create(),
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
    expect(probeCalls, 2);
    expect(await workingDirectory!.exists(), isFalse);
  });
}
