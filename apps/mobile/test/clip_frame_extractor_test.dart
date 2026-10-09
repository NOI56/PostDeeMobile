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
}
