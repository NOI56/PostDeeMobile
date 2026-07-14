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
- Unified social posting via PostPeer API (postpeer.dev) for TikTok, YouTube Shorts, Instagram Reels, and Facebook Reels. Direct platform API integrations are deferred until post-launch.
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
- Backend RevenueCat webhook scaffold is prepared; mobile `purchases_flutter`
  gateway is wired behind `ENABLE_REVENUECAT_BILLING=true`. Real App Store /
  Google Play product setup, platform SDK keys, and sandbox/device purchase
  testing remain.
- Render PostgreSQL and the API service have been created and the live health
  endpoint responds successfully. Secret/provider state remains a dated
  operational check and must be rechecked in the Render dashboard before launch.
- The isolated free-tier Staging Blueprint and database have now been created on
  Render, and the API health check passes. The Free Postgres database expires on
  2026-08-14. A dedicated Firebase Staging project, isolated Android Debug app
  id, Google provider, restricted Android API key, and Firebase-token-to-API
  login smoke test now pass on the Android Emulator. RevenueCat Test Store
  products, entitlements, current offering, and authenticated sandbox webhook
  transport are configured, but purchase/restore/lifecycle E2E remains. R2,
  Gemini/Groq, Phone Auth, and controlled social publishing still need
  functional staging credentials and smoke tests.
- Legacy AI Clip Review UI, `/clip-reviews` route, config, and internal
  mock/provider code have been removed from the active app path. Subscription
  compatibility flags remain false for older clients.
- Global readiness is now part of the plan. The app remains Thai-first for the
  first launch, but future screens and backend flows should avoid Thailand-only
  assumptions where the cost is low.
- Firebase Auth, Render deployments, Upstash, RevenueCat webhooks, uploads,
  analytics, real-clip caption provider hardening, production verification of
  the Prisma AI caption usage ledger, and PostPeer social posting still need
  provider-level testing before production use.

## Backend Services Plan

Goal: keep the first production backend simple, hosted, and low-maintenance while avoiding custom infrastructure until the product proves real usage.

Primary backend choices:

| Area | Service | First production use | Current repo status | Notes |
| --- | --- | --- | --- | --- |
| API hosting | Render Web Service | Run the Node.js/Express API from `apps/api` | Render blueprint exists; web instance is pinned to 1 while `PUBLISH_QUEUE=memory` | Start with one API service. Add a separate worker service when BullMQ scheduling is enabled. |
| Database | Render PostgreSQL | Store users, posts, templates, subscriptions, and publish metrics through Prisma | Prisma schema and repositories exist | Use Render PostgreSQL first before considering Neon, Supabase, or self-hosted PostgreSQL. Set all Prisma-backed stores to `prisma` only after migrations and seed flow are verified. |
| Queue / scheduling | Upstash Redis + BullMQ | Schedule publish jobs and let a worker process delayed posts | BullMQ adapter exists; queue handoff failures return 503, stale rescheduled jobs are skipped, and config now requires shared Prisma posts for BullMQ | Use `PUBLISH_QUEUE=bullmq`, `POST_STORE=prisma`, `DATABASE_URL`, and `REDIS_URL` after Upstash is configured. Keep the in-memory queue for local development only. |
| Video storage | Cloudflare R2 | Store temporary upload videos and signed upload/download URLs | R2 adapter and managed multipart sessions exist | Use `VIDEO_STORAGE=r2` with `UPLOAD_PROTOCOL_MODE=dual` during rollout. New clients opt in to `multipart-v1`; move to strict `multipart` after old clients are retired. Keep videos temporary and delete after successful publishing where possible. |
| Auth | Firebase Auth | Google Sign-In, Firebase ID token verification, and Phone Auth for Basic quota unlock | Dedicated Android Debug Staging config and Google login/token/API smoke pass on Emulator; Production, iOS, Phone Auth, and physical-device tests remain | Keep Debug Staging on `com.postdee.postdee_mobile.staging`; do not mix its Dart defines with Profile/Release Firebase files. |
| AI caption from real clip | Gemini multimodal (listens to clip; Pro also sees frames) | Generate captions, SEO wording, hashtags, and hooks from a selected clip. Starter = audio only; Pro = audio + selected frames. | `POST /captions/generate-from-clip` sends the clip to Gemini (retry + model fallback + local template fallback); media keys are user-scoped, AI-only uploads can request cleanup, and quota is reserved before calling AI; the mobile app extracts and uploads frames for Pro (`selectedFrameKeys`); legacy Groq/Whisper path kept for when no Gemini is configured | Verify the Pro frame flow on a real device, plus Gemini quota/tier and the Prisma usage ledger, before selling as production AI. |
| AI auto editing | Groq Whisper large-v3 + mobile FFmpeg | Pro subtitle transcription, optional silence/filler cuts, UI capability recipe, subtitle burn-in, phone-side review, and video export | Backend route, `/ai-edits/prepare` recipe contract, quota ledger, mobile FFmpeg flow, silence presets, exact filler allowlist, detected count/time summary, reversible supported capabilities with automatic preview re-render, accordion settings, and Post/manual-editor exits exist. Production beat sync and the 3-second hook are locked as `เร็ว ๆ นี้` behind default-off compile-time flags. | Re-check Groq pricing/docs before production launch. Backend handles transcription, quota, and recipe hints; mobile renders and reviews locally to control cost. `ENABLE_EXPERIMENTAL_BEAT_SYNC=true` and `ENABLE_EXPERIMENTAL_AI_HOOK=true` are internal setup-UI QA flags only and do not make either renderer real. |
| Subscriptions | RevenueCat | Manage Starter and Pro subscriptions across Apple App Store and Google Play | Test Store products/entitlements/offering and authenticated webhook transport configured; mobile SDK gateway remains behind a flag | Test purchase, restore, renewal, cancel, and refund before claiming billing E2E. Prefer RevenueCat over maintaining custom Apple/Google verification. |
| Social posting | PostPeer API | Publish to TikTok, YouTube Shorts, Instagram Reels, and Facebook Reels through one provider | Per-user connect/refresh/provider-first disconnect and publisher code are wired; a connected provider account and controlled publish test are still needed | Use PostPeer first to reduce platform integration risk. Direct platform APIs are deferred until after launch. |
| Error tracking | Sentry | Capture backend, worker, and mobile errors | Planned | Add after build/test stability is restored so production issues are visible from day one. |
| Push notifications | Firebase Cloud Messaging | Notify users about scheduled publish results and failures | Mobile registration, `POST /devices`, notifier, and firebase-admin sender exist; mock remains default | Add the service account, set `PUSH_SENDER=firebase`, enable APNs/iOS capabilities, and test on a real device. |

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
7. Configure RevenueCat real App Store / Google Play products, replace the local
   Test Store key with platform SDK keys, and test Starter/Pro purchases on
   sandbox devices.
