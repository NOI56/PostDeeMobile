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
- In-process scheduling with Prisma-backed posts in the current single-instance
  Render configuration; optional Upstash Redis/BullMQ migration for scaling.
- Firebase Auth (Google Sign-In, Phone Auth) and Firebase Cloud Messaging (FCM) for Push Notifications.
- RevenueCat for cross-platform subscription management (Apple App Store / Google Play).
- Sentry for error tracking and performance monitoring.
- Universal uploader for one 9:16 video.
- Write one shared caption; preview the automatically derived YouTube Shorts
  title and optionally customize it without retyping the caption.
- A separate scheduling worker when the optional BullMQ path is enabled.
- Unified social posting via PostPeer API (postpeer.dev) for TikTok, YouTube
  Shorts, Instagram Reels, and Facebook Page Reels. The existing `FACEBOOK_REELS`
  value always sends PostPeer `platform: 'facebook'` with
  `platformSpecificData.contentType: 'reel'`, with no Page feed fallback.
  Real connected-account E2E remains pending. TikTok native connection is a
  proposed next track, starting with developer registration and sandbox setup
  before implementation; real direct
  platform APIs remain gated on credentials, secure token lifecycle, provider
  review, and end-to-end verification.
- Unified analytics summary for Pro users, with backend-backed date ranges and
  a publish-date daily series.

Current status:

- Managed PostPeer mobile connection trial: Android Custom Tabs with an
  external-browser fallback and automatic authenticated status refresh after
  a pending attempt returns to the same signed-in session. Manual refresh is
  retained. No new developer registration, direct native social SDK, or
  automatic browser-to-app redirect is included. Installed-app handoff and
  password-free authorization require physical-device verification. See
  [the mobile trial](docs/superpowers/plans/2026-10-25-postpeer-mobile-connection-trial.md).
- TikTok native-first connection has a proposed setup/design/security plan
  only. Register the developer app and sandbox accounts before implementation;
  publishing continues through PostPeer during the managed mobile trial.
  No native social SDK, API contract, direct token exchange/storage,
  or direct publisher has been added for this proposal. See
  [the setup and security plan](docs/superpowers/plans/2026-10-21-tiktok-native-connection.md).
- Mobile UI refresh has shared light/dark themes (light is the default), glass cards, Thai
  bottom navigation labels, auth bar copy, and Home dashboard direction.
  Upload, Calendar, Analytics, Profile, and package/paywall surfaces have the
  approved design structure. Home latest-post rows now request owner-scoped
  signed media, show a rendered cover when available, and fall back to a paused
  source-video frame or the existing play icon; final device-specific visual
  polish remains.
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
- Earlier records confirm that Render PostgreSQL and the API service were
  created and the health endpoint responded. The 2026-10-20 read-only inventory
  shows Production API/database suspended by the user; neither was resumed.
  Staging health is reported separately below. Secret/provider readiness still
  requires release-specific verification before launch.
- The recorded 2026-07-15 Staging snapshot reports that the isolated free-tier
  Blueprint/database were created and the API health check passed. Its recorded
  Free Postgres expiry was 2026-08-14. A subsequent read-only check on
  2026-10-20 confirmed HTTP 200 from the Staging API, a live 2026-10-18 deploy,
  and an available Basic 256 MB/1 GB PostgreSQL 18 database. The local
  dependency/FCM fix is not deployed there. The repository's Free/temporary-
  branch Blueprint differs from the live Starter/main service and must be
  reconciled before deploy. Earlier records also report a dedicated Firebase
  Staging project, isolated Android Debug app id, Google provider, restricted
  Android API key, and a passing Firebase-token-to-API login smoke test on the
  Android Emulator. RevenueCat Test Store products, entitlements, current
  offering, and authenticated sandbox webhook transport were configured.
  Test Store purchase and true Restore/resync E2E were recorded as passing with
  a Firebase UID after the backend and Render key were configured.
  RevenueCat Play configuration and a signed AAB are ready, while Play Console
  setup and a real Google Play purchase remain blocked by the required physical
  Android account verification. Lifecycle, R2, Gemini/Groq, Phone Auth, and
  controlled social publishing still need functional staging credentials and
  smoke tests.
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

