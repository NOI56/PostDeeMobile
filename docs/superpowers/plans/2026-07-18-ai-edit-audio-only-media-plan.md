# AI Edit Audio-Only Media Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make current AI Editing capabilities extract and upload a temporary M4A on mobile, transcribe only that audio, clean it locally/remotely, and continue rendering the original video on mobile.

**Architecture:** Add a purpose-limited `audio/mp4` path to the existing managed upload API, accept an owned `audioS3Key` in AI edit routes while preserving legacy `videoS3Key`, and keep the existing Groq/recipe/quota flow. Mobile selects `audio-only` from enabled production capabilities, extracts AAC/M4A with FFmpeg, uploads it, requests the existing recipe, and renders that recipe against the untouched source video.

> 2026-07-23 follow-up: this historical audio-only milestone remains valid for
> transcription and fallback. Whole-duration visual planning is implemented in
> `2026-07-23-ai-edit-whole-video-proxy-plan.md`; it intentionally supersedes the
> earlier “do not add the future 360p visual proxy” scope boundary.

**Tech Stack:** Flutter/Dart, FFmpegKit, Node.js, Express, TypeScript, Vitest, Prisma-compatible stores, Cloudflare R2/S3-compatible storage, Groq Whisper.

**Implementation status (2026-07-22):** Backend audio upload/media/cleanup support
is present on `main`. The scoped follow-up implements mobile M4A extraction and
cleanup plus transcript-based `targetDurationSeconds` planning for 30/60/custom.
Backend tests/build/Prisma validation and mobile analyze/tests/debug APK build
pass; real Staging evidence remains required after merge and deploy.

**Quality update (2026-07-22):** A duration-only change reuses the successful
in-memory transcript through non-metered `/ai-edits/plan`; Groq no longer
receives the PostDee spelling prompt, and highlight planning quality-gates
provider segments before selecting one continuous story window. The same gate
omits unreliable time ranges from rendered subtitle lines.

**Transcript coverage update (2026-07-23):** Production mobile now divides the
source audio into balanced M4A chunks no longer than 30 seconds and sends
ordered `audioChunks`. The API validates ownership for every key, transcribes
chunks sequentially, restores source-relative timestamps, merges one transcript,
clips AAC timing overrun at the next chunk boundary, meters the combined duration
once, and deletes every temporary chunk on success
or failure. Legacy single `audioS3Key` remains compatible.

## Global Constraints

- Follow `docs/superpowers/specs/2026-07-18-ai-edit-audio-only-media-design.md` exactly.
- Write each failing test and observe the expected failure before production code.
- Do not upload the full source video for current supported AI Editing capabilities.
- Do not add the future 360p visual proxy in this plan.
- Do not add a customer-facing mode or file-format picker.
- Accept only `.m4a` + `audio/mp4` + `purpose=ai-edit-audio`, maximum 25 MiB.
- Preserve legacy `videoS3Key` requests and never auto-delete legacy video media.
- Reject requests containing both `audioS3Key` and `videoS3Key`.
- Validate authenticated ownership before download or cleanup.
- Never log audio bytes, signed URLs, storage keys, transcripts, or provider credentials.
- Keep final preview/export on the original local video through the existing FFmpeg renderer.
- The worktree already contains unrelated user changes. Do not revert them or commit whole dirty files; inspect scoped diffs before every handoff.

---

### Task 1: Purpose-Limited Audio Upload Validation

**Files:**
- Create: `apps/api/src/modules/uploads/uploadService.test.ts`
- Modify: `apps/api/src/modules/uploads/uploadService.ts`
- Modify: `apps/api/src/modules/uploads/uploadRoutes.ts`
- Modify: `apps/api/src/modules/uploads/uploadRoutes.test.ts`

**Interfaces:**
- Produces: `aiEditAudioUploadPurpose = 'ai-edit-audio'`
- Produces: `aiEditAudioUploadMaxBytes = 25 * 1024 * 1024`
- Produces: upload validation result errors with a stable `code` and `message`
- Consumed later by: mobile `CreateUploadRequest.purpose`

- [ ] **Step 1: Add failing unit tests for the exact audio contract**

Create table-driven tests around `readUploadMetadata`:

