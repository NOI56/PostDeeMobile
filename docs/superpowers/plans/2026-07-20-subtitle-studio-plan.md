# PostDee Subtitle Studio — Research and Implementation Plan

> Status: Approved for phased implementation on 20 July 2026. This document does
> not by itself change the current package, quota, API contract, or production
> architecture; each phase still requires its verification gate.

**Goal:** Extend the existing PostDee AI Editing flow with a mobile subtitle
editor that lets a seller correct Thai captions, adjust timing and styling,
preview changes immediately, burn the accepted result into the video on the
phone, and continue directly to Upload/Post.

**Recommended product position:** Do not clone SaduakSub. Reuse the useful
interaction principles and make PostDee's advantage the complete flow:
`AI selects the best moments -> seller corrects/styles subtitles -> PostDee
renders -> seller posts to multiple platforms`.

## 1. What was inspected

Research date: 20 July 2026.

The review used the signed-in SaduakSub editor, pricing page, and privacy page
that were already available in the user's Chrome session. No subtitle text,
style, project, payment, render action, or transcription credit was changed or
consumed.

### Observed SaduakSub workflow

1. Upload or open a video project.
2. Receive automatically timed transcript lines.
3. Edit text in a list, seek/listen per line, add a line, and use undo/redo.
4. Choose whether a change affects the whole clip or only the current line.
5. Preview subtitles over the vertical video and move/resize the subtitle block.
6. Adjust font, size, number of rows, text colour, current-word colour, outline,
   shadow, and text animation.
7. Optionally add a sound effect to an individual subtitle line.
8. Save the current visual style as a reusable brand style.
9. Render 720p or plan-gated 1080p output and keep recent jobs in a project list.

Observed text effects included pop, fade, directional slide, word-by-word pop,
word-by-word typing, and character-by-character typing. Observed sound options
included pop, click, whoosh, shutter, capture, ding, and typing.

### Observed service constraints

- The free plan shows a 3-minute maximum source clip, 720p output, watermark,
  limited stored projects, and a monthly transcription-minute quota.
- Paid plans increase transcription minutes, project count, clip length, and
  output resolution. The highest plan advertises a priority render queue.
- The privacy page states that uploaded video/audio and generated output are
  processed for the service, that ElevenLabs/Groq may receive media for speech
  transcription, and that Cloudflare is used for CDN and temporary file
  delivery/storage.
- The privacy page states that uploaded clips and generated files are normally
  deleted automatically in about seven days.

### What is inferred, not directly verified

The advertised render queue, temporary Cloudflare results, and stored-job list
strongly suggest an asynchronous server render pipeline. The exact renderer,
model routing between providers, database design, queue technology, and internal
APIs were not visible and should not be assumed or copied.

## 2. PostDee's current baseline

PostDee already has the expensive and technically risky foundations:

- `/ai-edits/prepare` checks the Pro plan, ownership, AI-editing quota, obtains a
  transcript, builds the cut plan, and returns a mobile render recipe.
- The transcription provider returns overall text, segment timestamps, and word
  timestamps. Groq/OpenAI requests ask for both word and segment timing.
- The backend validates timing coverage and falls back to readable segments when
  Thai word timing is fragmented or incomplete.
- Mobile extracts and uploads a small temporary M4A for the current production
  AI capabilities while the original source video remains on the phone.
- Mobile builds SRT, bundles Prompt Bold, uses FFmpeg/libass to burn subtitles,
  tries hardware H.264 first, falls back safely, and verifies that the output
  still contains a video stream.
- The current screen already offers three subtitle sizes, three text-density
  choices, top/bottom position, and final review before Upload/Post.

The main missing part is not transcription. It is a persistent, editable
subtitle project and a live editor between `prepare` and the final FFmpeg render.

## 3. Feature decision matrix

