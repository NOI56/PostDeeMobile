# ARCHITECTURE.md

Architecture overview for the PostDee mobile app and backend scaffold.

## Product Goal

PostDee helps Thai e-commerce sellers, affiliate marketers, and creators upload one vertical 9:16 video and publish or schedule it across multiple short-form platforms from one app. The product should remain Thai-first for the initial launch while keeping the architecture global-ready for other countries, languages, currencies, timezones, phone formats, billing markets, and compliance requirements.

Target platforms:

- TikTok
- YouTube Shorts
- Instagram Reels
- Facebook Page Reels through PostPeer (the existing `FACEBOOK_REELS` value maps
  to `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`;
  there is no fallback to a Page feed video, and real-account E2E remains pending)

## Project Layout

```text
D:\PostDeeMobile
  apps
    mobile  Flutter mobile app
    api     Express + TypeScript backend
  README.md
  API.md
  ARCHITECTURE.md
  AGENTS.md
```

## System Overview

```mermaid
flowchart LR
  Mobile["Flutter Mobile App"] --> API["Express API (Render)"]
  Mobile -.->|purchases_flutter| RC["RevenueCat"]
  RC -.->|Webhooks| API
  API -.->|Subscriber read for Restore| RC
  API --> Auth["Firebase Auth & FCM"]
  API --> DB["PostgreSQL (Render)"]
  API --> Storage["Cloudflare R2 Video Storage"]
  API --> Scheduler["In-process Publish Scheduler (current)"]
  API -.-> Queue["Upstash Redis / BullMQ (optional)"]
  API --> Captions["Real-Clip Caption Provider"]
  API --> Editing["Groq Whisper AI Auto Editing"]
  Scheduler --> Social["PostPeer API (Unified)"]
  Scheduler --> Storage
  Scheduler --> DB
  Queue -.-> Worker["Separate Publish Worker (when enabled)"]
  Worker --> Social
  Worker --> Storage
  Worker --> DB
  API -.-> PlannedSentry["Sentry (planned)"]
  Worker -.-> PlannedSentry
```

The checked-in `render.yaml` uses `PUBLISH_QUEUE=memory`, `POST_STORE=prisma`,
and one API instance. `server.ts` starts the in-process scheduler, which reads
due posts from the configured post store and uses the shared publish-processing
logic, publishing up to 4 posts at once. It also fails posts whose `PUBLISHING` claim (the Post `updatedAt`) is
older than 30 minutes, so a restart mid-publish cannot leave them stuck; the
BullMQ worker path has no such sweep yet. Redis/BullMQ and a separate worker are an optional deployment path;
configure shared Prisma posts, `DATABASE_URL`, and `REDIS_URL` before enabling
that path or increasing the API instance count. This describes repository
configuration, not a fresh check of the live Render service.

Production และ Staging ต้องเป็นคนละ data boundary: `render.yaml` ชี้ไป
`postdee-api`/`postdee-postgres` ส่วน `render.staging.yaml` ชี้ไป
`postdee-api-staging`/`postdee-postgres-staging` และต้องใช้ R2, Firebase,
RevenueCat และ PostPeer ชุดทดสอบแยกกัน รายละเอียดอยู่ใน `docs/STAGING.md`
Android Debug เพิ่ม suffix `.staging` และใช้ `src/debug/google-services.json`;
Profile/Release ยังคงใช้ Firebase Production จึงห้ามผสมกับ Staging Dart defines

## Mobile App

Path:

```text
apps/mobile
```

Current mobile pieces:

- Light and dark Flutter themes; light is the current default.
- Home dashboard with total views, total likes, subscription status, Basic Phone OTP verification, and Starter/Pro CTAs.
- Universal uploader screen with 9:16 metadata validation and platform toggles.
- Calendar tab for scheduled posts and refresh after scheduling.
- Upload AI caption entry point after a video is selected.
- AI editing has no global advanced-mode switch. Each available capability
  exposes its settings directly in a single-open accordion, and the Preset card
  is always available. Beat sync remains visible but locked as `เร็ว ๆ นี้` in
  production; internal QA can expose its setup-only controls with
  `ENABLE_EXPERIMENTAL_BEAT_SYNC=true`.
- AI captioning is gated by paid Starter/Pro status. Starter should use
  audio-only understanding from the selected clip; Pro can add selected visual
  frames.
- Legacy Clip Review UI, route, config, and internal mock/provider code have
  been removed from the active app path.
- Saved templates screen.
- Unified analytics screen gated by Pro status.
- Firebase/Google auth gateway with an isolated Android Debug Staging config;
  Google login/token/Staging API smoke passes on Emulator. Firebase Phone Auth,
  iOS, Production, and physical-device tests remain.
- RevenueCat webhook scaffold for Starter and Pro entitlements, plus a legacy Store Subscription scaffold.

Important mobile services:

- `PostDeeApiClient` calls the backend.
- `PostDeeApiAuthHeaders` sends Firebase bearer tokens when available.
- Without Firebase auth, the app falls back to local mock headers.
- `PostDeeAuthSessionStore` stores the active mobile auth session.
- A session generation changes on sign-in/logout, while token refresh and name
  updates preserve it. Account-deletion consent and token reads check that
  generation across asynchronous work. The auth controller serializes native
  login/logout, Apple deletion revocation and phone credential linking/reload/
  token retrieval; stale responses cannot clear a later session. Auth sessions
  carry a stable UID from Firebase or the configured mock principal.
- Link in Bio stores one versioned JSON draft per UID in SharedPreferences;
  unowned legacy keys are ignored. Draft fields and the owned editor sheet clear
  on identity transitions; stale loads/save feedback cannot populate a new
  session. Local drafts remain on the device and are not a cloud backup.
- FCM gateway generation checks discard stale initialization and subscriptions,
  clear the in-app center on identity changes and register tokens through bound
  API headers. Messages require `data.userId` matching the current UID. On an
  identity change the gateway deletes the device's FCM token, so the backend's
  copy for the previous account stops delivering; the next account registers a
  fresh token only after that deletion settles. Backend token rows are not
  removed, and background OS notification display is not controlled.
