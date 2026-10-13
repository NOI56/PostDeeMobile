# Security integration into current main — 2026-10-13

Status: MAIN PUSH + STAGING DELIVERY + EMULATOR UPDATE COMPLETE. Runtime source
`9244f16dba0850839029a3a6ada89f7df0e008e2` has fresh local verification, Staging
Live deployment and retained-data basic native smoke. This does not declare
Production ready or close the original audit's remaining validation gaps.

## Scope and baseline

The user requested main push/deployment and showed the Android Emulator with
the Staging marker and the current Store link editor. Delivery preparation
targets that Staging app first; Production scope has not been confirmed.

Verified by `git fetch origin main codex/ai-edit-thai-timing-staging --no-tags`:
`origin/main` is `c4e52201a58b556f5f47529027549a2fc16af84c`. A fresh managed
worktree, `security-main-delivery/PostDeeMobile`, and branch
`codex/security-main-delivery` start at that exact commit (merge base matches,
ahead/behind 0/0). The original `D:/PostDeeMobile` worktree and its uncommitted
changes are preserved.

During preparation another authorized main integration advanced the shared
remote from `c4e5220` to `f5dea16f59bfb317c92971c6bbef60d8b742ea5d` (30 commits,
including system-audit reliability fixes and current mobile motion). A second
`git fetch origin main --no-tags` verifies that latest head. Local WIP checkpoint
`b4961e8` preserves the initial port; it has not been pushed. Reconciliation
onto `f5dea16` completed locally at checkpoint `b632b5a`, retaining both sides
intentionally, including content fingerprints,
image protection, device token rotation/unregistration/cold taps, native billing
acknowledgements and all current motion UI. No whole-file older-side resolution.

Earlier audit/remediation artifacts reviewed `0882996` plus a dirty working
tree, not this current main. Their source findings and 50 + 130 unrun added
cases must not be presented as verification of this delivery branch. Replay
only still-applicable behavior; do not copy old files over main or replay an
entire stale branch. Main already has trusted-proxy/IPv6 rate limiting, paid
rescheduling admission, stable mobile identity and per-owner drafts.

## Existing behavior to preserve

- Current Store link UI, website publication, themes, images, compositions,
  contacts and custom links; per-UID drafts and account-deletion cleanup.
- Home, Calendar, account/profile, bottom navigation, the full-screen
  four-step post composer and saved publish drafts.
- Current PostPeer mappings, target/settings validation, idempotent post
  creation/queue repair, `publish-now`, scheduling limits and real receipts.
- Shared API mutation/deletion coordinator, readiness, shutdown and provider
  uncertainty handling; do not create nested owner-lock deadlocks.
- Firebase credential snapshots/UID validation, auth timeouts/disposal and
  existing Thai errors. Billing session cache, pending confirmation and retry
  must not buy twice when an already-dispatched payment needs confirmation.
- Existing configuration, schema/migrations, dependency locks, providers,
  Staging Firebase project and APK signature. No Production/provider activation.

## Selective source integration

1. Final User ensure, Post create/quota/reschedule/publish-now and Subscription
   activation/RevenueCat event writes check and lock an ACTIVE owner marker in
   the same Serializable database transaction. Memory stores share owner
   admission. Keep legacy mode owner checks independently of multipart.
2. Queue admission covers enqueue, ensure-enqueued and reschedule while
   preserving current idempotent semantics, health/close functions and account
   cleanup of owned jobs without post rows. Keep Redis outside SQL transactions.
   Preserve main's acknowledgement/error/SQL rollback boundaries: no generic new
   queue acknowledgement timeout or broad late compensation removes previously
   accepted/idempotent jobs. The independent lifecycle FIFO has a five-second
   admission/drain wait; it does not bound the existing HTTP coordinator's wait
   or the complete DELETE request.
3. Add authenticated `POST /billing/purchase-readiness` returning
   `status: ok`, `purchaseReady: true`, `preparationProtocol: 1`; current mobile
   validates it before RevenueCat buy. Keep legacy GET user preparation during
   this additive rollout, now subject to final owner fencing. This delivery
   stage does not include the earlier stale branch's read-only GET cutover.
4. Add session generations to the existing stable identity/credential store,
   bound HTTP operations and a shared native auth queue for account deletion,
   Apple revocation and phone linking. Retain main's caller/UI timeouts/cleanup,
   while holding the queue until the raw SDK work settles, including both phases
   of Google sign-in. An expired queued attempt must not dispatch later.
