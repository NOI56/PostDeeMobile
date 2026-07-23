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
- Render Staging ติดตาม branch `main` แล้ว การอัปโหลด R2 จากแอปผ่าน และตั้ง
  `GROQ_API_KEY` ชุด Staging แล้ว รอบเดิมที่ส่งวิดีโอ 38 MB ทั้งไฟล์หยุดที่
  transcription เพราะเกินขนาดไฟล์ของ provider โดยโควตาไม่เปลี่ยน โค้ดปัจจุบันจึง
  แยกเสียง M4A ขนาดเล็กก่อนอัปโหลด; ยังต้อง deploy แล้วทดสอบคลิปเดิมซ้ำก่อนนับว่า
  AI edit ผ่าน E2E

## Backend

Path: `apps/api`

Current backend pieces:

- `GET /health`
- Mock-safe route implementations for uploads, posts, captions, templates,
  analytics, and billing
- In-memory stores for posts, templates, and publish queue placeholders
- Optional BullMQ publish queue adapter selectable with `PUBLISH_QUEUE=bullmq`
- Optional Cloudflare R2 video storage adapter selectable with `VIDEO_STORAGE=r2`, including signed upload and signed download access scaffolds
- Optional Gemini caption adapter selectable with `CAPTION_PROVIDER=gemini`
- Optional Groq transcription adapter selectable with `TRANSCRIPTION_PROVIDER=groq`
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
can call real R2, Gemini, Groq, Firebase, PostPeer, and RevenueCat services.
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
  In production, `TRANSCRIPTION_PROVIDER=groq` or `openai` downloads the stored
  clip through signed storage access and sends it to the speech provider.
- It still does not sample real frames from the uploaded video.

#### Removed: `POST /clip-reviews`

The legacy AI Clip Review endpoint is no longer mounted. Requests to
`/clip-reviews` return `404`.

Reason: it overlaps with AI caption from the real clip and made the package
copy confusing. Useful ideas from the old mock review output should move into
AI caption from the real clip or the future Pro Groq Whisper auto editing flow.

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

Stores queued posts in memory and creates a publish job placeholder.
The scaffold can still accept `subscriptionPlan` as a temporary request override
only in local mock development. When `NODE_ENV=production`, the backend rejects
request-body plan overrides and uses the configured subscription store instead.
If no plan is available, the request is treated as `BASIC`.
Posts are scoped to the current auth user. With `AUTH_PROVIDER=mock`, use `x-postdee-user-id` to simulate different sellers during development.
With the memory subscription store, use `x-postdee-subscription-plan: STARTER` or `PRO` to simulate a paid seller.

Create request:

```json
{
  "caption": "ของดีต้องลอง #ของดีบอกต่อ",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "subscriptionPlan": "PRO",
  "scheduledAt": "2026-06-02T10:00:00.000Z"
}
```

