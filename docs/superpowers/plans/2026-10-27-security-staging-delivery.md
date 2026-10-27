# Security and reliability Staging delivery — 2026-10-27

Status: integration and validation in progress. This plan is not a test or
deployment receipt. Production remains suspended; no Production release or
app-store distribution is part of this delivery.

## Baseline and scope

Start from verified `origin/main`
`82d26a708282d346012ae9b412d19d0faa5d39f7` on
`codex/security-staging-delivery`. Port only the intended security/reliability
commit `67e7411824075d3ce95e0553acf73e771cfe841f`, cherry-picked as
`977a6124ccccffb1aef7d4bacceb1a475fe4889d`, and review fixes needed by that port.
Keep the pending publish-review presentation change in a separate commit.
Preserve unrelated worktrees and their uncommitted work.

The scope is caption media limits/audio transport, bounded in-process publish
concurrency and PostPeer request timeout, settled queue cleanup, invalid FCM
token cleanup, owner-scoped template deletion, constant-time webhook-token
comparison and Firebase Admin revocation checks with matching project identity.
The port also updates its existing test-tool dependencies.

Retain the latest main UI and existing publishing settings, quota/entitlement,
account-deletion, owner/session and managed-upload safeguards. AI editing stays
retired with `410 AI_EDITING_RETIRED` under its existing default configuration.
Facebook remains Page Reels only, with publish/Page-draft choices and no Page
feed fallback. Shopee Video and Lazada Video remain future targets.

## Compatibility and release order

1. Validate and release the API before Mobile starts sending `audioS3Key`.
   Older Mobile `videoS3Key` requests remain compatible; older APIs reject the
   new field. No schema migration, package/quota change or feature-flag change
   is introduced by this delivery.
2. For captions, keep whole MP4 when it fits 15,000,000 bytes; larger clips use
   temporary M4A, uploaded with existing `purpose: "ai-edit-audio"`. Accept
   exactly one media key and enforce the same budget on extracted audio. Pro
   may add selected frames. This is a per-clip cap; frames, base64 and request
   overhead can still cause provider fallback. Legacy video above the clip
   budget, up to the existing 200 MiB media ceiling, uses the local template
   without buffering the full clip.
3. Use the existing Staging service `srv-d9bb72ojs32c739osa5g` in confirmed
   workspace `tea-d45nsamuk2gs73cmhol0`. It tracks `main` with auto-deploy off.
   Retain its environment and provider settings; do not blindly sync Blueprint
   values or replace credentials. A configured Firebase service account must
   match the API's `FIREBASE_PROJECT_ID` even when the admin console is off.
4. Wait for CI and the selected Staging deploy to succeed, verify the actual
   deployed SHA and health/readiness, then deliver and smoke-test the matching
   Staging Mobile build. API deployment does not update an installed app.

## Verification and remaining acceptance

Required results are pending: targeted regressions, complete API tests,
typecheck/build and Prisma validation; complete Flutter tests/analyze and the
exact Staging APK build; final baseline diff review; CI; deployed-SHA and
post-deploy checks. Append actual commands, counts, environment and outcomes
only after they are observed.

Caption temporary-media cleanup remains best effort after a request. A completed
upload abandoned before generation can still be orphaned. Local fixtures and
health checks do not prove real Gemini caption quality, FCM delivery, social
publishing or purchase/restore lifecycle. Connected-account E2E and Production
migration/backup/compatibility acceptance remain separate gates before launch.
