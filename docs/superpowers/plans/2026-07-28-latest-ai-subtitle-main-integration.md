# Latest AI Editing and Subtitle Studio Main Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `main` the single authoritative PostDee app containing the latest approved AI result-review and Subtitle Studio behavior while retaining only `ตัดคลิปเป็น EP` in the uploader tools.

**Architecture:** Port behavior from `codex/elevenlabs-scribe-v2-staging` into a new branch created from local `main`, one dependency-complete unit at a time. Preserve the existing setup → render → result review flow, add the validated per-cue word contract needed by active-word subtitles, and keep the dirty root worktree and unrelated staging/provider changes out of the integration.

**Tech Stack:** Flutter/Dart, Express/TypeScript, Vitest, FFmpegKit/libass, bundled OFL fonts, Git worktrees, Android Pixel 8 emulator.

## Global Constraints

- `main` remains the sole app source used by the desktop launcher.
- Subtitle Studio opens only from the explicit edit-subtitles action on result review.
- Automatic Thai subtitles remain one line, inside the video safe area, with readable base characters, vowels, and tone marks.
- Active-word highlighting uses only server-validated word timing; unsafe timing renders a static cue.
- Editing, preview, and re-render do not consume another AI minute.
- The uploader continues to expose only `ตัดคลิปเป็น EP`.
- Cover editing, automatic watermark controls, advanced upload mode, and dirty-root-only experiments remain excluded.
- Do not merge `codex/elevenlabs-scribe-v2-staging` wholesale.
- Do not delete, reset, rebase, or rewrite existing branches/worktrees.
- Use `apply_patch` for text edits; copy reviewed binary TTF assets explicitly because binary font files cannot be represented by a text patch.

---

## Execution Setup

Before Task 1, use `superpowers:using-git-worktrees`.

```powershell
cd D:\PostDeeMobile
git rev-parse --git-dir
git rev-parse --git-common-dir
git rev-parse --show-superproject-working-tree
git check-ignore .worktrees
git worktree add .worktrees\latest-ai-subtitle-main -b codex/latest-ai-subtitle-main main
```

Expected:

- `.worktrees` is ignored.
- The new worktree is
  `D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main`.
- The new branch starts at the current local `main`, including the approved
  design and this plan.
- The existing `main` worktree remains checked out on `main`, so the desktop
  launcher continues to resolve it.

Set up and establish the baseline:

```powershell
cd D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\api
npm.cmd install
npm.cmd run test
npm.cmd run build

cd D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\mobile
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat pub get
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test
```

If any baseline command fails, stop and report the exact pre-existing failure
before porting code.

---

### Task 1: Add the validated subtitle-word API contract

**Files:**

- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.test.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRecipe.ts`
- Modify only if route serialization drops the field:
  `apps/api/src/modules/aiEdits/aiEditRoutes.test.ts`
- Modify only if route serialization drops the field:
  `apps/api/src/modules/aiEdits/aiEditRoutes.ts`

**Interfaces:**

- Produces: `subtitles.segments[].words`
  as `Array<{ word: string; start: number; end: number }>`
- Contract:
  - field absent is reserved for legacy deployed responses;
  - `words: []` is authoritative and means timing is unsafe/unavailable;
  - non-empty `words` must reconstruct the cue text using only allowed untimed
    whitespace, punctuation, and symbols, with exact case and Unicode code
    points;
  - each word must be finite, ordered, non-overlapping, and bounded by its cue.
- Consumed by Task 2 through `ClipTranscriptSegment.words`.

- [ ] **Step 1: Add failing recipe tests for safe and unsafe cue timing**

Add focused cases to `aiEditRecipe.test.ts` using the file's existing
`buildRecipe` fixture:

```ts
it('adds server-validated word timings to each subtitle cue', () => {
  const words = [
    { word: 'Hello', start: 0, end: 0.4 },
    { word: 'world', start: 0.4, end: 0.8 },
    { word: 'again', start: 1.5, end: 2.3 }
  ];
  const recipe = buildRecipe({
    capabilities: { subtitle: true },
    language: 'en',
    text: 'Hello world again',
    durationSeconds: 2.3,
    settings: { subtitleWordsPerLine: 2 },
    segments: [{ text: 'Hello world again', start: 0, end: 2.3 }],
    words
  });

  expect(recipe.subtitles.segments).toEqual([
    { text: 'Hello world', start: 0, end: 0.8, words: words.slice(0, 2) },
    { text: 'again', start: 1.5, end: 2.3, words: words.slice(2) }
  ]);
});

