# ARCHITECTURE.md

Architecture overview for the PostDee mobile app and backend scaffold.

## Product Goal

PostDee helps Thai e-commerce sellers, affiliate marketers, and creators upload one vertical 9:16 video and publish or schedule it across multiple short-form platforms from one app. The product should remain Thai-first for the initial launch while keeping the architecture global-ready for other countries, languages, currencies, timezones, phone formats, billing markets, and compliance requirements.

Target platforms:

- TikTok
- YouTube Shorts
- Instagram Reels
- Facebook Page Video through PostPeer (the internal compatibility value remains
  `FACEBOOK_REELS`; Reels are not currently supported by this provider path)

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
  API --> Queue["Upstash Redis / BullMQ"]
  API --> Captions["Real-Clip Caption Provider"]
  API --> Editing["ElevenLabs + Gemini AI Auto Editing"]
  Queue --> Worker["Publish Worker"]
  Worker --> Social["PostPeer API (Unified)"]
  Worker --> Storage
  Worker --> DB
  API -.-> PlannedSentry["Sentry (planned)"]
  Worker -.-> PlannedSentry
```

Production และ Staging ต้องเป็นคนละ data boundary: `render.yaml` ชี้ไป
`postdee-api`/`postdee-postgres` ส่วน `render.staging.yaml` ชี้ไป
`postdee-api-staging`/`postdee-postgres-staging` และต้องใช้ R2, Firebase,
RevenueCat และ PostPeer ชุดทดสอบแยกกัน รายละเอียดอยู่ใน `docs/STAGING.md`
Android Debug เพิ่ม suffix `.staging` และใช้ `src/debug/google-services.json`;
Profile/Release ยังคงใช้ Firebase Production จึงห้ามผสมกับ Staging Dart defines

## Backend Runtime Dependency Boundary

The backend imports `firebase-admin/app`, `firebase-admin/auth`, and the root
messaging API for Firebase Auth and FCM. It does not use the optional Firestore
or Google Cloud Storage clients; persistent application data remains in Render
PostgreSQL through Prisma and video media remains in Cloudflare R2.

CI keeps optional native packages during build and test, but its production
audit excludes unused optional packages. Render keeps the same build-time
packages through Prisma migration and prunes development plus optional packages
before the API starts. This avoids removing platform-native build tools too
early while keeping unused Firebase clients out of the running service.

## Mobile App

Path:

```text
apps/mobile
```

Current mobile pieces:

- Light and dark Flutter themes; light is the current default.
- Home dashboard with total views, total likes, subscription status, Basic Phone OTP verification, and Starter/Pro CTAs.
- Universal uploader screen with 9:16 metadata validation, explicit platform
  selection, and progressive settings: a selected row shows one outcome summary;
  detailed TikTok/YouTube/Instagram/Facebook controls open only in that
  platform's bottom sheet. Review shows the connected account/channel/page and
  requested outcome for every selected destination; missing identity, incomplete
  settings, or an unknown outcome disables confirmation.
- Calendar tab refreshes only while visible, polls queued/publishing posts every
  30 seconds, displays terminal posts by their actual publish time, and opens
  completed results read-only.
- Upload AI caption entry point after a video is selected.
- AI editing advanced settings use a single-open accordion. Beat sync remains
  visible but locked as `เร็ว ๆ นี้` in production; internal QA can expose its
  setup-only controls with `ENABLE_EXPERIMENTAL_BEAT_SYNC=true`.
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
- `PostDeeApiAuthHeaders` sends Firebase bearer tokens when available. The
  production Firebase source returns the live UID and token in one credential
  snapshot; the session store rejects it if the UID differs from the stable
  session owner or changes while the async refresh is running.
- Without Firebase auth, the app falls back to local mock headers.
- `PostDeeAuthSessionStore` stores the active mobile auth session.
- Home uses the legacy `POST /billing/store/verify` path by default for local
  scaffold runs, and can use RevenueCat `purchases_flutter` when
  `ENABLE_REVENUECAT_BILLING=true`; entitlements are then updated by
  `POST /billing/revenuecat/webhooks`. A user-initiated Restore first calls the
  RevenueCat SDK, then the authenticated `POST /billing/revenuecat/resync` route
  to reconcile the server subscription store.

Global readiness principles:

- Store user-facing copy through localization-ready structures instead of hard-coded Thai-only strings when a screen is redesigned.
- Use user locale and timezone for schedules, analytics dates, and billing display.
- Keep prices and plan names provider-neutral so App Store and Google Play can map products per country.
- Accept international phone number formats for Firebase Phone Auth.
- Keep country-specific legal, tax, platform-policy, and privacy requirements behind explicit launch checklists before opening each market.

Design system:

- Background: `#000000`.
- Cards: dark charcoal such as `#121212`.
- Minimal, professional, dark UI.
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
- Prisma
- PostgreSQL schema (Render)
- Upstash Redis/BullMQ adapter (not enabled in the current single-instance deployment)
- Cloudflare R2 video storage and managed multipart adapters
- Firebase ID token verifier
- Firebase Cloud Messaging (FCM) sender
- Gemini caption provider with production provider/device verification remaining
- ElevenLabs Scribe v2 transcription + Gemini AI auto-editing recipe flow with physical-device acceptance remaining
- RevenueCat webhook and authenticated Restore/resync adapters
- Sentry error tracking is planned; it is not integrated yet

Main route groups:

- `GET /health`
- `GET /publishing/readiness`
- `GET /auth/me`
- `POST /uploads`
- `POST /uploads/:uploadId/parts/:partNumber`
- `POST /uploads/:uploadId/complete`
- `GET /uploads/:uploadId`
- `DELETE /uploads/:uploadId`
- `GET /posts`
- `POST /posts`
- `PATCH /posts/:id`
- `POST /posts/:id/publish-now`
- `DELETE /posts/:id`
- `POST /captions/generate`
- `GET /ai-edits/quota`
- `POST /ai-edits/transcribe`
- `POST /ai-edits/prepare`
- `POST /ai-edits/plan`
- `GET /templates`
- `POST /templates`
- `GET /analytics/summary?range=today|7d|30d|90d|year`
- `GET /billing/subscription`
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
- `Post`: server-side queued/publishing/result lifecycle record with caption,
  platforms, optional schedule time, an immutable `platformSettings` snapshot,
  and an internal/redacted `platformTargets` snapshot. It has no local-draft
  API contract; the older Prisma `DRAFT` enum value is normalized to `QUEUED`.
- `Template`: reusable text snippets.
- `PlatformPublish`: per-platform publish/analytics record with public
  `deliveryOutcome` (`LIVE|PRIVATE|UNLISTED|DRAFT`) and internal/redacted
  `providerPostId`.
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

Migration `20260811130000_add_platform_publish_configuration` adds the nullable
Post snapshots and PlatformPublish outcome/provider-id fields. Null keeps old
rows readable: legacy posts normalize to the historical direct/private/publish
defaults, while old platform results keep the old status UI because their exact
delivery visibility cannot be reconstructed.

## Adapters And Stores

| Feature | Local/Mock | Production path |
| --- | --- | --- |
| Templates | `TEMPLATE_STORE=memory` | `TEMPLATE_STORE=prisma` |
| Publish drafts | App-owned Application Support files scoped by stable authenticated user ID | The same local-only store; no backend record or cross-device sync |
| Posts | `POST_STORE=memory` | `POST_STORE=prisma` |
| Subscription | `SUBSCRIPTION_STORE=memory` | `SUBSCRIPTION_STORE=prisma` |
| Analytics | `ANALYTICS_STORE=memory` | `ANALYTICS_STORE=prisma` |
| Queue | `PUBLISH_QUEUE=memory` | `PUBLISH_QUEUE=bullmq` (Upstash) with `POST_STORE=prisma` and `DATABASE_URL` |
| Video storage | `VIDEO_STORAGE=mock`, `UPLOAD_PROTOCOL_MODE=legacy` | `VIDEO_STORAGE=r2`, with `UPLOAD_PROTOCOL_MODE=dual` during rollout and strict `multipart` after old clients are retired |
| Captions | `CAPTION_PROVIDER=mock` | Real-clip caption provider using backend AI |
| Caption usage | `CAPTION_USAGE_STORE=memory` | `CAPTION_USAGE_STORE=prisma` |
| AI auto editing | `TRANSCRIPTION_PROVIDER=mock` | ElevenLabs Scribe v2 transcribes; `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite` plans from visual proxy/transcript with structured JSON and provider-default sampling (no explicit `temperature`); PostDee rules are the final fallback; FFmpeg export stays on mobile |
| Auth | `AUTH_PROVIDER=mock` | `AUTH_PROVIDER=firebase` |
| Billing | `BILLING_PROVIDER=mock` | `BILLING_PROVIDER=revenuecat` |
| Social publishing | Local uses `mock`; initial Staging uses fail-closed `disabled` | `SOCIAL_PUBLISHER=postpeer` with per-user social connections and signed R2/S3 media URLs; `FACEBOOK_REELS` currently targets Facebook Page Video; shared `POSTPEER_*_ACCOUNT_ID` values are rejected in production |

The authenticated `GET /publishing/readiness` route is deliberately only a
configuration gate: `acceptingPosts: true` means the API process is not using
`SOCIAL_PUBLISHER=disabled`. It does not probe the provider, storage, queue,
separate worker, or a user's connections. Post create, reschedule, and the
publish-now command repeat the gate at their mutation boundaries; cancellation
remains available. Both its
accepting `200` and disabled `503` responses use
`Cache-Control: private, no-store`. This prevents storing either readiness result
but does not prove that caching caused a previous mismatch.

Staging also opts into `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true`. When the
single-process memory scheduler is paired with `SOCIAL_PUBLISHER=postpeer`, its
async start performs one atomic global aggregate Prisma `count` with status in
`QUEUED` or `PUBLISHING` before creating the polling timer or opening the HTTP
listener; future schedules are included. A non-zero total or query error fails
closed with no post, owner, caption, or media data loaded or logged. The flag
defaults to `false`, is rejected with BullMQ because it cannot guard a separate
worker, and does not change the Production Blueprint.

The API entry point parses `ServerConfig` once and passes the same object into
`createApp` and the scheduler-start diagnostics, avoiding two independent
environment reads during one process startup. Before the scheduler starts it
logs only `mode`, `publisher`, and `emptyBacklogGuard`; no credential, post, user,
caption, or media value is included. When the PostPeer empty-backlog guard is
enforced, the explicit guard-pass log is written only after `scheduler.start()`
resolves. A missing pass log is not success, and this instrumentation does not
retroactively prove that a previously deployed process ran the guard.

Production account deletion is temporarily disabled with
`FIREBASE_AUTH_DELETE_ENABLED=false`. A controlled environment that enables the
path additionally requires `FIREBASE_SERVICE_ACCOUNT_JSON`; the API then uses
Firebase Admin token verification with revocation checks.