5. Preserve billing pending-state behavior while binding preparation, SDK
   configuration/product lookup, buy/restore, reconciliation and entitlement
   polling to their original operation. Never retarget a later account.
6. Clear/filter in-app push history by exact recipient UID and bind token
   registration. Backend publish notifications carry `data.userId`.
7. Retain current rich Store link draft fields and server publication; guard
   delayed operations/modal results on session-generation changes and close
   only routes owned by the affected editor.

## Verification and delivery gates

Add/update regression cases before implementation, review the diff against the
verified main baseline and run the relevant full API/Flutter checks plus exact
Staging APK build/identity checks before deployment. Deploy the additive API
before updating the installed app, then smoke-test the retained-data device
against that compatible API before declaring delivery complete. Check package/API/Firebase/
entitlement/source SHA and keep the existing signature/session/data when
updating the Emulator; never uninstall or clear data to bypass a signature
mismatch.

Current status: selective source integration and independent source review are
complete in the local branch based on `f5dea16`. Added regression cases: 35 API
and 113 mobile (148 total). Trusted-parent `git diff --check` passes and no merge
markers remain. The user explicitly answered "อนุญาตให้รัน test/build ตามปกติ"
to the delivery execution question, exempting the audit skill's OS-sandbox rule
for normal project test/build on the host or CI. The earlier audit evidence
retains its original needs-validation/UNRUN status; this is new delivery evidence.

Local verification on the prepared source:

- Fresh API `npm ci` and Prisma generation pass; lockfile unchanged and only a
  dummy local `DATABASE_URL` is used. No database/server/provider is launched.
- API targeted changed tests: 293/293 in 16 files, plus helper regression runtime
  tests. Final full `npm run test -- --maxWorkers=4`: **1,816/1,816 in 115 files**
  (32.23 s). API production build, schema validation and seed/config helper
  compilation pass. The new `ownerLifecycleTypes.test.ts` standalone strict
  compilation fails before the generic fix and passes after it.
- Catalogue `--check` passes with all 100 templates; generator tests **22/22**.
  Production dependency audit at CI's high threshold passes (0 high/critical,
  4 moderate advisories); no dependency change was made.
- Flutter **3.44.1 / Dart 3.12.1**, locked `pub get` passes; targeted **318/318**,
  analyze **No issues found** (24.0 s), full tests **2,171/2,171** (2:25).
- Initial checks exposed and fixed generic transaction result inference, a
  duplicate Dart import, missing braces, and shell test fixtures. An unchanged
  catalogue image sweep timed out once while checks competed for host resources;
  isolated 20/20 and the controlled-worker full suite pass without timeout edits.
- Full test-inclusive API `tsc -p tsconfig.json` remains **failed with 142 fixture
  typing errors**. A clean pinned-f5 snapshot using the same dependencies has
  the same file/error-code counts. Some wrapper error messages differ; this does
  not claim full type-check success or eliminate that existing test typing debt.

Logs: `.tmp/security-delivery-api/` and
`apps/mobile/.tmp/security-delivery-mobile/`. These are local ignored artifacts.
Exact APK build, main push, Staging deploy and basic native smoke pass as below.

Source preparation and independent review are complete in a local branch
(78 changed files: 38 API source/tests, 31 mobile source/tests, 9 documentation).
Only the following recorded actions constitute delivery evidence; earlier
audit findings and historical CI/smoke keep their original meaning.

## Exact delivery receipt

- Verified source: `9244f16dba0850839029a3a6ada89f7df0e008e2`, two commits ahead
  of pinned `f5dea16` and zero behind. Fresh-fetch immediately before delivery
  confirms that baseline. No changed schema/migration/dependency/provider/Render
  configuration, unexpected deletions or Home/Calendar/composer rewrites.
- Root pushes the review branch, fast-forwards canonical local main, and pushes
  remote main normally. Both remote refs are verified exact `9244f16`. Fresh
  branch protection is absent and applicable branch rules are empty; no PR is
  required or created. Existing generated files and three QA artifacts in the
  main checkout retain all six SHA256 hashes and remain excluded from commits.
