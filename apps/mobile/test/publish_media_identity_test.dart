import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/uploader/publish_media_identity.dart';

void main() {
  test('identity follows bytes and watermark rather than paths or upload keys',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('postdee-identity-');
    addTearDown(() => directory.delete(recursive: true));
    final video = File('${directory.path}/first.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final same = File('${directory.path}/reupload.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final changed = File('${directory.path}/changed.mp4')
      ..writeAsBytesSync([3, 2, 1]);
    final cover = File('${directory.path}/cover.jpg')..writeAsBytesSync([4, 5]);
    final first = await publishMediaContentFingerprint(
        videoFile: video, watermarkEnabled: true, coverImageFile: cover);
    expect(
        await publishMediaContentFingerprint(
            videoFile: same, watermarkEnabled: true, coverImageFile: cover),
        first);
    expect(
        await publishMediaContentFingerprint(
            videoFile: changed, watermarkEnabled: true, coverImageFile: cover),
        isNot(first));
    expect(
        await publishMediaContentFingerprint(
            videoFile: same, watermarkEnabled: false, coverImageFile: cover),
        isNot(first));
    cover.writeAsBytesSync([5, 4]);
    expect(
        await publishMediaContentFingerprint(
            videoFile: same, watermarkEnabled: true, coverImageFile: cover),
        isNot(first));
  });
}