Account deletion is an idempotent cleanup saga, but is not yet production-safe.
Its durable managed-upload owner marker is set first, while the process-local
owner coordinator serializes authenticated API mutations and RevenueCat webhook
application within one API process. A mutation already running in another API
process can pass the durable-marker check before deletion starts and commit
afterward. The publish worker atomically claims a due post before
checking the marker and calling a provider, without a lease spanning that call.
The Production feature remains off until this incomplete mutation boundary and
the remaining device/slow-network cleanup gates are closed.
Queued jobs are then removed and PostPeer
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
    U->>M: Scrub to a frame and style Thai cover text
    M-->>M: Render a 1080x1920 JPEG
  end
  opt User saves a local draft
    M-->>M: Copy video, optional cover, and manifest to Application Support / stable UID
    M-->>U: Saved locally; no publish API, R2, provider, queue, or quota mutation
  end
  U->>M: Explicitly select destinations
  M-->>U: Reveal one settings summary; open only the selected platform sheet
  M-->>U: Review exact requested outcome for every selected platform
  U->>M: Confirm publish
  M->>A: GET /publishing/readiness
  break SOCIAL_PUBLISHER is disabled
    A-->>M: 503 SOCIAL_PUBLISHING_UNAVAILABLE
    M-->>U: Thai unavailable message; stop before upload
  end
  A-->>M: 200 acceptingPosts=true
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
  opt Instagram or Facebook uses the custom cover image
    M->>A: POST /uploads for JPEG/PNG cover
    M->>S: Upload rendered cover image
  end
  M->>A: POST /posts + stable clientRequestId + complete platformSettings
  break Publishing was disabled after preflight
    A-->>M: 503 SOCIAL_PUBLISHING_UNAVAILABLE
    Note over M,S: Uploaded media remains temporary and needs cleanup
  end
  A->>A: Resolve/revalidate and persist internal platformTargets snapshot
  A->>A: Create or find durable owner-scoped QUEUED post
  A->>Q: Enqueue or repair publish job
  alt Queue handoff succeeds
    A-->>M: 201 new post or 200 idempotent replay + post/job
    opt This publish came from an active local draft
      M-->>M: Delete after accepted/recovered lifecycle response
    end
  else Queue unavailable
    A-->>M: 503; durable post remains for same-key repair
  end
  Q->>W: Run job immediately or at scheduled time
  W->>A: Revalidate current connection against target snapshot
  W->>P: Publish to selected platforms
  opt Cleanup enabled or storage lifecycle policy
    W->>S: Delete temporary video and cover after success
  end
  W->>A: Record publish/analytics result
```

Rules:

- Mobile checks `GET /publishing/readiness` after confirmation and before
  watermarking or uploading. A disabled response is shown in Thai and stops the
  client-side flow.
- `acceptingPosts: true` is only a configuration signal. It does not prove that
  PostPeer, R2/S3, the queue/worker, or every selected account is operational.
- `POST /posts` and `PATCH /posts/:id` return
  `503 SOCIAL_PUBLISHING_UNAVAILABLE` before upload-readiness, quota, post-store, or
  queue mutations when publishing is disabled. `DELETE /posts/:id` remains
  available so users/operators can cancel old queued or scheduled records.
- Old clients do not run the preflight, and a configuration change can race a
  new client after its preflight. Media uploaded before the authoritative `503`
  is not deleted by the post route and must be covered by temporary-object
  cleanup.
- Basic users can create real-time posts only.
- Basic users must verify a phone number before using the free quota.
- Basic users are limited to 3 post units per month after phone verification.
- Starter and Pro can schedule posts up to 30 days in advance. The mobile date
  picker and post API enforce the same limit. The API accepts only calendar-valid
  RFC 3339 timestamps with `Z` or `±HH:mm`, normalizes them to UTC, and rejects
  past, timezone-free, or malformed values for create and reschedule requests.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Post units count unique selected platforms, not post rows. Duplicate platform
  values are collapsed, and the monthly-unit check plus post insert is atomic
  (a serializable Prisma transaction in the persistent store).
- Upload metadata is capped by `UPLOAD_MAX_SIZE_BYTES`. Managed multipart part
  sizes are selected by the server, and a post can reference the key only after
  its session reaches `COMPLETED`.
- Cover fields are optional. The post, queue, scheduler, and worker carry
  `coverImageS3Key` and `coverFrameTimeMs` only after the seller saves a cover.
  Both storage keys remain owner-scoped and must be completed before queueing.
- Managed cover uploads accept JPEG or PNG up to 2 MiB. Mobile avoids uploading
  an unused image for TikTok/YouTube-only posts.
- Platform adapters send only supported controls: Instagram uses the signed
  image or frame offset, Facebook Page Video receives the signed image, TikTok
  receives the frame time, and YouTube Shorts receives no custom thumbnail.
- New clients opt in with `multipart-v1`. `UPLOAD_PROTOCOL_MODE` defaults to
  `legacy`; production uses `dual` during rollout, and moves to strict
  `multipart` only after old clients are retired.
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
- Starter unlocks real-clip AI captioning from audio.
- Pro unlocks analytics, hashtag radar, AI comment center, team/editor access,
  AI captioning from audio plus selected frames, and ElevenLabs + Gemini auto
  editing.
- A PostPeer `202 pending/publishing` response stays inside the publisher until
  `GET /v1/posts/{postId}` reaches a terminal result or the roughly two-minute
  bounded poll expires. Success requires a real platform URL/id; no synthetic
  external id is stored.
- `GET /posts` joins each authenticated user's posts with their persisted
  `platformResults`, including partial and failed platform outcomes.
- Mobile presents the returned post lifecycle without upgrading it to success:
  `QUEUED`, `PUBLISHING`, `PUBLISHED`, and `PARTIAL_PUBLISHED` have distinct
  messages; an unknown status retains the local draft and blocks a success view.
  Recovered requests are labelled as the existing item.
- Per-platform `deliveryOutcome` separates `LIVE`, `PRIVATE`, `UNLISTED`, and
  `DRAFT`. Internal `PUBLISHED` means the requested delivery was confirmed; it
  does not imply public visibility. Existing null outcomes fall back to legacy
  status wording.
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
  M->>RC: Request purchase
  RC->>Store: Process payment
  Store-->>RC: Receipt/Token
  RC-->>M: Entitlement unlocked
  RC->>A: POST webhook with event id + timestamp
  A->>DB: Atomically advance cursor + apply subscription
```