## Backend Services Plan

Goal: keep the first production backend simple, hosted, and low-maintenance while avoiding custom infrastructure until the product proves real usage.

Primary backend choices:

| Area | Service | First production use | Current repo status | Notes |
| --- | --- | --- | --- | --- |
| API hosting | Render Web Service | Run the Node.js/Express API from `apps/api` | Render blueprint exists; web instance is pinned to 1 while `PUBLISH_QUEUE=memory` | Start with one API service. Add a separate worker service when BullMQ scheduling is enabled. |
| Database | Render PostgreSQL | Store users, posts, templates, subscriptions, and publish metrics through Prisma | Prisma schema and repositories exist; relational features share the canonical Prisma user record | Use Render PostgreSQL first before considering Neon, Supabase, or self-hosted PostgreSQL. Set all Prisma-backed stores to `prisma` only after migrations and seed flow are verified; Prisma analytics must use Prisma posts. |
| Queue / scheduling | Current in-process scheduler; optional Upstash Redis + BullMQ | Publish due posts from the configured post store; migrate to a separate worker for scaling | `render.yaml` uses `PUBLISH_QUEUE=memory`, `POST_STORE=prisma`, and one API instance. The BullMQ adapter exists; queue handoff failures return 503, stale rescheduled jobs are skipped, and BullMQ requires shared Prisma posts | Keep one API instance with the current scheduler. Before enabling multiple instances, configure `PUBLISH_QUEUE=bullmq`, `POST_STORE=prisma`, `DATABASE_URL`, `REDIS_URL`, and a separate worker; verify recovery and provider flows. |
| Video storage | Cloudflare R2 | Store temporary upload videos and signed upload/download URLs | R2 adapter and Prisma-backed managed multipart sessions exist; Home requests three owner-scoped signed cover/video previews after the API limits recent rows | Use `VIDEO_STORAGE=r2`, `UPLOAD_PROTOCOL_MODE=dual`, and `DATABASE_URL` during rollout. New clients opt in to `multipart-v1`; move to strict `multipart` after old clients are retired. Keep videos temporary and delete after successful publishing where possible; preview rows must retain their missing-media fallback. |
| Auth | Firebase Auth | Google Sign-In, Firebase ID token verification, and Phone Auth for Basic quota unlock | Dedicated Android Debug Staging config and Google login/token/API smoke pass on Emulator; Production, iOS, Phone Auth, and physical-device tests remain | Keep Debug Staging on `com.postdee.postdee_mobile.staging`; do not mix its Dart defines with Profile/Release Firebase files. |
| AI caption from real clip | Gemini multimodal (listens to clip; Pro also sees frames) | Generate captions, SEO wording, hashtags, and hooks from a selected clip. Starter = audio only; Pro = audio + selected frames. | `POST /captions/generate-from-clip` sends the clip to Gemini (retry + model fallback + local template fallback); media keys are user-scoped, AI-only uploads can request cleanup, and quota is reserved before calling AI; the mobile app extracts and uploads frames for Pro (`selectedFrameKeys`); legacy Groq/Whisper path kept for when no Gemini is configured | Verify the Pro frame flow on a real device, plus Gemini quota/tier and the Prisma usage ledger, before selling as production AI. |
| AI auto editing | Groq Whisper large-v3 + mobile FFmpeg | Pro subtitle transcription, transcript-based best-moment selection for an explicitly selected 30/60/custom target length, optional silence/filler cuts, phone-side review, and video export | The setup screen does not preselect 30 seconds and blocks processing until the seller chooses a target. `/ai-edits/prepare` accepts `targetDurationSeconds` separately, selects spoken hooks/benefits/proof/offers/CTA in chronological order, and returns real cut ranges for mobile FFmpeg. Quota, silence presets, filler allowlist, review, reversible supported capabilities, and Upload/Post exit exist. Visual highlight selection still needs a safe visual proxy. PostDee does not include a built-in manual timeline editor. | Verify Thai selection quality with real seller clips and physical-device exports before marketing the result as production AI. Re-check Groq pricing/docs. Beat sync and opening-hook reordering flags remain internal QA only. |
| Subscriptions | RevenueCat | Manage Starter and Pro subscriptions across Apple App Store and Google Play | Test Store purchase and true Restore/resync E2E pass on Emulator; RevenueCat Play config, production Android public SDK key, and signed AAB are ready | Verify Play Console access on a physical Android device, then create the Play app/subscriptions/service credentials/internal testing and test lifecycle plus real Google Play/App Store purchases before claiming production billing E2E. |
| Social posting | PostPeer API | Publish to TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels through one provider | Per-user connect/refresh/provider-first disconnect are wired; fresh users are ensured before a pseudonymous named profile is saved; `202` results poll for about two minutes without fake ids; `GET /posts` returns per-platform results; YouTube defaults private and TikTok SELF_ONLY for controlled testing; connected-account E2E is still pending | `FACEBOOK_REELS` always sends `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`; no Page feed fallback. Verify Page Reel delivery with real accounts before production claims. Retry only an explicitly safe pre-accept error; unknown outcomes require checking the destination first. |
| Error tracking | Sentry | Capture backend, worker, and mobile errors | Planned | Add after build/test stability is restored so production issues are visible from day one. |
| Push notifications | Firebase Cloud Messaging | Notify users about scheduled publish results and failures | Mobile registration, `POST /devices`, notifier, and a modular Firebase Admin 14 sender exist; 13 mocked sender regressions pass and mock remains default | Add the service account, set `PUSH_SENDER=firebase`, enable APNs/iOS capabilities, and test delivery on a real device. |

