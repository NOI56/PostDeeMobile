import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/watermark_video_processor.dart';

class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(StateError('asset failed'));
}

void main() {
  test('creates a processor without invoking native FFmpeg', () {
    expect(
      FfmpegWatermarkVideoProcessor(),
      isA<FfmpegWatermarkVideoProcessor>(),
    );
  });

  test(
    'a watermark result cleans only its owned temporary directory',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'postdee-watermark-result-cleanup-',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final inputFile = File('${root.path}${Platform.pathSeparator}input.mp4')
        ..writeAsBytesSync([1]);
      final outputDirectory = Directory(
        '${root.path}${Platform.pathSeparator}owned-output',
      )..createSync();
      final outputFile = File(
        '${outputDirectory.path}${Platform.pathSeparator}output.mp4',
      )..writeAsBytesSync([2]);
      final result = WatermarkedVideoResult(
        file: outputFile,
        fileName: 'output.mp4',
        sizeBytes: outputFile.lengthSync(),
        temporaryDirectory: outputDirectory,
      );

      await result.cleanupTemporaryFiles();

      expect(outputDirectory.existsSync(), isFalse);
      expect(inputFile.existsSync(), isTrue);
    },
  );

  test(
    'processor cleans its temporary directory when preparation fails',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'postdee-watermark-processor-error-',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final inputFile = File('${root.path}${Platform.pathSeparator}input.mp4')
        ..writeAsBytesSync([1]);
      final outputDirectory = Directory(
        '${root.path}${Platform.pathSeparator}owned-output',
      );
      final processor = FfmpegWatermarkVideoProcessor(
        assetBundle: _FailingAssetBundle(),
        createTemporaryDirectory: (_) async {
          await outputDirectory.create();
          return outputDirectory;
        },
      );

      await expectLater(
        processor(
          WatermarkVideoRequest(inputFile: inputFile, fileName: 'input.mp4'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(outputDirectory.existsSync(), isFalse);
      expect(inputFile.existsSync(), isTrue);
    },
  );
}