8. Add Sentry to the API, worker, and mobile app.
9. Connect a per-user PostPeer account, refresh its integration state, and run a controlled real publish test.
10. Deploy and verify the real-clip AI caption usage ledger with `CAPTION_USAGE_STORE=prisma` before selling the paid AI caption quotas.
11. Harden Pro AI auto editing with persistent job/session recovery, top-up handling, and real-device tests of the setup-to-review-to-post/manual-editor flow before production launch.

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
- Keep AI advanced settings in an accordion with at most one expanded
  capability and no default expansion, so the mobile flow stays scannable.

Planned order:

1. Lock shared UI primitives: theme tokens, glass card, gradient button style,
   platform status chips, Thai navigation labels, and reusable mini chart/bar
   widgets.
2. Finish Home dashboard: greeting, plan card, latest-post status rows, quick
   actions, and platform performance summary.
3. Redesign Upload: vertical video preview, edit thumbnail action, platform
   toggles, schedule/date/time controls, draft state, and a single clear Post
   CTA.
4. Refine Calendar and Upload AI Caption: scheduled-post calendar, refresh after
   scheduled posts, and real-clip AI captioning after a video is selected.
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
| `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md` | Referenced in pricing, backend services, Phase 2, and next steps | Pro AI auto editing uses Groq Whisper large-v3 for transcription and mobile-side FFmpeg for setup, result review, reversible supported edits, and post/manual-editor exits. |
| `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md` | Reflected in the Mobile UI Refresh Plan | Older task checklist for the approved Thai ultra-dark mobile UI. Some details may need another sync after the Calendar/Profile navigation changes. |
| `docs/superpowers/plans/2026-06-04-store-subscription-billing.md` | Reflected in backend services and store compliance | Store subscription scaffold is represented here, while RevenueCat remains the preferred production subscription management direction. |

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

8. AI Auto Editing With Groq Whisper
   - Pro users can request Thai transcription, cut silence, burn in subtitles, review the phone-rendered result, and remove supported AI edits they do not want.
   - Backend handles auth, quota, temporary storage, and Groq Whisper transcription with a Thai language hint, a concise PostDee spelling prompt, and both word and segment timestamps. It validates word timing before using it for silence/filler cuts and subtitle timing, falls back to segments when coverage is incomplete, and keeps Thai character-level timing for gaps while using readable segment subtitles.
   - Mobile re-renders accepted capabilities from the original clip, then lets the user continue to posting or open the manual editor.
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
2. **Authentication**: If Google Sign-In is offered, Apple Sign-In MUST also be implemented in the mobile UI (supported natively by Firebase Auth). Done in code: `FirebaseAppleAuthGateway` uses Firebase `signInWithProvider('apple.com')`. Still needs the Apple provider enabled in Firebase and the iOS "Sign in with Apple" capability before it works on device.
3. **Account Deletion**: Implemented in code. The Profile screen warns that store subscriptions must be managed separately, iOS/macOS Apple users pass a backend readiness check then reauthenticate and revoke Apple access, and `DELETE /account` requires recent Firebase authentication. It sets a durable deletion barrier before cleanup, blocks later authenticated mutations and worker claims, drains or reconciles an in-flight completion, aborts persisted and orphan R2 multipart sessions, disconnects PostPeer integrations, removes queued jobs/R2 objects/database data, and deletes the Firebase identity last. Late RevenueCat events cannot recreate a missing user, and an account-only verifier supports a lost-response retry only after Firebase confirms the UID is gone. Apple Sign-In remains unavailable on Android/web until server-side token revocation exists there. Legacy and managed-multipart production API/R2/Firebase disposable-account smoke tests pass. Launch completion still requires physical-device end-to-end and slow-network tests, plus a lifecycle rule scoped only after temporary and scheduled media use separate prefixes. Production remains in `dual` rollout mode; the signed-`PUT` replay path is fully closed only after old clients are retired and strict `multipart` mode is enabled.
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
6. Verify the per-user PostPeer connect/refresh flow and run one controlled real
   publish test, deferring individual social API app reviews.
7. Continue AI editing job/session persistence, Groq Whisper transcription hardening, top-up,
   retry/recovery, and real-device testing of pace detections, review counts, export, posting, and manual editing.
8. Add music upload/ownership storage, license a cross-platform PostDee catalog,
   then implement and test beat analysis, audio mixing, and voice ducking before
   marking beat sync as applied or enabling it in production. Keep
   `ENABLE_EXPERIMENTAL_BEAT_SYNC` false for production until then.
