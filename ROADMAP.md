# ROADMAP.md

Build roadmap for PostDee.

## Phase 1: Core App

Goal: make the first usable PostDee MVP work end to end.

Core items:

- Mobile UI refresh for a Thai creator workflow, using PostDee light/dark
  palettes and the approved green creator UI.
- Global-ready product foundations: localization, timezone, currency, phone
  formats, store products per market, and country launch checklists.
- Gemini caption generation through the backend.
- API Hosting on Render (Node.js/Express) and Database on Render PostgreSQL.
- Cloudflare R2 temporary video storage.
- Upstash Serverless Redis and BullMQ for scheduling.
- Firebase Auth (Google Sign-In, Phone Auth) and Firebase Cloud Messaging (FCM) for Push Notifications.
- RevenueCat for cross-platform subscription management (Apple App Store / Google Play).
- Sentry for error tracking and performance monitoring.
- Universal uploader for one 9:16 video.
- Scheduling through Upstash Redis and BullMQ.
- Unified social posting via PostPeer API (postpeer.dev) for TikTok, YouTube
  Shorts, Instagram Reels, and Facebook Page Video. `FACEBOOK_REELS` remains an
  internal compatibility value only; PostPeer's current path is not Facebook
  Reels. Direct platform API integrations are deferred until post-launch.
- Unified analytics summary for Pro users, with backend-backed date ranges and
  a publish-date daily series.

Current status:

- Mobile UI refresh has a first-pass shared dark theme, glass cards, Thai
  bottom navigation labels, auth bar copy, and Home dashboard direction.
  Upload, Calendar, Analytics, Profile, and package/paywall surfaces have the
  approved design structure; final device-specific visual polish remains.
- Gemini backend smoke test passed.
- Legacy signed upload and managed R2 multipart both passed disposable-account
  production API smoke tests. The managed test covered session creation,
  just-in-time part upload, completion/status, Firebase deletion readiness,
  account cleanup, deleted-account retry semantics, and zero leftover smoke
  sessions/objects in PostgreSQL and R2. Full mobile-to-worker real-video and
  slow-network tests still remain.
- Backend RevenueCat webhook and authenticated subscriber resync paths are
  prepared; mobile `purchases_flutter` purchase/restore is wired behind
  `ENABLE_REVENUECAT_BILLING=true`. Test Store purchase E2E passes on the
  Android Emulator, and true Restore/resync E2E passes after the Staging deploy
  and Render server-key configuration. The RevenueCat Play Store app/products,
  entitlements, default offering, production Android public SDK key, and signed
  AAB are prepared. Play Console app/subscriptions, internal testing, service
  credentials, real Google Play purchase, and physical-device testing remain;
  Play Console requires account verification on a physical Android device and
  does not accept an Emulator for that step.
- Render PostgreSQL and the API service have been created and the live health
  endpoint responds successfully. Secret/provider state remains a dated
  operational check and must be rechecked in the Render dashboard before launch.
- The isolated free-tier Staging Blueprint and database have now been created on
  Render, and the API health check passes. The Free Postgres database expires on
  2026-08-14. A dedicated Firebase Staging project, isolated Android Debug app
  id, Google provider, restricted Android API key, and Firebase-token-to-API
  login smoke test now pass on the Android Emulator. RevenueCat Test Store
  products, entitlements, current offering, and authenticated sandbox webhook
  transport are configured. Test Store purchase and true Restore/resync E2E pass
  with a Firebase UID after the current backend and Render key were configured.
  RevenueCat Play configuration and a signed AAB are ready, while Play Console
  setup and a real Google Play purchase remain blocked by the required physical
  Android account verification. R2 upload from Android now passes, while
  production-bucket isolation and cleanup still need confirmation. Lifecycle,
  Gemini/ElevenLabs, Phone Auth, and controlled social publishing still need
  current-candidate smoke tests after their environment-specific credentials are
  reconfirmed in the Dashboard. Render Staging and its Blueprint now track `main`.
- Legacy AI Clip Review UI, `/clip-reviews` route, config, and internal
  mock/provider code have been removed from the active app path. Subscription
  compatibility flags remain false for older clients.
- Global readiness is now part of the plan. The app remains Thai-first for the
  first launch, but future screens and backend flows should avoid Thailand-only
  assumptions where the cost is low.
- Firebase Auth, Render deployments, Upstash, RevenueCat webhooks, uploads,
  analytics, real-clip caption provider hardening, production verification of
  the Prisma AI caption usage ledger, and PostPeer social posting still need
  provider-level testing before production use. PostPeer profiles now satisfy
  the required name contract without exposing the Firebase UID/email and ensure
  the local User first; accepted async posts are polled for roughly two minutes,
  never receive a fabricated external id, and expose persisted per-platform
  results through `GET /posts`. A real connected-account E2E is still pending.
- Social-post safety now has an authenticated configuration preflight. Mobile
  checks it before watermark/upload; `POST /posts` and `PATCH /posts/:id`
  authoritatively return `503 SOCIAL_PUBLISHING_UNAVAILABLE` while the publisher
  is disabled, and cancel remains available. This prevents new false queued
  failures in the current client but does not enable or verify PostPeer. Old
  clients or a config race can still leave a temporary uploaded object.
- The Production Blueprint currently selects `SOCIAL_PUBLISHER=postpeer` even
  though connected-account E2E is pending. Treat this as a launch configuration
  risk; the repository cannot prove the live Render value, and the safety-gate
  work does not change that Blueprint.

## Backend Services Plan

Goal: keep the first production backend simple, hosted, and low-maintenance while avoiding custom infrastructure until the product proves real usage.