it('returns an authoritative empty word list for unsafe cue timing', () => {
  const recipe = buildRecipe({
    capabilities: { subtitle: true },
    language: 'en',
    text: 'one two',
    durationSeconds: 1.2,
    segments: [{ text: 'one two', start: 0, end: 1.2 }],
    words: [
      { word: 'one', start: 0, end: 0.7 },
      { word: 'two', start: 0.6, end: 1.2 }
    ]
  });

  expect(recipe.subtitles.segments[0]?.words).toEqual([]);
});
```

- [ ] **Step 2: Run the recipe test and verify RED**

```powershell
cd apps\api
npm.cmd run test -- src/modules/aiEdits/aiEditRecipe.test.ts
```

Expected: FAIL because current `main` subtitle segments do not expose
per-cue `words`.

- [ ] **Step 3: Implement the smallest validated-word attachment**

Port only the word-to-cue validation needed by the new tests from
`codex/elevenlabs-scribe-v2-staging`. Add a focused helper with this shape:

```ts
const attachValidatedSubtitleWords = (
  segments: TranscriptSegment[],
  words: TranscriptWord[]
): AiEditSubtitleSegment[] =>
  segments.map((segment) => {
    const cueWords = words.filter(
      (word) => word.start < segment.end && word.end > segment.start
    );
    const timingIsSafe =
      cueWords.length > 0 &&
      cueWords.every(
        (word, index) =>
          Number.isFinite(word.start) &&
          Number.isFinite(word.end) &&
          word.start >= segment.start - subtitleWordTimingToleranceSeconds &&
          word.end <= segment.end + subtitleWordTimingToleranceSeconds &&
          word.end > word.start &&
          (index === 0 ||
            word.start >=
              cueWords[index - 1]!.end -
                subtitleWordTimingToleranceSeconds)
      );
    const textMatches =
      normalizeTranscriptTextForCoverage(
        cueWords.map((word) => word.word).join('')
      ) === normalizeTranscriptTextForCoverage(segment.text);

    return {
      ...segment,
      words: timingIsSafe && textMatches ? cueWords : []
    };
  });
```

Call it after final subtitle regrouping, word-count constraints, and boundary
repair. Never attach words before cue boundaries are final.

- [ ] **Step 4: Run focused API tests and verify GREEN**

```powershell
npm.cmd run test -- src/modules/aiEdits/aiEditRecipe.test.ts
npm.cmd run test -- src/modules/aiEdits/aiEditRoutes.test.ts
npm.cmd run build
```

Expected: PASS with no TypeScript errors.

- [ ] **Step 5: Commit the API contract**

```powershell
git add apps/api/src/modules/aiEdits/aiEditRecipe.ts apps/api/src/modules/aiEdits/aiEditRecipe.test.ts apps/api/src/modules/aiEdits/aiEditRoutes.ts apps/api/src/modules/aiEdits/aiEditRoutes.test.ts
git commit -m "feat(ai-edit): expose validated subtitle cue timing"
```

Stage only files actually modified.

---

### Task 2: Parse validated words and map safe Subtitle Studio projects

**Files:**

- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `apps/mobile/test/postdee_api_client_test.dart`
- Create: `apps/mobile/lib/features/ai_editing/subtitle_word_timing_safety.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_mapper.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_project_identity.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart`
- Modify:
  `apps/mobile/test/subtitle_project_test.dart`
- Modify:
  `apps/mobile/test/subtitle_project_mapper_test.dart`
- Modify:
  `apps/mobile/test/subtitle_project_identity_test.dart`
- Modify:
  `apps/mobile/test/subtitle_studio_controller_test.dart`
- Modify only where identity behavior changes:
  `apps/mobile/test/subtitle_draft_store_test.dart`

**Interfaces:**

- Consumes: Task 1 `subtitles.segments[].words`
- Produces:

```dart
class ClipTranscriptSegment {
  final List<AiEditTranscriptWordResult>? words;
}

