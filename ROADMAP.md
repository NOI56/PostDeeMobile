# ROADMAP.md

Build roadmap for PostDee.

## Post quota on the clip step (2026-10-25, follow-up candidate)

- Show a compact strip immediately in the uploader's clip-selection step, even
  before a clip is selected: effective plan badge, monthly remaining/limit in
  `หน่วย`, used post
  units and a thin progress bar. Show a small paid purchased-credit line only
  when nonempty; explain Basic's phone-verification gate.
- Reuse `GET /billing/subscription` fields through a dedicated background
  post-quota loader, separate from imperative subscription preflight calls.
  Load on composer entry with an empty or handed-in clip; refresh for
  selection/reselection, resume, auth
  changes, successful in-composer subscription resync and post acceptance/failure
  or recovery while the composer stays open. Billing/phone changes are observed
  on those refreshes. Guard owner/session/request/clip scope and show loading/retry
  unless all monthly limit/used/remaining fields are valid, without inventing zero.
- Preserve post-unit limits, add-on consumption, phone/publish gates, the
  wizard and all caption-credit work. Selection does not spend quota, start AI,
  publish or initiate payment. No new API, backend, schema, migration, price,
  provider or flag change. The UI needs an updated Mobile build and installation;
  a Render API deployment does not update the installed screen. Record actual
  checks/delivery separately in the
  [post-quota strip plan](docs/superpowers/plans/2026-10-25-post-quota-strip.md).

## AI caption credits per selected channel (2026-10-25, implementation candidate)

- Charge 1/2/3/4 credits for 1/2/3/4 selected AI caption channels. Keep one
  provider operation and show `สร้างแคปชั่น · N เครดิต` on the existing action.
  Shared-caption and legacy keyword requests remain one credit.
- Reserve the whole request atomically, monthly credits before retained add-on
  credits. Insufficient total balance must not partially debit or call AI.
  Refund the entire batch for fallback/failed/incomplete generation; successful
  generation remains charged if its preview is dismissed.
- Derive cost on the API and confirm the displayed cost with `expectedCredits`.
  Reject old/mismatched multi-platform requests with `409
  AI_CAPTION_COST_CONFIRMATION_REQUIRED` before charge or provider work. Return
  `requestedCredits`, `chargedCredits` and existing `charged` quota metadata;
  insufficient quota includes actual remaining balance and required cost.
- Coordinate API/Mobile rollout: older multi-platform apps require an update,
  and newer Mobile against the older API can overquote its one-credit charge.
  No plan allowance/price, add-on pack, schema, migration, provider or flag
  change. This record does not establish deployment or real-provider/device
  acceptance; track validation in the
  [credit-per-channel plan](docs/superpowers/plans/2026-10-25-caption-credit-per-channel.md).

## Compact AI caption quota strip (2026-10-25, implementation candidate)

- Add the approved small strip above the existing AI generation action with
  plan, monthly remainder/limit, used count and a thin remaining bar.
- Read actual authenticated quota through `GET /captions/quota` on composer
  entry/resume; update from generation independently of caption edits or
  advanced-preview acceptance. Retry failed reads and refresh after failures
  or pending refund recounts without inventing a zero balance.
- Preserve nonexpiring add-on credits: show a short credit line only when a
  bank remains, and disable AI when known paid total availability cannot cover
  the selected request cost.
  Keep the existing wizard, selection/preview/undo, trial/owner guards and
  manual editing/posting behavior. No package-rule, flag or schema change.
- Deliver the additive API before the Mobile build; older API `404` responses
  show unavailable/retry. This entry does not establish a deployment or real
  provider/device acceptance. Track checks and delivery in the
  [quota-strip plan](docs/superpowers/plans/2026-10-25-caption-quota-strip.md).
## Per-channel clip-duration alerts (2026-10-25, local candidate)

- Warn after video pick/prefill/draft restore and show a duration error beside
  each connected channel. Disable incompatible unselected rows while allowing
  selected incompatible rows to be unchecked; never trim or silently deselect.
- Block Next/final confirmation while a selected channel has a duration error.
  Select all adds compatible channels without removing existing selections.
- Use Facebook Page Reels 3–90 seconds, YouTube Shorts at most 180 seconds,
  Instagram Reels 3–900 seconds, TikTok Inbox at most 600 seconds and TikTok
  Direct at most min(600 seconds, fresh connected creator limit).
- Unknown source duration is not a pass. Preserve actual outgoing-file checks,
  TikTok preparation/consent, cached receipts, accepted recovery, owner scope,
  quotas and already accepted schedules. No backend/schema/flag change.