Recommended activation order:

1. Keep backend/mobile build, analyze, and tests green as changes land.
2. Replace the remaining health-only R2/Gemini/Groq values with real
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
10. Connect per-user PostPeer test accounts, refresh their integration state,
    and run a controlled real publish E2E. Confirm YouTube `private`, TikTok
    `SELF_ONLY`, Instagram Reels, Facebook Page Reels, the bounded async poll,
    and `GET /posts.platformResults` before enabling public claims.
11. Deploy and verify the real-clip AI caption usage ledger with `CAPTION_USAGE_STORE=prisma` before selling the paid AI caption quotas.
12. Harden Pro AI auto editing with persistent job/session recovery, top-up handling, and real-device tests of the setup-to-review-to-post flow before production launch.

## Mobile UI Refresh Plan

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
- Expose settings directly on each available AI capability with no global
  advanced-mode switch. Keep the panels in an accordion with at most one
  expanded capability and no default expansion, so the mobile flow stays
  scannable.

Planned order:

1. Lock shared UI primitives: theme tokens, glass card, gradient button style,
   platform status chips, Thai navigation labels, and reusable mini chart/bar
   widgets.
2. Finish Home dashboard: greeting, plan card, latest-post status rows, quick
   actions, and platform performance summary.
3. Redesign Upload: vertical video preview, functional cover editor (video
   frame, Thai text, font/style/position, and rendered image), platform toggles,
   schedule/date/time controls capped at 30 days in advance, draft state, and a
   single clear Post CTA. The selected frame is center-cropped and normalized
   to a 1080x1920 JPEG no larger than 2 MiB. Cover publishing follows each destination's real
   capability: Instagram full image, Facebook Page Reels best-effort thumbnail
   (display on the Reel still needs real-account verification; provider may choose the cover),
   TikTok frame time only, and
   YouTube Shorts final selection in the YouTube mobile app.
   YouTube title preview uses the first sentence of the first nonempty caption
   line (up to 100 Unicode code points); the full caption stays the description.
   `ปรับชื่อเฉพาะ YouTube` preserves an explicit title across caption edits and
   offers a reset to automatic. Blank captions are allowed only when posting
   solely to YouTube with a nonempty custom title. Carry the optional override
   through persistence, scheduling, and the provider; verify on a connected
   account before treating this as production-ready.