Primary backend choices:

| Area | Service | First production use | Current repo status | Notes |
| --- | --- | --- | --- | --- |
| API hosting | Render Web Service | Run the Node.js/Express API from `apps/api` | Render blueprint exists; web instance is pinned to 1 while `PUBLISH_QUEUE=memory` | Start with one API service. Add a separate worker service when BullMQ scheduling is enabled. |
| Database | Render PostgreSQL | Store users, posts, templates, subscriptions, and publish metrics through Prisma | Prisma schema and repositories exist | Use Render PostgreSQL first before considering Neon, Supabase, or self-hosted PostgreSQL. Set all Prisma-backed stores to `prisma` only after migrations and seed flow are verified. |
| Queue / scheduling | Upstash Redis + BullMQ | Schedule publish jobs and let a worker process delayed posts | BullMQ adapter exists; queue handoff failures return 503, stale rescheduled jobs are skipped, and config now requires shared Prisma posts for BullMQ. The deployed single-instance service currently uses an in-process scheduler that polls Prisma for due posts, so pending scheduled records survive an API restart, but execution is still tied to the web process. | Keep `PUBLISH_QUEUE=memory` for local development or the current one-instance deployment. Do not scale that mode above one API instance or treat it as an independently operated worker. Before multi-instance/worker isolation or stronger queue operations are required, use `PUBLISH_QUEUE=bullmq`, `POST_STORE=prisma`, `DATABASE_URL`, `REDIS_URL`, and a separate worker service. |
| Video storage | Cloudflare R2 | Store temporary upload videos and signed upload/download URLs | R2 adapter and managed multipart sessions exist | Use `VIDEO_STORAGE=r2` with `UPLOAD_PROTOCOL_MODE=dual` during rollout. New clients opt in to `multipart-v1`; move to strict `multipart` after old clients are retired. Keep videos temporary and delete after successful publishing where possible. |
| Auth | Firebase Auth | Google Sign-In, Firebase ID token verification, and Phone Auth for Basic quota unlock | Dedicated Android Debug Staging config and Google login/token/API smoke pass on Emulator; Production, iOS, Phone Auth, and physical-device tests remain | Keep Debug Staging on `com.postdee.postdee_mobile.staging`; do not mix its Dart defines with Profile/Release Firebase files. |
| AI caption from real clip | Gemini multimodal (listens to clip; Pro also sees frames) | Generate captions, SEO wording, hashtags, and hooks from a selected clip. Starter = audio only; Pro = audio + selected frames. | `POST /captions/generate-from-clip` sends the clip to configured-primary Gemini 2.5 Flash-Lite, retries transient failures, then falls back directly to the local template; media keys are user-scoped, AI-only uploads can request cleanup, and quota is reserved before calling AI; the mobile app extracts and uploads frames for Pro (`selectedFrameKeys`) | Verify the Pro frame flow on a real device, plus Gemini quota/tier and the Prisma usage ledger, before selling as production AI. |
| AI auto editing | ElevenLabs Scribe v2 + Gemini 3.5 Flash-Lite + mobile FFmpeg | Pro transcript/highlight planning, optional verified-silence/repeated-speech cleanup, AI-selected sound effects, subtitle burn-in, phone-side review, and video export | `/ai-edits/prepare`, fair quota outcomes, waveform-verified silence, safe repeated-speech review, atomic accepted-source state, subtitle-safe rendering, and local colour compatibility exist. AI SFX uses a separate catalog-only planner: it returns at most eight trusted `soundId + sourceSeconds` anchors; mobile fixes volume, maps through final cuts, and mixes bundled procedural WAVs. Manual SFX selection is removed. Production beat sync and the 3-second hook remain default-off. | Tasks 3–8 and deployed identity/health are verified. Pixel 8 `color-local` passed device/render checks, while the main matrix remains blocked: a new STT-only Staging key still received upstream HTTP `401`, PostDee quota stayed unchanged, and ElevenLabs showed only 6/10,000 workspace credits remaining. Wait for or restore provider quota, rerun the API-dependent matrix, then capture AI SFX Preview/full-export listening, peak, and A/V-sync evidence on Android and iPhone before Production. |
| Subscriptions | RevenueCat | Manage Starter and Pro subscriptions across Apple App Store and Google Play | Test Store purchase and true Restore/resync E2E pass on Emulator; RevenueCat Play config, production Android public SDK key, and signed AAB are ready | Verify Play Console access on a physical Android device, then create the Play app/subscriptions/service credentials/internal testing and test lifecycle plus real Google Play/App Store purchases before claiming production billing E2E. |
| Social posting | PostPeer API | Publish to TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Video through one provider | Per-user connect/refresh/provider-first disconnect are wired; fresh users are ensured before a pseudonymous named profile is saved; `202` results poll for about two minutes without fake ids; `GET /posts` returns per-platform results; the config-only readiness gate and fail-fast create/reschedule path exist; YouTube defaults private and TikTok SELF_ONLY for controlled testing; connected-account E2E is still pending | Readiness does not probe PostPeer/accounts. Keep Staging disabled except for a controlled run, clear old queued/scheduled records before enabling, and treat `FACEBOOK_REELS` as Page Video. Retry only an explicitly safe pre-accept error; unknown outcomes require checking the destination first. |
| Error tracking | Sentry | Capture backend, worker, and mobile errors | Planned | Add after build/test stability is restored so production issues are visible from day one. |
| Push notifications | Firebase Cloud Messaging | Notify users about scheduled publish results and failures | Mobile registration, `POST /devices`, notifier, and firebase-admin sender exist; mock remains default | Add the service account, set `PUSH_SENDER=firebase`, enable APNs/iOS capabilities, and test on a real device. |

