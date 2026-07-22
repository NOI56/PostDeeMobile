import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart';

void main() {
  AiEditRecipeResult recipeFixture({
    bool includeRawWords = false,
    double durationSeconds = 5,
    List<ClipTranscriptSegment>? subtitleSegments,
    List<AiEditCut> cutRanges = const [AiEditCut(start: 3, end: 4)],
    String color = '#FFFFFF',
    String position = 'bottom',
  }) {
    return AiEditRecipeResult(
      version: 1,
      status: 'ready',
      renderMode: 'mobile-ffmpeg',
      transcript: AiEditTranscriptResult(
        text: 'หนึ่งสอง',
        language: 'th',
        durationSeconds: durationSeconds,
        segments: const [
          ClipTranscriptSegment(text: 'หนึ่ง', start: 0.1, end: 1.2),
          ClipTranscriptSegment(text: 'สอง', start: 1.5, end: 2.5),
        ],
        words: includeRawWords
            ? const [
                AiEditTranscriptWordResult(
                  word: 'ห',
                  start: 0.1,
                  end: 0.2,
                ),
              ]
            : const [],
        model: 'fixture',
      ),
      subtitles: AiEditSubtitlesResult(
        enabled: true,
        segments: subtitleSegments ??
            const [
              ClipTranscriptSegment(text: 'หนึ่ง', start: 0.1, end: 1.2),
              ClipTranscriptSegment(text: 'สอง', start: 1.5, end: 2.5),
            ],
        style: AiEditSubtitleStyleResult(
          mode: 'outline',
          color: color,
          wordsPerLine: 2,
          position: position,
        ),
      ),
      cutRanges: cutRanges,
      silenceRanges: const [],
      fillerRanges: const [],
      capabilities: const {},
    );
  }

  SubtitleProject mapFixture() => mapAiEditRecipeToSubtitleProject(
        recipe: recipeFixture(),
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        now: DateTime.utc(2026, 7, 20),
      );

  test('maps prepared subtitle segments on the source timeline', () {
    final project = mapFixture();

    expect(project.sourceDurationMs, 5000);
    expect(project.cues.map((cue) => cue.text), ['หนึ่ง', 'สอง']);
    expect(project.cues.map((cue) => cue.sourceStartMs), [100, 1500]);
    expect(
      project.cues.every(
        (cue) => cue.timingMode == SubtitleTimingMode.segment,
      ),
      isTrue,
    );
  });

  test('does not trust raw transcript words for highlighting', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(includeRawWords: true),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.expand((cue) => cue.words), isEmpty);
  });

  test('maps an empty prepared subtitle list to a valid empty project', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(subtitleSegments: const []),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues, isEmpty);
    expect(() => validateSubtitleProject(project), returnsNormally);
  });

  test('generates stable cue ids for the same recipe', () {
    final first = mapFixture();
    final second = mapFixture();

    expect(
      first.cues.map((cue) => cue.cueId),
      second.cues.map((cue) => cue.cueId),
    );
  });

  test('sorts non-empty segments and uses deterministic timing-based ids', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: ' later ', start: 2, end: 3),
          ClipTranscriptSegment(text: '   ', start: 0, end: 0.5),
          ClipTranscriptSegment(text: 'first', start: 0.25, end: 1),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.map((cue) => cue.cueId), [
      'cue-1-250-1000',
      'cue-2-2000-3000',
    ]);
    expect(project.cues.map((cue) => cue.text), ['first', 'later']);
  });

  test('maps valid cut ranges on the source timeline', () {
    final project = mapFixture();

    expect(project.cutRanges, hasLength(1));
    expect(project.cutRanges.single.sourceStartMs, 3000);
    expect(project.cutRanges.single.sourceEndMs, 4000);
    expect(project.revision, 0);
    expect(project.createdAt, DateTime.utc(2026, 7, 20));
    expect(project.updatedAt, DateTime.utc(2026, 7, 20));
  });

  test('uses recipe colour and top alignment with Prompt defaults', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(color: '#A1B2C3', position: 'top'),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.fontId, 'Prompt');
    expect(project.defaultStyle.textColor, '#A1B2C3');
    expect(project.defaultStyle.alignment, SubtitleAlignment.top);
  });

  test(
      'falls back to default colour and alignment for unsupported style values',
      () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(color: '#ffffff', position: 'middle'),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.textColor, SubtitleStyle.defaults.textColor);
    expect(project.defaultStyle.alignment, SubtitleAlignment.bottom);
  });

  test('rejects zero or non-finite source durations', () {
    for (final duration in [
      0.0,
      double.nan,
      double.infinity,
      double.maxFinite,
    ]) {
      expect(
        () => mapAiEditRecipeToSubtitleProject(
          recipe: recipeFixture(durationSeconds: duration),
          projectId: 'project-1',
          sourceFingerprint: 'source-1',
          now: DateTime.utc(2026, 7, 20),
        ),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }
  });

  test('rejects malformed or overlapping prepared subtitle segments', () {
    for (final segments in [
      const [ClipTranscriptSegment(text: 'bad', start: 2, end: 1)],
      const [
        ClipTranscriptSegment(text: 'one', start: 0, end: 2),
        ClipTranscriptSegment(text: 'two', start: 1.5, end: 3),
      ],
      const [ClipTranscriptSegment(text: 'bad', start: -0.1, end: 1)],
      [ClipTranscriptSegment(text: 'bad', start: double.nan, end: 1)],
    ]) {
      expect(
        () => mapAiEditRecipeToSubtitleProject(
          recipe: recipeFixture(subtitleSegments: segments),
          projectId: 'project-1',
          sourceFingerprint: 'source-1',
          now: DateTime.utc(2026, 7, 20),
        ),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }
  });

  test('merges overlapping cut ranges from the combined AI recipe', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        cutRanges: const [
          AiEditCut(start: 1, end: 3),
          AiEditCut(start: 2, end: 4),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cutRanges, hasLength(1));
    expect(project.cutRanges.single.sourceStartMs, 1000);
    expect(project.cutRanges.single.sourceEndMs, 4000);
  });

  test('rejects malformed cut ranges', () {
    for (final cutRanges in [
      const [AiEditCut(start: 4, end: 3)],
      [AiEditCut(start: double.infinity, end: 4)],
    ]) {
      expect(
        () => mapAiEditRecipeToSubtitleProject(
          recipe: recipeFixture(cutRanges: cutRanges),
          projectId: 'project-1',
          sourceFingerprint: 'source-1',
          now: DateTime.utc(2026, 7, 20),
        ),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }
  });
}
