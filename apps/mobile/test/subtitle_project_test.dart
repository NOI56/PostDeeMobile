import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';

void main() {
  SubtitleProject validProject() => SubtitleProject(
        schemaVersion: 1,
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        sourceDurationMs: 5000,
        language: 'th',
        cues: [
          SubtitleCue(
            cueId: 'cue-1',
            sourceStartMs: 100,
            sourceEndMs: 1200,
            text: 'สวัสดีค่ะ',
            timingMode: SubtitleTimingMode.segment,
          ),
        ],
        defaultStyle: SubtitleStyle.defaults,
        cutRanges: const [],
        revision: 0,
        createdAt: DateTime.utc(2026, 7, 20),
        updatedAt: DateTime.utc(2026, 7, 20),
      );

  test('round-trips a versioned project through JSON', () {
    final original = validProject();
    final decoded = SubtitleProject.fromJson(original.toJson());

    expect(decoded.toJson(), original.toJson());
  });

  test('rejects overlapping cues', () {
    final invalid = validProject().copyWith(cues: [
      SubtitleCue(
        cueId: 'one',
        sourceStartMs: 0,
        sourceEndMs: 1000,
        text: 'one',
        timingMode: SubtitleTimingMode.segment,
      ),
      SubtitleCue(
        cueId: 'two',
        sourceStartMs: 900,
        sourceEndMs: 1500,
        text: 'two',
        timingMode: SubtitleTimingMode.segment,
      ),
    ]);

    expect(
      () => validateSubtitleProject(invalid),
      throwsA(isA<SubtitleProjectValidationException>()),
    );
  });

  test('rejects word timing outside its cue', () {
    final invalid = validProject().copyWith(cues: [
      SubtitleCue(
        cueId: 'cue-1',
        sourceStartMs: 100,
        sourceEndMs: 1200,
        text: 'hello',
        timingMode: SubtitleTimingMode.word,
        words: [
          SubtitleWord(
            wordId: 'word-1',
            text: 'hello',
            sourceStartMs: 0,
            sourceEndMs: 500,
          ),
        ],
      ),
    ]);

    expect(
      () => validateSubtitleProject(invalid),
      throwsA(isA<SubtitleProjectValidationException>()),
    );
  });

  test('rejects an unsupported schema version while decoding', () {
    final json = validProject().toJson()..['schemaVersion'] = 99;

    expect(
      () => SubtitleProject.fromJson(json),
      throwsA(isA<SubtitleProjectValidationException>()),
    );
  });

  test('uses the specified readable default style', () {
    final style = SubtitleStyle.defaults;

    expect(style.fontId, 'Prompt');
    expect(style.fontWeight, 700);
    expect(style.fontSize, 22);
    expect(style.textColor, '#FFFFFF');
    expect(style.activeWordColor, '#00E5A8');
    expect(style.outlineColor, '#000000');
    expect(style.shadowColor, '#000000');
    expect(style.alignment, SubtitleAlignment.bottom);
    expect(style.maxLines, 2);
  });

  test('copies caller-owned words when constructing a cue', () {
    final words = <SubtitleWord>[
      const SubtitleWord(
        wordId: 'word-1',
        text: 'one',
        sourceStartMs: 0,
        sourceEndMs: 100,
      ),
    ];
    final cue = SubtitleCue(
      cueId: 'cue-1',
      sourceStartMs: 0,
      sourceEndMs: 200,
      text: 'one two',
      timingMode: SubtitleTimingMode.word,
      words: words,
    );

    words.add(
      const SubtitleWord(
        wordId: 'word-2',
        text: 'two',
        sourceStartMs: 100,
        sourceEndMs: 200,
      ),
    );

    expect(cue.words, hasLength(1));
  });
}