Render runtime hardening keeps `firebase-admin` Auth/FCM support but removes its
unused optional Firestore and Google Cloud Storage clients after the build and
Prisma migration. CI still installs platform-native optional build tools, while
the production dependency audit excludes optional modules that are not shipped
in the running service.

### AI auto-editing update (2026-08-08)

The table's earlier audio-only deployment note is superseded. ElevenLabs M4A
transcription uses balanced source-audio chunks no longer than 30 seconds.
The API shifts source-relative timestamps only when every timed item remains
intact; clipping, dropped evidence, overlap, backwards order, or malformed
provider timing marks the complete timeline untrusted and prevents AI planning
from cutting against a repaired-looking subset. All temporary chunks are still
cleaned on success or failure. Mobile now sends the actual
source duration for quota preflight and omits the target at the rightmost
“ไม่ย่อ” stop. This fixes
the observed long-form omission where active Thai speech at the start of the
2:30 fixture produced no subtitle until 22 seconds. Target-length cuts that land
inside a cue are moved before the cue and balanced at the tail. Shorter targets
also add a
whole-duration 360 px/1 fps MP4 proxy with complete audio. The API pairs that
proxy with timestamped transcript segments through Gemini Files API, falls back
to audio planning on any visual failure, and cleans temporary device/R2/Gemini
media best-effort. The remaining release gate is a deployed Pixel 8 rerun that
must open Subtitle Studio with the full opening cue, then an R2 + ElevenLabs +
Gemini validation across the licensed Thai fixture matrix, followed by physical Android
and iPhone rendering tests.

Recommended activation order:

1. Keep backend/mobile build, analyze, and tests green as changes land.
2. Replace the remaining health-only R2/Gemini/ElevenLabs values with real
   staging-only provider credentials and pass the functional smoke tests in
   `docs/STAGING.md`.
3. Recheck Render secrets and Prisma migrations against the live database only
   after the same release candidate passes Staging.
4. Add Upstash Redis and run the publish worker as a separate Render worker service when durable scheduling is needed.
5. Test Cloudflare R2 managed multipart upload/download in the full
   mobile-to-worker flow, including per-part retry, completion recovery, abort,
   and account deletion while an upload is active.
6. Enable and test Firebase Phone Auth, then add isolated iOS Staging config and
   repeat auth smoke tests on physical Android/iOS devices.
7. Verify Play Console access on a physical Android device, then create the Play
   app/subscriptions, configure service credentials, and open internal testing.
8. Upload the prepared signed AAB and test Starter/Pro purchase and Restore
   through Google Play internal testing; complete App Store configuration and
   physical-device sandbox testing separately.
9. Add Sentry to the API, worker, and mobile app.
10. While Staging is still disabled, install only its PostPeer key, connect and
    refresh disposable per-user accounts, and cancel old queued/scheduled work.
    Enable PostPeer only for a controlled real publish E2E. Confirm readiness,
    YouTube `private`, TikTok `SELF_ONLY`, Instagram Reels, Facebook Page Video,
    the bounded async poll, and `GET /posts.platformResults`; then restore
    `disabled` and verify readiness returns `503` before enabling public claims.
11. Deploy and verify the real-clip AI caption usage ledger with `CAPTION_USAGE_STORE=prisma` before selling the paid AI caption quotas.
12. Harden Pro AI auto editing with persistent job/session recovery, top-up handling, and real-device tests of the setup-to-review-to-post/manual-editor flow before production launch.

## Mobile UI Direction

The current app uses the light theme by default and keeps dark theme support.
The dated 2026-06-06 ultra-dark implementation checklist is a historical visual
direction and is superseded wherever it conflicts with this light-default
product decision. Keep its verified navigation and behavior improvements, but
do not restore the older theme just because an unchecked historical step remains.

Goal: make the Flutter app feel like a polished Thai mobile product before
connecting more production providers. This UI work should stay incremental and
must not change backend contracts, billing rules, auth rules, or social posting
behavior unless a later task explicitly says so.

Reference direction:

- Light/dark PostDee palettes with green accents, clear cards, thin borders, and
  small status indicators.
- Thai-first copy for visible user flows.
- Bottom navigation has five tabs; AI editing opens as a child flow rather than
  a sixth persistent tab.
- Keep AI captioning available from Upload after a clip is selected.
- Keep Templates available as a secondary entry point instead of a main
  bottom-nav tab.
- Keep AI advanced settings in an accordion with at most one expanded
  capability and no default expansion, so the mobile flow stays scannable.

Planned order:

1. Lock shared UI primitives: theme tokens, glass card, gradient button style,
   platform status chips, Thai navigation labels, and reusable mini chart/bar
   widgets.
2. Finish Home dashboard: greeting, plan card, latest-post status rows, quick
   actions, and platform performance summary.
3. Redesign Upload: vertical video preview, functional cover editor (video
   frame, Thai text, font/style/position, rendered 1080x1920 image, secure
   upload, preview, and platform-aware delivery), platform toggles,
   schedule/date/time controls capped at 30 days in advance, draft state, and a
   single clear Post CTA. The
   cover editor implementation now exists; real connected-account publishing
   still requires staging verification.
4. Refine Calendar and Upload AI Caption: the calendar now refreshes when
   visible, polls live post states, and opens completed results read-only;
   real connected-account verification and real-clip AI captioning after video
   selection remain.
5. Redesign Analytics: date filter chips, KPI cards, views trend chart,
   platform comparison bars, and Thai labels for all visible metrics.
