# PostDee Subscription Packages Plan

> Status: planning source of truth for package positioning. Do not treat this as fully implemented behavior until the matching backend and mobile gates are updated.

> Product update (2026-10-05): a hosted profile link replaces AI video editing.
> Every package gets one page with up to 20 custom links. AI caption quotas and
> existing prices stay the same; editing-minute quotas and top-ups are retired
> from the active mobile offer. Public deployment/migration is a release gate.

> Reliability update (2026-10-09, Staging API): quota limits and package rules
> stay unchanged. Failed caption providers refund only their exact reservation;
> fallback responses identify `isFallback` and `quota.charged`. A failed usage
> recount keeps the last known conservative count with `usageRefreshPending`.
> Mobile prices come from the store and pending purchases are rechecked without
> starting a second purchase. Verification and release order are recorded in
> `2026-10-09-system-audit-fixes.md`; API `85ef2a9` is Live on Staging with both
> additive migrations applied. Native payment/provider acceptance remains open.

> AI entitlement update (2026-10-09, implemented; automated checks pass): after
> a successful subscription GET denies AI access with RevenueCat enabled, Mobile calls
> the existing authenticated server resync once per Generate action, then use
> a fresh GET rather than the resync reply's plan. Paid users, disabled
> RevenueCat and a failed initial GET skip it. Failure keeps the paid gate
> closed with a Thai verification error and manual retry. No purchase, SDK
> Restore, free grant, price, tier, quota or API/schema change is introduced.
> Owner/source guards and existing Starter mode / Pro frames stay unchanged.
> Exact-source APK build and native paid end-to-end checks remain pending;
> automated results and delivery limits are recorded in the audit plan.

> Scheduling update (2026-10-08): Starter allows up to 14 days ahead, and Pro
> allows up to 30 days ahead. New schedules and reschedules use the current
> plan and current request time. Previously accepted queue entries keep their
> original time after the policy change or a downgrade. No data migration or
> R2 lifecycle/retention change is required by this package rule.

The scheduling release uses the existing subscription `plan` and `canSchedule`
contract; it does not add a billing field, change prices/quotas, or migrate queued
rows. Deploy the API enforcement before distributing the matching mobile build.
An older mobile build may still offer Starter dates beyond 14 days, but the API
rejects a new request beyond the current entitlement. Existing accepted entries
continue through the original worker flow after a downgrade; Basic users can
view or cancel them but need a paid plan to submit a new schedule or reschedule.

## Package Goals

Keep the packages easy for Thai sellers to understand:

- **Starter 199 THB/month**: practical daily posting and lightweight AI help.
- **Pro 299 THB/month**: growth, analytics, advanced AI, and serious shop/team workflows.

Avoid duplicate feature names that confuse users. In particular, **AI audio clip review is paused and should not be sold as a separate Starter or Pro package feature for now**.

## Starter 199 THB/month

Starter should feel useful enough for a small shop to pay without needing analytics yet.

- 120 post units per month.
- Post unit counting: 1 platform = 1 unit.
  - Example: one video posted to TikTok, YouTube Shorts, Instagram Reels, and Facebook Reels uses 4 units.
  - After that example, Starter would have 116 units left.
- Schedule posts up to 14 days ahead.
- Calendar view for scheduled posts.
- Caption templates.
- AI caption from real clip, audio-only: 50 generations per month.
  - The user uploads/selects a video first.
  - AI listens to the clip audio and uses the real spoken content.
  - AI should infer language and market from the selected clip automatically.
  - Optional guidance is the override path for a seller who wants a specific
    language, market, or style.
  - Output must include SEO wording, hashtag suggestions, caption options, and hook ideas.
  - Pressing generate/change again counts as another generation.
  - Do not sell a separate prompt-only caption generator as the main package feature.
- Auto watermark.
- EP clip splitting UI and future simple EP workflow.
- One hosted profile page with up to 20 custom links (also available on Basic).
- No Pro analytics dashboard.
- No hashtag radar.
- No AI comment center.
- No viral alert.
- No AI video review.
- No team and editor access.
- No separate AI audio clip review feature.

## Pro 299 THB/month

Pro should be the plan for serious sellers, creators, and shops that want to grow.

- 250 post units per month.
- Post unit counting remains 1 platform = 1 unit for reporting consistency.
- Schedule posts up to 30 days ahead.
- Calendar view for scheduled posts.
- Caption templates.
- AI caption from real clip, audio + visual frames: 120 generations per month.
  - AI listens to the clip audio.
  - AI can also inspect selected video frames/images from the clip.
  - AI should infer language and market from the selected clip automatically.
  - Optional guidance is the override path for a seller who wants a specific
    language, market, or style.
  - Output must include SEO wording, hashtag suggestions, caption options, and hook ideas.
  - Pressing generate/change again counts as another generation.
  - Do not sell a separate prompt-only caption generator as the main package feature.