- These commits carry `[skip ci] [skip render]`. Verification is the new local
  evidence above, not an asserted new CI run. Manual Staging deployment pins the
  tested SHA and avoids an automatic Production release.
- Render Staging service `srv-d9bb72ojs32c739osa5g`, deployment
  [dep-db71pfbl550s73ag4uo0](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db71pfbl550s73ag4uo0),
  manually starts **18:57:50 GMT+7** and reaches **Deploy succeeded | Live at
  18:59:41 GMT+7 on 2026-10-13**, duration **1m51s**, source exact `9244f16`.
  Build succeeds; start logs show **16 migrations / No pending migrations**,
  social publisher disabled and memory publish scheduler. Actual auto-deploy
  remains disabled/specific-commit; no service setting/feature flag is changed.
- Post-deployment `/health` and `/ready` return HTTP200, with database/queue ok.
  Unauthenticated `POST /billing/purchase-readiness` returns HTTP401 requiring
  a Bearer token. This establishes the live auth gate; the authenticated protocol
  response is covered by local route tests, not a claimed live SDK purchase.
- Exact APK command: `apps/mobile/tool/postdee-staging.ps1 -Command build-apk`
  with `--target=lib/main.dart --target-platform=android-x64 --build-number=8017`.
  Flutter 3.44.1, Gradle assembleDebug succeeds (108.1 s). Package
  `com.postdee.postdee_mobile.staging`, versionCode **8017**, Staging API,
  Firebase project `project-798caf7e-85b8-45e3-af7`, Firebase auth on/local mock
  off, and existing ignored RevenueCat Test Store overlay (key not retained).
  This debug target is for the Emulator; it is not an app-store release.
- APK SHA256: `A4A8798201602CCAA0F9E4E9321B411822883C2057C6B0F2D493405D5CFB5D57`.
  Signer SHA256: `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`,
  matching installed8016. Root uses `adb -s emulator-5556 install -r`; **Success**.
  Package metadata confirms8017, same data directory/signature/first-install time.
  No uninstall, clear-data, credential change or sign-out is performed.
- Native basic smoke: app running; Home, Calendar, Account and Store link load.
  Shop **noikub** remains published at the same profile slug with **2/20 links**.
  Test Store paywall loads product prices; back navigation returns normally.
  Phone form opens/cancels without sending SMS. Current app PID log scan has no
  fatal/unhandled/framework exception matches. No buy/restore, real OTP, publish,
  account deletion, provider-failure injection or A→B live identity switch is
  performed; their mock regression coverage is not physical-device acceptance.
- Production API `srv-d8uf2sbtqb8s73b6ptmg` is freshly observed **Suspended by you**
  after delivery. No Production resume, deploy, environment or database mutation
  is performed. Original dirty `D:/PostDeeMobile` remains untouched.
- Local ignored evidence: `.tmp/security-delivery/{receipt.json,
  post-deploy-probes.json,mobile-source-manifest.json,apk-build.log,
  main-preserved-before.json,main-preserved-after.json,emulator-8017-final.png}`.
  Screenshots/QA records containing account details are kept local, not pushed.

The receipt-only follow-up commit changes documentation, with skip tokens;
runtime blobs must match `9244f16`. It requires no duplicate build/deploy/install.

## Remaining limitations

Owner database fences do not make SQL/Redis or multiple API processes atomic.
Already-admitted provider/native operations cannot be canceled by a generation
check; cross-instance late queue adds, crash recovery and draining need separate
work. Existing managed-upload snapshot admission and other account stores are
outside the three-entity final-write guarantee. Main's device token rotation,
authenticated unregistration and cold-start tap handling are preserved. In-app
recipient filtering alone cannot establish backend cleanup or control
OS-displayed background notifications; runtime lifecycle checks remain pending.

Mock auth now uses the configured `AppConfig.mockUserId`, aligning local scope
with the API's development principal. Existing published server profiles reload
under that owner. Older local drafts under `local-mock-user` remain in their
original scope; no automatic draft migration or deletion is included.

Billing rollout: additive endpoint → preparation-aware mobile builds → retire
or independently disable any deployed legacy buying builds → consider a
separate read-only GET cutover. Confirm whether such builds exist before that
last step. Never restore missing-user webhook recreation as a compatibility
fallback. Unsupported/missing preparation must stop before a new SDK buy, while
already-completed payments retain main's pending-confirmation/retry flow.