6. Add Profile/navigation pass: replace the current Templates bottom tab with
   Profile, keep Templates reachable from Upload or AI tools, and make sure no
   current template feature disappears.
7. Verify each round on the Android emulator with Flutter analyze, widget
   tests, debug APK build, install, and screenshots.

## Global Readiness Plan

Goal: keep PostDee easy for Thai sellers first, while making the app usable in
other countries without a future rewrite.

Recommended order:

1. Localization foundation
   - Keep Thai as the first complete language.
   - Prepare app copy for English and future languages.
   - Avoid hard-coded Thai-only strings when redesigning screens.

2. Country, timezone, and schedule handling
   - Store schedule times in UTC on the backend.
   - Display and edit schedules in the user's local timezone.
   - Make analytics date ranges locale-aware.

3. Currency and store subscription markets
   - Keep backend plan ids provider-neutral: Basic, Starter, Pro.
   - Let App Store Connect and Google Play map localized prices per country.
   - Show user-facing price text from store product metadata where possible.

4. International phone and identity
   - Keep Firebase Phone Auth using international E.164 phone numbers.
   - Do not assume Thai-only phone prefixes.
   - Keep anti-abuse logic based on verified phone identity, not email alone.

5. Content and AI localization
   - Thai affiliate captions remain the first polished prompt style.
   - Upload AI captioning should infer language and market from the selected
     clip instead of making the seller choose fields.
   - Keep optional guidance as the simple override path for requests like
     "write this in English for the US market".
   - Add provider-tested language detection for high-priority markets such as
     English, Indonesian, Vietnamese, Japanese, Korean, and Arabic.
   - Keep AI keys on the backend only for every country.

6. Compliance and platform availability
   - Add a country launch checklist before opening each market.
   - Review privacy, tax, app-store subscription, consumer protection, and
     social platform policy requirements for that market.
   - Do not assume every social platform API or permission is available in every
     country.

7. Infrastructure and support readiness
   - Keep storage, queue, and API settings region-configurable.
   - Add status/support copy that can be localized.
   - Track country-specific provider issues separately from global app errors.

## Detailed Plan Files

These narrower plans live outside this roadmap. ROADMAP is the high-level map;
when product direction changes, update both the detailed plan and this file.

Plan status uses five groups:

- **ใช้งานอยู่**: current product or package direction.
- **ทำบางส่วน**: the core exists, but named release or follow-up work remains.
- **อนาคต**: approved direction that has not started. There is currently no
  whole plan file in this group; future-only work is listed in Phase 2, Global
  Readiness, and the remaining phases of partial plans.
- **ประวัติ**: completed implementation record; unchecked execution boxes do
  not mean that the capability is absent.
- **ถูกแทนที่**: an older approach that must not override the current runtime.

| Plan file | Status | Notes |
| --- | --- | --- |
| `docs/superpowers/plans/2026-06-04-store-subscription-billing.md` | ถูกแทนที่ | The direct Apple/Google verification scaffold is retained for history and compatibility; RevenueCat is the production subscription direction. |
| `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md` | ถูกแทนที่ | The ultra-dark checklist is historical. The current app is light by default with optional dark theme; retain only behavior and navigation improvements that still match the current UI. |
| `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md` | ถูกแทนที่ | The original Groq provider choice is retired. Current AI editing uses ElevenLabs Scribe v2, Gemini planning, PostDee-rule fallback, and mobile FFmpeg; dated timing and safety notes remain useful history. |
| `docs/superpowers/plans/2026-06-13-subscription-packages-plan.md` | ใช้งานอยู่ | Current positioning source for Basic, Starter 199, Pro 299, quotas, paused AI audio review, and Team & Editor Access. Active paywalls must still hide benefits that are not end-to-end ready. |
| `docs/superpowers/plans/2026-06-21-production-foundation-revenuecat-plan.md` | ทำบางส่วน | Webhook, Test Store purchase, Restore/resync, Play configuration, and signed AAB foundations exist; physical Play Console verification and real Google Play/App Store purchases remain. |
| `docs/superpowers/plans/2026-06-26-postpeer-user-social-connections.md` | ถูกแทนที่ | The proposed signed-state callback flow was replaced by PostPeer profile state and explicit refresh polling. Use API/architecture docs for the runtime; real connected-account publishing remains a release test, not an unchecked-plan count. |
| `docs/superpowers/plans/2026-07-18-ai-edit-audio-only-media-plan.md` | ประวัติ | Implemented M4A transcription/cleanup milestone. The later whole-video visual proxy supersedes only its earlier no-visual-proxy boundary. |
| `docs/superpowers/plans/2026-07-20-subtitle-project-foundation-implementation-plan.md` | ประวัติ | The versioned project, validated edits, bounded undo/redo, recipe mapping, and local draft foundation are implemented; unchecked task boxes are retained as an execution record. |
| `docs/superpowers/plans/2026-07-20-subtitle-studio-plan.md` | ทำบางส่วน | Core editor, live preview, Thai-safe fonts, ASS/static fallback, and result-review entry exist. Brand preset persistence, parity evidence, physical-device hardening, post-MVP effects, and optional cloud sync remain. |
| `docs/superpowers/plans/2026-07-23-ai-edit-subtitle-review-flow.md` | ประวัติ | Implemented flow: render and show result review first; open Subtitle Studio only from the explicit review action. |
| `docs/superpowers/plans/2026-07-23-ai-edit-whole-video-proxy-plan.md` | ทำบางส่วน | Whole-duration 360p visual planning is implemented on `main`; deployed R2/Gemini device quality evidence remains a release gate. |
| `docs/superpowers/plans/2026-07-23-pro-entitlement-and-main-launcher.md` | ประวัติ | The package badge refresh and desktop launcher-to-`main` work are implemented; operational entitlement expiry still follows RevenueCat. |
| `docs/superpowers/plans/2026-07-28-latest-ai-subtitle-main-integration.md` | ประวัติ | Explicitly integrated into remote `main`; its unchecked boxes are historical, while fresh real-device quality acceptance remains tracked separately. |
| `docs/superpowers/plans/2026-07-30-gemini-model-separation-implementation.md` | ประวัติ | Implemented model split: Gemini 3.5 Flash-Lite for edit planning and Gemini 2.5 Flash-Lite for captions, with the retired caption fallback removed. |
| `docs/superpowers/plans/2026-08-01-ai-edit-correctness-and-fair-quota-implementation.md` | ทำบางส่วน | Tasks 1–2 are committed locally. The verified Tasks 3–8 implementation is committed locally in `43fa6e0`. Task 9 Steps 1–5 are complete; Step 6 remains blocked after a new STT-only Staging key and same-SHA deploy still produced upstream HTTP `401`. PostDee quota stayed unchanged; ElevenLabs showed only 6/10,000 workspace credits remaining, so provider-side quota exhaustion is the leading diagnosis. `color-local` passed device/render checks with direct no-call log evidence still pending. |
| `docs/superpowers/plans/2026-08-08-ai-subtitle-setup-frame-drag-colors-plan.md` | ทำบางส่วน | Implementation is included in local commit `43fa6e0`: real local frame preview, draggable normalized subtitle position, pre-AI text/outline colours, truthful 1/3/5-word variants, and ASS export parity exist. API 914/914, Mobile 759/759, Flutter analyze, and matrix APK `879E74425CC95B5E1C98831A688F20F687CECD7F8C5F078714C3A4AC789A2145` are verified; deployed identity/health match, `color-local` passed device/render checks with direct no-call log evidence still pending, and subtitle/API-dependent Pixel 8 acceptance remains blocked by the Staging transcription provider. |
| `docs/superpowers/plans/2026-08-09-ai-sound-effects-foundation-plan.md` | ทำบางส่วน | AI-only SFX is implemented and automated verification passes: API 938/938 plus build, Mobile 792/792 plus analyze, and diff-check. The manual picker/Studio/local-only path is removed. A dedicated provider selects only allowlisted PostDee sound IDs at trusted source anchors; mobile fixes volume, maps through final cuts, and reuses the recipe in preview/export. Staging provider recovery plus Android/iPhone listening and A/V-sync evidence remain release gates. |

