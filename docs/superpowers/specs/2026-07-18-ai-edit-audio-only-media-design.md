# AI Edit Audio-Only Media Design

## Goal

Reduce AI editing transfer, memory, and temporary-storage load by extracting a small audio artifact on the mobile device and sending that artifact to Groq Whisper for transcription, while keeping the original video local for FFmpeg preview and export.

## Approved Product Behavior

- The customer continues to select a normal video and press the existing AI editing action. There is no file-format or analysis-mode choice in the UI.
- Source videos may be `.mp4`, `.mov`, or another format accepted by the existing picker and FFmpeg build.
- PostDee creates a temporary `.m4a` audio file automatically. The customer never needs to create, select, rename, or manage this file.
- Subtitle timing, silence removal, and filler-word removal use audio-only analysis.
- Current color adjustment remains a local FFmpeg operation and does not make the AI inspect the video.
- The original video remains unchanged and local until PostDee renders the reviewed result.
- A clip with no usable audio stops before upload or AI usage and shows a clear Thai error. It does not consume AI editing minutes.
- Visual analysis and the 360p proxy are out of scope until a real visual capability such as shot selection, product-aware zoom, or reframing is production-ready.

## Chosen Approach

Use mobile-side FFmpeg extraction, the existing authenticated managed upload flow, temporary R2 storage, backend ownership/quota enforcement, Groq Whisper transcription, and mobile-side FFmpeg rendering.

Rejected alternatives:

- Server-side extraction still uploads and buffers the full source video, so it does not deliver the intended transfer/RAM reduction.
- Direct mobile-to-Groq upload would require a safe ephemeral credential and quota protocol and would move provider security concerns into the client.

## Architecture

The mobile app selects an analysis strategy from the effective enabled capabilities. Every currently production-supported AI editing capability uses `audio-only`; unknown or future visual capabilities fail closed instead of silently sending the wrong media. The app extracts AAC audio into an M4A container using one channel, 16 kHz sampling, and a 64 kbps target bitrate.

The generic upload API gains a narrowly validated `ai-edit-audio` purpose. That purpose accepts only `audio/mp4`, a `.m4a` filename, no image dimensions, and at most 25 MiB. Existing video/image requests keep their current behavior and do not need the new purpose.

The AI editing API accepts `audioS3Key` for new clients and keeps `videoS3Key` as a temporary backward-compatible fallback. Exactly one key is accepted per request. Only an owned key can be transcribed or cleaned up. Internally, transcription inputs use a media-neutral key name so the caption and legacy video flows do not pretend every input is audio.

The API and mobile client both attempt remote cleanup. S3-compatible deletion is idempotent, so a second delete is safe. The API performs cleanup after every accepted prepare/transcribe attempt, including quota and provider failures. The mobile client calls the authenticated cleanup endpoint after an upload whenever the prepare result is received or fails. Local temporary files are deleted in a `finally` path.

## Components

### Mobile analysis selection

- Add a small pure media-strategy selector under `apps/mobile/lib/features/ai_editing/`.
- Inputs are the effective capability flags after production locks are applied.
- `subtitle`, `silence`, `filler`, and local `color` resolve to `audio-only`.
- Any enabled unknown/visual capability returns an unsupported result. It must not silently upload the full source video.
- The selection happens automatically inside the existing process action; no new customer control is added.

### Mobile audio artifact

- Add an injectable FFmpeg audio extractor under `apps/mobile/lib/features/ai_editing/`.
- Output is a uniquely named `.m4a` in a PostDee-owned temporary directory.
- FFmpeg removes video and encodes AAC, mono, 16 kHz, 64 kbps.
- The extractor verifies a successful return code, a non-empty output file, and an audio stream. Missing audio gets a dedicated user-facing error.
- The artifact owns cleanup of its temporary file/directory so tests can verify success and failure lifecycles.

### Upload validation

- Extend mobile `CreateUploadRequest` with optional `purpose` and send `ai-edit-audio` only for the extracted artifact.
- Extend backend upload metadata validation without changing existing video/image behavior.
- `purpose=ai-edit-audio` requires content type `audio/mp4`, extension `.m4a`, positive size, size at most 25 MiB, and absent width/height.
- Audio without that purpose, other audio MIME types, oversized audio, and audio requests with dimensions are rejected with a specific validation code/message.

### AI editing contract

- New mobile clients send `audioS3Key`, `durationSeconds`, capabilities/settings, and no `videoS3Key`.
- `/ai-edits/prepare` and `/ai-edits/transcribe` accept exactly one of `audioS3Key` or legacy `videoS3Key`.
- `audioS3Key` must be owned by the authenticated user and identify an `.m4a` object.
- The backend downloads the audio with a 25 MiB ceiling and expects `audio/mp4` before calling Groq.
- Legacy `videoS3Key` keeps the existing 200 MiB ceiling during the compatibility window and is never automatically deleted.
- Responses keep the existing recipe, transcript, and quota shape, so mobile rendering and review do not need a product-flow rewrite.

### Remote cleanup

