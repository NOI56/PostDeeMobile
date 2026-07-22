import 'dart:convert';
import 'dart:io';

class SubtitleProjectIdentity {
  const SubtitleProjectIdentity({
    required this.projectId,
    required this.sourceFingerprint,
  });

  final String projectId;
  final String sourceFingerprint;
}

SubtitleProjectIdentity buildSubtitleProjectIdentity({
  required File sourceFile,
  required String setupSignature,
}) {
  final stat = sourceFile.statSync();
  final sourceFingerprint = jsonEncode({
    'path': sourceFile.absolute.path,
    'sizeBytes': stat.size,
    'lastModifiedMs': stat.modified.millisecondsSinceEpoch,
  });
  final hash = _fnv1a64('$sourceFingerprint\n$setupSignature');
  return SubtitleProjectIdentity(
    projectId: 'subtitle-${hash.toRadixString(16).padLeft(16, '0')}',
    sourceFingerprint: sourceFingerprint,
  );
}

int _fnv1a64(String value) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  var hash = offsetBasis;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return hash;
}