## Planned Pricing

These tiers are the intended product packaging. The current package source of
truth is `docs/superpowers/plans/2026-06-13-subscription-packages-plan.md`.
The older AI Clip Review route, config, UI, and internal backend code have been
removed so this package plan does not compete with a separate review feature.

| Tier | Price | Main Value | Intended Limits |
| --- | ---: | --- | --- |
| Basic | Free | Test posting only | Phone verification required, then 3 real-time test posts per month |
| Starter | 199 THB/month | Practical daily posting plus AI caption from the real clip audio | 120 post units/month, scheduling, calendar, templates, auto watermark, EP clip splitting UI, Link in Bio basic page, and 50 real-clip AI caption generations/month |
| Pro | 299 THB/month | Growth tools, analytics, team workflows, and stronger AI from audio plus selected visual frames | 250 post units/month, scheduling, calendar, templates, auto watermark, EP clip splitting, full analytics, hashtag radar, AI comment center, viral alert, Link in Bio advanced page, Team & Editor Access, 120 real-clip AI caption generations/month, and 200 AI auto editing minutes/month |

Package rules:

- The active Paywall must show only end-to-end ready benefits. EP splitting,
  hashtag radar, viral alerts, and team/editor access remain planned and must
  not be presented as included until their real flows are verified.
- Basic must verify a phone number before using the 3-post free test quota.
- Post units count by platform: posting one video to four platforms uses four
  units.
- Starter can schedule posts. Analytics, hashtag radar, AI comment center,
  viral alert, and team access stay Pro-only.
- Starter AI captioning listens to the selected clip audio and returns SEO
  wording, hashtags, caption options, and hook ideas.
- Pro AI captioning can use audio plus selected visual frames from the clip for
  stronger suggestions.
- Upload AI captioning should auto-detect language and market from the selected
  clip. Sellers can override through optional guidance instead of extra fields.
- Do not sell prompt-only AI captioning as the main paid feature. Text guidance
  can exist only as an optional extra after the user selects a clip.
- Do not include a separate "AI audio clip review" feature in Starter or Pro
  package marketing for now.
- AI auto editing top-up: 49 THB for 120 extra editing minutes. This applies
  to AI editing minutes, not post units.
- Secret AI keys must stay on the backend only. Team editors must never see the
  owner's social account passwords or tokens.

## Phase 2: Growth Features

Items 1-7 below are future growth features that should start after the core
posting and scheduling flow is usable with real provider APIs. Item 8 records
production hardening for the AI editing system that already exists on `main`;
it is not a future feature waiting to be built from zero.

Recommended order:

1. Link in Bio Generator
   - Create merchant pages such as `postdee.link/store-name`.
   - Store affiliate links, product links, and campaign links.
   - Let scheduled posts update the bio page link list.
   - This is the first Phase 2 feature because it creates low-risk lock-in.

2. EP Link Assistant
   - Help users split long videos into EP.1, EP.2, and later parts.
   - Generate an EP link comment such as "Watch EP.2 here: ...".
   - Require explicit user approval before posting any comment.
   - Support YouTube Shorts, Instagram Reels, and Facebook Reels/Page where official APIs and permissions allow it.
   - Do not auto-post EP link comments on TikTok in this phase.

