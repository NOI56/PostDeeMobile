import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/ai_edit_local_recipe.dart';

void main() {
  test('builds a cut-free local color recipe at the real source duration', () {
    final recipe = buildLocalColorAiEditRecipe(durationSeconds: 150.64);

    expect(recipe.renderMode, 'local-render-only');
    expect(recipe.transcript.durationSeconds, 150.64);
    expect(recipe.transcript.model, 'local-color-preset');
    expect(recipe.transcript.segments, isEmpty);
    expect(recipe.transcript.boundarySegments, isEmpty);
    expect(recipe.transcript.words, isEmpty);
    expect(recipe.subtitles.enabled, isFalse);
    expect(recipe.subtitles.segments, isEmpty);
    expect(recipe.cutRanges, isEmpty);
    expect(recipe.silenceRanges, isEmpty);
    expect(recipe.fillerRanges, isEmpty);
    expect(recipe.plan.cuts, isEmpty);
    expect(recipe.plan.model, 'local-color-preset');
    expect(recipe.capabilities['color']?.isApplied, isTrue);
    expect(recipe.capabilities['color']?.enabled, isTrue);
    for (final capability in ['subtitle', 'silence', 'filler']) {
      expect(recipe.capabilities[capability]?.enabled, isFalse);
      expect(recipe.capabilities[capability]?.state, 'skipped');
    }
  });

  test('rejects a non-positive or non-finite source duration', () {
    for (final duration in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => buildLocalColorAiEditRecipe(durationSeconds: duration),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'durationSeconds'),
        ),
        reason: 'durationSeconds=$duration must fail closed',
      );
    }
  });
}
