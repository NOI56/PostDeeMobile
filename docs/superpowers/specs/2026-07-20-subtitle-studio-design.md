# PostDee Subtitle Studio Design

## Goal

Add a subtitle-only editor between the existing AI prepare step and final mobile
render so a seller can correct Thai transcript text and timing, preview a
verified style immediately, burn the accepted subtitles into the local video,
and continue to PostDee's existing Upload/Post flow.

This is not a general video timeline editor. AI best-moment selection, silence
cuts, transcription quota, result review, and multi-platform posting remain the
responsibility of the existing AI Editing flow.

## Approved Product Behavior

- The seller selects a video and target result length through the current AI
  Editing setup.
- PostDee extracts and uploads the existing temporary audio artifact, calls
  `/ai-edits/prepare` once, and reuses that successful recipe.
- Before final rendering, PostDee opens Subtitle Studio with the prepared cues.
- The seller can edit text, add/delete a cue, split/merge adjacent cues, nudge
  start/end timing, seek to a cue, and replay that cue.
- Edits have bounded undo/redo history and an autosaved local recovery draft.
- MVP whole-clip style controls are Prompt/Anuphan, font size, text colour,
  active-word colour, outline, shadow, one/two rows, and safe top/middle/bottom
  placement.
- Preview changes are drawn with Flutter over the local video. Changing text or
  style does not run FFmpeg and does not consume AI quota.
- Final export runs once after confirmation through the current on-device
  FFmpeg pipeline and then enters the current result-review and Upload/Post flow.
- Reliable validated word timing may produce active-word highlighting. Unsafe
  or edited-out-of-alignment timing falls back to a readable static cue.
- The source video remains local for current production capabilities. Only the
  temporary transcription audio follows the existing upload/cleanup path.
- SFX, animated per-line effects, custom font upload, a waveform editor,
  per-line free positioning, and cloud project sync are outside the first MVP.

## Considered Approaches

### 1. Copy the cloud editor/render model

Upload the source video, edit a server project, queue a server render, and keep
recent outputs in cloud storage.

Rejected for MVP because it duplicates the current mobile renderer, increases
media transfer/storage cost, expands the PDPA/security surface, and removes the
current advantage of keeping the source video on the phone.

### 2. Keep SRT and add only a text list

Allow text correction but keep the current fixed Prompt/white/black SRT export.

Rejected as the target design because it cannot support verified active-word
colour, multiple named styles, per-event overrides, outline/shadow controls, or
future subtitle effects. The old SRT route remains a rollback path.

### 3. Local live editor plus ASS export

Reuse the existing backend transcript/timing validation, create an editable
mobile subtitle project, preview with Flutter, and export ASS through the
existing libass/FFmpeg filter.

Chosen because it reuses the strongest existing components, avoids repeated AI
calls and repeated preview renders, keeps source media local, and supports a
safe staged rollout with the old SRT route available behind a feature flag.

## Architecture

The AI prepare response remains the authoritative source for transcript and cut
data. Mobile maps the response into a `SubtitleProject` with stable cue/word
identifiers and keeps timestamps on the original source timeline. This matches
the existing renderer, which burns subtitle pixels before compacting AI/silence
cut ranges.

Subtitle Studio owns only subtitle state and interactions. It does not modify
the AI cut plan. Cues fully removed by the cut plan are marked as not present in
the result and hidden by default, but their original timestamps are retained.

The live preview listens to the existing video player's playback position and
uses an indexed/binary lookup for the active cue and word. It updates only the
subtitle overlay, not the full cue list. Only style properties with tested
Flutter and libass equivalents are customer-visible.

The exporter creates an ASS document for advanced styles and active-word
events. If the feature flag is disabled, the project is unsupported, or ASS
render validation fails before output acceptance, PostDee can retain the
existing static SRT path without retranscribing the clip.

## Domain Model

```text
SubtitleProject
  schemaVersion
  projectId
  sourceFingerprint
  sourceDurationMs
  language
  cues[]
  defaultStyle
  cutRanges[]
  revision
  createdAt / updatedAt

SubtitleCue
  cueId
  sourceStartMs / sourceEndMs
  text
  words[]
  timingMode: word | segment | estimated
  styleOverride?       (schema only in MVP)
  positionOverride?    (schema only in MVP)
  soundEffect?         (schema only; not rendered in MVP)

SubtitleWord
  wordId
  text
  sourceStartMs / sourceEndMs
  separatorAfter

SubtitleStyle
  fontId / fontWeight
  fontSize
  textColor / activeWordColor
  outlineColor / outlineWidth
  shadowColor / shadowDepth
  alignment
  normalizedX / normalizedY
  maxLines
  animation            (none in MVP)
```

### Invariants