3. Auto-Branding Watermark
   - Let users place a store logo on video before publishing.
   - Prefer mobile-side processing first to reduce backend video processing cost.
   - Validate performance on real iOS and Android devices before production release.

4. Trending Hashtag Radar
   - Track hashtag and keyword trends relevant to seller categories.
   - Keep this behind Pro until cost and data sources are clear.

5. AI Comment Center
   - Summarize comments across connected owned channels.
   - Report positive feedback, negative feedback, common questions, and suggested replies.
   - Start with daily reports and suggested replies before any auto-reply behavior.

6. Viral Alert Notification
   - Alert sellers when a post grows faster than expected.
   - Start with simple thresholds such as views increasing by more than 50 percent in one hour.

7. Team and Editor Access
   - Let owners invite editors or agency staff.
   - Editors can prepare posts and schedules without seeing social account passwords.
   - Use role-based access around connected OAuth accounts.

8. Harden the Existing AI Auto Editing System
   - The existing ElevenLabs + Gemini + mobile FFmpeg flow lets Pro users request Thai transcription, receive internal silence candidates, verify those candidates against the source waveform, burn in subtitles, review the phone-rendered result, and remove supported AI edits they do not want. Only waveform-approved intersections become silence cuts; probe failure keeps the original audio and exposes a local retry that does not upload, prepare, or charge again. The verified Tasks 3–8 implementation is committed locally in `43fa6e0`; Task 9 Steps 1–5 and deployment evidence are complete. Pixel 8 `color-local` passed device/render checks with no quota change but still needs direct zero-upload/prepare log evidence. A new 30-day, Speech-to-Text-only Staging key was deployed on the unchanged SHA, yet `target-30` still failed closed/no-charge with upstream HTTP `401`; ElevenLabs showed 9,994/10,000 credits used. Provider-side quota exhaustion is therefore the leading diagnosis, but the missing upstream response detail prevents calling it confirmed. Wait for or restore provider quota under separate approval, then rerun once before continuing Steps 6–10.
   - Mobile starts every optional capability off. The seller can explicitly enable subtitles, silence cleanup, repeated-speech cleanup, or `AI ใส่เอฟเฟกต์เสียงให้`; with no optional capability selected, target-length shortening can still run by itself. The colour/light and audio-cleanup cards are hidden from setup, with restored values forced off, while legacy internal support remains intact. SFX is an AI analysis path: the server may return only an allowlisted PostDee sound ID at a trusted source anchor, mobile fixes volume at 25%, maps it through final cuts, and renders locally. The manual picker/Studio path is removed.
   - Backend handles auth, quota, temporary storage, ElevenLabs Scribe v2 transcription, Gemini 3.5 Flash-Lite visual/transcript planning with structured JSON and provider-default sampling (no explicit `temperature`), and deterministic rule fallback. It validates the complete timing timeline before using it for subtitles, planning, repeated-speech cleanup, or silence candidates; partial or damaged timing fails closed instead of falling back to a repaired-looking subset.
   - Mobile re-renders accepted capabilities from the original clip, then lets the user continue to posting or open the manual editor.
   - Review uses an adaptive 540p/20 fps preview for sources longer than one minute (720p/24 fps for shorter sources), reports FFmpeg processed-time progress, supports cancel/retry, and reuses identical results. Going to Post renders a separate full-source-dimension file.
   - The mobile target-length safety guard restores context around AI-selected moments when incomplete transcript timing would otherwise leave less than the slider-selected duration.
   - Target-length planning now rejects known prompt leakage and low-quality provider segments, omits those ranges from rendered subtitle lines, then selects one continuous story window. Changing only the duration slider reuses the current in-memory transcript through non-metered `/ai-edits/plan`, so the source audio is transcribed and charged once per analysis settings set.
   - Duration-only replanning also reuses the current source's local 360p visual proxy. Thai continuation-fragment openings receive a soft penalty in transcript and Gemini visual planning so a nearby complete sentence is preferred without hard-blocking a genuinely stronger hook.
   - Real Staging logs exposed repeated Gemini Files upload-start HTTP 400 responses from the hand-written resumable request. Upload, status polling, and deletion now use Google's official `@google/genai` SDK; a deployed device E2E remains the release gate before claiming visual planning is active.
   - The AI editing header shows exact Pro minutes remaining/used, refreshes from `GET /ai-edits/quota`, and adopts the latest `prepare` quota immediately after a metered analysis.
   - The pace tool now appears as “จัดการคำพูดซ้ำ” instead of a fixed filler-word list. The user chooses `AI เลือกให้`, which starts from safely timed adjacent-repeat recommendations, or `เลือกเอง`, which detects the same candidates but starts with no cuts. Both modes let the user keep/remove each safe occurrence before re-render, and manual mode ignores legacy automatic filler ranges. Distributed frequent words remain uncut; subtitle text and media cuts share the same validated range, while unsafe mapping keeps the word.
   - Android FFmpeg rendering supplies bundled Thai-safe Bai Jamjuree, Prompt, or Anuphan fonts to libass, supports validated active-word ASS with static SRT fallback, and compacts kept audio ranges alongside cut video. Transcript-derived gaps never enter that processor directly; every preview, review update, subtitle re-render, and export receives only waveform-verified silence ranges.
   - Android preview completion no longer depends only on the plugin callback: an exact FFmpeg `progress=end` marker exits polling, then the renderer probes the output and requires a video stream before accepting it. Pro preflight releases after 30 seconds; FFmpeg no-progress startup limits are 30 seconds for preview and 90 seconds for full export, but a terminal session or `progress=end` wins before timeout.
   - The render screen labels the final 99% output probe as “กำลังตรวจไฟล์วิดีโอ...” so normal mux/finalization work is not mistaken for a frozen render.
   - AI prepare now renders a lightweight result and opens result review first; Subtitle Studio opens only from the explicit review action. It provides local autosaved drafts, active-word live preview with safe static fallback, cue text and timing edits, add/delete/split/merge, undo/redo, Bai Jamjuree/Prompt/Anuphan selection, colours, fade/pop, outline, shadow, and draggable normalized placement. The pre-AI setup shows one real local frame, allows scrubbing and finger placement, exposes text/outline colours, removes the top/bottom buttons, and labels subtitle density truthfully as 1/3/5 words. The API prepares all three density variants from one transcript, so presentation/density changes in the same editing session do not call the provider or reserve minutes again. Custom placement stays in ASS and fails closed instead of silently falling back to an incorrectly positioned SRT. The implementation is in local commit `43fa6e0`; deployed identity/health match and local colour preview/export passed, while subtitle and API-dependent Pixel 8 parity remain blocked by the Staging transcription provider.
   - The 2026-07-28 integration adds authoritative optional `subtitles.segments[].words`, exact case-sensitive cue reconstruction, one-line 3/4/5-word style rules, display-oriented dimensions for rotated clips, a final subtitle-boundary tolerance, one retry for transient or unavailable media probes, and a hard requested-duration output cap. Focused mobile tests and `flutter analyze` pass; fresh Pixel 8 and physical-device acceptance remain required.
   - The 2026-07-29 live-clip quality fix caps multi-token Thai server cues at five semantic words and 20 graphemes; an indivisible longer brand/URL token remains whole in an isolated cue and mobile shrinks it to measured width. The fix also limits opening pre-roll to a real subtitle-free gap, preserves the Gemini-selected opening/Hook while moving only a dangling Thai tail to the first complete phrase (10% of target, bounded to 1–3 seconds), shares that allowance with the FFmpeg cap, and uses the longer media/transcript duration for planning and quota. API and Flutter automated suites pass; a fresh Staging Pixel 8 render of the same 2:30 clip remains the acceptance gate before release.
   - The duration used above is currently the longer of the official client's native FFprobe result and ElevenLabs' last-word endpoint. Add a server-side M4A/MP4 duration probe plus an API 600-second ceiling before public billing; client duration alone is not tamper-resistant.
   - Baseline Pixel 8 emulator acceptance before the 2026-07-29 quality fix used the 2:30 / 38 MB Thai clip, opened Subtitle Studio with 20 source-timeline cues, restored an autosaved Anuphan draft without another metered prepare, rendered an exact 30-second 2.4 MB preview, and reached result review with the new “แก้ข้อความและรูปแบบซับ” return action. The first run exposed overlapping combined plan/silence/filler cut ranges; the mobile recipe adapter now validates malformed ranges and merges valid overlaps before project validation.
   - The mobile dependency is pinned to `ffmpeg_kit_flutter_new_video` 2.3.2,
     which ships the FFmpeg 8.1.2 CVE-2026-8461 fix for Android and iOS. Store
     release remains blocked on native export smoke tests on physical Android
     and iPhone devices; until those pass, process only trusted team-created clips.
   - Transcript gaps are silence candidates only. The Android/iOS client confirms each candidate against the source waveform before rendering; failed or ambiguous verification keeps the original audio. Silence analysis uses `natural` (1.0 s), `balanced` (0.6 s default), or `compact` (0.4 s) thresholds, excludes leading/trailing gaps, and never places a candidate directly in executable cuts. Mobile applies safety padding, rejects source edges/protected speech, and distinguishes probe failure from a successful empty result. Successful results are cached for the exact source/evidence; failures can retry locally. Repeated-speech cleanup reconstructs Thai fragments only by exact NFC text in raw provider order, inside one reliable segment, with gaps no greater than 0.15 seconds. It recommends only safely timed adjacent words/phrases, keeps distributed frequent words, negation, emphasis, numbers/prices, timed audio-event barriers, and any fragment that cannot be proven exact, while retaining the old exact filler allowlist only for legacy clients. Fair-usage outcomes leave unavailable-only repeat/subtitle/silence requests unmetered, reject explicit empty or colour-only prepare calls before provider work, and preserve metering for legacy requests that omit capabilities.
   - Mobile fits and aligns AI story-plan cuts before applying verified silence and supported repetition cleanup. Dedicated repaired `transcript.boundarySegments` remain separate from visible subtitle cues, so opening/tail alignment still works when subtitles are off without rendering text. Missing or unsafe boundary evidence keeps the planner cut and shows a warning instead of falling back to raw provider segments. Pending setup source is separate from the accepted source/recipe/project; the accepted set changes atomically only after render success, so a failed new-source attempt cannot corrupt review or export.
   - Result review reports verified silence status/count/time and distinguishes “ตรวจแล้ว · ไม่พบช่วงเงียบที่ปลอดภัย” from a failed probe with retry. Repeated-speech summaries do not promise the exact exported savings. Independent rollback flags can disable verified silence or automatic repeat cuts; repeat rollback keeps detection groups visible but read-only and forces empty occurrence selections through every render/export path.
   - The tested color-only local route remains as internal/legacy compatibility but is no longer offered as a seller setup card. Its original-duration path still uses a cut-free recipe with no audio extraction/upload/prepare call; unknown enabled capabilities fail closed, a local retry repeats only rendering, a failed source B render preserves accepted source A, and output uses `_edited.mp4` unless real subtitle content is present. AI SFX now has a separate analysis/placement contract and quota outcome over the existing in-house procedural assets and local renderer. It never accepts provider-controlled volume/URL/path, never falls back to a random sound, and discards anchors removed by final cuts. Physical Android/iPhone listening/A-V-sync evidence remains required before Production.
   - Baseline Pixel 8 emulator verification before the 2026-07-29 quality fix reached an exact 30-second review preview (2.4 MB), showed live progress and recoverable cancellation, produced a 29.994667-second full export (about 14 MB), and opened the Post flow. The post-fix rerun and physical Android/iPhone export tests remain required before Store release.
   - Task 9 now records exact codec/FPS/file size/audio peak/timebase evidence for the `color-local` full export. Other paths and manual lip-sync remain pending; do not describe renderer acceptance as complete until the full matrix records real device evidence.
   - The 3-second hook remains `planned` with no renderer. Production keeps `ENABLE_EXPERIMENTAL_AI_HOOK=false`; `true` is internal setup-UI QA only.
   - Beat-sync setup can keep original audio or select an owned MP3/M4A/WAV file with a rights confirmation, plus cut intensity, music volume, and voice ducking. Production keeps this capability locked as `เร็ว ๆ นี้` because a verified cross-platform music catalog, beat detection, and real music mixing remain future work. Internal QA may expose only the setup UI with `ENABLE_EXPERIMENTAL_BEAT_SYNC=true`.

