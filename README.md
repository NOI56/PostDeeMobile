# PostDee

PostDee is a cross-platform mobile app and backend for Thai e-commerce sellers,
affiliate marketers, and creators. The product is Thai-first and has an
8-locale foundation (th, en, vi, zh, id, ms, tl, ja), but many active screens
still contain Thai copy and are not fully localized. The Flutter app supports
light and dark palettes (light is the current default), backed by Express,
Prisma, and provider adapters that remain mock-safe until explicitly enabled.

## Project Structure

```text
apps/
  api/      Node.js, Express, TypeScript, Prisma, PostgreSQL scaffold
  mobile/   Flutter source scaffold for iOS and Android
```

## Deployment Environments

- `render.yaml` จัดการ Production (`postdee-api` และ `postdee-postgres`)
- `render.staging.yaml` เป็น Blueprint แยกสำหรับ Staging แบบต้นทุนต่ำ และต้องใช้
  database, R2 bucket, Firebase project, RevenueCat webhook และ PostPeer account
  ชุดทดสอบเท่านั้น
- ขั้นตอนและข้อจำกัดค่าใช้จ่ายอยู่ใน `docs/STAGING.md` ปัจจุบันสร้างทรัพยากร
  Staging บน Render แล้ว, `/health` ผ่าน และ Android Debug ใช้ Firebase project
  แยกพร้อมผ่าน Google Sign-In → Firebase token → Staging API บน Emulator แล้ว
  RevenueCat Test Store/offering/webhook ตั้งค่าแล้ว และทั้ง purchase กับ true
  Restore/resync E2E ผ่านบน Android Emulator ด้วย Firebase UID หลัง deploy backend
  และตั้ง `REVENUECAT_REST_API_V1_KEY` ใน Render Staging (เป็นราคาทดสอบและไม่มีการ
  เรียกเก็บเงินจริง) ฝั่ง RevenueCat มี Play Store app, Starter/Pro products,
  entitlements, default offering และ production Android public SDK key แล้ว พร้อม
  signed AAB สำหรับอัปโหลด แต่ Play Console app/subscriptions, internal testing,
  service credentials และ Google Play purchase จริงยังทำไม่ได้จนกว่าจะยืนยันสิทธิ์
  ด้วยมือถือ Android จริง; Emulator ใช้ยืนยันขั้นตอนนี้ไม่ได้
- Render Staging ติดตาม branch `main` แล้ว บันทึกการทดสอบเดิมระบุว่าการอัปโหลด
  R2 จากแอปผ่านและเคยตั้ง `GEMINI_API_KEY`/`ELEVENLABS_API_KEY` ชุด Staging
  รอบเดิมที่ส่งวิดีโอ 38 MB ทั้งไฟล์หยุดที่ transcription เพราะเกินขนาดไฟล์ของ
  provider โดยโควตาไม่เปลี่ยน โค้ดปัจจุบันจึงแยกเสียง M4A ขนาดเล็กก่อนอัปโหลด;
  backend ปัจจุบัน deploy แล้ว แต่ยังต้องยืนยัน secret ใน Dashboard และทดสอบคลิป
  เดิมซ้ำบน release candidate ก่อนนับว่า AI edit ผ่าน E2E

## Backend Runtime Dependency Boundary

GitHub CI installs all optional packages because native build and test tools use
platform-specific optional binaries. Its production audit excludes optional
packages that are not part of the PostDee runtime. Render completes the build
and Prisma migration first, then prunes development and optional packages before
starting the API. PostDee uses `firebase-admin` for Auth and FCM only; the
optional Firestore and Google Cloud Storage clients are not shipped in the
running service. Video storage continues to use Cloudflare R2.

## AI Editing Runtime Source of Truth

- Both `render.yaml` and `render.staging.yaml` set
  `TRANSCRIPTION_PROVIDER=elevenlabs`, `EDIT_PLAN_PROVIDER=gemini`, and
  `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite`. ElevenLabs Scribe v2
  produces timed Thai transcripts; Gemini 3.5 plans from the full visual proxy
  and transcript with structured JSON and provider-default sampling (no
  explicit `temperature`); deterministic PostDee rules are the final fallback.
  Groq is not selectable in runtime configuration.
- Transcript gaps are silence candidates only. The Android/iOS client confirms
  each candidate against the source waveform before rendering; failed or
  ambiguous verification keeps the original audio. The verifier uses FFmpeg
  `silencedetect`, keeps only padded intersections away from source edges and
  protected speech, and passes those verified ranges through preview, review,
  subtitle re-render, and export. Local retry does not transcribe, upload, call
  `/ai-edits/prepare`, or consume another AI-edit minute. A successful probe
  with no safe range is shown separately from a probe failure.
- The retained color-only compatibility path renders original-duration edits
  locally for Pro users and does not consume AI editing minutes. It does not
  extract audio, upload media, or call `/ai-edits/prepare`; the seller-facing
  setup card is now hidden. Colour plus shortening or any audio-dependent
  capability keeps the normal API path. Unknown enabled capabilities fail
  closed before either route starts side effects.
- Fresh device measurements for output codec, FPS, file size, audio peak, and
  A/V sync remain a release gate. The local colour-only path now has one exact
  Pixel 8 export measurement, but the API-dependent matrix is blocked and the
  repository does not claim the renderer acceptance checks are complete.
- The verified Tasks 3–8 implementation is committed locally in `43fa6e0`.
  Task 9 Steps 1–5 are complete, with exact deployed Staging SHA/health and the
  fresh APK/fixture hashes recorded. Step 6 is `BLOCKED`: a new 30-day,
  Speech-to-Text-only Staging key was installed and deployed on the unchanged
  code SHA, but `target-30` still failed closed with upstream HTTP 401 at 21:57
  ICT, without output or PostDee quota use. ElevenLabs showed 9,994/10,000
  workspace credits used (6 remaining), so provider-side quota exhaustion is
  the leading diagnosis; the upstream response detail was not available to
  prove the exact cause. Colour-only local render/export evidence passed
  without consuming quota, while direct zero-upload/prepare log evidence
  remains pending.
  Remaining matrix rows are open.

## Backend

Path: `apps/api`

Current backend pieces:

- `GET /health`
- Mock-safe route implementations for uploads, posts, captions, templates,
  analytics, and billing
- In-memory stores for local posts, templates, and single-process publish queue testing
- Optional BullMQ publish queue adapter selectable with `PUBLISH_QUEUE=bullmq`
- Optional Cloudflare R2 video storage adapter selectable with `VIDEO_STORAGE=r2`, including signed upload and signed download access scaffolds
- Optional Gemini caption adapter selectable with `CAPTION_PROVIDER=gemini`
- ElevenLabs Scribe v2 adapter selectable with
  `TRANSCRIPTION_PROVIDER=elevenlabs`; brand-name keyterms are opt-in because
  the provider charges extra for keyterm prompting
- Legacy S3/OpenAI adapters remain available with `VIDEO_STORAGE=s3` and `CAPTION_PROVIDER=openai`
- Mock/Firebase auth middleware selectable with `AUTH_PROVIDER=firebase`
- RevenueCat webhook receiver for Starter and Pro subscription entitlements
- Authenticated RevenueCat subscriber resync for reconciling restored purchases
- Legacy store subscription verification scaffold for Apple App Store and Google Play purchases
- Store notification handler that updates paid entitlement state for known verified store purchases
- Mock publish worker scaffold for the `publish-posts` queue
- Prisma schema for users, posts, platform publishing records, saved templates, and subscriptions
- Prisma schema and repository for persistent real-clip AI caption usage
  counts
- `.env.example` with required environment variables

Run backend checks:

```powershell
cd apps/api
npm.cmd install
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

Prepare a local PostgreSQL database after `DATABASE_URL` is set:

```powershell
cd apps/api
npm.cmd run prisma:generate
npm.cmd run prisma:migrate:dev
npm.cmd run prisma:seed
```

The seed command upserts the mock auth user from `MOCK_USER_ID`, `SEED_USER_EMAIL`, and `SEED_USER_DISPLAY_NAME`.

Start the backend in development:

```powershell
cd apps/api
npm.cmd run dev
```

The API listens on port `4000` by default.

Start the publish worker scaffold after Redis is available and `PUBLISH_QUEUE=bullmq`, `POST_STORE=prisma`, and `DATABASE_URL` are configured:

```powershell
cd apps/api
npm.cmd run worker:publish
```

The worker currently uses mock platform publishing and mock video cleanup by default. When `ANALYTICS_STORE=prisma`, it records platform publish results into `PlatformPublish` so the analytics summary can read them from PostgreSQL. It claims posts with `QUEUED -> PUBLISHING` before calling external publishers, skips jobs for posts that are already running or finished, skips stale scheduled jobs whose `runAt` no longer matches the post's current schedule, and treats optional R2/S3 cleanup failures as best-effort cleanup results instead of changing a successfully published post to failed. It is the handoff point for real TikTok, YouTube Shorts, Instagram Reels, Facebook Page Video, and R2/S3 cleanup integrations. `FACEBOOK_REELS` remains the internal compatibility value, but PostPeer's current Facebook capability is Page Video, not Reels.

PostPeer `202 pending/publishing` responses are polled through
`GET /v1/posts/{postId}` for roughly two minutes. A platform is marked
`PUBLISHED` only when PostPeer returns a real platform URL or id; the backend no
longer invents an external id. Only errors explicitly known to be safe may be
retried. An uncertain provider outcome fails closed with instructions to check
the platform before trying again, so a retry cannot silently create a duplicate.

### Backend API

The API defaults to mock-safe/local adapters. When explicitly configured, it
can call real R2, Gemini, ElevenLabs, Firebase, PostPeer, and RevenueCat services.
Having an adapter in code does not mean its provider-level production test has
passed; see `docs/GO_LIVE.md` for the current activation checklist.

#### `GET /health`

Returns service status.

```json
{
  "status": "ok",
  "service": "postdee-api"
}
```

#### `GET /publishing/readiness`

Authenticated configuration preflight for new social posts. A `200` response
with `{ "status": "ok", "acceptingPosts": true,
"platformSettingsVersion": 1 }` means that this API process is not configured
with `SOCIAL_PUBLISHER=disabled` and accepts the Phase 2 settings contract. It
does not probe
PostPeer, object storage, the publish queue, or the signed-in user's connected
accounts, and it is not provider-level readiness evidence.

Roll out this contract API-first: apply the Prisma migration, deploy the API,
and verify `platformSettingsVersion: 1` before releasing Mobile that sends
per-platform settings. The version is an operational compatibility signal, not
a provider-health check; current Mobile also fails closed before upload when the
field is missing, malformed, or lower than `1`.

Both the accepting `200` response and disabled `503` response set
`Cache-Control: private, no-store` so a previous readiness result is not stored
for reuse. This is a defensive response contract; it does not establish that
caching caused any earlier observation.

When publishing is disabled, the route returns `503` with
`SOCIAL_PUBLISHING_UNAVAILABLE`. Current mobile clients call this endpoint
before watermarking or uploading media and show a Thai unavailable message.
`POST /posts`, `PATCH /posts/:id`, and `POST /posts/:id/publish-now` repeat the
same authoritative gate in case the configuration changes after the preflight;
`DELETE /posts/:id` remains available so an existing queued post can still be
canceled.

#### `GET /auth/me`

Returns the current scaffold auth user. With `AUTH_PROVIDER=mock`, the API uses `MOCK_USER_ID` by default and supports development headers such as `x-postdee-user-id`, `x-postdee-email`, `x-postdee-display-name`, `x-postdee-phone-verified`, and `x-postdee-phone-number`.
`AUTH_PROVIDER=mock` is for local development only; startup rejects it when
`NODE_ENV=production`.

Response:

```json
{
  "status": "ok",
  "user": {
    "id": "local-dev-user",
    "provider": "mock"
  }
}
```

#### `POST /uploads`

Creates upload metadata and returns a temporary object key; local mock storage
keeps this flow provider-safe during development.
This route requires the current authenticated user. In local mock mode, the
mobile app sends `x-postdee-user-id`; in Firebase mode, it sends a bearer token.

Request:

```json
{
  "fileName": "demo reel.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 12345678,
  "width": 1080,
  "height": 1920,
  "uploadProtocol": "multipart-v1"
}
```

Response includes `upload.videoS3Key`, the existing legacy field name for the temporary object key that can be passed to `POST /posts`. New upload keys are scoped to the authenticated user, for example `uploads/<user-id>/<upload-id>/<file>`.
When `width` and `height` are provided, the backend validates that the metadata describes a vertical 9:16 video, such as `1080x1920`.
The backend rejects uploads above `UPLOAD_MAX_SIZE_BYTES` (default `524288000`, or 500 MiB).

New mobile clients opt in with `"uploadProtocol": "multipart-v1"`. In `dual`
or `multipart` mode, the response contains an opaque session `id`,
`partSizeBytes`, `partCount`, and `sessionExpiresAt`. The client requests each
part URL just in time from `POST /uploads/:uploadId/parts/:partNumber`, uploads
that exact byte range, and sends the returned ETags to
`POST /uploads/:uploadId/complete`. A managed `videoS3Key` can be used by
`POST /posts` only after the session reaches `COMPLETED`; status and abort are
available through `GET /uploads/:uploadId` and `DELETE /uploads/:uploadId`.
Ambiguous completion responses are polled with bounded backoff, and the API can
reconcile a `COMPLETING` session by checking the completed R2 object's exact
size before marking it `COMPLETED`.

`UPLOAD_PROTOCOL_MODE` defaults to `legacy`, so existing clients still receive
the original signed `PUT` fields (`uploadUrl`, `uploadMethod`, `uploadHeaders`,
and `uploadExpiresAt`). Production uses `dual` during rollout: opted-in clients
use managed multipart while older clients keep working. The legacy URL remains
a replay risk until all supported clients are upgraded and production can move
to strict `multipart` mode.

#### `POST /captions/generate`

Generates a local Thai affiliate caption template from 1 or 2 keywords. This route requires a paid plan, either Starter or Pro, limits each keyword to 80 characters, and consumes the same monthly AI caption generation quota used by paid caption features.

Current product direction: AI captioning should start from a selected real
clip. Starter uses audio-only understanding, while Pro can combine audio with
selected visual frames. The app should let AI detect the spoken language and
best caption direction from the clip automatically; if a seller wants a
different language, market, or style, they can write that in optional guidance.
The keyword endpoint remains a temporary scaffold and should not be the main
paid package promise.

Request:

```json
{
  "keywords": ["กันแดด", "ผิวใส"]
}
```

Response includes `caption`, `hashtags`, `[ใส่ลิงก์ Affiliate ที่นี่]`, and the remaining monthly `quota`.

If the authenticated user is Basic, the API returns `402` with code `PRO_REQUIRED`. If the monthly caption quota is exhausted, it returns `429` with code `AI_CAPTION_QUOTA_REACHED`.

#### `POST /captions/generate-from-clip`

Generates the new mock-safe real-clip AI caption package after a clip is
selected. This route accepts `videoS3Key`, optional `guidance`, optional
`selectedFrameKeys`, and optional `deleteAfterUse`. The mobile upload flow sends
`deleteAfterUse: true` for AI-only clip/frame uploads so the backend attempts
R2/S3 cleanup after the caption request. The route also checks that media keys
belong to the authenticated user and reserves monthly quota before calling the
AI provider.

- Starter uses audio-only mode and has 50 generations/month.
- Pro uses audio plus selected-frame mode and has 120 generations/month.
- Each successful generate/change request counts as one generation.
- The current scaffold returns caption options, hooks, hashtags, SEO keywords,
  a search title, auto language/market context, source mode, and remaining
  quota.
- Local development can keep usage in memory with `CAPTION_USAGE_STORE=memory`;
  production should use `CAPTION_USAGE_STORE=prisma` after the Prisma migration
  is applied.
- In local mode, `TRANSCRIPTION_PROVIDER=mock` returns a safe Thai transcript.
  In production, `TRANSCRIPTION_PROVIDER=elevenlabs` or legacy `openai` downloads the stored
  clip through signed storage access and sends it to the speech provider.
- It still does not sample real frames from the uploaded video.

#### Removed: `POST /clip-reviews`

The legacy AI Clip Review endpoint is no longer mounted. Requests to
`/clip-reviews` return `404`.

Reason: it overlaps with AI caption from the real clip and made the package
copy confusing. Useful ideas from the old mock review output should move into
AI caption from the real clip or the Pro ElevenLabs + Gemini auto-editing flow.

#### `GET /templates` and `POST /templates`

Stores reusable text templates for the current authenticated user. Template
lists and creates are scoped by `userId`.

Create request:

```json
{
  "title": "Affiliate disclosure",
  "body": "ลิงก์นี้เป็นลิงก์ Affiliate"
}
```

#### `GET /posts` and `POST /posts`

Stores queued posts in the configured memory/Prisma post store and creates a
publish job in the configured queue.
The mobile publish-draft feature is deliberately outside this API: saving a
draft copies its video, optional cover, and manifest into app-owned Application
Support storage scoped by the signed-in stable user ID (the Firebase UID with
real authentication). It does not create
an API post, upload to R2, contact PostPeer/social platforms, enqueue work, or
consume post quota. Consequently there is no `DRAFT` value in the backend post
status contract and `GET /posts` never returns these local drafts. They are not
synced between devices, although the operating system may include app-owned
files in a device/cloud backup according to its backup settings.

The scaffold can still accept `subscriptionPlan` as a temporary request override
only in local mock development. When `NODE_ENV=production`, the backend rejects
request-body plan overrides and uses the configured subscription store instead.
If no plan is available, the request is treated as `BASIC`.
Posts are scoped to the current auth user. With `AUTH_PROVIDER=mock`, use `x-postdee-user-id` to simulate different sellers during development.
With the memory subscription store, use `x-postdee-subscription-plan: STARTER` or `PRO` to simulate a paid seller.

Create request:

```json
{
  "clientRequestId": "submit_2d7d3b0b7d8e4ec58c0e4d72",
  "caption": "ของดีต้องลอง #ของดีบอกต่อ",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
  "coverFrameTimeMs": 4200,
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "platformSettings": {
    "TIKTOK": { "publishMode": "INBOX_DRAFT" },
    "YOUTUBE_SHORTS": {
      "title": "รีวิวสินค้าชิ้นใหม่",
      "visibility": "private",
      "madeForKids": false,
      "containsSyntheticMedia": false,
      "communityGuidelinesCertified": true
    }
  },
  "subscriptionPlan": "PRO",
  "scheduledAt": "2026-06-02T10:00:00.000Z"
}
```

Phase 2 keeps the main screen compact: selecting a connected destination reveals
one short outcome summary and a settings button; the detailed controls open in
that platform's sheet instead of placing every platform field on the main form.
The review also names the connected account/channel/page using its display name
or external account id. Mobile fails closed when that identity is missing, a
required setting is incomplete, or the requested outcome cannot be determined;
the seller must refresh or reconnect instead of confirming an inferred target.
The complete explicit settings shapes are:

- TikTok: `INBOX_DRAFT`. `DIRECT_POST` with `SELF_ONLY` remains a legacy/internal
  shape and is blocked for new Mobile requests until creator-info, current
  privacy/interaction choices, consent, and TikTok audit approval exist.
- YouTube Shorts: a title (1–100 characters, no `<` or `>`),
  `private|unlisted|public`, the made-for-kids answer, the realistic synthetic
  media answer, and `communityGuidelinesCertified: true`.
- Instagram Reels: `shareToFeed: true|false`; there is no per-post Private mode.
- Facebook Page Video: `publishMode: PUBLISH|PAGE_DRAFT`. The user must choose;
  the internal compatibility platform name remains `FACEBOOK_REELS`.

“Save draft in PostDee” and provider drafts are different. A PostDee draft stays
local and has no remote side effect. TikTok `INBOX_DRAFT` and Facebook
`PAGE_DRAFT` run only after Post: they upload media, create a server post, enter
the queue, contact the provider, and consume one post unit for that destination.

The new-post response includes `post` and `publishJob`. If `scheduledAt` is
present, the job status is `SCHEDULED`; otherwise it is `READY`. A replay of a
post that has already advanced beyond `QUEUED` can return the existing `post`
without a job.
For new connected-account posts, the API also saves an immutable internal target
snapshot and revalidates that account before the final database write and again
before the worker calls PostPeer. A disconnected or changed account fails
closed. Provider account ids in `platformTargets` and the provider-level
`providerPostId` are internal and are removed from public post, queue, and
platform-result responses.
Current Mobile stores one stable `clientRequestId` in each local draft. The
first accepted request returns `201`; a matching retry returns the same durable
post with `200` and `idempotentReplay: true`, repairing its missing queue job
when it is still `QUEUED`. A committed key reused for a different publishing
intent—including different platform settings—or one whose original post is
terminal `FAILED`, returns a safe `409`
instead of reporting a new queue success. Legacy requests may omit the field,
but every such call is treated as a new attempt and has no deduplication
guarantee.
After `409 IDEMPOTENT_POST_FAILED` or `409 IDEMPOTENCY_KEY_REUSED`, Mobile keeps
the original local draft and records the block against that draft ID in the
current Upload state, so another Post tap does not upload again. The only way to
submit again from this state is the explicit “เริ่มรายการโพสต์ใหม่” action: it
warns that the old attempt may already exist, requires confirmation, then saves
the same editable content as a new draft with a new request ID while retaining
the original draft for inspection.
An accepted schedule must be strictly in the future and no more than 30 days
after the server's current time. The same window applies when rescheduling.
`videoS3Key` and optional `coverImageS3Key` must come from `POST /uploads` for
the same authenticated user; the backend rejects media keys owned by another
user. `coverFrameTimeMs` stores the selected source-video frame in milliseconds.
Cloud Scheduling requires Starter or Pro. The `BASIC` scaffold path supports
real-time posting only after phone verification and is limited to 3 post units
per month. Starter is limited to 120 post units per month, and Pro is limited
to 250 post units per month. A post unit is counted per selected platform, so
one video posted to four platforms uses four units. Repeated platform values
are collapsed, and the quota check plus post insert is atomic. `scheduledAt`
must be a valid future RFC 3339 timestamp with `Z` or an explicit `±HH:mm`
timezone, and no more than 30 days ahead. The API rejects impossible calendar
dates and normalizes accepted offsets to UTC.

When `SOCIAL_PUBLISHER=disabled`, `POST /posts` returns
`503 SOCIAL_PUBLISHING_UNAVAILABLE` before managed-upload readiness checks,
subscription/quota reads, post persistence, or queue enqueue. The mobile
preflight normally prevents the media upload too, but an old client or a race
between preflight and submit can already have uploaded an object; that orphan
must be handled by the normal temporary-media cleanup policy.

Post creation is database-first: the durable owner-scoped `QUEUED` row remains
when queue enqueue returns `503 PUBLISH_QUEUE_UNAVAILABLE`, and a retry with the
same supplied request ID repairs the queue without a second post/quota charge.
The draft does not yet persist completed remote upload keys, so a lost response
can still leave replacement video/cover objects unused even though the post row
is deduplicated. Production needs remote-key reuse or explicit superseded-object
cleanup plus a verified R2 lifecycle rule.

#### `POST /posts/:id/publish-now`

Moves an authenticated user's still-queued scheduled post into the ready queue
without pretending that the scheduled time is the current time. The route is
owner-scoped, returns `404 SCHEDULED_POST_NOT_FOUND` when the post is missing or
no longer an editable schedule, and returns `503 PUBLISH_QUEUE_UNAVAILABLE` if
the queue replacement fails. It first clears the exact persisted schedule with
a compare-and-set, then replaces the job; failure conditionally restores the
original schedule only if no newer state has advanced. It also returns
`503 SOCIAL_PUBLISHING_UNAVAILABLE` before reading or changing the post when
social publishing is disabled.

#### `GET /queue/jobs`

Lists publish job placeholders created by `POST /posts` for the current
authenticated user.

Response:

```json
{
  "status": "ok",
  "jobs": [
    {
      "id": "mock-job-id",
      "queueName": "publish-posts",
      "postId": "mock-post-id",
      "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
      "runAt": "2026-06-02T10:00:00.000Z",
      "status": "SCHEDULED",
      "createdAt": "2026-06-01T00:00:00.000Z"
    }
  ]
}
```

#### `GET /analytics/summary?range=30d`

Returns a unified analytics summary for the 4 supported platforms. This route requires the Pro plan.
In local mock mode, use `x-postdee-subscription-plan: PRO` or call `POST /billing/mock-success` for the same mock user before requesting analytics.
Supported ranges are `today`, `7d`, `30d`, `90d`, and `year`. The response
includes platform totals plus a UTC `daily` series grouped by platform publish
date, so the mobile date filters and chart use backend data instead of sample
numbers.

- TikTok
- YouTube Shorts
- Instagram Reels
- Facebook Page Video (internal compatibility value: `FACEBOOK_REELS`)

#### `GET /billing/subscription`

Returns the current authenticated user's plan status and feature flags for the mobile Home screen.

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

After phone verification, Basic keeps `monthlyPostLimit` at `3`, sets `remainingPostsThisMonth` from current-month usage, and sets `canUseFreePostQuota` to `true`.
Starter response sets `plan` to `STARTER`, `status` to `ACTIVE`,
`monthlyPostLimit` to `120`, enables AI captions and scheduling, and keeps
analytics locked.
Pro response sets `plan` to `PRO`, `status` to `ACTIVE`, `monthlyPostLimit` to
`250`, enables scheduling, analytics, and the higher AI caption tier.
Compatibility AI review flags may still appear for older clients, but they
remain `false` and should not be shown in package copy.

#### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when `BILLING_PROVIDER=revenuecat`.
The webhook requires `Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>`.
RevenueCat `app_user_id` must match the PostDee user id, which should be the
Firebase uid in production. The backend maps RevenueCat entitlement or product
ids to Starter or Pro, then updates the configured subscription store.

Request shape:

```json
{
  "event": {
    "id": "event-id-from-revenuecat",
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "event_timestamp_ms": 1780444800000,
    "expiration_at_ms": 1780531200000
  }
}
```

Active purchase and renewal events activate the mapped plan. `EXPIRATION`
removes paid access. `CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE`
are acknowledged without revoking access immediately because the subscription
can still be active until the paid period actually expires. Actionable events
require `id` and `event_timestamp_ms`; the per-user cursor and subscription
change are atomic, so retries and older events cannot overwrite newer state.

#### `POST /billing/revenuecat/resync`

Reconciles the authenticated Firebase user's subscription after the mobile app
calls RevenueCat `restorePurchases`. The backend reads the RevenueCat subscriber
with the server-only `REVENUECAT_REST_API_V1_KEY`, prefers Pro when both paid
entitlements are active, and updates the configured subscription store. If
RevenueCat has no active entitlement, only the matching RevenueCat-backed local
subscription is deactivated. An active but unmapped entitlement returns a safe
configuration error without removing existing access.
Clients must not send or choose another RevenueCat app user id; the route always
uses the authenticated PostDee user id.

The subscriber response's `request_date_ms` and webhook `event_timestamp_ms`
share one per-user serializable ordering cursor. Older or equal snapshots/events
are acknowledged without overwriting newer state. If `request_date_ms` is
absent, local API receipt time is used; synchronized server clocks are required
because skew can temporarily suppress a legitimate webhook as apparently old.

This route is not operational in an environment until the current backend is
deployed and its RevenueCat REST API v1 secret is configured. Provider failures
return an error without downgrading the existing plan.

#### `POST /billing/store/verify`

Legacy direct Apple/Google store verification scaffold. It can verify a Starter
or Pro subscription purchase from the mobile store flow and activates the
matching plan for the authenticated user based on `productId`. In
`BILLING_PROVIDER=mock`, `provider` is `mock-store`. In `BILLING_PROVIDER=store`,
Android purchases use Google Play verification when Google credentials are
configured, and iOS purchases use App Store Server API verification with Apple
signed transaction verification when Apple credentials and root certificates are
configured. Production billing should use RevenueCat instead of this custom
store verifier.

Request:

```json
{
  "platform": "ANDROID",
  "productId": "postdee_pro_monthly",
  "purchaseToken": "google-play-purchase-token"
}
```

Use `productId: "postdee_starter_monthly"` for Starter 199 THB/month and `productId: "postdee_pro_monthly"` for Pro 299 THB/month. For iOS, send `platform: "IOS"` with `transactionId`. When the App Store verifier decodes `originalTransactionId`, the backend uses it as the durable Apple billing id so renewal notifications can match the same subscription even when later transaction ids change.

Response includes the verified store purchase metadata and the activated subscription:

```json
{
  "status": "ok",
  "purchase": {
    "provider": "mock-store",
    "platform": "ANDROID",
    "productId": "postdee_pro_monthly",
    "verifiedAt": "2026-06-04T00:00:00.000Z"
  },
  "subscription": {
    "userId": "local-dev-user",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

#### `POST /billing/mock-success`

Activates the Starter or Pro plan for the authenticated mock user. This endpoint exists only for local scaffold testing before real Apple/Google store receipt verification is connected.
It is disabled when `NODE_ENV=production` or when real store billing mode is enabled.
Startup also rejects `BILLING_PROVIDER=mock` when `NODE_ENV=production`.

Request:

```json
{
  "plan": "STARTER"
}
```

#### `POST /billing/google-play/notifications`

Receives Google Play Real-time Developer Notifications through a Pub/Sub push payload. The endpoint requires `Authorization: Bearer <GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN>`, decodes the Pub/Sub `message.data`, supports subscription, test, and voided purchase notifications, maps clear subscription events to local entitlement status, and returns an acknowledgement. It updates only subscriptions that were previously bound through `POST /billing/store/verify`.

Current Google status mapping:

- `1`, `2`, `4`, `6`, `7` -> `ACTIVE`
- `5` -> `PAST_DUE`
- `12`, `13`, `20` -> `CANCELED`
- `voidedPurchaseNotification` with `productType: 1` -> `CANCELED`
- `3` is intentionally ignored because user cancellation can still leave entitlement active until the paid period ends.

#### `POST /billing/apple/notifications`

Receives App Store Server Notification V2 payloads. The scaffold requires `signedPayload` verification through Apple `SignedDataVerifier` or an injected test decoder, extracts the decoded transaction id and original transaction id when available, maps clear subscription events to local entitlement status, and returns an acknowledgement. It updates only subscriptions that were previously bound through `POST /billing/store/verify`.

Current Apple status mapping:

- `SUBSCRIBED`, `DID_RENEW`, `DID_RECOVER`, `REFUND_REVERSED` -> `ACTIVE`
- `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD` -> `ACTIVE`
- `DID_FAIL_TO_RENEW` without subtype `GRACE_PERIOD` -> `PAST_DUE`
- `EXPIRED`, `REFUND`, `REVOKE`, `GRACE_PERIOD_EXPIRED` -> `CANCELED`

Response includes the parsed notification event and `status: "ok"` after the handler finishes.

## Mobile

Path: `apps/mobile`

Current mobile pieces:

- Light and dark Flutter themes (light is the current default)
- Generated Android and iOS platform folders with app display name `PostDee`
- Home dashboard with manual refresh for total views and likes from `GET /analytics/summary`, plus automatic analytics refresh after the plan becomes Pro
- Universal uploader screen with 9:16 validation, real video selection, saved
  caption templates, scheduling that must be in the future and is capped at 30
  days, explicit connected-platform selection with no automatic destinations,
  and a
  functional cover editor. A seller can scrub to a source-video frame, add Thai
  text, choose Prompt or Anuphan, adjust weight, size, colors, and position, then
  review the cover before posting. Mobile renders a 1080x1920 JPEG; Instagram
  and Facebook receive the image, TikTok receives the frame time, and YouTube
  Shorts leaves final cover selection to the YouTube mobile app. The compact
  tool area still exposes only `ตัดคลิปเป็น EP`; the removed manual editor,
  automatic-watermark, and advanced-mode cards must not return.
- Publish drafts are copied into per-stable-UID Application Support storage with
  their video, optional cover, caption/settings, selected destinations, and
  optional schedule. Saving locally does not call publishing readiness, upload,
  post, provider, queue, or quota paths. Drafts do not sync across devices and
  may be included in OS backup. After an active draft is accepted into the post
  queue, Mobile deletes its local copy; a failure before queue acceptance
  retains it, and a local cleanup failure is reported rather than hidden. This source-level path
  still needs real-device save/restore/storage/backup verification.
- The pre-publish review shows the requested per-platform outcome and connected
  account/channel/page before confirm: TikTok inbox draft, the completed YouTube
  visibility/compliance choice, Instagram share-to-feed, and Facebook Page Video
  publish/page-draft. A missing account identity, incomplete setting, or unknown
  outcome blocks confirmation and asks the seller to refresh/reconnect or fix the
  setting. Scheduled-post detail uses the dedicated authenticated
  `POST /posts/:id/publish-now` command.
- The result screen reports the server lifecycle truth: `QUEUED` means accepted
  into the queue, `PUBLISHING` means still sending, `PUBLISHED` means every
  requested delivery was confirmed (which may be private or a provider draft),
  and `PARTIAL_PUBLISHED` means only some destinations succeeded. An
  unrecognized status is not shown as success and the local draft is retained;
  an idempotent replay is labelled as the existing item.
- Calendar tab that refreshes when opened, polls queued/publishing posts while
  visible, uses the real publish time, and opens completed results read-only;
  plus AI caption entry points from Upload after a clip is selected
- Mobile API client and Upload UI call `POST /captions/generate-from-clip` for
  the new real-clip caption scaffold after a clip is selected.
- Pro AI editing backend exposes `POST /ai-edits/prepare`, which turns the
  selected clip, UI capability toggles, style/prompt, and settings into a
  mobile FFmpeg render recipe. It meters the same 200 monthly AI editing minutes
  as transcription only after the requested edit plan and recipe succeed; a
  failed planner/recipe retry does not consume quota. The final atomic
  reservation still enforces the monthly limit. It does not render video
  server-side. ElevenLabs transcription returns timed words, segments, and
  non-speech audio-event tags without a free-form spelling prompt. Optional segment confidence/no-speech/compression
  signals are retained for highlight quality checks and to omit unreliable ranges
  or clearly unexpected mixed-script recognition noise from burned subtitle
  lines. Normal Latin product/place names remain allowed. The backend validates the
  complete provider timing timeline before using it for subtitles, planning,
  repeated-speech cleanup, or silence candidates. A malformed, missing,
  overlapping, backwards, clipped, or out-of-range timed event fails closed for
  editing; a partial display subset may still be retained for diagnostics but is
  never treated as safe cut evidence.
- The AI editing setup starts every optional capability switch off. The seller
  can explicitly enable subtitles, silence cleanup, repeated-speech cleanup, or
  `AI ใส่เอฟเฟกต์เสียงให้`; leaving all switches off still permits base
  target-length shortening. The seller-facing colour/light and audio-cleanup
  cards remain hidden while their internal contracts stay compatible with older
  results. SFX is an AI analysis path, not a manual sound editor: the provider
  may return only an allowlisted PostDee `soundId` and trusted source timestamp,
  while mobile fixes volume at 25%, maps each surviving anchor through the final
  cut timeline, and reuses the same recipe for preview and full export. The app
  contains no seller-facing sound picker, placement slider, or manual SFX Studio.
  Provider/timing/parse failure keeps the clip unchanged and does not meter an
  unavailable-only request; a completed analysis, including a valid empty
  selection, uses the normal AI-edit minute policy. Real-device listening and
  A/V-sync acceptance remain required before Production.
- For the production capability set, mobile extracts mono 16 kHz AAC at 64 kbps
  into balanced temporary `.m4a` chunks no longer than 30 seconds, uploads them
  with `purpose=ai-edit-audio`, and sends ordered `audioChunks` to the backend.
  This keeps the whole source timeline while avoiding a tiny final chunk and
  long-form leading-speech omissions. The backend transcribes each chunk,
  restores source-relative timestamps, and merges one transcript only when no
  timed item had to be clipped or dropped at a chunk boundary. Any such timing
  damage marks the combined result untrusted so planning stops safely instead
  of cutting from a repaired-looking subset. A successful metered prepare
  reserves usage at most once for the combined request. The original video
  stays on the phone for FFmpeg
  rendering. Local and remote temporary audio are cleaned best-effort after the
  prepare call; legacy single `audioS3Key` and `videoS3Key` clients remain
  compatible.
- When the requested result is shorter than the source transcript, mobile also
  creates a temporary whole-duration 360 px MP4 visual proxy at 1 fps with its
  complete audio track. It uploads that bounded proxy with
  `purpose=ai-edit-visual-proxy`; `POST /ai-edits/plan` sends the proxy through
  Gemini Files API together with timestamped Thai transcript segments. Gemini
  selects the story window after seeing the entire proxy, while the full-quality
  source never leaves the phone for rendering. If visual analysis is unavailable,
  the existing audio/transcript plan remains the safe fallback. Mobile reuses
  the local proxy when only the target duration changes, then deletes it when
  the source is replaced, removed, or the editing screen closes. R2 and Gemini
  temporary files are cleaned best-effort after each planning request. Gemini
  file upload, processing-state polling, and deletion use Google's official
  `@google/genai` server SDK so the app does not maintain a fragile resumable
  upload protocol itself.
- The full source duration is sent as `durationSeconds` for quota pre-check,
  planning, and recipe timeline recovery. The backend uses the longer valid
  value between that client-reported media duration and the provider transcript
  duration. This recovers trailing video/silence when the official app reports
  native FFprobe duration. A server-side media-duration probe and API-side
  10-minute limit remain release blockers before public billing can treat the
  value as tamper-resistant.
  Current mobile accepts source clips up to 10 minutes. After selection, one
  duration slider requests from 5 seconds up to 3 minutes (or from 1 second for
  a source shorter than 5 seconds), capped by the source length. Its rightmost
  stop means “keep original” and omits `targetDurationSeconds`, so provider
  timing drift cannot trim the final fraction of the clip or trigger an
  unnecessary visual proxy. The edit
  planner excludes known prompt leakage and low-quality segments, then uses
  transcript selling signals (hook, benefit, proof, offer, and CTA) to choose one
  continuous story window. Thai continuation fragments such as `แต่`, `แล้ว`,
  `โดย`, `ซึ่ง`, and `ของมาจาก` receive a soft opening penalty when a complete
  nearby sentence is available; the local duration cap remains a
  safety guard for old or malformed recipes. If incomplete transcript/silence
  timing would leave less media than requested, mobile restores neighboring
  context around the selected moments so a slider-selected request does not
  collapse into a near-empty result. The recipe carries repaired
  `transcript.boundarySegments` separately from visible
  `subtitles.segments`. Mobile uses only those strict transcript boundaries for
  opening/tail alignment, including when the subtitle capability is off, while
  the renderer still receives no subtitle overlay. If the field is missing or
  its evidence is unavailable, mobile keeps the planner story-window cut,
  displays a boundary-evidence warning, and never guesses from raw provider
  segments. If a leading target-length cut intersects a repaired transcript
  boundary cue, mobile moves the cut just before that cue and balances the
  result at the tail, preventing the shortened clip from opening mid-sentence.
  The 0.15-second pre-roll is used only when that time is a real subtitle-free
  gap. If the target would end on a dangling Thai connector such as `ก็`, mobile
  keeps the opening/Hook and internal AI cuts unchanged, then moves only the
  trailing boundary to the first nearby complete phrase. The semantic allowance
  is 10% of the selected target, bounded to 1–3 seconds; if no complete phrase
  fits, the dangling cue is removed instead. The renderer uses the same limit,
  and this does not enable or duplicate the separate three-second hook feature.
- After the first successful metered prepare, changing only the duration slider
  reuses the same in-memory transcript and calls non-metered
  `POST /ai-edits/plan`.
  Audio is not uploaded or transcribed again unless the source or analysis
  settings change.
- When automatic subtitles are available, mobile first renders a lightweight
  result and opens result review. Subtitle Studio opens only from the explicit
  “edit subtitles” review action. The user can edit text and
  timing, add/delete/split/merge cues, undo/redo, and change the bundled
  Bai Jamjuree/Prompt/Anuphan font, size, text colour, outline, shadow, and the
  free subtitle position while the Flutter preview updates immediately. The
  setup screen shows a paused real frame from the selected clip, lets the seller
  scrub to another frame, and lets them drag the subtitle directly. The chosen
  preview frame is local-only: it is not uploaded and is not used as a cover.
  Subtitle cues use one line in both new and restored drafts; legacy two-line
  draft styles are migrated to one line when loaded.
  Draft JSON is autosaved in app-owned storage and reopening the same source
  and AI setup restores it. These local edits and retries do not call a metered
  AI endpoint.
- Thai subtitle preparation rejects unsafe character-fragment timing and keeps
  the API's readable Thai cue boundaries instead of splitting an unspaced phrase.
  The API expands provider fragments to semantic Thai words and enforces a final
  safety ceiling of five words and 20 graphemes for multi-token cues. An
  indivisible brand name, URL, or other single token may exceed 20 graphemes so
  it is not cut in half; it is isolated from neighboring tokens and mobile
  measures its real width before shrinking the font for preview/export.
  The setup choices now state the real density contract: karaoke is at most one
  word, readable is at most three words, and complete is at most five words.
  One metered prepare response can include all three cue variants from the same
  transcript, so changing only 1/3/5, colour, outline, or position in the current
  editing session does not transcribe the clip or reserve minutes again. Preview
  and export use the same one-line ASS coordinate contract; an overlong manual
  cue is rejected with a correction message instead of being silently clipped.
- Transcription-provider failures return structured HTTP 502
  `AI_TRANSCRIPTION_PROVIDER_FAILED` without consuming AI-edit quota or exposing
  provider details; the mobile screen translates this into a retryable Thai error.
- After the first phone-side render, the mobile app stays on the AI editing
  screen so the user can preview the result, remove supported AI edits they do
  not want, or add them back. Each review checkbox automatically re-renders a
  new preview from the original clip without another metered prepare call while
  keeping the last successful preview safe on failure. The accepted result can
  then go directly to Upload/Post or open in the manual editor for further changes.
- AI review uses a disposable lightweight preview: sources longer than 60 seconds
  render at up to 540p/20 fps/1 Mbps, while shorter sources use up to
  720p/24 fps/2 Mbps. FFmpeg writes real processed-time progress for the UI,
  and mobile accepts FFmpeg's own `progress=end` marker when an Android
  completion callback is lost. The output must still contain a real video
  stream. At 99%, the UI says that it is verifying the video instead of leaving
  users with what looks like a frozen progress screen. A Pro entitlement
  preflight releases the screen after 30 seconds instead of locking the editor.
  FFmpeg startup with no processed-time, terminal session, or exact
  `progress=end` signal times out after 30 seconds for preview and 90 seconds
  for full export. Renders can be cancelled or retried, and identical local
  results are reused.
  Choosing Post creates a separate full-source-dimension export before opening
  Upload/Post, so the lightweight preview is never published.
- The AI editing header loads `GET /ai-edits/quota` and shows the authenticated
  user's exact remaining and used Pro minutes. It updates immediately from the
  metered `prepare` response and can be tapped to refresh without consuming a
  minute.
- `POST /ai-edits/prepare` reserves minutes only when at least one requested AI
  outcome is usable. Repeat or silence analysis with unsafe timing does not
  consume minutes when no other requested analysis succeeds. A safe silence
  analysis still counts when it completes but finds no gap. Explicit empty or
  colour-only capability requests stop before transcription. After the local
  Pro entitlement check, the official mobile client handles colour-only edits
  that keep the original duration with a cut-free full-duration recipe on the
  phone: it does not extract audio, upload media, call `prepare`, or change the
  minute balance. Colour plus a shortened target, subtitles, silence cleanup,
  or repeated-speech cleanup stays on the normal audio/API route. Any unknown
  enabled capability fails closed before those side effects. Legacy clients
  that omit the capability field keep their previous metered behaviour.
- Android subtitle export gives libass the selected bundled Thai-safe
  Bai Jamjuree, Prompt, or Anuphan font explicitly and maps the selected colour,
  active-word colour, fade/pop effect, outline, shadow, and safe alignment into
  the final MP4. Validated complete word timing uses escaped ASS active-word
  events; missing, incomplete, edited, or unsafe timing falls back to readable
  static SRT without inventing word timing. Subtitles are burned against the
  original source timeline before kept ranges are compacted, so a diagnostic
  SRT can legitimately end later than the shortened MP4; cues inside removed
  ranges do not appear in the final video. The output name ends in
  `_subtitled.mp4` only when real subtitle content is rendered; otherwise it
  ends in `_edited.mp4`.
  Silence removal compacts kept audio ranges with
  `atrim` + `concat` so the audio ends with the shortened video instead of
  continuing after the final frame.
- Pace cleanup settings are real recipe inputs. `silencePreset` maps to internal
  gaps in a complete validated word timeline, or a complete reliable segment
  timeline when safe word evidence is unavailable, with thresholds of `natural`
  = 1.0 s, `balanced` = 0.6 s (the default), and `compact` = 0.4 s. Leading and
  trailing gaps are not candidates. Mobile treats those gaps as non-executable
  candidates until its waveform verifier succeeds; only verified intersections
  enter the final cut list. Successful verification, including an empty result,
  is cached for the exact source and timing evidence. Failed verification is not
  cached so the user can retry locally.
  The setup offers `AI เลือกให้` (default) and `เลือกเอง`. Both choices send
  `speechReductionMode: "auto"` so one analysis can report repeated
  Thai words or phrases with stable occurrence IDs and source timing. Only
  adjacent repeats within 0.35 seconds are selected for removal by default;
  the last occurrence is retained. A word used three or more times in separate
  sentences is shown for awareness but kept, because removing a product name or
  important subject could damage meaning. Thai provider fragments are usable
  only when they reconstruct one exact NFC-normalized semantic word in raw
  provider order, inside one reliable segment, with no internal gap above 0.15
  seconds. This evidence is used only for repeated-speech detection and does not
  replace subtitle word timing. Negation, `ๆ`, numbers/prices, fragments that
  cannot be proven exact, timed audio events, and unsafe timing fail closed. AI
  mode starts with those recommendations selected; manual mode starts with none selected. The review
  then lets the user keep or remove each safe occurrence before re-rendering.
  `fillerWords` and `fillerRanges` remain as a legacy-client compatibility path;
  the current setup no longer displays a fixed filler-word chip list, and
  manual mode never applies legacy filler ranges automatically.
- Mobile keeps the setup's pending source separate from the accepted source used
  by review, Subtitle Studio, retry, and export. Source, duration, recipe,
  verified silence, subtitle project, selected repeat occurrences, and rendered
  result become active together only after a render succeeds. A failed render
  for a newly selected clip therefore leaves the previous result intact. The
  same rule covers local colour retry: retry repeats only the phone-side render,
  while a failed source B attempt cannot replace the accepted source A state.
- Build-time rollback flags can disable verified-silence cuts and automatic
  repeat cuts independently. With repeat cutting disabled, detected groups stay
  visible as read-only information, all selected occurrence IDs are empty, and
  every render/export path keeps the speech. Other selected capabilities are
  unchanged.
- Result review shows detected silence and repeated-speech groups, the number
  of selected safe occurrences, and their combined detected time. These are pre-render
  detections, not a promise that the exported clip saves exactly that duration.
  Mobile fits the AI story plan to the requested length before applying these
  cleanup ranges, so duration restoration cannot put removed silence or repeated speech
  audio back; the final export may therefore be slightly shorter than requested.
  When subtitles are enabled, the selected word is also removed from its
  source-timeline cue before burn-in. If that word cannot be mapped safely, the
  media cut is rejected too so subtitle text and speech never disagree.
- Production exposes only seller-selectable AI editing capabilities with a real
  mobile path: subtitle, silence, repeated-speech cleanup, and AI-selected sound
  effects. The existing color/light renderer remains compatibility-tested
  internal support, but its setup card and the audio-cleanup card are hidden.
  Auto-reframe, zoom, translation, price tags, CTA cards, and the AI-page
  watermark remain locked as `เร็ว ๆ นี้`. AI SFX uses ten procedural WAV
  assets with recorded hashes; the model selects only an allowlisted ID and
  trusted timestamp, while mobile owns volume, cut-timeline mapping, and local
  rendering. No manual sound-effect UI remains.
- Beat-sync advanced settings now let the user keep the original audio or pick
  an owned MP3/M4A/WAV file through Flutter's `file_selector`, confirm usage rights, choose
  cut intensity, music volume, and voice ducking, and send those choices in the
  prepare recipe. The licensed PostDee catalog and the real beat-analysis/music
  mixing renderer are still pending, so the UI does not claim beat sync was
  applied to the exported clip yet. Catalog tracks remain unavailable until
  their license explicitly covers all six PostDee publishing destinations.
- Production keeps beat sync locked off with a `เร็ว ๆ นี้` state through the
  compile-time `ENABLE_EXPERIMENTAL_BEAT_SYNC` flag, whose default is `false`.
  Internal QA may set it to `true` to inspect the setup-only UI; the flag does
  not enable beat analysis, music mixing, ducking, or any other renderer work.
- Production also keeps the 3-second hook/highlight capability locked as
  `เร็ว ๆ นี้` through default-false `ENABLE_EXPERIMENTAL_AI_HOOK`. An internal
  QA build may expose the control, but the API still marks it `planned` and the
  mobile renderer does not reorder the opening timeline.
- AI editing advanced settings use an accordion so only one capability section
  is expanded at a time. No section is expanded by default.
- Legacy AI Clip Review UI, `/clip-reviews` route, config, and internal
  mock/provider code have been removed from the active app path.
- Saved templates wired to `GET /templates` and `POST /templates`
- Unified analytics wired to `GET /analytics/summary?range=...`, including real
  range selection and a publish-date daily chart without simulated numbers
- Home API connection check wired to `GET /health`, a local Gemini caption smoke check, plan status refresh wired to `GET /billing/subscription`, Basic Phone OTP UI for unlocking the 3-post free quota, and one automatic analytics refresh after Pro is unlocked
- Upload AI captions keep the customer flow simple: select a clip, optionally add guidance, then let AI infer language and market from the clip.
- Starter and Pro CTAs on Home can use the legacy Flutter `in_app_purchase`
  scaffold by default, or the RevenueCat `purchases_flutter` path when
  `ENABLE_REVENUECAT_BILLING=true`; purchases are confirmed through
  `POST /billing/revenuecat/webhooks`, while user-initiated Restore runs the SDK
  restore then `POST /billing/revenuecat/resync`

Local API config can be passed with Dart defines:

```powershell
flutter run --dart-define=API_BASE_URL=http://localhost:4000 --dart-define=POSTDEE_MOCK_USER_ID=local-dev-user
```

Use `STORE_STARTER_MONTHLY_PRODUCT_ID=postdee_starter_monthly` and `STORE_PRO_MONTHLY_PRODUCT_ID=postdee_pro_monthly` when testing non-default store subscription product ids.
Use `POSTDEE_MOCK_SUBSCRIPTION_PLAN=STARTER` or `PRO` when testing scheduled posts against the mock backend.
For local RevenueCat Test Store billing, run from `apps/mobile` with `--dart-define-from-file=revenuecat.local.json`. That ignored file contains the RevenueCat Test Store SDK key and must not be used for App Store or Google Play release builds.
For internal beat-sync UI QA only, add `--dart-define=ENABLE_EXPERIMENTAL_BEAT_SYNC=true`. Keep this define absent or `false` in production builds until the renderer is implemented and verified.
For internal hook UI QA only, add `--dart-define=ENABLE_EXPERIMENTAL_AI_HOOK=true`. Keep it absent or `false` in production; this flag does not add highlight analysis or timeline rendering.

A local Flutter SDK is available at `.tools/flutter` for this workspace and is ignored by Git. If you do not add Flutter to the system `PATH`, run mobile checks through the local SDK:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

Android build/run still requires Android Studio and the Android SDK. Production iOS build/run requires Xcode on macOS.

If platform folders ever need to be regenerated:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat create --platforms=android,ios .
```

## Required Environment Variables

Copy `apps/api/.env.example` to `apps/api/.env` and replace the placeholder values before connecting real services.

Required services for later milestones:

- PostgreSQL for app data
- Redis for BullMQ scheduling
- Cloudflare R2 for temporary video storage
- Firebase Auth for Google Sign-In and Phone OTP verification
- Gemini API for Thai caption generation
- PostPeer for real TikTok, YouTube Shorts, Instagram Reels, and Facebook Page
  Video publishing (`FACEBOOK_REELS` is retained only as the current internal
  compatibility value)
- RevenueCat subscriptions for Starter and Pro, backed by Apple App Store and Google Play products

See `FIREBASE_SETUP.md` for the Firebase Auth and Google Sign-In setup checklist.

Production account deletion is temporarily disabled with
`FIREBASE_AUTH_DELETE_ENABLED=false` because the current mutation boundary is
process-local and cannot yet guarantee a full cross-process drain. In a
controlled environment, enabling the path also requires
`FIREBASE_SERVICE_ACCOUNT_JSON`. When enabled, `DELETE /account` disconnects
the user's PostPeer integrations, removes
the R2 owner prefix (or an S3-compatible client that implements owner-prefix
listing), deletes local data, and deletes the Firebase identity last. Active
Firebase users must have signed in within five minutes. A dedicated
account-only retry path accepts a still-valid token only when Firebase confirms
the UID is already gone; revoked tokens remain rejected. RevenueCat webhooks do
not recreate users that no longer exist. PostPeer cleanup follows every page of
the profile's integrations and fails before local deletion when provider cleanup
is unavailable or any external disconnect fails. A durable marker protects the
managed-upload owner prefix before queue/provider cleanup. The owner coordinator
serializes authenticated API mutations and RevenueCat webhook application only
inside one API process; another process can pass the durable-marker check before
deletion starts and commit afterward. The publish worker
first atomically claims a due post from `QUEUED` to `PUBLISHING`, then checks the
marker before calling the provider, without holding a lease across that call.
Therefore this path is not production-safe until every user mutation participates
in a durable repository barrier and full mutation drain. Keep the Production
feature disabled until that gate and the remaining device/slow-network cleanup
tests are complete.

Queue/storage scaffold switches:

- `TEMPLATE_STORE=memory` keeps saved templates in memory; `TEMPLATE_STORE=prisma` uses PostgreSQL through Prisma.
- `POST_STORE=memory` keeps posts in memory; `POST_STORE=prisma` uses PostgreSQL through Prisma and upserts the current auth user before creating posts.
- `SUBSCRIPTION_STORE=memory` reads mock subscription headers and local mock billing activations; `SUBSCRIPTION_STORE=prisma` reads and upserts active subscriptions through PostgreSQL.
- `BILLING_PROVIDER=mock` keeps the local billing scaffold; `BILLING_PROVIDER=store` keeps the legacy direct Apple/Google verifier; `BILLING_PROVIDER=revenuecat` receives RevenueCat webhooks and is the production billing path.
- `REVENUECAT_WEBHOOK_AUTH_TOKEN` is required when `BILLING_PROVIDER=revenuecat` in production.
- `REVENUECAT_REST_API_V1_KEY` is a server-only RevenueCat secret used by the
  authenticated restore/resync route. Never put it in Flutter or commit it.
- `REVENUECAT_STARTER_ENTITLEMENT_ID` and `REVENUECAT_PRO_ENTITLEMENT_ID` map RevenueCat entitlements to PostDee plans.
- `REVENUECAT_STARTER_PRODUCT_ID` and `REVENUECAT_PRO_PRODUCT_ID` map RevenueCat products to PostDee plans when entitlement ids are not present in the webhook.
- `GOOGLE_PLAY_PACKAGE_NAME` is the Android package name registered in Google Play Console.
- `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON` is the preferred production credential source for Android Publisher API OAuth.
- `GOOGLE_PLAY_ACCESS_TOKEN` is a temporary scaffold access token fallback for Android Publisher API calls.
- `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` is required by the Google Play Real-time Developer Notifications endpoint.
- `APPLE_APP_BUNDLE_ID` is the iOS bundle id registered in App Store Connect.
- `APPLE_APP_STORE_ISSUER_ID`, `APPLE_APP_STORE_KEY_ID`, and `APPLE_APP_STORE_PRIVATE_KEY` are used to sign App Store Server API JWTs.
- `APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64` is a comma-separated list of DER root certificates encoded as base64 for Apple's signed transaction verifier.
- `APPLE_APP_APPLE_ID` is the numeric App Store app id. It is optional for sandbox but should be set for production verification.
- `APPLE_APP_STORE_ENVIRONMENT=sandbox|production` selects the App Store Server API base URL. Keep sandbox for development.
- `ANALYTICS_STORE=memory` returns in-memory analytics metrics; `ANALYTICS_STORE=prisma` reads platform publish metrics from PostgreSQL through Prisma and lets the publish worker record platform results.
- `CAPTION_USAGE_STORE=memory` keeps real-clip AI caption usage in memory;
  `CAPTION_USAGE_STORE=prisma` persists monthly usage in PostgreSQL through
  Prisma.
- `PUBLISH_QUEUE=memory` keeps publish jobs in memory; `PUBLISH_QUEUE=bullmq`
  uses Redis/BullMQ. Create commits the durable post before enqueue; a queue
  failure returns `503 PUBLISH_QUEUE_UNAVAILABLE` and a same-key replay repairs
  the job. Reschedule/publish-now update the post first and use a conditional
  rollback if queue replacement fails.
- `PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` so the API and separate worker process share the same post records.
- Publish workers claim only `QUEUED` posts before calling a publisher. Duplicate
  retry jobs for posts already `PUBLISHING`, `PUBLISHED`,
  `PARTIAL_PUBLISHED`, or `FAILED` are skipped. Scheduled jobs whose `runAt`
  no longer matches the post's current `scheduledAt` are also skipped.
- Provider publishing retries are bounded and run only for an explicitly safe
  pre-accept failure. Network/timeouts or a PostPeer result that cannot be
  confirmed are not submitted again; the user must check the destination first.
- `SOCIAL_PUBLISHER=mock` returns fake success only in local development;
  `SOCIAL_PUBLISHER=disabled` fails closed without contacting a platform and is
  the initial Staging setting. It also makes publishing readiness, post create,
  post reschedule, and publish-now fail with
  `503 SOCIAL_PUBLISHING_UNAVAILABLE`, while cancel remains available.
  `SOCIAL_PUBLISHER=postpeer` calls PostPeer and requires `POSTPEER_API_KEY` plus
  `VIDEO_STORAGE=r2|s3`.
- `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true` is an opt-in activation guard for
  the single-process `PUBLISH_QUEUE=memory` scheduler. Before a real PostPeer
  process starts its scheduler or listens for traffic, it runs one atomic
  global aggregate count with status in `QUEUED` or `PUBLISHING`; future
  schedules are therefore included. A non-zero total or inspection error blocks startup
  without loading post/user/media details. Staging enables this guard; its
  default is `false`, and the Production Blueprint is unchanged.
- API startup reads server configuration once and passes that same object to the
  app and scheduler diagnostics. It logs only the non-secret social mode,
  publisher name, and whether the empty-backlog guard is enforced. When that
  guard is enforced, a guard-pass message is emitted only after scheduler
  startup succeeds. Staging SHA `208b4e580ddd2291a7a32e718c2519d785730895`
  recorded the enabled mode and guard-pass before one authorized YouTube Shorts
  Private publish passed, then recorded the disabled mode after restoration.
  This evidence does not retroactively prove that an earlier deployment ran the
  guard.
- `POSTPEER_TIKTOK_ACCOUNT_ID`, `POSTPEER_YOUTUBE_ACCOUNT_ID`, `POSTPEER_INSTAGRAM_ACCOUNT_ID`, and `POSTPEER_FACEBOOK_ACCOUNT_ID` are non-production/operator smoke-test integration ids only. Production rejects them and must publish through per-user social connections.
- New per-user PostPeer profiles use versioned 128-bit HMAC pseudonyms. A lost
  mapping to one older 40-bit profile may be repaired temporarily with both
  `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` and
  `POSTPEER_LEGACY_RECOVERY_PROFILE_ID`. The fingerprint is the full
  `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`;
  remove both values immediately after that user's refresh restores the
  mapping. Partial, malformed, duplicate, or mismatched recovery data fails
  closed.
- `PostPeerProfile.profileId` is uniquely claimed by one PostDee user at the
  database boundary. The first mapping remains authoritative for same-user
  races; cross-user claims fail safely without exposing the existing owner.
- `VIDEO_STORAGE=mock` creates mock S3-style upload keys and mock read placeholders; `VIDEO_STORAGE=r2` uses Cloudflare R2 through the S3-compatible API for signed upload and signed download access; `VIDEO_STORAGE=s3` remains available as a legacy AWS S3 path.
- `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID`, and `CLOUDFLARE_R2_SECRET_ACCESS_KEY` configure R2 uploads.
- `CLOUDFLARE_R2_ENDPOINT` can override the default `https://<accountId>.r2.cloudflarestorage.com` endpoint when needed.
- `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS=300` keeps R2 signed upload URLs usable for five minutes. Legacy upload retries request one fresh URL after explicit expiry; managed multipart retries request a fresh URL only for the affected part.
- `UPLOAD_PROTOCOL_MODE=legacy|dual|multipart` selects the upload rollout. It
  defaults to `legacy`; production uses `dual` while old clients are upgraded,
  then can move to strict `multipart` to remove the legacy signed-URL replay
  window.
- `MULTIPART_UPLOAD_PART_SIZE_BYTES=16777216` sets the server-selected managed
  part size (16 MiB by default).
- `MULTIPART_UPLOAD_SESSION_EXPIRES_SECONDS=3600` sets how long an unfinished
  managed upload session remains usable.
- `UPLOAD_MAX_SIZE_BYTES=524288000` controls the maximum declared upload size accepted by `POST /uploads`.
- `RATE_LIMIT_WINDOW_MS=60000` and `RATE_LIMIT_MAX_REQUESTS=300` cap requests per IP per window; exceeding the cap returns `429` with code `RATE_LIMITED` (`GET /health` is exempt). Auth, upload, AI, and social-connection routes also have tighter fixed per-IP buckets.
- `AWS_S3_UPLOAD_EXPIRES_SECONDS=900` controls how long legacy S3 signed upload URLs remain usable.
- `CAPTION_PROVIDER=mock` uses the local Thai template; `CAPTION_PROVIDER=gemini` calls the configured primary `GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite` with `GEMINI_API_KEY`, retries transient failures, then falls back directly to the local template without trying a secondary Gemini model; `CAPTION_PROVIDER=openai` remains available as a legacy path.
- `EDIT_PLAN_PROVIDER=gemini` uses `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite` for transcript and visual planning. Both requests require structured JSON and use provider-default sampling without an explicit `temperature`.
- `TRANSCRIPTION_PROVIDER=mock` uses the local Thai transcript for AI caption
  language detection and AI editing; `TRANSCRIPTION_PROVIDER=elevenlabs` calls Scribe v2 with
  `ELEVENLABS_API_KEY`, `ELEVENLABS_TRANSCRIPTION_MODEL`, and optional
  `ELEVENLABS_TRANSCRIPTION_KEYTERMS`; `TRANSCRIPTION_PROVIDER=openai` remains
  available as a legacy path.
- `AUTH_PROVIDER=mock` uses development headers; `AUTH_PROVIDER=firebase`
  requires `FIREBASE_PROJECT_ID`. It verifies Google Secure Token certificates
  by default, or Firebase Admin revocation/user existence when
  `FIREBASE_AUTH_DELETE_ENABLED=true`.
- The mobile app has an auth session store, Google Sign-In UI, and
  Firebase/Google auth gateway. In the production Firebase path, each API header
  refresh reads the live UID and ID token as one credential snapshot and checks
  that UID against the stable session/draft owner before and after the async
  refresh. If the signed-in account changes or no longer matches, the request
  fails closed; Upload also rechecks ownership around remote steps and stops the
  remaining publish flow so one account's draft/video cannot continue under
  another account. Without a Firebase token, local development keeps using mock
  headers. If Firebase auth is enabled before project files are configured,
  startup falls back to a readable sign-in setup message.

Seed helpers:

- `MOCK_USER_ID` controls the default local auth user.
- `SEED_USER_EMAIL` and `SEED_USER_DISPLAY_NAME` control the Prisma seed user.

## Roadmap

See `ROADMAP.md` for the build roadmap. It includes the current Phase 1 core app work, planned pricing with Basic, Starter 199, and Pro 299, AI caption from the real clip, Pro ElevenLabs + Gemini auto editing, and Phase 2 growth features such as Link in Bio, EP tools, watermarking, hashtag radar, AI comment center, viral alerts, and Team and Editor Access.

## Current Limits

The backend defaults to mock-safe adapters and in-memory stores for local work,
while production can use Prisma and real provider adapters. Per-user PostPeer
social connections and the connect/refresh/provider-first disconnect API flow
are implemented. A fresh Firebase user is ensured locally before its PostPeer
profile is persisted, and the provider receives a stable pseudonymous profile
name rather than the Firebase UID/email. `GET /posts` now returns user-scoped
`platformResults` for each post. Phase 2 persists one explicit settings snapshot
and reports `deliveryOutcome` as `LIVE`, `PRIVATE`, `UNLISTED`, or `DRAFT` so a
provider draft/private delivery is not described as publicly live merely because
the internal platform result reached `PUBLISHED`. Existing rows may have a null
outcome and continue to use their legacy status display. New TikTok requests are
limited to `INBOX_DRAFT`; direct posting remains blocked pending creator-info,
consent, and audit approval. One immediate Staging YouTube Shorts Private
connected-account E2E passed on 2026-08-10 with a real non-mock external
reference and exactly one post unit, but it predates the complete Phase 2
settings/target/delivery matrix. Production, provider-draft behavior, and the
remaining platforms/scheduling paths still require controlled E2E tests and
never use shared `POSTPEER_*_ACCOUNT_ID` values. The internal
`FACEBOOK_REELS` value currently targets Facebook Page Video, not Reels. The
repository's Production Blueprint currently selects
`SOCIAL_PUBLISHER=postpeer` even though broader provider-level E2E is still
pending. Treat this as an unresolved configuration risk, not proof that the
deployed Production environment or a user connection is ready; this safety
change does not alter the Production Blueprint.
The current owner/post mutation locks are JavaScript maps inside one API
process. They serialize current authenticated route mutations and RevenueCat
webhook application in that process, but cannot drain mutations already running
in another API instance and are not held around the worker's provider call.
Account deletion is therefore not production-safe, and scale-out would widen
the race. Add a durable repository
owner barrier/lease or equivalent transactional outbox/claim-and-drain protocol
that rejects new writes and drains every in-flight user mutation before cleanup,
then test same-process and genuinely separate-process races.
The in-app Privacy Policy and Terms are still labelled working drafts. Final
hosted legal text, Android/iOS backup behavior for app-owned draft media, Data
Safety/App Privacy disclosures, physical-device draft/replay tests, the
`platformSettingsVersion: 1` API-first migration, legacy-null backlog review,
immutable target revalidation, and the full controlled social
scheduling/provider-draft/recovery matrix remain release gates.
Real-clip AI captioning/editing,
Firebase device auth, RevenueCat Google Play purchases, R2 media flow, and
renewal/refund/cancel handling still need their listed real-device/provider
checks. RevenueCat Test Store purchase and true Restore/resync E2E pass on the
Emulator after the Staging deploy and server REST key configuration. The
RevenueCat Play app/products/entitlements/default offering, production Android
public SDK key, and signed AAB are prepared, but Play Console app/subscriptions,
internal testing, service credentials, and a real Google Play purchase remain
blocked until the developer account is verified with a physical Android device;
the Emulator cannot complete that verification. Platform
views/likes ingestion, Sentry, beat/hook rendering, and AI minute top-ups are not
complete production features yet. See `docs/GO_LIVE.md` and
`LAUNCH_CHECKLIST.md` for the operational truth.
