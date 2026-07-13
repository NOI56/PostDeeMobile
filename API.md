# API.md

PostDee backend API reference.

This document describes the current Express + TypeScript scaffold in `apps/api`. It is written for local development and integration planning. Production integrations for social publishing, live analytics, Cloudflare R2, real-clip AI captioning, Pro Groq Whisper auto editing, Firebase, Apple App Store, and Google Play still require real credentials and provider-level testing.

## Base URL

Local default:

```text
http://localhost:4000
```

Backend path:

```text
apps/api
```

## Current Status

The backend currently supports safe scaffold flows for:

- Health checks
- Mock or Firebase authentication
- Upload metadata validation and mock/R2/S3 signed upload plus signed read access scaffolding
- Post creation and queue handoff
- Caption generation through mock, Gemini, or legacy OpenAI providers. The
  product direction is real-clip captioning after a video is selected. Remote
  providers retry transient failures (e.g. a Gemini 503) with backoff and Gemini
  also falls back to a secondary model before `POST /captions/generate` degrades
  to the local template caption.
- Real-clip caption scaffold at `POST /captions/generate-from-clip`, with
  Starter/Pro mode selection, authenticated media-key ownership checks,
  optional temporary AI media cleanup, and monthly quota reservation through
  memory or Prisma-backed usage storage.
- Saved templates
- Pro-only analytics summary
- Store subscription verification scaffold for Apple App Store and Google Play
- Store server notification routes for renewal, cancel, refund, and grace-period handoff

The backend must not publish to TikTok, YouTube Shorts, Instagram Reels, or Facebook Reels through shared PostPeer account ids in production (startup rejects them). Production publishing resolves per-user social connections, and real PostPeer publishing should only be enabled after the per-user connect/refresh flow is verified with a connected test account and a controlled provider test is approved.

## Authentication

### Mock Auth

Default local mode:

```env
AUTH_PROVIDER="mock"
MOCK_USER_ID="local-dev-user"
```

`AUTH_PROVIDER=mock` is rejected at startup when `NODE_ENV=production`.

Development headers:

| Header | Purpose |
| --- | --- |
| `x-postdee-user-id` | Override the mock user id |
| `x-postdee-email` | Optional mock email |
| `x-postdee-display-name` | Optional mock display name |
| `x-postdee-subscription-plan` | Simulate `BASIC`, `STARTER`, or `PRO` in memory mode |
| `x-postdee-phone-verified` | Use `true` to simulate phone verification |
| `x-postdee-phone-number` | Optional mock phone number |

### Firebase Auth

Production direction:

```env
AUTH_PROVIDER="firebase"
FIREBASE_PROJECT_ID="your-firebase-project-id"
```

Authenticated requests must include:

```http
Authorization: Bearer <firebase-id-token>
```

The backend reads `phone_number` from the verified Firebase ID token and treats it as phone verification for the Basic free quota.

## Plans And Entitlements

| Feature | Basic | Starter | Pro |
| --- | --- | --- | --- |
| Price | Free | 199 THB/month | 299 THB/month |
| Phone verification | Required for free quota | Not required for quota | Not required for quota |
| Monthly post units | 3 after phone verification | 120 | 250 |
| Real-time posting | Yes | Yes | Yes |
| Cloud scheduling | No | Yes | Yes |
| Calendar for scheduled posts | No | Yes | Yes |
| AI caption from real clip | No | Audio-only, 50 generations/month scaffolded | Audio + selected frames, 120 generations/month scaffolded |
| AI auto editing with Groq Whisper | No | No | 200 minutes/month scaffolded |
| AI audio review as a separate feature | No | No | No |
| Unified Analytics | No | No | Yes |
| Hashtag radar and AI comment center | No | No | Yes |
| Team and editor access | No | No | Yes |

Important rules:

- Basic users must verify a phone number before using the 3-post free quota.
- Basic users can only post in real time.
- Post units count by platform. One video posted to four platforms uses four
  units.
- Starter users can post immediately, schedule posts, use the calendar, and use
  real-clip AI captioning from audio after a selected clip.
- Pro users unlock analytics, hashtag radar, AI comment center, team/editor
  access, visual-frame AI captioning, and Groq Whisper auto editing scaffolds.
- Prompt-only caption generation may still exist in the API while the app
  transitions, but it should not be the main paid package promise.
- Secret provider keys must stay on the backend, never inside the Flutter app.

## Standard Error Shape

Most errors follow this format:

```json
{
  "status": "error",
  "code": "PAID_PLAN_REQUIRED",
  "message": "Cloud Scheduling requires the Starter or Pro plan"
}
```

Some validation errors include only `status` and `message`.

## Endpoints

### `GET /health`

Checks whether the API process is running.

Response:

```json
{
  "status": "ok",
  "service": "postdee-api"
}
```

### `GET /auth/me`

Returns the current authenticated user.

Response:

```json
{
  "status": "ok",
  "user": {
    "id": "local-dev-user",
    "provider": "mock",
    "email": "seller@example.com",
    "displayName": "PostDee Seller",
    "phoneVerified": true
  }
}
```

## Uploads

### `POST /uploads`

Creates an upload record and, when using R2 or S3, returns a signed `PUT` upload URL.
Requires authentication. Upload URLs are created for the current authenticated
user's flow; unauthenticated Firebase-mode requests return `401`.

Request:

