import '../../core/network/postdee_api_client.dart';

AiEditRecipeResult buildLocalColorAiEditRecipe({
  required double durationSeconds,
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
      model: 'local-color-preset',
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
    plan: const AiEditPlanResult(
      cuts: [],
      summary: 'ปรับสีบนอุปกรณ์',
      model: 'local-color-preset',
    ),
    capabilities: const {
      'subtitle': skipped,
      'silence': skipped,
      'filler': skipped,
      'color': AiEditCapabilityStatusResult(
        enabled: true,
        state: 'applied',
        message: 'ปรับสีบนอุปกรณ์',
      ),
    },
  );
}