- Auto watermark.
- EP clip splitting.
- Full analytics dashboard.
- Hashtag radar.
- AI comment center: sentiment summary and reply drafts.
- Viral alert notification.
- Future video insight can be considered later only if it does not reintroduce
  the removed standalone AI Clip Review product.
- One hosted profile page with up to 20 custom links. Click or campaign
  insights remain future work and are not sold as an active benefit.
- Team and editor access.
  - The shop owner can invite an admin/editor to help prepare uploads, captions, and scheduled posts.
  - Editors must not see the owner's TikTok, YouTube, Instagram, or Facebook passwords/tokens.
  - Recommended first version: simple owner/editor roles, invite by email, revoke access, and basic activity log.
  - If future agency workflows need many brands, approval chains, or client billing, create a separate Agency plan later.
- No separate AI audio clip review feature.

## Top-up

- AI editing-minute top-ups are no longer offered in the current mobile product.

## Paused / Removed From Package Marketing

### AI audio clip review

Do not include "AI audio clip review" in Starter or Pro package lists for now.

Reason:

- It overlaps with AI caption from real clip and the ElevenLabs/Gemini auto
  editing flow.
- Users are more likely to understand "AI caption from your clip" than a separate "audio review" feature.
- Future direction: merge useful audio-review ideas into AI caption from a real clip transcript.

The active Clip Review UI, `/clip-reviews` backend route, backend config, and
internal mock/provider code have now been removed from the app path. Useful
ideas such as hooks, SEO wording, and hashtag suggestions should be rebuilt
inside real-clip captioning instead of kept as a separate review feature.

## Current implementation status

### Plan-specific scheduling verification (2026-10-08)

- Baseline: fresh `origin/main` and HEAD `2e5801a18358df716dec5f86f4b805b6f00aa02e`
  on `codex/integrate-pending-main-work`. Initial local verification includes
  preserved uncommitted app-first OAuth work. The scheduling release excludes
  that separate patch; its clean-source checks and deployment are recorded below.
- Backend files: `subscriptionEntitlements.ts`, `postRoutes.ts`, and
  `postRoutes.test.ts`. Mobile files: shared `post_schedule_policy.dart`,
  Uploader, Calendar, Paywall, Profile FAQ, and Legal Document screens, plus
  policy/uploader/calendar/paywall/legal/app widget tests. The app layout test
  uses the existing shell subscription injection for a known Pro fixture.
- Targeted backend tests: 76 pass; full API suite: 1,621 pass. API build,
  Prisma schema validation, and seed/config TypeScript checks pass. Deferred
  plan changes and lookup failures are checked before accepting a new schedule
  inside the owner mutation boundary; existing matching requests still replay.
- Compiled API local HTTP smoke passes Starter +14 days and Pro +30 days,
  rejects each boundary +1 ms, preserves an accepted +20-day queue after a
  downgrade, replays the same request on Basic, keeps the old time after a
  rejected move, and checks Basic cancellation plus foreign-owner isolation.
  All adapters used by this smoke are local mocks; no social platform is called.
- Mobile targeted tests: 104 pass; final full Flutter suite: 1,628 pass;
  analysis reports no issues. Coverage includes refreshed plan limits,
  unknown/Basic plan blocking, preserved old queue/draft dates, interrupted
  subscription lookup on disposal/account switch, and elapsed-time messages.
- The validated Staging helper builds the combined working tree successfully;
  this initial APK includes the separate app-first patch and is not the scoped
  scheduling release artifact.
  APK metadata: `com.postdee.postdee_mobile.staging`, `0.1.0-staging`, min SDK 24,
  target SDK 36. Signature verification and the Firebase Android OAuth debug
  certificate match pass. API base is the Staging URL; Firebase Auth is enabled
  and local mock auth is disabled. APK size is 303,517,278 bytes with SHA256
  `19DEA44B4779063B785277FE5FD98FF59A96E4D9DD5AC9D38DEB38003F6F1648`.
- No database migration, credentials, R2 retention policy, plan prices, or
  provider flags change. At this initial local check, the new APK is not
  installed over the user's app and the API is not deployed. The scoped release
  is recorded below. Real scheduled provider publishing and physical
  Android/iPhone verification remain release gates.
- Local logs: `artifacts/schedule-policy-full-flutter-test-final.log` and
  `artifacts/schedule-policy-staging-build.log`. Logs/artifacts remain untracked.
- A lost original POST response followed by a lower entitlement can still
  prevent the mobile draft from submitting its old time again. Keep the draft
  and check Calendar before creating a replacement; an already accepted server
  queue entry remains intact and server matching-request replay is preserved.

