import 'dart:collection';

const maxAiEditSoundEffectsPerVideo = 8;
const defaultAiEditSoundEffectVolume = 0.25;

enum AiEditSoundEffectCategory {
  accent,
  transition,
  success,
  attention,
}

enum AiEditSoundEffectProvenance {
  postDeeProcedural,
}

class AiEditSoundEffectDefinition {
  const AiEditSoundEffectDefinition({
    required this.id,
    required this.titleTh,
    required this.assetPath,
    required this.durationSeconds,
    required this.category,
    required this.provenance,
  });

  final String id;
  final String titleTh;
  final String assetPath;
  final double durationSeconds;
  final AiEditSoundEffectCategory category;
  final AiEditSoundEffectProvenance provenance;
}

const postDeeSoundEffectCatalog = <AiEditSoundEffectDefinition>[
  AiEditSoundEffectDefinition(
    id: 'soft_pop',
    titleTh: 'ป๊อปนุ่ม',
    assetPath: 'assets/sfx/soft_pop.wav',
    durationSeconds: 0.22,
    category: AiEditSoundEffectCategory.accent,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'clean_tap',
    titleTh: 'แตะเบา',
    assetPath: 'assets/sfx/clean_tap.wav',
    durationSeconds: 0.12,
    category: AiEditSoundEffectCategory.accent,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'short_whoosh',
    titleTh: 'วูบสั้น',
    assetPath: 'assets/sfx/short_whoosh.wav',
    durationSeconds: 0.45,
    category: AiEditSoundEffectCategory.transition,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'medium_whoosh',
    titleTh: 'วูบยาว',
    assetPath: 'assets/sfx/medium_whoosh.wav',
    durationSeconds: 0.75,
    category: AiEditSoundEffectCategory.transition,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'sparkle',
    titleTh: 'ประกาย',
    assetPath: 'assets/sfx/sparkle.wav',
    durationSeconds: 0.8,
    category: AiEditSoundEffectCategory.accent,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'success_ding',
    titleTh: 'สำเร็จ',
    assetPath: 'assets/sfx/success_ding.wav',
    durationSeconds: 0.7,
    category: AiEditSoundEffectCategory.success,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'coin_ping',
    titleTh: 'เหรียญ',
    assetPath: 'assets/sfx/coin_ping.wav',
    durationSeconds: 0.42,
    category: AiEditSoundEffectCategory.success,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'soft_impact',
    titleTh: 'กระแทกนุ่ม',
    assetPath: 'assets/sfx/soft_impact.wav',
    durationSeconds: 0.35,
    category: AiEditSoundEffectCategory.accent,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'short_riser',
    titleTh: 'ไต่ระดับ',
    assetPath: 'assets/sfx/short_riser.wav',
    durationSeconds: 0.9,
    category: AiEditSoundEffectCategory.transition,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
  AiEditSoundEffectDefinition(
    id: 'attention_boop',
    titleTh: 'เตือนเบา',
    assetPath: 'assets/sfx/attention_boop.wav',
    durationSeconds: 0.32,
    category: AiEditSoundEffectCategory.attention,
    provenance: AiEditSoundEffectProvenance.postDeeProcedural,
  ),
];

AiEditSoundEffectDefinition? findPostDeeSoundEffect(String id) {
  for (final effect in postDeeSoundEffectCatalog) {
    if (effect.id == id) {
      return effect;
    }
  }
  return null;
}

class AiEditSoundEffectPlacement {
  const AiEditSoundEffectPlacement({
    required this.soundId,
    required this.startSeconds,
    this.volume = defaultAiEditSoundEffectVolume,
  });

  final String soundId;

  /// Output-timeline position. The first release only supports an uncut,
  /// original-duration local render, so source and output time are identical.
  final double startSeconds;
  final double volume;

  Map<String, Object> toJson() => {
        'soundId': soundId,
        'startSeconds': _roundToMilliseconds(startSeconds),
        'volume': _roundToMilliseconds(volume),
      };
}

class AiEditSoundEffectValidationException implements Exception {
  const AiEditSoundEffectValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<AiEditSoundEffectPlacement> validateAiEditSoundEffectPlacements(
  Iterable<AiEditSoundEffectPlacement> placements, {
  required double outputDurationSeconds,
}) {
  if (!outputDurationSeconds.isFinite || outputDurationSeconds <= 0) {
    throw const AiEditSoundEffectValidationException(
      'ยืนยันความยาววิดีโอไม่ได้',
    );
  }

  final result = placements.toList(growable: false);
  if (result.length > maxAiEditSoundEffectsPerVideo) {
    throw const AiEditSoundEffectValidationException(
      'ใส่เอฟเฟกต์เสียงได้ไม่เกิน 8 จุดต่อคลิป',
    );
  }

  for (final placement in result) {
    if (findPostDeeSoundEffect(placement.soundId) == null) {
      throw const AiEditSoundEffectValidationException(
        'ไม่พบเอฟเฟกต์เสียงที่เลือก',
      );
    }
    if (!placement.startSeconds.isFinite ||
        placement.startSeconds < 0 ||
        placement.startSeconds >= outputDurationSeconds) {
      throw const AiEditSoundEffectValidationException(
        'ตำแหน่งเอฟเฟกต์เสียงอยู่นอกวิดีโอ',
      );
    }
    if (!placement.volume.isFinite ||
        placement.volume <= 0 ||
        placement.volume > 1) {
      throw const AiEditSoundEffectValidationException(
        'ระดับเสียงเอฟเฟกต์ต้องมากกว่า 0% และไม่เกิน 100%',
      );
    }
  }

  result.sort((left, right) {
    final byStart = left.startSeconds.compareTo(right.startSeconds);
    return byStart != 0 ? byStart : left.soundId.compareTo(right.soundId);
  });
  return UnmodifiableListView(result);
}

double _roundToMilliseconds(double value) =>
    (value * 1000).roundToDouble() / 1000;