- Home uses the legacy `POST /billing/store/verify` path by default for local
  scaffold runs, and can use RevenueCat `purchases_flutter` when
  `ENABLE_REVENUECAT_BILLING=true`; entitlements are then updated by
  `POST /billing/revenuecat/webhooks`. A user-initiated Restore first calls the
  RevenueCat SDK, then the authenticated `POST /billing/revenuecat/resync` route
  to reconcile the server subscription store. Actionable webhook updates and
  their per-user RevenueCat event cursor are committed atomically; duplicate or
  out-of-order events cannot overwrite newer entitlement state.

Global readiness principles:

- Store user-facing copy through localization-ready structures instead of hard-coded Thai-only strings when a screen is redesigned.
- Use user locale and timezone for schedules, analytics dates, and billing display.
- Keep prices and plan names provider-neutral so App Store and Google Play can map products per country.
- Accept international phone number formats for Firebase Phone Auth.
- Keep country-specific legal, tax, platform-policy, and privacy requirements behind explicit launch checklists before opening each market.

Design system:

- Light is the default theme; users can switch between light and dark.
- Light background: `#F2F5F2`; cards: `#FFFFFF`.
- Dark background: `#0E1411`; cards: `#19221D`.
- Use the shared green creator palette from `app_theme.dart` and readable
  theme-aware surfaces.
- Social platform colors should be used only as small accents/icons.

## Backend API

Path:

```text
apps/api
```

Backend stack:

- Node.js
- Express
- TypeScript
- Prisma 6.19.3
- PostgreSQL schema (Render)
- Upstash Redis/BullMQ scaffold
- Cloudflare R2 video storage scaffold
- Firebase ID token verifier
- Firebase Cloud Messaging (FCM) sender using lazy modular Firebase Admin APIs
- Gemini caption provider scaffold
- Groq Whisper AI auto editing scaffold
- RevenueCat webhook receiver scaffold
- Sentry error tracking is planned; it is not integrated yet

Dependency maintenance keeps Prisma on version 6.19.3 and scopes the
`deepmerge-ts@8.0.2` override to `@prisma/config@6.19.3`. Prisma config loading,
client generation, schema validation, and helper compilation pass with that
override on Node 22.23.3. Reassess the override when upgrading Prisma.
The FCM sender uses `firebase-admin/app` and `firebase-admin/messaging`, reuses
the `postdee-backend` app by name, and caches initialization per sender. Mocked
tests cover that SDK contract; they do not establish live delivery readiness.

Main route groups:

- `GET /health`
- `GET /auth/me`
- `POST /uploads`
- `POST /uploads/:uploadId/parts/:partNumber`
- `POST /uploads/:uploadId/complete`
- `GET /uploads/:uploadId`
- `DELETE /uploads/:uploadId`
- `GET /posts`
- `POST /posts`
- `PATCH /posts/:id`
- `DELETE /posts/:id`
- `GET /captions/quota`
- `POST /captions/generate`
- `GET /ai-edits/quota`
- `POST /ai-edits/transcribe`
- `POST /ai-edits/prepare`
- `POST /ai-edits/plan`
- `GET /templates`
- `POST /templates`
- `GET /analytics/summary?range=today|7d|30d|90d|year`
- `GET /billing/subscription`
- `POST /billing/purchase-readiness`
- `POST /billing/revenuecat/webhooks`
- `POST /billing/revenuecat/resync`
- `POST /billing/store/verify`
- `POST /billing/mock-success`
- `POST /billing/google-play/notifications`
- `POST /billing/apple/notifications`
- `POST /devices`
- `GET /social-connections`
- `POST /social-connections/:platform/connect`
- `POST /social-connections/refresh`
- `DELETE /social-connections/:platform`
- `GET /queue/jobs`

## Module Layout

```text
apps/api/src
  app.ts
  server.ts
  config
  modules
    analytics
    aiEdits
    auth
    billing
    captions
    platformPublishes
    posts
    queue
    storage
    subscriptions
    templates
    uploads
    users
  routes
  workers
```

Key idea:

- Routes parse HTTP requests and return responses.
- Services validate business input.
- Stores/repositories hide memory vs Prisma persistence.
- Factories select mock/local implementations from environment config.

## Data Model

Prisma schema path:

```text
apps/api/prisma/schema.prisma
```

Important models:

- `User`: app user identity.
- `Post`: queued video post with caption, platforms, optional schedule time,
  and a nullable `youtubeTitle` override.
- `Template`: reusable text snippets.
- `PlatformPublish`: per-platform publish/analytics record.
- `Subscription`: Basic/Starter/Pro entitlement state.
- `RealClipCaptionUsage`: monthly usage ledger for paid AI caption generations
  from selected clips.
- `AiEditUsage`: monthly minute ledger for Pro AI editing.
- `DeviceToken`: per-user FCM registration token.
- `SocialConnection` and `PostPeerProfile`: per-user provider connection state.

Subscription fields are provider-neutral:

- `billingCustomerId`
- `billingSubscriptionId`

This keeps the schema usable for Apple App Store, Google Play, or other future billing providers.

## Adapters And Stores

| Feature | Local/Mock | Production path |
| --- | --- | --- |
| Templates | `TEMPLATE_STORE=memory` | `TEMPLATE_STORE=prisma` |
| Posts | `POST_STORE=memory` | `POST_STORE=prisma` |
| Subscription | `SUBSCRIPTION_STORE=memory` | `SUBSCRIPTION_STORE=prisma` |
| Analytics | `ANALYTICS_STORE=memory` | `ANALYTICS_STORE=prisma` with `POST_STORE=prisma` |
| Queue / scheduling | `PUBLISH_QUEUE=memory` with the configured post store | Current `render.yaml`: in-process scheduler, `PUBLISH_QUEUE=memory`, `POST_STORE=prisma`, one API instance. Optional scaling path: `PUBLISH_QUEUE=bullmq`, shared Prisma posts, `DATABASE_URL`, `REDIS_URL`, and a separate worker. |
| Video storage | `VIDEO_STORAGE=mock`, `UPLOAD_PROTOCOL_MODE=legacy` | `VIDEO_STORAGE=r2`, with `UPLOAD_PROTOCOL_MODE=dual` plus `DATABASE_URL` during rollout and strict `multipart` after old clients are retired |
| Captions | `CAPTION_PROVIDER=mock` | Real-clip caption provider using backend AI |
| Caption usage | `CAPTION_USAGE_STORE=memory` | `CAPTION_USAGE_STORE=prisma` |
| AI auto editing | `TRANSCRIPTION_PROVIDER=mock` | `TRANSCRIPTION_PROVIDER=groq` with Groq Whisper transcription on backend, FFmpeg export on mobile |
| Auth | `AUTH_PROVIDER=mock` | `AUTH_PROVIDER=firebase` |
| Billing | `BILLING_PROVIDER=mock` | `BILLING_PROVIDER=revenuecat` |
| Social publishing | Local uses `mock`; initial Staging uses fail-closed `disabled` | `SOCIAL_PUBLISHER=postpeer` with per-user social connections and signed R2/S3 media URLs; `FACEBOOK_REELS` always requests Facebook Page Reels with `contentType: 'reel'`, with no Page feed fallback; real-account E2E remains pending; shared `POSTPEER_*_ACCOUNT_ID` values are rejected in production |

