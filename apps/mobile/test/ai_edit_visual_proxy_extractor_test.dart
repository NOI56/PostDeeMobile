import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_visual_proxy_extractor.dart';

void main() {
  test('creates a low-bandwidth proxy that still spans the whole clip',
      () async {
    final sourceDirectory = Directory.systemTemp.createTempSync(
      'postdee-visual-proxy-source-',
    );
    addTearDown(() {
      if (sourceDirectory.existsSync()) {
        sourceDirectory.deleteSync(recursive: true);
      }
    });
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}source.mp4',
    )..writeAsBytesSync([1, 2, 3]);
    late List<String> receivedArguments;

    final extractor = AiEditVisualProxyExtractor(
      runFfmpeg: (arguments) async {
        receivedArguments = arguments;
        File(arguments.last).writeAsBytesSync([4, 5, 6]);
        return true;
      },
    );

    final artifact = await extractor.extract(source);

    expect(receivedArguments, containsAllInOrder(['-i', source.path]));
    expect(receivedArguments, contains('fps=1,scale=360:-2'));
    expect(receivedArguments, containsAllInOrder(['-ac', '1', '-ar', '16000']));
    expect(receivedArguments, isNot(contains('-t')));
    expect(artifact.file.path.toLowerCase().endsWith('.mp4'), isTrue);
    expect(artifact.file.lengthSync(), greaterThan(0));
    final workingDirectory = artifact.workingDirectory;
    expect(workingDirectory.existsSync(), isTrue);

    await artifact.cleanup();

    expect(workingDirectory.existsSync(), isFalse);
  });

  test('rejects an empty visual proxy', () async {
    final sourceDirectory = Directory.systemTemp.createTempSync(
      'postdee-empty-visual-proxy-',
    );
    addTearDown(() {
      if (sourceDirectory.existsSync()) {
        sourceDirectory.deleteSync(recursive: true);
      }
    });
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}source.mp4',
    )..writeAsBytesSync([1]);
    final extractor = AiEditVisualProxyExtractor(
      runFfmpeg: (_) async => true,
    );

    await expectLater(
      extractor.extract(source),
      throwsA(
        isA<AiEditVisualProxyException>().having(
          (error) => error.failure,
          'failure',
          AiEditVisualProxyFailure.emptyOutput,
        ),
      ),
    );
  });
}
