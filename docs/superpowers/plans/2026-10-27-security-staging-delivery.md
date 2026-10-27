# Security and reliability Staging delivery — 2026-10-27

Status: implementation integrated and pushed; local validation, GitHub CI,
iOS build and Staging delivery passed. Production remains suspended; no
Production release or app-store distribution is part of this delivery.

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

Local validation, GitHub CI, deployed-SHA and post-deploy checks are recorded
below. Real provider/paid-account acceptance remains separate.

Caption temporary-media cleanup remains best effort after a request. A completed
upload abandoned before generation can still be orphaned. Local fixtures and
health checks do not prove real Gemini caption quality, FCM delivery, social
publishing or purchase/restore lifecycle. Connected-account E2E and Production
migration/backup/compatibility acceptance remain separate gates before launch.

## Local verification and main receipt

- Source `9bba2e37b51abc36454aeba4612553659d0614d6` was pushed to
  `origin/main` with a normal fast-forward push after refreshing the remote.
  It preserves baseline `82d26a70` and contains port `977a6124`, review fixes
  `00e1dd2c`, and the separately committed publish-summary change `3f27f158`.
  The final baseline diff contains 48 related files, no deleted files, no
  Prisma schema/migration changes and no feature-flag changes. Existing dirty
  worktrees were preserved; the original main worktree's two requested UI
  files were committed there rather than discarded.
- API validation used Node **22.23.3** and a clean `npm ci --include=dev`.
  Regression tests first reproduced the mismatched Firebase-project and
  uncancelled oversized-body cases, then passed **8/8** after the fixes.
  `npm run test -- --maxWorkers=2 --no-file-parallelism` passed **2,888 tests /
  54 skipped**, **180 files passed / 9 skipped**, in 177.61 seconds.
  The skipped suites are not evidence of real database/provider acceptance.
- The first API suite run, while Flutter/Gradle were running, hit four
  existing Sentry fatal-child startup deadlines. The unchanged tests passed
  **4/4** in isolation, then passed in the complete final API run above; no
  timeout was relaxed and no monitoring implementation was changed.
- `npm run typecheck`, `npm run build`, `npm run prisma:generate`,
  `npm run prisma:validate`, and the documented seed/config helper `tsc`
  command passed. Prisma validation used a placeholder local URL, not the
  hosted database. Production dependency audit with
  `--omit=dev --omit=optional --audit-level=high` reported **0 vulnerabilities**.
  Shared profile-template catalog parity and its **22 tests** passed.
- Bundled Flutter **3.44.1 / Dart 3.12.1**: cached `pub get --offline`,
  **163 targeted tests**, full `flutter test --no-pub --reporter expanded
  --concurrency 2` (**3,173 passed / 6 skipped**) and
  `flutter analyze --no-pub` (**No issues found**) passed. The new review
  test was observed failing before the requested presentation change.
  Staging CI define/receipt guards passed **21 Python tests**.
- The Staging helper built debug APK **12062**, package
  `com.postdee.postdee_mobile.staging`, using the checked-in Staging example
  and the existing ignored RevenueCat Test Store overlay. The API base is
  `https://postdee-api-staging.onrender.com`; Firebase is
  `project-798caf7e-85b8-45e3-af7`, Firebase auth is enabled, local mock auth
  is disabled, and experimental hook/beat-sync defaults remain false.
  No key or credential was copied into Git.
- APK SHA-256:
  `B200503453F972B6A0094729FD4F00C0471A465ED0CE950F0F2A9B0F40B55CA9`.
  `git diff origin/main --quiet` confirmed the actual build workspace matched
  the pushed source, including both review-summary files. Flutter-generated
  Windows registration changes were excluded from the release.
- Existing Emulator baseline before update: package version **12061**, UID
  **10197**, internal storage, an authenticated Free account, zero connected
  channels and an existing saved clip draft. After API deployment the safe
  update installed **12062**, preserving UID **10197** and the same internal
  storage. No uninstall, data clear, account/plan change or real provider
  publication was performed.
- Exact-source GitHub runs: CI
  <https://github.com/NOI56/PostDeeMobile/actions/runs/40519611458> and iOS build
  <https://github.com/NOI56/PostDeeMobile/actions/runs/40519611394>.
  Both completed **success** on the exact source above. The iOS workflow built
  an unsigned app/IPA artifact; it did not publish to the App Store. Local logs
  and native before/after evidence remain under the ignored `.tmp` directories
  in the delivery validation worktree.

## Staging deployment and native smoke receipt

- Existing service `postdee-api-staging` / `srv-d9bb72ojs32c739osa5g` was
  manually deployed from the confirmed workspace after the main CI succeeded.
  Deploy `dep-dbgb98d9el5s73cejsh0` selected exact source
  `9bba2e37b51abc36454aeba4612553659d0614d6` and became **live on 2026-10-27 at
  21:28:09 Asia/Bangkok** (14:28:09.955366 UTC):
  <https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-dbgb98d9el5s73cejsh0>.
  No credentials, environment values, service settings or feature flags were
  changed. Staging auto-deploy remains off; API deployment preceded the Mobile
  update.
- Startup found **25 migrations / no pending migrations**, enforced the
  existing PostPeer empty-backlog guard, reported an empty publish backlog and
  listened on port 10000. This release adds no schema migration.
- Post-live `/health` and `/ready` returned **200**; readiness reported database
  and queue `ok` with `Cache-Control: no-store`. Unauthenticated template list,
  caption generation and the new template-delete route returned **401**. The
  delete route was **404** before deployment because it did not exist.
  `/ai-edits` remained **410**, preserving the retirement gate.
- The existing public demo shop returned **200** before and after deployment.
  After normalizing only the per-request CSP nonce, its content SHA-256 stayed
  `889BB66379AB0DB5F1785D2ACE8197A89C4A204C71D10101B4EE4709C159BDE7`.
  No published shop content was edited.
- On the updated Emulator, the same saved draft file and `ทำต่อ` action remained
  visible, connected-channel count remained **0/4**, and the account page
  retained its Free plan and **0/3** remaining post units without a load-failure
  message. Visual inspection and native UI hierarchy checks passed. These are
  account/draft preservation checks, not a real caption or publishing E2E.
- A bounded error-level Render log query for **14:28:10–14:30:20 UTC** returned
  no entries. The native account was Free with no connected channels, so no
  paid Gemini generation, real FCM send, authenticated hosted template CRUD,
  social publication or purchase/restore acceptance was performed in this run.
  Owner-scoped deletion, audio transport/cleanup, scheduler, timeout and token
  behaviors are covered by the local regressions and exact-source CI above.
- Production service `srv-d8uf2sbtqb8s73b6ptmg` was checked after the source push
  and remained **suspended**. It was not resumed, redeployed or migrated.
  The following receipt-only commit changes no API/Mobile source and uses
  `[skip ci] [skip render]`; another API deployment is unnecessary.