## Guardrails

- Do not use bot, scraper, or browser automation for social posting.
- Do not post comments or replies without explicit user approval.
- Do not add TikTok auto-comment support until official API support and policy review are clear.
- Keep secret keys only in backend environment variables, never in the Flutter app.
- Keep `ENABLE_EXPERIMENTAL_AI_HOOK` and `ENABLE_EXPERIMENTAL_BEAT_SYNC` absent or
  `false` in production until their real analyzers/renderers pass device tests.
- Keep Phase 2 behind Pro or future Agency plan gates where appropriate.
- Do not market separate AI audio review while real-clip AI captioning and
  ElevenLabs + Gemini auto editing cover that user need.
- Keep Pro-only social/team tools scoped so editors can prepare work without
  seeing owner credentials or tokens.

## App Store & Google Play Compliance

To ensure the app passes store review guidelines, the following must be implemented before the first production release:
1. **Payments**: Use RevenueCat to process all digital subscriptions natively through Apple and Google to comply with in-app purchase rules.
2. **Authentication**: If Google Sign-In is offered, Apple Sign-In MUST also be implemented in the mobile UI (supported natively by Firebase Auth). Done in code: `FirebaseAppleAuthGateway` uses Firebase `signInWithProvider('apple.com')`. Still needs the Apple provider enabled in Firebase and the iOS "Sign in with Apple" capability before it works on device.
3. **Account Deletion**: Implemented in code. The Profile screen warns that store subscriptions must be managed separately, iOS/macOS Apple users pass a backend readiness check then reauthenticate and revoke Apple access, and `DELETE /account` requires recent Firebase authentication. It sets a durable deletion barrier before cleanup, blocks later authenticated mutations and worker claims, drains or reconciles an in-flight completion, aborts persisted and orphan R2 multipart sessions, disconnects PostPeer integrations, removes queued jobs/R2 objects/database data, and deletes the Firebase identity last. Late RevenueCat events cannot recreate a missing user, and an account-only verifier supports a lost-response retry only after Firebase confirms the UID is gone. Apple Sign-In remains unavailable on Android/web until server-side token revocation exists there. Legacy and managed-multipart production API/R2/Firebase disposable-account smoke tests pass. Launch completion still requires physical-device end-to-end and slow-network tests, plus a lifecycle rule scoped only after temporary and scheduled media use separate prefixes. Production remains in `dual` rollout mode; the signed-`PUT` replay path is fully closed only after old clients are retired and strict `multipart` mode is enabled.
4. **Content & Safety**: Rely on Gemini's built-in safety filters to prevent abusive or explicit AI generation.
5. **Policies**: Host and link a valid Privacy Policy and Terms of Service inside the app.