- Active purchase screens must list only benefits that work end to end in the
  current app. EP splitting, hashtag radar, viral alerts, and team/editor
  access remain roadmap items and must not appear as included benefits until
  their mobile, backend, and provider flows have been verified.

- The core package rules in this plan are implemented and covered by backend
  tests: Starter has 120 post units and 50 clip-caption generations, Pro has
  250 post units, 120 clip-caption generations, and 200 AI-editing minutes.
  Post usage counts selected platforms and Starter scheduling is enabled.
  Remaining production work:
  - AI caption from real clip now has a mock-safe endpoint and memory/Prisma
    quota ledger options, plus transcription-backed language/market context.
    Production still needs real R2/ElevenLabs/Gemini clip testing and the Prisma migration
    applied and verified against a real PostgreSQL database.
  - Team and editor access needs Pro entitlement checks, invite records, role permissions, revoke access, and an activity log.
  - Social account credentials/tokens must stay owner-scoped and never be exposed to invited editors.
  - Prompt-only AI caption entry points should be removed, hidden, or changed into optional extra guidance after a clip is selected.
  - AI audio review entitlement/marketing should stay removed or hidden.
- Mobile currently needs updates before this plan becomes real behavior:
  - Package copy should match this plan.
  - `PostDeeApiClient` can call the real-clip caption endpoint. Upload AI
    caption UI requires a selected clip first, keeps language/market automatic,
    and shows audio-only for Starter and audio+visual-frame mode for Pro.
  - Profile or settings should show Team and Editor Access as a Pro 299 feature.
  - Starter/paywall screens should make it clear that team access unlocks in Pro.
  - Any separate AI audio review UI should stay removed unless it is renamed into a future clip-based caption workflow.
  - Profile and paywall screens should show clear Starter vs Pro differences.

### Scoped scheduling delivery (2026-10-08)

- User authorized push/deploy. Source `8aa84443734d893d44fe404f1fe5ed58dce27492`
  is pushed to `origin/main` from baseline `2e5801a`. The release contains only
  scheduling policy, related screens/tests, and policy documentation. Separate
  uncommitted app-first OAuth files and their documentation remain preserved
  in the integration worktree; generated Windows files and artifacts are not
  committed. No files, routes, existing queue entries or dependencies are removed.
- Exact-source [CI](https://github.com/NOI56/PostDeeMobile/actions/runs/37791964615)
  succeeds: API 1,621 tests across 107 files, 22 template-generator tests,
  build/schema/production audit, plus Flutter analysis and 1,610 tests. The
  scheduling API blobs match the previously verified compiled local HTTP smoke.
  [Unsigned iOS build](https://github.com/NOI56/PostDeeMobile/actions/runs/37791964612)
  and artifact upload succeed at the same source. No signed iPhone build or
  physical-device acceptance is claimed.
- Clean-source local Flutter tests (1,610), analysis and validated Staging APK
  build pass in the `main` worktree. APK is `com.postdee.postdee_mobile.staging`,
  version `0.1.0-staging`, min SDK 24/target SDK 36, 289,699,911 bytes, SHA256
  `DF91BBB33DC6B0B93A76FED3702CD71B6BF1B8DE8EAB14087CAA19B5968D3EA8`.
  Signature verification passes with the existing Firebase-matching debug
  certificate. API base is `https://postdee-api-staging.onrender.com`; Firebase
  Auth is enabled, local mock auth is disabled and the existing validated
  RevenueCat Test Store overlay is used. The APK is not installed over the
  emulator in this release. Local evidence is in
  `apps/mobile/artifacts/schedule-main-{flutter-test,flutter-analyze,staging-build}.log`.
- Render [deploy dep-db3qgqmi0phs73b71tl0](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db3qgqmi0phs73b71tl0)
  is Live at the exact source above, instance `8cg7w`; build/start succeeds,
  fourteen existing migrations are present and none are pending. The read-only
  live Shell imports the compiled entitlement module and confirms
  `BASIC: 0, STARTER: 14, PRO: 30`, source SHA and API tree
  `5d2ed3724765bc3183a104b99ac930945fb3cfd5`.
- After deployment, `/health` and `/ready` return `200`; database/queue checks
  are `ok` and readiness is `no-store`. Anonymous `/posts` and
  `/publishing/readiness` return `401`. Publishing remains disabled and the
  memory queue remains on the existing single instance. No customer post,
  purchase, quota, credentials, R2 lifecycle, environment or Production write
  is performed. Actual scheduled social-provider acceptance remains unverified
  while Staging publishing is disabled.
- Deployment screenshot and redacted receipt stay local under
  `artifacts/schedule-release`. Any later documentation-only delivery commit
  does not change the deployed API tree and does not require another deployment.
