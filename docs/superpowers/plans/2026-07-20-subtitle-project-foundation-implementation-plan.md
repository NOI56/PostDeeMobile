# Subtitle Project Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tested, non-visual Subtitle Studio foundation: a versioned subtitle project, safe editing/undo operations, a mapper from the existing AI recipe, and an injectable local draft store.

**Architecture:** Add focused pure-Dart files under `features/ai_editing/subtitle_studio/`. Keep all cue times on the original source timeline, treat raw provider word timing as untrusted, and make every committed edit pass the same project validator. This milestone does not change the customer flow, API, Prisma, renderer, package rules, or quota behavior.

**Tech Stack:** Flutter/Dart, `characters`, `dart:convert`, `dart:io`, Flutter Test.

## Global Constraints

- Write each focused test first and run it to observe the expected failure.
- Modify only new Subtitle Studio files and their new focused tests in this milestone.
- Do not modify `ai_editing_screen.dart`, `postdee_api_client.dart`, API routes, Prisma, package rules, or the FFmpeg renderer.
- Do not trust `recipe.transcript.words` for active-word highlighting; the current backend has not yet returned its timing-quality decision to mobile.
- Store all times as integer milliseconds on the original source timeline.
- Reject non-finite/invalid converted timing, overlapping cues, empty IDs/text, and unsupported schema versions.
- Preserve Thai combining marks and emoji grapheme clusters during split operations.
- Keep undo/redo to at most 50 snapshots.
- Stage and commit only the exact files owned by each task; the worktree contains unrelated user changes.

---

### Task 1: Versioned Subtitle Project Domain

**Files:**
- Create: `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project.dart`
- Test: `apps/mobile/test/subtitle_project_test.dart`

**Interfaces:**
- Produces: `SubtitleTimingMode`, `SubtitleAlignment`, `SubtitleWord`, `SubtitleCue`, `SubtitleStyle`, `SubtitleCutRange`, `SubtitleProject`, `SubtitleProjectValidationException`, `validateSubtitleProject(SubtitleProject)`.
- Consumed by: Tasks 2–4.

- [ ] **Step 1: Write the failing domain/JSON tests**

Create `apps/mobile/test/subtitle_project_test.dart` with tests equivalent to:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:postdee_mobile/features/ai_editing/subtitle_studio/subtitle_project.dart';

