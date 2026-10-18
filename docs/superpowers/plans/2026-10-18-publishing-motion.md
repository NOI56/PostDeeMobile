# Publishing activity: shared motion and real channel results

สถานะ: SOURCE VERIFIED / NATIVE BUILD BLOCKED — targeted/full Flutter tests and
analysis pass. Local tooling/resources prevent a verified Staging APK; package
inspection, installation and native acceptance remain unverified. Delivery is
incomplete. The user subsequently authorized push/deploy; release verification
is in progress, with no native delivery claimed yet.

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
  in the canonical `D:\PostDeeMobile` checkout remain untouched, as does unrelated
  work. No reset, wholesale branch copy or deleted capability.
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

## Tests-first evidence and verification boundary

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

## Native build blocker and environment boundary

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

Sync only `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`,
`apps/mobile/README.md` and this plan. Earlier release receipts remain intact.
The automated source checks pass; native build/delivery remains incomplete.
The subsequent push/deploy request authorizes release work. A feature-branch
checkpoint can preserve the verified source while exact Staging build and
installed-app verification remain pending; do not infer native delivery from a
source push or from an API deploy.

## Authorized release follow-up

The user requested `push/deploy` after reviewing the source-verification result.
Fresh `origin/main` remains `1cf755e`; only the intended publishing changes are
being prepared. Native release verification is a gate before merging to main.

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
- The current live API is `fc457b2` / `dep-dba64iqjnfac73egt8i0` in the previously
  confirmed My Workspace. Unlike the motion feature itself, main's earlier
  `ce501d4` YouTube-title follow-up includes a backward-compatible post-route
  change absent from Live. Release will incorporate that already-reviewed change
  after checks pass. There is no schema, dependency or environment-variable diff.
- Pre-deploy `/health` and `/ready` return 200 with database/queue ok; unauthenticated
  posts and publishing-readiness reads return 401. No provider post, purchase,
  user-data change or Production deployment is part of the checks.

CI, APK inspection, native update/smoke, final main/push and Render outcomes are
pending and must be recorded from actual results before delivery is claimed.