- AI edit routes receive the existing storage delete dependency.
- When `audioS3Key` is used, the route requests deletion in a `finally` path after validation has established ownership.
- Add an authenticated idempotent audio-cleanup endpoint for the mobile client to cover upload-completed/request-never-arrived and lost-response cases.
- The cleanup endpoint accepts only an owned `.m4a` audio key; it cannot delete another user's media or a video key.
- Cleanup failure is logged without converting an otherwise successful transcription into a failed edit. Operations monitoring must expose cleanup failures.

## Data Flow

1. Customer selects a video in the existing AI Editing screen.
2. Mobile applies production capability locks and selects `audio-only`.
3. Mobile checks subscription state and available quota as it does today.
4. Mobile FFmpeg extracts temporary AAC/M4A audio from the local source video.
5. Mobile requests a managed upload with `purpose=ai-edit-audio`, `contentType=audio/mp4`, and the actual file size.
6. Mobile uploads the temporary M4A directly to R2.
7. Mobile calls `/ai-edits/prepare` with `audioS3Key` and the existing editing configuration.
8. Backend verifies Pro access, ownership, extension/content type, preliminary quota, and bounded media size.
9. Backend sends the audio bytes to Groq Whisper and meters the returned real duration using the existing quota rules.
10. Backend builds the existing mobile FFmpeg recipe and returns it.
11. Backend deletes the remote M4A in `finally`; mobile also calls best-effort cleanup after the request settles.
12. Mobile deletes the local temporary audio in `finally`.
13. Mobile renders and previews the recipe against the original local video, preserving final video quality.

## Backward Compatibility

- Existing app versions can continue sending `videoS3Key` during a documented compatibility window.
- New app versions send only `audioS3Key` for current supported capabilities.
- Requests containing both keys return `400 AI_EDIT_MEDIA_AMBIGUOUS`.
- Requests containing neither key retain a clear `400` media-required error.
- The legacy public field is removed only after deployed-version adoption is measured and an API version/migration plan is approved.

## Error Handling and Quota Rules

- No audio stream or FFmpeg extraction failure: no upload, no provider call, no quota usage.
- Upload creation/upload failure: no provider call, no quota usage; local audio is cleaned up.
- Basic/Starter plan or preliminary quota rejection: no provider call; remote audio cleanup is attempted.
- Invalid ownership, extension, MIME, or size: no provider call and no cross-user cleanup.
- Groq failure: no successful-minute reservation; remote/local cleanup still runs.
- Successful Groq response: meter the provider-reported duration exactly as the current route does.
- Local render failure after a successful transcription keeps the existing quota behavior because the paid AI work already occurred; the customer can retry rendering from the cached recipe without another transcription call.
- The app never falls back to uploading the full video without telling the customer.

## Security and Privacy

- Authentication and storage-key ownership checks remain mandatory before download or delete.
- The audio key, signed URL, raw transcript, and customer audio must not be written to normal logs or Sentry breadcrumbs.
- Temporary audio is deleted after processing and is included in account-wide media cleanup if immediate deletion fails.
- MIME/extension/size checks reduce misuse but do not replace provider-side validation and bounded downloads.
- Groq credentials remain backend-only.

## Testing

Tests are written first and observed failing before implementation.

Backend coverage:

- Upload validation accepts only the exact AI audio purpose/MIME/extension/size contract.
- Existing video/image upload tests remain unchanged and passing.
- Prepare/transcribe accept owned audio and reject ambiguous, missing, foreign, oversized, or wrong-type media.
- Legacy video requests remain compatible and are not deleted.
- Audio cleanup runs on success, quota rejection, and provider failure; duplicate cleanup is safe.
- Quota is not consumed when audio validation or Groq fails.

Mobile coverage:

- Current supported capabilities select audio-only automatically.
- Unknown/visual capabilities fail closed and never upload full video.
- FFmpeg arguments create AAC/M4A mono 16 kHz 64 kbps without video.
- No-audio, extraction failure, upload failure, prepare failure, success, and widget disposal clean local artifacts.
- New prepare requests contain `audioS3Key` and do not contain `videoS3Key`.
- Existing review/render behavior still uses the original local video.
- Remote cleanup is requested after upload for both success and failure paths.

Verification commands after implementation:

```powershell
cd apps/api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate

cd ..\mobile
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

## Documentation Sync

After implementation, update `API.md`, `ARCHITECTURE.md`, `README.md`, `ROADMAP.md`, the AI auto-editing plan, and go-live/staging checklists. Documentation must distinguish the implemented audio-only path from the future 360p visual proxy and must not advertise visual editing as production-ready.

## Success Criteria

- A real `.mp4` or `.mov` source can complete the existing AI Editing flow while only the temporary M4A is sent for transcription.
- The original full video is not uploaded for current audio-only capabilities.
- The customer performs no manual conversion or file selection.
- Clips without audio do not consume quota.
- Temporary audio is cleaned locally and remotely in normal success/failure paths.
- Old app requests continue to work during the compatibility window.
- Existing recipe review and 1080p-quality mobile export behavior remains intact.
