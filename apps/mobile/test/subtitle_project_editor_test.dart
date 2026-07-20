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

  test('merge joins Thai script directly', () {
    expect(mergedText('ภาษา', 'ไทย'), 'ภาษาไทย');
  });

  test('merge inserts one space between English words', () {
    expect(mergedText('hello', 'world', language: 'en'), 'hello world');
  });

  test('merge preserves existing boundary whitespace without adding more', () {
    expect(mergedText('hello ', 'world', language: 'en'), 'hello world');
    expect(mergedText('hello', ' world', language: 'en'), 'hello world');
    expect(mergedText('hello ', ' world', language: 'en'), 'hello world');
  });

  test('merge does not add spaces around closing or prefix punctuation', () {
    expect(mergedText('hello', '!', language: 'en'), 'hello!');
    expect(mergedText('(', 'hello', language: 'en'), '(hello');
    expect(mergedText('฿', '100', language: 'th'), '฿100');
  });

  test('merge spaces numeric and mixed Thai Latin boundaries', () {
    expect(mergedText('ราคา', '100'), 'ราคา 100');
    expect(mergedText('สินค้า', 'Pro'), 'สินค้า Pro');
  });

  test('merge spaces other word-like boundaries for non-Thai projects', () {
    expect(mergedText('商品', '説明', language: 'ja'), '商品 説明');
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

  test('insertCueAt can add the first cue to an empty project', () {
    final editor = testEditor(emptyProject());
    final cue = testCue(cueId: 'cue-1', text: 'first');

    editor.insertCueAt(0, cue);

    expect(editor.project.cues, [same(cue)]);
    expect(editor.canUndo, isTrue);
  });

  test('insertCueAt can add a cue after deleting the last cue', () {
    final editor = testEditor(projectWithCue(text: 'old'));
    final replacement = testCue(cueId: 'cue-2', text: 'replacement');

    editor.deleteCue('cue-1');
    editor.insertCueAt(0, replacement);

    expect(editor.project.cues.single, same(replacement));
    editor.undo();
    expect(editor.project.cues, isEmpty);
    editor.undo();
    expect(editor.project.cues.single.text, 'old');
  });

  test('invalid insert index leaves project and history unchanged', () {
    final editor = testEditor(emptyProject());
    final before = editor.project.toJson();

    for (final index in [-1, 1]) {
      expect(
        () => editor.insertCueAt(index, testCue()),
        throwsA(isA<SubtitleProjectValidationException>()),
      );
    }

    expect(editor.project.toJson(), before);
    expect(editor.canUndo, isFalse);
    expect(editor.canRedo, isFalse);
  });

  test('split keeps visual metadata on both cues but sound only on first', () {
    final editor = testEditor(
      projectWithCue(
        text: 'one two',
        styleOverride: SubtitleStyle.defaults,
        positionOverride: SubtitleAlignment.top,
        soundEffect: 'pop',
      ),
    );

    editor.splitCue('cue-1', graphemeOffset: 3);

    expect(
      editor.project.cues.map((cue) => cue.styleOverride),
      everyElement(same(SubtitleStyle.defaults)),
    );
    expect(
      editor.project.cues.map((cue) => cue.positionOverride),
      everyElement(SubtitleAlignment.top),
    );
    expect(editor.project.cues.map((cue) => cue.soundEffect), ['pop', null]);
  });

  test('merge accepts equal visual metadata values and retains the first', () {
    final firstStyle = styleWithFontSize(22);
    final secondStyle = styleWithFontSize(22);
    final editor = testEditor(
      twoCueProject(
        'one',
        'two',
        firstStyle: firstStyle,
        secondStyle: secondStyle,
        firstPosition: SubtitleAlignment.top,
        secondPosition: SubtitleAlignment.top,
      ),
    );

    editor.mergeWithNext('cue-1');

    expect(editor.project.cues.single.styleOverride, same(firstStyle));
    expect(
      editor.project.cues.single.positionOverride,
      SubtitleAlignment.top,
    );
  });

  test('merge rejects different visual metadata without changing history', () {
    final editor = testEditor(
      twoCueProject(
        'one',
        'two',
        firstStyle: styleWithFontSize(22),
        secondStyle: styleWithFontSize(24),
      ),
    );
    final before = editor.project.toJson();

    expect(
      () => editor.mergeWithNext('cue-1'),
      throwsA(isA<SubtitleProjectValidationException>()),
    );

    expect(editor.project.toJson(), before);
    expect(editor.canUndo, isFalse);
    expect(editor.canRedo, isFalse);
  });

  test('merge rejects different position overrides atomically', () {
    final editor = testEditor(
      twoCueProject(
        'one',
        'two',
        firstPosition: SubtitleAlignment.top,
        secondPosition: SubtitleAlignment.bottom,
      ),
    );
    final before = editor.project.toJson();

    expect(
      () => editor.mergeWithNext('cue-1'),
      throwsA(isA<SubtitleProjectValidationException>()),
    );

    expect(editor.project.toJson(), before);
    expect(editor.canUndo, isFalse);
  });

  test('merge rejects a second cue sound effect atomically', () {
    final editor = testEditor(
      twoCueProject('one', 'two', secondSoundEffect: 'ding'),
    );
    final before = editor.project.toJson();

    expect(
      () => editor.mergeWithNext('cue-1'),
      throwsA(isA<SubtitleProjectValidationException>()),
    );

    expect(editor.project.toJson(), before);
    expect(editor.canUndo, isFalse);
    expect(editor.canRedo, isFalse);
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

String mergedText(String first, String second, {String language = 'th'}) {
  final editor = testEditor(
    twoCueProject(first, second, language: language),
  );
  editor.mergeWithNext('cue-1');
  return editor.project.cues.single.text;
}

SubtitleProject twoCueProject(
  String first,
  String second, {
  String language = 'th',
  SubtitleStyle? firstStyle,
  SubtitleStyle? secondStyle,
  SubtitleAlignment? firstPosition,
  SubtitleAlignment? secondPosition,
  String? firstSoundEffect,
  String? secondSoundEffect,
}) =>
    SubtitleProject(
      schemaVersion: 1,
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      sourceDurationMs: 2000,
      language: language,
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 0,
          sourceEndMs: 1000,
          text: first,
          timingMode: SubtitleTimingMode.segment,
          styleOverride: firstStyle,
          positionOverride: firstPosition,
          soundEffect: firstSoundEffect,
        ),
        SubtitleCue(
          cueId: 'cue-2',
          sourceStartMs: 1000,
          sourceEndMs: 2000,
          text: second,
          timingMode: SubtitleTimingMode.segment,
          styleOverride: secondStyle,
          positionOverride: secondPosition,
          soundEffect: secondSoundEffect,
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
  SubtitleStyle? styleOverride,
  SubtitleAlignment? positionOverride,
  String? soundEffect,
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
          styleOverride: styleOverride,
          positionOverride: positionOverride,
          soundEffect: soundEffect,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

SubtitleProject emptyProject() => SubtitleProject(
      schemaVersion: 1,
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      sourceDurationMs: 2000,
      language: 'th',
      cues: const [],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

SubtitleCue testCue({String cueId = 'cue-new', String text = 'new'}) =>
    SubtitleCue(
      cueId: cueId,
      sourceStartMs: 0,
      sourceEndMs: 1000,
      text: text,
      timingMode: SubtitleTimingMode.segment,
    );

SubtitleStyle styleWithFontSize(double fontSize) => SubtitleStyle(
      fontId: SubtitleStyle.defaults.fontId,
      fontWeight: SubtitleStyle.defaults.fontWeight,
      fontSize: fontSize,
      textColor: SubtitleStyle.defaults.textColor,
      activeWordColor: SubtitleStyle.defaults.activeWordColor,
      outlineColor: SubtitleStyle.defaults.outlineColor,
      outlineWidth: SubtitleStyle.defaults.outlineWidth,
      shadowColor: SubtitleStyle.defaults.shadowColor,
      shadowDepth: SubtitleStyle.defaults.shadowDepth,
      alignment: SubtitleStyle.defaults.alignment,
      normalizedX: SubtitleStyle.defaults.normalizedX,
      normalizedY: SubtitleStyle.defaults.normalizedY,
      maxLines: SubtitleStyle.defaults.maxLines,
      animation: SubtitleStyle.defaults.animation,
    );
