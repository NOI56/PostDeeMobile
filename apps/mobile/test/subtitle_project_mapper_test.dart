import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/core/network/postdee_api_client.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart';

void main() {
  AiEditRecipeResult recipeFixture({
    List<AiEditTranscriptWordResult> transcriptWords = const [],
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
        words: transcriptWords,
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

  test('preserves a Thai API segment before opening Subtitle Studio', () {
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
    expect(project.cues.single.sourceStartMs, 1000);
    expect(project.cues.single.sourceEndMs, 4000);
  });

  test('does not merge adjacent Thai cues already split by the API', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'จะเป็นของ', start: 0, end: 0.35),
          ClipTranscriptSegment(text: 'มือสองไปหา', start: 0.35, end: 2),
        ],
      ),
      projectId: 'project-thai-api-boundaries',
      sourceFingerprint: 'source-thai-api-boundaries',
      now: DateTime.utc(2026, 7, 26),
      maxCharsPerCue: 18,
    );

    expect(project.cues.map((cue) => cue.text), ['จะเป็นของ', 'มือสองไปหา']);
  });

  test('maps verified transcript words inside a subtitle cue', () {
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
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    final cue = project.cues.single;
    expect(cue.timingMode, SubtitleTimingMode.word);
    expect(cue.words.map((word) => word.text), ['hello', 'world']);
    expect(cue.words.map((word) => word.sourceStartMs), [100, 600]);
    expect(cue.words.map((word) => word.sourceEndMs), [500, 1200]);
    expect(cue.words.map((word) => word.separatorAfter), [' ', '']);
    expect(
      cue.words.map((word) => word.wordId),
      ['${cue.cueId}-word-1', '${cue.cueId}-word-2'],
    );
  });

  test('prefers server-validated cue words over raw transcript words', () {
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
                start: 0.2,
                end: 0.5,
              ),
              AiEditTranscriptWordResult(
                word: 'world',
                start: 0.7,
                end: 1.1,
              ),
            ],
          ),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.4),
          AiEditTranscriptWordResult(word: 'world', start: 0.5, end: 1.2),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(
      project.cues.single.words.map((word) => word.sourceStartMs),
      [200, 700],
    );
    expect(
      project.cues.single.words.map((word) => word.sourceEndMs),
      [500, 1100],
    );
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
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('mixed nested word contract does not fall back per missing cue', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
            text: 'first',
            start: 0.1,
            end: 1,
            words: [
              AiEditTranscriptWordResult(word: 'first', start: 0.1, end: 1),
            ],
          ),
          ClipTranscriptSegment(text: 'second', start: 1.5, end: 2.5),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'first', start: 0.1, end: 1),
          AiEditTranscriptWordResult(word: 'second', start: 1.5, end: 2.5),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues[0].words.single.text, 'first');
    expect(project.cues[1].words, isEmpty);
    expect(project.cues[1].timingMode, SubtitleTimingMode.segment);
  });

  test('keeps transcript words that belong to their respective cues', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'first', start: 0.1, end: 1),
          ClipTranscriptSegment(text: 'second', start: 1.5, end: 2.5),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'first', start: 0.1, end: 1),
          AiEditTranscriptWordResult(word: 'second', start: 1.5, end: 2.5),
          AiEditTranscriptWordResult(word: 'ignored', start: 4.1, end: 4.5),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues[0].words.single.text, 'first');
    expect(project.cues[1].words.single.text, 'second');
    expect(
      project.cues.every(
        (cue) => cue.timingMode == SubtitleTimingMode.word,
      ),
      isTrue,
    );
  });

  test('falls back when transcript words do not reconstruct the cue', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(
              text: 'hello brave world', start: 0.1, end: 1.2),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
          AiEditTranscriptWordResult(word: 'world', start: 0.6, end: 1.2),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('preserves punctuation, symbols, and whitespace between timed words',
      () {
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
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    final cue = project.cues.single;
    expect(cue.timingMode, SubtitleTimingMode.word);
    expect(cue.words.map((word) => word.text), ['ขายดี', 'ส่งฟรี']);
    expect(cue.words.map((word) => word.separatorAfter), [', ', '! ✨']);
  });

  test('treats Thai abbreviation and repetition marks as semantic cue text',
      () {
    for (final mark in const ['\u0E2F', '\u0E46']) {
      final project = mapAiEditRecipeToSubtitleProject(
        recipe: recipeFixture(
          subtitleSegments: [
            ClipTranscriptSegment(
              text: 'word$mark',
              start: 0.1,
              end: 1.2,
              words: const [
                AiEditTranscriptWordResult(
                  word: 'word',
                  start: 0.1,
                  end: 1.2,
                ),
              ],
            ),
          ],
        ),
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        now: DateTime.utc(2026, 7, 20),
      );

      expect(project.cues.single.words, isEmpty);
      expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
    }
  });

  test('falls back for malformed or overlapping transcript word timing', () {
    final invalidWords = <List<AiEditTranscriptWordResult>>[
      const [
        AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
        AiEditTranscriptWordResult(word: 'world', start: 0.4, end: 1.2),
      ],
      const [
        AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
        AiEditTranscriptWordResult(word: 'world', start: 0.6, end: 0.6),
      ],
      [
        const AiEditTranscriptWordResult(word: 'hello', start: 0.1, end: 0.5),
        AiEditTranscriptWordResult(
          word: 'world',
          start: double.nan,
          end: 1.2,
        ),
      ],
    ];

    for (final words in invalidWords) {
      final project = mapAiEditRecipeToSubtitleProject(
        recipe: recipeFixture(
          subtitleSegments: const [
            ClipTranscriptSegment(text: 'hello world', start: 0.1, end: 1.2),
          ],
          transcriptWords: words,
        ),
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        now: DateTime.utc(2026, 7, 20),
      );

      expect(project.cues.single.words, isEmpty);
      expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
    }
  });

  test('falls back when a transcript word crosses a cue boundary', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'hello world', start: 0.1, end: 1.2),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'hello', start: 0.05, end: 0.5),
          AiEditTranscriptWordResult(word: 'world', start: 0.6, end: 1.2),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('does not expose fragmented Thai character timing as words', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'สวัสดี', start: 0.1, end: 0.6),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'ส', start: 0.1, end: 0.2),
          AiEditTranscriptWordResult(word: 'ว', start: 0.2, end: 0.3),
          AiEditTranscriptWordResult(word: 'ั', start: 0.3, end: 0.35),
          AiEditTranscriptWordResult(word: 'ส', start: 0.35, end: 0.45),
          AiEditTranscriptWordResult(word: 'ดี', start: 0.45, end: 0.6),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.cues.single.words, isEmpty);
    expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
  });

  test('does not trust structurally fragmented authoritative Thai cue words',
      () {
    for (final fixture in [
      (
        text: 'ก้',
        words: const [
          AiEditTranscriptWordResult(word: 'ก', start: 0.1, end: 0.3),
          AiEditTranscriptWordResult(word: '้', start: 0.3, end: 0.6),
        ],
      ),
      (
        text: 'ก้า',
        words: const [
          AiEditTranscriptWordResult(word: 'ก', start: 0.1, end: 0.25),
          AiEditTranscriptWordResult(word: '้', start: 0.25, end: 0.4),
          AiEditTranscriptWordResult(word: 'า', start: 0.4, end: 0.6),
        ],
      ),
    ]) {
      final project = mapAiEditRecipeToSubtitleProject(
        recipe: recipeFixture(
          subtitleSegments: [
            ClipTranscriptSegment(
              text: fixture.text,
              start: 0.1,
              end: 0.6,
              words: fixture.words,
            ),
          ],
        ),
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        now: DateTime.utc(2026, 7, 20),
      );

      expect(project.cues.single.words, isEmpty);
      expect(project.cues.single.timingMode, SubtitleTimingMode.segment);
    }
  });

  test('keeps verified semantic Thai word timing', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(
        subtitleSegments: const [
          ClipTranscriptSegment(text: 'อยู่ที่บ้านนะ', start: 0.1, end: 1.4),
        ],
        transcriptWords: const [
          AiEditTranscriptWordResult(word: 'อยู่', start: 0.1, end: 0.4),
          AiEditTranscriptWordResult(word: 'ที่', start: 0.4, end: 0.7),
          AiEditTranscriptWordResult(word: 'บ้าน', start: 0.7, end: 1.1),
          AiEditTranscriptWordResult(word: 'นะ', start: 1.1, end: 1.4),
        ],
      ),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(
      project.cues.single.words.map((word) => word.text),
      ['อยู่', 'ที่', 'บ้าน', 'นะ'],
    );
    expect(project.cues.single.timingMode, SubtitleTimingMode.word);
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

  test('uses recipe colour and top alignment with Thai-safe defaults', () {
    final project = mapAiEditRecipeToSubtitleProject(
      recipe: recipeFixture(color: '#A1B2C3', position: 'top'),
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      now: DateTime.utc(2026, 7, 20),
    );

    expect(project.defaultStyle.fontId, 'Bai Jamjuree');
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