| Capability | SaduakSub observed | PostDee now | Decision |
| --- | --- | --- | --- |
| Timed Thai transcription | Yes | Yes | Reuse current provider and validation |
| Edit text per cue | Yes | No | MVP |
| Add/delete/split/merge cue | Add line observed | No | MVP |
| Seek and replay one cue | Yes | No | MVP |
| Adjust cue start/end | Timed lines observed | No | MVP with safe nudge controls; waveform later |
| Undo/redo and autosave | Yes | No | MVP |
| Live subtitle preview | Yes | Static setup preview + rendered review | MVP with Flutter overlay |
| Font, size, colours, outline, shadow | Yes | Prompt, size, white/black fixed | MVP, whole-clip style first |
| Current-word highlight | Yes | No | MVP after timing-quality fallback is implemented |
| Per-line style/position | Yes | No | Data model supports it; UI after MVP |
| Text animations | Yes | No | Phase 2, start with a small verified set |
| Sound effect per cue | Yes | Capability key only, no renderer | Phase 2 after licensing/audio tests |
| Reusable brand style | Yes | Presets exist only in page memory | MVP as local persistent style |
| Cloud project library | Yes | No | Phase 3; local recovery draft first |
| 720p/1080p switch | Yes | Preserves source dimensions | Separate package/product decision |

## 4. Target user flow

```text
Select video
  -> choose AI target length and options
  -> upload temporary audio and prepare one transcript/cut recipe
  -> open Subtitle Studio
  -> correct words and timing
  -> choose whole-clip style and preview instantly
  -> confirm once
  -> render the final video on the phone
  -> compare original/result
  -> Upload/Post/Schedule
```

Mobile layout should be designed for a phone, not shrink a desktop three-column
editor. Recommended layout:

- video preview at the top;
- current cue and playback controls below it;
- bottom tabs for `ข้อความ`, `สไตล์`, and later `เอฟเฟกต์`;
- scrollable cue list in the text tab;
- a clear `ทั้งคลิป` / `บรรทัดนี้` scope selector when per-cue styling ships;
- one final `สร้างวิดีโอ` action instead of running FFmpeg after every edit.

## 5. Architecture decision

### 5.1 Keep the current privacy and cost advantage

- Keep the original video on the device.
- Continue uploading only the temporary audio required for transcription.
- Reuse one successful transcript for AI cutting and subtitle editing.
- Do not charge or reserve another AI minute when the user edits text, changes a
  colour, previews, retries a local render, or returns to the same cached recipe.
- Keep edited draft data local in the first release. Cloud sync is opt-in later.

### 5.2 Add an explicit subtitle project model

Recommended domain model (names are illustrative):

```text
SubtitleProject
  schemaVersion
  projectId
  sourceFingerprint
  sourceDurationMs
  cues[]
  defaultStyle
  brandStyleId?
  cutRanges[]
  createdAt / updatedAt

SubtitleCue
  cueId
  sourceStartMs / sourceEndMs
  text
  words[]
  timingMode: word | segment | estimated
  styleOverride?
  positionOverride?
  soundEffect?

SubtitleWord
  wordId
  text
  sourceStartMs / sourceEndMs
  separatorAfter

SubtitleStyle
  fontId
  fontSize
  textColor
  activeWordColor
  outlineColor / outlineWidth
  shadowColor / shadowDepth
  backgroundColor?
  alignment
  normalizedX / normalizedY
  maxLines
  animation
```

Use stable IDs so undo/redo, autosave, selection, and later cloud conflict
handling do not depend on a cue's array index.

All cue timestamps should remain on the original source timeline. The current
renderer burns subtitle pixels before applying cut ranges, so this avoids
recalculating every cue after silence/best-moment cuts. In the editor, cues fully
inside removed ranges should be marked `ไม่อยู่ในผลลัพธ์` and hidden by default.

### 5.3 Live preview without repeated FFmpeg renders

Use the existing video player with a Flutter `Stack` overlay:

- resolve the active cue/word from the current playback position with an indexed
  or binary search instead of rebuilding the full cue list on every tick;