4. Refine Calendar and Upload AI Caption: scheduled-post calendar, refresh after
   scheduled posts, and real-clip AI captioning after a video is selected.
   Keep quota feedback compact above `ให้ AI ช่วยเขียน`: plan,
   remaining/limit, used count, and a thin bar from the authenticated read-only
   `GET /captions/quota`. Refresh on entry, tab activation, app resume, and
   failed generation attempts; successful generation supplies its latest quota.
   Show retry on read failures without substituting a zero balance. This UI
   uses the existing monthly caption limits and does not add a post quota panel.
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

| Plan file | ROADMAP sync status | Notes |
| --- | --- | --- |
| `docs/superpowers/plans/2026-06-13-subscription-packages-plan.md` | Synced into Planned Pricing below | Current source of truth for Basic, Starter 199, Pro 299, package limits, paused AI audio review, and Team & Editor Access positioning. |
| `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md` | Referenced in pricing, backend services, Phase 2, and next steps | Pro AI auto editing uses Groq Whisper large-v3 for transcription and mobile-side FFmpeg for setup, result review, reversible supported edits, and the Upload/Post exit; a built-in manual timeline editor is out of scope. |
| `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md` | Reflected in the Mobile UI Refresh Plan | Older task checklist for the approved Thai ultra-dark mobile UI. Some details may need another sync after the Calendar/Profile navigation changes. |
| `docs/superpowers/plans/2026-06-04-store-subscription-billing.md` | Reflected in backend services and store compliance | Store subscription scaffold is represented here, while RevenueCat remains the preferred production subscription management direction. |
| `docs/superpowers/plans/2026-06-21-production-foundation-revenuecat-plan.md` | Synced with the current billing foundation | Webhooks and true Restore/resync are verified on Staging; the addendum records the prepared RevenueCat Play configuration/AAB and remaining Play Console physical-device verification. |
| `docs/superpowers/plans/2026-07-17-scaling-roadmap.md` | Linked from architecture and roadmap | Active-user capacity gates for approximately 100, 1,000, 10,000, and 100,000 users. Upgrades use measured concurrency, latency, memory, database, queue, and provider pressure rather than registered-user count. |

## Scaling Roadmap

PostDee will keep the current Flutter, Express, PostgreSQL, Render, R2, and
BullMQ foundation and expand it incrementally. The detailed source of truth is
`docs/superpowers/plans/2026-07-17-scaling-roadmap.md`.

| Active-user planning tier | Required engineering gate |
| ---: | --- |
| Up to 100 | Durable BullMQ scheduling, separate worker, optimized AI audio path, real push/provider E2E, Sentry, and recovery evidence |
| Up to 1,000 | Safe multiple API instances, Redis-backed rate limits, bounded Prisma connections, pagination, graceful shutdown, and load/soak evidence |
| Up to 10,000 | Durable asynchronous AI jobs, isolated worker pools, database-side analytics/usage rollups, retention, and provider-aware autoscaling |
| Up to 100,000 | Fresh enterprise architecture review from real 10,000-user metrics, HA/read replicas, disaster recovery, API lifecycle, security, staffing, and contractual support |

Registered accounts alone do not open a gate. Upgrade decisions use monthly
active users, peak concurrency, p95/p99 latency, CPU/RAM, database connections
and slow queries, queue delay/failures, provider limits, and recovery tests.
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
  Scheduled creation and rescheduling both require a current server-resolved
  Starter/Pro entitlement; Basic receives `402 PAID_PLAN_REQUIRED` before changes.
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

