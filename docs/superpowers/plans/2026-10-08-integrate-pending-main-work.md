# Integrate genuine pending work — 2026-10-08

## Scope and baseline

The user requested completing genuine pending work into `main` and pushing it.
Historical patch-equivalent commits, obsolete AI editing drafts and old PRs do
not represent additional requested product features. Preserve current login,
the dock/running-dot motion, four-step full-screen Create post, publishing
safety, hundred profile logos/templates and account/draft ownership.

Shared integration branch: `codex/integrate-pending-main-work`, initially at
`b1f793ca3119c64cc38984029005e5a3ff771873`. No dependency refresh, schema
migration, provider activation, new statistics subscription, Render change or
manual API deployment is included. Scaling is future planning only.

## Stage 1 — delivered

- [x] Preserve current main navigation in the mobile UI cleanup at `aafd076`.
- [x] Verify app-source CI `37749129032` on that exact source: API 1,556 tests in
  104 files, Flutter 1,571 tests/analyze, generators/build/schema/audit and APK.
- [x] Integrate and push main `b1f793c`, which adds the existing delivery receipt.
  The cleanup removes Home monthly metrics, unsupported connection choices and
  duplicate Account shortcuts; related features remain in their active flows.
- [x] Main CI `37751374749` passed on `b1f793c` after integration.

## Stage 2 — source, native and CI delivery complete

Source commit `36dbaccb1d23ee46f9c970f2fdd8fff3d32b01d0` is pushed to the
integration branch, fast-forwarded to main and pushed to remote main. The local
and origin main refs agree with ahead/behind 0/0. Exact-source CI
[37754460435](https://github.com/NOI56/PostDeeMobile/actions/runs/37754460435)
completed successfully with both Backend API and Flutter Mobile jobs on that
exact full source SHA, independently of the earlier Stage 1 run. The main-push
workflow intentionally skipped APK building; APK acceptance below uses the
validated local build, not an asserted CI APK.

1. Owner-only Home previews: opt-in `includeMedia=true&limit=3`, newest-first
   bounded signing, cover preference, optional URLs, private/no-store and safe
   fallback on server/mobile failures. Plain `/posts` remains compatible.
2. Runtime hardening: trusted-proxy/IPv6 rate keys, two-second single-flight
   `/ready`, 30-second shutdown/drain and interrupted recovery only from saved
   complete terminal receipts. Unknown outcomes stay untouched/not ready.
3. Preserve main's existing route-level Prisma User preparation after its
   validation/quota gates. The generic preparation prototype duplicated already
   delivered behavior and is removed. New guard matching normalizes case and
   trailing slashes for mutating social/billing reads and includes `GET`/`HEAD`
   `/uploads/:uploadId` reconciliation, draining through response completion.
4. Explicit Staging-only 18 dp noninteractive build strip plus portable Windows
   exact-main launcher, environment SDK discovery and existing validated helper.
5. Reconcile the future scaling proposal and the historical hardening record;
   sync README, ROADMAP, API, ARCHITECTURE, GO_LIVE and STAGING.

Ownership during implementation: backend lifecycle/rate/recovery, Home
API/mobile, root owner-guard/readiness wiring, and Staging tooling/docs are separate
areas in the shared checkout. Pre-existing generated Windows plugin files and
ignored artifacts are not source changes for this integration.

Targeted results recorded so far:

- Home/client Flutter: 116 tests passed. Home covers/frame deadline/disposal and
  old API compatibility; previews do not autoplay or fetch off-tab.
- Backend hardening: 110 tests in 14 files passed; eight meaningful failing
  regressions preceded runtime implementation. Build passed. A provider result
  followed by persistence failure makes the scheduler unavailable; complete
  saved receipts can recover without a second publish.
- Root owner-guard targeted verification: four case/trailing-slash variants
  and three upload-status cases failed before implementation; the subsequent
  49-test targeted run passed. It covers blocked deletion, in-flight reads and
  upload reconciliation drain. Existing route-level FK preparation remains on
  main; there is no new generic preparation error contract.
- Staging badge: four tests passed after failing compilation exposed the missing
  behavior. Production-off, narrow-screen login scrolling and existing dock,
  notification/composer-close/Account hit areas are covered.
- Launcher and Staging helper parse successfully. `-ResolveOnly` resolves exact
  main plus SDK/config paths without build, adb, install, logging or UI actions.

## Current local verification — 2026-10-08

- Full API suite: 1,609 tests in 107 files passed in 42.32 seconds. TypeScript
  build, Prisma 6.19.3 generation/schema validation and helper type checks pass.
- Shared catalog checks confirm 100 profile templates and 100 platform logos;
  generator suite: 22 tests passed.
- Production audit: no high/critical findings; four moderate findings remain
  unchanged from the baseline. Package manifests/lock/schema were not refreshed
  or migrated by this integration.
- Compiled `dist/server.js` listened successfully in Firebase-auth mode with
  mock-safe providers: `/health` and `/ready` returned `200`, and private
  `/posts` without a token returned `401`. Emitting `SIGTERM` through the real
  entry point stopped HTTP intake and drained the scheduler successfully. This
  local smoke does not prove real Firebase tokens, live DB/Redis or provider
  acceptance/crash recovery.
- Full Flutter suite: 1,588 tests passed. The final 45-test badge/Home run also
  passes after explicit `TextDecoration.none` for the Staging text and the
  test-factory lint correction. Final Flutter analyze reports no issues.
- Validated Staging APK build passed with Flutter 3.44.1 / Dart 3.12.1. Final
  source/runtime parity and existing signature were verified; the installed
  APK is identical to the built APK: 281,390,530 bytes, SHA256
  `e5620b662a051bd9b0f889fae60f867cbbeaa14ae3bea558eba7c8c7b84cedd7`.
- Native `install -r` succeeded with the account/session, two profile links,
  Free 0/3 and YouTube 1/4 retained. Home, Calendar, Store and Account are
  observed; connections list contains only the four supported platforms.
  Create post opens the four-step full-screen composer, shows draft (1), has
  no dock and retains the plain Staging badge. Closing with X without edits
  returns Home. No save/publish, store purchase, OTP or connection write was
  performed during this smoke.

These are current local/source and limited emulator results, not live provider
verification. Stage 2 commit/main/push and exact-source API/Mobile CI are
complete at `36dbacc`. Stage 1 main CI `37751374749` is a separate earlier
result. The separate unsigned-iOS workflow
[37754460621](https://github.com/NOI56/PostDeeMobile/actions/runs/37754460621)
also completed successfully at the same exact source SHA. It builds with
`--no-codesign`; no iPhone device/App Store acceptance is claimed.

## Remaining operational limits

- Memory scheduling uses durable Prisma post records but runs in one API
  process. Local owner locks/rate counters do not coordinate separate processes;
  do not enable multi-instance or independent workers without shared barriers.
- `/ready` checks DB/queue availability, not provider/storage/account health or
  independent-worker heartbeat. Unknown `PUBLISHING` outcomes require operator
  provider verification and restart after reconciliation, never blind resend.
- API preview/lifecycle additions have not been manually deployed in this task.
  New APKs show placeholders with an older API; live signed R2 URLs and real
  PostgreSQL/Redis/provider crash/drain behavior require later release checks.
- No production deployment, paid statistics ingestion, active AI editor or
  additional provider is introduced. Existing product plans take precedence
  over historical editing/dependency notes.