Firebase production account deletion additionally requires
`FIREBASE_AUTH_DELETE_ENABLED=true` and `FIREBASE_SERVICE_ACCOUNT_JSON`. Whenever
`AUTH_PROVIDER=firebase` and a service account is configured, the API verifies
tokens through Firebase Admin with revocation checks, so disabled, deleted or
revoked users are rejected. Without a service account (current Staging), the
certificate-only verifier cannot see revocations.

Account deletion is an idempotent saga: the durable owner barrier is set first,
later authenticated mutations are rejected, and the publish worker checks the
same barrier before claiming a post. Queued jobs are then removed and PostPeer
integration pages are listed so every external integration id can be
disconnected. An active completion is allowed a short drain window; a stale
completion is reconciled against the R2 object size before persisted and orphan
multipart sessions are aborted. Every R2 object under the user's exact encoded
owner prefix is attempted, user-scoped database records are deleted, and the
Firebase identity is deleted last.
External cleanup failure stops before database deletion and can be retried;
external deletion is not transactional, so some already-deleted objects or
integrations may remain deleted after a retryable response. Late RevenueCat
active events are ignored when their local user no longer exists and cannot
recreate the account.
Firebase deletion also requires a token authenticated within the last five
minutes. The account-only retry verifier accepts a valid token for a UID that
Firebase confirms is already missing, while still rejecting revoked tokens.
On iOS/macOS, the mobile app first checks `GET /account/deletion-readiness`, then
reauthenticates and revokes Apple access before calling the delete endpoint.
Apple Sign-In must not be exposed on Android/web until server-side Apple token
revocation is implemented for those platforms.
The mobile deletion flow binds the original confirmation to its session and
stops across readiness, revocation or token refresh when that session changes.
Billing status reads do not ensure or recreate User. RevenueCat purchase
preparation goes through authenticated mutation admission instead.

The owner lifecycle marker is independent of multipart upload mode. An active
Prisma feature supplies the durable `ManagedUploadOwner` store in legacy mode
too; all-memory runs use a process-local marker. Explicit final User ensure,
Post creation/quota/reschedule and Subscription activation/RevenueCat event
operations lock the ACTIVE owner row inside the same Serializable transaction
as their write. Serialization conflicts retry up to three attempts. Memory
factories share a per-owner FIFO with deletion. This prevents these entities
from being recreated by work that resumes after the deletion marker commits.

Redis calls stay outside SQL transactions. A process-local admission queue holds
until the actual enqueue/reschedule settles, including compensating removal
after its 10-second acknowledgement timeout. Deletion waits up to five seconds
for admission, then returns `503 ACCOUNT_WRITE_DRAIN_FAILED` for retry if busy.
Cleanup removes owned queue jobs even without a post row and returns
`503 ACCOUNT_PUBLISH_CLEANUP_FAILED` on failure. Cross-instance late Redis adds,
process crashes and already-admitted provider calls remain unresolved; SQL and
Redis are not atomic. Templates, device tokens and social writes are outside
this batch's final-write fences. Mocked lifecycle/concurrency regressions ran
in the local API suite on 20 October 2026; real PostgreSQL/Redis race checks
remain pending.
Managed-upload create/begin-completion also retain their earlier snapshot-based
ACTIVE check; they do not yet use this same conditional owner-row lock.

## Upload And Scheduling Flow

```mermaid
sequenceDiagram
  participant U as User
  participant M as Mobile
  participant A as API
  participant S as Storage
  participant Q as Queue
  participant W as Worker
  participant P as Social Platforms

  U->>M: Select vertical video
  opt User customizes the cover
    U->>M: Scrub to a video frame; style cover text
    M->>M: Center-crop and render a 1080x1920 JPEG locally
  end
  M->>A: POST /uploads (uploadProtocol: multipart-v1)
  alt Managed multipart in dual/multipart mode
    A->>S: Initiate multipart upload
    A-->>M: Session id + videoS3Key + part plan
    loop Every part
      M->>A: POST /uploads/:id/parts/:number
      A-->>M: Just-in-time signed part URL
      M->>S: PUT exact byte range
    end
    M->>A: POST /uploads/:id/complete + ETags
    A->>S: Complete multipart upload
    A-->>M: Upload status COMPLETED
  else Legacy mode or old client during dual rollout
    A->>S: Create upload key / signed URL
    A-->>M: videoS3Key + uploadUrl
    M->>S: PUT full video file
  end
  opt Instagram custom cover or Facebook best-effort thumbnail requested
    M->>A: POST /uploads for JPEG/PNG cover
    M->>S: Upload rendered cover image
  end
  M->>A: POST /posts
  A->>Q: Enqueue publish job
  A-->>M: post + publishJob
  Q->>W: Run job immediately or at scheduled time
  W->>P: Publish to selected platforms
  opt Cleanup enabled or storage lifecycle policy
    W->>S: Delete temporary video and cover after success
  end
  W->>A: Record publish/analytics result
  U->>M: Open Home latest posts
  M->>A: GET /posts?includeMedia=true&limit=3
  A->>A: Sort and limit owned posts
  A->>S: Sign media for only those rows
  A-->>M: Posts + optional coverImageUrl/videoUrl
  M->>M: Show cover or paused video frame
```