Response includes `post` and `publishJob`. If `scheduledAt` is present, the job status is `SCHEDULED`; otherwise it is `READY`.
`videoS3Key` must come from `POST /uploads` for the same authenticated user; the backend rejects media keys owned by another user.
Cloud Scheduling requires Starter or Pro. The `BASIC` scaffold path supports
real-time posting only after phone verification and is limited to 3 post units
per month. Starter is limited to 120 post units per month, and Pro is limited
to 250 post units per month. A post unit is counted per selected platform, so
one video posted to four platforms uses four units.

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
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "expiration_at_ms": 1780531200000
  }
}
```

Active purchase and renewal events activate the mapped plan. `EXPIRATION`
removes paid access. `CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE`
are acknowledged without revoking access immediately because the subscription
can still be active until the paid period actually expires.

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
- Universal uploader screen with 9:16 metadata form, client/server 9:16 metadata validation, upload plan status refresh with remaining Basic post units, video file picker scaffold, saved template insertion for captions, Starter/Pro pre-check for scheduled posts, optional local file path upload to R2/S3 signed URLs, platform toggles, and backend calls to `POST /uploads` then `POST /posts`
- Calendar tab for scheduled posts, plus AI caption entry points from Upload after a clip is selected
- Mobile API client and Upload UI call `POST /captions/generate-from-clip` for
  the new real-clip caption scaffold after a clip is selected.
- Pro AI editing backend exposes `POST /ai-edits/prepare`, which turns the
  selected clip, UI capability toggles, style/prompt, and settings into a
  mobile FFmpeg render recipe. It meters the same 200 monthly AI editing minutes
  as transcription and does not render video server-side. Groq transcription
  sends the ISO-639-1 Thai hint (`th`) and requests both word and segment
  timestamps without a spelling prompt, preventing provider context from leaking
  into unrelated clip text. Optional segment confidence/no-speech/compression
  signals are retained for highlight quality checks and to omit unreliable ranges
  or clearly unexpected mixed-script recognition noise from burned subtitle
  lines. Normal Latin product/place names remain allowed. The backend validates word timing
  coverage before using it for precise silence/filler cuts and subtitle timing;
  incomplete timing falls back to segments. Groq Thai character-level tokens
  still drive precise gaps, but subtitle text falls back to readable segments.
  Whitespace-only provider tokens are ignored during validation; malformed
  tokens containing real transcript text still fail closed.
- For the production capability set, mobile extracts mono 16 kHz AAC at 64 kbps
  into balanced temporary `.m4a` chunks no longer than 30 seconds, uploads them
  with `purpose=ai-edit-audio`, and sends ordered `audioChunks` to the backend.
  This keeps the whole source timeline while avoiding a tiny final chunk and
  long-form leading-speech omissions. The backend transcribes each chunk,
  restores source-relative timestamps, clips AAC timing overrun at every chunk
  boundary, merges one non-overlapping transcript, and meters the combined
  duration once. The original video stays on the phone for FFmpeg
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
  the existing audio/transcript plan remains the safe fallback. Local, R2, and
  Gemini temporary files are cleaned best-effort after planning.
- The full source duration is sent as `durationSeconds` for the quota pre-check.
  A selected 30/60/custom shortened duration is sent separately as
  `targetDurationSeconds`; the target is omitted at the rightmost “keep
  original” stop so provider timing drift cannot trim the final fraction of the
  clip or trigger an unnecessary visual proxy. The edit
  planner excludes known prompt leakage and low-quality segments, then uses
  transcript selling signals (hook, benefit, proof, offer, and CTA) to choose one
  continuous story window; the local duration cap remains a
  safety guard for old or malformed recipes. If incomplete transcript/silence
  timing would leave less media than requested, mobile restores neighboring
  context around the selected moments so a 30/60/custom request does not
  collapse into a near-empty result. If a leading target-length cut intersects
  a subtitle cue, mobile moves the cut just before that cue and balances the
  result at the tail, preventing the shortened clip from opening mid-sentence.
- After the first successful metered prepare, changing only 30/60/custom reuses
  the same in-memory transcript and calls non-metered `POST /ai-edits/plan`.
  Audio is not uploaded or transcribed again unless the source or analysis
  settings change.
- When automatic subtitles are available, mobile now opens Subtitle Studio
  after `prepare` and before the first FFmpeg render. The user can edit text and
  timing, add/delete/split/merge cues, undo/redo, and change the bundled
  Prompt/Anuphan font, size, text colour, outline, shadow, and safe
  top/middle/bottom position while the Flutter preview updates immediately.
  Subtitle cues use one line in both new and restored drafts; legacy two-line
  draft styles are migrated to one line when loaded.
  Draft JSON is autosaved in app-owned storage and reopening the same source
  and AI setup restores it. These local edits and retries do not call a metered
  AI endpoint.
- Thai subtitle preparation rebuilds readable word boundaries when provider
  word timestamps arrive as character fragments. Long Thai fallback segments
  or fallback segments containing several words are also split at estimated
  Thai word boundaries, capped at two estimated words per cue, before reaching
  mobile. Cues shorter than 0.7 seconds are joined across only a small
  neighboring gap, mobile never hard-splits an unspaced Thai phrase, and the
  live preview scales text down inside its single line instead of hiding it
  with an ellipsis.
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
  renders can be cancelled or retried, and identical local results are reused.
  Choosing Post creates a separate full-source-dimension export before opening
  Upload/Post, so the lightweight preview is never published.
- The AI editing header loads `GET /ai-edits/quota` and shows the authenticated
  user's exact remaining and used Pro minutes. It updates immediately from the
  metered `prepare` response and can be tapped to refresh without consuming a
  minute.
- Android subtitle export gives libass the selected bundled Prompt or Anuphan
  font explicitly and maps the selected colour, outline, shadow, and safe
  alignment into the final MP4. The current rollback-safe renderer still uses
  SRT/static cues; active-word karaoke and per-cue styles remain future work.
  Silence removal compacts kept audio ranges with
  `atrim` + `concat` so the audio ends with the shortened video instead of
  continuing after the final frame.
- Pace cleanup settings are real recipe inputs. `silencePreset` maps to validated
  word-timing gaps, falling back to transcript segments, with thresholds of
  `natural` = 1.0 s, `balanced` = 0.6 s (the default), and `compact` = 0.4 s.
  A qualifying gap before the first spoken range or after the last spoken range
  is included when the provider returns a valid media duration.
  `fillerWords` is an exact allowlist containing only
  `เอ่อ`, `อ่า`, `แบบว่า`, `คือว่า`, and `ประมาณว่า`; matching trims surrounding
  whitespace/punctuation instead of using substring matches on normal word
  tokens. The exact transcript alias `เออ` maps to `เอ่อ`; a detected Thai
  character-token stream may be conservatively reassembled for the same
  allowlist only across tight timing and verified Thai word/text boundaries. A missing
  `fillerWords` field keeps the legacy all-five default, while an explicit empty
  array means no filler-word cuts. Mobile requires at least one selected word
  while the filler capability is enabled.
- Result review shows the number of detected silence and filler ranges plus
  their combined detected time from the prepare recipe. These are pre-render
  detections, not a promise that the exported clip saves exactly that duration.
- Production exposes only the AI editing capabilities with a real mobile
  renderer: subtitle, silence, filler-word cuts, and color/light adjustment.
  Auto-reframe, zoom, audio cleanup, translation, price tags, CTA cards, and
  the AI-page watermark are locked as `เร็ว ๆ นี้` and sent to the API as
  disabled until their exported-video processors pass real-device tests.
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

Complete production account deletion also requires
`FIREBASE_AUTH_DELETE_ENABLED=true` and `FIREBASE_SERVICE_ACCOUNT_JSON`. When
enabled, `DELETE /account` disconnects the user's PostPeer integrations, removes
the R2 owner prefix (or an S3-compatible client that implements owner-prefix
listing), deletes local data, and deletes the Firebase identity last. Active
Firebase users must have signed in within five minutes. A dedicated
account-only retry path accepts a still-valid token only when Firebase confirms
the UID is already gone; revoked tokens remain rejected. RevenueCat webhooks do
not recreate users that no longer exist. PostPeer cleanup follows every page of
the profile's integrations and fails before local deletion when provider cleanup
is unavailable or any external disconnect fails. The deletion barrier is set
before queue and provider cleanup, blocks later authenticated mutations, and is
also checked by the publish worker before it claims a post.

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
- `PUBLISH_QUEUE=memory` keeps publish jobs in memory; `PUBLISH_QUEUE=bullmq` uses Redis/BullMQ. If the publish queue is unavailable while creating or rescheduling a post, the API returns `503 PUBLISH_QUEUE_UNAVAILABLE` instead of leaving the post state ahead of the queue.
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
  the initial Staging setting; `SOCIAL_PUBLISHER=postpeer` calls PostPeer and
  requires `POSTPEER_API_KEY` plus `VIDEO_STORAGE=r2|s3`.
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
- `CAPTION_PROVIDER=mock` uses the local Thai template; `CAPTION_PROVIDER=gemini` calls Gemini with `GEMINI_CAPTION_MODEL` and `GEMINI_API_KEY`; `CAPTION_PROVIDER=openai` remains available as a legacy path.
- `TRANSCRIPTION_PROVIDER=mock` uses the local Thai transcript for AI caption language detection and AI editing; `TRANSCRIPTION_PROVIDER=groq` calls Groq with `GROQ_TRANSCRIPTION_MODEL` and `GROQ_API_KEY`; `TRANSCRIPTION_PROVIDER=openai` remains available as a legacy path.
- `AUTH_PROVIDER=mock` uses development headers; `AUTH_PROVIDER=firebase`
  requires `FIREBASE_PROJECT_ID`. It verifies Google Secure Token certificates
  by default, or Firebase Admin revocation/user existence when
  `FIREBASE_AUTH_DELETE_ENABLED=true`.
- The mobile app has an auth session store, Google Sign-In UI, and Firebase/Google auth gateway. `PostDeeApiClient` can send `Authorization: Bearer <Firebase ID token>` from that session; without a token it keeps using local mock headers. If Firebase auth is enabled before project files are configured, startup falls back to a readable sign-in setup message.

Seed helpers:

- `MOCK_USER_ID` controls the default local auth user.
- `SEED_USER_EMAIL` and `SEED_USER_DISPLAY_NAME` control the Prisma seed user.

## Roadmap

See `ROADMAP.md` for the build roadmap. It includes the current Phase 1 core app work, planned pricing with Basic, Starter 199, and Pro 299, AI caption from the real clip, Pro Groq Whisper auto editing, and Phase 2 growth features such as Link in Bio, EP tools, watermarking, hashtag radar, AI comment center, viral alerts, and Team and Editor Access.

## Current Limits

The backend defaults to mock-safe adapters and in-memory stores for local work,
while production can use Prisma and real provider adapters. Per-user PostPeer
social connections and the connect/refresh/provider-first disconnect API flow
are implemented. A fresh Firebase user is ensured locally before its PostPeer
profile is persisted, and the provider receives a stable pseudonymous profile
name rather than the Firebase UID/email. `GET /posts` now returns user-scoped
`platformResults` for each post. Controlled-first publishing uses YouTube
`private` and TikTok `SELF_ONLY` (`draft: false`) until explicit privacy choices
are added. Production publishing still requires a connected-account E2E test
and never uses shared `POSTPEER_*_ACCOUNT_ID` values. The internal
`FACEBOOK_REELS` value currently targets Facebook Page Video, not Reels.
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