```ts
it('accepts a bounded M4A only for the AI edit audio purpose', () => {
  expect(readUploadMetadata({
    purpose: 'ai-edit-audio',
    fileName: 'postdee-ai-edit.m4a',
    contentType: 'audio/mp4',
    sizeBytes: 1024
  }, { maxSizeBytes: 500 * 1024 * 1024 })).toMatchObject({
    ok: true,
    metadata: { fileName: 'postdee-ai-edit.m4a', contentType: 'audio/mp4' }
  });
});

it.each([
  ['missing purpose', { fileName: 'clip.m4a', contentType: 'audio/mp4', sizeBytes: 1024 }],
  ['wrong extension', { purpose: 'ai-edit-audio', fileName: 'clip.mp3', contentType: 'audio/mp4', sizeBytes: 1024 }],
  ['wrong MIME', { purpose: 'ai-edit-audio', fileName: 'clip.m4a', contentType: 'audio/mpeg', sizeBytes: 1024 }],
  ['dimensions supplied', { purpose: 'ai-edit-audio', fileName: 'clip.m4a', contentType: 'audio/mp4', sizeBytes: 1024, width: 360, height: 640 }],
  ['too large', { purpose: 'ai-edit-audio', fileName: 'clip.m4a', contentType: 'audio/mp4', sizeBytes: 25 * 1024 * 1024 + 1 }]
])('rejects %s', (_label, payload) => {
  expect(readUploadMetadata(payload, { maxSizeBytes: 500 * 1024 * 1024 })).toMatchObject({ ok: false });
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
cd apps/api
npm.cmd run test -- src/modules/uploads/uploadService.test.ts src/modules/uploads/uploadRoutes.test.ts
```

Expected: FAIL because `audio/mp4` is rejected and the audio-purpose constants/error code do not exist.

- [ ] **Step 3: Implement the minimal purpose branch**

Add constants and a strict branch before the existing video/image rule:

```ts
export const aiEditAudioUploadPurpose = 'ai-edit-audio' as const;
export const aiEditAudioUploadMaxBytes = 25 * 1024 * 1024;

const isAiEditAudio = payload.purpose === aiEditAudioUploadPurpose;
if (isAiEditAudio) {
  const valid = contentType === 'audio/mp4' &&
    fileName.toLowerCase().endsWith('.m4a') &&
    isPositiveNumber(sizeBytes) &&
    sizeBytes <= Math.min(maxSizeBytes, aiEditAudioUploadMaxBytes) &&
    width === undefined && height === undefined;
  if (!valid) {
    return {
      ok: false as const,
      code: 'UPLOAD_AI_EDIT_AUDIO_INVALID',
      message: 'AI edit audio must be an M4A audio/mp4 file no larger than 25 MiB.'
    };
  }
}
```

Keep the returned storage metadata shape unchanged so managed/legacy storage adapters need no schema change. Update the route to include `code` when the validation result provides one.

- [ ] **Step 4: Verify GREEN and existing upload compatibility**

Run the same focused test command. Expected: all upload service/route tests PASS, including existing video, image, legacy, dual, and multipart cases.

### Task 2: Media-Neutral Transcription With a Bounded Audio Download

**Files:**
- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.ts`
- Modify: `apps/api/src/modules/aiEdits/transcriptionProvider.test.ts`
- Modify: `apps/api/src/modules/storage/mediaDownload.ts`
- Modify: `apps/api/src/modules/storage/mediaDownload.test.ts`
- Modify: `apps/api/src/app.ts`
- Modify: `apps/api/src/modules/captions/captionRoutes.ts`
- Modify tests that construct `TranscriptionInput`

**Interfaces:**
- Produces: `type TranscriptionMediaKind = 'audio' | 'legacy-video'`
- Produces: `type TranscriptionInput = { mediaS3Key: string; mediaKind: TranscriptionMediaKind }`
- Produces: `aiEditAudioDownloadMaxBytes = 25 * 1024 * 1024`
- Produces: `FetchAudio(input: TranscriptionInput): Promise<AudioSource>`

- [ ] **Step 1: Add failing provider/download tests**

Assert that Groq receives an M4A fetched with the media-neutral input and that bounded audio rejects declared or actual content above 25 MiB:

```ts
expect(fetchAudio).toHaveBeenCalledWith({
  mediaS3Key: 'uploads/local-dev-user/audio/clip.m4a',
  mediaKind: 'audio'
});
expect(form.get('file')).toBeInstanceOf(Blob);
```

Add a media-download test using `readAiMediaResponseBytes(response, aiEditAudioDownloadMaxBytes)` and expect `AI_MEDIA_TOO_LARGE`.

- [ ] **Step 2: Run focused tests and verify RED**

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/transcriptionProvider.test.ts src/modules/storage/mediaDownload.test.ts
```

