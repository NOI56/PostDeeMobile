import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_sound_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ships a unique in-house catalog with complete metadata', () {
    expect(postDeeSoundEffectCatalog, hasLength(10));
    expect(
      postDeeSoundEffectCatalog.map((effect) => effect.id).toSet(),
      hasLength(10),
    );

    for (final effect in postDeeSoundEffectCatalog) {
      expect(effect.titleTh.trim(), isNotEmpty);
      expect(effect.assetPath, startsWith('assets/sfx/'));
      expect(effect.assetPath, endsWith('.wav'));
      expect(effect.durationSeconds, greaterThan(0));
      expect(effect.durationSeconds.isFinite, isTrue);
      expect(effect.provenance, AiEditSoundEffectProvenance.postDeeProcedural);
    }
  });

  test('bundles every catalog asset as a non-empty WAV file', () async {
    for (final effect in postDeeSoundEffectCatalog) {
      final data = await rootBundle.load(effect.assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, greaterThan(44), reason: effect.assetPath);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
    }
  });

  test('finds only catalogued sound ids', () {
    expect(findPostDeeSoundEffect('soft_pop')?.titleTh, 'ป๊อปนุ่ม');
    expect(findPostDeeSoundEffect('missing'), isNull);
  });

  test('validates and sorts placements without mutating the caller list', () {
    final placements = [
      const AiEditSoundEffectPlacement(
        soundId: 'success_ding',
        startSeconds: 7.5,
        volume: 0.3,
      ),
      const AiEditSoundEffectPlacement(
        soundId: 'soft_pop',
        startSeconds: 1.25,
        volume: 0.25,
      ),
    ];

    final result = validateAiEditSoundEffectPlacements(
      placements,
      outputDurationSeconds: 10,
    );

    expect(result.map((item) => item.soundId), ['soft_pop', 'success_ding']);
    expect(placements.first.soundId, 'success_ding');
    expect(() => result.add(placements.first), throwsUnsupportedError);
  });

  test('allows an effect at zero but not at or after the output end', () {
    expect(
      validateAiEditSoundEffectPlacements(
        const [
          AiEditSoundEffectPlacement(
            soundId: 'clean_tap',
            startSeconds: 0,
            volume: 0.2,
          ),
        ],
        outputDurationSeconds: 1,
      ),
      hasLength(1),
    );

    for (final start in [1.0, 1.1, -0.1, double.nan]) {
      expect(
        () => validateAiEditSoundEffectPlacements(
          [
            AiEditSoundEffectPlacement(
              soundId: 'clean_tap',
              startSeconds: start,
              volume: 0.2,
            ),
          ],
          outputDurationSeconds: 1,
        ),
        throwsA(isA<AiEditSoundEffectValidationException>()),
      );
    }
  });

  test('rejects unknown sounds invalid volume and invalid duration', () {
    for (final placement in [
      const AiEditSoundEffectPlacement(
        soundId: 'unknown',
        startSeconds: 0,
        volume: 0.2,
      ),
      const AiEditSoundEffectPlacement(
        soundId: 'soft_pop',
        startSeconds: 0,
        volume: 0,
      ),
      const AiEditSoundEffectPlacement(
        soundId: 'soft_pop',
        startSeconds: 0,
        volume: 1.01,
      ),
      const AiEditSoundEffectPlacement(
        soundId: 'soft_pop',
        startSeconds: 0,
        volume: double.nan,
      ),
    ]) {
      expect(
        () => validateAiEditSoundEffectPlacements(
          [placement],
          outputDurationSeconds: 10,
        ),
        throwsA(isA<AiEditSoundEffectValidationException>()),
      );
    }

    for (final duration in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => validateAiEditSoundEffectPlacements(
          const [],
          outputDurationSeconds: duration,
        ),
        throwsA(isA<AiEditSoundEffectValidationException>()),
      );
    }
  });

  test('rejects more than the safe per-video limit', () {
    final placements = List.generate(
      maxAiEditSoundEffectsPerVideo + 1,
      (index) => AiEditSoundEffectPlacement(
        soundId: 'soft_pop',
        startSeconds: index.toDouble(),
        volume: 0.25,
      ),
    );

    expect(
      () => validateAiEditSoundEffectPlacements(
        placements,
        outputDurationSeconds: 20,
      ),
      throwsA(isA<AiEditSoundEffectValidationException>()),
    );
  });

  test('serializes placements deterministically for render caching', () {
    const placement = AiEditSoundEffectPlacement(
      soundId: 'sparkle',
      startSeconds: 2.3456,
      volume: 0.375,
    );

    expect(placement.toJson(), {
      'soundId': 'sparkle',
      'startSeconds': 2.346,
      'volume': 0.375,
    });
  });
}
