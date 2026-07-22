import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project_identity.dart';

void main() {
  test('builds a stable project identity for the same source and setup', () {
    final directory = Directory.systemTemp.createTempSync('subtitle-id-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);

    final first = buildSubtitleProjectIdentity(
      sourceFile: source,
      setupSignature: '30-seconds',
    );
    final second = buildSubtitleProjectIdentity(
      sourceFile: source,
      setupSignature: '30-seconds',
    );

    expect(second.projectId, first.projectId);
    expect(second.sourceFingerprint, first.sourceFingerprint);
    expect(first.projectId.length, lessThan(90));
  });

  test('uses a different project ID when the editing setup changes', () {
    final directory = Directory.systemTemp.createTempSync('subtitle-id-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);

    final short = buildSubtitleProjectIdentity(
      sourceFile: source,
      setupSignature: '30-seconds',
    );
    final long = buildSubtitleProjectIdentity(
      sourceFile: source,
      setupSignature: '60-seconds',
    );

    expect(long.projectId, isNot(short.projectId));
    expect(long.sourceFingerprint, short.sourceFingerprint);
  });
}
