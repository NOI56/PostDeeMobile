import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_frame_extractor.dart';

void main() {
  test(
      'cleanup deletes extraction outputs and always preserves the source clip',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-frame-cleanup-test-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final frame = File('${directory.path}/frame.jpg')..writeAsBytesSync([4, 5]);
    await cleanupExtractedCaptionFrames([frame, source], source);
    expect(await frame.exists(), isFalse);
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect(await directory.exists(), isTrue);
  });

  // FFmpegKit.execute re-splits a command string, so a quote in a file path
  // could break out of its argument. Each path must stay one argument.
  test('frame extraction passes each path as a single FFmpeg argument', () {
    expect(
      buildClipFrameArguments(
        seconds: 1.5,
        inputPath: "/tmp/seller's clip -vf x.mp4",
        outputPath: '/tmp/out dir/frame_1.jpg',
      ),
      [
        '-y',
        '-ss',
        '1.50',
        '-i',
        "/tmp/seller's clip -vf x.mp4",
        '-frames:v',
        '1',
        '-q:v',
        '3',
        '/tmp/out dir/frame_1.jpg',
      ],
    );
  });
}