Rules:

- Basic users can create real-time posts only.
- Basic users must verify a phone number before using the free quota.
- Basic users are limited to 3 post units per month after phone verification.
- Starter and Pro can schedule posts up to 30 days in advance. The mobile date
  picker and post API enforce the same limit.
  Both scheduled creation and queued-post rescheduling resolve the current plan
  from the subscription store; Basic rescheduling fails before queue/store
  mutation, regardless of any request body plan hint.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Post units count by selected platform, not post row.
- Duplicate platform values are normalized before storage and queueing, and the
  monthly-unit check plus post insert execute atomically (a serializable
  transaction in Prisma) so concurrent requests cannot exceed the plan limit.
- Scheduled times must parse as ISO-8601, be strictly in the future, and stay
  within the 30-day window; an invalid time never falls back to post-now.
- YouTube title choice is independent of the shared caption. Mobile previews
  an automatic title from the first sentence of the first nonempty caption
  line, removing `<`/`>` and limiting it to 100 Unicode code points, or accepts
  an explicit override
  behind `ปรับชื่อเฉพาะ YouTube`. Caption edits retain an explicit title until
  the user selects `ใช้ชื่อจากแคปชัน` to reset it to automatic. The client
  omits `youtubeTitle` in automatic mode; the backend derives the title while
  leaving the full-caption description unchanged. The API trims and validates
  the optional
  override (no `<`/`>`, at most 100 code points, YouTube selected), persists it
  as nullable, and carries it through queue/worker publishing. PostPeer receives
  the chosen YouTube title separately from the full-caption description.
  Empty captions are allowed only for YouTube-only posts with a nonempty
  custom title; other destinations still require a nonempty shared caption.
- Upload metadata is capped by `UPLOAD_MAX_SIZE_BYTES`. Managed multipart part
  sizes are selected by the server, and a post can reference the key only after
  its session reaches `COMPLETED`.
- Cover fields are optional and backward-compatible. The post, queue job, and
  worker carry `coverImageS3Key` plus `coverFrameTimeMs` only when the user
  saves a cover. Both storage keys remain owner-scoped and must be ready before
  the post can be queued. `coverFrameTimeMs` stores the selected video-frame
  position for destinations that support frame-based cover selection.
- Managed cover uploads accept JPEG or PNG up to 2 MiB. The mobile client skips
  uploading the rendered image for TikTok/YouTube-only posts because those
  destinations do not consume that image. In `dual` and `multipart` modes a
  cover must have a completed managed-upload session, preventing a legacy key
  from bypassing its media-type and size checks.
- Platform adapters apply cover controls per destination: Instagram uses the
  signed rendered cover (or frame offset). Facebook Page Reels always sends
  `contentType: 'reel'` and optionally sends the signed image as
  `videoThumbnailUrl` on a best-effort basis; its display on a Reel still needs
  real-account verification, and the provider may choose the cover. TikTok
  Direct Post uses the frame time, and YouTube Shorts leaves final cover
  selection to the YouTube mobile app.
- New clients opt in with `multipart-v1`. `UPLOAD_PROTOCOL_MODE` defaults to
  `legacy`; production uses `dual` during rollout, and moves to strict
  `multipart` only after old clients are retired. Both managed modes persist
  session and deletion-barrier state through Prisma and require `DATABASE_URL`.
- Managed part URLs are issued just in time and can be retried per part. The
  server owns completion and abort, which lets account deletion invalidate
  unfinished sessions before object cleanup.
- Completion and abort transitions use compare-and-set rules. If R2 completes
  an object before the database acknowledgement survives, `GET /uploads/:id`
  verifies its exact size with `HEAD` and reconciles the session.
- The legacy single-file signed `PUT` remains a bearer URL that cannot be
  revoked individually. It keeps a replay window while `legacy` or `dual` mode
  accepts old clients; strict `multipart` closes that remaining path.
- Every route except `GET /health` sits behind a global per-IP rate limit (`RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX_REQUESTS`); auth, upload, AI, and social-connection routes add tighter fixed per-IP buckets.
  The route buckets use Express's proxy-policy-resolved IP and the global
  limiter's default IPv6 `/56` grouping. Deployment must verify that the current
  proxy trust setting matches the actual ingress topology.
- Starter unlocks real-clip AI captioning from audio.
- Pro unlocks analytics, hashtag radar, AI comment center, team/editor access,
  AI captioning from audio plus selected frames, and Groq Whisper auto
  editing.
- A PostPeer `202 pending/publishing` response stays inside the publisher until
  `GET /v1/posts/{postId}` reaches a terminal result or the roughly two-minute
  bounded poll expires. Success requires a real platform URL/id; no synthetic
  external id is stored.
- `GET /posts` joins each authenticated user's posts with their persisted
  `platformResults`, including partial and failed platform outcomes.
- `GET /posts?includeMedia=true&limit=3` scopes to the authenticated user, then
  sorts and limits rows before platform-result lookup and media signing. A
  positive client limit is capped at 50. The response prefers an optional
  rendered-cover URL and also provides the source-video URL so Home can show a
  paused frame for posts without a cover. Signed URLs stay opt-in and mock
  storage returns no invented public URL; mobile releases video controllers
  while Home is hidden and retains the play-icon fallback for missing, expired,
  or unreadable media.
- Provider retries are explicit-safe-only. Unknown network/polling outcomes are
  terminal and tell the user to inspect the destination before trying again.

## RevenueCat Subscription Flow

PostDee uses RevenueCat as the main mobile paid subscription provider.

```mermaid
sequenceDiagram
  participant U as User
  participant M as Mobile (purchases_flutter)
  participant RC as RevenueCat
  participant Store as Apple/Google Store
  participant A as API Webhook
  participant DB as Subscription Store

  U->>M: Tap Start Starter or Start Pro
  M->>A: POST /billing/purchase-readiness
  A->>DB: Check owner lifecycle and ensure canonical User
  A-->>M: purchaseReady true, preparationProtocol 1
  M->>RC: Request purchase
  RC->>Store: Process payment
  Store-->>RC: Receipt/Token
  RC-->>M: Entitlement unlocked
  RC->>A: POST /billing/revenuecat/webhooks
  A->>DB: Activate STARTER or PRO subscription
```