- resolve the active word only when timing quality is safe;
- render the chosen font/style within platform safe areas;
- tap a cue to seek to its start;
- replay the cue range without changing the source file;
- drag only within a bounded safe region;
- debounce autosave, but commit text immediately to the in-memory project.

The Flutter preview and libass export will not be pixel-identical by default.
Only expose style controls that have a verified equivalent in both paths.

### 5.4 Replace static SRT-only styling with generated ASS

Keep FFmpeg/libass and the current encoder fallback. Add an ASS builder because
ASS supports named styles, per-event overrides, positioning, outline, shadow,
and timed word states that SRT cannot represent. Keep the existing SRT path as a
feature-flagged fallback during rollout.

Recommended fallback hierarchy:

1. Reliable word timing: generate time-sliced ASS events that show the full cue
   and colour only the currently spoken word.
2. Reliable cue timing but unsafe word timing: show the whole cue without a
   moving word highlight.
3. Invalid cue timing: block final render and show the exact cue to repair.

Do not assume standard ASS `\\k` behavior exactly matches the target design:
depending on the style, it can leave prior/future words in primary/secondary
colours instead of highlighting only the current word. Prototype and benchmark
both karaoke tags and per-word full-cue events, then ship only the version whose
preview/export behavior matches on supported devices.

If the user changes text while the original word count still maps safely, keep
the existing word durations. If the structure changes, mark that cue as
`estimated`, distribute timing conservatively inside the cue, and allow the user
to adjust the cue. Do not show a confidently wrong word-by-word animation.

Start with the already bundled Prompt and Anuphan families. Add fonts or sound
assets only after commercial redistribution rights are recorded.

### 5.5 Persistence

MVP persistence:

- autosave the active project's JSON locally with schema versioning;
- save small reusable brand styles in the existing local preferences mechanism;
- keep an undo and redo command stack in memory;
- copy or retain the source through a managed local project path if recovery
  after an app restart is promised;
- add explicit cleanup for abandoned drafts and generated previews.

Do not store a large project JSON indefinitely in SharedPreferences. Use a
small index in preferences and a versioned file in app-owned storage.

Cloud project sync is Phase 3 and needs authenticated user scope, retention,
delete/export rights, storage quotas, and a PDPA review before implementation.

## 6. Implementation phases

### Phase 0 — Lock behavior with tests

- [ ] Document subtitle editing invariants: non-empty ID, finite timestamps,
      `0 <= start < end <= sourceDuration`, stable ordering, and overlap rules.
- [ ] Add failing tests for Thai grapheme handling, cue edits, timing validation,
      undo/redo, autosave schema migration, and ASS escaping.
- [ ] Add compatibility fixtures for the current recipe response.
- [ ] Decide whether exact cue overlaps are disallowed or rendered as layered
      captions. Recommended MVP: disallow overlaps and offer an automatic fix.

### Phase 1 — Domain model and project adapter

Suggested new files:

- `apps/mobile/lib/features/ai_editing/subtitle_project.dart`
- `apps/mobile/lib/features/ai_editing/subtitle_edit_command.dart`
- `apps/mobile/lib/features/ai_editing/subtitle_project_store.dart`

Work:

- [ ] Convert `AiEditRecipeResult.subtitles`, transcript words, and cut ranges
      into `SubtitleProject` without another API request.
- [ ] Implement edit, add, delete, split, merge, and time-nudge commands.
- [ ] Bound undo/redo history (recommended first limit: 50 commands).
- [ ] Preserve Thai combining marks and emoji grapheme clusters.
- [ ] Add local JSON autosave and safe schema-version fallback.
- [ ] Persist whole-clip brand styles locally.

### Phase 2 — Mobile editor and live preview

Suggested new files:

- `apps/mobile/lib/features/ai_editing/subtitle_editor_screen.dart`
- `apps/mobile/lib/features/ai_editing/subtitle_editor_controller.dart`
- `apps/mobile/lib/features/ai_editing/subtitle_preview_overlay.dart`

Work:

- [ ] Insert Subtitle Studio after `/ai-edits/prepare` and before final render.
- [ ] Build the cue list, active-cue tracking, tap-to-seek, replay-cue, text edit,
      add/delete/split/merge, and undo/redo interactions.
- [ ] Add whole-clip font, size, text colour, highlight colour, outline, shadow,
      row count, and safe top/middle/bottom position controls.
- [ ] Do not rerender MP4 when a style or word changes.
- [ ] Warn when a cue is outside the AI-selected result.
- [ ] Preserve the last successful rendered result if a new render fails.

### Phase 3 — ASS renderer and active-word highlight

Suggested new file:

- `apps/mobile/lib/features/ai_editing/ass_subtitle_builder.dart`

Files to extend:

- `apps/mobile/lib/features/ai_editing/subtitle_burn_video_processor.dart`
- `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`

Work:

- [ ] Generate deterministic ASS headers, styles, events, and escaped text.
- [ ] Copy every selected bundled font into the render workspace.
- [ ] Map preview controls only to verified libass equivalents.
- [ ] Generate active-word events only for reliable word timing; do not rely on
      karaoke tags until their current-word-only behavior is visually verified.
- [ ] Keep segment-level fallback for fragmented Thai timing.
- [ ] Keep current hardware encoder, MPEG-4 fallback, stream verification,
      cancellation, temp cleanup, audio/video cut synchronization, and progress.
- [ ] Run one final render after confirmation, then reuse current result review
      and Upload/Post handoff.
- [ ] Put Subtitle Studio/ASS export behind a feature flag until real-device
      acceptance passes; preserve the current SRT route as rollback.

### Phase 4 — Production hardening and MVP release gate

- [ ] Unit-test ASS output, colour conversion, outline/shadow, alignment,
      karaoke durations, source-timeline cuts, and malformed values.
- [ ] Widget-test editing, focus/keyboard, cue selection, undo/redo, autosave,
      screen rotation, and accessibility labels/touch targets.
- [ ] Render short golden fixtures and compare sampled frames with preview.
- [ ] Test clean Thai speech, background music, multiple Thai accents, English
      product names, numbers/prices, emoji, long words, and silence.
- [ ] Test physical low/mid/high Android devices and at least one supported
      iPhone at the source resolutions PostDee promises.
- [ ] Test long clips for heat, battery, free-space failure, cancellation, and
      cleanup. Never delete the source or last accepted output on failure.
- [ ] Verify that one transcription is charged once and all local edit/render
      retries consume zero additional AI minutes.

MVP is ready only when the exported MP4 contains the corrected text and selected
style, word highlight falls back safely, preview/export parity is acceptable on
real devices, and render failure is recoverable.

### Phase 5 — Post-MVP effects and per-line controls

- [ ] Per-cue style and position override.
- [ ] A small verified animation set: fade, pop, and word-by-word reveal first.
- [ ] Waveform and drag handles for precise start/end timing.
- [ ] Licensed sound-effect library, per-cue volume, preview, and FFmpeg
      `adelay`/`amix` integration.
- [ ] Export/import SRT and VTT.
- [ ] More licensed Thai fonts.

### Phase 6 — Optional cloud project library

- [ ] Add user-scoped subtitle project endpoints and persistence only after a
      separate API/data-retention design is approved.
- [ ] Add optimistic concurrency/version checks for cross-device editing.
- [ ] Add explicit project/media retention and delete-account cleanup.
- [ ] Keep cloud sync opt-in; do not silently upload source video.

## 7. API direction

No new endpoint is required for the first editor because the current prepare
recipe already contains transcript segments and words.

For reliable active-word UX, add backward-compatible cue metadata later rather
than make mobile duplicate backend timing validation:

```json
{
  "subtitles": {
    "cues": [
      {
        "id": "cue-1",
        "text": "...",
        "start": 0.2,
        "end": 1.7,
        "timingMode": "word",
        "words": [
          { "text": "...", "start": 0.2, "end": 0.8 }
        ]
      }
    ]
  }
}
```

