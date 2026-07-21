# AI Auto Editing With Groq Whisper Implementation Plan

> Status: the mobile flow stays in `ai_editing_screen.dart` through **setup → prepare/render → result review**. The user previews the AI result and uses review checkboxes to remove or restore supported edits; every change automatically re-renders locally from the original clip before the accepted result continues to Upload/Post.
>
> Original plan name referenced Whisper-1. The current production direction is Groq `whisper-large-v3` for transcription, with the same quota ledger and mobile FFmpeg export flow.
>
> 2026-07-03 update: `POST /ai-edits/prepare` now turns the Claude Design AI editing UI toggles, style/prompt, transcript, cut suggestions, overlays, and render hints into a mobile FFmpeg recipe. Server-side video rendering remains out of scope.
>
> 2026-07-22 provider-failure update: `/ai-edits/transcribe` and
> `/ai-edits/prepare` return structured HTTP 502
> `AI_TRANSCRIPTION_PROVIDER_FAILED` before quota reservation when transcription
> is unavailable. Mobile shows a Thai retry message instead of `Request failed`.
>
> 2026-07-22 target-length update: the customer flow no longer preselects 30
> seconds. The seller must choose 30/60/custom before processing, and the
> selected value is sent as `targetDurationSeconds` for AI highlight planning.
>
> 2026-07-11 update: mobile now caches a successful prepare recipe, shows a playable result review, supports reversible subtitle/silence/filler/color edits that are actually rendered, and keeps `planned` capabilities out of the applied list. Local retry does not call the minute-metered prepare endpoint again.
>
> 2026-07-12 automatic-preview update: changing a supported edit checkbox immediately starts a local preview re-render from the original clip. Controls are locked while FFmpeg runs, the previous playable preview remains visible, and a failed update restores both the last accepted checkbox state and video.
>
> 2026-07-12 beat-sync update: capability setup can keep original audio or select an owned MP3/M4A/WAV file with explicit rights confirmation, then send source, intensity, volume, and ducking preferences in `recipe.music`. The licensed catalog, beat analyzer, audio mixer, and ducking renderer remain planned and are not shown as applied.
> Catalog entries stay disabled unless their license metadata covers all six publishing destinations; local file paths and storage keys are never trusted as client API input.
>
> 2026-07-12 UX safety update: production keeps beat sync off and shows `เร็ว ๆ นี้` through the default-false `ENABLE_EXPERIMENTAL_BEAT_SYNC` compile-time flag. Internal QA may set the flag to `true` to inspect setup controls only; it does not enable rendering. Capability settings are available without a global advanced-mode switch and use an accordion with at most one open section and no default expansion.
>
> 2026-07-12 pace update (revised 2026-07-14): silence cleanup uses
> `natural` (1.0 s), `balanced` (0.6 s default), or `compact` (0.4 s) validated
> word-gap thresholds with segment fallback, overlap-safe range merging, and
> qualifying leading/trailing gaps when duration is valid. Filler cleanup uses exact
> normalized matches from the five-word allowlist `เอ่อ`, `อ่า`, `แบบว่า`,
> `คือว่า`, `ประมาณว่า`; missing legacy input means all five, while explicit
> empty input means none. Review shows detected range counts and combined
> detected time. The 3-second hook stays locked in production by default-false
> `ENABLE_EXPERIMENTAL_AI_HOOK`; internal exposure remains `planned` with no renderer.
>
> 2026-07-13 Android render verification: subtitle burn-in now supplies the bundled Prompt font to libass, and silence removal concatenates reset audio keep ranges instead of retaining the source timestamps. A Pixel emulator real-flow test produced visible subtitles and aligned 14.24 s video / 14.31 s audio from a 19.4 s source, and both review capabilities were removed and restored successfully.
>
> 2026-07-13 quota visibility update: the AI editing header shows exact remaining/used Pro minutes from `GET /ai-edits/quota`, updates immediately from the metered `prepare.quota` response, and supports a non-metered tap-to-refresh action.
>
> 2026-07-14 capability-honesty update: production enables only subtitle,
> silence, filler-word cuts, and color/light adjustment. Reframe, zoom, audio
> cleanup, translation, price tags, CTA cards, and the AI-page watermark stay
> locked as `เร็ว ๆ นี้`, are sent disabled by mobile, and remain `planned` in
> the API until real exported-video processors are verified.
>
> 2026-07-22 deferred-controls update: translation, price-tag, CTA-card, and
> AI-page watermark controls are hidden from the customer setup UI until their
> exported-video processors are real. Their capability keys remain disabled in
> payloads for preset and API compatibility.
>
> 2026-07-14 subtitle-controls honesty update: the verified mobile renderer
> currently burns white subtitles with a black outline, supports three text
> sizes, groups text into short/medium/long ranges, and positions subtitles at
> the top or bottom. Custom font/color, true word-highlight karaoke, center
> positioning, and manual transcript correction remain planned and must not be
> presented as working controls until their exported video is verified.
>
> 2026-07-14 Thai timing update: the recipe validates word timing coverage and
> uses valid timings for silence detection. Semantic word tokens may also drive
> subtitle grouping; Groq Thai character-level tokens keep their precise gaps
> but fall back to readable segment subtitles. Semantic Thai subtitle tokens
> stay joined while Latin product names and numbers keep readable spacing.
> Fragmented filler tokens are
> reassembled conservatively from the exact allowlist across tight timing and
> verified Thai word/text boundaries (or timing boundaries on both sides when
> reference text is unavailable), including `เออ` as the transcription
> alias for `เอ่อ`. Whitespace-only provider tokens are ignored without hiding
> invalid timing on meaningful transcript tokens.

## Goal

Add an AI automatic editing system for PostDee that helps Thai sellers turn a vertical video into a cleaner short clip with accurate Thai subtitles, optional silence cutting, and mobile-side rendering.

This plan is separate from the package-level **AI caption from real clip** feature:

- Starter 199 can use real-clip captioning from audio only.
- Pro 299 can use real-clip captioning from audio plus selected video frames.
- Both packages can receive SEO wording, hashtags, caption options, hook ideas,
  and auto language/market context inferred from the clip.
- Full subtitle burn-in, silence cutting, and exported edited video remain the AI auto editing scope below.

The first implementation direction is **Approach 1: Hybrid low-cost architecture**:

- Backend handles authentication, plan/quota checks, temporary storage, and Groq Whisper transcription.
- Mobile handles preview, subtitle editing, FFmpeg subtitle burn-in, silence cutting, watermarking, and final upload.
- Use Groq `whisper-large-v3` first for transcription because it is the top Groq Whisper model and supports the timestamp workflow needed for subtitle timing.

## Core Features

### 1. Accurate Thai transcription

- Extract or upload the clip audio.
- Backend sends audio to Groq `whisper-large-v3`.
- Send the ISO-639-1 `th` language hint for Thai-first accuracy and latency.
- Send a concise Groq-only Thai spelling prompt for the proper noun
  `PostDee` → `โพสต์ดี`; do not silently replace transcript text afterward.
- Request both word- and segment-level timestamps in the same Groq call. Words
  are validated for text/timeline coverage before driving subtitle, silence, and
  filler timing. Segments remain the conservative fallback for partial timing
  and the readable subtitle source for Thai character-level tokens.
- Return structured transcript data to mobile:
  - full text
  - sentence/segment timing
  - word timing
  - confidence/error metadata where available

### 2. Auto-cut silence and filler words

- Detect silent gaps from validated word timing first, with segment timing as a
  conservative fallback.
- Merge overlapping timing ranges and apply the same threshold to leading and
  trailing silence when a finite media duration is available.
- Let the user choose a 1.0 s `natural`, 0.6 s `balanced`, or 0.4 s `compact`
  minimum gap; missing/invalid input stays backward compatible with `balanced`.
- Let the user choose from the exact allowlist `เอ่อ`, `อ่า`, `แบบว่า`,
  `คือว่า`, `ประมาณว่า`. Missing legacy `fillerWords` means all five; an
  explicit empty list means no filler cuts and never falls back implicitly.
- Treat exact transcript `เออ` as the `เอ่อ` alias. Reassemble only a validated
  Thai character-token stream across tight timing and verified Thai word/text
  boundaries, or timing boundaries on both sides when reference text is
  unavailable; do not substring-match longer semantic tokens.
- Later, improve accuracy with FFmpeg silence detection.
- Let users preview the suggested cuts before exporting.
- Show detected silence/filler counts and their combined pre-render time without
  promising the same number of seconds will disappear from the final clip.
- Keep the first version conservative so it does not cut natural pauses too aggressively.

### 3. Flexible subtitle editing

The first verified mobile subtitle editor supports:

- short, medium, or long text grouping per subtitle range
- readable spacing for Latin product names and numbers inside Thai subtitles
- three text sizes
- white text with a black outline
- top or bottom positioning
- preview subtitles over the video before burn-in

Keep these controls planned until their exported-video behavior exists and is
verified: custom font/color, outline/background selection, true word-highlight
karaoke, center positioning, and editing incorrect Thai transcript words before
final export.

### 4. Mobile-side render/export

- Use the existing Flutter + FFmpeg direction.
- Mobile creates the final edited video:
  - cut silence
  - burn in subtitles
  - apply watermark if enabled
  - export final MP4
- Upload the final MP4 to the existing upload/post flow.

## Smart Architecture

### Backend responsibilities

- Verify signed-in user.
- Check subscription and AI editing quota.
- Create an AI editing job.
- Store temporary media/audio in Cloudflare R2 or existing video storage adapter.
- Send audio to Groq `whisper-large-v3`.
- Save transcript result and usage.
- Return transcript/timing data or a UI-facing mobile render recipe to mobile.
- Track quota minutes and top-up minutes.

Backend should not render video in the first version. Rendering video server-side is intentionally out of scope to keep cost low.

### Mobile responsibilities

- Let user choose video from Upload.
- Show AI editing entry point after video selection.
- Display transcription progress.
- Show subtitle editor and style controls.
- Preview silence cut suggestions.
- Configure the silence preset and exact filler-word allowlist; require at least
  one filler word while that capability is enabled.
- Show detected silence/filler counts and combined detected time in result review.
- Keep the opening hook locked as `เร็ว ๆ นี้` when
  `ENABLE_EXPERIMENTAL_AI_HOOK=false`; an internal true value exposes setup UI
  only and does not add highlight selection or timeline rendering.
- Configure beat-sync music safely: keep original audio or choose an owned file,
  confirm usage rights, and set intensity, volume, and voice ducking without
  claiming the pending renderer has applied them.
- Render and preview the initial result locally on the user's phone.
- Let the user remove supported AI edits and re-render once from the original clip.
- Show export progress and friendly error messages.
- Continue with the accepted result directly into posting/scheduling.

## Pricing Model To Plan Around

Package positioning lives in `docs/superpowers/plans/2026-06-13-subscription-packages-plan.md`.

### Pro plan

- Price: 299 THB/month.
- Included AI editing quota: 200 minutes/month.
- Expected AI transcription cost target: about 13 THB/month per fully used quota at 200 minutes, before retries.
- Expected gross margin target before app-store fees, tax, server, retries, and support: about 254 THB.

### Top-up

- Price: 49 THB.
- Additional AI editing quota: 120 minutes.
- Expected AI transcription cost target: about 8 THB at 120 minutes, before retries.
- Expected gross margin target before payment fees, tax, server, retries, and support: about 22.50 THB.

### Important pricing note

These numbers are planning estimates. Before implementation or launch, verify current OpenAI pricing, exchange rate, Apple/Google fees, VAT/tax handling, and retry behavior.

## Recommended Build Phases

### Phase 1: Planning and data model

- Add backend design for AI editing jobs and minute usage ledger.
- Decide how quota is reserved, consumed, and refunded on failed jobs.
- Decide maximum file length and maximum monthly usage rules.
- Keep all providers mockable for tests.

### Phase 2: Backend transcription scaffold

- Add a mock transcription provider first.
- Add Groq `whisper-large-v3` provider behind config.
- Add API routes such as `POST /ai-edits/transcribe` and `POST /ai-edits/prepare`.
- Add quota checks for Pro and top-up minutes.
- Add tests for Basic blocked, Pro allowed, quota exceeded, and failed transcription.

### Phase 3: Mobile transcript and result-review UI

- Add AI editing entry point inside Upload after video selection.
- Add transcription progress state.
- Add subtitle review screen:
  - transcript list
  - editable words/phrases
  - display mode selector
  - font/color selector
- Keep the user on the AI screen after the initial render and show only
  capabilities that were actually applied.
- Present advanced capability settings as a single-open accordion with no
  default expansion. Keep beat sync locked as `เร็ว ๆ นี้` unless an internal
  QA build explicitly enables `ENABLE_EXPERIMENTAL_BEAT_SYNC=true`.
- Add real silence/filler advanced settings, preserve them in presets/snapshots,
  and show detected counts/time after analysis. Keep the hook locked unless an
  internal QA build sets `ENABLE_EXPERIMENTAL_AI_HOOK=true`; even then its recipe
  status remains `planned` and it must not appear as applied.

### Phase 4: Mobile FFmpeg export

- Add subtitle burn-in processor.
- Add conservative silence cut processor.
- Combine with existing watermark processor where possible.
- Re-render the accepted capability set from the original clip.
- Pass the latest result to Upload/Post.
- Add progress, cancellation, and error handling.

### Phase 5: Usage, billing, and top-up

- Show remaining AI editing minutes in Profile or Upload.
- Add top-up product scaffold.
- Add usage history.
- Add warnings before long clips consume quota.

### Phase 6: Real-device quality testing

- Test Thai speech accuracy with seller/product videos.
- Test background noise, music, fast speech, and mixed Thai/English.
- Test long clips, low-end Android devices, heat, battery, and app backgrounding.
- Test exported MP4 compatibility with TikTok, YouTube Shorts, Instagram Reels, and Facebook Reels.

## Risks And Decisions

- Groq `whisper-large-v3` is the first production transcription model. Re-check Groq docs before production launch because model pricing or timestamp support may change.
- Valid word-level timestamps provide precise filler/silence timing and may
  provide subtitle ranges; segment timing remains essential as a conservative
  fallback when words are partial or fragmented into unreadable Thai subtitle
  tokens. If a future chosen model cannot return both, keep Groq
  `whisper-large-v3` for timing or add a separate alignment step.
- Do not market a separate AI audio clip review feature for now. If the app needs audio understanding, merge it into "AI caption from the real clip" instead.
- Do not keep prompt-only AI captioning as the main sold feature. The sold feature should start from a selected clip.
- Mobile rendering saves server cost but may be slow on low-end phones.
- Android minSdk is already raised to 24 because of FFmpeg dependency.
- If mobile rendering causes too many failures, fallback option is server-side render for Pro users or long clips only.
- Groq cost estimates must include retries and failed exports, not just successful transcriptions.
- App-store fees and tax mean the listed margin is not net profit yet.

## Out Of Scope For First Version

- Full server-side video rendering.
- Advanced AI scene detection.
- Auto B-roll insertion.
- Voice enhancement/noise removal.
- Fully automatic social posting changes.
- Production launch pricing lock without latest cost verification.

## Acceptance Criteria For The First Real MVP

- A Pro user can choose a video, request AI transcription, review the rendered result on the AI screen, and remove or restore supported AI edits with an automatic preview update from the original clip.
- The user can send the accepted result to posting/scheduling.
- Quota minutes are counted by audio/video duration.
- Basic users are blocked with a clear upgrade message.
- Failed transcription/export does not silently consume quota without a recoverable state.
- Tests cover backend quota rules and mobile happy path/error states.
- Silence preset thresholds and exact filler allowlist semantics are covered by
  backend/client/UI tests, including missing legacy fields versus explicit empty
  `fillerWords`.
- Result review labels silence/filler counts and combined time as detections,
  not guaranteed exported-duration savings.
- Production keeps `ENABLE_EXPERIMENTAL_AI_HOOK=false` until a real hook analyzer
  and timeline renderer exist; internal requests remain `planned`.
- Production does not expose beat sync as usable until its analyzer, music
  mixer, ducking, licensing checks, and real-device rendering are verified.