## Immediate Next Steps

1. Sync remaining mobile and backend package copy with the new Starter 199 and
   Pro 299 positioning.
2. Test real-clip captioning against R2/Gemini with real videos, then harden
   spoken-language detection and market-aware prompting.
3. Run the Prisma migration and verify `CAPTION_USAGE_STORE=prisma` against a
   real PostgreSQL database.
4. Enable the Firebase providers/capabilities and run real-device auth tests;
   the project files are already present.
5. Test managed R2 multipart uploads from the mobile app through the backend
   and worker flow, then retire legacy clients and change production from
   `dual` to strict `multipart` mode.
6. Verify the per-user PostPeer connect/refresh flow while Staging remains
   disabled, cancel old queued/scheduled records, then run controlled real
   publishing with disposable connected accounts. Confirm readiness returns to
   `503` after restoring `disabled`. Treat `FACEBOOK_REELS` as Facebook Page
   Video, verify uncertain outcomes before retrying, and defer individual social
   API app reviews.
7. Continue AI editing job/session persistence, ElevenLabs transcription/Gemini planning hardening, top-up,
   retry/recovery, and real-device testing of pace detections, review counts, export, posting, and manual editing.
8. Add music upload/ownership storage, license a cross-platform PostDee catalog,
   then implement and test beat analysis, audio mixing, and voice ducking before
   marking beat sync as applied or enabling it in production. Keep
   `ENABLE_EXPERIMENTAL_BEAT_SYNC` false for production until then.