The preparation POST calls no payment or subscriber provider. GET subscription
is read-only; missing/deleted-user webhook events still cannot create a user.
Mobile requires that protocol acknowledgement before SDK purchase. Missing,
404/501 or unsupported readiness fails before buy with a Thai compatibility
message. The real RevenueCat gateway serializes configuration through terminal
buy/restore callback across instances, checks its captured exact UID/session
after every preparation await and before dispatch, and rejects stale results.
Readiness/resync/polling use one API client bound to the original operation;
polling cannot read or accept a later account's subscription. Checks do not
cancel native configuration/payment already dispatched. Release the additive
endpoint, then preparation-aware mobile builds,
retire/independently disable legacy buying builds, then deploy read-only GET.
This branch already bundles GET cutover. Builds that never call preparation can
still buy after a failed GET and require a separate retirement mechanism.

Restore is an explicit user action and uses a separate reconciliation path:

```mermaid
sequenceDiagram
  participant U as User
  participant M as Mobile (purchases_flutter)
  participant A as Authenticated API
  participant RC as RevenueCat Subscriber API
  participant DB as Subscription Store

  U->>M: Tap Restore purchases
  M->>RC: restorePurchases with Firebase uid
  RC-->>M: Customer info refreshed
  M->>A: POST /billing/revenuecat/resync
  A->>RC: GET subscriber using server REST key
  RC-->>A: Active entitlements and expiry
  A->>DB: Reconcile PRO, STARTER, or BASIC
  A-->>M: Current subscription
```

The mobile app never receives `REVENUECAT_REST_API_V1_KEY`. The API derives the
RevenueCat app user id only from the authenticated Firebase user, prefers Pro if
both paid entitlements are active, and leaves the existing plan unchanged if the
provider lookup fails. Zero active RevenueCat entitlements deactivates only the
matching RevenueCat-backed record. Active but unmapped access returns a
configuration error and does not downgrade the user.

Production status and remaining work:

- RevenueCat already has the Play Store app, `postdee_starter_monthly` and
  `postdee_pro_monthly` products, Starter/Pro entitlements, and the default
  offering.
- Link Apple and Google service credentials to the RevenueCat dashboard after
  the matching store apps are available.
- Configure `REVENUECAT_WEBHOOK_AUTH_TOKEN` and the RevenueCat webhook URL.
- Staging already has the server-only `REVENUECAT_REST_API_V1_KEY`; Test Store
  true Restore/resync E2E passes there.
- The production Android public SDK key is configured through an ignored local
  production config, and a signed AAB is ready. The iOS platform key and store
  configuration still remain.
- Create the Play Console app/subscriptions, configure its service credentials,
  and open internal testing after the developer account is verified on a
  physical Android device. The Emulator cannot complete this verification.
- Run sandbox/device purchases and renewal/cancel/refund webhook tests.

## Real-Clip AI Caption Flow

```mermaid
sequenceDiagram
  participant M as Mobile
  participant A as API
  participant Sub as Subscription Store
  participant Usage as Caption Usage Store
  participant S as Storage
  participant AI as Caption Provider

  M->>A: GET /captions/quota
  A->>Sub: Read authenticated user plan
  A->>Usage: Count authenticated user's current UTC month
  A-->>M: plan + quota (no usage reservation)
  M->>A: POST /uploads for AI-only clip and optional frames
  A-->>M: user-scoped media keys
  M->>A: POST /captions/generate-from-clip with media keys and deleteAfterUse
  A->>Sub: Check user plan
  A->>A: Verify media keys belong to auth user
  A->>Usage: Reserve monthly caption quota
  alt User is Starter
    A->>AI: Generate from clip audio context
    A-->>M: caption + hashtags + SEO + hooks
  else User is Pro
    A->>AI: Generate from clip audio + selected frames
    A-->>M: stronger caption + hashtags + SEO + hooks
  else User is Basic
    A-->>M: 402 PRO_REQUIRED
  end
  A->>S: Best-effort delete AI-only media when requested
```

Caption routes:

- `GET /captions/quota` reads the current plan and shared monthly caption
  usage without reserving a generation. Remaining quota is clamped at zero,
  including when recorded usage exceeds the current plan after a downgrade.
- `POST /captions/generate` remains the legacy keyword scaffold, but paid users still spend monthly AI caption quota and each keyword is capped at 80 characters.
- `POST /captions/generate-from-clip` is the new clip-first scaffold with
  Starter audio-only mode, Pro audio plus selected-frame mode, SEO fields, hook
  ideas, transcription-backed language/market context, authenticated media-key
  ownership checks, opt-in cleanup for AI-only clip/frame uploads, and monthly
  quota reservation through memory or Prisma-backed usage storage.

The Upload AI panel displays a compact quota strip immediately above
`ให้ AI ช่วยเขียน`, showing the plan, remaining/limit, used count, and a thin
remaining-quota bar. It reads the quota on entry, Upload-tab activation, and
app resume. Successful generation uses the returned quota immediately; a
failed attempt refreshes the read because the backend may already have
reserved usage. Loading and failed reads stay distinct from an exhausted
quota; a failed read offers retry rather than a fabricated zero. A known
exhausted paid quota disables AI generation without blocking manual caption
editing or posting. The display does not change package limits or generation
accounting.

The clip-first route now reuses the configured transcription provider for
spoken-language detection. Local mode uses a mock Thai transcript; production
can use Groq/OpenAI by downloading the stored clip through signed storage
access. The route still does not sample real frames. The mobile app keeps
language and market selection automatic; provider-level R2/Groq clip testing is
still required. User text can remain as optional guidance after clip selection,
not as the main sold feature. Production can use a backend AI provider such as
Gemini with:

```env
CAPTION_PROVIDER="gemini"
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
GEMINI_API_KEY="..."
```

Production SEO fields should be generated in the same AI call when possible:

- `seoKeywords`
- `searchTitle`
- `captionOptions`

This keeps SEO cost low because the app avoids a second AI request just for search keywords.

