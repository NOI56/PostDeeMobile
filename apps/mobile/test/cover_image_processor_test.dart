import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/cover_image_processor.dart';

class _FontAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
        Uint8List.fromList(const [1, 2, 3, 4]),
      );
}

void main() {
  test('renders a real cover file with the selected Thai design', () async {
    final root = Directory.systemTemp.createTempSync('postdee-cover-test-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(List<int>.filled(16, 1));
    List<String>? executedArguments;

    final processor = FfmpegCoverImageProcessor(
      assetBundle: _FontAssetBundle(),
      createWorkingDirectory: () async =>
          Directory('${root.path}${Platform.pathSeparator}result')
            ..createSync(recursive: true),
      runCommand: (arguments) async {
        executedArguments = arguments;
        File(arguments.last).writeAsBytesSync(const [137, 80, 78, 71]);
        return true;
      },
    );

    final result = await processor(
      CoverImageRequest(
        videoFile: video,
        fileName: 'clip.mp4',
        design: const CoverDesign(
          coverFrameTimeMs: 1250,
          text: "โปรแรง, วันนี้: 50% ของร้าน's",
          fontFamily: CoverFontFamily.prompt,
          fontWeight: 700,
          fontSize: 64,
          textColor: Colors.white,
          backgroundColor: Color(0xB3000000),
          dx: 0.5,
          dy: 0.24,
        ),
      ),
    );

    expect(File(result.localImagePath).existsSync(), isTrue);
    expect(result.sizeBytes, greaterThan(0));
    expect(result.imageBytes, const [137, 80, 78, 71]);
    expect(result.coverFrameTimeMs, 1250);
    expect(executedArguments, isNotNull);
    expect(executedArguments,
        containsAllInOrder(['-i', video.path, '-ss', '1.250']));
    final filter = executedArguments![executedArguments!.indexOf('-vf') + 1];
    expect(filter, contains('scale=1080:1920'));
    expect(filter, contains('drawtext='));
    expect(filter, contains('textfile='));
    expect(filter, isNot(contains('โปรแรง')));
    expect(filter, contains('box=1'));
    expect(filter, contains('fontsize=64'));
    expect(filter, contains('fix_bounds=1'));
    expect(filter, contains('text_align=center'));
    expect(filter, contains('x=(w*0.500-text_w/2)'));
    final coverText = File('${root.path}${Platform.pathSeparator}result'
            '${Platform.pathSeparator}cover_text.txt')
        .readAsStringSync();
    expect(coverText, contains('โปรแรง'));
    expect(coverText, contains('\n'));
    expect(coverText.replaceAll('\n', ' '), "โปรแรง, วันนี้: 50% ของร้าน's");

    await result.cleanupTemporaryFiles();
    await result.cleanupTemporaryFiles();
    expect(
        Directory('${root.path}${Platform.pathSeparator}result').existsSync(),
        isFalse);
    expect(video.existsSync(), isTrue);
  });

  test('buildCoverImageArguments leaves the frame clean without cover text',
      () {
    final arguments = buildCoverImageArguments(
      inputPath: 'clip.mp4',
      outputPath: 'cover.jpg',
      fontPath: 'Prompt-Bold.ttf',
      design: const CoverDesign(coverFrameTimeMs: 2500),
    );
    final filter = arguments[arguments.indexOf('-vf') + 1];

    expect(arguments, containsAllInOrder(['-i', 'clip.mp4', '-ss', '2.500']));
    expect(filter, contains('crop=1080:1920'));
    expect(filter, isNot(contains('drawtext=')));
    expect(arguments, containsAllInOrder(['-q:v', '3']));
    expect(arguments.last, 'cover.jpg');
  });

  test('gallery cover arguments use the imported image without seeking', () {
    final arguments = buildCoverImageArguments(
      inputPath: 'imported-cover.png',
      outputPath: 'cover.jpg',
      fontPath: 'Prompt-Bold.ttf',
      design: const CoverDesign(coverFrameTimeMs: 2500),
      sourceKind: CoverSourceKind.galleryImage,
    );

    expect(arguments, containsAllInOrder(['-i', 'imported-cover.png']));
    expect(arguments, isNot(contains('-ss')));
    expect(arguments, containsAllInOrder(['-frames:v', '1']));
    expect(arguments.last, 'cover.jpg');
  });

  test('rejects a missing gallery source instead of using a video frame',
      () async {
    final root = Directory.systemTemp.createTempSync(
      'postdee-cover-missing-gallery-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3]);
    final missingImage = File(
      '${root.path}${Platform.pathSeparator}missing-cover.png',
    );
    final processor = FfmpegCoverImageProcessor(
      assetBundle: _FontAssetBundle(),
    );

    await expectLater(
      processor(
        CoverImageRequest(
          videoFile: video,
          fileName: 'clip.mp4',
          design: const CoverDesign(),
          sourceKind: CoverSourceKind.galleryImage,
          sourceImageFile: missingImage,
        ),
      ),
      throwsA(
        isA<CoverImageException>().having(
          (error) => error.message,
          'message',
          contains('ไม่พบรูปหน้าปก'),
        ),
      ),
    );
    expect(video.existsSync(), isTrue);
  });
  test('clamps export seek one safe frame margin before the clip ends', () {
    final arguments = buildCoverImageArguments(
      inputPath: 'clip.mp4',
      outputPath: 'cover.jpg',
      fontPath: 'Prompt-Bold.ttf',
      design: const CoverDesign(coverFrameTimeMs: 12000),
      durationMs: 12000,
    );

    expect(arguments, containsAllInOrder(['-ss', '11.900']));
    expect(clampCoverFrameTimeMs(20000, durationMs: 20000), 19900);
    expect(clampCoverFrameTimeMs(1, durationMs: 1), 0);
  });

  test('keeps 48 complete Thai graphemes and emoji families', () {
    const thaiGrapheme = 'ก้';
    final value = List.filled(60, thaiGrapheme).join();
    final wrapped = formatCoverTextForExport(value, fontSize: 64);
    final graphemes = wrapped.replaceAll('\n', '').characters.toList();

    expect(graphemes, hasLength(48));
    expect(graphemes, everyElement(thaiGrapheme));

    const family = '👨‍👩‍👧‍👦';
    final emoji = formatCoverTextForExport(
      List.filled(49, family).join(),
      fontSize: 40,
    ).replaceAll('\n', '').characters.toList();
    expect(emoji, hasLength(48));
    expect(emoji, everyElement(family));
  });

  test('deletes owned temp files on render failure', () async {
    final root = Directory.systemTemp.createTempSync('postdee-cover-fail-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3]);
    final resultDirectory =
        Directory('${root.path}${Platform.pathSeparator}failed-result');
    final processor = FfmpegCoverImageProcessor(
      assetBundle: _FontAssetBundle(),
      createWorkingDirectory: () async => resultDirectory,
      runCommand: (_) async => false,
    );

    await expectLater(
      processor(
        CoverImageRequest(
          videoFile: video,
          fileName: 'clip.mp4',
          design: const CoverDesign(text: 'ทดสอบ'),
        ),
      ),
      throwsA(isA<CoverImageException>()),
    );
    expect(resultDirectory.existsSync(), isFalse);
    expect(video.existsSync(), isTrue);
  });

  test(
      'copies a gallery source into owned temp files and keeps regeneration metadata',
      () async {
    final root = Directory.systemTemp.createTempSync('postdee-cover-gallery-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3]);
    final imported =
        File('${root.path}${Platform.pathSeparator}custom-cover.png')
          ..writeAsBytesSync(const [4, 5, 6, 7]);
    final resultDirectory =
        Directory('${root.path}${Platform.pathSeparator}gallery-result');
    List<String>? executedArguments;
    final processor = FfmpegCoverImageProcessor(
      assetBundle: _FontAssetBundle(),
      createWorkingDirectory: () async => resultDirectory,
      runCommand: (arguments) async {
        executedArguments = arguments;
        File(arguments.last).writeAsBytesSync(const [8, 9, 10]);
        return true;
      },
    );

    final result = await processor(
      CoverImageRequest(
        videoFile: video,
        fileName: 'clip.mp4',
        design: const CoverDesign(coverFrameTimeMs: 3200),
        durationMs: 5000,
        sourceKind: CoverSourceKind.galleryImage,
        sourceImageFile: imported,
        sourceImageName: 'หน้าปกพร้อมใช้.png',
      ),
    );

    expect(result.sourceKind, CoverSourceKind.galleryImage);
    expect(result.sourceImageName, 'หน้าปกพร้อมใช้.png');
    expect(result.sourceImagePath, isNot(imported.path));
    expect(result.sourceImageFile, isNotNull);
    expect(result.sourceImageFile!.existsSync(), isTrue);
    expect(result.sourceImageFile!.readAsBytesSync(), const [4, 5, 6, 7]);
    expect(result.coverFrameTimeMs, 3200);
    expect(executedArguments, isNotNull);
    expect(
      executedArguments,
      containsAllInOrder(['-i', result.sourceImagePath]),
    );
    expect(executedArguments, isNot(contains('-ss')));

    await result.cleanupTemporaryFiles();
    expect(resultDirectory.existsSync(), isFalse);
    expect(imported.existsSync(), isTrue);
    expect(video.existsSync(), isTrue);
  });

  test('never deletes unmanaged files and defers owned cleanup for a lease',
      () async {
    final root = Directory.systemTemp.createTempSync('postdee-cover-lease-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final video = File('${root.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync(const [1, 2, 3]);
    final external = File('${root.path}${Platform.pathSeparator}external.jpg')
      ..writeAsBytesSync(const [4, 5, 6]);
    final unmanaged = CoverEditorResult(
      localImagePath: external.path,
      sizeBytes: external.lengthSync(),
      design: const CoverDesign(),
    );
    await unmanaged.cleanupTemporaryFiles();
    expect(external.existsSync(), isTrue);

    final resultDirectory =
        Directory('${root.path}${Platform.pathSeparator}leased-result');
    final processor = FfmpegCoverImageProcessor(
      assetBundle: _FontAssetBundle(),
      createWorkingDirectory: () async => resultDirectory,
      runCommand: (arguments) async {
        File(arguments.last).writeAsBytesSync(const [7, 8, 9]);
        return true;
      },
    );
    final managed = await processor(
      CoverImageRequest(
        videoFile: video,
        fileName: 'clip.mp4',
        design: const CoverDesign(),
      ),
    );
    final lease = managed.retainTemporaryFiles();

    await managed.cleanupTemporaryFiles();
    expect(resultDirectory.existsSync(), isTrue);
    await lease!.release();
    expect(resultDirectory.existsSync(), isFalse);
    expect(video.existsSync(), isTrue);
  });
}
