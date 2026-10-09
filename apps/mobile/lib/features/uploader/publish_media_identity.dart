import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Identifies source bytes and rendering choices independently of upload keys.
/// Hash files as streams so large videos do not need to fit in memory.
Future<String> publishMediaContentFingerprint({
  required File videoFile,
  required bool watermarkEnabled,
  File? coverImageFile,
}) async {
  final videoDigest = await sha256.bind(videoFile.openRead()).first;
  final coverDigest = coverImageFile == null
      ? null
      : await sha256.bind(coverImageFile.openRead()).first;
  return sha256
      .convert(utf8.encode(jsonEncode([
        'postdee-source-media-v1',
        videoDigest.toString(),
        watermarkEnabled,
        coverDigest?.toString(),
      ])))
      .toString();
}