Expected: FAIL because the provider still accepts `{ videoS3Key }` and no 25 MiB audio constant exists.

- [ ] **Step 3: Implement the media-neutral input**

Use the input object end to end:

```ts
export type TranscriptionMediaKind = 'audio' | 'legacy-video';
export type TranscriptionInput = {
  mediaS3Key: string;
  mediaKind: TranscriptionMediaKind;
};
export type FetchAudio = (input: TranscriptionInput) => Promise<AudioSource>;
```

In `app.ts`, fetch signed storage media and apply:

- audio: require `audio/mp4`, use 25 MiB ceiling, filename remains `.m4a`;
- legacy video: preserve the current 200 MiB ceiling and current content type behavior.

Update the real-clip caption fallback call to pass `{ mediaS3Key: videoS3Key, mediaKind: 'legacy-video' }`. Do not change the public caption API in this task.

- [ ] **Step 4: Verify GREEN**

Run the focused provider/download/caption tests. Expected: PASS and Groq multipart form still contains Thai hint, timestamps, provider model, and real media bytes.

### Task 3: Audio AI Edit Contract, Ownership, and Idempotent Cleanup

**Files:**
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.ts`
- Modify: `apps/api/src/modules/aiEdits/aiEditRoutes.test.ts`
- Modify: `apps/api/src/app.ts`
- Modify: `API.md`

**Interfaces:**
- Consumes: media-neutral transcription input from Task 2
- Produces: public `audioS3Key` support on `/ai-edits/transcribe` and `/ai-edits/prepare`
- Produces: `POST /ai-edits/audio/cleanup` with `{ audioS3Key: string }`
- Preserves: legacy `videoS3Key`

- [ ] **Step 1: Add failing route tests for new/legacy requests**

Cover:

```ts
it('prepares from owned temporary audio and deletes it', async () => {
  const audioS3Key = ownedUploadKey('local-dev-user', 'clip.m4a');
  const deleteVideo = vi.fn(async () => undefined);
  const transcribe = vi.fn(async () => ({
    text: 'เธชเธงเธฑเธชเธ”เธตเธเนเธฐ',
    language: 'th',
    durationSeconds: 60,
    segments: [{ text: 'เธชเธงเธฑเธชเธ”เธตเธเนเธฐ', start: 0, end: 1 }],
    words: [{ word: 'เธชเธงเธฑเธชเธ”เธตเธเนเธฐ', start: 0, end: 1 }],
    model: 'test-whisper'
  }));
  const app = createApp({
    transcriptionProvider: { transcribe },
    videoStorage: { ...createMockVideoStorage(), deleteVideo }
  });

  await request(app)
    .post('/ai-edits/prepare')
    .set('x-postdee-subscription-plan', 'PRO')
    .send({ audioS3Key, durationSeconds: 60, capabilities: { silence: true } })
    .expect(200);

  expect(transcribe).toHaveBeenCalledWith({ mediaS3Key: audioS3Key, mediaKind: 'audio' });
  expect(deleteVideo).toHaveBeenCalledWith(audioS3Key);
});
```

Also test both keys (`400 AI_EDIT_MEDIA_AMBIGUOUS`), neither key, foreign key, non-M4A audio key, quota rejection cleanup, provider failure cleanup, legacy video success without deletion, and duplicate cleanup success.

- [ ] **Step 2: Run route tests and verify RED**

```powershell
cd apps/api
npm.cmd run test -- src/modules/aiEdits/aiEditRoutes.test.ts
```

Expected: FAIL because routes require `videoS3Key` and have no audio cleanup dependency/endpoint.

- [ ] **Step 3: Implement one media parser shared by transcribe/prepare**

Use a discriminated internal result:

```ts
type AiEditMedia =
  | { key: string; kind: 'audio'; deleteAfterUse: true }
  | { key: string; kind: 'legacy-video'; deleteAfterUse: false };