The current `segments` field must remain during migration so older mobile builds
continue to work. A future cloud library should use separate user-scoped CRUD
endpoints and must not be smuggled into `/ai-edits/prepare`.

## 8. Quota and package recommendation

Do not change Basic/Starter/Pro in this implementation plan. Use the current Pro
AI Editing entitlement and existing minute ledger for the first release.

Rules that must remain true:

- charge only after a successful transcription/recipe response according to the
  existing reservation behavior;
- do not charge for editing, previewing, local rendering, or local retries;
- do not transcribe the same cached AI-edit job again merely to reopen the
  subtitle editor;
- a failed provider or render must not silently consume a second quota unit.

After real usage and provider cost are measured, product can separately decide
whether a subtitle-only allowance belongs in Starter. Resolution, watermark,
brand-style limits, and cloud storage counts are commercial decisions and should
not be copied from SaduakSub automatically.

## 9. Privacy and safety requirements

- Keep source video local for current capabilities.
- Explain that temporary audio is sent to the configured transcription provider.
- Delete owned temporary audio immediately on success/failure where possible and
  keep a short server-side TTL as defense in depth.
- Never log raw media, signed URLs, storage keys, transcripts, or provider keys.
- Keep signed storage access user-scoped.
- Store local drafts without sensitive transcript analytics by default.
- If cloud sync is added, document retention, deletion, download/export, and
  cross-border processing before release.
- Record commercial licences for every redistributed font and sound effect.

## 10. Primary risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Flutter preview differs from libass export | User sees a different final result | Expose only parity-tested controls; golden frame checks |
| Thai word timing arrives as characters or incomplete words | Wrong flashing/highlight | Reuse backend validation; segment fallback; never force karaoke |
| Edited text no longer matches original word tokens | Highlight drifts | Mark cue `estimated`, remap conservatively, allow timing edit |
| AI cut ranges compact the output timeline | Cue appears in a removed section | Store source timing, burn before cuts, label removed cues |
| Per-word ASS events become large on long clips | Slow render on lower-end phones | Benchmark event count; use static-cue fallback |
| Repeated FFmpeg renders heat the device | Slow UX and failure | Flutter live preview; render only after confirmation |
| Long drafts/source copies fill storage | App/device storage pressure | Managed paths, size display, cleanup policy, free-space preflight |
| SFX or fonts lack redistribution rights | Legal/product risk | Ship only documented commercial-compatible assets |
| Cloud projects expose user media/transcripts | PDPA/security risk | Keep MVP local; later opt-in and user-scoped design review |

## 11. Definition of done

- A user can correct any transcript line before export.
- A user can add/delete/split/merge a cue and safely adjust its start/end.
- Cue edits support undo/redo and recover from a local autosave.
- The preview follows video playback and displays the selected whole-clip style.
- The final MP4 contains the same corrected text, font family, colours, outline,
  shadow, and safe position within an agreed visual tolerance.
- Reliable word timing produces active-word highlight; unsafe timing produces a
  readable non-karaoke fallback.
- The original source and last accepted render survive cancellation/failure.
- Editing and local rendering do not consume another AI quota minute.
- Focused mobile/backend tests pass, and real-device exports are recorded before
  the feature is marketed as production-ready.

## 12. Documentation to sync when implementation is approved

This proposal intentionally does not edit the already modified central docs.
When the scope is approved and implementation begins, update together:

- `ROADMAP.md`: change the statement that PostDee has no built-in manual editor
  to clarify that only subtitle-cue editing exists, not a full video timeline.
- `ARCHITECTURE.md`: add the Subtitle Studio step, local draft boundary, live
  preview, ASS export, and timing fallback.
- `API.md`: document any backward-compatible `subtitles.cues` addition and later
  project CRUD endpoints.
- `README.md`: document the customer flow and what is production-verified.
- `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md`: replace
  the old deferred subtitle controls only after their exported behavior passes.
