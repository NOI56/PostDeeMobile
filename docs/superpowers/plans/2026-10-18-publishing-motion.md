# Publishing activity: shared motion and real channel results

สถานะ: ANDROID STAGING DELIVERED — release source `5c83b3a` passes CI and builds
APK 12026 with the existing Test Store settings. APK inspection, local signing,
guarded update and read-only native smoke pass. The compatible API is Live.
The earlier local build blocker below is historical; CI resolved delivery without
changing local SDKs or clearing user data. Active-sending/FPS and a new provider
publication remain unverified.

## Request and verified baseline

ผู้ใช้เลือก variant 3: แสดงสถานะกำลังส่งร่วมกับเส้นเคลื่อนไหวและผลจริงรายช่องทาง
ใน Home, Calendar และรายละเอียดโพสต์ โดยไม่แสดงเปอร์เซ็นต์ที่ไม่มีข้อมูลรองรับ

- Source worktree:
  `C:\Users\stopp\.codex\worktrees\admin-usage-accuracy\PostDeeMobile`.
- Branch: `codex/publishing-motion`; canonical main, HEAD and merge base:
  `1cf755eba9b156f95bb818eb2d5ee7fb7c0efd86`, initially 0 ahead/0 behind.
  Root verified fresh origin before implementation.
- Source-worktree Windows generated-plugin status is line-ending metadata only,
  with no actual source diff. The three original dirty generated-plugin files
  in the original `D:\PostDeeMobile` checkout and canonical main worktree remain
  untouched, as does unrelated work. No reset, wholesale branch copy or deleted
  capability.
- Earlier motion receipts remain historical:
  [Oct12 audit](2026-10-12-mobile-motion-smoothness-audit.md) and
  [Oct13 integration](2026-10-13-main-motion-audit-integration.md).

## Smallest implementation and preserved behavior

- `PostDeePublishingMotion` supplies one clock per post scope to the shared
  badge, indeterminate rail and sending-channel icons. It preserves phase on
  ordinary rebuilds, stops/resets when sending ends or animation is disabled,
  and respects reduced motion, `TickerMode`, lifecycle and disposal.
- Home, Calendar and detail reuse the same presentation. A still-`PUBLISHING`
  parent keeps its sending state even when only some provider results exist.
  Completed channels show their actual outcome while remaining channels can
  continue sending; the rail does not claim a completion percentage.
- Per-channel labels preserve `DRAFT`, `PRIVATE`, `UNLISTED` and `LIVE` meanings.
  `FAILED` overrides a stale successful outcome; `PENDING` means `รอส่ง`, a
  missing result means `รอผล`, and unknown status/outcome means `ผลยังไม่ยืนยัน`.
  Legacy `PUBLISHED` without an outcome retains `เผยแพร่แล้ว`.
- Home silently refreshes its existing recent-post read every 30 seconds only
  while a loaded recent post is `PUBLISHING`. The app must be resumed, Home
  active, its route current and its stable owner signed in. Hidden routes/tabs,
  background state, owner changes, terminal results and disposal stop polling;
  owner generations reject late results. `QUEUED` alone does not start this
  new Home timer. Existing manual/return refresh behavior stays available.
- Calendar retains its existing 30-second visible polling for `QUEUED` and
  `PUBLISHING`, plus selection, filters, owner guards and queue-only actions.
- Detail remains the `PostSummaryResult` snapshot passed during navigation.
  Refresh the parent list and reopen detail to see newer provider results.
  There is no single-post GET endpoint, subscription or detail polling added.
- Preserve scheduling/package rules, API owner scope, local drafts, existing
  publishing actions, media access, authentication and entitlement behavior.
  No API/schema/dependency/flag/configuration/entitlement change or migration.

## Initial local checkpoint: tests-first evidence and verification boundary

Regression tests were written before runtime patches. Root's initial Home RED
showed that a `PUBLISHING` post with partial provider results could display a
terminal label; Calendar RED showed the missing rail. These failures motivate
the scoped presentation fixes. Final source verification is recorded below.

The source volume had about 127 MiB free, so root prepared a verification copy
on D: with about 79 GiB free and D: `TEMP`/`TMP`. The final snapshot verified
SHA-256 matches for 562 files before checks: 560 source/test inputs plus
`docs/STAGING.md` and `shared/profile-templates.json`. Source edits remain in
the C: worktree. Both C: and D: SDKs report Flutter 3.44.1 / Dart 3.12.1.
The final audit also matches all 488 runtime/test/assets/config/tool inputs to
the verified D: manifest, with no API, pubspec or Android-code changes. The 15
intended files were uncommitted at that checkpoint; no task-owned Dart/Java
process remained after its build cleanup.

| Check | Current evidence |
| --- | --- |
| Shared motion/labels, Home, Calendar and detail, five targeted files | PASS: 145/145 |
| Full Flutter suite | PASS: 2,437; two optional previews skipped; 4 m 07 s |
| Flutter analysis | PASS: No issues; 10.8 s |
| Exact Staging APK build | BLOCKED by local tooling/resources; no verified APK |
| APK inspection and native installed-app checks | Not verified |