```

The parser must:

1. reject both/missing keys;
2. require `.m4a` for `audioS3Key`;
3. verify ownership before provider call or deletion;
4. never mark legacy video for deletion.

Pass `videoStorage.deleteVideo` into `registerAiEditRoutes`. Wrap only owned audio request processing in `try/finally`; log cleanup failure without changing a successful response.

- [ ] **Step 4: Implement the authenticated cleanup endpoint**

`POST /ai-edits/audio/cleanup` validates authentication, `.m4a`, and ownership, calls the idempotent storage delete, and returns `{ status: 'ok' }`. Return the same `MEDIA_KEY_FORBIDDEN` contract for cross-user keys.

- [ ] **Step 5: Verify GREEN and API compatibility**

Run AI edit route tests plus API build. Expected: new audio cases and every legacy recipe/quota/plan test PASS.

### Task 4: Mobile Analysis Strategy and FFmpeg M4A Artifact

**Files:**
- Create: `apps/mobile/lib/features/ai_editing/ai_edit_media_strategy.dart`
- Create: `apps/mobile/test/ai_edit_media_strategy_test.dart`
- Create: `apps/mobile/lib/features/ai_editing/ai_edit_audio_extractor.dart`
- Create: `apps/mobile/test/ai_edit_audio_extractor_test.dart`

**Interfaces:**
- Produces: `enum AiEditAnalysisMode { audioOnly }`
- Produces: `selectAiEditAnalysisMode(Map<String, bool>)`
- Produces: `AiEditAudioArtifact(file, cleanup)`
- Produces: injectable `AiEditAudioExtractor`

- [ ] **Step 1: Write failing strategy tests**

```dart
test('current production capabilities select audio only', () {
  expect(selectAiEditAnalysisMode({
    'subtitle': true,
    'silence': true,
    'filler': true,
    'color': true,
    'zoom': false,
  }), AiEditAnalysisMode.audioOnly);
});

test('an enabled visual capability fails closed', () {
  expect(
    () => selectAiEditAnalysisMode({'subtitle': true, 'zoom': true}),
    throwsA(isA<UnsupportedAiEditAnalysisException>()),
  );
});
```

- [ ] **Step 2: Verify strategy tests fail, then implement minimal selector**

Only enabled keys matter. The safe set is exactly `subtitle`, `silence`, `filler`, and `color`; an enabled unknown key throws.

- [ ] **Step 3: Write failing extractor tests around injected runners/probes**

Test the argument list includes:

```dart
['-y', '-i', source.path, '-vn', '-ac', '1', '-ar', '16000',
 '-c:a', 'aac', '-b:a', '64k', output.path]
```

Test successful non-empty artifact, missing source, no audio stream, FFmpeg non-zero return, empty output, and idempotent cleanup.

- [ ] **Step 4: Run focused Flutter tests and verify RED**

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat test test/ai_edit_media_strategy_test.dart test/ai_edit_audio_extractor_test.dart
```

Expected: FAIL because the files/types do not exist.

- [ ] **Step 5: Implement extractor without a new dependency**

Use the existing `ffmpeg_kit_flutter_new_video` package. Build arguments as a list, create a unique `Directory.systemTemp` directory, verify success and a non-empty `.m4a`, and expose a bounded idempotent cleanup method. Throw a dedicated exception with Thai-friendly categories rather than leaking FFmpeg output.

- [ ] **Step 6: Verify GREEN**

Run the focused tests. Expected: PASS without invoking a native FFmpeg session in unit tests because runner/probe functions are injected.

### Task 5: Mobile API Contract and Existing Screen Integration

**Files:**
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `apps/mobile/test/postdee_api_client_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 strategy/extractor
- Produces: `CreateUploadRequest.purpose`
- Produces: `AiEditPrepareRequest.audioS3Key` and legacy `videoS3Key`
- Produces: `cleanupAiEditAudio(String audioS3Key)`
- Adds injectable screen dependencies for extraction and remote cleanup

- [ ] **Step 1: Add failing serialization tests**

Assert the new client produces:

```dart
expect(CreateUploadRequest(
  fileName: 'postdee-ai-edit.m4a',
  contentType: 'audio/mp4',
  sizeBytes: 1024,
  purpose: 'ai-edit-audio',
).toJson()['purpose'], 'ai-edit-audio');

