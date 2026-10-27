import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/clip_frame_extractor.dart';

void main() {
  test('passes a file path with an apostrophe as one FFmpeg argument',
      () async {
    final directory = Directory.systemTemp.createTempSync('postdee-frames-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File("${directory.path}${Platform.pathSeparator}Bob's clip.mp4")
      ..writeAsBytesSync([1, 2, 3]);
    final calls = <List<String>>[];

    final frames = await FfmpegClipFrameExtractor(
      probeDuration: (_) async => 8,
      runFfmpeg: (arguments) async {
        calls.add(arguments);
        File(arguments.last).writeAsBytesSync([9]);
        return true;
      },
    ).call(video, maxFrames: 2);

    expect(frames, hasLength(2));
    expect(calls, hasLength(2));
    for (final arguments in calls) {
      expect(arguments, containsAllInOrder(['-i', video.path]));
      expect(arguments, containsAllInOrder(['-vf', 'scale=720:-2']));
    }
    expect(calls.first, containsAllInOrder(['-ss', '2.67']));
  });

  test('skips a frame FFmpeg could not write', () async {
    final directory = Directory.systemTemp.createTempSync('postdee-frames-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final video = File('${directory.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);

    final frames = await FfmpegClipFrameExtractor(
      probeDuration: (_) async => null,
      runFfmpeg: (_) async => false,
    ).call(video);

    expect(frames, isEmpty);
  });
}
