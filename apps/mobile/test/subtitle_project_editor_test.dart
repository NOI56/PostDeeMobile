import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project_editor.dart';

void main() {
  test('editing mapped word text disables unsafe word highlight', () {
    final editor = testEditor(wordTimedProject());

    editor.updateCueText('cue-1', 'แก้คำแล้ว');

    expect(editor.project.cues.single.text, 'แก้คำแล้ว');
    expect(editor.project.cues.single.timingMode, SubtitleTimingMode.estimated);
    expect(editor.project.cues.single.words, isEmpty);
  });

  test('split uses grapheme boundaries and preserves source coverage', () {
    final editor = testEditor(projectWithCue(text: '👍🏽ดีมาก'));

    editor.splitCue('cue-1', graphemeOffset: 1);

    expect(editor.project.cues, hasLength(2));
    expect(editor.project.cues[0].text, '👍🏽');
    expect(editor.project.cues[1].text, 'ดีมาก');
    expect(editor.project.cues.first.sourceStartMs, 0);
    expect(editor.project.cues.last.sourceEndMs, 1000);
  });

  test('merge joins Thai without inventing a space', () {
    final editor = testEditor(twoCueProject('สวัสดีค่ะ', 'ชื่อแดงนะคะ'));

    editor.mergeWithNext('cue-1');

    expect(editor.project.cues.single.text, 'สวัสดีค่ะชื่อแดงนะคะ');
  });

  test('invalid timing leaves the current project unchanged', () {
    final editor = testEditor(twoCueProject('one', 'two'));
    final before = editor.project.toJson();

    expect(
      () => editor.updateCueTiming('cue-2', startMs: 500, endMs: 2000),
      throwsA(isA<SubtitleProjectValidationException>()),
    );
    expect(editor.project.toJson(), before);
  });

  test('undo and redo restore complete project snapshots', () {
    final editor = testEditor(projectWithCue(text: 'before'));

    editor.updateCueText('cue-1', 'after');
    editor.undo();
    expect(editor.project.cues.single.text, 'before');
    editor.redo();
    expect(editor.project.cues.single.text, 'after');
  });

  test('undo history keeps at most fifty snapshots', () {
    final editor = testEditor(projectWithCue(text: '0'));
    for (var index = 1; index <= 55; index += 1) {
      editor.updateCueText('cue-1', '$index');
    }
    for (var index = 0; index < 50; index += 1) {
      editor.undo();
    }
    expect(editor.canUndo, isFalse);
    expect(editor.project.cues.single.text, '5');
  });

  test('inserting and deleting a cue can be undone', () {
    final editor = testEditor(projectWithCue(text: 'one'));
    final cue = SubtitleCue(
      cueId: 'cue-2',
      sourceStartMs: 1000,
      sourceEndMs: 2000,
      text: 'two',
      timingMode: SubtitleTimingMode.segment,
    );

    editor.insertCueAfter('cue-1', cue);
    editor.deleteCue('cue-2');
    editor.undo();

    expect(editor.project.cues.map((item) => item.cueId), ['cue-1', 'cue-2']);
  });
}

SubtitleProjectEditor testEditor(SubtitleProject project) {
  var nextId = 1;
  return SubtitleProjectEditor(
    project: project,
    idGenerator: () => 'generated-${nextId++}',
    now: () => DateTime.utc(2026, 7, 20, 12),
  );
}

SubtitleProject wordTimedProject() => projectWithCue(
      text: 'คำเดิม',
      words: const [
        SubtitleWord(
          wordId: 'word-1',
          text: 'คำเดิม',
          sourceStartMs: 0,
          sourceEndMs: 1000,
        ),
      ],
      timingMode: SubtitleTimingMode.word,
    );

SubtitleProject twoCueProject(String first, String second) => SubtitleProject(
      schemaVersion: 1,
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      sourceDurationMs: 2000,
      language: 'th',
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 0,
          sourceEndMs: 1000,
          text: first,
          timingMode: SubtitleTimingMode.segment,
        ),
        SubtitleCue(
          cueId: 'cue-2',
          sourceStartMs: 1000,
          sourceEndMs: 2000,
          text: second,
          timingMode: SubtitleTimingMode.segment,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

SubtitleProject projectWithCue({
  required String text,
  List<SubtitleWord> words = const [],
  SubtitleTimingMode timingMode = SubtitleTimingMode.segment,
}) =>
    SubtitleProject(
      schemaVersion: 1,
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      sourceDurationMs: 2000,
      language: 'th',
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 0,
          sourceEndMs: 1000,
          text: text,
          words: words,
          timingMode: timingMode,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );
