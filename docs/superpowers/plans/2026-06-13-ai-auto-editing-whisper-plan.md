# AI Auto Editing With Groq Whisper Implementation Plan

> Status: mobile editing UI built as a **scaffold** (2026-06-17) in `apps/mobile/lib/features/ai_editing/`, on its own bottom-nav "ตัดต่อ" tab. The tab (`ai_editing_screen.dart`) is a thin entry that opens a single **unified CapCut-style editor** (`capcut_editor_screen.dart`): preview + timeline (trim handles, split, playhead) + a bottom tool bar mixing manual tools (trim, split, speed, volume, text, sticker, filter, adjust) with AI helpers (auto caption + silence-cut with per-segment toggles). The user chooses per tool — let AI cut/caption, or do it by hand. This extends beyond the original AI-auto scope (a general editor) because users are familiar with CapCut.
>
> Original plan name referenced Whisper-1. The current production direction is Groq `whisper-large-v3` for transcription, with the same quota ledger and mobile FFmpeg export flow.
>
> 2026-07-03 update: `POST /ai-edits/prepare` now turns the Claude Design AI editing UI toggles, style/prompt, transcript, cut suggestions, overlays, and render hints into a mobile FFmpeg recipe. Server-side video rendering remains out of scope.

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
- Request word-level timestamps so the app knows when each spoken word starts and ends.
- Return structured transcript data to mobile:
  - full text
  - sentence/segment timing
  - word timing
  - confidence/error metadata where available

### 2. Auto-cut silence

- Detect silent gaps from transcript word timing first.
- Later, improve accuracy with FFmpeg silence detection.
- Let users preview the suggested cuts before exporting.
- Keep the first version conservative so it does not cut natural pauses too aggressively.

### 3. Flexible subtitle editing

Mobile subtitle editor should support:

- subtitle display mode:
  - 1 word at a time
  - 2 words at a time
  - 1 sentence/phrase at a time
- font selection
- subtitle color selection
- outline/background style
- edit wrong Thai words before final export
- preview subtitles over the video before burn-in

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
- Run FFmpeg export locally on the user's phone.
- Show export progress and friendly error messages.
- Continue into the existing posting/scheduling flow with the exported file.

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

### Phase 3: Mobile transcript UI

- Add AI editing entry point inside Upload after video selection.
- Add transcription progress state.
- Add subtitle review screen:
  - transcript list
  - editable words/phrases
  - display mode selector
  - font/color selector
- Do not render final video yet in this phase.

### Phase 4: Mobile FFmpeg export

- Add subtitle burn-in processor.
- Add conservative silence cut processor.
- Combine with existing watermark processor where possible.
- Export a final MP4 and pass it back to the Upload flow.
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
- Word-level timestamps are essential for karaoke-style subtitles. If a future chosen model does not support them, keep Groq `whisper-large-v3` for timing or add a separate alignment step.
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

- A Pro user can choose a video, request AI transcription, edit Thai subtitle text, export a subtitled MP4 on the phone, and post/schedule that exported MP4.
- Quota minutes are counted by audio/video duration.
- Basic users are blocked with a clear upgrade message.
- Failed transcription/export does not silently consume quota without a recoverable state.
- Tests cover backend quota rules and mobile happy path/error states.
