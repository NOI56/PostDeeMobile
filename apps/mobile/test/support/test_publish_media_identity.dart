import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:postdee_mobile/features/uploader/publish_draft.dart';

// Widget fake clocks cannot await filesystem streams. Test stores represent
// the digest that the real store computes while materializing its media copy.
String testPublishMediaFingerprint(PublishDraftSaveRequest request) {
  final usesCover = request.platformApiValues.any((platform) =>
      platform == 'INSTAGRAM_REELS' || platform == 'FACEBOOK_REELS');
  final cover = usesCover ? request.coverImageFile : null;
  return sha256
      .convert(utf8.encode(jsonEncode([
        'postdee-source-media-v1',
        sha256.convert(request.videoFile.readAsBytesSync()).toString(),
        request.watermarkEnabled,
        cover == null
            ? null
            : sha256.convert(cover.readAsBytesSync()).toString(),
      ])))
      .toString();
}
