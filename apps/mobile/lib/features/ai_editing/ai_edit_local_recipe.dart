import '../../core/network/postdee_api_client.dart';
import 'ai_edit_sound_effects.dart';

AiEditRecipeResult buildLocalColorAiEditRecipe({
  required double durationSeconds,
}) {
  return _buildLocalAiEditRecipe(
    durationSeconds: durationSeconds,
    model: 'local-color-preset',
    summary: 'ปรับสีบนอุปกรณ์',
    capability: 'color',
    capabilityMessage: 'ปรับสีบนอุปกรณ์',
  );
}

AiEditRecipeResult buildLocalManualSoundEffectsAiEditRecipe({
  required double durationSeconds,
  required int effectCount,
}) {
  if (effectCount <= 0 || effectCount > maxAiEditSoundEffectsPerVideo) {
    throw ArgumentError.value(
      effectCount,
      'effectCount',
      'must be between 1 and $maxAiEditSoundEffectsPerVideo',
    );
  }
  return _buildLocalAiEditRecipe(
    durationSeconds: durationSeconds,
    model: 'local-manual-sfx',
    summary: 'เพิ่มเอฟเฟกต์เสียง $effectCount จุดบนอุปกรณ์',
    capability: 'manualSfx',
    capabilityMessage: 'เพิ่มเอฟเฟกต์เสียง $effectCount จุดบนอุปกรณ์',
  );
}

AiEditRecipeResult _buildLocalAiEditRecipe({
  required double durationSeconds,
  required String model,
  required String summary,
  required String capability,
  required String capabilityMessage,
}) {
  if (!durationSeconds.isFinite || durationSeconds <= 0) {
    throw ArgumentError.value(
      durationSeconds,
      'durationSeconds',
      'must be finite and greater than zero',
    );
  }

  const skipped = AiEditCapabilityStatusResult(
    enabled: false,
    state: 'skipped',
    message: 'ไม่ได้เลือกใน UI',
  );

  return AiEditRecipeResult(
    version: 1,
    status: 'ready',
    renderMode: 'local-render-only',
    transcript: AiEditTranscriptResult(
      text: '',
      language: 'th',
      durationSeconds: durationSeconds,
      segments: const [],
      boundarySegments: const [],
      words: const [],
      model: model,
    ),
    subtitles: const AiEditSubtitlesResult(
      enabled: false,
      segments: [],
      style: AiEditSubtitleStyleResult(
        mode: 'bold',
        color: '#FFFFFF',
        wordsPerLine: 2,
        position: 'bottom',
      ),
    ),
    cutRanges: const [],
    silenceRanges: const [],
    fillerRanges: const [],
    plan: AiEditPlanResult(
      cuts: const [],
      summary: summary,
      model: model,
    ),
    capabilities: {
      'subtitle': skipped,
      'silence': skipped,
      'filler': skipped,
      'color': capability == 'color'
          ? AiEditCapabilityStatusResult(
              enabled: true,
              state: 'applied',
              message: capabilityMessage,
            )
          : skipped,
      'sfx': skipped,
      if (capability == 'manualSfx')
        'manualSfx': AiEditCapabilityStatusResult(
          enabled: true,
          state: 'applied',
          message: capabilityMessage,
        ),
    },
  );
}
