# AI Edit Subtitle Review Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one-tap AI editing render a captioned preview and reach result review without opening Subtitle Studio automatically.

**Architecture:** Keep mapping the AI recipe into a `SubtitleProject`, but store that project directly in `AiEditingScreen` state before rendering. Reuse the existing review action to open Subtitle Studio explicitly and re-render after a saved edit.

**Tech Stack:** Flutter, Dart widget tests, existing subtitle mapper and FFmpeg renderer abstractions.

## Global Constraints

- Do not change AI quota or subscription behavior.
- Do not change backend API contracts.
- Keep Subtitle Studio available from the result review screen.
- Preserve AI-generated caption text and default style in the first preview.
- Preserve the subtitle size and position selected on the AI setup screen.

---

### Task 1: Prevent automatic Subtitle Studio navigation

**Files:**
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`

**Interfaces:**
- Consumes: `mapAiEditRecipeToSubtitleProject`, `_renderPreparedRecipe`, `_openSubtitleStudio`
- Produces: `_subtitleProject` initialized before the first render and edited only through the review action

- [ ] **Step 1: Change the existing widget test to express the desired flow**

Track Subtitle Studio launch count and all `BurnSubtitleRequest` values. After
the process action, assert zero studio launches, one captioned render, and the
result review. Then tap `ai-review-edit-subtitles` and assert one studio launch
and a second render containing the edited text and style.

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test --no-pub test\ai_editing_screen_test.dart --plain-name "renders AI subtitles first and opens Subtitle Studio only on request"
```

Expected: FAIL because the existing flow launches Subtitle Studio once during
initial processing.

- [ ] **Step 3: Implement the minimum flow change**

Replace the automatic `_openSubtitleStudio` call after preparation with:

```dart
if (reviewCapabilities['subtitle'] == true) {
  final identity = buildSubtitleProjectIdentity(
    sourceFile: file,
    setupSignature: prepareSignature,
  );
  final mappedProject = mapAiEditRecipeToSubtitleProject(
    recipe: preparedResult.recipe,
    projectId: identity.projectId,
    sourceFingerprint: identity.sourceFingerprint,
    now: DateTime.now().toUtc(),
    maxCharsPerCue:
        _buildEditOptions(reviewCapabilities).subtitleMaxChars ?? 18,
  );
  final initialProject = mappedProject.copyWith(
    defaultStyle: _subtitleStyleForSetup(
      mappedProject.defaultStyle,
      reviewCapabilities,
    ),
  );
  setState(() {
    _subtitleProject = initialProject;
  });
}
```

The existing `_renderPreparedRecipe` call then creates the preview, and the
existing `_editReviewSubtitles` method remains the only Studio launcher.
`_subtitleStyleForSetup` preserves the mapped font family and colors while
applying the selected setup font size and top/bottom position.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: PASS.

### Task 2: Verify and publish

**Files:**
- Verify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Verify: `apps/mobile/test/ai_editing_screen_test.dart`

**Interfaces:**
- Consumes: completed Task 1 behavior
- Produces: verified Android debug APK and synchronized `main`

- [ ] **Step 1: Run full mobile checks**

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze --no-pub
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test --no-pub
```

Expected: no analyzer issues and all tests pass.

- [ ] **Step 2: Build and install the staging APK**

Build from the `main` worktree with the existing root staging and RevenueCat
local define files, install with `adb install -r`, and launch the staging
package on `emulator-5554`.

- [ ] **Step 3: Commit and push**

Stage only the design, plan, implementation, and regression test. Commit with:

```text
fix(ai-edit): show review before subtitle studio
```

Push `main` and verify the local and remote commit SHAs match.