Actionable RevenueCat events require `id` and `event_timestamp_ms`. PostgreSQL
stores the latest per-user cursor in the same serializable transaction as the
subscription change; retries and older events are acknowledged without
overwriting newer entitlement state.

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
  RC-->>A: Entitlements, expiry, request_date_ms
  A->>DB: Atomically advance cursor + reconcile subscription
  A-->>M: Current subscription
```

The mobile app never receives `REVENUECAT_REST_API_V1_KEY`. The API derives the
RevenueCat app user id only from the authenticated Firebase user, prefers Pro if
both paid entitlements are active, and leaves the existing plan unchanged if the
provider lookup fails. Zero active RevenueCat entitlements deactivates only the
matching RevenueCat-backed record. Active but unmapped access returns a
configuration error and does not downgrade the user. Webhooks and subscriber
resync share the same per-user serializable cursor, so a stale snapshot cannot
undo a newer lifecycle event. Equal millisecond timestamps are non-newer. When
RevenueCat omits `request_date_ms`, the API falls back to local receipt time;
server clock skew remains an operational risk and clocks must stay synchronized.

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

Current local mode has two caption routes:

- `POST /captions/generate` remains the legacy keyword scaffold, but paid users still spend monthly AI caption quota and each keyword is capped at 80 characters.
- `POST /captions/generate-from-clip` is the implemented clip-first flow with
  Starter audio-only mode, Pro audio plus selected-frame mode, SEO fields, hook
  ideas, transcription-backed language/market context, authenticated media-key
  ownership checks, opt-in cleanup for AI-only clip/frame uploads, and monthly
  quota reservation through memory or Prisma-backed usage storage.

The clip-first route now reuses the configured transcription provider for
spoken-language detection. Local mode uses a mock Thai transcript; production
can use ElevenLabs/OpenAI by downloading the stored clip through signed storage
access. The route still does not sample real frames. The mobile app keeps
language and market selection automatic; provider-level R2/ElevenLabs clip testing is
still required. User text can remain as optional guidance after clip selection,
not as the main sold feature. Production can use a backend AI provider such as
Gemini with:

```env
CAPTION_PROVIDER="gemini"
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
GEMINI_API_KEY="..."
```

The configured primary caption model retries transient failures, then falls
back directly to the existing local template; no secondary Gemini model is
attempted.

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
captioning or Pro ElevenLabs + Gemini auto editing.

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

## AI Auto Editing With ElevenLabs + Gemini Flow

```mermaid
sequenceDiagram
  participant M as Mobile
  participant A as API
  participant Sub as Subscription Store
  participant W as ElevenLabs Scribe v2
  participant G as Gemini 3.5 Flash-Lite
  participant F as Mobile FFmpeg

  M->>A: POST /ai-edits/transcribe or /ai-edits/prepare
  A->>Sub: Check Pro plan and editing minutes
  alt User is Pro with minutes
    A->>W: Transcribe audio with word + segment timestamps
    W-->>A: transcript + word timing + segment timing
    alt /ai-edits/transcribe
      A-->>M: transcript + quota
    else /ai-edits/prepare
      A->>G: Plan transcript and visual proxy with structured JSON (no explicit temperature)
      G-->>A: coherent target-length story window
      A-->>M: mobile render recipe + transcript + quota
      M->>F: Render adaptive lightweight preview from original clip
      F-->>M: reviewable MP4
      M-->>M: Stay on AI review and toggle supported edits off or back on
      M->>F: Automatically re-render preview from original clip after each toggle
      alt User chooses Post
        M->>F: Render full-source-dimension export
        F-->>M: publishable MP4
        M-->>M: Open Upload/Post with full-quality result
      else User chooses more editing
        M-->>M: Open manual editor with latest result
      end
    end
  else Basic or Starter
    A-->>M: 402 PRO_REQUIRED
  end