Focused coverage includes one shared rotation phase, stop/reset and fresh
restart under motion guards, ordinary rebuilds, disposal without leaked frames,
truthful per-channel outcomes, owner/visibility-safe Home refresh and 320px
layouts with doubled text. The first post-patch targeted run exposed fixture
finder/frame-settling issues and a narrow Home overflow; the scoped fixes are
included in the passing final results. Analysis required one braces-only lint
fix before its passing run. No FPS improvement or real provider publication is
inferred from widget tests.

## Initial local native build blocker and environment boundary

The first Staging helper build failed because the Dart VM could not start
thread `DartWorker` (error 22) during the `objective_c` native-assets hook. It reported
no app syntax failure. A retry used process-only resource limits: one Gradle
worker, parallelism/daemon disabled, heap 1536 MiB, metaspace 768 MiB, code cache
128 MiB and `ActiveProcessorCount=2`, with Gradle/Java/temp paths on D:. The
same-version SDK used by the tests then stalled before Gradle; the retry did
not produce a verified APK.

Root stopped only verified task-owned Dart/batch children and its own completed,
idle Gradle daemon to avoid leaving workers behind. No other process or source
configuration was changed. An SDK alias junction was confined to the D:
verification copy. These workarounds do not establish native build acceptance.

Source configuration checks identify Staging API
`https://postdee-api-staging.onrender.com`, Firebase project
`project-798caf7e-85b8-45e3-af7` and Android package
`com.postdee.postdee_mobile.staging`. These are source settings, not inspected
APK contents. No APK inspection, native install, app/user-data mutation,
physical-device FPS check or provider publication occurred for this work.

## Changed code and test inventory

Runtime:

- `apps/mobile/lib/features/shared/postdee_publishing_motion.dart` (new).
- `apps/mobile/lib/features/home/home_screen.dart`.
- `apps/mobile/lib/features/calendar/calendar_screen.dart`.
- `apps/mobile/lib/features/posts/post_detail_screen.dart`.

Regression tests:

- `apps/mobile/test/postdee_publishing_motion_test.dart` (new).
- `apps/mobile/test/home_publishing_motion_test.dart` (new).
- `apps/mobile/test/calendar_motion_test.dart`.
- `apps/mobile/test/calendar_screen_test.dart`.
- `apps/mobile/test/post_detail_screen_test.dart`.

## Documentation scope

The initial implementation syncs `README.md`, `ROADMAP.md`, `API.md`,
`ARCHITECTURE.md`, `apps/mobile/README.md` and this plan. The authorized release
also updates `docs/STAGING.md` and the opt-in CI build instructions. Earlier
receipts remain intact. Native delivery is established by the actual release
checks below, not by a source push or an API deploy alone.

## Authorized release follow-up

The user requested `push/deploy` after reviewing the source-verification result.
Fresh `origin/main` was `1cf755e`; only the intended publishing changes were
prepared. Native release verification was a gate before main integration.

- A further read-only audit matched 531 Mobile runtime/test/asset/platform/tool
  inputs against the verification manifest with zero mismatches.
- Local Flutter tooling still stalls before its main command, including direct
  `flutter_tools.snapshot` invocation. Further local build attempts were stopped;
  only verified task-owned processes were cleaned up.
- The existing opt-in GitHub APK build disables billing, so it cannot replace
  the installed Test Store app unchanged. The delivery follow-up adds an optional
  CI Test Store overlay and explicit build number, with synthetic-key regression
  tests. Only the existing public `test_` Android SDK key is stored as a GitHub
  Actions secret; no private configuration or signing key is uploaded. APKs are
  signed locally with the existing debug key.
- Native preflight finds Staging version 12025 on `emulator-5556`, retaining the
  original app UID and adopted volume. Candidate build 12026 must use the guarded
  volume-aware updater. No uninstall, data clearing or cross-volume move is
  authorized or needed.
- The previous live API was `fc457b2` / `dep-dba64iqjnfac73egt8i0` in the previously
  confirmed My Workspace. Unlike the motion feature itself, main's earlier
  `ce501d4` YouTube-title follow-up includes a backward-compatible post-route
  change absent from that Live version. The release incorporates that reviewed
  change after checks pass. There is no schema, dependency or environment-variable
  diff.
- Pre-deploy `/health` and `/ready` return 200 with database/queue ok; unauthenticated
  posts and publishing-readiness reads return 401. No provider post, purchase,
  user-content edit or Production deployment is part of the checks.

## Verified release results