## Removed Legacy AI Clip Review Route

```mermaid
sequenceDiagram
  participant M as Mobile
  participant A as API

  M->>A: POST /clip-reviews
  A-->>M: 404 Not Found
```

The active route and mobile UI have been removed. It should not be marketed as
a separate "AI audio review" package feature. Useful output ideas such as
caption angles, hooks, hashtags, and SEO keywords should move into real-clip AI
captioning or Pro Groq Whisper auto editing.

Known limitations:

- The route is not mounted.
- Subscription responses keep old audio/video review fields only as
  compatibility fields, and they should remain `false`.
- The old config and internal mock/provider files have been removed.
- It does not download uploaded media, run audio extraction, sample frames,
  persist AI review usage, create review-specific SEO suggestions, or call a
  review-specific multimodal provider.

Cleanup direction:

- Keep the standalone Clip Review UI removed.
- Keep `/clip-reviews` returning 404 unless a future approved plan reintroduces
  it under a clearer product name.
- Do not put AI audio review in Starter or Pro package copy.
- Reuse useful product ideas such as hooks, hashtags, and SEO fields inside
  real-clip captioning where they help.

## AI Auto Editing With Groq Whisper Flow

```mermaid
sequenceDiagram
  participant M as Mobile
  participant A as API
  participant Sub as Subscription Store
  participant W as Groq Whisper
  participant F as Mobile FFmpeg

  M-->>M: Extract temporary AAC/M4A (mono, 16 kHz, 64 kbps)
  M->>A: Upload audio/mp4 with purpose=ai-edit-audio
  M->>A: Request recipe with audioS3Key + targetDurationSeconds
  A->>Sub: Check Pro plan and editing minutes
  alt User is Pro with minutes
    A->>W: Transcribe bounded audio with word + segment timestamps
    W-->>A: transcript + word timing + segment timing
    A-->>A: Select strongest spoken moments within target duration
    A-->>A: Delete owned temporary M4A (best effort)
    A-->>M: editable transcript data or mobile render recipe
    M->>F: Render initial preview from original clip
    F-->>M: reviewable MP4
    M-->>M: Stay on AI review and toggle supported edits off or back on
    M->>F: Automatically re-render preview from original clip after each toggle
    M-->>M: Accept result and open Upload/Post
  else Basic or Starter
    A-->>M: 402 PRO_REQUIRED
  end
```

Mobile preflights the current subscription before creating an AI-edit upload.
Basic/Starter users receive the Pro message locally and no `POST /uploads`, R2
transfer, or metered prepare request is started. The API Pro check remains the
authoritative security boundary for stale or modified clients.

For every currently enabled production capability (`subtitle`, `silence`,
`filler`, and `color`), mobile sends only a temporary M4A analysis artifact;
the original video stays on the device for FFmpeg preview/export. The upload
exception is narrowly scoped to `purpose=ai-edit-audio`, `audio/mp4`, `.m4a`,
no dimensions, and 25 MiB. The API accepts exactly one `audioS3Key` or legacy
`videoS3Key`, caps legacy video downloads at 200 MiB, and never auto-deletes a
legacy video. Both API and mobile attempt idempotent M4A cleanup. No-audio,
extraction, or upload failure happens before the provider and consumes no AI
editing minutes.

The core Pro flow is implemented. Backend handles auth, quota, temporary storage, and
Groq Whisper transcription. `POST /ai-edits/prepare` combines the AI editing UI
capability toggles, selected style/prompt, transcript, cut plan, overlay hints,
and quota into one mobile render recipe. The API pre-checks estimated duration,
builds the plan and recipe, then reserves actual transcribed minutes before a
successful response so parallel requests do not exceed the monthly quota. A
live OpenAI/Groq planner failure returns `502 AI_EDIT_PLAN_PROVIDER_FAILED`
before reservation and never silently falls back to `mock-rule`; only explicit
`EDIT_PLAN_PROVIDER=mock` uses that rule-based test model, which mobile labels as
test mode. Mobile caches that successful recipe, renders an
initial preview, and stays on the AI screen. Review checkboxes automatically
re-render from the original clip when supported edits are removed or restored,
without another metered prepare request. The last successful preview remains
available if a new render fails. The user can then continue to Upload/Post with
the accepted render. PostDee intentionally has no built-in manual timeline
editor. Users who want hands-on timeline editing may use a separate external
editor such as CapCut, but there is no CapCut integration, export target, or
share handoff in this architecture. Mobile handles FFmpeg
subtitle burn-in, silence cutting, supported visual adjustments, and final MP4
export; capabilities marked `planned` are not shown as already applied.
Recipe caching excludes the temporary storage key, so a local render retry can
reuse the prior recipe without extracting, uploading, or transcribing again.
A target result length is a required explicit mobile selection (30 seconds,
60 seconds, or custom); the setup screen does not preselect 30 seconds. It is a
separate planner input from the client duration estimate used for the early
quota check. The planner keeps high-value transcript
segments (hook, benefit, proof, offer, and CTA) in chronological order and
returns the rest as cut ranges. Mobile renders those ranges and retains a local
duration cap only as compatibility protection for malformed or older recipes.
A 360p visual proxy and visual-frame AI analysis remain unimplemented; future
visual capabilities must fail closed until that separate pipeline is verified.
The production capability allowlist is currently `subtitle`, `silence`,
`filler`, and `color`. Auto-reframe, zoom, and audio cleanup remain `planned`
and mobile locks them as `เร็ว ๆ นี้`. Translation, price tags, CTA cards, and
the AI-page watermark are hidden from the customer setup UI while deferred;
their compatibility keys remain disabled so older presets and API payloads stay
safe without implying that recipe hints changed the exported file.
The AI header independently reads the authenticated monthly quota and replaces
that value with `prepare.quota` as soon as a metered recipe succeeds. Local
preview re-renders and manual quota refreshes do not call the metered endpoint.
The renderer copies the bundled Prompt font into each subtitle render workspace
and passes that directory to libass. For silence cuts, video frames use the
selected keep timeline while audio keep ranges are reset and concatenated, so
both streams finish together after local preview re-renders.

