import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_draft_store.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart';

void main() {
  test('restores a matching draft and keeps edit actions undoable', () async {
    final initial = _project();
    final draft = initial.copyWith(
      cues: [initial.cues.first.copyWith(text: 'ฉบับร่าง')],
      revision: 3,
    );
    final store = _MemoryDraftStore(draft);
    final controller = SubtitleStudioController(
      initialProject: initial,
      draftStore: store,
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-cue',
      autosaveDelay: Duration.zero,
    );

    await controller.initialize();
    expect(controller.project.cues.first.text, 'ฉบับร่าง');

    controller.stageSelectedCueText('แก้แล้ว');
    await controller.flushPendingText();
    expect(controller.project.cues.first.text, 'แก้แล้ว');
    controller.undo();
    expect(controller.project.cues.first.text, 'ฉบับร่าง');
    controller.redo();
    expect(controller.project.cues.first.text, 'แก้แล้ว');
  });

  test('ignores a draft from an older cue segmentation identity', () async {
    final initial = _project().copyWith(projectId: 'project-cue-v2');
    final oldDraft = initial.copyWith(
      projectId: 'project-cue-v1',
      cues: [initial.cues.first.copyWith(text: 'มีของให')],
      revision: 3,
    );
    final controller = SubtitleStudioController(
      initialProject: initial,
      draftStore: _MemoryDraftStore(oldDraft),
      now: () => DateTime.utc(2026, 7, 27, 12),
      idGenerator: () => 'new-cue',
    );

    await controller.initialize();

    expect(controller.project.toJson(), initial.toJson());
  });

  test('ignores a matching draft whose non-word cue keeps stale words',
      () async {
    final initial = _project();
    final invalidDraft = initial.copyWith(
      cues: [
        initial.cues.first.copyWith(
          words: const [
            SubtitleWord(
              wordId: 'stale-word',
              text: 'สวัสดีค่ะ',
              sourceStartMs: 0,
              sourceEndMs: 2000,
            ),
          ],
        ),
      ],
      revision: 2,
    );
    final controller = SubtitleStudioController(
      initialProject: initial,
      draftStore: _MemoryDraftStore(invalidDraft),
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-cue',
    );

    await controller.initialize();

    expect(controller.project.toJson(), initial.toJson());
    expect(controller.validationMessage, isNotNull);
  });

  test('rejects an empty cue without corrupting the project', () async {
    final controller = SubtitleStudioController(
      initialProject: _project(),
      draftStore: _MemoryDraftStore(),
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-cue',
      autosaveDelay: Duration.zero,
    );
    await controller.initialize();

    controller.stageSelectedCueText('   ');
    final saved = await controller.flushPendingText();

    expect(saved, isFalse);
    expect(controller.project.cues.first.text, 'สวัสดีค่ะ');
    expect(controller.validationMessage, isNotNull);
  });

  test('starts on the first cue that remains in the AI-selected result',
      () async {
    final initial = _project().copyWith(
      cues: [
        _project().cues.first,
        SubtitleCue(
          cueId: 'cue-2',
          sourceStartMs: 2500,
          sourceEndMs: 4000,
          text: 'ประโยคที่อยู่ในคลิป',
          timingMode: SubtitleTimingMode.segment,
        ),
      ],
      cutRanges: const [
        SubtitleCutRange(sourceStartMs: 0, sourceEndMs: 2000),
      ],
    );
    final controller = SubtitleStudioController(
      initialProject: initial,
      draftStore: _MemoryDraftStore(),
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-cue',
    );

    await controller.initialize();

    expect(controller.selectedCueId, 'cue-2');
  });

  test('does not fall back to the selected cue while playing through a gap',
      () async {
    final controller = SubtitleStudioController(
      initialProject: _project(),
      draftStore: _MemoryDraftStore(),
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-cue',
    );
    await controller.initialize();

    expect(
      controller.previewCueAt(1000, isPlaying: true)?.cueId,
      'cue-1',
    );
    expect(controller.previewCueAt(2500, isPlaying: true), isNull);
    expect(
      controller.previewCueAt(2500, isPlaying: false)?.cueId,
      'cue-1',
    );
  });

  test('supports timing, split, merge, add, delete, style, and autosave',
      () async {
    var nextId = 0;
    final store = _MemoryDraftStore();
    final controller = SubtitleStudioController(
      initialProject: _project(),
      draftStore: store,
      now: () => DateTime.utc(2026, 7, 22, 12),
      idGenerator: () => 'new-${nextId++}',
      autosaveDelay: Duration.zero,
    );
    await controller.initialize();

    expect(controller.adjustSelectedTiming(endDeltaMs: -200), isTrue);
    expect(controller.splitSelectedCue(), isTrue);
    expect(controller.mergeSelectedWithNext(), isTrue);
    expect(controller.addCueAfterSelected(), isTrue);
    expect(controller.deleteSelectedCue(), isTrue);
    controller.updateDefaultStyle(
      copySubtitleStyle(
        controller.project.defaultStyle,
        fontId: 'Anuphan',
        fontSize: 30,
        alignment: SubtitleAlignment.middle,
      ),
    );
    await controller.saveNow();

    expect(controller.project.defaultStyle.fontId, 'Anuphan');
    expect(controller.project.defaultStyle.fontSize, 30);
    expect(controller.project.defaultStyle.alignment, SubtitleAlignment.middle);
    expect(store.saved?.revision, controller.project.revision);
  });
}

class _MemoryDraftStore implements SubtitleDraftStore {
  _MemoryDraftStore([this.saved]);

  SubtitleProject? saved;

  @override
  Future<void> deleteDraft(String projectId) async => saved = null;

  @override
  Future<SubtitleProject?> loadDraft(String projectId) async => saved;

  @override
  Future<void> saveDraft(SubtitleProject project) async => saved = project;
}

SubtitleProject _project() => SubtitleProject(
      schemaVersion: 3,
      projectId: 'project-1',
      sourceFingerprint: 'source-1',
      sourceDurationMs: 5000,
      language: 'th',
      cues: [
        SubtitleCue(
          cueId: 'cue-1',
          sourceStartMs: 0,
          sourceEndMs: 2000,
          text: 'สวัสดีค่ะ',
          timingMode: SubtitleTimingMode.segment,
        ),
      ],
      defaultStyle: SubtitleStyle.defaults,
      cutRanges: const [],
      revision: 0,
      createdAt: DateTime.utc(2026, 7, 22),
      updatedAt: DateTime.utc(2026, 7, 22),
    );
