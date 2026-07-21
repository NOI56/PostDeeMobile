import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FFmpeg dependency includes the Android and iOS security fix', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final versionMatch = RegExp(
      r'^\s*ffmpeg_kit_flutter_new_video:\s*[\^~]?([0-9]+)\.([0-9]+)\.([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(versionMatch, isNotNull);

    final version = <int>[
      int.parse(versionMatch!.group(1)!),
      int.parse(versionMatch.group(2)!),
      int.parse(versionMatch.group(3)!),
    ];
    final hasPatchedVersion = version[0] > 2 ||
        (version[0] == 2 && version[1] > 3) ||
        (version[0] == 2 && version[1] == 3 && version[2] >= 2);

    expect(
      hasPatchedVersion,
      isTrue,
      reason: 'Use ffmpeg_kit_flutter_new_video 2.3.2 or newer.',
    );
  });
}