These features should start after the core posting and scheduling flow is usable with real provider APIs.

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
   - Support YouTube Shorts, Instagram Reels, and Facebook Page Reels where official APIs and permissions allow it.
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

8. AI Auto Editing With Groq Whisper
   - Pro users can request Thai transcription, cut silence, burn in subtitles, review the phone-rendered result, and remove supported AI edits they do not want.
   - Backend handles auth, quota, temporary storage, and Groq Whisper transcription with a Thai language hint, a concise PostDee spelling prompt, and both word and segment timestamps. It validates word timing before using it for silence/filler cuts and subtitle timing, falls back to segments when coverage is incomplete, and keeps Thai character-level timing for gaps while using readable segment subtitles.
   - Mobile automatically extracts AAC/M4A (mono, 16 kHz, 64 kbps), uploads only that owner-scoped audio for current analysis, and cleans local/remote artifacts. The source video remains local for final-quality rendering; legacy `videoS3Key` stays temporarily compatible.
   - Live OpenAI/Groq planning fails explicitly with `502 AI_EDIT_PLAN_PROVIDER_FAILED` and does not reserve prepare quota; `mock-rule` is limited to configured mock/test mode and is labeled as test mode on mobile.
   - Mobile re-renders accepted capabilities from the original clip, then lets the user continue to Upload/Post with that accepted result. PostDee does not provide a built-in manual timeline editor; users who want hands-on editing can use a separate external editor such as CapCut, with no claimed integration or handoff.
   - Cached local render retries skip extraction/upload/transcription. A 360p visual proxy remains planned; future visual capabilities fail closed until it exists and passes device/provider tests.
   - The AI editing header shows exact Pro minutes remaining/used, refreshes from `GET /ai-edits/quota`, and adopts the latest `prepare` quota immediately after a metered analysis.
   - Android FFmpeg rendering supplies the bundled Prompt font to libass and compacts kept audio ranges alongside silence-cut video, preventing missing burned subtitles or audio that outlives the final video frame.
   - The mobile dependency is pinned to `ffmpeg_kit_flutter_new_video` 2.3.2,
     which ships the FFmpeg 8.1.2 CVE-2026-8461 fix for Android and iOS. Store
     release remains blocked on native export smoke tests on physical Android
     and iPhone devices; until those pass, process only trusted team-created clips.
   - Silence cleanup uses `natural` (1.0 s), `balanced` (0.6 s default), or `compact` (0.4 s) validated word-gap thresholds with segment fallback, including qualifying leading/trailing silence and overlap-safe range merging. Whitespace-only timing tokens are ignored, while malformed meaningful tokens fail closed. Filler cleanup uses an exact five-word allowlist, accepts exact `เออ` as the `เอ่อ` transcription alias, and conservatively reassembles a validated Thai character-token stream only across tight timing and verified Thai word/text boundaries; missing legacy input selects all five, while explicit empty input selects none.
   - Result review reports detected silence/filler counts and their combined pre-render time. It does not claim that the exported clip saves exactly that duration.
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
  Groq Whisper auto editing cover that user need.
- Keep Pro-only social/team tools scoped so editors can prepare work without
  seeing owner credentials or tokens.

## App Store & Google Play Compliance

To ensure the app passes store review guidelines, the following must be implemented before the first production release:
1. **Payments**: Use RevenueCat to process all digital subscriptions natively through Apple and Google to comply with in-app purchase rules.
   RevenueCat purchases now await authenticated purchase-readiness before Store
   purchase; GET subscription is read-only. Coordinate the mobile/API update for
   older clients that relied on GET bootstrap. Protocol-1 readiness now fails
   closed on older APIs. Roll out the additive endpoint, then mobile preparation,
   retire/disable legacy buying builds, then deploy read-only GET; this branch
   bundles the cutover. Local API/Flutter regression suites ran on 20 October
   2026; this does not verify the live rollout or native Store behavior.
   RevenueCat configuration/product lookup, buy/restore callback and entitlement
   polling now retain the original UID/session; native work already dispatched
   still needs device validation.
