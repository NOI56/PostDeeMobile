# ARCHITECTURE.md

Architecture overview for the PostDee mobile app and backend scaffold.

## Product Goal

PostDee helps Thai e-commerce sellers, affiliate marketers, and creators upload one vertical 9:16 video and publish or schedule it across multiple short-form platforms from one app. The product should remain Thai-first for the initial launch while keeping the architecture global-ready for other countries, languages, currencies, timezones, phone formats, billing markets, and compliance requirements.

Target platforms:

- TikTok
- YouTube Shorts
- Instagram Reels
- Facebook Reels

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
  API --> Auth["Firebase Auth & FCM"]
  API --> DB["PostgreSQL (Render)"]
  API --> Storage["Cloudflare R2 Video Storage"]
  API --> Queue["Upstash Redis / BullMQ"]
  API --> Captions["Real-Clip Caption Provider"]
  API --> Editing["Groq Whisper AI Auto Editing"]
  Queue --> Worker["Publish Worker"]
  Worker --> Social["PostPeer API (Unified)"]
  Worker --> Storage
  Worker --> DB
  API -.-> Sentry["Sentry Error Tracking"]
  Worker -.-> Sentry
```

## Mobile App

Path:

```text
apps/mobile
```

Current mobile pieces:

- Ultra-dark Flutter UI theme.
- Home dashboard with total views, total likes, subscription status, Basic Phone OTP verification, and Starter/Pro CTAs.
- Universal uploader screen with 9:16 metadata validation and platform toggles.
- Calendar tab for scheduled posts and refresh after scheduling.
- Upload AI caption entry point after a video is selected.
- AI captioning is gated by paid Starter/Pro status. Starter should use
  audio-only understanding from the selected clip; Pro can add selected visual
  frames.
- Legacy Clip Review UI, route, config, and internal mock/provider code have
  been removed from the active app path.
- Saved templates screen.
- Unified analytics screen gated by Pro status.
- Firebase/Google auth gateway scaffold with Firebase Phone Auth UI for Basic free quota verification.
- RevenueCat webhook scaffold for Starter and Pro entitlements, plus a legacy Store Subscription scaffold.

Important mobile services:

- `PostDeeApiClient` calls the backend.
- `PostDeeApiAuthHeaders` sends Firebase bearer tokens when available.
- Without Firebase auth, the app falls back to local mock headers.
- `PostDeeAuthSessionStore` stores the active mobile auth session.
- Home uses the legacy `POST /billing/store/verify` path by default for local
  scaffold runs, and can use RevenueCat `purchases_flutter` when
  `ENABLE_REVENUECAT_BILLING=true`; entitlements are then updated by
  `POST /billing/revenuecat/webhooks`.

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
- Upstash Redis/BullMQ scaffold
- Cloudflare R2 video storage scaffold
- Firebase ID token verifier
- Firebase Cloud Messaging (FCM) sender
- Gemini caption provider scaffold
- Groq Whisper AI auto editing scaffold
- RevenueCat webhook receiver scaffold
- Sentry error tracking integration

Main route groups:

- `GET /health`
- `GET /auth/me`
- `POST /uploads`
- `GET /posts`
- `POST /posts`
- `POST /captions/generate`
- `GET /templates`
- `POST /templates`
- `GET /analytics/summary`
- `GET /billing/subscription`
- `POST /billing/revenuecat/webhooks`
- `POST /billing/store/verify`
- `POST /billing/mock-success`
- `POST /billing/google-play/notifications`
- `POST /billing/apple/notifications`
- `GET /queue/jobs`

## Module Layout

```text
apps/api/src
  app.ts
  server.ts
  config
  modules
    analytics
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
- `Post`: queued video post with caption, platforms, and optional schedule time.
- `Template`: reusable text snippets.
- `PlatformPublish`: per-platform publish/analytics record.
- `Subscription`: Basic/Starter/Pro entitlement state.
- `RealClipCaptionUsage`: monthly usage ledger for paid AI caption generations
  from selected clips.

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
| Analytics | `ANALYTICS_STORE=memory` | `ANALYTICS_STORE=prisma` |
| Queue | `PUBLISH_QUEUE=memory` | `PUBLISH_QUEUE=bullmq` (Upstash) with `POST_STORE=prisma` and `DATABASE_URL` |
| Video storage | `VIDEO_STORAGE=mock` | `VIDEO_STORAGE=r2` (Cloudflare) |
| Captions | `CAPTION_PROVIDER=mock` | Real-clip caption provider using backend AI |
| Caption usage | `CAPTION_USAGE_STORE=memory` | `CAPTION_USAGE_STORE=prisma` |
| AI auto editing | `TRANSCRIPTION_PROVIDER=mock` | `TRANSCRIPTION_PROVIDER=groq` with Groq Whisper transcription on backend, FFmpeg export on mobile |
| Auth | `AUTH_PROVIDER=mock` | `AUTH_PROVIDER=firebase` |
| Billing | `BILLING_PROVIDER=mock` | `BILLING_PROVIDER=revenuecat` |
| Social publishing | `SOCIAL_PUBLISHER=mock` | `SOCIAL_PUBLISHER=postpeer` with PostPeer account ids and signed R2/S3 media URLs |

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
  M->>A: POST /uploads
  A->>S: Create upload key / signed URL
  A-->>M: videoS3Key + optional uploadUrl
  M->>S: PUT video file when signed URL exists
  M->>A: POST /posts
  A->>Q: Enqueue publish job
  A-->>M: post + publishJob
  Q->>W: Run job immediately or at scheduled time
  W->>P: Publish to selected platforms
  W->>S: Delete temporary video after success
  W->>A: Record publish/analytics result
