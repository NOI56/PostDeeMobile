# PostDee Subscription Packages Plan

> Status: planning source of truth for package positioning. Do not treat this as fully implemented behavior until the matching backend and mobile gates are updated.

## Package Goals

Keep the packages easy for Thai sellers to understand:

- **Starter 199 THB/month**: practical daily posting and lightweight AI help.
- **Pro 299 THB/month**: growth, analytics, advanced AI, and serious shop/team workflows.

Avoid duplicate feature names that confuse users. In particular, **AI audio clip review is paused and should not be sold as a separate Starter or Pro package feature for now**.
Scheduling access uses the current server-resolved Starter/Pro entitlement for
both scheduled post creation and rescheduling an existing queued post. Basic,
including a paid account whose entitlement has ended, cannot reschedule through
request body plan hints; rejection must leave the post and queue unchanged.
RevenueCat purchase preparation must establish the authenticated canonical user
before the SDK purchase, while subscription GET remains read-only and webhooks
cannot recreate missing/deleted users. Older mobile clients require a coordinated
API/app migration to this preparation step. The regressions ran in the local
API/Flutter suites on 20 October 2026; live rollout and native Store behavior
still require separate verification.

## Starter 199 THB/month

Starter should feel useful enough for a small shop to pay without needing analytics yet.

- 120 post units per month.
- Post unit counting: 1 platform = 1 unit.
  - Example: one video posted to TikTok, YouTube Shorts, Instagram Reels, and Facebook Page Reels uses 4 units.
  - After that example, Starter would have 116 units left.
- Schedule posts.
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
- Link in Bio basic page.
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
- Schedule posts.
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
- AI auto editing with Groq Whisper: 200 minutes per month, per the AI auto editing plan.
- Link in Bio advanced page, including future click or campaign insights.
- Team and editor access (roadmap; not an included benefit in the current app).
  - Planned: the shop owner can invite an admin/editor to help prepare uploads, captions, and scheduled posts.
  - Editors must not see the owner's TikTok, YouTube, Instagram, or Facebook passwords/tokens.
  - Recommended first version: simple owner/editor roles, invite by email, revoke access, and basic activity log.
  - If future agency workflows need many brands, approval chains, or client billing, create a separate Agency plan later.
- No separate AI audio clip review feature.

## Top-up

- AI auto editing top-up: 49 THB for 120 extra minutes.
- Applies to AI auto editing minutes, not regular posting units.
- Can be offered to Pro first.

## Paused / Removed From Package Marketing

### AI audio clip review

Do not include "AI audio clip review" in Starter or Pro package lists for now.

Reason:

- It overlaps with AI caption from real clip and the planned Groq Whisper auto editing flow.
- Users are more likely to understand "AI caption from your clip" than a separate "audio review" feature.
- Future direction: merge useful audio-review ideas into AI caption from a real clip transcript.

The active Clip Review UI, `/clip-reviews` backend route, backend config, and
internal mock/provider code have now been removed from the app path. Useful
ideas such as hooks, SEO wording, and hashtag suggestions should be rebuilt
inside real-clip captioning instead of kept as a separate review feature.

## Current implementation status

- Security remediation: RevenueCat buy awaits authenticated
  `POST /billing/purchase-readiness` with `purchaseReady: true` and
  `preparationProtocol: 1`. Unsupported/missing readiness, 404 and 501 prevent
  SDK buy and show a Thai compatibility message. GET subscription is read-only;
  webhook missing-user protection remains. Release the additive endpoint first,
  then preparation-aware apps, retire/disable legacy builds that skip it, and
  only then cut over GET. This branch bundles GET cutover, so those legacy
  builds must be addressed before deployment. Final subscription writes also
  lock the active owner marker in their database transaction. Mocked regression
  and concurrency cases ran in the local suites on 20 October 2026; real
  PostgreSQL/Redis races and sandboxed security validation remain pending.
  RevenueCat SDK configuration/product lookup through buy/restore completion is
  serialized and session-bound; readiness/resync/polling use bound HTTP headers.
  Already-dispatched native work and RevenueCat transfer policy still require
  device/provider validation.

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
    Production still needs real R2/Groq clip testing and the Prisma migration
    applied and verified against a real PostgreSQL database.
  - Team and editor access needs Pro entitlement checks, invite records, role permissions, revoke access, and an activity log.
  - Social account credentials/tokens must stay owner-scoped and never be exposed to invited editors.
  - Prompt-only AI caption entry points should be removed, hidden, or changed into optional extra guidance after a clip is selected.
  - AI audio review entitlement/marketing should stay removed or hidden.
- Mobile implementation and remaining package-copy guidance:
  - Package copy should match implemented benefits and keep roadmap items separate.
  - `PostDeeApiClient` can call the real-clip caption endpoint. Upload AI
    caption UI requires a selected clip first, keeps language/market automatic,
    and shows audio-only for Starter and audio+visual-frame mode for Pro.
  - A compact quota strip above `ให้ AI ช่วยเขียน` shows the current plan,
    remaining/limit, used count, and a thin remaining-quota bar. It reads
    authenticated `GET /captions/quota` on entry, Upload-tab activation, and app
    resume. Successful generation supplies the latest quota; failed attempts
    refresh the read because usage may already have been reserved. The read
    shares the existing UTC-month ledger without consuming quota; loading or
    failure must not be presented as zero remaining, and failed reads offer
    retry. An exhausted paid quota disables AI generation while manual editing
    and posting remain available. This display leaves package limits unchanged.
  - Team and Editor Access remains planned for Pro 299. Do not present it as an
    included benefit or claim that upgrading unlocks it in Profile, settings,
    or Paywall until the mobile, backend, and provider flows have been verified.
  - Any separate AI audio review UI should stay removed unless it is renamed into a future clip-based caption workflow.
  - Profile and paywall screens should show clear Starter vs Pro differences.