- Mobile tests, analysis and Staging APK12052 build/package/signature checks pass;
  installation, runtime and provider E2E remain unverified.
  Source review dated 2026-10-25 is not real-account publishing evidence. See the
  [contract and source record](docs/superpowers/plans/2026-10-15-platform-publish-preflight.md#per-channel-duration-alerts--2026-10-25-local-candidate).

## Facebook Page Reels only (2026-10-24)

- Retain `FACEBOOK_REELS` and always send PostPeer `platform: 'facebook'` with
  `platformSpecificData.contentType: 'reel'`; never fall back to a Page feed video.
- Preserve `PUBLISH|PAGE_DRAFT`, optional `isAiGenerated`, per-platform captions,
  immutable target snapshots, existing TikTok Direct and billing safeguards.
- Remove feed-specific Facebook media limits; the 2026-10-25 local candidate
  separately adds the documented 3–90-second API Reel duration guard. Keep
  actual-media verification and provider validation. Signed thumbnails
  remain best effort, with Reel display and real-account publish/draft E2E pending.
- No new client fields, environment variables or migrations. Updated publishers
  also route existing queued/scheduled Facebook jobs to Page Reels.

## Preview from final post review (2026-10-24, local candidate)

- Replace clip/caption edit links with one `พรีวิว` button below the thumbnail;
  keep channel editing and existing wizard Back navigation.
- Preview the actual local clip in approximate views for selected destinations
  only, with their effective caption/account identity and resolved YouTube title.
  Preserve chosen-cover capability and watermark notes.
- Keep post metadata bound to its captured owner session while preserving plain
  local playback and owned temporary-network playback. Preview performs no AI,
  upload, FFmpeg rendering, publication or quota mutation.
- Add the approved TikTok-style bottom gradient, real caption/identity,
  decorative heart/comment/save/share rail with no counts, bounded caption
  expansion and safe narrow/large-text/landscape fallback. Label clip audio
  without inventing song details.
- Add playback-only volume 0–100%, committing slider changes on release, with
  mute/restore and retention across tabs/retry. Preserve owner/lifecycle/timeout
  guards; change neither system volume nor export audio.
- Preserve refreshed main `6afe4d6` (runtime `342470f`) and its Facebook routing/media behavior;
  use generic Facebook in this preview without claiming verified publication.
- Full Mobile rerun passes **2,867 tests / 6 skipped**. Analyzer, **150** Staging,
  **187** API/typecheck and **10** real-font visual checks pass. APK **12049**
  builds with eight source/environment checks passing and is installed with
  unchanged UID/storage. After manual sign-in, native play/pause/seek and volume
  100% → 36% → mute → 36% → 62% pass on an existing 45-second draft; Back preserves
  its clip, empty caption, zero destinations and one draft. An initial transient
  pause error recovered on explicit resume/pause; its cause is unconfirmed.
  Current Home shows Free with only YouTube connected, so latest TikTok/Instagram
  native tabs and the earlier Pro demo draft's restoration remain unverified.
  Older 12048 TikTok native evidence and final visual tests retain their separate
  scope. No draft save/field edit/AI/upload/post/purchase occurred in this follow-up.
  Scope is 14 files; the bounded Sentry fixture changes tests only and
  process telemetry suppression changes no SDK/OS/production monitoring.
  No main/push/cloud deployment of this preview feature has occurred.
  No API/schema/dependency/configuration change is needed. Prior verification
  history and final results are in the
  [post-preview plan](docs/superpowers/plans/2026-10-24-publish-post-preview.md).

## Immersive post-preview follow-up (2026-10-24, local APK 12051)

- Follow the supplied full-screen reference: remove the bottom seek/replay/time/
  volume panel only from post preview, keep the actual video at its natural
  aspect ratio without cropping, and overlay caption/identity and decorative
  heart/comment/save/share icons. No social counts or account are fabricated.
- Tap the canvas to play/pause. Put playback-only volume behind the top speaker
  button; preserve mute/restoration, command/lifecycle and ownership safeguards.
  Plain local and authenticated network clip viewing retains its prior controls.
- Keep selected-platform chips, effective captions and YouTube titles. An empty
  destination selection still shows the shared caption and generic social rail.
  Move explanatory notes into an inline information panel that pauses playback
  and is removed together with the owner-bound preview.
- Preserve refreshed baseline `8872f0e` and its nine incoming API-security/docs
  commits. The refresh introduces no Mobile/schema change, and all ten candidate
  Mobile runtime/test hashes remain unchanged.
- Before the cosmetic follow-up, 12050 Mobile passes **2,880 tests / 6 skipped**, analysis has no issues
  and joint preview checks pass **76**. Fresh-baseline API static/build checks
  and **206 tests across 11 files** pass; this scope is distinct from 12049's 187.
  Final **163** Staging and **15** exact-color visual checks also pass. APK
  **12050** builds with eight complete-source and package/Firebase checks
  matching. Installed 12050 retains account/storage/draft. Native immersive tap
  play/pause, absent bottom controls and inline volume 100% → 34% → mute → 34%
  pass on the existing zero-target draft. An initial startup ANR recovered with
  one app-only restart; its cause is unconfirmed. Connected TikTok tab acceptance
  remains unverified. Final cosmetic **12051** adjusts Staging status-bar contrast,
  passes **44** player/**165** Staging checks and analysis, and builds with eight
  source/package/Firebase checks matching. Installation preserves UID/storage;
  native play/pause/replay, volume, information, Back and readable status icons
  pass. Its cold start reaches Home without an app restart. The actual clip is
  landscape/letterboxed and has zero destinations; native iOS and connected
  TikTok tabs remain unverified. The subsequent user instruction authorizes
  `main/push` for the verified UI without a backend deployment.
  Prior 12049 results are historical
  and do not establish acceptance of this candidate. No API/schema/dependency/
  configuration/backend change or publication is introduced. Track results in
  the [post-preview record](docs/superpowers/plans/2026-10-24-publish-post-preview.md).

## Looping wheel time picker (2026-10-24)

- Share one 24-hour Flutter wheel picker between Create Post and Calendar
  rescheduling. Loop hours/minutes independently without altering the date.
- Preserve the initial existing time, uploader 18:30 fallback, Cancel semantics,
  device-local display and UTC request serialization.
- Keep future-time/Starter 14-day/Pro 30-day rolling limits, monthly quota,
  auth/owner checks and queue safeguards unchanged. No API or migration change.
- Full Mobile tests (2,819 passed / 6 skipped), analyzer, 93 Staging-configured
  checks, real-font light/dark rendering and exact-source APK 12046 pass.
  The user subsequently authorized main/push. Native installation/acceptance
  and backend deployment are not part of that Git delivery. Record results in the
  [wheel-picker plan](docs/superpowers/plans/2026-10-24-wheel-time-picker.md).

## Compact caption AI controls (2026-10-23, Staging delivered)

- Replace the advanced target chips with a uniform two-by-two grid under
  `ให้ AI ช่วยเขียน` and `เลือกช่องทางที่ต้องการ`.
- Put the full existing writing profile and clip guidance behind `สไตล์`.
  Remove select-all/clear and the standalone cost row. Show the cost on the
  single action, now `สร้างแคปชั่น · N เครดิต` under the 2026-10-25 contract,
  disabled when no channel is selected.
- Preserve four manual editors, draft targets, selected-only AI preview/apply/
  undo. The original fixed one-credit rule is superseded by the 2026-10-25
  per-channel contract. The original presentation release introduced no API,
  contract, quota, schema or backend change.
- Follow-up source `4a1c0f9` is merged/pushed to main; Staging APK 12045 is
  installed with account, UID and internal storage retained. Selected targets
  show only a green border and unobscured logos. Analyzer, 35 Staging checks,
  semantics and light/dark rendering pass. Native zero/two-target checks pass;
  all-four native interaction was stopped after independent screen changes.
  Earlier compact-panel full-suite/style-cancel evidence is recorded separately.
  No live AI request, profile save or publication was made.
  The original UI used the then-current API without a backend redeploy; the
  later pricing change requires coordinated delivery. Track results in the
  [compact-panel plan](docs/superpowers/plans/2026-10-23-caption-ai-compact-panel.md).

## Select AI caption channels (2026-10-23, Staging Live)

- Keep four advanced manual caption editors and start AI targets empty. Let
  users explicitly choose 1–4 supported channels before generation, independently
  of the destinations they later publish to.
- Request only the chosen channels. Preview, apply and undo only those variants,
  retaining unselected caption text and guarding against stale results.
- Remember targets in the current local draft across mode switches and reopening;
  exclude them from reusable channel/account preferences and post/recovery API
  settings. Historical drafts without target metadata remain readable.
- The original fixed one-credit rule for a set is superseded by the
  2026-10-25 per-channel contract. Preserve fallback refunds and plan/owner/media
  checks. The selection release's API already supported subsets; that work
  needed no backend runtime or deployment change, schema or migration.
- Checks pass 2,787 Mobile tests, 2,504 API tests, static/schema checks and
  28 Staging-configured widget smoke tests. Staging APK 12043 builds and package
  configuration checks pass. Feature `dab94fb` is on `main`/GitHub with passing
  Backend/Mobile CI and an exact-source Live Staging synchronization deployment.
  APK **12043** is installed, preserving account/data. Emulator smoke passes
  default-empty/disabled generation, one-target mode retention and two-target
  local-draft restoration after a cold restart. The created test draft was
  removed, restoring the original empty draft list. No real AI, credit spend,
  purchase or post occurred. iOS no-codesign CI also passes; provider quality
  and real publication remain unverified. Record actual results in the
  [selection plan](docs/superpowers/plans/2026-10-23-caption-target-selection.md).

## Four-platform advanced captions (2026-10-23, Staging Live)

- Add optional advanced caption settings in Create Post: hide the shared editor,
  show four manual platform fields, and offer an explicit AI request for all
  four with preview/apply before replacing text and undo to pre-AI text.
  Preserve shared and advanced edits across toggles, drafts and
  stale/account-switched asynchronous results.
- Store optional per-post captions inside the existing platform-settings JSON;
  validate and deliver each selected destination's effective text. Retain old
  clients, immutable recovery, existing disclosure/visibility/target settings and
  platform-specific limits. Facebook now targets Page Reels under the contract above.
  Preserve YouTube's explicit empty description (`caption: ""`, including
  trimmed whitespace) without falling back to shared text, while retaining
  title/settings requirements and rejecting empty overrides for the other three.
- Generate platform-adapted variants from the selected clip in one provider
  operation; the 2026-10-25 contract atomically reserves one credit per selected
  channel. Keep writing style and grounded evidence rules.
  Incomplete/malformed output is a labeled local fallback and
  uses the existing quota refund path. No new provider, credential or migration.
- Keep per-post captions out of reusable channel defaults. Derive an automatic
  YouTube title from its effective description and preserve explicit titles.
- Released to `main` and Staging: caption commit `6b06c63` plus startup owner
  conflict fix `a391bc4`; API-first installation of APK 12042 preserves data.
  Final CI passes 2,500 API and 2,767 Mobile tests. The unchanged Mobile tree
  also passes iOS compilation without signing. Existing plan/quota reads pass
  from the installed client; actual AI output and real publication remain
  untested for this feature. Results and remaining acceptance are in the
  [implementation plan](docs/superpowers/plans/2026-10-23-platform-captions.md).

## Sentry error reporting (2026-10-23, candidate verified)

- Add opt-in, errors-only monitoring to Flutter, the API/in-process publisher
  and the optional standalone worker. SDK pins are `sentry_flutter: 9.30.1`
  and `@sentry/node: 11.8.0`; retain the existing iOS CocoaPods build path.
- Keep `SENTRY_DSN` empty by default and deployment environments explicit.
  Staging must report as `staging` even though its Node runtime uses
  `NODE_ENV=production`; `SENTRY_RELEASE` is an optional safe build label.
- Allowlist outbound error/stack/operation/status fields; exclude customer
  content, identities, credentials and provider payloads. Retain bounded Mobile
  OS/manufacturer/model and Dart/Flutter runtime metadata without device IDs,
  device names, users or arbitrary context maps. Keep tracing,
  performance data, logs, Replay, screenshots, view hierarchies and attachments
  disabled. No API contract, schema, migration, billing or publish behavior change.
- Capture Dart/Flutter errors and safe handled API 5xx failures, plus server,
  scheduler, publishing and optional worker errors. Disable Flutter's native
  SDK/crash handling until a separate native-envelope privacy boundary is
  verified: Sentry-native crashes/ANRs remain out of scope. Preserve existing
  native Crashlytics collection whenever Firebase monitoring is available.
- Sentry owns only Dart error hooks after successful initialization; retain
  Crashlytics Dart hooks as fallback and Firebase Analytics/Auth/FCM in both paths.
- Full API regression/typecheck/build/schema checks and final-3 Mobile
  tests/analysis/build pass. APK12041 passes exact-source/native startup checks,
  retains QA Pixel_8 UID/data and reports a generic API 500 event with matching
  release/environment. Native Crashlytics collection reads enabled. A local
  API synthetic error reaches its own project. Both latest dashboard events
  lack geography after IP storage prevention and the `$user.**` scrub rule.
  No real post, purchase or native crash was triggered. Live entitlement and
  full publishing/checkout acceptance were not verified. The 2026-10-23
  `main/push/deploy` request authorizes main integration, GitHub push and Staging
  API activation. Feature `b486ca3` and lockfile-only fix `35512aa` are on
  `main`/GitHub. The first Staging build failed at `npm ci` and kept the old live
  API. After the lock fix, an initial cloud event exposed an empty-stack warning.
  The minimal API sanitizer fix `12e0589` is on `main`; its unchanged API tree
  is served by current Staging source `a0540a3`, with
  health/readiness 200, 22 migrations/none pending and no monitoring-init failure.
  Its 2,422-test API suite/static checks pass; the repeated isolated cloud event
  matches source/release/environment and shows no processing error. Prior
  Backend/Mobile CI and unsigned iOS compilation pass; current CI `39893356044`
  also passes Backend and Flutter Mobile with the Mobile tree unchanged.
  The separately authorized drain-first drill proves an actual same-process
  uncaught fatal, exact Sentry Fatal/Unhandled event, exit 1 and Render restart.
  Temporary instrumentation is removed; the clean deployment is healthy with
  all global publish counts zero. An observed roughly 33-second 502 interval
  is recorded. A crash during active publishing was not tested.
  Forced Express-main-process HTTP-error and iOS/native-crash runtime acceptance
  remain separate gates. Track
  actual results in the
  [work record](docs/superpowers/plans/2026-10-22-sentry-monitoring.md).

## Calendar selected covers (2026-10-21)

- Show each saved selected cover in a 9:16 thumbnail beside the compact post
  details, with a one-line caption and ellipsis plus a readable placeholder for
  missing or unavailable images. Full captions remain in post details.
- Preserve complete calendar history, date/platform filters, status refresh,
  pending activity and existing post/queue actions. Load selected-day covers
  through the existing exact-owner read with bounded concurrent requests.
- Recover a saved legacy frame when no cover image was stored, defaulting to
  the first frame when no frame choice was recorded. Preserve
  chosen images for new posts on all four supported destinations while retaining
  historical upload receipts and their retry identity.
- Keep HTTPS fetching in Dart and stream bounded video ranges through a private
  loopback proxy to the existing extractor, whose native package lacks TLS.
- No backend, schema or dependency change. The earlier installed APK12035
  exposed a legacy-data gap, and an installed APK12036 component check exposed
  unsupported native HTTPS. The expanded fix passes 2,725 Mobile tests (six
  optional skips), clean analysis and build. APK12039 is installed and native
  Calendar cover/one-line-caption acceptance passes, as tracked in the
  [work record](docs/superpowers/plans/2026-10-21-calendar-post-covers.md);
  the user authorized main integration and GitHub push on 2026-10-21. No API
  deployment or migration is required, and no manual cloud deployment, real
  post or purchase was performed for this release.

## Usability review follow-up (2026-10-21)

- Address the seven priority themes from the 100 synthetic scenarios: detail
  status freshness, visible validation, safe result/recovery navigation, readable
  text and small-screen onboarding, explicit disconnect confirmation, consistent
  quota units/reset time, and searchable history with channel/date context.
- Retain read-only recovery and independent per-channel outcomes. Reviewing a
  failure does not automatically resend or copy a successful channel into a new
  publish request. Existing channels, defaults, explicit consent and purchased
  credit accounting stay intact.
- New API contracts are additive: authenticated owned `GET /posts/:id` and an
  optional monthly reset timestamp. API first, Mobile second; no migration or
  new purchase/provider integration. Add-on sales stay disabled.
- Native store/provider acceptance, physical-device performance, full translation,
  notification history across sessions/devices and server-side history pagination
  remain separate work. Preserve the approved icon-only center action pending
  actual-user feedback. Local verification/delivery is recorded in the
  [work record](docs/superpowers/plans/2026-10-21-ux-review-fixes.md).

## Staging dependency/runtime release (2026-10-20, delivered)

- Start from verified remote `main` `c2777a8f93048d88efb596fddbaa7244dc0f3595`
  in a separate managed worktree; preserve the dirty older checkout.
- Select only Firebase Admin 14.5.0/Morgan 1.12.1 dependency fixes, the scoped
  Prisma 6.19.3/deepmerge-ts 8.0.2 override, modular FCM sender with 13 regression
  cases, and Staging configuration/tests/docs. No new schema or migration;
  retain current Mobile, admin/trial access, CI and ElevenLabs/Gemini providers.
- Reconcile local infrastructure fields to the observed Starter/main/manual
  web service and Basic 256 MB/1 GB PostgreSQL 18 database. Source `0a43e7b`
  is Live on Staging deploy `dep-dbbmva3bc2fs73bnpemg`; its original delivery
  preceded main integration.
  Candidate checks pass on Node 22.23.3/
  npm 10.9.9: predeploy 2,305 API tests pass with `--maxWorkers=2`, 18 database integration tests skip;
  typecheck/build/Prisma/catalog checks, clean install and dependency tree pass,
  and the production audit including optional dependencies reports zero findings.
- Predeploy Dashboard/shell checks confirm Staging DB/Firebase/R2 identity and
  credential presence, 20 matching applied migrations, `SELECT 1`, and empty
  publish backlog. Live Social is `postpeer`, differing from the Blueprint's
  `disabled`: preserve Dashboard values and deploy only the reviewed SHA without
  a Blueprint sync or a merge into production's `main` branch. New-instance SHA
  and Node 22.23.3 are confirmed; startup has 20 migrations/none pending,
  health/ready return 200 and no-token checks return 401. Node 26.12.0 is the
  predeploy snapshot. Provider/device E2E remains open; Production stays
  user-suspended. Documentation follow-up does not change the deployed API SHA.
  See [Staging delivery](docs/STAGING.md).
- Local DB follow-up on the same runtime source uses a fresh loopback-only
  PostgreSQL 18.1 fixture with all 20 existing migrations. All 18 DB tests pass
  under both UTC and Asia/Bangkok sessions; the full API suite with the fixture
  enabled passes 138 files/2,323 tests with no skips. All 18 application tables
  are empty after cleanup and the fixture server is stopped. No runtime code,
  schema or deployment changes; provider/device acceptance remains open.
- The user subsequently authorized main/push. Runtime `0a43e7b`, delivery docs
  `39f96f9` and DB follow-up `ad788aa` are fast-forwarded into `main` from
  `c2777a8`. Only documentation changes afterward; verified API/Mobile inputs
  remain unchanged. A `[skip render]` integration commit preserves the observed
  Production user-suspended and Staging manual-deploy state; no new API deploy.

## Publishing progress motion (2026-10-20, locally verified and Staging APK installed)

- Local Home follow-up: improve visibility of sending feedback using Calendar's
  badge → inset rail → actual channel result order, retaining shared motion and
  status/poll/navigation behavior. See the
  [Home work record](docs/superpowers/plans/2026-10-20-home-publishing-feedback.md).
- Implemented the selected smooth full-screen progress treatment while retaining
  real stage percentages, outcome labels, publishing/retry and navigation guards.
- Lifecycle/reduced-motion behavior, narrow/enlarged-text layouts and truthful
  outcomes pass 51 focused cases and the full Mobile suite (2,488 passed / three
  optional skips). The final opt-in render passes separately with five pending
  screen captures. Analysis is clean; Staging x86_64 APK12028 is built and its
  package/environment verified. Guarded native update to 12028 passes, preserving
  the signed-in Home, existing draft, quota, connected channels and history.
- Source is integrated into `main` on 2026-10-20 for the authorized main/push
  delivery. No API/configuration/schema/dependency changes or migration;
  no real provider publishing was used and no API deployment is required.
- [Work record](docs/superpowers/plans/2026-10-20-publish-progress-smooth-motion.md).

## Remembered channel settings (2026-10-20, YouTube native restart verified)

- Remember allowlisted choices locally per owner, endpoint and connected channel.
- Preserve explicit Save/Cancel, same-clip draft precedence and fresh content
  declarations. TikTok privacy and interactions remain manually selected.
- Integrated follow-up: preserve TikTok music/policy checkmarks while editing viewers,
  interactions or AI in the open sheet; keep disclosure/account/content
  invalidation. Add sequence regressions for all four platforms; see the
  [consent work record](docs/superpowers/plans/2026-10-20-platform-settings-consent.md).
  Source is in `main` for the authorized main/push delivery; APK12029 is locally
  verified but not installed. No API deployment or migration is needed.
- Guard delayed reads/writes against account, channel and form changes; clear
  owner defaults after successful account deletion. No server migration.
- Local full Mobile verification passes: 2,480 tests, two optional skips and clean
  analysis. Staging APK12027 is built and installed. Native YouTube Save and
  force-stop/restart restore the reusable choices in a fresh post, while
  clip-specific declarations stay unanswered. Cancel/reopen and final Home
  preservation also pass. Meta coverage remains automated fixtures. Integrated
  into `main` with smooth progress on 2026-10-20; no API deployment is required.
  Evidence and delivery limits:
  [work record](docs/superpowers/plans/2026-10-18-remember-platform-defaults.md).

## Publishing activity (2026-10-18, Android Staging delivered)

- Implement selected variant 3 in Home, Calendar and detail: one motion clock
  per post drives the sending badge, indeterminate rail and sending channel
  icons, with real per-channel results and no fabricated percentage.
- Refresh Home's existing recent-post read every 30 seconds only for loaded
  `PUBLISHING` posts, while resumed, active, on the current route and owned by
  the current signed-in user. Preserve Calendar's existing visible
  `QUEUED`/`PUBLISHING` polling. Detail was a snapshot in that release; the
  2026-10-21 usability candidate adds a single-post GET and detail refresh.
- Preserve reduced-motion/ticker/lifecycle guards and delivery-outcome truth.
  No API, schema, dependency, flag, entitlement or migration changes. Targeted
  tests pass 145/145; full Flutter passes 2,437 with two optional previews
  skipped, and analysis has no issues. Release CI repeats the suite, tests 17
  configuration/receipt guards and builds APK 12026 with the existing Test Store
  settings. APK inspection, local signing, guarded update and native
  Home/Calendar/detail/Account smoke checks pass with retained user data.
  The compatible Staging API is Live. Native active-sending/FPS and new provider
  publication remain outside these read-only checks; see the
  [implementation plan](docs/superpowers/plans/2026-10-18-publishing-motion.md).

## YouTube title from shared caption (2026-10-18, local implementation)

- Write one caption and preview the YouTube title automatically: first sentence
  of the first nonempty line, `<`/`>` removed, maximum 100 Unicode code points.
  Keep the full caption as the description with existing guards unchanged.
- Offer `ปรับชื่อเฉพาะ YouTube` for an explicit title; preserve it across caption
  edits and provide `ใช้ชื่อจากแคปชัน` to reset. Keep automatic/custom choice in
  existing local drafts and resolve the nested API title before review/send.
- Allow a blank caption only for YouTube-only intent with a valid explicit
  `platformSettings.YOUTUBE_SHORTS.title` and every required YouTube declaration,
  including create, accepted replay and read-only recovery. Other destinations
  still require a caption. Preserve readiness, quota, scheduling and target checks.
- Local automated verification passes; [results and delivery limits](docs/superpowers/plans/2026-10-18-unified-platform-settings.md#youtube-title-follow-up-2026-10-18-local-implementation)
  include APK12025 build/install with retained data and basic Home launch.
  Entitlement loading, exact updated API deployment and provider publication
  remain unverified. No new migration, API field or service configuration is
  needed; blank descriptions require the updated API. Earlier records remain historical.

## Unified channel settings (2026-10-18, Staging delivered)

- Use one compact/scrollable settings shell for four platforms with account
  identity, grouped fields, Cancel/Save, keyboard support and validation reasons.
- Keep TikTok Inbox short and independent of Direct capability loading; fetch
  fresh capabilities for Direct, reject stale results and preserve manual consent.
- Keep YouTube title, audience, realistic synthetic-media and certification
  choices explicit; show Instagram feed/cover and Facebook Page Reels/draft intent.
- Add optional IG/FB AI-media disclosure through draft, review, immutable intent,
  API validation and PostPeer mapping, preserving absent legacy declarations.
- API regression suite passes 127 files / 2,207 tests with typecheck/build/Prisma.
  Mobile **2,371 tests** pass (two optional previews skipped), analysis and the
  Staging APK12024 build pass; the new five-sheet preview runs separately. Evidence:
  [the work record](docs/superpowers/plans/2026-10-18-unified-platform-settings.md).
- Source `866f0e3` is merged/pushed to main and Live on Staging deploy
  `dep-dba2oieq1p3s73a3g6qg`. Exact-source Backend/Flutter CI `39089186176`
  and unsigned iOS `39089186129` pass; health/readiness return HTTP 200.
  Staging's API contains its memory-queue publisher, with no separate worker.
  Android **12024** is installed after a verified full AVD backup, adding a
  separate 16 GiB private volume and recovering the existing data. A guarded
  same-volume reinstall and cold boot preserve version/UID/storage. Native Home,
  the same two drafts, local video playback and a read-only TikTok Inbox check
  pass. Other new native platform dialogs/publication are not claimed. Other
  environments must release API/all workers before Mobile; no migration, plan or service
  environment change is needed.
  Connected-account publication and iOS device delivery remain separate checks.
- Guard future Android updates against silently selecting another storage
  location. The launcher verifies the current mounted volume/UID/version, pins
  that volume, preserves the build number and fails without uninstalling or
  clearing data. Staging `run` rejects adopted Android storage; use the guarded
  launcher followed by `flutter attach` instead. This separate installer/tool
  follow-up has local validation; the earlier CI and Staging deployment cover
  source `866f0e3`. The user authorized its separate tool/document push.
- Follow up separately on a restored old draft's connection warning despite
  TikTok/YouTube being connected. Source inspection suggests initial connection
  loading leaves an earlier validation message stale; add a targeted regression
  before changing the Dart flow. This storage update does not claim publishing.

## Administrator console and trial access (2026-10-18)

- Delivered follow-up: consistent read snapshots, batched all-account usage reports
  with UTC date ranges, whole-cohort totals, explicit quota/delivery/AI-reservation
  definitions and safe manual/visible-page refresh. Preserve owner/viewer and
  trial/paid-access boundaries. Actual local PostgreSQL concurrency/load and
  responsive browser flows pass. Source `fc457b2` is merged/pushed to main and
  Live on Staging deploy `dep-dba64iqjnfac73egt8i0` at 13:10:11 Bangkok;
  exact-source API/Flutter CI `39102818467`, health/readiness, source assets,
  fresh owner login and all-account report reads pass. No trial/customer writes,
  Mobile update, new migration or flag change were needed. See the
  [usage accuracy work record](docs/superpowers/plans/2026-10-18-admin-usage-accuracy.md).

- Implement seven Thai admin views, member/monthly-usage inspection, safe post
  failure summaries, trial-period reports/CSV and audit history.
- Separate paid RevenueCat entitlements from local expiring Starter/Pro trials;
  support grant/extend/revoke with 7/14/30-day presets and preserve usage.
- Restrict mutations to recently authenticated allowlisted Firebase owners;
  viewer roles are read-only. Use atomic versioned/idempotent grant-and-audit writes
  behind target account deletion fences. Keep all flags disabled by default.
- Local implementation and fixture/database/browser verification are recorded in
  [the implementation plan](docs/superpowers/plans/2026-10-18-admin-console-and-trial-access.md).
  Source `50fba5e` is Live on Staging with both earlier migrations and healthy HTTP checks;
  the read-only Firebase credential is installed and both flags are enabled in
  its API/memory-queue process. Owner identity, Web app and sign-in domain are configured.
- Manual Google owner sign-in and all seven live read-only views now pass, with
  member search/details, post status/platform/date filters, trial review/cancel
  and 390px responsive checks. Still verify authorized real trial grant/extend/
  revoke, nonempty CSV, live ordinary-user denial and Mobile trial refresh.
  No real customer trials were granted. Report estimates require
  operator-supplied rates; conversion
  attribution and invoicing are outside this version.
- Update Mobile billing to confirm purchased access independently of trials and
  gate legacy purchase preparation during a trial upgrade before customer rollout.
- Admin UX follow-ups are pushed to main and Live in `dep-dba5im61egvs739eoteg`:
  Thai overview/per-channel results distinguish draft delivery and unknown
  publication outcome; neutral member details precede explicit trial actions;
  empty Trials/Reports/Audit explain next steps and disabled CSV. Owner/Viewer,
  local grant/extend/revoke, report CSV and 390px layouts were verified with
  memory fixtures; these do not replace the remaining live acceptance checks.
  API/Flutter CI `39100690775`, release asset hashes and existing-owner overview/
  post reads pass. Fresh owner login into the new UI remains unverified.

## Channel publishing preflight (2026-10-15, Staging delivered)

- Add consistent YouTube/Instagram/Facebook caption guards to Mobile, new API
  requests and the provider publisher; retain TikTok and accepted replay behavior.
- Add read-only owner-bound channel readiness with reconnect/permission guidance,
  explicit evidence only, unverified unknown capabilities and API-404 compatibility.
- Probe the actual outgoing file before upload; preserve original media, local
  drafts, optional receipt metadata and unknown request identity across retries.
- Expose account revisions for every connected platform and recover accepted
  original submissions through an owner-scoped read-only lookup before new
  preflight guards, without creating or enqueueing another post.
- Keep YouTube title suggestion editable and blank-only; display every selected
  YouTube declaration, Instagram feed choice and YouTube Terms notice at review.
  Facebook now targets Page Reels; real-account Reel E2E remains pending.
- Backend **2,163 tests**, Mobile **2,351 tests** (one optional preview skipped),
  typecheck/build, schema/helper checks, analysis and the exact Staging APK build
  pass. Diagnostic runtime evidence and remaining external checks are in the
  [verification record](docs/superpowers/plans/2026-10-15-platform-publish-preflight.md).
- Source `2e86634` is merged/pushed to main and Live on Staging deploy
  `dep-db8focbrjlhs73bs5s90`. Exact-source Backend/Flutter CI `38766556966` and
  unsigned iOS `38766556987` pass. API shipped before the data-preserving Android
  **12023** update; login and both drafts remain, authenticated readiness reads
  and refreshed Home pass. No new database migration is required.
- TikTok/YouTube remain connected with unconfirmed publishing capabilities;
  Instagram/Facebook are disconnected. Real publication, iOS device checks and
  Production rollout remain unverified and outside this delivery.

## TikTok Direct Post (2026-10-15, Staging delivered)

- Implement account-bound creator-info, explicit privacy and interaction choices,
  commercial/AI disclosure and consent. Keep Inbox available and preserve all
  existing draft/private delivery and idempotency behavior.
- Recheck account revision/current capabilities before accepting new posts and
  again at worker execution. Do not change privacy or fall back to Inbox silently.
- Require selected-platform final Direct proof; bounded status GET must never
  resend an accepted CREATE. `LIVE` means published to the selected audience.
- Delivered source `5681602` to main and Staging deploy `dep-db8ep7brjlhs73e46qc0`,
  then updated Android to 12022 without clearing data. Exact-head Backend/Flutter
  CI `38757735457` passes; iOS CI `38757735448` passes its unsigned build and
  artifact checks. No iOS device test or installation is claimed.
- Read-only account-bound creator options and the actual logged-in settings UI
  pass. Provider audit/public approval and a real Direct publication remain
  unverified; no upload, publication, historical repair or Production change was
  made. Other environments need API-first rollout with no new schema migration.
- Record exact targeted/full verification and release evidence in
  [the implementation record](docs/superpowers/plans/2026-10-15-tiktok-direct-post.md).

## TikTok Inbox CREATE confirmation (2026-10-15, Staging delivered)

- Correct the later 13:48 local FAILED result whose canonical provider GET
  proves an Inbox handoff. The documented CREATE summary reproduces rejection
  before GET; its use in the real incident is inferred because that raw CREATE
  response was not captured.
- Implement narrow bounded GET confirmation for requested INBOX_DRAFT using a
  genuine CREATE post ID when the successful selected summary lacks status/ID.
  Keep strict selected-platform Inbox evidence, failure/pending
  precedence and provider-ID binding; never resend the POST or infer success
  from parent status or a messages URL alone.
- Regression-first tests reproduce 21 failures; all 102 corrected publisher tests
  pass and independent review finds no blocker. Full API verification passes
  119 files / 1,981 tests, typecheck/build, Prisma checks and two compiled smokes.
- Source `e191ed7` is on main and Live on Staging deploy
  `dep-db8dr449v7es738gr9vg` at 14:07:09 UTC; CI `38747979249` passes Backend
  and Mobile (2,252 tests/analysis). Health/readiness pass twice, with 18 migrations
  and the empty-backlog guard verified. The separate two-row repair/readback and
  APK12021 Calendar/detail confirm `ส่งเป็นร่างแล้ว` at 14:13 UTC. All five
  unresolved markers are preserved; no provider resend or new APK is included.
  User-side TikTok Inbox/public posting remains unverified.
  Preserve the completed earlier repair, native APK12021, phone-gate UX,
  schema, quotas, flags and Production. Plan:
  `docs/superpowers/plans/2026-10-15-tiktok-inbox-create-confirmation.md`.

## TikTok Inbox result mapping (2026-10-15, Staging delivered)

- Recognize the observed completed TikTok Inbox receipt as the existing DRAFT
  delivery outcome, retaining the genuine provider post ID and all failure,
  pending, target, mode and duplicate-publication guards.
- Keep Direct Post blocked for new requests and reject Inbox receipts as proof
  of private/live publication. Public posting still requires the user to finish
  the TikTok Inbox flow. Do not resend to repair a status discrepancy.
- All 1,947 API tests, typecheck/build, Prisma checks and compiled worker smoke
  pass. Source `7a55fe8` is merged/pushed to main; exact-head CI `38741265826`
  passes Backend API (119 files / 1,947 tests) and Mobile (2,252 tests/analysis).
- Staging deploy `dep-db8d6gss728c7391ajp0` is Live at 13:23:04 UTC with
  health/readiness HTTP200, 18 migrations/no pending and the empty-backlog guard
  retained. No environment/configuration, Production or new APK change is made.
  The separately guarded one-time historical repair changes only the matched
  parent/TikTok receipt; Calendar and detail show `ส่งเป็นร่างแล้ว` without error.
  All five unresolved operation markers are preserved; no provider resend or
  queue replay is performed. User-side TikTok Inbox/public posting remains open.
- No schema, package, API shape or mobile rebuild is required. Historical FAILED
  rows need separate owner/intent/provider proof before any receipt correction.
  Receipt: `docs/superpowers/plans/2026-10-15-tiktok-inbox-delivery-status.md`.

## TikTok native completion with background engines (2026-10-15)

- Correct the real-app FFprobe timeout caused by a background FlutterEngine
  replacing the plugin's global completion-event owner. Await each session's
  native MethodChannel result while exposing its cancellation ID immediately.
- Keep bounded cancellation, H.264/AAC CFR30 and actual decoded-prefix checks,
  draft/request/receipt safety, Firebase messaging, and Calendar activity intact.
- Normalize only the upload copy into TikTok's 360–4096-pixel dimension range;
  the actual 180x320 QA source needs 360x640 output. Use the local v2 receipt
  policy and existing explicit legacy-recovery guard, retaining source media.
- All 2,252 Mobile tests and analysis pass, including nine native-adapter
  regressions. Six native two-engine cases, a cold start, scoped cancellation,
  and the exact Staging APK startup/configuration checks also pass.
- Staging APK 12021 is installed on the user emulator without losing its account
  or draft. TikTok remains selected at review. Public publication is unverified.
  The earlier account check showed Free with 0/3 remaining and an unverified
  phone; existing free-plan rules require phone verification. The native source is included in
  the main/CI/Staging delivery above; the installed APK12021 stays unchanged.
  Push CI skips APK building/uploading. No native-fix migration or configuration
  change is required. Receipt:
  `docs/superpowers/plans/2026-10-15-tiktok-native-session-completion.md`.

## TikTok frame rate and complete Calendar activity (2026-10-15)

- Include immediate, scheduled, and partially published owner activity in
  Calendar, using real local activity dates and retaining queue-only actions.
- Prepare TikTok-selected video as validated H.264/AAC constant 30 FPS before
  upload, checking actual decoded frames in a bounded prefix; preserve source
  media, ownership, request IDs, and upload-retry safety.
- Keep legacy incompatible upload receipts intact until the user explicitly
  starts a new attempt. Translate the known frame-rate rejection without
  exposing raw provider errors.
- Source `0f2941b` is merged and pushed to main; exact-head CI `38725833299`
  passes Backend and Mobile (1,914 API / 2,226 Flutter tests). Staging deployment
  `dep-db8bdj2vcj2c738t2ke0` is Live with health/readiness HTTP200, 18 existing
  migrations/no pending, and the empty-backlog activation guard retained. Full
  verification/native codec acceptance, APK delivery, and remaining limits are
  recorded in `docs/superpowers/plans/2026-10-14-tiktok-media-and-calendar-activity.md`.
  No social retry or Production change is included.

## Main integration (2026-10-13, completed)

- Fast-forward verified main `c4e52201` to exact feature head
  `be7732f6a14f9f91e6eda4a39179b30c385427ab` and push normally, following the
  user's authorization and CI `38386971185` success (Backend/Mobile, 2,058 tests,
  analysis8.9 s). Preserve local generated/QA files and exclude old dirty copies.
- Runtime matches Staging Live `7b0c51d` and installed8016. No new runtime patch,
  build/migration, config change or Production deployment; Staging auto-deploy is
  disabled and Production API/database remain user-suspended with no new deploy.
  Earlier Oct12 “no main merge” receipts are historical. Plan:
  `docs/superpowers/plans/2026-10-13-main-motion-audit-integration.md`.

## Mobile motion smoothness audit (2026-10-12, Staging delivered)

- Check main tabs, composer, video/results and account overlays for interrupted
  motion, stale actions, hidden tickers and lifecycle/disposal behavior.
- Keep controls/data stable, settle finite feedback without stale replay, stop
  background thumbnail decoding and preserve requested public-preview effects.
- Final source passes 2,058 Flutter tests and analysis (No issues, 8.6 s).
  Exact Staging x64 4016/8016 build/install and safe native navigation/preview
  background-resume/composer-return checks pass with data retained. Debug emulator
  samples do not prove a speedup or certify physical-device 60/120 FPS; physical
  profile-mode measurements with populated content remain unverified. No business API,
  schema/config/dependency change or new migration. Combined source
  `7b0c51d71090e5c080182daa8630d5b90e6d3d49` is pushed to
  `origin/codex/audit-system-fixes`; CI `38249605630` passed both jobs/2,058 Mobile
  tests and analysis14.2 s, with CI APK build/upload skipped. Render
  `dep-db6d96vavr4c73b21o2g` is Live at 19:39:44 GMT+7; 16 existing migrations/
  no pending and health/readiness HTTP200. Installed8016 and disabled publishing/
  memory queue remain; post-Live safe navigation preserves data. No main merge
  or second source deployment for the docs-only receipt. Keep initial8015 separate. Plan:
  `docs/superpowers/plans/2026-10-12-mobile-motion-smoothness-audit.md`.

## Bottom navigation motion (2026-10-12, Staging delivered)

- Add a finite selected-icon halo/lift/scale/color and native press feedback to
  the four ordinary dock tabs. Retain the running dot, center Create post,
  84 dp controls, localized semantics and existing navigation/state guards.
- Settle motion for reduced motion, background state and parent `TickerMode`
  without replay or new API/persistence/business triggers. No schema/config/
  dependency or migration change. Initial dock-only source passed 1,979 Flutter
  tests and analysis, including 13 new navigation cases. Exact Staging x64 APK
  4015/8015 was installed then; native feedback/composer return preserved data.
  Motion/accessibility guards use fixtures. Combined source `7b0c51d` passes CI
  `38249605630` and is Live through `dep-db6d96vavr4c73b21o2g` with current8016/
  2,058-test audit receipt retained. Keep the initial8015 history separate. Plan:
  `docs/superpowers/plans/2026-10-12-bottom-nav-ui-motion.md`.

## Account UI motion (2026-10-12, Staging delivered)

- Add Account-only finite content/sheet entrances and press feedback, preserving
  native gestures/semantics/hit targets. Respect reduced motion, lifecycle,
  parent `TickerMode` and the Account tab's existing active state.
- Preserve profile ownership/generation, email/phone verification, billing,
  settings, legal pages, deletion confirmation and sign out. No new request,
  persistence trigger, package rule, API/schema/config/dependency or migration.
- Final source passes 1,966 Flutter tests and analysis, including 29 new Account
  cases. Exact Staging x64 APK 4014/8014 is built/installed with the account
  retained; native read/browse/dismiss/tab-return checks pass with unchanged
  settings/account and retained scroll position. Mutation/business actions use
  controlled fixtures. Combined source `904a3f89c3601a1fac28eedfaf8781434b19bd49`
  is pushed to `origin/codex/audit-system-fixes`; exact-source CI `38205149761`
  passed both jobs/1,966 Mobile tests. Render `dep-db66eh8473hc73dabfcg` is Live
  at 11:53:11 GMT+7; 16 existing migrations/no pending and health/readiness HTTP
  200. Installed 8014 and disabled publishing/memory queue stay unchanged;
  post-Live safe navigation preserves account/shop data. No main merge. Keep the prior
  Shop 1,937/8013 delivery separate. Plan:
  `docs/superpowers/plans/2026-10-12-account-ui-motion.md`.

## Shop-link UI motion (2026-10-12, Staging delivered)

- Add brief press, current-only section entrance and drag-proxy feedback to the
  existing mobile manager/theme controls. Respect reduced motion, lifecycle,
  `TickerMode` and hidden tabs without keeping outgoing forms/actions mounted.
- Preserve serialized owner-scoped local autosave, explicit publication,
  confirmed-URL actions, all 100 templates and legacy/media/font/link settings.
  No public-page motion, API/schema/config/dependency or migration changes.
- The earlier Shop-only source passed 1,937 Flutter tests and analysis, including 22 new motion
  cases. At that Shop release, exact Staging x64 APK 4013/8013 was installed with retained account/shop
  data. Native read/click/browse/cancel/navigation checks pass; mutation/Save/
  Apply/publication paths are controlled fixtures. Combined source `904a3f8`
  passed CI `38205149761` and is Live via `dep-db66eh8473hc73dabfcg` with installed
  8014 retained; post-Live Shop has its two original links/confirmed URL. See
  `docs/superpowers/plans/2026-10-12-shop-link-ui-motion.md`.

## Guided create-post revision (2026-10-12, Staging delivered)

- Implemented the approved “ทีละขั้น” direction in the existing clip → caption →
  destinations → review/time/send flow. Keep explicit local drafts and one
  publish confirmation; make the AI action visible with optional controls
  collapsed, verified account names and a concise step/channel-count footer.
  Keep date/time in the shared review and schedule panel.
- Show only known clip metadata. Preserve cover editing, caption-style learning,
  SEO/fallback handling, owner isolation, account identity and all package,
  scheduling, submission/retry and truthful delivery-result guards.
  Reject stale owner/request connection results and hide identities while the
  current lookup is loading, failed or belongs to another owner.
- Reuse Home press feedback, short selection transitions and current-only step
  entrance. Stop motion for reduced motion, disabled `TickerMode` and background
  state. No endpoint, schema, provider, dependency or environment change or
  migration is required.
- Implement focused inline validation for missing caption, an AI waiting
  indicator/full-response reveal tied to the existing operation and a temporary
  check only after verified explicit local Save. Preserve manual-edit/owner/clip
  guards, fallback/review and existing save triggers. The final rapid-save guard
  rejects busy callbacks before clearing feedback generation. Save/guard tests
  pass 86/86, the final full suite passes 1,915/1,915 and analysis passes. Final
  feedback includes 10 new tests. At that composer release, APK 4012/8012 was installed with the same account;
  native blank-caption error/focus/keyboard is verified and the clean empty
  caption step was left open. The 187/187, 1,914/1,914 and
  native 8011 validation receipts precede this guard; AI/save outcomes are fixtures.
- The preceding connector source added three thin lines and pending-step
  outlines, and passed all 1,905 Flutter tests and analysis. At that release
  Staging APK 4010/8010 was installed with the same signer and retained session.
  Native clip/caption checks showed connectors/outlines and correct active
  selection without invented completion. The preceding 8009 four-step checks
  remain a separate receipt. Positive identity/metadata/schedule/AI and narrow/
  large-text cases use widget fixtures. The earlier user-selected form was left
  untouched by the agent; installation followed the user's return to Calendar.
  Authorized source `430f82ad1c493b5a8bcf1f51b007e2a7604dae1e` is pushed to
  `origin/codex/audit-system-fixes`; exact-source CI `38200231563` passed both
  jobs. No remote APK build was requested; local 8012 was unchanged in that delivery. Render
  specific-commit deploy `dep-db65d08473hc73d6fp50` is Live at 10:41:35 GMT+7;
  16 existing migrations have none pending and health/readiness return HTTP 200.
  Social publishing stays disabled, the queue remains memory and main is not
  merged. Keep receipts separate from Calendar/Home in
  `docs/superpowers/plans/2026-10-12-create-post-guided-ux.md`.

## Calendar compact revision (2026-10-12, Staging delivered)

- Implemented the approved compact list with week/month switch, Today, real
  per-day counts, all/four-platform filters and concise time/status rows. Initial
  week view keeps the existing upcoming-day selection if today has no post.
- Pass the selected local day into the existing composer without automatic
  saving/publishing or changed scheduling limits. Preserve terminal detail,
  partial/unknown outcomes and queued-post reschedule/cancel behavior.
- Keep confirmed content/selection during refresh, expose errors/retry and
  preserve owner/mutation guards plus visible-only polling. Run the relevant
  regression/full suite, analysis, exact-environment build and native QA.
- Share the composer's injected local clock with relative-date labels, preserving
  `DateTime.now` as the default and the original scheduling assertions.
- Authorized feature SHA `3368f4d` is pushed; exact-source CI `38187776818`
  passes 1,883 Flutter tests, analysis and Backend checks. Local Staging APK
  4007/8007 installs with retained data/session; post-deploy native smoke is a
  Home cold launch. Full native Calendar/date-handoff/Free-guard checks are the preceding
  8006 receipt. Positive queue/partial/mutations remain fixtures because the real
  account has no posts. Exact-source Render deploy `dep-db62jdvlot8c738l37q0`
  is Live at 07:30:34 GMT+7 on 2026-10-12; 16 existing migrations have none
  pending and health/ready return HTTP 200. Social publishing remains disabled
  on Staging. No backend/API/schema/
  provider/configuration change or new migration; Home delivery remains separate.
  Plan: `docs/superpowers/plans/2026-10-11-calendar-ux.md`.

### Calendar motion follow-up (2026-10-12, Staging delivered)

- Reuse Home press feedback and initial-loading skeletons. Animate day/view/
  platform selection over 160 ms, week/month height over 220 ms and only the
  current owner/day/filter section's fade/eight-pixel entrance over 180 ms.
- Preserve loaded content during silent refresh, current owner guards, date
  handoff, queue actions and all scheduling/package rules. Stop effects for
  reduced motion, inactive tabs and background state. Add no API, migration,
  environment setting or dependency.
- Authorized source `df8df1d` is pushed; exact-source CI `38189859822` passes
  1,891 Flutter tests, analysis and Backend checks. Render deploy
  `dep-db6327ajnfac73c7vr90` is Live at 08:02:20 GMT+7; 16 existing migrations
  have none pending and health/readiness return HTTP 200. At that Calendar
  release, locally verified Staging APK 4008/8008 was installed with its account;
  post-Live native refresh preserved the selected date/filter and account state.
  The later guided revision updates the local APK. Record this
  follow-up's checks and delivery separately from the preceding release in
  `docs/superpowers/plans/2026-10-11-calendar-ux.md`.

## Home next-action revision (2026-10-11, Staging delivered)

- Prioritize the latest explicitly saved owner/device-local draft or a clear
  create-post action. Keep the existing full-screen composer and navigation.
- Make subscription status compact; show real supported-channel connections,
  the earliest future queued post, recent delivery outcomes and server-confirmed
  store-link publication. Keep load errors distinct from empty/Free/disconnected
  states and expose retry.
- Preserve account isolation, subscription refresh, owner-only media previews,
  partial/unknown publishing outcomes, calendar state and all existing package
  gates. This is not a new statistics feature or API/provider integration.
- Base-revision local verification passes: 1,825 Flutter tests, clean analysis, 1,781 API
  tests/109 files, API build and Prisma validation/helper type-check. The
  exact-source Staging x86_64 APK is installed at version code 8003 without
  clearing account/draft data; native create/resume, Connections, empty Calendar
  and published-shop navigation pass. Positive future queue and partial/unknown
  outcomes use automated fixtures, not new customer posts.
- Implement the subsequently selected “พร้อมภาพปก” variant: full-width saved
  cover, or a muted paused local first frame with a five-second limit and static
  fallback; dispose decoders while hidden/backgrounded/replaced. Add a derived
  next-required-step hint, accessible press/loading feedback, and coordinated
  six-source pull-to-refresh retaining current content and known empty results.
  No playback, thumbnail write, FFmpeg job or media upload is added.
  Match the accepted 120 logical-pixel cropped cover, wrap metadata/stack actions
  for large text and preserve the notification button's semantic tap action.
  No persisted exact wizard-step field exists. Respect reduced motion and
  verify Thai large-text/narrow layouts. The preceding counts/version 8003 cover
  the base revision; the final follow-up suite passes all 1,863 tests in 2m54s.
  The current follow-up emulator has no draft; positive draft/cover cases use
  fixtures without creating customer data. Intermediate version 8004 native
  empty-Home/pull/press/navigation checks pass. Frozen-source version 8005 is
  built/installed with clean analysis and final native bell/pull/create-and-close
  checks passing. The final receipts are recorded in the implementation plan.
- No route/schema migration, credential, dependency or environment change is
  required. Local verification above is the pre-delivery receipt. Feature
  `ce89a0e464517f87f5902dd8ab32c764f2e67a72` is pushed to the existing branch;
  exact-source CI `38125004499` passes and Render deploy
  `dep-db5kk4h42hec739a7gg0` is Live. Post-Live health/readiness and native
  version 8005 pull refresh pass with the same session/Free 0/3/connections 0/4.
  CI intentionally skips APK build/upload; the verified local Staging debug/Test
  Store APK stays installed. All 16 existing migrations have none pending;
  main and Production remain unchanged. Acceptance and fidelity ledger:
  `docs/superpowers/plans/2026-10-11-home-ux.md`.

## System audit fixes (2026-10-09, Staging API delivered)

- Fix correctness before adding new screens: media-aware draft replay and saved
  upload receipts; account-scoped push registration/history; bounded startup
  restoration that cannot replace a newer session.
- Refresh Home/account quota after navigation, show stale-load failures and list
  all post statuses. Keep Calendar on the current month. Remove disabled EP UI.
- Autosave local shop edits with clear state; keep publishing explicit. Align
  mobile category rhythm/outline contrast with HTML, pause hidden animations and
  pin device-draft images before saving. Preserve legacy image references.
- Read store prices, bound purchase/restore waiting without duplicate purchases,
  identify AI fallback/refund its exact reservation, preserve text typed during
  template saving, and finish login legal/self-service and notification links.
- Staging API `9f0b729` is Live; all 16 migrations are applied with none pending,
  including the additive Post/Image migrations. CI `37897827978` passed Backend
  API and Flutter Mobile. Other environments still need API-first rollout. No paid
  provider, social publishing, Production activation, purchase or OTP test is
  authorized by the local fix itself. Native E2E remains a separate release gate.
- Current implementation and verification are tracked in
  `docs/superpowers/plans/2026-10-09-system-audit-fixes.md`. The exact split x64 APK
  is installed with the account preserved; injected-URI warm return passed.
  Real provider/browser return, cold callback, authenticated live route checks
  and direct `/ready` checks remain unverified.

## AI caption aspect-ratio fix (2026-10-09, Staging API delivered)

AI caption uploads use `purpose: "ai-caption-video"` for `.mp4` / `video/mp4`
clips at any aspect ratio, within the existing size limit. Known dimensions
are retained, including the observed `1080x2400` (9:20) clip; omit both when
unknown or supply both as positive finite integers. Generic uploads and mobile
posting retain 9:16 validation. Starter/Pro access, ownership and caption quota
stay unchanged. Staging API `9f0b729` includes this purpose; other environments
must deploy API before mobile. No migration is required for this purpose, and
the older API still rejects known non-9:16 dimensions.

Generation uploads the clip and optional Pro frames to configured
storage/providers and may consume mobile data. This fix has not performed real
remote user uploads, provider generation or paid state changes. Real provider
and production generation verification remains a separate release gate.

## Caption quality follow-up (2026-10-09, limited provider probes)

Ground the primary caption's opening hook in speech and visible clip evidence,
including silent clips, without invented claims or tutorial steps. Normalize
topical hashtags and SEO keywords, deduplicate up to five each, and leave
missing/invalid metadata empty instead of adding unrelated generic defaults.
Hooks remain separate. Thai is the prompt default unless actual speech or
dominant meaningful whole-clip text clearly establishes another language;
brands, account names, dates and numbers do not override it. Captions use creator
voice rather than an analysis summary, in one or two short sentences. Silent
menu navigation previews only visible menus/data without inferred business
setup, store creation or promotional benefits. Visible buttons, plan or
link labels do not establish actions or integrations. Real-clip temperature
decreases from 0.8 to 0.4; prompt instructions cannot guarantee factual accuracy.

Mobile excludes the literal `SEO:` paragraph from publish text, shows search
keywords in a collapsed current-screen area, and deduplicates tags already in
the caption. Replacing a clip retains all caption/guidance and requests review
of nonempty text; applied fallback AI also needs review. Optional local
`captionNeedsReview` defaults to false in manifest version 3 and persists until
`ตรวจแล้ว` or an applied non-fallback AI result. Text edits do not clear it.

Historical `AUDIO_ONLY` / `AUDIO_WITH_FRAMES` enums remain compatible: both
Gemini modes already send the whole MP4, while Pro adds up to three selected
frames. This is no isolated-audio transport or paid-policy change. Models,
retries, quotas, SDK and four-platform posting stay unchanged; no API field or
migration is required. Limited direct-provider probes improved the final primary
caption but still returned wrong silent-language metadata; this is not a general
quality benchmark or deployed API/quota verification. The local Staging APK is
installed; authenticated caption UI smoke remains pending at the user's choice.
This patch is not pushed/deployed; the earlier Staging receipt does not cover it.

## AI caption entitlement reconciliation (implemented, automated checks pass)

Only a successful initial subscription GET denying AI access with RevenueCat
enabled performs one existing authenticated server resync per Generate
action, followed by a fresh GET. Ignore the resync reply's plan and retain the
paid gate, Pro frames and owner/source guards. Paid users, disabled RevenueCat
and failed initial reads add no resync. Failure shows a Thai rights-verification
error with manual retry. This does not purchase, call SDK Restore, grant free
access or change package/quota/API/schema rules. Automated checks pass, including
1,744 Flutter tests and clean analysis. The exact-source Staging APK is built
and installed; native Free/denied gating and button usability pass. Live HTTP
sequencing and active-paid reconciliation/generation remain unverified.
No push/deployment occurred in this task.

Subsequent authorized delivery (2026-10-09) pushed audit source `c8e463d`;
exact-source CI `37918977276` passed both jobs and Render deploy
`dep-db4ccku0tbcc73dtlasg` is Live. The installed `24266aa` APK has the same
runtime. No API/schema/environment change, `main` merge or Production delivery
was made. Active-paid AI and live HTTP sequencing remain unverified; see the
chronological audit receipt.

## Caption style and remembered edits (2026-10-09, verification in progress)

Add optional `writingStyle` with tone, length and emoji presets, plus up to
three trimmed examples of 500 UTF-16 code units each. Legacy requests omit it;
invalid supplied styles are rejected. Manual presets outrank style examples,
which never establish clip facts or change language priority. Prompt compliance
is not guaranteed; labeled local fallback does not apply manual style.

Remember selected settings and eligible human edits per account on the device.
The visible remember switch defaults on; off excludes examples from requests
and learning. Clear memory keeps manual presets; account deletion clears that
owner's profile. Learn only edited accepted non-fallback AI on caption Next to
platforms, same owner/source and review cleared; not jump/save/cancel/unchanged
AI/fallback. Examples travel with explicit generation, without cloud sync or
social-history import. Deploy API before Mobile because old servers ignore the
field. Automated checks and the local `089dcb52` APK build pass. Staging API
source `7d568458` is Live; the new APK remains uninstalled to preserve the open
form. Native, real paid AI/style-quality and live HTTP verification remain
pending; prices, rights, quota, model/provider, schema and environment remain
unchanged. Exact-source CI and deployment are recorded in the audit follow-up.

## Android social-connect return (Staging API delivered)

New Android connect links can request the fixed `android` or `android-staging`
return target. The native warm return keeps the original screen and triggers
an authenticated connection refresh; a deep link alone never proves success.
Cold starts use the normal authentication gate and may lack the previous
in-memory screen. Browser Open App confirmation, X/manual refresh and iOS's
legacy external-browser flow remain supported. The fixed-target API is Live on
Staging at `9f0b729`; other environments must deploy API before mobile. Generate
a new link to use the return target; links already open retain their prior flow.
No new permission, provider OAuth app, schema or environment setting is required.
An injected VIEW URI returned to the original Connections screen with its 1/4
state retained on the installed Staging APK; the production URI had no handler
in that Staging-only installation. Real provider/browser handoff, Open App
confirmation and cold callback remain unverified.
## Security integration into current main (2026-10-13)

- Selectively port security fixes from the old audited worktree onto verified
  `main` `f5dea16` (advanced from initial `c4e5220` during preparation), preserving the current Store link/customization, full-screen
  composer, scheduling/idempotency and billing pending-confirmation behavior.
- Add final User/Post/Subscription owner write fences, legacy owner checks,
  session-bound auth/native/HTTP operations, purchase-readiness protocol 1 and
  push recipient UID. Keep legacy GET bootstrap for this additive rollout;
  retire incompatible mobile builds before considering read-only GET.
- Current status: selective source integration/review complete in the local
  branch; API 1,816 tests/build/schema and Flutter 2,171 tests/analyze pass.
  Runtime `9244f16` is on main and Staging Live; APK8017 retained-data Emulator
  smoke passes. Real purchase/OTP/publishing and background push acceptance
  remain separate gates. Previous
  audit cases and old CI/device smoke do not validate this delivery branch.
  Preserve Production feature flags and infrastructure; Staging/Emulator are
  the first delivery stage. Exact evidence belongs in
  `docs/superpowers/plans/2026-10-13-security-main-delivery.md`.

## Shared owner operation drain (2026-10-14, delivered to Staging)

- Continue local `1b5a403` on `codex/staging-regression-and-test-types`, based
  on verified remote main `f07ee30`. Add durable operation tickets and an
  owner-exclusive deletion claim. Seal before shared drain, refresh provider
  cleanup scope after drain, and hold work through HTTP handler/finally,
  managed uploads, queue admission and worker provider/results/notification.
- Keep crashes, unknown provider outcomes and release failures as private
  unresolved blockers. No TTL cleanup or automatic claim takeover exists.
  Known completed work releases its exact ticket; all-process synthetic tests
  pass 10/10 on PostgreSQL 18.1 with 18 actual migrations and two Node processes.
  HTTP/worker lifetimes run concurrently while explicit queue/store FIFO remains.
  Full API tests pass 1,909/1,909 in 119 files; typecheck, production build,
  Prisma schema/helper validation and independent review pass locally.
  Exact-source feature CI `38514367627` also passes 1,909 API/2,189 Mobile cases,
  typecheck/build/analyze/schema checks; exact-source main CI `38514981824`
  also passes.
- Source `7576ee3` is pushed on main and Live on Staging at 12:09:57 Asia/Bangkok
  through `dep-db7gsd3bc2fs73f64600`. Migration
  `20261014020000_track_owner_operations` is applied on `postdee_staging`, with
  all 18 complete before the upgraded API starts. Account/R2 part-recovery-abort
  smoke passes and the retained app's session/shop draft stay intact. Activation
  in another environment still requires migration/Prisma generation, every
  API/worker upgrade and quiescing/draining older binaries. Hosted flags and
  account creation remain untouched; Production stays user-suspended.
- Preserve `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled`
  and the single-instance Staging memory queue. Actual Redis/BullMQ, provider/
  Firebase, complete upload/abort, OAuth and legacy signed-PUT cancellation or
  expiry remain acceptance gates. The prepared disposable-account procedure
  has not been executed. Plan:
  [`2026-10-14-shared-owner-operation-drain.md`](docs/superpowers/plans/2026-10-14-shared-owner-operation-drain.md).

## Staging regression and test typing (2026-10-14, delivered to Staging)

- Start from verified main `f07ee30` on
  `codex/staging-regression-and-test-types`. Repair the 142 existing fixture
  typing errors and add `npm run typecheck` to CI after Prisma generation.
  Targeted tests pass 474/474; full API tests pass 1,871/1,871 in 116 files,
  with typecheck, production build and Prisma schema validation passing.
  Runtime, schema, dependencies and mobile source are unchanged in typing-only
  commit `1b5a403`, now included in the `7576ee3` main/Staging delivery above.
  No new APK installation or feature activation has occurred.
- The existing Staging app preserves its session and complete original shop
  draft through restart and a temporary edit/restore. Native synthetic clip,
  manual caption and zero-destination guard checks pass. Authenticated Staging
  R2 part transfer/recovery/abort pass; no upload completion, AI or social post.
- Actual local PostgreSQL 18.1 with 17 migrations and two independent Node
  processes passes seven checks. Late User/Post/Subscription writes and new
  remote admission reject `DELETING`/`DELETED` owners. An IPC simulation also
  demonstrated already-admitted remote work finishing after deletion in another
  process. The later shared-operation implementation addresses this callback
  lifetime gap; real Redis/provider draining remains unverified. Keep deletion
  disabled until the remaining rollout and cleanup acceptance gates pass.
- The user has no disposable Staging deletion account. Prepare its creation
  procedure only, using a separate test device/emulator and synthetic data;
  later account creation, deletion and flag changes require authorization.
  Plan and precise evidence:
  [`2026-10-14-staging-regression-and-typecheck.md`](docs/superpowers/plans/2026-10-14-staging-regression-and-typecheck.md).

## Account deletion retry authorization (2026-10-14, delivered to Staging)

- Start from verified main `1bf125c`; turn the SDK-fixture missing-identity
  failure into a regression test. The fixture is not confirmation that the
  same condition is reachable through real Firebase.
- Authorize the first deletion only from an extant Firebase identity with a
  finite `auth_time` within five minutes (future skew at most 60 seconds).
  Persist server time and `DELETING` atomically under the same UID in
  `ManagedUploadOwner`, separate from the cascading `User` row.
- Allow an older-token or missing-identity retry only when that UID has valid
  authorization and status `DELETING`/`DELETED`. Mock cleanup and generic
  lifecycle begin/finish calls must not create authorization. Absent storage
  methods or read/write failures must stop cleanup with
  `503 ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE` before marking the owner
  locally. Recheck proof under the owner lock before cleanup.
- Migrate `20261014003000_authorize_account_deletion` and regenerate Prisma
  before the API rollout. Do not backfill existing `NULL` tombstones: a legacy
  missing-identity account without proof needs verified operator recovery.
  Readiness response fields and the mobile flow remain compatible.
- Local verification passed 1,871 API cases, production API build,
  Prisma generation/schema/helper checks, 159 mobile compatibility cases and
  Flutter analyze. Disposable PostgreSQL execution passed 16 checks and real
  migration deployment. Main `3481f3f` is Live on Staging at
  `dep-db785nvavr4c73a1cm80`, with migration 17 applied and health/readiness ok.
  Exact-source CI `38452410378` passed API 1,871 and full Mobile 2,189 cases,
  build/analyze/schema; the CI compatibility follow-up adds an await during
  logo normalization. No new APK was installed. At that delivery, full
  test-inclusive TypeScript retained main's 142 existing fixture errors with no
  new errors; the separate local follow-up above repairs them. Keep Production
  deletion disabled; durable multi-process draining and real provider/device
  cleanup acceptance remain separate gates. Plan:
  `docs/superpowers/plans/2026-10-14-account-deletion-authorization.md`.

## Pending-work integration (2026-10-08)

- Mobile cleanup is integrated and pushed to `main` at `b1f793c`; app-source CI
  `37749129032` passed at `aafd076`. Preserve the dock/running dot, full-screen
  four-step composer, existing login and all hundred profile templates.
- Source integration `36dbaccb1d23ee46f9c970f2fdd8fff3d32b01d0` is committed,
  pushed and fast-forwarded to remote `main`; local/origin main agree. Its
  exact-source CI `37754460435` passed Backend API and Flutter Mobile. It includes owner-scoped Home
  previews through opt-in bounded signed URLs,
  database/queue `/ready`, 30-second graceful shutdown, trusted-proxy/IPv6
  rate-limit keys and recovery only from complete saved terminal results.
  Preserve main's route-level Prisma user preparation after validation/quota
  gates. Normalize case/trailing slashes when guarding mutating social/billing
  reads, and hold the same barrier through `GET`/`HEAD` upload-status
  reconciliation until response completion. No generic duplicate upsert is
  introduced.
- The integration adds a Staging-only build strip and portable Windows main launcher. Keep
  production off by default and retain current auth/Test Store validation.
- No schema/dependency/provider activation, subscription or infrastructure
  change is included. The memory scheduler and deletion/mutation locks remain
  single-process. Readiness is not provider E2E or separate-worker health.
- Current evidence and delivery gates are recorded in
  `docs/superpowers/plans/2026-10-08-integrate-pending-main-work.md`. Staging
  API source `9baa18c` (same runtime as `36dbacc`) is Live on 2026-10-08 deploy
  `dep-db3m2g59fdbs73ecbib0`; DB/queue readiness, authenticated empty-owner
  contracts and separate R2 image/video/range/cleanup checks pass. Nonempty
  native Home and two-authorized-owner isolation remain unverified, alongside
  provider crash/Redis/multi-instance/Production gates.
- The reconciled scaling roadmap is future work only. Shared owner coordination,
  shared rate limits and real failure/load evidence must precede horizontal
  scaling; no paid services or worker deployment are enabled by this plan.
  AI editing remains inactive compatibility code, Groq is not selectable, and
  new cross-platform statistics ingestion remains deferred.

## Current Product Decision (2026-10-05)

- Replace the AI video editing/Subtitle Studio entry with Profile link in the
  bottom navigation and the primary Home shortcut. The 2026-10-06 navigation
  revision places Calendar second and Store link fourth. Keep uploader AI
  captions, publishing, calendar, templates, and existing analytics.
- The 2026-10-07 create-post revision combines the selected Pinterest 1 + 2
  direction into a full-screen four-step composer: clip, caption, connected
  destinations, and review/time/send. Use a small poster with a full-screen
  local player, manually requested AI, secondary template/tool controls,
  explicit local Save draft and a changed-form exit prompt. Keep one final
  confirmation, editable inline review, real target-account/settings gates,
  per-user draft ownership and the existing submission request ID on retries.
  Closing returns to the previous shell tab; Calendar opens the same composer.
  Use a current-step counter, destination-specific Next labels and check marks
  for ready previous steps so first-time users can follow the bottom actions.
  This adds no API/schema/provider/pricing/entitlement change or migration.
  Verification is tracked in the dated addendum to
  `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md`.
- Provide one public profile page per authenticated account on every package,
  with 1–20 explicitly enabled custom links. Host `/p/<slug>` on the existing
  API domain; persist with Prisma and include profile cleanup in account deletion.
- Offer equal customization on every package: seven editable theme presets,
  colors and fonts per section and optional per-link overrides, logo/cover,
  solid/gradient/image backgrounds, categories and link order, and one featured
  promotion. Preview before publishing; keep product cards/prices for later.
  Use existing private media storage, not a new paid customization provider.
- The selected 2026-10-07 themes add pink pastel, cottage garden and lavender
  storefront link cards alongside the four original presets. Offer optional
  background/entrance/featured motion and heart/flower/sparkle decorations in
  a collapsed group, with reduced-motion support.
  Preserve colors/fonts, owned images, 100 normalized logos, safe contacts,
  local drafts, explicit publication, rights and the 20-link limit. Cards use
  existing links; product prices, free-position dragging and animated uploads
  remain outside this scope. API theme/effects support must precede Mobile;
  no provider, dependency, flag or migration is added. Local/remote validation
  and the completed 2026-10-07 Staging release are recorded in
  `docs/superpowers/plans/2026-10-07-profile-themes-motion.md`.
- Provide five customization categories with twenty layout/style templates
  each: minimal, cute/pastel, nature/warm, luxury/premium, creative/colorful.
  Keep the seven legacy choices, private draft content/images, per-link
  overrides and explicit publishing. Use category → preview → apply; remove
  visitor and preview pause buttons while retaining owner effects toggles and
  OS reduced motion. Shared catalog and nullable `templateId` are additive,
  with no migration or paid service; deliver API before Mobile. Staging delivery
  completed on 2026-10-07 at runtime commit `fc087c4`, after exact-commit CI
  passed 1,469 API and 1,422 Flutter tests. See
  `docs/superpowers/plans/2026-10-07-profile-template-categories.md`.
- Current composition revision, accepted on 2026-10-07: keep all fifteen
  A1–E3 sample directions and expand to twenty distinct short-page compositions
  in each of the five categories. Replace the earlier five-header/four-button
  model; retain all hundred template IDs, appearance version 1, seven legacy
  themes, content/images, custom colors/fonts, safe contacts and explicit
  publishing. Reuse the actual native composition renderer for chooser
  thumbnails and owner-draft previews; public HTML resolves the same catalog.
  Bundle eight ImageGen raster decorations locally in API/Mobile and expose
  only a read-only PNG filename allowlist at `/profile-decorations/:file`,
  with one-day caching and nosniff. No runtime Pinterest calls, multi-section
  store website, database migration, credentials, provider or dependencies.
  The hundred brand marks remain untouched. Local implementation/QA is complete:
  1,555 API tests, 1,499 Flutter tests, analysis, builds/schema checks, hundred-page
  320px browser matrix and twenty native structures pass. The exact Staging debug
  APK above describes local acceptance before integration. Initial integrated `9c7fa74`
  preserves the latest grouped Account UI and four-step composer; exact-source
  CI `37623591224` passes 1,555 API / 1,556 Flutter tests. Staging API deployment
  `dep-db342ek9v7es73astung` became Live with successful read-only runtime fixtures.
  The matching Android APK was built by passing opt-in Actions run `37627939566`
  from exact `9c7fa74`, locally re-signed and installed on emulator-5556. Its
  installed bytes match; account/draft/Flutter preferences are unchanged after
  native QA of all fifteen base previews, Account and the four-step composer.
  A follow-up corrects cropped uploaded logos with centered `contain` in every
  new composition, retaining frames and cover/background cropping; its own
  corrected source `ae65b9d5eacddf6f9cf000bdb4efb44b4e82b3e0` passes CI
  `37633935019` (104 API files / 1,556 tests, Flutter analyze / 1,559 tests and
  APK build). It is Live on `dep-db35c71srm7s73e5sf1g` with compiled fixtures
  confirming 100 contain-fit logos, retained IDs, cover cropping and eight PNGs.
  The matching verified/re-signed APK is installed in place on emulator-5556;
  stored account/draft/preferences match immediately after installation. The
  `9c7fa74` APK receipt is historical. CI avoids the Windows Flutter-tool startup
  hang; public browser/owned-image, iOS and physical-device checks remain unverified.
  The prior `fc087c4` receipt verifies the initial release only. See the current
  delivery receipt in the same plan for evidence and visual adaptations.
- Separate local draft saving from publishing. Show a shareable URL only after
  the API confirms publication. Support updating and unpublishing; changing a
  published slug invalidates the old URL.
- Open the internal link manager for every profile state: shop identity,
  separate Store information/Appearance/Preview actions, Add link above the
  editable list, visibility switches and drag ordering. Keep move up/down,
  featured-promotion and delete actions, with separate information, theme and
  review views. Expose Save draft in the footer and publish explicitly from
  review; confirmed publication returns to the manager. Preserve the 20-link
  total draft limit, all customization and the existing API/media boundaries.
  The public page is unchanged. All 1,132 Flutter tests, analysis and the Staging
  debug build pass, with native Android emulator flow/visual checks complete.
  Evidence and remaining limits are in
  `docs/superpowers/plans/2026-10-06-link-manager-ui.md`.
- Use original full-color YouTube, Shopee, Lazada, LINE, TikTok, Instagram,
  Facebook, Messenger, WhatsApp and Google Maps marks in mobile link cards,
  previews and public pages. Share identical
  bundled PNGs in transparent 40 x 40 slots. Use explicit source bounds for all
  ten to center visible artwork and fit its longest side to 40 with aspect
  ratio preserved; provide vector website/email/telephone icons and retain
  manual generic-link and brand overrides. Public `/profile-platforms/:file`
  serves only the ten known files from the page origin. The earlier background
  correction replaces YouTube's opaque canvas with its official transparent PNG,
  removes added white fills and versions its public URL with `?v=2`; the other
  six files retain their original artwork. The size-normalization follow-up
  changes only display geometry, retaining all seven PNG bytes and public URLs;
  no colored/white artwork is cropped. This follow-up adds no
  migration, provider call or package rule; existing published pages use the
  marks after API/assets deployment. Verification and delivery status are in
  `docs/superpowers/plans/2026-10-06-profile-platform-logos.md`.
- Recognize the three added contact brands from trusted URL domains/paths;
  suggest names for empty Messenger, WhatsApp, Google Maps, email and telephone
  links while preserving custom titles and the hostname fallback. Accept a
  single ASCII `mailto:` address without query/fragment/percent encoding or
  multiple recipients, and `tel:` with optional `+` followed by 7–15 digits.
  Let the mobile field accept a plain email or phone number and normalize the
  contact scheme before saving/publishing; the API accepts explicit schemes.
  Keep credential-free HTTP(S) and reject other schemes/malformed contacts.
  Deploy API/assets before Mobile because older APIs reject new icon values
  and contact schemes. These are outbound links, with no new paid API,
  integration, dependency, schema or migration; existing seven asset files,
  draft/publication behavior, 20-link limit and package rights remain unchanged.
  Verification and release details are appended to the platform-logo plan.
- Expand the profile-link catalogue to 100 brand logos: retain all ten existing
  asset bytes and add 90 curated regional/global destinations. This is a
  selection, not a world popularity ranking. Use one shared catalogue to
  generate API/Mobile names, recognition rules and artwork metadata, with a
  generator check for 100 IDs, hashes, matching PNG copies and source bounds.
  Replace a long logo dropdown with one searchable picker for names, aliases
  and countries, keeping automatic names only for titles the user left empty.
  Keep manual overrides, safe contacts, original colors/proportions, 40 x 40
  visible-bound slots, local/public page parity and the existing 20-link limit.
  The public route allowlists 100 PNGs; the icon contract has 100 brand IDs plus
  `auto|link|website|email|phone`. API/assets must ship before Mobile because
  older APIs reject the new IDs. Add no paid service, API integration,
  dependency, environment flag, schema, migration or package-rule change.
  Verification/release status is recorded in
  `docs/superpowers/plans/2026-10-07-global-profile-platform-logos.md`;
  dated totals for earlier releases do not cover this expansion.
- Remove editing-minute benefits, quota cards, and top-up promotion from the
  active product. Legacy editing code/API contracts remain for compatibility and
  shared media helpers; historical editing milestones below are not active TODOs.
  Since 2026-10-24 (security Batch 3) the API answers every `/ai-edits/*`
  request with `410 AI_EDITING_RETIRED` unless the `AI_EDITING_ENABLED=true`
  rollback switch is set, so direct callers can no longer spend editing
  provider work. See
  `docs/superpowers/plans/2026-10-24-ai-editing-retirement-security-batch3.md`.
- Staging now includes customization migration
  `20261005193000_customize_link_in_bio_profile`, the generated client/API and
  bundled fonts at `9195211f16519fd58c9cc01d6949dd8486190d01`. Real gallery logo
  upload and authenticated image reload after an app restart passed. Public
  appearance/image access and unpublishing remain unverified for customization.
  The user deferred live browser and R2 lifecycle checks because saved browser
  permissions block the Staging and Cloudflare domains. The
  direct read returned `403 AccessDenied`. This is Staging evidence, not
  Production acceptance.
  No new social statistics API, custom domain, click tracking, or scheduled-link
  auto-update is required by this first profile-page version.

- Shop-logo positioning (2026-10-13): choose the visible part of a gallery image
  with drag, zoom and reset in the circular preview, then explicitly confirm.
  Cancel preserves existing media and draft settings; changing account closes
  the owned crop dialog. Uses the existing image upload and publication flow.
  Verification and main delivery:
  `docs/superpowers/plans/2026-10-13-shop-logo-position-main.md`.

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
- Post/caption consumable add-on: target 49 THB once for 100 post units and 50
  caption credits, Starter/Pro only, with non-expiring purchased balances
  and included monthly quota consumed first. This is separate from retired editing-minute top-ups. The
  server gate starts disabled; migration, store/RevenueCat configuration and
  native purchase/refund acceptance are required before selling it. Delivery
  checks are tracked in `docs/superpowers/plans/2026-10-21-nonexpiring-post-caption-credits.md`.
  Android and iPhone share the same policy. A Basic downgrade retains the
  balance until membership is active again. Native purchase/refund acceptance
  on both stores remains pending; no live store availability is implied.
- Sentry for opt-in error reporting; the current candidate excludes performance
  monitoring and automatic native crash collection pending separate privacy and
  device acceptance work.
- Universal uploader for one 9:16 video.
- Scheduling through Upstash Redis and BullMQ.
- Unified social posting via PostPeer API (postpeer.dev) for TikTok, YouTube
  Shorts, Instagram Reels, and Facebook Page Reels. `FACEBOOK_REELS` always sends
  `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`, with no
  Page feed fallback. Real-account E2E remains pending. Direct platform API
  integrations are deferred until post-launch.
- Unified analytics summary for Pro users, with backend-backed date ranges and
  a publish-date daily series.

Current status:

- Mobile UI refresh has a first-pass shared dark theme, glass cards, Thai
  bottom navigation labels, auth bar copy, and Home dashboard direction.
  Upload, Calendar, AI Editing, Analytics, Profile, and package/paywall surfaces
  have the approved design structure; final device-specific visual polish
  remains.
- Gemini backend smoke test passed.
- Legacy signed upload and managed R2 multipart both passed disposable-account
  production API smoke tests. The managed test covered session creation,
  just-in-time part upload, completion/status, Firebase deletion readiness,
  account cleanup, deleted-account retry semantics, and zero leftover smoke
  sessions/objects in PostgreSQL and R2. Full mobile-to-worker real-video and
  slow-network tests still remain.
- Backend RevenueCat webhook and authenticated subscriber resync paths are
  hardened in the Batch 1 source change with explicit subscription environment/
  store validation, production Test Store rejection and TRANSFER reconciliation
  through existing owner/cursor guards. RevenueCat promotional grants do not
  unlock paid access; trial access uses the existing audited
  admin-console trial flow. Promotional-only resync cancellation has explicit
  regression coverage. This work does not establish live production billing
  acceptance or deploy changes; owner configuration and staged validation remain
  required. See
  `docs/superpowers/plans/2026-10-23-billing-security-batch1.md`.
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
- The isolated Staging Blueprint/database were originally created on Free;
  the recorded 2026-08-14 expiry belongs to that historical setup. The
  2026-10-20 read-only check found the Starter API healthy and the Basic 256 MB/
  1 GB PostgreSQL 18 database available; its latest live deploy is dated
  2026-10-18. The local Blueprint is being reconciled without a sync/deploy.
  Earlier records report a dedicated Firebase Staging project, isolated Android
  Debug app id, Google provider, restricted Android API key, and Firebase-token-to-API
  login smoke test now pass on the Android Emulator. RevenueCat Test Store
  products, entitlements, current offering, and authenticated sandbox webhook
  transport are configured. Test Store purchase and true Restore/resync E2E pass
  with a Firebase UID after the current backend and Render key were configured.
  RevenueCat Play configuration and a signed AAB are ready, while Play Console
  setup and a real Google Play purchase remain blocked by the required physical
  Android account verification. R2 upload from Android now passes, while
  production-bucket isolation and cleanup still need confirmation. Lifecycle,
  Gemini/ElevenLabs, Phone Auth, and the remaining controlled social publishing
  paths still need current-candidate smoke tests after their environment-specific
  credentials are reconfirmed in the Dashboard. One Staging YouTube Shorts
  Private immediate publish now passes. Render Staging and its Blueprint track
  `main`.
- Legacy AI Clip Review UI, `/clip-reviews` route, config, and internal
  mock/provider code have been removed from the active app path. Subscription
  compatibility flags remain false for older clients.
- Global readiness is now part of the plan. The app remains Thai-first for the
  first launch, but future screens and backend flows should avoid Thailand-only
  assumptions where the cost is low.
- Firebase Auth, Render deployments, Upstash, RevenueCat webhooks, uploads,
  analytics, real-clip caption provider hardening, production verification of
  the Prisma AI caption usage ledger, and broader PostPeer social posting still
  need provider-level testing before production use. PostPeer profiles now satisfy
  the required name contract without exposing the Firebase UID/email and ensure
  the local User first; accepted async posts are polled for roughly two minutes,
  never receive a fabricated external id, and expose persisted per-platform
  results through `GET /posts`. One Staging YouTube Shorts Private immediate
  connected-account E2E passed; broader platform and Production E2E is pending.
- Social-post safety now has an authenticated configuration preflight. Mobile
  checks it before watermark/upload; `POST /posts`, `PATCH /posts/:id`, and
  `POST /posts/:id/publish-now` authoritatively return
  `503 SOCIAL_PUBLISHING_UNAVAILABLE` while the publisher is disabled, and
  cancel remains available. This prevents new false queued failures in the
  current client but does not enable or verify PostPeer. Old clients or a config
  race can still leave a temporary uploaded object.
- Local publish-draft implementation is present in the current working tree:
  video/cover/manifest copies live in Application Support under a stable
  authenticated UID, with no server `DRAFT` post or publish-side
  API/R2/provider/queue/quota
  effect when saving. Drafts do not sync across devices and OS backup may include
  them. Destination selection now starts empty, review states each platform's
  outcome, schedules must be future and within 14 days for Starter or 30 days
  for Pro, and queued schedules have
  a dedicated publish-now command. The result UI distinguishes queued,
  publishing, published, and partial outcomes and retains a draft for an unknown
  status. Focused automated coverage exists; the final combined suites,
  real-device verification, and provider E2E remain open until recorded against
  the release candidate.
- Phase 2 per-platform configuration is implemented in the working tree without
  filling the main Upload page with every field: selecting a destination reveals
  one summary/settings action and opens that platform's sheet. New intent is
  TikTok inbox draft; complete YouTube title/visibility/kids/synthetic-media/
  certification; Instagram share-to-feed; and an explicit Facebook Page Reels
  publish/page-draft choice. The new TikTok Direct flow adds creator-info,
  consent and revision checks and is delivered to Staging API/Android; provider
  audit/public publication, iOS and other-environment rollout still need
  verification. Review names the connected account/channel/page and blocks
  missing identity, incomplete settings, or an unknown outcome. Provider drafts
  are remote submissions that upload, enqueue, and consume quota—not PostDee
  local drafts.
- The API advertises `platformSettingsVersion: 1`, persists settings plus an
  internal immutable connected-account snapshot, revalidates it before commit
  and provider call, and redacts provider account/post ids from public responses.
  `deliveryOutcome` distinguishes live/private/unlisted/provider-draft delivery.
  The nullable Prisma migration preserves legacy rows, but legacy-null queued
  work has no target snapshot and must be inspected/drained before activation.
- Each local publish draft now persists a stable submit request ID. The API
  commits one deterministic owner-scoped post before enqueue: first success is
  `201`, a matching replay is `200 idempotentReplay: true` and repairs a missing
  queue job, while mismatched intent or a terminal failed replay returns `409`.
  Legacy clients may omit the key but get no deduplication guarantee. This
  protects post/quota state. New drafts persist completed R2 video/cover receipts
  with their source-media fingerprint before submit and reuse matching receipts.
  Interrupted uploads and old uncertain drafts without receipts still require
  recovery/orphan handling before explicitly starting another post.
- Mobile outage recovery bounds ordinary JSON requests to 20 seconds, AI
  transcription/prepare/plan/caption POSTs to 120 seconds, and legacy or
  per-part upload PUTs to 180 seconds. Client-local `API_REQUEST_TIMEOUT`/`408`
  cancels the pending request/body but does not prove server cancellation;
  explicit publish retry retains the original draft/request ID. Completed
  store purchases await backend confirmation and can retry confirmation
  without buying again; initial current-plan failures disable new purchases
  while retry/Restore remain available. Pending confirmation survives paywall
  reopening in a stable-UID memory cache, cleared on sign-out/account change;
  app restart recovery uses Restore. Failed connection-status reads remain
  unknown and block connection actions. Package rules, server/schema contracts,
  and existing provider/device acceptance gates are unchanged.
- Route/post lock maps remain process-local. The shared-drain implementation
  delivered to Staging
  adds PostgreSQL lifetime tickets and a cleanup claim across upgraded API/
  worker processes; crashes and unknown outcomes remain blocked without TTL.
  Account deletion and multi-instance/separate-worker activation still require
  the migration/all-process rollout and actual Redis/provider/Firebase, legacy
  upload/OAuth and device cleanup acceptance. Synthetic separate-process tests
  alone do not authorize activation.
- On 2026-08-10, the disabled Pixel 8 fail-fast check and an initial controlled
  action that stopped before upload were recorded on the earlier candidate.
  Follow-up Staging SHA `208b4e580ddd2291a7a32e718c2519d785730895`
  then logged `postpeer` mode plus an empty-backlog guard-pass before one
  separately authorized YouTube Shorts Private action reached terminal
  `PUBLISHED` with a real non-mock external reference. Fresh quota changed
  exactly once from `249/250` to `248/250`. The destination reported Private,
  and the current user had no new `QUEUED`/`PUBLISHING` post. Staging was
  restored to `disabled`; the first restoration deploy was ineffective and is
  recorded rather than hidden. See
  `docs/testing/results/2026-08-10-social-publishing-pixel8.md`.
- The deployed follow-up marks both readiness `200` and `503` responses
  `Cache-Control: private, no-store`, supplies one parsed config object to the
  app and scheduler diagnostics, and logs only the non-secret runtime mode,
  publisher, guard enforcement, and a post-start guard pass. The controlled
  retry verified those enabled/guard logs and the final disabled startup log;
  it does not identify caching as the cause of the earlier blocked action.
- The Production Blueprint currently selects `SOCIAL_PUBLISHER=postpeer` even
  though broader connected-account E2E and Production verification are pending.
  Treat this as a launch configuration risk; the repository cannot prove the
  live Render value, and the safety-gate
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
| Social posting | PostPeer API | Publish to TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels through one provider | Per-user connect uses a native Android Custom Tab bridge with external-only fallback, trusted OAuth-host validation, fixed Android return targets and one authenticated return/resume/manual refresh, and provider-first disconnect; iOS currently uses the external system browser; fresh users are ensured before a pseudonymous named profile is saved; `202` results poll for about two minutes without fake ids; `GET /posts` returns per-platform results; the config-only readiness gate and fail-fast create/reschedule path exist; Staging has an opt-in startup guard whose single atomic aggregate status-in query refuses PostPeer activation when any global `QUEUED` (including future) or `PUBLISHING` row exists, or when inspection fails; YouTube defaults private and TikTok SELF_ONLY for controlled testing; the disabled Mobile fail-fast passed, but the first controlled YouTube attempt stopped at readiness before upload and the runtime mode/guard pass were not observable, so connected-account E2E is still pending | Readiness does not probe PostPeer/accounts. Injected-URI warm return passed on the Staging APK; verify real provider/browser handoff, Open App confirmation, cold-start authentication, the iOS external-browser flow and manual fallback on physical devices. The fixed-target API is Live on Staging; other environments need API before mobile. Generate new links to use the return target. Keep Staging disabled except for a controlled run; require explicit runtime-mode and empty-backlog guard-pass evidence before another single private attempt. `FACEBOOK_REELS` always requests Page Reels via `contentType: 'reel'`, retaining publish/Page-draft choices with no Page feed fallback; real-account E2E remains pending. Retry only an explicitly safe pre-accept error; unknown outcomes require checking the destination first. |
| Error tracking | Sentry | Capture allowlisted backend, publisher/worker and Dart/Flutter errors | Clean Staging a0540a3 serves the CI-tested 12e0589 API tree; isolated ingestion and actual drained-main-process fatal/restart are verified, temporary hook removed | Native Crashlytics/APK12041 remain accepted. Crash during active publishing, forced HTTP-500 middleware and native/iOS runtime remain separate; tracing/logs/Replay stay off. |
| Push notifications | Firebase Cloud Messaging | Notify users about scheduled publish results and failures | Mobile registration, `POST /devices`, notifier, and firebase-admin sender exist; mock remains default | Add the service account, set `PUSH_SENDER=firebase`, enable APNs/iOS capabilities, and test on a real device. |

Render runtime hardening keeps `firebase-admin` Auth/FCM support but removes its
unused optional Firestore and Google Cloud Storage clients after the build and
Prisma migration. CI still installs platform-native optional build tools, while
the production dependency audit excludes optional modules that are not shipped
in the running service.

On 2026-10-04, the lockfile's compatible `@fastify/busboy` dependency was patched
from `3.2.0` to `3.2.1` to resolve the high severity CI audit blocker. The Render
Dashboard still reports the workspace suspended for non-payment, and Staging
returns HTTP `503` with `x-render-routing: suspend`; live deployment and current
provider tests remain blocked until the workspace is restored.

On 2026-10-06, pre-merge CI identified `GHSA-jqcg-44mw-7w3h` in `proxy-addr`.
The compatible lockfile patch to `2.0.8` and two security/rate-limit regressions
pass the backend suite. The high/critical production audit gate stays enabled;
four moderate dependency findings remain for separate follow-up. No API/schema
or trust-proxy configuration changes are part of this patch.

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
9. Verify the opt-in Sentry candidate with synthetic local API and native Mobile
   events, review the outbound allowlist, then activate each authorized cloud
   environment. Native crashes/ANRs and performance tracing remain separate work.
10. While Staging is still disabled, install only its PostPeer key, connect and
    refresh disposable per-user accounts, and cancel old queued/scheduled work.
    Enable PostPeer only for a controlled real publish E2E. Confirm readiness,
    YouTube `private`, TikTok `SELF_ONLY`, Instagram Reels, Facebook Page Reels,
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
- Bottom navigation has five entry points: Home, Calendar, Create post,
  Store link, and Account. Store link opens the internal link manager and Account
  opens the existing profile/settings screen. The full-width opaque dock extends
  through the bottom safe area, with rounded top corners, outline icons, a raised
  solid green upload action, and green selected icons/text/dots. The center
  action hides its visible label while retaining the tooltip and accessible name.
  The separate 2026-10-06 link-manager revision uses the selected Pinterest
  mobile Links-manager reference while retaining this dock and its clearance.
  The wider app redesign remains separate. Analytics remains reachable
  from publish results and individual post details so the existing reporting
  system is not removed.
- Account uses four labeled groups: My account, Channels/tools, My package, and
  Settings/help. The current plan occupies one compact card; the existing
  paywall retains package comparison. Language/theme choices open on demand,
  with logout and confirmed account deletion kept separate at the bottom.
  Channels/tools contains the connection row; caption-template and profile-link
  shortcuts are removed from Account.
  See `docs/superpowers/plans/2026-10-07-grouped-account-ui.md`.
- Home keeps one direct Link in Bio shortcut followed by the latest posts.
  Monthly views/likes cards are temporarily removed from Home along with their
  analytics request; analytics stays available from post details and publish
  results. Create post stays in the bottom navigation, while the future
  viral-alert preview stays off Home until its real end-to-end flow is ready.
- Keep AI captioning available from Upload after a clip is selected.
- Create post opens above the shell as a full-screen four-step flow; the dock
  stays on shell tabs and is hidden while composing. The final step contains
  scheduling and the shared review summary rather than another review page.
  AI starts only from the user's button, and local draft saving remains explicit.
- Keep saved caption-template selection in Create post. Manage profile links
  through the Store link tab.
- Legacy AI editing settings are no longer exposed from the active navigation.

Planned order:

1. Lock shared UI primitives: theme tokens, glass card, gradient button style,
   platform status chips, Thai navigation labels, and reusable mini chart/bar
   widgets.
2. Finish Home dashboard: greeting, plan card, latest-post status rows, quick
   actions, and platform performance summary.
3. Redesign Upload: full-screen clip → caption → destinations → review/send
   steps, small local poster and full-screen player, manual AI, explicit draft
   save/changed-form exit, and a functional cover editor (video
   frame, Thai text, font/style/position, rendered 1080x1920 image, secure
   upload, preview, and platform-aware delivery), platform toggles,
   schedule/date/time controls capped at 14 days for Starter and 30 days for Pro,
   draft state, and a
   single clear final Post CTA. The four-step implementation now exists;
   final regression/build/native QA and real connected-account publishing
   verification remain separate release gates.
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
- **อนาคต**: a proposed direction that has not started. The reconciled capacity
  roadmap and remaining Phase 2/Global Readiness work do not activate providers
  or infrastructure by themselves.
- **ประวัติ**: completed implementation record; unchecked execution boxes do
  not mean that the capability is absent.
- **ถูกแทนที่**: an older approach that must not override the current runtime.

| Plan file | Status | Notes |
| --- | --- | --- |
| `docs/superpowers/plans/2026-10-14-shared-owner-operation-drain.md` | ทำบางส่วน | Source `7576ee3` is on main/Staging with migration 18; feature/main CI pass 1,909 API/2,189 Mobile, local two-process 10/10 and post-Live account/R2/native checks pass. Flags/account creation unchanged. Real Redis/provider/Firebase and legacy upload/OAuth acceptance remain. |
| `docs/superpowers/plans/2026-10-14-staging-regression-and-typecheck.md` | ทำบางส่วน | Typing commit `1b5a403` is included in main/Staging `7576ee3`; hosted CI and native draft/clip plus R2 part/recovery/abort pass. Upload completion, real Redis/provider drain and disposable-account deletion remain separate gates. No flag activation or new APK. |
| `docs/superpowers/plans/2026-07-17-scaling-roadmap.md` | อนาคต | Reconciled on 2026-10-08 against the active product and single-process owner boundary; capacity tiers require measured evidence and no scaling infrastructure is enabled. |
| `docs/superpowers/plans/2026-10-05-backend-hardening.md` | ประวัติ | Original isolated-branch verification is historical; the 2026-10-08 integration ports runtime hardening without its old dependency refresh. |
| `docs/superpowers/plans/2026-10-08-integrate-pending-main-work.md` | ประวัติ | Source/CI/native delivery is complete at `36dbacc`; the same runtime is Live on Staging at `9baa18c`/`dep-db3m2g59fdbs73ecbib0`. Readiness/auth/empty-owner contracts and separate R2 fixture delivery/cleanup pass. Nonempty native Home, two-owner isolation and provider/crash/scale/Production gates remain. |
| `docs/superpowers/plans/2026-06-04-store-subscription-billing.md` | ถูกแทนที่ | The direct Apple/Google verification scaffold is retained for history and compatibility; RevenueCat is the production subscription direction. |
| `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md` | ถูกแทนที่ | The ultra-dark checklist is historical. The current app is light by default with optional dark theme; retain only behavior and navigation improvements that still match the current UI. |
| `docs/superpowers/plans/2026-06-13-ai-auto-editing-whisper-plan.md` | ถูกแทนที่ | Groq is retired. ElevenLabs/Gemini/FFmpeg editing modules are retained compatibility code; AI editing and Subtitle Studio have no active product entry. |
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
| Basic | Free | Try posting and publish a profile page | Phone verification required for 3 real-time test posts per month; one profile page with up to 20 links |
| Starter | 199 THB/month | Practical daily posting plus AI caption from the real clip audio | 120 post units/month, scheduling up to 14 days ahead, calendar, templates, auto watermark, EP clip splitting UI, one profile page with up to 20 links, and 50 real-clip AI caption credits/month |
| Pro | 299 THB/month | Growth tools, analytics, team workflows, and stronger AI from audio plus selected visual frames | 250 post units/month, scheduling up to 30 days ahead, calendar, templates, auto watermark, EP clip splitting, full analytics, hashtag radar, AI comment center, viral alert, one profile page with up to 20 links, Team & Editor Access, and 120 real-clip AI caption credits/month |

Package rules:

- The active Paywall must show only end-to-end ready benefits. EP splitting,
  hashtag radar, viral alerts, and team/editor access remain planned and must
  not be presented as included until their real flows are verified.
- Basic must verify a phone number before using the 3-post free test quota.
- Post units count by platform: posting one video to four platforms uses four
  units.
- Starter can schedule up to 14 days ahead; Pro can schedule up to 30 days.
  Previously accepted schedules retain their time after this policy change or
  a downgrade. New schedules and reschedules use the current plan's limit;
  these limits do not define R2 file retention. Analytics, hashtag radar,
  AI comment center, viral alert, and team access stay Pro-only.
- Starter AI captioning listens to the selected clip audio and returns SEO
  wording, hashtags, caption options, and hook ideas.
- Pro AI captioning can use audio plus selected visual frames from the clip for
  stronger suggestions.
- AI caption credits count by generation target: one credit per selected
  channel, with shared-caption requests costing one. Repeating generation
  consumes the same selected cost; preview dismissal does not refund success.
- Upload AI captioning should auto-detect language and market from the selected
  clip. Sellers can override through optional guidance instead of extra fields.
- Do not sell prompt-only AI captioning as the main paid feature. Text guidance
  can exist only as an optional extra after the user selects a clip.
- Do not include a separate "AI audio clip review" feature in Starter or Pro
  package marketing for now.
- AI auto editing minutes and top-ups are retired from current package marketing.
- Secret AI keys must stay on the backend only. Team editors must never see the
  owner's social account passwords or tokens.

## Phase 2: Growth Features

Items 1-7 below are future growth features that should start after the core
posting and scheduling flow is usable with real provider APIs. Item 8 records
historical hardening for the retained AI editing implementation. The 2026-10-05
product decision above supersedes its active product/release priority.

Recommended order:

1. Link in Bio Generator
   - Publish merchant pages at the configured PostDee API domain `/p/store-name`.
   - Store affiliate links, product links, and campaign links.
   - Explicit publish/update/unpublish controls are included; scheduled-post
     auto-update and click/campaign insights remain future work.

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
3. **Account Deletion**: Partially implemented and temporarily disabled in
   Production. The Profile screen warns that store subscriptions must be managed
   separately; iOS/macOS Apple users pass readiness, reauthenticate, and revoke
   Apple access before `DELETE /account`. Initial Firebase deletion must persist
   recent-authentication authorization; stale/missing-identity retries require
   that same UID's stored proof, not only a lifecycle tombstone. Apply migration
   `20261014003000_authorize_account_deletion` and regenerate Prisma before the
   patched API; existing tombstones receive no authorization backfill.
   The cleanup saga sets a durable marker
   for the managed-upload owner prefix, reconciles/aborts multipart sessions,
   disconnects PostPeer integrations, removes queued jobs/R2 objects/database
   data, and deletes the Firebase identity last. The shared-drain implementation
   delivered to Staging
   records operation lifetimes and exclusive cleanup claims in PostgreSQL,
   including worker provider calls. Keep `FIREBASE_AUTH_DELETE_ENABLED=false`
   until its additive migration and all-process upgrade/drain cover the target
   environment,
   then pass real Redis/provider/Firebase, physical-device, slow-network, OAuth
   and R2 lifecycle/legacy-upload tests. Unresolved tickets never auto-expire.
   Apple Sign-In remains unavailable on Android/web until server-side token
   revocation exists there. Production also remains in `dual` upload rollout;
   retire signed-`PUT` clients before switching to strict `multipart` mode.
4. **Content & Safety**: Rely on Gemini's built-in safety filters to prevent abusive or explicit AI generation.
5. **Policies**: The in-app Privacy Policy and Terms are working drafts. Finalize
   and host reviewed HTTPS versions, including the local-draft/Application
   Support and OS-backup caveats, before store submission.

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
   `503` after restoring `disabled`. Verify `FACEBOOK_REELS` delivers Facebook
   Page Reels via `contentType: 'reel'` with no Page feed fallback, verify
   uncertain outcomes before retrying, and defer individual social
   API app reviews.
7. Finish the remaining live customization checks for published appearance,
   public images, browser copy/open and unpublishing on the deployed Staging
   version. Verify R2 lifecycle settings and confirm pages disappear on account
   deletion before claiming full release acceptance.
8. Retain legacy editing safety tests and shared media helpers without exposing
   editing, subtitles, music, or editing-minute top-ups as active product features.
