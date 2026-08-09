import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
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
    expect(
      postDeeSoundEffectCatalog.map((effect) => effect.id).toSet(),
      aiEditRecipeKnownSoundEffectIds,
      reason: 'The API allowlist and bundled catalog must never drift apart.',
    );
    expect(
      maxAiEditSoundEffectsPerVideo,
      maxAiEditRecipeSoundEffectsPerVideo,
      reason: 'The API and renderer must enforce one shared item limit.',
    );
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

  test('maps AI source anchors through the final cut timeline', () {
    final placements = mapAiEditSoundEffectsToOutputTimeline(
      suggestions: const [
        AiEditSoundEffectSuggestionResult(
          soundId: 'soft_pop',
          sourceSeconds: 1,
        ),
        AiEditSoundEffectSuggestionResult(
          soundId: 'clean_tap',
          sourceSeconds: 3,
        ),
        AiEditSoundEffectSuggestionResult(
          soundId: 'success_ding',
          sourceSeconds: 5,
        ),
        AiEditSoundEffectSuggestionResult(
          soundId: 'sparkle',
          sourceSeconds: 9,
        ),
      ],
      finalCutRanges: const [
        AiEditCut(start: 2, end: 4),
        AiEditCut(start: 6, end: 8),
      ],
      sourceDurationSeconds: 10,
    );

    expect(placements.map((item) => item.soundId), [
      'soft_pop',
      'success_ding',
      'sparkle',
    ]);
    expect(placements.map((item) => item.startSeconds), [1, 3, 5]);
    expect(
      placements.map((item) => item.volume).toSet(),
      {defaultAiEditSoundEffectVolume},
      reason: 'The API cannot choose or amplify SFX volume.',
    );
  });

  test('drops cut-start anchors and keeps cut-end anchors at the join', () {
    final placements = mapAiEditSoundEffectsToOutputTimeline(
      suggestions: const [
        AiEditSoundEffectSuggestionResult(
          soundId: 'soft_pop',
          sourceSeconds: 2,
        ),
        AiEditSoundEffectSuggestionResult(
          soundId: 'clean_tap',
          sourceSeconds: 4,
        ),
      ],
      finalCutRanges: const [AiEditCut(start: 2, end: 4)],
      sourceDurationSeconds: 10,
    );

    expect(placements, hasLength(1));
    expect(placements.single.soundId, 'clean_tap');
    expect(placements.single.startSeconds, 2);
  });

  test('normalizes unsorted overlapping cuts before mapping anchors', () {
    final placements = mapAiEditSoundEffectsToOutputTimeline(
      suggestions: const [
        AiEditSoundEffectSuggestionResult(
          soundId: 'success_ding',
          sourceSeconds: 8,
        ),
      ],
      finalCutRanges: const [
        AiEditCut(start: 5, end: 7),
        AiEditCut(start: 2, end: 4),
        AiEditCut(start: 3, end: 6),
      ],
      sourceDurationSeconds: 10,
    );

    expect(placements.single.startSeconds, 3);
  });

  test('fails closed for an invalid final cut timeline', () {
    for (final cuts in [
      const [AiEditCut(start: -1, end: 2)],
      const [AiEditCut(start: 3, end: 3)],
      const [AiEditCut(start: 3, end: 11)],
      const [AiEditCut(start: double.nan, end: 4)],
    ]) {
      expect(
        () => mapAiEditSoundEffectsToOutputTimeline(
          suggestions: const [
            AiEditSoundEffectSuggestionResult(
              soundId: 'soft_pop',
              sourceSeconds: 1,
            ),
          ],
          finalCutRanges: cuts,
          sourceDurationSeconds: 10,
        ),
        throwsA(isA<AiEditSoundEffectValidationException>()),
      );
    }
  });
}