```json
{
  "fileName": "demo-video.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 12345678,
  "width": 1080,
  "height": 1920
}
```

Validation:

- `fileName` is required.
- `contentType` must start with `video/` or `image/`.
- `sizeBytes` must be positive and no larger than `UPLOAD_MAX_SIZE_BYTES` (default `524288000`, or 500 MiB).
- If `width` and `height` are provided, the media must be vertical 9:16 within a 2 percent tolerance.

Mock response:

```json
{
  "status": "ok",
  "upload": {
    "id": "upload-id",
    "fileName": "demo-video.mp4",
    "contentType": "video/mp4",
    "sizeBytes": 12345678,
    "width": 1080,
    "height": 1920,
    "aspectRatio": "9:16",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "storageProvider": "mock-s3",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

R2 or S3 response may also include:

```json
{
  "uploadUrl": "https://signed-upload-url.example",
  "uploadMethod": "PUT",
  "uploadHeaders": {
    "Content-Type": "video/mp4"
  },
  "uploadExpiresAt": "2026-06-05T08:15:00.000Z"
}
```

The bundled R2 signed `PUT` URL signs `Content-Type` and `Content-Length` so the uploaded object must match the declared metadata. Clients should upload the same file whose byte length was sent as `sizeBytes`.

## Posts

Supported platform values:

```text
TIKTOK
YOUTUBE_SHORTS
INSTAGRAM_REELS
FACEBOOK_REELS
```

### `GET /posts`

Returns posts for the authenticated user.

Response:

```json
{
  "status": "ok",
  "posts": []
}
```

### `POST /posts`

Creates a queued post and hands it to the publish queue.

Request:

```json
{
  "caption": "Try this product today. #PostDee",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "scheduledAt": "2026-06-06T10:00:00.000Z"
}
```

Rules:

- `caption`, `videoS3Key`, and at least one valid platform are required.
- `videoS3Key` must be an upload key owned by the authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape returned by `POST /uploads`.
- If `scheduledAt` is present, the user must be Starter or Pro.
- Basic users must have a verified phone number before using the free quota.
- Basic is limited to 3 post units per month after phone verification.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Post units count selected platforms, not post rows.

Worker behavior:

- The publish worker claims a post by moving it from `QUEUED` to `PUBLISHING`
  before calling the platform publisher.
- Retry or duplicate jobs are skipped when the post is already `PUBLISHING`,
  `PUBLISHED`, `PARTIAL_PUBLISHED`, or `FAILED`.
- Stale scheduled jobs are skipped when the job `runAt` no longer matches the
  post's current `scheduledAt`, such as after a reschedule.
- Optional R2/S3 cleanup after a fully successful publish is best-effort. A
  cleanup failure is returned in the worker result, but the post stays
  `PUBLISHED`.
- If the publish queue is unavailable while creating or rescheduling a post,
  the API returns `503` with `PUBLISH_QUEUE_UNAVAILABLE` and keeps the post
  store from advancing ahead of the queue.

Local-only request override:

```json
{
  "subscriptionPlan": "PRO"
}
```

This override is accepted only in local mock development. In `NODE_ENV=production`,
the backend rejects request-body plan overrides with
`SUBSCRIPTION_PLAN_OVERRIDE_DISABLED`.

Production should use the subscription store, not request-body overrides.

Success response:

```json
{
  "status": "ok",
  "post": {
    "id": "post-id",
    "userId": "local-dev-user",
    "caption": "Try this product today. #PostDee",
    "videoS3Key": "uploads/upload-id/demo-video.mp4",
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "scheduledAt": "2026-06-06T10:00:00.000Z",
    "status": "QUEUED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  },
  "publishJob": {
    "id": "job-id",
    "queueName": "publish-posts",
    "postId": "post-id",
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "runAt": "2026-06-06T10:00:00.000Z",
    "status": "SCHEDULED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

Basic user without phone verification:

```json
{
  "status": "error",
  "code": "PHONE_VERIFICATION_REQUIRED",
  "message": "Phone verification is required to use the Basic free post quota"
}
```

Post limit reached:

```json
{
  "status": "error",
  "code": "POST_LIMIT_REACHED",
  "message": "Basic plan is limited to 3 posts per month"
}
```

## Account

### `GET /account/deletion-readiness`

Checks that Firebase identity deletion, owner-prefix media cleanup, and any
stored PostPeer profile cleanup are configured before the mobile app starts
Apple reauthentication. Returns
`{ "status": "ok", "identityAlreadyDeleted": false }` or a retryable `503`
without changing account data. `identityAlreadyDeleted=true` lets the mobile
app finish an idempotent retry without repeating Apple reauthentication.
If a stored PostPeer profile exists but provider cleanup is not configured,
the endpoint returns `503 ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE`.

### `DELETE /account`

Permanently deletes the authenticated user's account, owned upload objects,
Firebase identity, and user-scoped application data. This backs the App Store /
Google Play required "Delete Account" flow in the profile screen.

Behavior:

- Cancels any queued or scheduled publish jobs for the user's posts first.
- Lists every paginated integration in the user's PostPeer profile and
  disconnects each one through the provider before deleting local records.
  This includes integration ids for platforms PostDee does not yet recognize.
  Provider cleanup failure returns `503 ACCOUNT_SOCIAL_CLEANUP_FAILED` so the
  request can retry without losing local account data.
- Deletes every object under the exact owner prefix
  `uploads/<encoded-firebase-uid>/` before deleting database records. A storage
  cleanup failure returns `503 ACCOUNT_MEDIA_CLEANUP_FAILED`, leaving the
  account records available for retry. Cleanup attempts every listed object;
  because external object deletion is not transactional, some objects may
  already be gone when a retryable error is returned.
- With Prisma stores, deletes the `User` row; `onDelete: Cascade` removes every
  related row in one step.
- With in-memory stores, each store drops the user's records.
- When Firebase auth is used, `FIREBASE_AUTH_DELETE_ENABLED=true` and
  `FIREBASE_SERVICE_ACCOUNT_JSON` are required. Firebase identity is deleted
  last. Active identities must present an ID token whose `auth_time` is no more
  than five minutes old or receive `403 ACCOUNT_REAUTHENTICATION_REQUIRED`.
- `auth/user-not-found` is treated as an idempotent success. Other Firebase
  failures return `503 ACCOUNT_IDENTITY_DELETE_FAILED`; retrying the same
  request completes identity deletion after the already-idempotent data cleanup.
  The account-only verifier accepts a still-valid signed token when (and only
  when) Firebase Admin confirms that the UID is already missing; revoked tokens
  remain rejected.
- If Firebase identity deletion is not enabled, the endpoint returns
  `503 ACCOUNT_DELETION_UNAVAILABLE` before changing any data.
- On iOS/macOS, the mobile flow calls the readiness endpoint, reauthenticates
  Apple-linked users, and calls Firebase `revokeTokenWithAuthorizationCode`
  before deletion. Apple Sign-In must remain unavailable on Android/web until a
  server-side Apple token revocation flow is implemented there.
- Late active RevenueCat webhooks are acknowledged and ignored when the
  PostDee user row no longer exists, so a renewal cannot recreate a deleted
  account.

Success response:

```json
{
  "status": "ok"
}
```

## Captions

### `POST /captions/generate`

Generates a Thai affiliate-style caption from 1 or 2 keywords.

Requires Starter or Pro. Each keyword must be 80 characters or fewer. Successful
generations reserve one monthly AI caption generation from the Starter/Pro
quota; quota exhaustion returns `429` with code `AI_CAPTION_QUOTA_REACHED`.

Current note: this endpoint is still the legacy prompt/keyword caption
scaffold. New UI should prefer `POST /captions/generate-from-clip` after a
clip is selected. Optional user text should become extra guidance after clip
selection, not the main sold workflow.

Request:

```json
{
  "keywords": ["skincare", "sensitive skin"]
}
```

Response:

```json
{
  "status": "ok",
  "caption": "Generated caption text",
  "hashtags": ["#PostDee", "#Affiliate"],
  "affiliateLinkPlaceholder": "[Affiliate link placeholder]",
  "model": "gemini-2.5-flash-lite",
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49
  }
}
```

Current providers:

```env
CAPTION_PROVIDER="mock"
CAPTION_PROVIDER="gemini"
CAPTION_PROVIDER="openai"
```

Gemini production direction:

```env
CAPTION_PROVIDER="gemini"
GEMINI_API_KEY="..."
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
```

### `POST /captions/generate-from-clip`

Generates a mock-safe AI caption package from a selected clip key.

Requires Starter or Pro.

- Starter uses `AUDIO_ONLY` mode and is limited to 50 generations/month.
- Pro uses `AUDIO_WITH_FRAMES` mode and is limited to 120 generations/month.
- Each successful generate/change request counts as one generation.
- Local development can keep quota usage in memory with
  `CAPTION_USAGE_STORE=memory`. Production should use
  `CAPTION_USAGE_STORE=prisma` so monthly usage survives API restarts.
- It uses `videoS3Key`, optional `guidance`, optional `selectedFrameKeys`, and
  optional `deleteAfterUse`.
- `videoS3Key` and any `selectedFrameKeys` must be upload keys owned by the
  authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape
  returned by `POST /uploads`.
- When the mobile app uploads media only for AI captioning, it sends
  `"deleteAfterUse": true`; the backend then attempts to delete the clip and
  selected frames after the request. Cleanup failures are logged but do not
  block a successful caption response.
- Usage is reserved before the AI provider is called so simultaneous requests
  cannot exceed the monthly quota within the configured usage store.
- Media downloaded for AI processing is capped to protect API memory.
- When `CAPTION_PROVIDER=gemini`, this endpoint sends the clip to Gemini to
  listen and write the caption directly (Starter = audio only; Pro =
  `AUDIO_WITH_FRAMES`, also sending the `selectedFrameKeys` images). Gemini
  retries transient failures and falls back to a secondary model, then to the
  local template caption if it still fails, so a caption is always returned.
- When no Gemini provider is configured, it falls back to the legacy path: the
  configured `TRANSCRIPTION_PROVIDER` (e.g. Groq Whisper) transcribes the clip
  and a local template builds the caption.
- Note: Groq Whisper is otherwise reserved for the auto-editing/subtitle flow
  (which needs accurate timestamps); the caption path prefers Gemini.
- Frame sampling itself (extracting `selectedFrameKeys` from the video) is done
  by the mobile app via FFmpeg, which uploads the frames as images before
  calling this endpoint. Pending real-device verification.
- The active customer flow should not require manual language or market
  selection. Spoken language is inferred from the clip, while `guidance`
  remains the simple override path when a seller wants a specific language,
  market, or style.

Request:

```json
{
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "guidance": "focus on the opening hook",
  "selectedFrameKeys": [
    "uploads/local-dev-user/frame-upload-1/demo-1.jpg",
    "uploads/local-dev-user/frame-upload-2/demo-2.jpg"
  ],
  "deleteAfterUse": true
}
```

Starter response example:

```json
{
  "status": "ok",
  "model": "local-real-clip-template",
  "caption": "Caption option A",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"],
  "hooks": ["Hook A", "Hook B", "Hook C"],
  "hashtags": ["#PostDee", "#ShortVideo"],
  "seoKeywords": ["short video", "affiliate seller"],
  "searchTitle": "Best moments from demo-video.mp4",
  "context": {
    "selectedCaptionLanguage": "Thai",
    "selectedTargetMarket": "Thailand",
    "selectedTone": "auto",
    "detectedSpokenLanguage": "th",
    "suggestedCaptionLanguage": "Thai",
    "suggestedTargetMarket": "Thailand"
  },
  "source": {
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "mode": "AUDIO_ONLY",
    "selectedFrameCount": 0
  },
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49
  }
}
```

Quota reached:

```json
{
  "status": "error",
  "code": "AI_CAPTION_QUOTA_REACHED",
  "message": "Starter is limited to 50 real-clip AI caption generations per month",
  "quota": {
    "limit": 50,
    "usedThisMonth": 50,
    "remainingThisMonth": 0
  }
}
```

Production direction:

The paid caption flow should return SEO fields in the same AI call where
possible:

```json
{
  "seoKeywords": ["keyword 1", "keyword 2", "keyword 3"],
  "searchTitle": "Search-friendly short video title",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"]
}
```

These SEO fields are returned by the new mock-safe real-clip scaffold, but the
AI provider still needs real clip audio/frame inputs before production launch.

## Removed Legacy AI Clip Review Endpoint

`POST /clip-reviews` is no longer mounted in the app.

Reason:

- It overlapped with AI caption from the real clip.
- It exposed confusing package flags such as AI audio review and AI video review.
- The current product plan sells real-clip captioning and future Pro Groq Whisper
  auto editing instead.

Current behavior:

- Requests to `/clip-reviews` return `404`.
- `canUseAiAudioReview` and `canUseAiVideoReview` are kept as compatibility
  fields in subscription responses, but they are always `false`.
- The old route, UI, config, and internal mock/provider files have been
  removed.

Future SEO direction: Starter real-clip captioning should be based on audio
understanding. Pro real-clip captioning should combine audio and selected visual
frames where useful.

## AI Auto Editing

All `/ai-edits/*` endpoints require auth. `POST /ai-edits/transcribe`,
`POST /ai-edits/prepare`, and `POST /ai-edits/plan` require the `PRO` plan
(otherwise `402` with `code: "PRO_REQUIRED"`); `GET /ai-edits/quota` is
available to any authenticated user.

### `POST /ai-edits/transcribe`

Transcribes an uploaded clip (Thai). Meters usage against a monthly minute quota
(`200` min); returns `402` `AI_EDIT_QUOTA_EXCEEDED` when exhausted. The client
`durationSeconds` is only a pre-check estimate; the backend reserves the actual
transcribed minutes before returning success so concurrent requests cannot push
usage past the configured store limit. Request:
`{ "videoS3Key": "uploads/<user-id>/<upload-id>/clip.mp4", "durationSeconds": 18 }`. Response includes
`transcript` (text, language, durationSeconds, segments[], words[]) and `quota`.
The Groq adapter requests both `word` and `segment` timestamp granularities;
omitting segment timestamps would prevent subtitle timing and silence-gap cuts.

### `GET /ai-edits/quota`

Reports `{ limitMinutes, usedMinutes, remainingMinutes }` for the current month.

### `POST /ai-edits/prepare`

Builds the UI-facing mobile render recipe for the AI editing screen. This is the
backend contract for the Claude Design flow: the app sends the selected clip,
chosen style/prompt, and capability toggles such as `subtitle`, `silence`,
`filler`, `hook`, `zoom`, `color`, `cta`, `pricetag`, and `watermark`.

This endpoint is Pro-gated and minute-metered like `/ai-edits/transcribe`: the
client `durationSeconds` is a pre-check estimate, the backend transcribes the
stored clip, then reserves the actual transcribed minutes before returning the
recipe. It does **not** render video on the server; mobile still renders/export
with FFmpeg.

Request:

```json
{
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "durationSeconds": 65,
  "styleId": "flash_sale",
  "prompt": "เหลือ 45 วิ เน้นตอนพูดราคา",
  "capabilities": {
    "subtitle": true,
    "silence": true,
    "filler": true,
    "hook": false,
    "beatsync": false,
    "reframe": true,
    "zoom": true,
    "color": true,
    "sfx": true,
    "audio": true,
    "translate": true,
    "pricetag": true,
    "cta": true,
    "watermark": true
  },
  "settings": {
    "silencePreset": "balanced",
    "fillerWords": ["เอ่อ", "อ่า", "แบบว่า", "คือว่า", "ประมาณว่า"],
    "ctaText": "กดตะกร้าเลย",
    "priceText": "99 บาท",
    "watermarkText": "Meena Shop",
    "toneFilter": "warm",
    "zoomLevel": "medium",
    "music": {
      "source": "original",
      "beatIntensity": "balanced",
      "volume": 0.25,
      "ducking": {
        "enabled": true,
        "musicVolumeDuringSpeech": 0.12
      }
    }
  }
}
```

Response includes:

- `recipe.renderMode: "mobile-ffmpeg"`
- `recipe.transcript` with text, language, duration, segments, words, and model
- `recipe.subtitles` for mobile subtitle burn-in
- `recipe.cutRanges`, `silenceRanges`, and `fillerRanges`
- `recipe.overlays` for CTA, price tag, and watermark hints
- `recipe.renderHints` for tone and zoom settings. Hook removal is not emitted
  by the current recipe builder yet.
- `recipe.music` with the validated source (`auto`, `library`, `device`, or
  `original`), optional genre/library track reference, beat intensity, volume,
  and voice-ducking preferences
- `recipe.capabilities`, where each requested UI capability is marked
  `applied`, `hinted`, `planned`, or `skipped`
- `quota` with `{ limitMinutes, usedMinutes, remainingMinutes }`

Capabilities that need future audio/visual analysis, such as beat sync,
the opening hook/highlight, auto-reframe, SFX/music choice, audio cleanup, and subtitle translation, are
accepted in the recipe but marked `planned` so the UI can stay honest.

`settings.silencePreset` accepts three values and changes the minimum gap
between transcript segments that becomes a silence range:

- `natural`: 1.0 second
- `balanced`: 0.6 second (also used when the field is missing or invalid)
- `compact`: 0.4 second

`settings.fillerWords` is an exact allowlist. Supported values are `เอ่อ`,
`อ่า`, `แบบว่า`, `คือว่า`, and `ประมาณว่า`. The backend normalizes NFC and
removes surrounding whitespace, punctuation, and symbols before comparing a
transcript word; it never uses a substring match. Omitting the field preserves
legacy behavior and checks all five words. Sending `[]`, a non-array value, or
an array that sanitizes to no supported values fails closed and produces no
filler ranges; it does not fall back to the legacy list.

Production mobile builds send `hook: false` because
`ENABLE_EXPERIMENTAL_AI_HOOK` defaults to `false`. If an internal or legacy
client sends `hook: true`, the response still marks it `planned`, emits no hook
render hint, and mobile does not reorder the first three seconds. The compile-time
flag exposes setup UI only; it does not enable a renderer.

`settings.music` is additive and optional. Requests that omit it default to
`source: "original"`. A library track is referenced only by an opaque `trackId`.
The current API validates and passes this reference through; a production
catalog resolver with ownership/licensing checks is still required before a
library track can be rendered.
Clients must never send a storage key or absolute device file path to this API.
Receiving music settings does not mean the current renderer has mixed music or
cut on detected beats.

The response is an editable review recipe, not a final server-rendered video.
Mobile may disable recipe capabilities and re-render locally from the original
clip before the user accepts the result. That review loop must reuse the
successful recipe instead of calling this minute-metered endpoint again.
Capabilities marked `planned`, `hinted`, or `skipped` must not be presented as
already applied to the preview.

Mobile derives the review's detected counts from `silenceRanges.length` and
`fillerRanges.length`, then merges overlapping/clamped ranges before displaying
the detected time.
That summary describes pre-render detections and must not be presented as the
exact duration removed from the exported clip.

### `POST /ai-edits/plan`

Returns a structured cut plan for an auto-edit style or a free-form prompt,
computed from an already-transcribed clip. Pro-gated but **not** minute-metered.

Currently backed by a rule-based mock (`model: "mock-rule"`); the contract is
designed so an LLM planner can replace the brain without changing callers.

Request (one of `styleId` or `prompt` is required):

```json
{
  "styleId": "flash_sale",
  "prompt": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธเธญเธญเธเนเธฅเนเธงเน€เธซเธฅเธทเธญ 15 เธงเธด",
  "durationSeconds": 30,
  "segments": [{ "text": "เธฃเธฒเธเธฒ 99 เธเธฒเธ—", "start": 3, "end": 6 }]
}
```

- `styleId` โ€” a mobile edit-style id (e.g. `flash_sale`, `qa`, `before_after`,
  `tutorial`, `comedy`); keeps keyword-relevant segments, cuts the rest.
- `prompt` โ€” free-form Thai instruction. The mock understands a target length
  ("เน€เธซเธฅเธทเธญ 45 เธงเธด") and profanity removal ("เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ").

Response:

```json
{
  "status": "ok",
  "plan": {
    "cuts": [{ "start": 10, "end": 12 }, { "start": 17, "end": 30 }],
    "summary": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ ยท เธขเนเธญเน€เธซเธฅเธทเธญ ~15 เธงเธด",
    "model": "mock-rule"
  }
}
```

`cuts` are absolute-second ranges to remove; the client feeds them into the same
on-device render pipeline used by silence/segment cuts. Returns `400` when
`durationSeconds` is missing or neither `styleId` nor `prompt` is provided.

## Templates

### `GET /templates`

Returns saved text templates for the authenticated user.

Response:

```json
{
  "status": "ok",
  "templates": []
}
```

### `POST /templates`

Creates a saved text template for the authenticated user.

Request:

```json
{
  "title": "Affiliate disclaimer",
  "body": "This post may contain an affiliate link."
}
```

Response:

```json
{
  "status": "ok",
  "template": {
    "id": "template-id",
    "title": "Affiliate disclaimer",
    "body": "This post may contain an affiliate link.",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

## Analytics

### `GET /analytics/summary?range=30d`

Returns a unified analytics summary for the authenticated user.

Requires Pro.

Supported `range` values are `today`, `7d`, `30d`, `90d`, and `year`.
The default is `30d`. Platform publish metrics are filtered by their publish
time (falling back to record creation time) and grouped into UTC date buckets.
The `daily` series therefore attributes the current synchronized totals to the
day each platform publish was created/published; it is not a provider-level
hourly history or a synthetic trend.

Response:

```json
{
  "status": "ok",
  "summary": {
    "range": "30d",
    "totalViews": 0,
    "totalLikes": 0,
    "platforms": [
      {
        "platform": "TIKTOK",
        "label": "TikTok",
        "views": 0,
        "likes": 0
      }
    ],
    "daily": [
      {
        "date": "2026-07-10",
        "views": 0,
        "likes": 0
      }
    ]
  }
}
```

If the user is not Pro:

```json
{
  "status": "error",
  "code": "PRO_REQUIRED",
  "message": "Unified Analytics requires the Pro plan"
}
```

An unsupported range returns `400 INVALID_ANALYTICS_RANGE`.

## Billing And Subscriptions

### `GET /billing/subscription`

Returns the current user's plan and feature flags.

Basic response example:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "BASIC",
    "status": "INACTIVE",
    "monthlyPostLimit": 3,
    "usedPostsThisMonth": 0,
    "remainingPostsThisMonth": 0,
    "phoneVerified": false,
    "requiresPhoneVerification": true,
    "canUseFreePostQuota": false,
    "canSchedule": false,
    "canUseAiCaptions": false,
    "canUseAnalytics": false,
    "canUseAiAudioReview": false,
    "canUseAiVideoReview": false
  }
}
```

After Basic phone verification:

```json
{
  "phoneVerified": true,
  "requiresPhoneVerification": false,
  "canUseFreePostQuota": true,
  "monthlyPostLimit": 3,
  "remainingPostsThisMonth": 3
}
```

Starter response sets:

```json
{
  "plan": "STARTER",
  "status": "ACTIVE",
  "monthlyPostLimit": 120,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 120,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": false,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

Pro response sets:

```json
{
  "plan": "PRO",
  "status": "ACTIVE",
  "monthlyPostLimit": 250,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 250,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": true,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

`canUseAiAudioReview` and `canUseAiVideoReview` are legacy compatibility flags
for older clients, but the active API keeps them false. Package copy should use
"AI caption from real clip" instead.

### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when
`BILLING_PROVIDER=revenuecat`.

This endpoint requires:

```http
Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>
```

RevenueCat `app_user_id` must match the PostDee user id. In production this
should be the Firebase uid used by the mobile app. The backend maps RevenueCat
entitlement ids or product ids to PostDee plans, stores the billing id as
`revenuecat:<app_user_id>`, and keeps `GET /billing/subscription` as the single
app-facing entitlement endpoint.

Example request:

```json
{
  "event": {
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "expiration_at_ms": 1780531200000
  }
}
```

Success response:

```json
{
  "status": "ok",
  "ignored": false,
  "eventType": "INITIAL_PURCHASE",
  "subscription": {
    "userId": "firebase-user-id",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

Supported active event types include `INITIAL_PURCHASE`, `RENEWAL`,
`PRODUCT_CHANGE`, `UNCANCELLATION`, and `NON_RENEWING_PURCHASE`. `EXPIRATION`
cancels the existing RevenueCat-bound subscription and removes paid access.
`CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE` are acknowledged
without revoking access immediately because the subscription can still be active
until the paid period actually expires. Unknown product or entitlement ids return
`202` with `ignored: true`.

### `POST /billing/store/verify`

Legacy direct Apple/Google store verifier. It verifies a mobile store purchase
and activates Starter or Pro when `BILLING_PROVIDER=store` or in local mock
mode. Production should use RevenueCat webhooks instead of this custom verifier.

Default product ids:

```env
STORE_STARTER_MONTHLY_PRODUCT_ID="postdee_starter_monthly"
STORE_PRO_MONTHLY_PRODUCT_ID="postdee_pro_monthly"
```

Android request:

```json
{
  "platform": "ANDROID",
  "productId": "postdee_starter_monthly",
  "purchaseToken": "google-play-purchase-token"
}
```

iOS request:

```json
{
  "platform": "IOS",
  "productId": "postdee_pro_monthly",
  "transactionId": "app-store-transaction-id"
}
```

Response:

```json
{
  "status": "ok",
  "purchase": {
    "provider": "mock-store",
    "platform": "ANDROID",
    "productId": "postdee_starter_monthly",
    "purchaseToken": "google-play-purchase-token",
    "verifiedAt": "2026-06-05T08:00:00.000Z"
  },
  "subscription": {
    "userId": "local-dev-user",
    "plan": "STARTER",
    "status": "ACTIVE"
  }
}
```

The backend stores a provider-neutral billing id:

- Android: `google-play:<purchaseToken>`
- iOS: `apple-app-store:<originalTransactionId>` when available, otherwise `apple-app-store:<transactionId>`

### `POST /billing/mock-success`

Activates Starter or Pro for local scaffold testing.
This endpoint is disabled in `NODE_ENV=production` and when `BILLING_PROVIDER`
is not `mock`.
`BILLING_PROVIDER=mock` is also rejected at startup when `NODE_ENV=production`.

Request:

```json
{
  "plan": "PRO"
}
```

Response:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

This endpoint is for local development only.

## Store Server Notifications

These endpoints support the legacy direct Apple/Google verifier path. The
preferred production billing path is RevenueCat.

### `POST /billing/google-play/notifications`

Receives Google Play Real-time Developer Notifications through a Pub/Sub push payload.

Requires `Authorization: Bearer <GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN>`.

Supported scaffold event types:

- `subscriptionNotification`
- `testNotification`
- `voidedPurchaseNotification`

The scaffold maps clear subscription events to entitlement state only when the purchase token was previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "google-play",
    "eventType": "SUBSCRIPTION_NOTIFICATION",
    "notificationId": "message-id",
    "notificationType": "4",
    "productId": "postdee_pro_monthly",
    "purchaseToken": "purchase-token"
  }
}
```

### `POST /billing/apple/notifications`

Receives App Store Server Notification V2 payloads.

Request:

```json
{
  "signedPayload": "apple-signed-notification-payload"
}
```

The scaffold verifies the signed payload when Apple root certificates and app config are present, extracts transaction ids, and updates subscriptions that were previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "apple-app-store",
    "eventType": "DID_RENEW",
    "notificationId": "notification-uuid",
    "notificationType": "DID_RENEW",
    "subtype": null,
    "transactionId": "transaction-id",
    "originalTransactionId": "original-transaction-id"
  }
}
```

Current notification mapping highlights:

- Apple `DID_RENEW` activates the subscription.
- Apple `EXPIRED` expires the subscription.
- Apple `REFUND` expires the subscription.
- Apple `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD` keeps the subscription active.
- Apple `DID_FAIL_TO_RENEW` without grace period marks the subscription as past due.
- Google Play cancellation, expiration, revocation, and voided purchase events can downgrade or expire known subscriptions.

## Queue

### `GET /queue/jobs`

Returns queued publish jobs for the authenticated user in local memory mode.
Canceling or rescheduling a queued post also removes or replaces the matching
publish queue job.

Response:

```json
{
  "status": "ok",
  "jobs": []
}
```

Production direction:

```env
PUBLISH_QUEUE="bullmq"
POST_STORE="prisma"
DATABASE_URL="postgresql://..."
REDIS_URL="redis://localhost:6379"
```

`PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` because
the API and worker run in separate processes and must share post state through
PostgreSQL.

## Environment Variables

| Variable | Example | Purpose |
| --- | --- | --- |
| `NODE_ENV` | `production` | Runtime environment; production disables local mock shortcuts |
| `PORT` | `4000` | API port |
| `DATABASE_URL` | `postgresql://...` | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis connection string for BullMQ |
| `AUTH_PROVIDER` | `mock`, `firebase` | Auth adapter |
| `FIREBASE_PROJECT_ID` | `postdee-prod` | Firebase project id |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `{...}` | Firebase Admin service account JSON for account deletion and revoked-token checks; keep secret |
| `FIREBASE_AUTH_DELETE_ENABLED` | `false`, `true` | Enables complete Firebase account deletion and revoked/deleted-token checks; requires the Firebase service account |
| `VIDEO_STORAGE` | `mock`, `r2`, `s3` | Temporary video storage adapter |
| `CLOUDFLARE_R2_BUCKET` | `postdee-video-temp` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | `...` | Cloudflare account id |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | `...` | R2 S3-compatible access key id |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | `...` | R2 S3-compatible secret access key |
| `CLOUDFLARE_R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` | Optional custom R2 endpoint |
| `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS` | `900` | Signed upload URL lifetime |
| `UPLOAD_MAX_SIZE_BYTES` | `524288000` | Maximum declared upload size accepted by `POST /uploads` |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Per-IP rate limit window in milliseconds |
| `RATE_LIMIT_MAX_REQUESTS` | `300` | Max requests per IP per window; exceeding returns `429` with code `RATE_LIMITED` (`GET /health` is exempt). Tighter fixed per-IP buckets also cover `/auth` (30/10min), `/uploads` (60/hr), `/captions` + `/ai-edits` (60/hr), and `/social-connections` (20/10min) |
| `AWS_REGION` | `ap-southeast-1` | Legacy S3 region |
| `AWS_S3_BUCKET` | `postdee-video-temp` | Legacy S3 bucket |
| `AWS_S3_UPLOAD_EXPIRES_SECONDS` | `900` | Legacy S3 signed upload URL lifetime |
| `CAPTION_PROVIDER` | `mock`, `gemini`, `openai` | Caption provider |
| `GEMINI_API_KEY` | `...` | Gemini API key |
| `GEMINI_CAPTION_MODEL` | `gemini-2.5-flash-lite` | Gemini caption model |
| `OPENAI_API_KEY` | `...` | Legacy OpenAI API key |
| `OPENAI_CAPTION_MODEL` | `gpt-4o-mini` | Legacy OpenAI caption model |
| `TRANSCRIPTION_PROVIDER` | `mock`, `openai`, `groq` | AI caption language detection and AI edit transcription provider |
| `GROQ_API_KEY` | `...` | Groq API key for AI caption detection and AI edit transcription |
| `GROQ_TRANSCRIPTION_MODEL` | `whisper-large-v3` | Groq transcription model |
| `WHISPER_MODEL` | `whisper-1` | Legacy OpenAI transcription model |
| `EDIT_PLAN_PROVIDER` | `mock`, `openai`, `groq` | Brain for `POST /ai-edits/plan`; `mock` is rule-based, the others call an LLM and fall back to mock on failure |
| `OPENAI_EDIT_PLAN_MODEL` | `gpt-4o-mini` | OpenAI chat model for edit planning |
| `GROQ_EDIT_PLAN_MODEL` | `llama-3.3-70b-versatile` | Groq chat model for edit planning |
| `BILLING_PROVIDER` | `mock`, `store`, `revenuecat` | Billing verifier adapter |
| `REVENUECAT_WEBHOOK_AUTH_TOKEN` | `...` | Bearer token required by the RevenueCat webhook endpoint |
| `REVENUECAT_STARTER_ENTITLEMENT_ID` | `starter` | RevenueCat entitlement mapped to Starter |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | `pro` | RevenueCat entitlement mapped to Pro |
| `REVENUECAT_STARTER_PRODUCT_ID` | `postdee_starter_monthly` | RevenueCat product mapped to Starter |
| `REVENUECAT_PRO_PRODUCT_ID` | `postdee_pro_monthly` | RevenueCat product mapped to Pro |
| `STORE_STARTER_MONTHLY_PRODUCT_ID` | `postdee_starter_monthly` | Starter store product id |
| `STORE_PRO_MONTHLY_PRODUCT_ID` | `postdee_pro_monthly` | Pro store product id |
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.postdee` | Android package name |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON` | `{...}` | Google Play verifier service account JSON |
| `GOOGLE_PLAY_ACCESS_TOKEN` | `...` | Optional Google Play access token |
| `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` | `...` | Bearer token required by the Google Play RTDN endpoint |
| `APPLE_APP_BUNDLE_ID` | `com.postdee` | iOS bundle id |
| `APPLE_APP_STORE_ISSUER_ID` | `...` | App Store Server API issuer id |
| `APPLE_APP_STORE_KEY_ID` | `...` | App Store Server API key id |
| `APPLE_APP_STORE_PRIVATE_KEY` | `...` | App Store Server API private key |
| `APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64` | `...` | Root certificates for notification verification |
| `APPLE_APP_APPLE_ID` | `1234567890` | Apple app id |
| `APPLE_APP_STORE_ENVIRONMENT` | `sandbox`, `production` | App Store environment |
| `TEMPLATE_STORE` | `memory`, `prisma` | Template persistence |
| `POST_STORE` | `memory`, `prisma` | Post persistence |
| `SUBSCRIPTION_STORE` | `memory`, `prisma` | Subscription persistence |
| `ANALYTICS_STORE` | `memory`, `prisma` | Analytics persistence |
| `CAPTION_USAGE_STORE` | `memory`, `prisma` | Real-clip AI caption monthly usage persistence |
| `AI_EDIT_USAGE_STORE` | `memory`, `prisma` | AI editing monthly minute usage persistence |
| `PUBLISH_QUEUE` | `memory`, `bullmq` | Publish queue adapter; `bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` |
| `SOCIAL_PUBLISHER` | `mock`, `postpeer` | Social publishing adapter |
| `POSTPEER_API_KEY` | `...` | PostPeer API key for real social publishing |
| `POSTPEER_API_BASE_URL` | `https://api.postpeer.dev` | Optional PostPeer API host override |
| `POSTPEER_TIKTOK_ACCOUNT_ID` | `abc123` | Operator PostPeer TikTok integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_YOUTUBE_ACCOUNT_ID` | `abc123` | Operator PostPeer YouTube Shorts integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_INSTAGRAM_ACCOUNT_ID` | `abc123` | Operator PostPeer Instagram Reels integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_FACEBOOK_ACCOUNT_ID` | `abc123` | Operator PostPeer Facebook Reels integration id used only when no per-user connection resolver is wired; forbidden in production |
| `MOCK_USER_ID` | `local-dev-user` | Default mock user id |

## Production Gaps

The following work is still required before production launch:

- Verify the per-user PostPeer connect/refresh flow with a connected test account before enabling production user publishing; do not use shared `POSTPEER_*_ACCOUNT_ID` values in production.
- Store social access tokens securely only if direct platform APIs replace the
  PostPeer provider later.
- Complete provider-level R2 upload and cleanup testing.
- Test real-clip caption transcription with real R2 videos and Groq before
  production launch; frame sampling is still not implemented.
- Apply and verify the Prisma `RealClipCaptionUsage` migration in production
  before selling paid AI caption quotas.
- Keep legacy AI review compatibility flags false while building real-clip AI
  captioning and Pro Groq Whisper editing.
- Design Pro AI auto editing jobs with Groq Whisper transcription, minute quotas,
  top-up handling, mobile FFmpeg export, retries, and failure handling before
  implementation.
- Complete Firebase Google Sign-In and Phone Auth device testing.
- Complete RevenueCat dashboard setup for real App Store / Google Play products,
  replace the local Test Store SDK key with platform RevenueCat SDK keys, and
  run App Store / Google Play sandbox purchase testing through RevenueCat.
- Add full RevenueCat renewal, cancel, refund, billing-issue, and notification
  replay coverage.
- Replace mock analytics with real platform analytics fetchers.
- Add audit logging and production monitoring (per-IP rate limiting is live via
  `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX_REQUESTS`).