- Feature source `5c83b3a91625a3c5ab3ddfe58f17c895fc8347c5` is pushed on
  `codex/publishing-motion`. [CI 39110380204](https://github.com/NOI56/PostDeeMobile/actions/runs/39110380204)
  succeeds at that exact source/workflow SHA: Flutter 2,437 pass/2 optional skips,
  analyze with no issues (13.6 s), CI build/receipt guards 17/17, API 2,291 pass/18
  optional skips, generator 22/22, TypeScript, build, Prisma and production
  dependency audit. The CI SDK is Flutter 3.47.7 / Dart 3.13.5, distinct from the
  initial local 3.44.1 / 3.12.1 checks.
- The CI helper retains default billing-off behavior. This release explicitly
  opts into the existing Android Test Store public SDK key and build 12026.
  Expected and actual merged-defines SHA-256 match:
  `fa0491fa29b90c2f22e66e98162aa55f9ac7ca932df0abcf11f73a19ed4de6ae`.
  The helper and workflow receipt tests cover invalid configuration/key/build
  numbers, value redaction, actual APK identity/version and hashes. Key values
  are not printed in logs; standalone merged configuration and private signing
  keys are not uploaded. The public SDK key is necessarily embedded in the APK.
- Actual APK identity is `com.postdee.postdee_mobile.staging`, min SDK 24 / target
  36. Resources match Firebase project `project-798caf7e-85b8-45e3-af7`; the kernel
  contains the Staging API, existing public SDK key and motion/platform-row code
  (checked as booleans only). Firebase auth is on, local mock auth and existing
  experimental AI/beat-sync flags are off. Billing is Test Store only.
- Original CI APK: 286,199,022 bytes, SHA-256
  `94e7f9bcc842f5d21f20ba67b6fcd46edb5be384e20da023d622ccab8fe57314`.
  Locally signed APK: 286,278,426 bytes, SHA-256
  `96dde68bd1807a1a10f47952175607d344a4bdc3a1320b3700682cf9c0229db8`.
  All 857 ZIP entry payload hashes match before/after signing, with none skipped;
  16 KiB alignment and v2/v3 signatures pass. The signer is the existing local
  debug certificate, SHA-256
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
- [Render deploy dep-dba83jqjnfac73enqm40](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-dba83jqjnfac73enqm40)
  is Live at `1cf755eba9b156f95bb818eb2d5ee7fb7c0efd86` from 15:24:35 Asia/Bangkok.
  It precedes APK installation. Its `apps/api` tree
  `14d236436b6e9aa16d02b91cc365f8a53d3f0a94` exactly matches candidate `5c83b3a`;
  no repeat API deploy is needed for the later Mobile/documentation integration.
  Auto-deploy remains off; service plan, secrets, flags, network and Production
  remain untouched. Startup reports 20 migrations and none pending. Post-live
  `/health` and `/ready` return 200 with DB/queue ok, unauthenticated posts and
  publishing-readiness return 401, and recent app error logs contain zero entries.
- A fresh authenticated admin overview at 15:22 shows only 2 failed, 1 partial
  and 8 completed posts. Its full status grouping has no queued/publishing rows.
  Direct MCP SQL is unavailable because the database blocks external access;
  the local CLI is unauthenticated. Neither restriction was changed. Migration
  state is confirmed by the successful internal deployment log, not direct SQL.
- Guarded update 12025 → 12026 succeeds on `emulator-5556`, retaining UID 10190,
  the mounted adopted volume and original 2026-10-05 first-install date. Existing
  certificate hash and package metadata remain consistent. No uninstall, data
  clearing, volume migration or downgrade. Android mount restrictions prevent a
  fresh byte hash of the installed APK; candidate payload/signature verification
  and the guarded package update are the installation evidence.
- Native smoke passes Home → Calendar/all week → Shorts filter → existing detail
  → Account → Home. Pro 244/250, saved draft, 2/4 connected channels and history
  remain present. Calendar shows 4 week posts / 2 Shorts-filter posts and the
  selected Oct 18 post. Existing detail preserves TikTok live / YouTube private
  labels and shows no sending rail for terminal results. The first entitlement
  read temporarily failed; one read-only refresh restored Pro on Home and Account.
  Its cause is unconfirmed; no entitlement/token/account change was made.
- The 907-line native crash-log slice has zero fatal, unhandled, E/Flutter or
  crash matches. The app is left on Home. No real post, AI generation, purchase,
  draft save or deletion was performed. No genuine `PUBLISHING` record existed,
  so active animation/FPS on native and provider acceptance are not claimed.
  Detail remains a snapshot: return to the refreshed parent and reopen it for
  newer results.
- Generated Python cache is preserved under the task evidence directory, rather
  than staged in Git. Only intended source/test/CI/documentation changes are
  integrated; pre-existing generated-plugin metadata and unrelated artifacts are
  retained. The documentation receipt does not alter the verified runtime;
  remote main identity is checked again after the authorized fast-forward/push.

Local evidence: `D:\PostDeeMobile\artifacts\publishing-motion-20261018`, including
`ci-39110380204.json`, `ci-39110380204.log`, `api-staging-delivery.json`,
`post-deploy-http.json`, `native-apk-verification.json`, `native-update.json`,
`native-final-receipt.json`, `native-crash-counts.json` and native screenshots.

Additional delivery tooling: `.github/workflows/ci.yml`,
`scripts/prepare_staging_ci_defines.py`, `scripts/test_prepare_staging_ci_defines.py`
and `docs/STAGING.md` (19 files in the runtime/CI checkpoint). The final receipt
only updates documentation and preserves the verified Mobile and API trees.