bool containsOnlyUntimedSubtitleSeparators(String text);
```

- `null` word data means a legacy API response may use the existing safe raw
  transcript fallback.
- An empty list blocks raw timing fallback for that cue.
- A non-word-timed cue may not retain stale `SubtitleWord` entries in a restored
  draft.

- [ ] **Step 1: Add failing mobile contract tests**

Add these observable cases to `postdee_api_client_test.dart`:

```dart
test('subtitle segment parser preserves validated word contract presence', () {
  final legacy = ClipTranscriptSegment.fromJson({
    'text': 'legacy',
    'start': 0,
    'end': 1,
  });
  final rejected = ClipTranscriptSegment.fromJson({
    'text': 'rejected',
    'start': 1,
    'end': 2,
    'words': <Object?>[],
  });
  final validated = ClipTranscriptSegment.fromJson({
    'text': 'hello world',
    'start': 2,
    'end': 3,
    'words': [
      {'word': 'hello', 'start': 2, 'end': 2.4},
      {'word': 'world', 'start': 2.5, 'end': 3},
    ],
  });

  expect(legacy.words, isNull);
  expect(rejected.words, isEmpty);
  expect(validated.words?.map((word) => word.word), ['hello', 'world']);
});
```

Add mapper tests with literal Thai/mixed-language fixtures proving:

- authoritative empty words never fall back to fragmented raw words;
- validated words reconstruct the cue exactly;
- whitespace and punctuation may remain untimed;
- malformed, overlapping, cross-cue, and Thai-character-fragment timing
  becomes static;
- draft identity changes after server cue regrouping.

- [ ] **Step 2: Run focused tests and verify RED**

```powershell
cd apps\mobile
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\postdee_api_client_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_project_mapper_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_studio_controller_test.dart
```

Expected: FAIL because `ClipTranscriptSegment` does not yet distinguish absent,
empty, and validated cue word data.

- [ ] **Step 3: Implement strict parsing and safe mapping**

Add a parser that returns an unmodifiable list only when every item has a
string `word`, finite numeric `start`, and finite numeric `end`. Any malformed
item makes the authoritative result empty.

Add `containsOnlyUntimedSubtitleSeparators` using Unicode whitespace,
punctuation, and symbol categories. Use it when verifying that timed words
reconstruct the full cue.

Port the minimum mapper/identity/controller changes required by the failing
tests. Preserve all existing project IDs and JSON schema behavior except the
intentional cue-segmentation identity update.

- [ ] **Step 4: Run the complete Subtitle Project foundation tests**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\postdee_api_client_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_project_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_project_mapper_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_project_identity_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_project_editor_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_studio_controller_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_draft_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit safe mobile mapping**

```powershell
git add apps/mobile/lib/core/network/postdee_api_client.dart apps/mobile/lib/features/ai_editing/subtitle_word_timing_safety.dart apps/mobile/lib/features/ai_editing/subtitle_studio apps/mobile/test/postdee_api_client_test.dart apps/mobile/test/subtitle_project_test.dart apps/mobile/test/subtitle_project_mapper_test.dart apps/mobile/test/subtitle_project_identity_test.dart apps/mobile/test/subtitle_project_editor_test.dart apps/mobile/test/subtitle_studio_controller_test.dart apps/mobile/test/subtitle_draft_store_test.dart
git commit -m "feat(mobile): map validated subtitle word timing"
```

---

### Task 3: Add licensed Thai-safe subtitle fonts and one-line style rules

**Files:**

- Add reviewed binary assets:
  `apps/mobile/assets/fonts/postdee_subtitle/*.ttf`
- Add license:
  `apps/mobile/assets/fonts/postdee_subtitle/OFL.txt`
- Add reviewed binary asset:
  `apps/mobile/assets/fonts/baijamjuree/BaiJamjuree-Bold.ttf`
- Add license: `apps/mobile/assets/fonts/baijamjuree/OFL.txt`
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/lib/features/ai_editing/style_options.dart`
- Modify: `apps/mobile/test/app_theme_test.dart`
- Modify: `apps/mobile/test/style_options_test.dart`
- Create only if font regeneration remains reproducible and reviewed:
  `apps/mobile/tool/build_postdee_subtitle_font.py`

**Interfaces:**

- Produces bundled font families:
  - `PostDee Subtitle Anuphan`
  - `PostDee Subtitle Prompt`
  - `PostDee Subtitle Thai`
- Produces one-line cue sizing consumed by preview and renderer.
- Does not modify uploader widgets or global product navigation.

- [ ] **Step 1: Add failing font and one-line tests**

Add tests that verify real asset loading and observable cue behavior:

```dart
test('bundles the Thai mark-safe subtitle fonts and licenses', () {
  final manifest = File('pubspec.yaml').readAsStringSync();

  expect(manifest, contains('family: Bai Jamjuree'));
  expect(manifest, contains('family: PostDee Subtitle Thai'));
  expect(manifest, contains('family: PostDee Subtitle Anuphan'));
  expect(manifest, contains('family: PostDee Subtitle Prompt'));
  expect(
    File('assets/fonts/baijamjuree/BaiJamjuree-Bold.ttf').existsSync(),
    isTrue,
  );
  expect(File('assets/fonts/baijamjuree/OFL.txt').existsSync(), isTrue);
  expect(
    File(
      'assets/fonts/postdee_subtitle/'
      'PostDeeSubtitleAnuphan-Regular.ttf',
    ).existsSync(),
    isTrue,
  );
  expect(File('assets/fonts/postdee_subtitle/OFL.txt').existsSync(), isTrue);
});

test('keeps a single-line Thai subtitle within the character limit', () {
  const thaiCue = 'หาของของที่ตัวเองต้องการ';
  final result = rechunkSubtitleByMaxChars(
    const [
      SubtitleSegment(text: thaiCue, start: 87.84, end: 89.077),
    ],
    18,
  );

  expect(result, hasLength(2));
  expect(
    result.every((cue) => cue.text.characters.length <= 18),
    isTrue,
  );
  expect(result.map((cue) => cue.text).join(), thaiCue);
  expect(result.first.start, 87.84);
  expect(result.last.end, 89.077);
});
```

- [ ] **Step 2: Run font/style tests and verify RED**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\app_theme_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\style_options_test.dart
```

Expected: FAIL because the reviewed assets/style behavior are not yet present
on `main`.

- [ ] **Step 3: Copy only reviewed font assets**

Copy from the read-only staging worktree:

```powershell
$sourceMobile = 'D:\PostDeeMobile\.worktrees\elevenlabs-scribe-v2-staging\apps\mobile'
$targetMobile = 'D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\mobile'
Copy-Item -LiteralPath "$sourceMobile\assets\fonts\postdee_subtitle" -Destination "$targetMobile\assets\fonts" -Recurse
Copy-Item -LiteralPath "$sourceMobile\assets\fonts\baijamjuree" -Destination "$targetMobile\assets\fonts" -Recurse
```

Before staging, verify every copied font has its OFL license and compare SHA256
hashes against the staging source. Do not copy any other directory.

- [ ] **Step 4: Register fonts and port one-line rules**

Use `apply_patch` for `pubspec.yaml` and `style_options.dart`. Register only the
font files actually consumed by preview/render. Port the Thai cue-width and
word-limit behavior without copying unrelated style presets.

- [ ] **Step 5: Verify fonts and style**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat pub get
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\app_theme_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\style_options_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
```

Expected: PASS and no missing-asset warnings.

- [ ] **Step 6: Commit font/style foundation**

```powershell
git add apps/mobile/assets/fonts apps/mobile/pubspec.yaml apps/mobile/lib/features/ai_editing/style_options.dart apps/mobile/test/app_theme_test.dart apps/mobile/test/style_options_test.dart apps/mobile/tool/build_postdee_subtitle_font.py
git commit -m "feat(mobile): bundle Thai-safe subtitle styles"
```

Stage the build script only when it is included and verified.

---

### Task 4: Complete live Subtitle Studio active-word editing

**Files:**

- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_preview_overlay.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_studio_screen.dart`
- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart`
- Modify: `apps/mobile/test/subtitle_preview_overlay_test.dart`
- Modify: `apps/mobile/test/subtitle_studio_screen_test.dart`
- Modify: `apps/mobile/test/subtitle_studio_controller_test.dart`

**Interfaces:**

- `SubtitlePreviewOverlay` consumes cue text, validated cue words, current
  playback position, selected style, and safe preview width.
- Produces immediate local preview with:
  - static fallback;
  - active-word color;
  - `none`, `pop`, and `fade` effects;
  - one-line shrink-to-fit without ellipsis.
- `SubtitleStudioScreen` exposes text/time and style sections while preserving
  existing edit/add/delete/split/merge/undo/redo commands.

- [ ] **Step 1: Add failing overlay behavior tests**

Add literal widget cases proving:

```dart
testWidgets('falls back to the original sentence when word timing is unsafe',
    (tester) async {
  const text = 'one two';
  const words = [
    SubtitleWord(
      wordId: 'word-1',
      text: 'one',
      sourceStartMs: 100,
      sourceEndMs: 500,
      separatorAfter: ' ',
    ),
    SubtitleWord(
      wordId: 'word-2',
      text: 'two',
      sourceStartMs: 400,
      sourceEndMs: 800,
    ),
  ];

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: SubtitlePreviewOverlay(
            text: text,
            style: SubtitleStyle.defaults,
            currentPlaybackTimeMs: 450,
            words: words,
          ),
        ),
      ),
    ),
  );

  expect(
    find.byKey(const ValueKey('subtitle-preview-active-words')),
    findsNothing,
  );
  expect(find.text(text), findsNWidgets(2));
});

testWidgets('keeps a highlighted Thai word intact for mark-safe fonts',
    (tester) async {
  const markedWord = 'ที่';
  const words = [
    SubtitleWord(
      wordId: 'word-1',
      text: 'ไป',
      sourceStartMs: 0,
      sourceEndMs: 300,
      separatorAfter: ' ',
    ),
    SubtitleWord(
      wordId: 'word-2',
      text: markedWord,
      sourceStartMs: 300,
      sourceEndMs: 600,
      separatorAfter: ' ',
    ),
    SubtitleWord(
      wordId: 'word-3',
      text: 'บ้าน',
      sourceStartMs: 600,
      sourceEndMs: 900,
    ),
  ];

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: SubtitlePreviewOverlay(
            text: 'ไป ที่ บ้าน',
            style: SubtitleStyle.defaults,
            currentPlaybackTimeMs: 450,
            words: words,
          ),
        ),
      ),
    ),
  );

  final richText = tester.widget<RichText>(
    find.byKey(const ValueKey('subtitle-preview-active-words')),
  );
  final rootSpan = richText.text as TextSpan;
  final activeSpan = rootSpan.children!
      .whereType<TextSpan>()
      .singleWhere((span) => span.text == markedWord);

  expect(activeSpan.text, markedWord);
  expect(
    activeSpan.style?.color,
    subtitleColor(SubtitleStyle.defaults.activeWordColor),
  );
});
```

Also cover:

- 78% → 103% → 100% pop keyframes within 220 ms;
- fade at cue edges;
- unknown effect safely normalized to `none`;
- long Thai cue shrinks to the six-pixel floor without ellipsis.

- [ ] **Step 2: Run overlay/studio tests and verify RED**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_preview_overlay_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_studio_screen_test.dart
```

Expected: FAIL on missing active-word/effect and safe-fit behavior.

- [ ] **Step 3: Implement the minimal overlay and UI behavior**

Port only the dependency-complete active-word workflow from commit `44f9112`.
Keep the existing explicit result-review entry point. Do not add automatic
navigation to Subtitle Studio.

Use these public helpers so preview behavior remains directly testable:

```dart
bool subtitleTextFitsSingleLine({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
});

double fitSubtitleFontSizeForSingleLine({
  required String text,
  required TextStyle style,
  required double preferredFontSize,
  required double maxWidth,
  required TextDirection textDirection,
});
```

Keep animation state derived from playback time; do not add timers that can
outlive the video/controller.

- [ ] **Step 4: Verify the complete local editor**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_preview_overlay_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_studio_screen_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_studio_controller_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 5: Commit Subtitle Studio interaction**

```powershell
git add apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_preview_overlay.dart apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_studio_screen.dart apps/mobile/lib/features/ai_editing/subtitle_studio/subtitle_studio_controller.dart apps/mobile/test/subtitle_preview_overlay_test.dart apps/mobile/test/subtitle_studio_screen_test.dart apps/mobile/test/subtitle_studio_controller_test.dart
git commit -m "feat(mobile): complete active-word subtitle studio"
```

---

### Task 5: Match final subtitle rendering to the live preview

**Files:**

- Modify:
  `apps/mobile/lib/features/ai_editing/subtitle_burn_video_processor.dart`
- Modify: `apps/mobile/test/subtitle_burn_test.dart`

**Interfaces:**

- Produces `SubtitleFileContent` with ASS for validated active-word/effect cues
  and SRT/static fallback otherwise.
- Uses the bundled subtitle font directory/family from Task 3.
- Preserves current FFmpeg cancellation, output verification, temp cleanup, and
  audio/video mapping.

- [ ] **Step 1: Add failing renderer parity tests**

Add literal tests for:

- SRT flattens explicit newlines;
- Thai upper/lower marks stay attached;
- stacked tone marks are adjusted only for the reviewed mark-safe font;
- active-word ASS keeps the complete sentence visible;
- malformed/incomplete timing falls back for the whole cue;
- pop runs once per cue, not once per word;
- fade applies only at cue edges;
- selected font, text color, active color, outline, shadow, and position appear
  in generated ASS/FFmpeg arguments;
- a requested ASS render retries as static SRT only for an explicit subtitle
  render failure.

Example literal assertion:

```dart
test('falls back the whole cue when word timing is incomplete or unsafe', () {
  const unsafeCue = SubtitleSegment(
      text: 'ขายดีมาก',
      start: 0,
      end: 1,
      words: [
        SubtitleWordTiming(text: 'ขาย', start: 0, end: 0.5),
      ],
    );
  final file = buildSubtitleFileContent(
    const [unsafeCue],
    activeWordColor: '#FF0000',
  );

  expect(file.fileName, 'captions.srt');
  expect(file.usesActiveWordTiming, isFalse);
  expect(file.content, contains('ขายดีมาก'));
});
```

- [ ] **Step 2: Run renderer tests and verify RED**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_burn_test.dart
```

Expected: FAIL on active-word/effect parity and Thai mark safety.

- [ ] **Step 3: Port the minimum ASS/static fallback implementation**

Port the reviewed renderer behavior from the staging branch without replacing
unrelated FFmpeg encoder, sticker, color, audio, cancellation, or cleanup code.
Keep these testable interfaces:

```dart
bool shouldProtectStackedThaiMarksForRender({
  required String fontFamily,
  required String fontAssetPath,
});

SubtitleFileContent buildSubtitleFileContent(
  List<SubtitleSegment> segments, {
  String? activeWordColor,
  String textColor = '#FFFFFF',
  String subtitleAnimation = 'none',
  bool protectStackedThaiMarks = false,
});
```

Keep font family, outline, shadow, and position in the existing render-request
and FFmpeg-argument path. Do not add those fields to
`buildSubtitleFileContent`; its responsibility is choosing ASS versus static
SRT and generating cue content.

- [ ] **Step 4: Run renderer and analyzer checks**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_burn_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 5: Commit renderer parity**

```powershell
git add apps/mobile/lib/features/ai_editing/subtitle_burn_video_processor.dart apps/mobile/test/subtitle_burn_test.dart
git commit -m "feat(mobile): match subtitle preview and export"
```

---

### Task 6: Integrate duration boundaries, media retries, and result-review flow

**Files:**

- Create:
  `apps/mobile/lib/features/ai_editing/subtitle_timeline_alignment.dart`
- Create: `apps/mobile/test/subtitle_timeline_alignment_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_edit_audio_extractor.dart`
- Modify: `apps/mobile/test/ai_edit_audio_extractor_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/video_duration_probe.dart`
- Modify: `apps/mobile/lib/features/uploader/video_picker_service.dart`
- Modify: `apps/mobile/test/video_picker_service_test.dart`

**Interfaces:**

- Produces:

```dart
List<SilenceCutRange> alignTargetTailToSubtitleBoundary({
  required List<SilenceCutRange> cuts,
  required List<SubtitleSegment> subtitles,
  required double sourceDurationSeconds,
  required double targetDurationSeconds,
  double toleranceSeconds = 1,
});
```

- Media metadata/audio inspection retries once only for transient or invalid
  probe output.
- The requested render duration never exceeds source duration.
- A crossing final subtitle cue is kept whole within the one-second tolerance.
- Successful preparation renders first and opens result review; Subtitle Studio
  opens only from the review action.

- [ ] **Step 1: Add failing timeline, retry, and flow tests**

Add literal timeline tests:

```dart
test('moves a target tail cut to the end of a crossing subtitle cue', () {
  final cuts = alignTargetTailToSubtitleBoundary(
    cuts: const [SilenceCutRange(start: 30, end: 60)],
    subtitles: const [
      SubtitleSegment(text: 'ประโยคสุดท้าย', start: 29.6, end: 30.7),
    ],
    sourceDurationSeconds: 60,
    targetDurationSeconds: 30,
  );

  expect(cuts.single.start, 30.7);
});
```

Add tests proving:

- the real 30-second replay tail cue remains complete;
- a cue exceeding tolerance moves the boundary before the cue;
- metadata/audio probe exception or unavailable native result is retried
  exactly once;
- rotated stream metadata produces display-oriented width and height;
- missing/invalid duration is retried once;
- final rendered duration is capped at selected/source duration;
- render progress remains visible when native progress polling is unavailable;
- AI processing reaches result review without launching Subtitle Studio;
- the explicit review action opens Subtitle Studio and applies edited output on
  the second render.

- [ ] **Step 2: Run focused tests and verify RED**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_timeline_alignment_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\video_picker_service_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\ai_edit_audio_extractor_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\ai_editing_screen_test.dart
```

Expected: FAIL only for the missing boundary/retry/progress behavior.

- [ ] **Step 3: Implement one behavior at a time**

Implement in this order, re-running the matching test after each change:

1. `alignTargetTailToSubtitleBoundary`;
2. one-retry media metadata probe;
3. one-retry audio/duration probe;
4. selected/source duration cap;
5. fallback render progress;
6. result-review-before-Subtitle-Studio navigation.

Do not port branch code that changes uploader tools, package rules, provider
selection, or quota limits.

- [ ] **Step 4: Run the focused integration set**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\subtitle_timeline_alignment_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\video_picker_service_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\ai_edit_audio_extractor_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\ai_editing_screen_test.dart
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 5: Commit AI flow robustness**

```powershell
git add apps/mobile/lib/features/ai_editing/subtitle_timeline_alignment.dart apps/mobile/test/subtitle_timeline_alignment_test.dart apps/mobile/lib/features/ai_editing/ai_editing_screen.dart apps/mobile/test/ai_editing_screen_test.dart apps/mobile/lib/features/ai_editing/ai_edit_audio_extractor.dart apps/mobile/test/ai_edit_audio_extractor_test.dart apps/mobile/lib/features/ai_editing/video_duration_probe.dart apps/mobile/lib/features/uploader/video_picker_service.dart apps/mobile/test/video_picker_service_test.dart
git commit -m "fix(ai-edit): preserve subtitle and media boundaries"
```

---

### Task 7: Lock uploader scope and synchronize documentation

**Files:**

- Modify tests only if a missing regression must be added:
  `apps/mobile/test/uploader_screen_test.dart`
- Modify: `README.md`
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `ROADMAP.md`
- Modify: `apps/mobile/README.md`
- Modify relevant status/checklist sections only:
  `docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md`

**Interfaces:**

- Uploader contract:
  - `ตัดคลิปเป็น EP` is present;
  - `ตัดต่อเอง`, cover editor, automatic watermark, and advanced upload mode
    are absent.
- Documentation records the validated cue-word API field, explicit review
  flow, one-line Thai subtitle behavior, and actual verification status.

- [ ] **Step 1: Add or confirm uploader regression behavior**

Use the existing widget test style. Add only missing observable assertions:

```dart
expect(find.text('ตัดคลิปเป็น EP'), findsOneWidget);
expect(find.text('ตัดต่อเอง'), findsNothing);
expect(find.text('แต่งหน้าปก'), findsNothing);
expect(find.text('ใส่ลายน้ำอัตโนมัติ'), findsNothing);
expect(find.text('โหมดตั้งค่าขั้นสูง'), findsNothing);
```

- [ ] **Step 2: Run uploader regression before documentation**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test test\uploader_screen_test.dart
```

Expected: PASS. If it fails, fix only the accidental integration change; do not
restore excluded tools.

- [ ] **Step 3: Update docs to match implemented behavior**

Use `apply_patch`. Record:

- optional/authoritative `subtitles.segments[].words`;
- result review before explicit Subtitle Studio;
- active-word static fallback;
- one-line Thai safe-area behavior;
- no extra AI charge for local editing/re-render;
- uploader remains EP-only;
- commands actually run and their results.

Do not claim ElevenLabs is the `main` default unless provider configuration is
separately changed and verified.

- [ ] **Step 4: Verify docs and diff scope**

```powershell
git diff --check
git diff --name-status main...
git diff -- apps/mobile/lib/features/uploader/uploader_screen.dart
git diff -- apps/mobile/lib/features/home
git diff -- apps/mobile/lib/features/calendar
git diff -- apps/mobile/lib/features/billing
git diff -- apps/mobile/lib/features/auth
```

Expected:

- no whitespace errors;
- uploader production code unchanged unless a direct AI result handoff required
  a narrow reviewed change;
- no home, calendar, billing, auth, PostPeer, deployment, or package-limit
  changes.

- [ ] **Step 5: Commit regression/docs**

```powershell
git add apps/mobile/test/uploader_screen_test.dart README.md API.md ARCHITECTURE.md ROADMAP.md apps/mobile/README.md docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md
git commit -m "docs: align latest AI subtitle workflow"
```

Stage only files actually modified.

---

### Task 8: Full verification, Pixel 8 acceptance, and integration handoff

**Files:**

- No production files expected.
- Store temporary verification output only under ignored `.tmp`/`artifacts`
  paths and remove assistant-created temporary files after use.

**Interfaces:**

- Produces a verified branch suitable for review and merge into `main`.
- Does not push, merge, or deploy until the user authorizes that external
  action.

- [ ] **Step 1: Run complete backend verification**

```powershell
cd D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'
npm.cmd run prisma:validate
```

Expected: all tests pass, TypeScript build succeeds, Prisma schema validates.

- [ ] **Step 2: Run complete mobile verification**

```powershell
cd D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\mobile
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat pub get
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=D:\PostDeeMobile\apps\mobile\staging.local.json
```

Expected: analyze clean, all tests pass, APK build succeeds.

- [ ] **Step 3: Install only the verified APK on Pixel 8**

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = 'D:\PostDeeMobile\.worktrees\latest-ai-subtitle-main\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk'
& $adb devices
& $adb -s emulator-5554 install -r $apk
& $adb -s emulator-5554 shell am force-stop com.postdee.postdee_mobile.staging
& $adb -s emulator-5554 shell am start -n com.postdee.postdee_mobile.staging/com.postdee.postdee_mobile.MainActivity
```

Expected: install succeeds and the staging package opens.

- [ ] **Step 4: Run real-device acceptance**

Use the existing Thai test video plus at least one mixed Thai/English clip.
Verify:

1. 30-second target;
2. 60-second target;
3. custom target;
4. result review appears before Subtitle Studio;
5. explicit subtitle edit opens Studio;
6. text/time, font, colors, outline, shadow, placement, and effect update;
7. active word is correct when timing is safe;
8. static fallback is readable when timing is unsafe;
9. Thai marks do not overlap;
10. cue remains one line and inside the frame;
11. save re-renders and returns to review;
12. upload handoff shows only EP uploader tool UI;
13. local subtitle edit/re-render does not reduce AI minutes again.

- [ ] **Step 5: Review final Git evidence**

```powershell
git status --short --branch
git log --oneline --decorate main..HEAD
git diff --stat main...HEAD
git diff --name-status main...HEAD
git diff --check main...HEAD
```

Expected: only the planned API/mobile subtitle files, tests, font assets, and
docs are present.

- [ ] **Step 6: Request code review before integration**

Use `superpowers:requesting-code-review`. Address only validated findings, then
rerun the affected tests and final verification.

- [ ] **Step 7: Finish the branch**

Use `superpowers:finishing-a-development-branch`. Present the verified choices:

- merge locally into `main`;
- push and open a pull request;
- keep the branch for more manual testing.

Do not merge or push until the user chooses.