```

Mobile preflights the current subscription before creating an AI-edit upload.
Basic/Starter users receive the Pro message locally and no `POST /uploads`, R2
transfer, or metered prepare request is started. The API Pro check remains the
authoritative security boundary for stale or modified clients.

The core Pro flow is implemented. For current audio-driven capabilities, mobile
extracts mono 16 kHz/64 kbps AAC into balanced temporary M4A chunks no longer
than 30 seconds and uploads only those files with the narrow `ai-edit-audio`
purpose. Balanced chunking avoids a very short final request while keeping every
part within the speech provider's short audio context. Backend validates ownership of every
chunk, transcribes them sequentially, and shifts local timing back onto the
source timeline. If a segment or word would need to be clipped or dropped at a
chunk boundary, the complete merged timeline becomes untrusted and cannot
authorize planning or cuts. A trusted merged transcript is metered once, and
the backend cleans
all temporary audio even after a partial failure; the untouched original video
remains local for rendering. Legacy single `audioS3Key` and `videoS3Key`
requests remain supported, and legacy videos are not automatically deleted.
`POST /ai-edits/prepare` combines the AI editing UI
capability toggles, selected style/prompt, transcript, cut plan, overlay hints,
and quota into one mobile render recipe. The API pre-checks estimated duration,
then derives `analysisOutcomes` from the actual plan, subtitle, silence, and
repeated-speech results. A pure usage policy reserves the transcribed minutes
only when at least one requested outcome succeeded; unavailable-only results do
not consume minutes, while a completed safe silence analysis succeeds even with
no candidate. The reservation remains atomic and occurs immediately before the
successful response, so concurrent requests cannot exceed the monthly limit.
Explicit empty and colour-only API requests are rejected before provider work.
Color-only edits at original duration render locally for Pro users and do not
consume AI editing minutes. After the local Pro entitlement check, the official
mobile client selects
`localRenderOnly` only when colour adjustment is the sole enabled capability and
the original duration is retained. It builds a cut-free full-duration recipe and
renders the original source without audio extraction, upload,
`/ai-edits/prepare`, or quota mutation. Colour plus a shortened target or any
audio-dependent capability remains on the normal API route, while any unknown
enabled capability fails closed before side effects. Requests from legacy
clients that omit the capability field remain metered for backward
compatibility. Mobile setup owns the optional-capability selection state: every
supported switch starts off and only explicit user selections are sent as
enabled. A no-capability request is still meaningful for target-length-only
shortening. Review summaries and local processors must gate provider detections
by the matching selected capability so data returned for one analysis cannot
silently activate another edit. Mobile caches that successful recipe and maps its
subtitle segments and source-timeline cuts into a versioned local
`SubtitleProject`. Separately, `mapAiEditTimelineEvidence()` reads repaired
`transcript.boundarySegments` for sentence alignment and builds conservative
protected-speech ranges from valid raw segments, global words, and validated
segment words. It never substitutes raw provider segments for missing boundary
evidence. Mobile renders a lightweight preview and opens result review
first. Subtitle Studio opens only from the explicit review action:
it restores an exact source/setup draft from app-owned storage, previews edits
with a Flutter overlay, and supports cue editing plus whole-clip style changes
without rerendering. Confirmation sends the corrected source-timeline cues and
style to FFmpeg; cancelling leaves the draft available and does not start a
render. Thai word timestamps that degrade into character fragments are
rebuilt from reliable segment text with `Intl.Segmenter`; their timing remains
bounded by the provider segment. Subtitle fragments below 0.7 seconds are
joined only across a nearby gap. Mobile keeps unspaced Thai phrases intact and
auto-fits the live preview rather than cutting a word or showing an ellipsis.
Before prepare, the subtitle setup uses a paused `VideoPlayerController` to show
one real frame from the selected source. Scrubbing changes only local preview
state; it creates no JPEG, is not uploaded, and is not a cover choice. Subtitle
position is stored as normalized centre X/Y and can be changed by dragging in
both setup and Subtitle Studio. Legacy top/middle/bottom drafts map to
`(.5,.12)`, `(.5,.5)`, and `(.5,.88)` only when normalized coordinates are
absent.
Review checkboxes automatically
re-render from the original clip when supported edits are removed or restored,
without another metered prepare request. The last successful preview remains
available if a new render fails. The user can then continue either to
Upload/Post or the manual editor. Mobile handles FFmpeg
subtitle burn-in, supported visual adjustments, and final MP4 export. Mobile
names an output `_subtitled.mp4` only when actual subtitle content is present;
otherwise the neutral output suffix is `_edited.mp4`. Mobile
keeps the setup's pending source separate from the accepted active source. The
active source/duration, recipe, silence verification, subtitle project,
capabilities, selected repeat occurrences, and rendered result are committed
atomically only after a render succeeds. Review, Subtitle Studio, retry, and
export read only that accepted set, so a failed render for a new source leaves
the previous result coherent and available. A local colour retry repeats only
the phone-side render and follows the same source A/source B atomicity rule.
Output codec, FPS, file size, audio peak, and A/V sync still require fresh
device-matrix evidence and are not recorded as completed renderer guarantees.

Transcript gaps are silence candidates only. The Android/iOS client confirms
each candidate against the source waveform before rendering; failed or
ambiguous verification keeps the original audio. Mobile runs FFmpeg
`silencedetect`, intersects candidates with waveform silence, applies padding,
rejects source edges and protected speech, and forwards only verified ranges to
all local render paths. Successful verification, including an empty result, is
cached by source fingerprint and timing evidence; failed probes are not cached.
Retry runs only the waveform verifier and local renderer—never transcription,
upload, `/ai-edits/prepare`, or another quota reservation. Capabilities marked
`planned` or unverified `hinted` candidates are not shown as already applied.

Two independent build-time rollback flags provide a fail-safe. Disabling
verified silence removes its effective capability, verifier, and final cuts.
Disabling automatic repeat cuts preserves detected groups as read-only evidence
but empties selected occurrence IDs and blocks structured and legacy repeat cuts
at the renderer boundary. Neither rollback changes subtitle, target-length, or
colour behavior.
The official client reports source duration as `durationSeconds` for quota
preflight and media timeline recovery. Prepare uses the longer available
client/provider duration for planning, recipe duration, and quota reservation,
while preserving provider word/segment endpoints. This is correct for the
current first-party app but is not a tamper-resistant server measurement; a
server-side M4A/MP4 duration probe and API 600-second ceiling remain public
release gates. Mobile accepts sources up to 10 minutes and sends a
slider-selected shortened result from 5 seconds up to 3 minutes (or from 1
second for a source under 5 seconds) separately as `targetDurationSeconds`;
mobile omits it when the slider is at “keep original”. The first successful prepare stores its transcript in
the current mobile editing session. A duration-only change calls the non-metered
`POST /ai-edits/plan` with that cached transcript instead of uploading and
transcribing audio again. The planner rejects known prompt leakage and low-quality
provider segments, scores seller-oriented signals such as hook, benefit, proof,
offer, and CTA, then returns one continuous target-length story window as
complementary cut ranges.
For a result shorter than the transcript, mobile creates a whole-duration visual
proxy rather than a sparse frame set: 360 px H.264 at 1 fps plus mono 16 kHz AAC.
The proxy is purpose-limited to 50 MiB, user-owned in R2, downloaded once by the
API, uploaded to Gemini Files API, and paired with timestamped transcript
segments. `gemini-3.5-flash-lite` therefore sees the full clip timeline and
audio before choosing cuts. Both transcript and visual GenerateContent requests
require structured JSON and use provider-default sampling without
`generationConfig.temperature`. The API falls back to Gemini transcript planning
if visual download, upload, processing, or generation fails; if Gemini itself is
unavailable, deterministic PostDee rules produce the final plan. The original
source remains on device and is always used for preview/full-quality rendering.
Mobile retains one local proxy for the current source so duration-only replans skip FFmpeg proxy
extraction; replacing/removing the source or leaving the screen deletes it.
Gemini and R2 copies remain request-scoped. Gemini file upload, status polling,
and deletion use the official `@google/genai` server SDK instead of maintaining
a hand-written resumable upload contract. Visual and transcript planners apply
a soft penalty to Thai
continuation-fragment openings and may nudge a suggested window to a nearby
complete transcript boundary while preserving target length.
The recipe also omits those unreliable time ranges from user-facing subtitle
lines, including clearly unexpected mixed-script recognition noise, while
retaining their speech timing for conservative silence detection.
Mobile still applies a final target cap as a compatibility safety guard.
The target guard restores nearby context only within the AI story-plan cuts.
Validated silence and repeated-speech cleanup ranges stay immutable and are
unioned after story fitting, so a removed word can never return merely to fill
the slider target. This prevents incomplete transcript timing from turning a
slider request into a near-empty clip without sacrificing confirmed cleanup. A
separate transcript-boundary guard, independent of visible subtitle state,
detects when the leading target cut lands inside a repaired spoken cue, moves
the opening just before that cue with a small pre-roll, and balances the duration
at the trailing cut so the result stays near target without opening
mid-sentence. This alignment still runs when subtitles are off and sends no
visible subtitle segment to the renderer. Missing or rejected boundary evidence
keeps the planner story-window cut unchanged and produces a review warning;
mobile does not infer a replacement boundary from raw transcript segments.
Pre-roll is limited to the real subtitle-free gap, so adjacent cues cannot leak
a 0.15-second tail from the previous sentence. If the final visible cue ends in
a dangling Thai connector, mobile preserves the opening and all internal
AI/silence cuts, then moves only the trailing boundary to the earliest complete
phrase. The allowed semantic tail is 10% of target bounded to 1–3 seconds, and
the FFmpeg hard cap uses that same allowance. If no complete phrase fits, mobile
moves the tail before the dangling cue. The separate three-second hook feature
remains unchanged.
If transcription fails, the API returns the stable
`AI_TRANSCRIPTION_PROVIDER_FAILED` code with HTTP 502 before quota reservation;
provider internals are not exposed. Mobile translates that code into a Thai
retry message and leaves the setup available for another attempt.
The seller-facing production capability allowlist includes `subtitle`,
`silence`, `filler`, and `sfx`. The internal `color` renderer and `audio`
contract stay available for compatibility with older results, but both setup
cards are hidden and restored presets are forced off so no invisible edit can
run. SFX uses a dedicated AI planner over strict transcript boundaries. The
planner sees catalog metadata rather than audio assets and can return only an
allowlisted `soundId` plus a source-timeline anchor. Atomic server validation
produces the recipe `soundEffects` list and a separate SFX analysis outcome for
fair quota decisions. Unavailable analysis never falls back to a random sound.
Auto-reframe, zoom, audio cleanup, translation, price tags, CTA cards, and the
AI-page watermark remain `planned`.

A strict mobile catalog maps the ten PostDee procedural IDs to bundled 48 kHz
stereo WAV assets. Mobile fixes volume at 25%, converts source anchors through
the final merged cut timeline, drops anchors inside removed ranges, and includes
the resulting output placements in the render-cache signature. FFmpeg copies
the assets into its private workspace, delays and mixes them after the edited
source-audio timeline, applies a limiter, and encodes AAC. Preview, review
rerenders, and full export derive placements from the same accepted recipe.
Manual selection state and the Sound Effect Studio are not part of the product.
Physical Android/iPhone listening, level, and A/V-sync evidence remains a
release gate.
The AI header independently reads the authenticated monthly quota and replaces
that value with `prepare.quota` as soon as a metered recipe succeeds. Local
preview re-renders and manual quota refreshes do not call the metered endpoint.
Review renders are disposable adaptive previews: sources longer than 60 seconds
use a maximum 540 dimension, 20 fps, and 1 Mbps; shorter sources use a maximum
720 dimension, 24 fps, and 2 Mbps. FFmpeg writes processed-time progress to a
local file because Android completion/statistics callbacks are not reliable on
all devices. Mobile polls that file and treats its exact `progress=end` marker
as a lost-callback fallback, but accepts the result only after probing a real
video stream. The progress UI labels this final 99% probe as video verification
so the user can distinguish finalization from a stalled encoder. Entitlement
preflight stops waiting after 30 seconds. FFmpeg startup is considered stalled
only when there is no processed-time, terminal session, or exact `progress=end`
signal for 30 seconds in preview or 90 seconds in full export. It supports
cancellation and timeouts, and
caches identical successful renders for the current editing session. Entering
Upload/Post triggers a separate full-source-dimension render, so preview media
is never treated as the publishable export.
The renderer copies the selected bundled Thai-safe Bai Jamjuree, Prompt, or
Anuphan font into each subtitle render workspace and passes that directory plus
verified style values (font size, text/active-word/outline/shadow colours,
outline/shadow depth, fade/pop effect, and normalized centre X/Y) to libass.
Custom positions force ASS with `\\an5\\pos(x,y)` on every dialogue. A custom
position never silently retries through SRT, because that would lose the
seller-approved placement. Complete validated cue-word timing produces escaped
ASS active-word events; legacy placement without custom coordinates may still
use the static SRT compatibility path.
Subtitle files stay on the original source timeline and are burned before video
and audio keep ranges are compacted. A diagnostic SRT may therefore extend past
the shortened MP4 without indicating a timing bug; removed-range cues never
appear in the final output.
The API can prebuild one-, three-, and five-word subtitle variants from a single
validated transcript. Mobile keeps those variants in the current editing
session and selects the requested density locally. Presentation-only changes
(font, colours, outline, and normalized position) and density changes therefore
do not invoke the transcription provider or reserve another editing minute.
Server and mobile both fail closed unless timed words reconstruct the cue with
the same case and Unicode code points after only untimed separators are
removed. Media probes retry one unavailable native result, and rotated video
metadata is converted to display-oriented width/height before one-line fitting.
For silence cuts, video frames use the
selected keep timeline while audio keep ranges are reset and concatenated, so
both streams finish together after local preview re-renders.

Pace cleanup is an end-to-end recipe input. The backend first validates that
word timings cover the transcript text and timeline, then `silencePreset`
selects their minimum gap: `natural` = 1.0 s, `balanced` = 0.6 s, and
`compact` = 0.4 s. A complete reliable segment timeline is used only when safe
word evidence is unavailable. Leading and trailing gaps are excluded. Overlapping
ranges are merged before internal gaps are calculated. Provider Thai
character-level timings remain useful for gap detection, while subtitle text
falls back to segments instead of being split
into individual characters. Thai fallback segments that are long or contain
several words are rebuilt with estimated Thai word boundaries and capped at
two estimated words per cue.
all multi-token Thai recipe paths additionally enforce no more than five
semantic words and 20 graphemes per cue before mobile rendering, including
short-cue and tail merges. An indivisible single token may exceed the grapheme
ceiling to avoid cutting a brand name or URL in half; the server isolates it in
one cue and mobile measures real width before shrinking the preview/export
font. Provider fragments are expanded with Thai word segmentation and timing
is distributed across the original span without cutting through a word.
Mobile presents each cue on one subtitle line;
legacy two-line draft styles normalize to one line when loaded. The
transcription request carries no free-form PostDee spelling prompt because
real-clip validation showed provider context leaking
into transcript text. Optional segment-level log-probability, no-speech, and
compression signals are retained for highlight and rendered-subtitle quality
gating.
Whitespace-only provider tokens do not invalidate an otherwise complete timing
stream; malformed tokens containing transcript text still fail closed.
Missing or invalid silence preset values use `balanced`. Mobile exposes local
`AI เลือกให้` and `เลือกเอง` modes, but both send `speechReductionMode: auto`
instead of a fixed filler-word allowlist so they reuse the same AI analysis.
The API builds stable repeated-speech groups and occurrence IDs only from a
complete, trusted Thai word timeline. Adjacent repeated words/phrases can be
recommended for removal; distributed frequent words are reported but retained.
This timing-evidence path is separate from subtitle fallback: it reads provider
fragments in their original order and reconstructs a word only when exact NFC
text stays inside one reliable segment with internal gaps no greater than 0.15
seconds. The output range uses the first and last proven fragments; it never
sorts, estimates, crosses an unreliable segment, or bridges a timed audio event.
Punctuation remains a sentence barrier. Negation, emphasis marks, numbers/prices,
fragments that cannot be proven exact, sentence boundaries, and unsafe timing
fail closed and retain the original speech. Legacy `fillerWords`/`fillerRanges`
semantics remain available only for older clients.
AI mode starts from the API's `defaultCutRanges`; manual mode starts from an
explicit empty selection and ignores legacy-only filler cuts. Mobile stores
subsequent keep/remove choices by occurrence ID. It fits and aligns the AI
story-plan cuts first, sanitizes the matching source-timeline subtitle words,
and then unions protected silence/repetition cleanup ranges. A cleanup range is
never resized to restore target length, and a range that cannot be removed from
an enabled subtitle safely is not cut from audio/video either. The review shows
detected groups and selected occurrences without promising the exact final
duration savings.

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
Advanced capability controls use local accordion state with at most one section
open and no default expansion; this is presentation state only and is never sent
to the backend recipe.

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

When `ANALYTICS_STORE=prisma`, the backend can aggregate metrics from `PlatformPublish`.

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
- Mobile binds `Authorization: Bearer <Firebase ID token>` to the live Firebase
  UID observed in the same refresh. Upload separately checks the captured draft
  owner/session generation before and after remote boundaries; an account switch
  fails closed and stops the remaining upload/create-post flow.
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
  stale jobs cannot publish at the old time. Create intentionally commits a
  durable post before enqueue and repairs it on a same-key replay. Reschedule and
  publish-now use persisted compare-and-set transitions plus conditional rollback
  when queue replacement fails.
- The current owner/post locks are process-local maps. They coordinate current
  authenticated route mutations and RevenueCat webhook application inside one
  API process; they neither drain an in-flight mutation in another instance nor
  span the worker's external provider call. Before treating account deletion
  as production-safe—or enabling multi-instance/separate-worker publishing—add
  a durable repository owner barrier/lease or equivalent transactional
  outbox/claim-and-drain protocol. It must reject new writes and drain every
  in-flight user mutation before cleanup, with same- and separate-process tests.
- Keep secret keys in environment variables, not source files.

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
  publish test before user publishing is enabled. One controlled Staging
  YouTube Shorts Private immediate E2E passed on 2026-08-10; the other
  platforms, scheduling/recovery paths, and Production remain unverified. A new
  identity is ensured in the local `User` store before its provider profile is
  saved, and the required PostPeer profile name is stable and pseudonymous.
  Phase 2 explicit settings/target/outcome persistence exists, but TikTok direct
  remains legacy-only and blocked for new clients. Provider-draft, YouTube
  compliance/visibility, immutable-target, migration/backlog, and redaction E2E
  remain required. Shared
  `POSTPEER_*_ACCOUNT_ID` values are rejected in production. The internal
  `FACEBOOK_REELS` key currently means Facebook Page Video, not Reels.
- `render.yaml` currently selects `SOCIAL_PUBLISHER=postpeer` while broader
  connected-account E2E and Production verification remain pending. Repository
  configuration cannot prove the live Render value or provider health; resolve this fail-closed policy
  mismatch before launch. The publishing-readiness change does not modify the
  Production Blueprint.
- New PostPeer profile names carry a versioned 128-bit HMAC suffix. Legacy
  40-bit profile recovery is disabled by default and can target only one
  operator-approved Firebase user/profile pair through a full HMAC fingerprint
  plus exact provider profile id. Profile pagination, uniqueness, name, and id
  must all validate before the recovered mapping is persisted. The
  `PostPeerProfile.profileId` database unique constraint is the final atomic
  ownership boundary. The first mapping remains authoritative during same-user
  races, while cross-user claims fail without returning ownership details.
- The publish worker atomically claims only `QUEUED` posts, then checks the
  durable account-deletion barrier before calling PostPeer or the
  mock publisher. Jobs for posts already `PUBLISHING`, `PUBLISHED`,
  `PARTIAL_PUBLISHED`, or `FAILED` are skipped to avoid duplicate provider
  calls. Scheduled jobs whose `runAt` no longer matches the post's current
  `scheduledAt` are skipped after reschedules, and optional R2/S3 cleanup
  failures are reported in the worker result without changing a successful post
  to `FAILED`.
- This barrier check is fail-closed but is not a distributed lease around the
  provider call. A mutation already running in another API process, or account
  deletion racing after the worker check, can still cross a
  cleanup boundary. Production account deletion and multi-instance/separate-worker
  publishing remain blocked on the full mutation-drain design described above.
- Direct social OAuth/token storage is not implemented because the MVP
  production path uses PostPeer first.
- Per-platform disconnect is provider-first and user-scoped: PostPeer must
  confirm the saved integration is gone before the local connection row is
  removed. Missing integrations are idempotent; provider failures keep local
  state so later refreshes cannot silently recreate a supposedly disconnected
  account.
- Real Gemini calls require credentials and provider testing.
- Real-clip AI captioning can use the transcription provider for audio
  language detection, but still needs real R2/ElevenLabs clip testing, visual-frame
  inputs, production migration verification for the Prisma usage ledger, and
  provider-level testing.
- Legacy AI Clip Review internals have been removed; only false compatibility
  fields remain for older clients.
- Pro AI auto editing has minute-metered prepare recipes and recoverable local
  review/render states, but still needs persistent job/session recovery, top-up
  handling, and real-device export/review testing.
- Real R2 upload requires Cloudflare credentials and integration testing.
- Redis/BullMQ scheduling needs infrastructure testing.
- The publish-draft/replay path still needs physical Android/iPhone storage,
  restart, account-switch, backup, lost-response, truthful-status, schedule, and
  cleanup testing plus controlled Staging E2E. TikTok inbox/Facebook Page draft
  and target-change paths are not yet provider-verified. Remote upload orphan
  cleanup must be verified against R2.
- The in-app Privacy Policy and Terms are working drafts. Final reviewed/hosted
  text and matching Android Data Safety, iOS App Privacy, and OS-backup
  disclosures remain release gates.
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
8. Harden Pro ElevenLabs + Gemini job/session persistence, top-up, retry/recovery, and real-device review/export states.
9. Test Firebase Google Sign-In and Phone Auth on real Android/iOS devices.
10. Test video picker and 9:16 preview on real devices.
11. Connect disposable per-user PostPeer accounts and run the full controlled
    upload → publish → polled result → `GET /posts.platformResults` E2E for each
    advertised capability before enabling social publishing.