final requestJson = AiEditPrepareRequest(
  audioS3Key: 'uploads/u/id/clip.m4a',
  durationSeconds: 60,
).toJson();
expect(requestJson, containsPair('audioS3Key', 'uploads/u/id/clip.m4a'));
expect(requestJson.containsKey('videoS3Key'), isFalse);
```

Keep a legacy constructor/test that serializes only `videoS3Key`. Constructor assertions require exactly one key.

- [ ] **Step 2: Verify API-client tests RED, implement, then verify GREEN**

Add `purpose` only when non-null and add `cleanupAiEditAudio` posting to `/ai-edits/audio/cleanup`.

- [ ] **Step 3: Add failing screen tests before changing `_processVideo`**

Update the existing happy path to inject an audio extractor and assert:

- selected source is passed to extractor;
- upload metadata is `.m4a`, `audio/mp4`, purpose `ai-edit-audio`, with no dimensions;
- uploaded file is the extracted artifact, not the original video;
- prepare request contains audio key only;
- renderer still receives the original source file;
- local and remote cleanup are attempted.

Add separate tests for no-audio, extraction failure, upload failure, prepare failure, cached recipe retry, changed setup, widget disposal, and cleanup failure. No-audio/extraction/upload failures must not call prepare.

- [ ] **Step 4: Run the focused screen test and verify RED**

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat test test/ai_editing_screen_test.dart
```

Expected: FAIL because the screen still uploads the original MP4 and builds `videoS3Key` requests.

- [ ] **Step 5: Implement the minimal screen integration**

Before extraction, compute a stable recipe-cache signature from selected video identity plus style/prompt/capabilities/settings, excluding the temporary storage key. On cache miss:

1. select analysis mode;
2. extract M4A;
3. upload it with audio purpose;
4. call prepare with `audioS3Key`;
5. cache the recipe under the stable signature;
6. best-effort remote cleanup and guaranteed local cleanup in `finally`.

On cache hit, skip extraction/upload/provider work and re-render locally. Remove AI-screen reliance on `_uploadedVideo`; do not remove uploader-screen video upload behavior.

- [ ] **Step 6: Verify GREEN and screen regressions**

Run `ai_editing_screen_test.dart` and `postdee_api_client_test.dart`. Expected: every existing review, automatic preview, quota, capability honesty, retry, and render test PASS.

### Task 6: Documentation, Full Verification, and Production Evidence

**Files:**
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md`
- Modify: `docs/GO_LIVE.md`
- Modify: `docs/STAGING_CHECKLIST.md`

**Interfaces:** none; this task records implemented truth only.

- [ ] **Step 1: Update docs after behavior is verified**

Document `purpose=ai-edit-audio`, `audioS3Key`, compatibility behavior, cleanup endpoint, 25 MiB limit, no-audio quota rule, and that the 360p visual proxy remains unimplemented.

- [ ] **Step 2: Run complete backend verification**

```powershell
cd apps/api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

Expected: all commands exit 0.

- [ ] **Step 3: Run complete mobile verification**

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

Expected: analyzer has no issues and all Flutter tests pass.

- [ ] **Step 4: Perform real-device/Staging evidence before production claim**

Use one Android `.mp4`, one iPhone `.mov` when available, one clip with no audio, and one noisy Thai speech clip. Confirm R2 receives only M4A for analysis, Groq timestamps return, temporary audio disappears, the original file is used for final rendering, and no-audio does not change quota. Record evidence in the staging checklist; do not claim this step passed without the devices/credentials.

- [ ] **Step 5: Review scoped diffs without staging unrelated work**

Run `git diff --check` and inspect every touched hunk. Because overlapping files were already modified, do not use whole-file staging or create an implementation commit until the user's pre-existing changes and these feature hunks can be separated safely.

## Plan Self-Review Result

- Every approved spec requirement maps to a task.
- Public and internal media key names are consistent across backend/mobile tasks.
- Legacy video compatibility and non-deletion are tested explicitly.
- Cleanup covers success, rejection, provider failure, lost response, and local artifacts.
- The plan does not implement visual analysis or silently fall back to full-video upload.
- Production readiness still requires real-device and real-provider evidence after automated verification.
