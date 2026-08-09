import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_burn_video_processor.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart';

void main() {
  AiEditRecipeResult recipeFixture({
    bool includeRawWords = false,
    List<AiEditTranscriptWordResult>? transcriptWords,
    double durationSeconds = 5,
    List<ClipTranscriptSegment>? subtitleSegments,
    List<AiEditCut> cutRanges = const [AiEditCut(start: 3, end: 4)],
    String color = '#FFFFFF',
    String position = 'bottom',
    String outlineColor = '#000000',
    double? normalizedX,
    double? normalizedY,
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
        words: transcriptWords ??
            (includeRawWords
                ? const [
                    AiEditTranscriptWordResult(
                      word: 'ห',
                      start: 0.1,
                      end: 0.2,
                    ),
                  ]
                : const []),
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
          outlineColor: outlineColor,
          normalizedX: normalizedX,
          normalizedY: normalizedY,
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

  test('fingerprints the exact AI subtitle baseline deterministically', () {
    final first = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'ชีวิตส', start: 0.1, end: 1.2),
        ],
      ),
      projectId: 'same-project',
      sourceFingerprint: 'same-source',
      now: DateTime.utc(2026, 7, 29),
    );
    final fresh = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'ชีวิตสองข้างทาง', start: 0.1, end: 1.2),
        ],
      ),
      projectId: 'same-project',
      sourceFingerprint: 'same-source',
      now: DateTime.utc(2026, 7, 29),
    );
    final freshAgain = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'ชีวิตสองข้างทาง', start: 0.1, end: 1.2),
        ],
      ),
      projectId: 'same-project',
      sourceFingerprint: 'same-source',
      now: DateTime.utc(2026, 7, 30),
    );

    expect(first.projectId, fresh.projectId);
    expect(first.recipeFingerprint, isNot(fresh.recipeFingerprint));
    expect(fresh.recipeFingerprint, freshAgain.recipeFingerprint);
    expect(
      fresh.recipeFingerprint,
      matches(RegExp(r'^recipe-[0-9a-f]{16}$')),
    );
  });

  test('rebases the recipe fingerprint when setup style changes', () {
    final original = mapFixture();
    final changedStyle = copySubtitleStyle(
      original.defaultStyle,
      textColor: '#00E5A8',
      outlineColor: '#112233',
      normalizedX: 0.25,
      normalizedY: 0.6,
    );

    final changed = applySubtitleSetupStyle(original, changedStyle);
    final changedAgain = applySubtitleSetupStyle(original, changedStyle);

    expect(changed.defaultStyle, changedStyle);
    expect(changed.recipeFingerprint, isNot(original.recipeFingerprint));
    expect(changed.recipeFingerprint, changedAgain.recipeFingerprint);
    expect(changed.cues, original.cues);
  });

  test('preserves long Thai boundaries already selected by the API', () {
    const text = 'กำลังทดสอบข้อความซับภาษาไทยที่ยาวเกินพื้นที่ปลอดภัย';
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: text, start: 1, end: 4),
        ],
      ),
      projectId: 'project-long-thai',
      sourceFingerprint: 'source-long-thai',
      now: DateTime.utc(2026, 7, 23),
      maxCharsPerCue: 18,
    );

    expect(project.cues, hasLength(1));
    expect(project.cues.single.text, text);
    expect(project.cues.first.sourceStartMs, 1000);
    expect(project.cues.last.sourceEndMs, 4000);
  });

  test('does not split a real Thai phrase in the middle of a word', () {
    const text = 'คะเก็บชีวิตสองข้างทางแล้วเดินทางต่อไป';
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: text, start: 0.1, end: 2.4),
        ],
      ),
      projectId: 'project-real-thai-phrase',
      sourceFingerprint: 'source-real-thai-phrase',
      now: DateTime.utc(2026, 7, 29),
      maxCharsPerCue: 18,
    );

    expect(project.cues.map((cue) => cue.text), [text]);
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

  test('maps server-validated words and preserves untimed separators', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'ขายดี, ส่งฟรี! ✨',
            start: 0.1,
            end: 1.2,
            words: [
              AiEditTranscriptWordResult(
                word: 'ขายดี',
                start: 0.1,
                end: 0.5,
              ),
              AiEditTranscriptWordResult(
                word: 'ส่งฟรี',
                start: 0.6,
                end: 1.2,
              ),
            ],
          ),
        ],
      ),
      projectId: 'project-validated',
      sourceFingerprint: 'source-validated',
      now: DateTime.utc(2026, 7, 20),
    );

    final cue = project.cues.single;
    expect(cue.timingMode, SubtitleTimingMode.word);
    expect(cue.words.map((word) => word.text), ['ขายดี', 'ส่งฟรี']);
    expect(cue.words.map((word) => word.sourceStartMs), [100, 600]);
    expect(cue.words.map((word) => word.separatorAfter), [', ', '! ✨']);
  });

  test('authoritative empty cue words block raw transcript fallback', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'hello world',
            start: 0.1,
            end: 1.2,
            words: [],
          ),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
          AiEditTranscriptWordResult(word: 'world', start: 0.6, end: 1.2),
        ],
      ),
      projectId: 'project-authoritative-empty',
      sourceFingerprint: 'source-authoritative-empty',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('rejects authoritative words whose capitalization differs', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'Hello',
            start: 0.1,
            end: 0.8,
            words: [
              AiEditTranscriptWordResult(
                word: 'hello',
                start: 0.1,
                end: 0.8,
              ),
            ],
          ),
        ],
      ),
      projectId: 'project-case-mismatch',
      sourceFingerprint: 'source-case-mismatch',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('rejects canonically different authoritative word text', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'Café',
            start: 0.1,
            end: 0.8,
            words: [
              AiEditTranscriptWordResult(
                word: 'Cafe\u0301',
                start: 0.1,
                end: 0.8,
              ),
            ],
          ),
        ],
      ),
      projectId: 'project-unicode-mismatch',
      sourceFingerprint: 'source-unicode-mismatch',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('legacy response uses safe raw transcript word timing', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'hello world', start: 0.1, end: 1.2),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
          AiEditTranscriptWordResult(word: 'world', start: 0.6, end: 1.2),
        ],
      ),
      projectId: 'project-legacy-safe',
      sourceFingerprint: 'source-legacy-safe',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.timingMode, SubtitleTimingMode.word);
    expect(
      project.cues.single.words.map((word) => word.text),
      ['hello', 'world'],
    );
  });

  test('falls back when validated word timing overlaps', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'hello world',
            start: 0.1,
            end: 1.2,
            words: [
              AiEditTranscriptWordResult(
                word: 'hello',
                start: 0.1,
                end: 0.7,
              ),
              AiEditTranscriptWordResult(
                word: 'world',
                start: 0.6,
                end: 1.2,
              ),
            ],
          ),
        ],
      ),
      projectId: 'project-overlap',
      sourceFingerprint: 'source-overlap',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('does not expose fragmented Thai character timing as words', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'สวัสดี',
            start: 0.1,
            end: 0.6,
            words: [
              AiEditTranscriptWordResult(word: 'ส', start: 0.1, end: 0.2),
              AiEditTranscriptWordResult(word: 'ว', start: 0.2, end: 0.3),
              AiEditTranscriptWordResult(word: 'ั', start: 0.3, end: 0.35),
              AiEditTranscriptWordResult(word: 'ส', start: 0.35, end: 0.45),
              AiEditTranscriptWordResult(word: 'ดี', start: 0.45, end: 0.6),
            ],
          ),
        ],
      ),
      projectId: 'project-fragmented-thai',
      sourceFingerprint: 'source-fragmented-thai',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
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

  test('explicit empty effective cuts do not leak raw recipe candidates', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        durationSeconds: 20,
        cutRanges: const [AiEditCut(start: 4.8, end: 6.2)],
      ),
      projectId: 'project-verified-cuts',
      sourceFingerprint: 'source-verified-cuts',
      now: DateTime.utc(2026, 8, 1),
      effectiveCutRanges: const [],
    );

    expect(project.cutRanges, isEmpty);
  });

  test('explicit effective cuts replace raw recipe candidates', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        durationSeconds: 20,
        cutRanges: const [AiEditCut(start: 4.8, end: 6.2)],
      ),
      projectId: 'project-effective-cuts',
      sourceFingerprint: 'source-effective-cuts',
      now: DateTime.utc(2026, 8, 1),
      effectiveCutRanges: const [AiEditCut(start: 10.1, end: 10.9)],
    );

    expect(project.cutRanges, hasLength(1));
    expect(project.cutRanges.single.sourceStartMs, 10100);
    expect(project.cutRanges.single.sourceEndMs, 10900);
  });

  test('replaces project cuts and rebases revision time and fingerprint', () {
    final createdAt = DateTime.utc(2026, 8, 1);
    final updatedAt = DateTime(2026, 8, 1, 7, 1);
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        durationSeconds: 20,
        cutRanges: const [AiEditCut(start: 4.8, end: 6.2)],
      ),
      projectId: 'project-replaced-cuts',
      sourceFingerprint: 'source-replaced-cuts',
      now: createdAt,
      effectiveCutRanges: const [],
    );

    final updated = replaceSubtitleProjectCutRanges(
      project: project,
      effectiveCutRanges: const [
        SilenceCutRange(start: 10.1, end: 10.9),
      ],
      now: updatedAt,
    );

    expect(project.cutRanges, isEmpty);
    expect(updated.cutRanges, hasLength(1));
    expect(updated.cutRanges.single.sourceStartMs, 10100);
    expect(updated.cutRanges.single.sourceEndMs, 10900);
    expect(updated.recipeFingerprint, isNot(project.recipeFingerprint));
    expect(updated.revision, project.revision + 1);
    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, updatedAt.toUtc());
    expect(() => validateSubtitleProject(updated), returnsNormally);
  });

  test('replacement sorts merges and deduplicates effective cuts', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(durationSeconds: 20),
      projectId: 'project-merged-replacement',
      sourceFingerprint: 'source-merged-replacement',
      now: DateTime.utc(2026, 8, 1),
      effectiveCutRanges: const [],
    );

    final updated = replaceSubtitleProjectCutRanges(
      project: project,
      effectiveCutRanges: const [
        SilenceCutRange(start: 8, end: 9),
        SilenceCutRange(start: 3.5, end: 5),
        SilenceCutRange(start: 3, end: 4),
        SilenceCutRange(start: 5, end: 6),
        SilenceCutRange(start: 8, end: 9),
      ],
      now: DateTime.utc(2026, 8, 1, 0, 1),
    );

    expect(updated.cutRanges, hasLength(2));
    expect(updated.cutRanges[0].sourceStartMs, 3000);
    expect(updated.cutRanges[0].sourceEndMs, 6000);
    expect(updated.cutRanges[1].sourceStartMs, 8000);
    expect(updated.cutRanges[1].sourceEndMs, 9000);
  });

  test('replacement fingerprint is deterministic for the same cut ranges', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(durationSeconds: 20),
      projectId: 'project-stable-replacement',
      sourceFingerprint: 'source-stable-replacement',
      now: DateTime.utc(2026, 8, 1),
      effectiveCutRanges: const [],
    );

    final first = replaceSubtitleProjectCutRanges(
      project: project,
      effectiveCutRanges: const [
        SilenceCutRange(start: 10.1, end: 10.9),
      ],
      now: DateTime.utc(2026, 8, 1, 0, 1),
    );
    final second = replaceSubtitleProjectCutRanges(
      project: project,
      effectiveCutRanges: const [
        SilenceCutRange(start: 10.1, end: 10.9),
      ],
      now: DateTime.utc(2026, 8, 1, 0, 2),
    );

    expect(first.recipeFingerprint, second.recipeFingerprint);
    expect(first.updatedAt, isNot(second.updatedAt));
  });

  test('effective cuts fail closed for invalid nonfinite or out-of-range data',
      () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(durationSeconds: 20),
      projectId: 'project-invalid-replacement',
      sourceFingerprint: 'source-invalid-replacement',
      now: DateTime.utc(2026, 8, 1),
      effectiveCutRanges: const [],
    );
    final invalidRanges = <SilenceCutRange>[
      const SilenceCutRange(start: -1, end: 2),
      const SilenceCutRange(start: 4, end: 3),
      const SilenceCutRange(start: 19, end: 21),
      SilenceCutRange(start: double.nan, end: 2),
      SilenceCutRange(start: 1, end: double.infinity),
      const SilenceCutRange(start: 1.0001, end: 1.0004),
    ];

    for (final range in invalidRanges) {
      expect(
        () => replaceSubtitleProjectCutRanges(
          project: project,
          effectiveCutRanges: [range],
          now: DateTime.utc(2026, 8, 1, 0, 1),
        ),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }
  });

  test('mapper effective cuts fail closed instead of falling back to raw cuts',
      () {
    for (final effectiveCutRanges in <List<AiEditCut>>[
      const [AiEditCut(start: -1, end: 2)],
      const [AiEditCut(start: 4, end: 3)],
      const [AiEditCut(start: 19, end: 21)],
      [AiEditCut(start: double.nan, end: 2)],
      [AiEditCut(start: 1, end: double.infinity)],
    ]) {
      expect(
        () => mapAiEditRecipeToSubtitleProject(
          recipe: recipeFixture(
            durationSeconds: 20,
            cutRanges: const [AiEditCut(start: 3, end: 4)],
          ),
          projectId: 'project-invalid-effective-map',
          sourceFingerprint: 'source-invalid-effective-map',
          now: DateTime.utc(2026, 8, 1),
          effectiveCutRanges: effectiveCutRanges,
        ),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }
  });

  test('uses recipe colour and top alignment with Thai-safe defaults', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(color: '#A1B2C3', position: 'top'),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.fontId, 'Anuphan');
    expect(project.defaultStyle.textColor, '#A1B2C3');
    expect(project.defaultStyle.alignment, SubtitleAlignment.top);
    expect(project.defaultStyle.normalizedX, 0.5);
    expect(project.defaultStyle.normalizedY, 0.12);
  });

  test('prefers normalized recipe position and maps outline colour', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        position: 'top',
        outlineColor: '#112233',
        normalizedX: 0.27,
        normalizedY: 0.63,
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.outlineColor, '#112233');
    expect(project.defaultStyle.alignment, SubtitleAlignment.middle);
    expect(project.defaultStyle.normalizedX, 0.27);
    expect(project.defaultStyle.normalizedY, 0.63);
  });

  test('ignores an incomplete normalized position and keeps legacy mapping',
      () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        position: 'top',
        normalizedX: 0.27,
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.alignment, SubtitleAlignment.top);
    expect(project.defaultStyle.normalizedX, 0.5);
    expect(project.defaultStyle.normalizedY, 0.12);
  });

  test(
      'falls back to default colour and alignment for unsupported style values',
      () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(color: '#ffffff', position: 'sideways'),
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
