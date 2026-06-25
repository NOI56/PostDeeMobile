# PostDee Subscription Packages Plan

> Status: planning source of truth for package positioning. Do not treat this as fully implemented behavior until the matching backend and mobile gates are updated.

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
- Team and editor access.
  - The shop owner can invite an admin/editor to help prepare uploads, captions, and scheduled posts.
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

## Notes For Implementation Later

- Backend currently needs updates before this plan becomes real behavior:
  - Starter post limit should change from 50 posts to 120 post units.
  - Post usage must count selected platforms, not just post rows.
  - Starter should be allowed to schedule posts.
  - Pro post limit should be 250 post units per month.
  - AI caption from real clip now has a mock-safe endpoint and memory/Prisma
    quota ledger options, plus transcription-backed language/market context.
    Production still needs real R2/Groq clip testing and the Prisma migration
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