- Project/cue/word IDs are non-empty and stable across edits and autosave.
- All numeric timestamps are finite.
- `0 <= start < end <= sourceDuration`.
- MVP cues are sorted and do not overlap. Invalid imports are normalized only
  when the repair is deterministic; otherwise the editor identifies the cue and
  blocks final export.
- Split/merge operations preserve the source-time coverage of the affected cue
  range.
- Thai combining marks and emoji grapheme clusters are never split by a text
  operation.
- A cue with word timing may use active-word state only when the words are
  ordered, bounded by the cue, non-overlapping, and approved by backend timing
  quality. Its words must also reconstruct `cue.text` exactly as every
  `word.text + word.separatorAfter` joined in order; otherwise project
  validation rejects it and the caller falls back to segment/estimated timing.
- When edited text can no longer map safely to word timing, only that cue changes
  to `estimated` or `segment`; other cues retain their validated timing.
- Nullable cue style, position, and sound-effect metadata is preserved by
  ordinary copies and cleared only through explicit typed clear flags. When a
  clear flag and replacement value are both supplied, clearing wins.
- A cue may be inserted at any validated list index, including index zero in an
  empty project. Invalid insertion does not alter project state or undo history.
- Split inherits visual style/position on both results, while cue-start sound
  metadata remains only on the first result. Merge is rejected atomically when
  visual overrides differ by value or the second cue owns a sound effect.
- Merge text is language/script aware at the boundary: preserve explicit
  whitespace; add none before Unicode closing punctuation (`Pe`/`Pf`) or the
  common closing `Po` set; add none after Unicode opening/initial/currency
  prefixes (`Ps`/`Pi`/`Sc`); concatenate Thai-to-Thai directly; add one space
  when either grapheme is ASCII Latin/digit; and add one space between other
  word-like graphemes for a non-Thai project language. Unicode category checks
  are anchored to the complete boundary grapheme.

## Components

### Project and commands

New focused files live under
`apps/mobile/lib/features/ai_editing/subtitle_studio/` rather than adding more
responsibility to the existing large `ai_editing_screen.dart`.

- `subtitle_project.dart`: immutable domain values, validation, JSON versioning.
- `subtitle_project_mapper.dart`: maps the current recipe and future optional
  validated cue metadata into a project.
- `subtitle_project_editor.dart`: validated edit/add/delete/split/merge/timing
  operations and bounded undo/redo (50 full-project snapshots).
- `subtitle_editor_controller.dart`: future selected-cue state, autosave
  scheduling, and export snapshot coordination.
- `subtitle_draft_store.dart`: injectable local persistence abstraction.

### Editor UI

- `subtitle_studio_screen.dart`: phone-first screen and bottom tabs.
- `subtitle_video_preview.dart`: video plus bounded subtitle overlay.
- `subtitle_cue_list.dart`: lazy list, selection, edit, cue replay controls.
- `subtitle_style_sheet.dart`: whole-clip controls for the parity-tested MVP set.

The MVP does not reproduce a desktop three-column layout. The video stays at
the top and the lower area switches between text and style tools.

### ASS export

- `ass_subtitle_writer.dart`: deterministic ASS header/styles/events, timestamp
  and RGB-to-ASS-BGR conversion, text escaping, font allowlist, and static
  fallback.
- The existing subtitle burn processor accepts either the legacy SRT artifact or
  the new ASS artifact and keeps all current encoder, stream verification,
  cancellation, cleanup, progress, and audio/video cut behavior.

For the desired “only the current word changes colour” look, the first verified
implementation uses time-sliced dialogue events that display the full cue and
apply an inline colour override only to the active word. Standard `\\k` karaoke
tags are not assumed to match this state because prior/future words may retain
primary/secondary colours. If event volume is too expensive on a supported
device, the cue falls back to a static event.

## Data Flow

1. Seller selects the source and AI setup options.
2. Mobile performs the existing subscription preflight and audio-only prepare
   flow.
3. API returns one recipe with transcript segments/words, cut ranges, and quota.
4. Mobile maps the cached recipe into `SubtitleProject`.
5. Subtitle Studio previews and edits the project entirely on-device.
6. Autosave writes a versioned local draft; no provider/API call occurs.
7. Seller confirms; controller freezes an immutable export snapshot.
8. ASS writer creates the subtitle artifact using only allowlisted bundled fonts.
9. Existing FFmpeg renderer burns subtitles before applying source-time cuts.
10. Existing output stream verification accepts or rejects the result.
11. Current result review shows original/result and continues to Upload/Post.

## Persistence

The first release stores one recoverable active project and reusable style data
locally. A small preferences index may point to a versioned JSON file in
app-owned storage; the full project is not kept indefinitely as one large
SharedPreferences value.