```

Rules:

- Basic users can create real-time posts only.
- Basic users must verify a phone number before using the free quota.
- Basic users are limited to 3 post units per month after phone verification.
- Starter and Pro can schedule posts.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Post units count by selected platform, not post row.
- Starter unlocks real-clip AI captioning from audio.
- Pro unlocks analytics, hashtag radar, AI comment center, team/editor access,
  AI captioning from audio plus selected frames, and Groq Whisper auto
  editing.

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
  RC->>A: POST /billing/revenuecat/webhooks
  A->>DB: Activate STARTER or PRO subscription
```

Production work required:

- Create `postdee_starter_monthly` and `postdee_pro_monthly` in RevenueCat.
- Link Apple and Google service credentials to RevenueCat dashboard.
- Configure `REVENUECAT_WEBHOOK_AUTH_TOKEN` and the RevenueCat webhook URL.
- Replace the local RevenueCat Test Store SDK key with real platform SDK keys
  before App Store / Google Play release builds.
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

- `POST /captions/generate` remains the legacy keyword scaffold.
- `POST /captions/generate-from-clip` is the new clip-first scaffold with
  Starter audio-only mode, Pro audio plus selected-frame mode, SEO fields, hook
  ideas, transcription-backed language/market context, authenticated media-key
  ownership checks, opt-in cleanup for AI-only clip/frame uploads, and monthly
  quota reservation through memory or Prisma-backed usage storage.

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

  M->>A: Request transcript for selected clip
  A->>Sub: Check Pro plan and editing minutes
  alt User is Pro with minutes
    A->>W: Transcribe audio with word timestamps
    W-->>A: transcript + word timing
    A-->>M: editable transcript data
    M->>F: Burn subtitles / cut silence / export MP4
  else Basic or Starter
    A-->>M: 402 PRO_REQUIRED
  end
```

This is planned for Pro. Backend handles auth, quota, temporary storage, and
Groq Whisper transcription. Mobile handles subtitle editing, FFmpeg subtitle
burn-in, silence cutting, watermarking where needed, and final MP4 export.

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
- Keep legacy store receipt and notification verification enabled only for the legacy direct-store path.
- Use signed R2/S3 URLs or a controlled upload endpoint.
- Do not allow a scheduled job to publish another user's post.
- Keep cancel/reschedule actions synchronized with the backing publish queue so
  stale jobs cannot publish at the old time. Queue handoff failures return
  `503 PUBLISH_QUEUE_UNAVAILABLE` instead of letting the post store advance
  ahead of the queue.
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

- Social platform publishing defaults to mock. The PostPeer path is wired but
  still needs connected account ids and a real provider-level publish test
  before enabling `SOCIAL_PUBLISHER=postpeer`.
- The publish worker claims only `QUEUED` posts before calling PostPeer or the
  mock publisher. Jobs for posts already `PUBLISHING`, `PUBLISHED`,
  `PARTIAL_PUBLISHED`, or `FAILED` are skipped to avoid duplicate provider
  calls. Scheduled jobs whose `runAt` no longer matches the post's current
  `scheduledAt` are skipped after reschedules, and optional R2/S3 cleanup
  failures are reported in the worker result without changing a successful post
  to `FAILED`.
- Direct social OAuth/token storage is not implemented because the MVP
  production path uses PostPeer first.
- Real Gemini calls require credentials and provider testing.
- Real-clip AI captioning can use the transcription provider for audio
  language detection, but still needs real R2/Groq clip testing, visual-frame
  inputs, production migration verification for the Prisma usage ledger, and
  provider-level testing.
- Legacy AI Clip Review internals have been removed; only false compatibility
  fields remain for older clients.
- Pro AI auto editing still needs Groq Whisper job design, minute quotas, top-up
  handling, mobile FFmpeg export states, retries, and failure handling.
- Real R2 upload requires Cloudflare credentials and integration testing.
- Redis/BullMQ scheduling needs infrastructure testing.
- Firebase auth needs real project files and device testing.
- RevenueCat subscriptions need real Apple/Google products, platform SDK keys,
  sandbox testing, and fuller renewal/cancel/refund webhook coverage. The
  legacy direct store verifier remains a scaffold.
- Analytics does not yet fetch real platform metrics.

## Recommended Next Steps

1. Add real App Store / Google Play product setup documentation.
2. Test RevenueCat purchase and restore on real sandbox devices.
3. Test RevenueCat renewal/cancel/refund webhook delivery from sandbox events.
4. Keep the legacy store notification scaffold covered, but do not make it the
   preferred production billing path.
5. Expand RevenueCat notification event coverage from sandbox evidence.
6. Run the `RealClipCaptionUsage` migration in staging/production and set
   `CAPTION_USAGE_STORE=prisma` before selling paid AI caption quotas.
7. Design Pro Groq Whisper auto editing jobs, quotas, top-up, and mobile export states.
8. Test Firebase Google Sign-In on a real Android/iOS device.
9. Test video picker and 9:16 preview on real devices.
10. Connect the first real social publishing provider.