Pace cleanup is an end-to-end recipe input. The backend first validates that
word timings cover the transcript text and timeline, then `silencePreset`
selects their minimum gap: `natural` = 1.0 s, `balanced` = 0.6 s, and
`compact` = 0.4 s. Missing/incomplete word timing falls back to segment gaps.
The same threshold applies before the first range and after the last range when
the transcript has a finite media duration. Overlapping ranges are merged before
gaps are calculated. Groq Thai character-level timings remain useful for gap
detection, while subtitle text falls back to segments instead of being split
into individual characters. The Groq request carries a concise Thai spelling
hint for `PostDee` → `โพสต์ดี`; this prompt is not sent through the OpenAI
provider path.
Whitespace-only provider tokens do not invalidate an otherwise complete timing
stream; malformed tokens containing transcript text still fail closed.
Missing or invalid preset values use `balanced`. `fillerWords` is an
exact, normalized allowlist limited to `เอ่อ`, `อ่า`, `แบบว่า`, `คือว่า`, and
`ประมาณว่า`; `เออ` is an exact alias of `เอ่อ`, and validated fragmented Thai
tokens are reassembled only across tight timing and verified Thai word/text
boundaries. A missing field keeps the legacy
all-five behavior, while an explicit empty or fully invalid list fails closed
with no filler cuts. The API
returns detected silence/filler ranges and mobile renders the supported cuts.
The review summarizes range counts and their combined detected time before
rendering; it does not claim that the final clip duration changes by exactly the
same amount.

The opening 3-second hook has no highlight selector or timeline renderer yet.
`ENABLE_EXPERIMENTAL_AI_HOOK` defaults to `false`, so production mobile locks it
as `เร็ว ๆ นี้` and clamps the effective request to false. Internal QA may expose
the setup control, but the API still returns `planned` and no hook render hint.

Beat-sync setup is currently a safe contract/UI foundation. Mobile can keep the
original audio or pick an owned MP3/M4A/WAV file, requires the user to confirm
usage rights, and sends `recipe.music` preferences for source, beat intensity,
volume, and voice ducking. Local absolute paths stay on the device. Clients send
only an opaque catalog `trackId`; the current backend validates and passes the
reference through. A future catalog resolver must verify storage ownership and
licensing instead of trusting a client-supplied storage key. Beat analysis, catalog licensing,
audio mixing, and ducking are still planned processors and must not be reported
as applied until the renderer implements them. The compile-time
`ENABLE_EXPERIMENTAL_BEAT_SYNC` flag defaults to `false`, so production clamps
the capability off and shows `เร็ว ๆ นี้`. Setting it to `true` is limited to
internal QA of the setup UI and does not change the API contract or renderer.
Capability controls have no global mode gate and use local accordion state with
at most one section open and no default expansion; this is presentation state
only and is never sent to the backend recipe.

## Analytics Flow

Analytics is Pro-only.

```mermaid
sequenceDiagram
  participant M as Mobile
  participant A as API
  participant Sub as Subscription Store
  participant Store as Analytics Store

  M->>A: GET /analytics/summary
  A->>Sub: Check user plan
  alt User is Pro
    A->>Store: Read platform metrics
    A-->>M: totalViews + totalLikes + platforms
  else User is Basic
    A-->>M: 402 PRO_REQUIRED
  end
```

When `ANALYTICS_STORE=prisma`, the backend can aggregate metrics from
`PlatformPublish`; startup also requires `POST_STORE=prisma` so those metrics
cannot point at posts that exist only in one process's memory.

## Auth Flow

Local development:

- `AUTH_PROVIDER=mock`
- User is read from development headers.
- If no header is sent, `MOCK_USER_ID` is used.
- Use `x-postdee-phone-verified: true` to simulate phone verification for Basic free-post testing.
- Request-body subscription plan overrides and mock billing activation are
  development-only shortcuts and are rejected when `NODE_ENV=production`.
- `AUTH_PROVIDER=mock` and `BILLING_PROVIDER=mock` are rejected at startup in
  production so local shortcuts cannot be deployed accidentally.

Firebase path:

- `AUTH_PROVIDER=firebase`
- Mobile signs in with Google/Firebase.
- Home lets Basic users send an SMS OTP and link/verify a phone number through Firebase Phone Auth before the Basic free quota is unlocked.
- Mobile sends `Authorization: Bearer <Firebase ID token>`.
- Backend verifies Firebase token issuer, audience, expiry, subject, and signature.
- Backend reads `phone_number` from the verified Firebase ID token and treats that as phone verification.

## Security Notes

- Never store social access tokens as plain text.
- Scope every user-owned query by `userId`.
- Require authentication before issuing signed upload URLs or returning template
  and queue data.
- Verify Firebase ID tokens before trusting user identity.
- Require phone verification before granting the Basic free post quota.
- Verify RevenueCat webhook authorization before changing subscription state.
- Verify Google Play notification bearer authorization before changing subscription state.
- Keep legacy store receipt and notification verification enabled only for the legacy direct-store path.
- Use signed R2/S3 URLs or a controlled upload endpoint.
- Only allow post creation from upload keys owned by the authenticated user.
- Do not allow a scheduled job to publish another user's post.
- Keep cancel/reschedule actions synchronized with the backing publish queue so
  stale jobs cannot publish at the old time. Queue handoff failures return
  `503 PUBLISH_QUEUE_UNAVAILABLE` instead of letting the post store advance
  ahead of the queue.
- Keep secret keys in environment variables, not source files.

## Scaling Strategy

PostDee scales the existing modular monolith before introducing distributed
architecture. Stateless API instances can scale horizontally only after the
production publish queue moves from process memory to BullMQ, rate limits are
shared through Redis, Prisma connections are bounded, and shutdown is graceful.
Heavy AI, publishing, notification, and analytics work moves to isolated worker
pools so one workload cannot delay scheduled publishing.

The planning gates are approximately 100, 1,000, 10,000, and 100,000 active
users, but registered-user count never triggers an upgrade by itself. Every gate
uses measured concurrency, latency, memory, database, queue, provider, and
recovery evidence. PostgreSQL query aggregation, rollups, read replicas, and
retention come before sharding. Kubernetes, active-active multi-region writes,
and broad microservice decomposition are deferred until evidence requires them.

