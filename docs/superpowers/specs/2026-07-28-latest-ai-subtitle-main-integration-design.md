# Latest AI Editing and Subtitle Studio Main Integration Design

> **Document status (implemented):** this design has been integrated into
> `main`. References to the former Staging branch describe the source used during
> integration, not a second current app or an active merge task.

## Goal

Make `main` the single authoritative mobile app again by selectively bringing
the latest proven AI editing and Subtitle Studio behavior from
`codex/elevenlabs-scribe-v2-staging` into `main`, without merging that staging
branch wholesale and without restoring uploader tools the user previously
removed.

## Confirmed Product Behavior

- The desktop launcher continues to build the worktree checked out on the exact
  `main` branch.
- AI editing keeps the current video-first setup and source-bounded duration
  selection.
- A successful AI preparation renders a result preview and opens result review.
- Subtitle Studio opens only after the user explicitly chooses to edit
  subtitles from result review.
- Subtitle Studio supports editing cue text and timing, add/delete,
  split/merge, undo/redo, local draft recovery, font, colours, outline, shadow,
  placement, and safe active-word highlighting.
- Automatic Thai subtitles remain one line, stay within the video safe area,
  and preserve Thai base characters, vowels, tone marks, and mixed-language
  words without visual overlap.
- Unsafe or incomplete word timing falls back to a static readable cue instead
  of highlighting the wrong word.
- The uploader retains only the approved `ตัดคลิปเป็น EP` growth-tool UI.
- Cover editing, automatic watermark controls, advanced upload mode, and other
  root-worktree-only uploader experiments remain excluded.

## Considered Integration Approaches

### Merge the complete staging branch

Rejected. The branch contains 45 commits not in `main`, spanning staging
provider configuration, API behavior, documentation, deployment fixes, and
mobile UI. A wholesale merge would couple the mobile restoration to unrelated
production decisions and increase regression risk.

### Install the staging branch as the app

Rejected. This recreates multiple competing app versions and bypasses the
existing launcher guarantee that the installed app comes from `main`.

### Selective behavior-based integration

Chosen. Start from `main`, identify the mobile behavior and tests that are
newer on the staging branch, port only the dependency-complete set, and resolve
each conflict in favor of the approved `main` product flow. Backend changes are
included only when a mobile contract test proves they are required for the
selected behavior.

## Source and Branch Safety

- `main` is the integration base and remains available in its existing linked
  worktree so the desktop launcher continues to resolve it.
- Implementation occurs on a new isolated `codex/` branch and worktree created
  from the current local `main`.
- The dirty root worktree and every existing feature/staging worktree are
  treated as read-only evidence.
- No branch is deleted, reset, rebased, or merged wholesale.
- Existing uncommitted root-worktree changes are never copied as a directory or
  used as the build source.

## Integration Units

### 1. Flow and duration safeguards

Preserve the approved setup-to-review flow, selected-duration cap, fallback
render progress, transient media-probe retry, and completion on subtitle
boundaries. These behaviors must compose with the current `main` quota and
entitlement checks without changing package limits.

### 2. Subtitle data and draft validity

Bring the latest project mapping, draft invalidation after regrouping, cue
limits, and mixed-language boundary handling into the existing
`subtitle_studio` domain. Existing project IDs and schema compatibility remain
stable so valid local drafts continue to load.

### 3. Subtitle Studio interaction

Bring the latest active-word workflow into the existing explicit-review entry
point. Text/timing editing, add/delete, split/merge, undo/redo, and style
controls remain local and do not consume additional AI quota.

### 4. Preview and final render parity

Use the same selected style and safe-area rules for Flutter preview and the
FFmpeg subtitle burn path. Active-word highlighting is enabled only for
validated word timing. Static cue fallback remains a successful output, not a
render failure.

### 5. Uploader isolation

Keep the current `main` uploader implementation that exposes only
`ตัดคลิปเป็น EP`. Integration conflicts in uploader, shell, home, calendar, or
publishing code are resolved by retaining `main` unless a direct AI
review-to-upload contract requires a narrowly scoped change.

## Data Flow

1. The seller selects a local vertical video and target result length.
2. Mobile performs the existing entitlement and quota preflight.
3. Mobile prepares one AI recipe through the existing authenticated API.
4. Mobile renders the prepared result and opens result review.
5. The seller may accept the result immediately or explicitly open Subtitle
   Studio.
6. Subtitle changes update a local project and preview without another AI call.
7. Saving subtitle changes re-renders the result and returns to review.
8. The accepted result continues through the existing upload/post flow.

## Error Handling

- Failed or incomplete provider output uses the existing readable fallback and
  must not open a stale draft automatically.
- Invalid word alignment renders a static cue.
- A failed re-render preserves the last accepted preview and editable project.
- Draft schema or source mismatch offers a fresh project without deleting the
  existing recovery file.
- Missing media, insufficient storage, cancellation, and transient probe
  failures keep their existing user-facing recovery paths.
- No retry may charge quota after a recipe has already succeeded.

## Test Strategy

All behavior changes follow red-green-refactor.

- Widget tests prove AI processing reaches result review before Subtitle Studio
  and that the explicit edit action applies text/style changes on re-render.
- Domain tests cover Thai graphemes, mixed-language boundaries, cue limits,
  split/merge, timing edits, undo/redo, draft invalidation, and active-word
  fallback.
- Renderer tests cover one-line safe bounds, selected-duration caps, stacked
  Thai marks, static fallback, output stream validation, progress, cancellation,
  and cleanup.
- Uploader regression tests prove `ตัดคลิปเป็น EP` remains and cover,
  watermark, and advanced-mode controls remain absent.
- Run focused Flutter tests after each integration unit, then full
  `flutter analyze`, `flutter test`, and an Android staging debug APK build.
- Install the verified APK on Pixel 8 and smoke-test 30-second, 60-second, and
  custom-duration Thai clips through setup, result review, Subtitle Studio,
  re-render, and upload handoff.

## Rollout

1. Create the isolated integration worktree from local `main`.
2. Establish a passing baseline before porting behavior.
3. Integrate one unit at a time with tests and a focused commit.
4. Run the complete mobile verification suite and build the staging APK.
5. Install and smoke-test on Pixel 8.
6. Review the branch diff for accidental uploader, billing, auth, API, or
   deployment changes.
7. Merge into `main` only after all checks pass.
8. Treat visible staging build identity and launcher update-wait behavior as a
   separate follow-up design after this integration is stable.

## Success Criteria

- The installed staging APK built from `main` contains the latest approved AI
  review and Subtitle Studio behavior.
- Subtitle Studio never opens automatically after AI preparation.
- Thai subtitles are readable, one-line, in bounds, and visually consistent
  between preview and export.
- Active-word highlighting never uses unsafe timing.
- Editing and re-rendering do not consume another AI minute.
- The uploader still exposes only `ตัดคลิปเป็น EP`.
- No unrelated root or staging branch work enters `main`.
- Flutter analysis, tests, Android build, and Pixel 8 smoke tests pass.