Autosave is debounced and atomic: serialize operations per short internal
project ID, write and validate a `.next` replacement, rotate the target to
`.backup`, then promote `.next`. A valid matching `.next` is the newest intended
replacement even when a valid target exists; promotion uses that target as the
rollback source. If promotion fails, restore the old target where possible and
retain recoverable remnants, and a failed queued operation does not block the
next same-project operation. If a valid target has no `.next`, any lone backup
remnant is neither read/validated nor modified; the target is returned even
when that backup is corrupt or belongs to another project. With no target,
recovery chooses a valid matching `.next` before a valid matching `.backup`.
A present corrupt, unsupported, or mismatched target is never overwritten or
deleted during load, even if valid remnants exist; load returns no draft and
preserves all files. Draft filenames use a case-insensitive-safe encoding and a
bounded component length. A corrupt or unsupported schema never crashes the
editor; it offers to rebuild from the cached recipe. If the picked source path
has expired, PostDee asks the seller to choose the same source and validates a
fingerprint before reconnecting the draft.

Cloud persistence is a separate later design requiring authenticated ownership,
retention/deletion rules, quotas, optimistic concurrency, and PDPA review.

## API Compatibility

The first project mapper can use the existing recipe, so no new endpoint or
Prisma model is required.

Before public active-word rollout, the API should add optional backward-
compatible cue metadata such as `timingMode` and validated `words` under
`subtitles`. Mobile must not independently treat raw provider word timing as
trusted because backend code already checks text/timeline coverage and
fragmented Thai tokens.

The existing `subtitles.segments` field remains until old deployed clients are
outside their compatibility window.

## Error Handling

- Invalid cue/text/timing: identify the exact cue and block export until fixed.
- Unsafe word alignment: render a static cue; do not flash the wrong word.
- Missing/expired source: keep the draft and ask the seller to relink the file.
- Autosave failure: keep in-memory edits, show a recoverable warning, and allow
  export while the source is still available.
- ASS generation failure: keep the project and previous accepted output; do not
  call transcription again.
- FFmpeg failure/cancel: keep source, project, and last accepted output exactly
  as the current review flow does.
- Unsupported device/performance threshold: disable active-word events and use
  static ASS/SRT rather than fail the complete export.

## Quota and Privacy

- Existing Pro AI Editing entitlement and minute ledger stay unchanged for MVP.
- One successful prepare/transcription is charged according to current rules.
- Editing, autosave, preview, export, cancel, and local render retry consume no
  additional AI minutes.
- Source video remains local for current supported capabilities.
- Temporary audio uses the existing authenticated owner checks and cleanup.
- Drafts do not create transcript analytics or cloud uploads by default.
- Raw media, signed URLs, storage keys, transcripts, and provider credentials are
  not written to normal logs.
- Only commercially redistributable fonts and sound assets may ship.

## Testing

Tests are written and observed failing before implementation.

Domain/foundation tests cover JSON round-trip/version fallback, exact word-text
reconstruction, nullable metadata clearing, IDs, finite/clamped timing,
sorting/overlap rejection, empty-project insertion, add/delete/split/merge,
language-aware joins, split/merge metadata safety, Thai graphemes, undo/redo,
recipe conversion including an empty prepared cue list, and atomic draft
recovery/queue continuation.

ASS tests cover timestamp/colour conversion, escaping `\\`, braces and newline,
font allowlisting, static cues, active-word event coverage, malformed timing,
and legacy SRT fallback.

Widget tests cover cue seek/replay, immediate text/style preview, selection,
keyboard/focus, undo/redo, autosave debounce, missing source recovery, and final
export using the latest immutable project snapshot.

Real-device acceptance covers Thai speech with combining marks, English product
names, numbers/prices, emoji, background music, silence cuts, 3–5 minute clips,
Android/iOS performance, cancellation, free-space failure, A/V stream validity,
and preview/export visual tolerance.

## Rollout

1. Add domain/command tests and project mapper without changing customer flow.
2. Add the editor and static preview behind a disabled feature flag.
3. Add optional validated cue metadata and ASS static styles.
4. Add active-word events with static fallback.
5. Run focused automated tests and physical-device acceptance.
6. Enable the flag for internal QA, then a small production cohort.
7. Make Subtitle Studio the standard pre-render step only after crash, render,
   quota, performance, and preview-parity evidence is acceptable.

## Success Criteria

- A seller corrects any prepared cue before export.
- Add/delete/split/merge and timing changes remain valid and undoable.
- A local autosave can recover the project when the source is still available.
- Preview changes immediately without an FFmpeg render or API request.
- Final output contains the accepted text/style and valid audio/video streams.
- Safe word timing highlights only the active word; unsafe timing is static.
- Silence/best-moment cuts keep subtitle/audio alignment.
- Failure preserves source, draft, and last accepted output.
- Reopening/editing/rendering does not charge another AI minute.