See `docs/superpowers/plans/2026-07-17-scaling-roadmap.md` for the
milestone-specific code, infrastructure, mobile, testing, and documentation
tasks.
## Testing Strategy

Backend checks:

```powershell
cd apps/api
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npx.cmd prisma validate --schema prisma\schema.prisma
```

Mobile checks:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

## Current Limits

- Social platform publishing defaults to mock. The PostPeer path is wired, but
  production must use per-user social connections and a real provider-level
  publish test before user publishing is enabled. A new identity is ensured in
  the local `User` store before its provider profile is saved, and the required
  PostPeer profile name is stable and pseudonymous. Controlled-first requests
  use YouTube `private` and TikTok `SELF_ONLY` direct posting. Shared
  `POSTPEER_*_ACCOUNT_ID` values are rejected in production. The internal
  `FACEBOOK_REELS` key always requests Facebook Page Reels using PostPeer
  `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`; a
  missing video fails before submission, with no fallback to a Page feed video.
  Real connected-account E2E is still pending.
- New PostPeer profile names carry a versioned 128-bit HMAC suffix. Legacy
  40-bit profile recovery is disabled by default and can target only one
  operator-approved Firebase user/profile pair through a full HMAC fingerprint
  plus exact provider profile id. Profile pagination, uniqueness, name, and id
  must all validate before the recovered mapping is persisted. The
  `PostPeerProfile.profileId` database unique constraint is the final atomic
  ownership boundary. The first mapping remains authoritative during same-user
  races, while cross-user claims fail without returning ownership details.
- The publish worker checks the durable account-deletion barrier, then claims
  only `QUEUED` posts before calling PostPeer or the
  mock publisher. Jobs for posts already `PUBLISHING`, `PUBLISHED`,
  `PARTIAL_PUBLISHED`, or `FAILED` are skipped to avoid duplicate provider
  calls. Scheduled jobs whose `runAt` no longer matches the post's current
  `scheduledAt` are skipped after reschedules, and optional R2/S3 cleanup
  failures are reported in the worker result without changing a successful post
  to `FAILED`.
- The managed PostPeer mobile connection trial uses an Android
  `CustomTabsIntent` through a small platform channel for HTTPS authorization
  URLs, with external-browser fallback and no embedded WebView fallback. Other
  platforms retain the external-browser flow. A pending mobile attempt is
  bound to its starting auth session; returning from the background triggers
  the existing authenticated profile-integration refresh. Manual refresh
  remains available. No mobile deep-link completion contract or automatic
  browser-to-app redirect is added. This does not establish ownership of a
  forwarded connect link or guarantee native social-app handoff; physical
  device checks remain pending. See
  `docs/superpowers/plans/2026-10-25-postpeer-mobile-connection-trial.md`.
- Direct social OAuth/token storage and direct platform publishing are not
  implemented; the production path still uses PostPeer. TikTok native-first
  authorization is a proposed design pending developer registration, sandbox
  setup, verified app/universal links, and subsequent implementation. No native
  social SDK, service seam, or native completion endpoint is added by this
  proposal. Server-side encrypted token lifecycle, owner/deletion
  fences, publishing permissions and device E2E are required before activation;
  see `docs/superpowers/plans/2026-10-21-tiktok-native-connection.md`.
- Per-platform disconnect is provider-first and user-scoped: PostPeer must
  confirm the saved integration is gone before the local connection row is
  removed. Missing integrations are idempotent; provider failures keep local
  state so later refreshes cannot silently recreate a supposedly disconnected
  account.
- Real Gemini calls require credentials and provider testing.
- Real-clip AI captioning supports the configured Gemini path and a legacy
  transcription-backed path. Mobile extracts and uploads selected visual
  frames for Pro; real-device/provider testing and production migration
  verification for the Prisma usage ledger remain.
- Legacy AI Clip Review internals have been removed; only false compatibility
  fields remain for older clients.
- Pro AI auto editing has minute-metered prepare recipes and recoverable local
  review/render states, but still needs persistent job/session recovery, top-up
  handling, and real-device export/review testing.
- Legacy and managed multipart R2 disposable-account API smoke tests were
  recorded as passing. Full mobile-to-worker and slow-network verification
  still remain; the source review does not revalidate live credentials.
- Redis/BullMQ scheduling needs infrastructure testing.
- Firebase Android Debug Staging Google auth passes end to end; Phone Auth,
  Production/iOS capability setup, and physical-device testing remain.
- RevenueCat Test Store products/entitlements/current offering and authenticated
  webhook transport are configured; purchase and true Restore/resync E2E pass on
  the Android Emulator with a Firebase UID after the Render Staging key was set.
  RevenueCat also has the Play Store app/products/entitlements/default offering
  and production Android public SDK key, and a signed AAB is ready. Play Console
  app/subscriptions, internal testing, Google service credentials, real Google
  Play purchase, lifecycle tests, and physical Android verification remain. Play
  Console requires a physical Android device for account verification and does
  not accept an Emulator. The legacy direct store verifier remains a scaffold.
- Analytics does not yet fetch real platform metrics.

## Recommended Next Steps

1. Verify Play Console access with a physical Android device, then create the
   Play app/subscriptions, service credentials, and internal-testing track.
2. Upload the signed AAB and test RevenueCat purchase and restore through Google
   Play internal testing.
3. Complete the matching App Store product and platform-key setup.
4. Test RevenueCat renewal/cancel/refund webhook delivery from sandbox events.
5. Keep the legacy store notification scaffold covered, but do not make it the
   preferred production billing path.
6. Expand RevenueCat notification event coverage from sandbox evidence.
7. Run the `RealClipCaptionUsage` migration in staging/production and set
   `CAPTION_USAGE_STORE=prisma` before selling paid AI caption quotas.
8. Harden Pro Groq Whisper job/session persistence, top-up, retry/recovery, and real-device review/export states.
9. Test Firebase Google Sign-In and Phone Auth on real Android/iOS devices.
10. Test video picker and 9:16 preview on real devices.
11. Connect disposable per-user PostPeer accounts and run the full controlled
    upload → publish → polled result → `GET /posts.platformResults` E2E for each
    advertised capability before enabling social publishing.