void main() {
  SubtitleProject validProject() => SubtitleProject(
        schemaVersion: 1,
        projectId: 'project-1',
        sourceFingerprint: 'source-1',
        sourceDurationMs: 5000,
        language: 'th',
        cues: const [
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
    final invalid = validProject().copyWith(cues: const [
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
    final invalid = validProject().copyWith(cues: const [
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
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_test.dart
```

Expected: FAIL because `subtitle_project.dart` and all domain types are missing.

- [ ] **Step 3: Implement the immutable domain and validator**

Create `subtitle_project.dart` with:

- enums whose JSON values are the enum names;
- immutable values and `copyWith` for cue/project;
- `toJson`/`fromJson` for every persisted value;
- `SubtitleStyle.defaults` using Prompt 700, size 22, `#FFFFFF` text,
  `#00E5A8` active word, black outline/shadow, bottom alignment, two rows;
- a validator that enforces the Global Constraints and validates ordered word
  timing only when `timingMode == SubtitleTimingMode.word`;
- defensive `List.unmodifiable` copies in project/cue constructors;
- `SubtitleProject.fromJson` calling `validateSubtitleProject` before returning.

The public signatures must be:

```dart
enum SubtitleTimingMode { word, segment, estimated }
enum SubtitleAlignment { top, middle, bottom }

class SubtitleProjectValidationException implements Exception {
  const SubtitleProjectValidationException(this.message);
  final String message;
}

void validateSubtitleProject(SubtitleProject project);
```

`SubtitleCue.words` defaults to `const []`, `SubtitleWord.separatorAfter`
defaults to an empty string, and all persisted colour fields use uppercase
`#RRGGBB` strings.

- [ ] **Step 4: Run the test and verify GREEN**

Run the same focused command. Expected: all `subtitle_project_test.dart` tests PASS.

- [ ] **Step 5: Commit only Task 1 files**

```powershell
git add -- apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project.dart apps/mobile/test/subtitle_project_test.dart
git commit -m "feat(mobile): add subtitle project domain"
```

---

### Task 2: Safe Editing and Bounded Undo/Redo

**Files:**
- Create: `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_editor.dart`
- Test: `apps/mobile/test/subtitle_project_editor_test.dart`

**Interfaces:**
- Consumes: `SubtitleProject`, `SubtitleCue`, `SubtitleTimingMode`, `validateSubtitleProject` from Task 1.
- Produces: `SubtitleProjectEditor`, `SubtitleIdGenerator`, `SubtitleNow`.
- Consumed by: the later Subtitle Studio controller/UI.

- [ ] **Step 1: Write failing editor tests**

Tests must cover:

```dart
test('editing mapped word text disables unsafe word highlight', () {
  final editor = testEditor(wordTimedProject());

  editor.updateCueText('cue-1', 'แก้คำแล้ว');

  expect(editor.project.cues.single.text, 'แก้คำแล้ว');
  expect(
    editor.project.cues.single.timingMode,
    SubtitleTimingMode.estimated,
  );
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
```

The test helpers inject a deterministic ID generator and fixed `now` callback.

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_editor_test.dart
```

Expected: FAIL because `SubtitleProjectEditor` is missing.

- [ ] **Step 3: Implement minimal editor operations**

Provide:

```dart
typedef SubtitleIdGenerator = String Function();
typedef SubtitleNow = DateTime Function();

class SubtitleProjectEditor {
  SubtitleProjectEditor({
    required SubtitleProject project,
    required SubtitleIdGenerator idGenerator,
    required SubtitleNow now,
    int historyLimit = 50,
  });

  SubtitleProject get project;
  bool get canUndo;
  bool get canRedo;

  void updateCueText(String cueId, String text);
  void updateCueTiming(String cueId, {required int startMs, required int endMs});
  void insertCueAfter(String cueId, SubtitleCue cue);
  void deleteCue(String cueId);
  void splitCue(String cueId, {required int graphemeOffset});
  void mergeWithNext(String cueId);
  void undo();
  void redo();
}
```

Every mutation builds a complete next project, increments `revision`, replaces
`updatedAt`, validates it, and only then pushes the prior snapshot. A failed
mutation must not change project/history. A new mutation clears redo history.
Use `package:characters/characters.dart` for split offsets.

- [ ] **Step 4: Run Task 1–2 tests and verify GREEN**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_test.dart test\subtitle_project_editor_test.dart
```

Expected: both files PASS.

- [ ] **Step 5: Commit only Task 2 files**

```powershell
git add -- apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_editor.dart apps/mobile/test/subtitle_project_editor_test.dart
git commit -m "feat(mobile): add safe subtitle editing history"
```

---

### Task 3: Existing AI Recipe Mapper

**Files:**
- Create: `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart`
- Test: `apps/mobile/test/subtitle_project_mapper_test.dart`

**Interfaces:**
- Consumes: `AiEditRecipeResult` from `core/network/postdee_api_client.dart` and Task 1 domain types.
- Produces: `mapAiEditRecipeToSubtitleProject(...) -> SubtitleProject`.
- Consumed by: later AI Editing integration.

- [ ] **Step 1: Write failing mapper tests**

Use this complete minimal recipe fixture:

```dart
AiEditRecipeResult recipeFixture({bool includeRawWords = false}) {
  return AiEditRecipeResult(
    version: 1,
    status: 'ready',
    renderMode: 'mobile-ffmpeg',
    transcript: AiEditTranscriptResult(
      text: 'หนึ่งสอง',
      language: 'th',
      durationSeconds: 5,
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
    subtitles: const AiEditSubtitlesResult(
      enabled: true,
      segments: [
        ClipTranscriptSegment(text: 'หนึ่ง', start: 0.1, end: 1.2),
        ClipTranscriptSegment(text: 'สอง', start: 1.5, end: 2.5),
      ],
      style: AiEditSubtitleStyleResult(
        mode: 'outline',
        color: '#FFFFFF',
        wordsPerLine: 2,
        position: 'bottom',
      ),
    ),
    cutRanges: const [AiEditCut(start: 3, end: 4)],
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
```

Then verify:

```dart
test('maps prepared subtitle segments on the source timeline', () {
  final project = mapAiEditRecipeToSubtitleProject(
    recipe: recipeFixture(),
    projectId: 'project-1',
    sourceFingerprint: 'source-1',
    now: DateTime.utc(2026, 7, 20),
  );

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

test('generates stable cue ids for the same recipe', () {
  final first = mapFixture();
  final second = mapFixture();
  expect(
    first.cues.map((cue) => cue.cueId),
    second.cues.map((cue) => cue.cueId),
  );
});
```

- [ ] **Step 2: Run the mapper test and verify RED**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_mapper_test.dart
```

Expected: FAIL because the mapper does not exist.

- [ ] **Step 3: Implement the pure mapper**

Use this signature:

```dart
SubtitleProject mapAiEditRecipeToSubtitleProject({
  required AiEditRecipeResult recipe,
  required String projectId,
  required String sourceFingerprint,
  required DateTime now,
});
```

Rules:

- convert finite seconds to rounded integer milliseconds;
- discard empty subtitle segments, sort by start/end, then validate;
- create deterministic IDs `cue-<one-based-index>-<startMs>-<endMs>`;
- map current segments as `SubtitleTimingMode.segment` with no words;
- map removal ranges from `recipe.cutRanges` to `SubtitleCutRange`;
- use Prompt defaults, recipe hex colour only if it matches `#RRGGBB`, and
  top/bottom alignment from the current recipe style;
- keep both timestamps equal to the supplied `now` and revision zero;
- throw `SubtitleProjectValidationException` for zero/invalid duration or
  overlapping/malformed prepared segments.

- [ ] **Step 4: Run Task 1 and mapper tests and verify GREEN**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_test.dart test\subtitle_project_mapper_test.dart
```

- [ ] **Step 5: Commit only Task 3 files**

```powershell
git add -- apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart apps/mobile/test/subtitle_project_mapper_test.dart
git commit -m "feat(mobile): map AI recipes to subtitle projects"
```

---

### Task 4: Injectable Versioned Draft Store

**Files:**
- Create: `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_draft_store.dart`
- Test: `apps/mobile/test/subtitle_draft_store_test.dart`

**Interfaces:**
- Consumes: `SubtitleProject.toJson/fromJson` from Task 1.
- Produces: `SubtitleDraftStore`, `FileSubtitleDraftStore`.
- Consumed by: later Subtitle Studio controller/integration.

- [ ] **Step 1: Write failing file-store tests**

Use a test-owned temporary directory and cover:

```dart
test('saves and loads one versioned project', () async {
  final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
  final project = validProject();

  await store.saveDraft(project);

  expect((await store.loadDraft(project.projectId))?.toJson(), project.toJson());
});

test('returns null for a corrupt draft without deleting it', () async {
  final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
  final file = store.fileForProject('project-1');
  await file.parent.create(recursive: true);
  await file.writeAsString('{broken');

  expect(await store.loadDraft('project-1'), isNull);
  expect(await file.exists(), isTrue);
});

test('uses an encoded filename for unsafe project ids', () {
  final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
  final file = store.fileForProject('../other');

  expect(file.parent.path, tempDirectory.path);
  expect(file.path, isNot(contains('..')));
});

test('delete removes only the requested project draft', () async {
  final store = FileSubtitleDraftStore(rootDirectory: tempDirectory);
  await store.saveDraft(projectWithId('one'));
  await store.saveDraft(projectWithId('two'));

  await store.deleteDraft('one');

  expect(await store.loadDraft('one'), isNull);
  expect(await store.loadDraft('two'), isNotNull);
});
```

- [ ] **Step 2: Run the draft-store test and verify RED**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_draft_store_test.dart
```

- [ ] **Step 3: Implement the injectable file store**

Use:

```dart
abstract class SubtitleDraftStore {
  Future<SubtitleProject?> loadDraft(String projectId);
  Future<void> saveDraft(SubtitleProject project);
  Future<void> deleteDraft(String projectId);
}

class FileSubtitleDraftStore implements SubtitleDraftStore {
  FileSubtitleDraftStore({required Directory rootDirectory});
  File fileForProject(String projectId);
}
```

Encode unsafe IDs with `base64Url.encode(utf8.encode(projectId))`, strip
padding, then encode each base64url ASCII code unit as fixed-width lowercase
hex. This keeps filenames injective on case-insensitive filesystems. Reject IDs
over 90 UTF-8 bytes before creating a path so the longest `.json.backup`
component stays under 255 bytes. Serialize load/save/delete operations per
encoded project ID. Save to a sibling `.next` file with `flush: true`,
decode/validate that file, rotate the old target to `.backup`, rename `.next`
to the target, then delete the backup. On promotion failure, restore the
backup. If an interrupted save left no target, recover a valid matching
`.next` first or a valid matching `.backup` second. Loading malformed JSON or
an unsupported schema returns null without deleting the original file.
Deletion targets only `fileForProject(projectId)` and its `.next/.backup`
siblings inside the injected root.

- [ ] **Step 4: Run all foundation tests and analyze**

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\subtitle_project_test.dart test\subtitle_project_editor_test.dart test\subtitle_project_mapper_test.dart test\subtitle_draft_store_test.dart
..\..\.tools\flutter\bin\flutter.bat analyze
```

Expected: all four focused test files pass and analyze reports no new issues.

- [ ] **Step 5: Commit only Task 4 files**

```powershell
git add -- apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_draft_store.dart apps/mobile/test/subtitle_draft_store_test.dart
git commit -m "feat(mobile): persist subtitle project drafts"
```

---

## Foundation Completion Gate

- The four focused test files pass together.
- Flutter analyze has no new issues.
- `git diff --check` is clean for the new files.
- The current AI Editing UI, API contract, renderer, quota, and package behavior
  are unchanged.
- The next implementation plan may consume these interfaces to build the
  feature-flagged Subtitle Studio screen and live preview.