2. **Authentication**: If Google Sign-In is offered, Apple Sign-In MUST also be implemented in the mobile UI (supported natively by Firebase Auth). Done in code: `FirebaseAppleAuthGateway` uses Firebase `signInWithProvider('apple.com')`. Still needs the Apple provider enabled in Firebase and the iOS "Sign in with Apple" capability before it works on device.
3. **Account Deletion**: Implemented in code. The Profile screen warns that store subscriptions must be managed separately, iOS/macOS Apple users pass a backend readiness check then reauthenticate and revoke Apple access, and `DELETE /account` requires recent Firebase authentication. It sets a durable deletion barrier before cleanup, blocks later authenticated mutations and worker claims, drains or reconciles an in-flight completion, aborts persisted and orphan R2 multipart sessions, disconnects PostPeer integrations, removes queued jobs/R2 objects/database data, and deletes the Firebase identity last. Late RevenueCat events cannot recreate a missing user, and an account-only verifier supports a lost-response retry only after Firebase confirms the UID is gone. Apple Sign-In remains unavailable on Android/web until server-side token revocation exists there. Legacy and managed-multipart production API/R2/Firebase disposable-account smoke tests pass. Launch completion still requires physical-device end-to-end and slow-network tests, plus a lifecycle rule scoped only after temporary and scheduled media use separate prefixes. Production remains in `dual` rollout mode; the signed-`PUT` replay path is fully closed only after old clients are retired and strict `multipart` mode is enabled.
   The security remediation adds session-bound mobile deletion consent, token
   refresh checks and serialized native auth/Apple revocation. New regression
   tests ran in the local API/Flutter suites on 20 October 2026. Real database,
   broker, device, and sandboxed security validation remain pending; earlier
   smoke-test results do not validate those conditions. User/Post/Subscription final
   writes now share the durable owner marker transaction (memory uses an owner
   FIFO), and legacy mode also has the deletion marker. Same-process queue
   admission is drained; deletion returns retryable 503 on busy/failed queue
   cleanup. Cross-instance Redis late adds, process crashes, already-admitted
   provider calls and other stores' final writes still need work.
   Mobile OTP uses the native auth queue, Link in Bio drafts are isolated by UID,
   and in-app notification history/recipient filtering follows the session.
   Native device tests, OS background push display and token detachment remain.
4. **Content & Safety**: Rely on Gemini's built-in safety filters to prevent abusive or explicit AI generation.
5. **Policies**: Host and link a valid Privacy Policy and Terms of Service inside the app.

## Immediate Next Steps

1. Sync remaining mobile and backend package copy with the new Starter 199 and
   Pro 299 positioning.
2. Test real-clip captioning against R2/Groq with real videos, then harden
   spoken-language detection and market-aware prompting.
3. Run the Prisma migration and verify `CAPTION_USAGE_STORE=prisma` against a
   real PostgreSQL database.
4. Enable the Firebase providers/capabilities and run real-device auth tests;
   the project files are already present.
5. Test managed R2 multipart uploads from the mobile app through the backend
   and worker flow, then retire legacy clients and change production from
   `dual` to strict `multipart` mode.
6. Verify the per-user PostPeer connect/refresh flow and run controlled real
   publishing with disposable connected accounts. Verify `FACEBOOK_REELS`
   produces a Facebook Page Reel via `contentType: 'reel'` with no Page feed
   fallback, verify uncertain outcomes before retrying, and defer
   individual social API app reviews.
7. Continue AI editing job/session persistence, Groq Whisper transcription hardening, top-up,
   retry/recovery, and real-device testing of pace detections, review counts, export, and posting.
8. Add music upload/ownership storage, license a cross-platform PostDee catalog,
   then implement and test beat analysis, audio mixing, and voice ducking before
   marking beat sync as applied or enabling it in production. Keep
   `ENABLE_EXPERIMENTAL_BEAT_SYNC` false for production until then.
