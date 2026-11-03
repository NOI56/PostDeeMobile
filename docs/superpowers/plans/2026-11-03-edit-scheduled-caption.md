# Edit scheduled post caption — 2026-11-03

## Scope and baseline

- Owner-approved brief: `artifacts/codex-briefs/2026-11-03-edit-scheduled-caption.md`.
- Latest `origin/main` fetched and verified against the remote at
  `9c05fa8ea3e36f149da97a2be69148d3066dfca8` on 2026-11-03 (Asia/Bangkok).
- New managed worktree:
  `C:\Users\stopp\.codex\worktrees\edit-scheduled-caption\PostDeeMobile`.
  Branch `codex/edit-scheduled-caption`, initial merge base equals baseline,
  ahead/behind `0/0`, initially clean.
- Root checkout `D:\PostDeeMobile` and its uncommitted
  `codex/store-premium-themes` work are preserved. No merge, deployment or app
  installation is authorized. A feature-branch push and Draft PR are authorized.

## Required preserved capabilities

Existing rescheduling, publish-now/cancel, old Mobile clients, accepted-post
quota accounting, manual/AI caption separation, per-platform settings and target
snapshots, video/cover ownership, owner locks, TikTok preparation/consent,
Facebook Page Reels (`facebook` + `contentType: reel` with existing modes),
delivery results, retries and interrupted-publish recovery must remain intact.
Retired features stay retired. No billing/feature-switch or schema change.

## Implementation

The additive route is `PATCH /posts/:id/caption`, accepting shared `caption`,
optional `platformCaptions` (null removes an override), optional `youtubeTitle`
and optional `expectedUpdatedAt`. It returns the public post. Public posts add
optional `updatedAt`; repository writes always compare the loaded version,
owner, queued status and scheduled time. Stable conflicts distinguish an
uneditable post, the closed 60-second window and a stale version/race. Existing
caption validators remain authoritative. Manual editing spends no credits or
post units and needs no new plan admission check.

The shared publish worker loads the authoritative caption/settings after claim,
closing both the BullMQ stale-job-data path and the memory poll/claim gap. A
claimed post cannot be edited. Missing owned claimed data fails closed.
Legacy YouTube title edits retain old settings without inventing consent;
strict new-post consent requirements remain in force. The persisted-only parser
accepts an edited legacy private title, and the publisher tests for the actual
certification fields before forwarding consent. Shared-caption-only edits keep
absent legacy settings absent; a legacy override/title edit materializes the
existing controlled defaults, preserving effective privacy/mode. Unknown
settings were already rejected by the baseline parser; that contract is unchanged.

Prisma locks the owned queued post row before checking the clock, then performs
the revision/schedule CAS in the same transaction. This also rejects an edit
that waited on another transaction until the 60-second window closed. PostgreSQL
serialization/deadlock errors from the raw lock map to a caption conflict.

Mobile uses a dedicated editor, existing platform-caption fields and validators,
shared/per-channel initialization, YouTube automatic/custom title behavior,
loading/errors/retry, discard confirmation and owner/session result guards.
Details and calendar reads show effective updated captions. All new copy has
Thai and English, with small-screen and theme coverage.
An already stored YouTube title is preserved as explicit; an absent title starts
in automatic mode. Resetting or clearing a custom title uses the composer's
existing caption-derived suggestion. The post contract stores the resolved
title, without inventing a persisted automatic/custom flag.

## Verification record

Automated feature verification passed for source commit
`493a5fad287c16fce90d59ce41ddf472def0685a`.

- Workspace Flutter SDK: `D:\PostDeeMobile\.tools\flutter\bin\flutter.bat`,
  Flutter 3.44.1 / Dart 3.12.1.
- API checks use the pinned Node `22.23.3`; the machine default is Node 24.
- Dedicated disposable PostgreSQL fixture:
  `127.0.0.1:55441/postdee_addon_test`, user `postdee_fixture`; all 30 baseline
  migrations applied. Neither the regular 5432 database nor Render is used.
- Tests-first failures confirmed the missing route/store method, stale queue
  content, legacy YouTube title handling, a locked-out account-change back
  action and caption-derived YouTube title reset before their corresponding fixes.
- API targeted: 6 files / 245 tests passed. Worker/publisher regression:
  9 files / 250 tests passed (overlapping existing coverage).
- Real PostgreSQL: 7 dedicated-fixture files / 25 tests passed / 0 skipped,
  including 6 post-claim/caption tests, add-on transactions/migration,
  Business subscription/migration, slug reservation and theme membership.
- Other opt-in database groups (ADMIN, SOCIAL_LINKING, ADDON_DB and
  CAPTION_BATCH) were not enabled; their databases are unrelated to this change.
- API typecheck, build, Prisma validate and seed/config tsc passed. Profile
  catalog parity and 89 generator/artwork tests passed; production dependency
  audit passed its high-severity threshold (existing moderate advisories remain).
- Mobile final targeted Thai/English/client tests: 71 passed, including empty
  per-channel validation and clearing a custom YouTube title back to the
  caption-derived fallback. Final analyze passed with no issues.
- Final full API: `npm.cmd run test -- --maxWorkers=1`, 203 files / 3,662 tests
  passed, 15 files / 80 opt-in tests skipped, 287.41 seconds. No timeout change.
  Earlier cold/concurrent runs hit Sentry SDK/process and generator timeouts;
  isolated checks and the final entire run passed without modifying those tests.
- Final full Mobile: `flutter test --no-pub --concurrency=4 --reporter expanded`,
  5,117 tests passed / 10 optional tests skipped, 11 minutes 29 seconds. An earlier
  full run was invalidated by a source edit while running; it was discarded and
  replaced with this full run after freezing the source.
- Exact-source [CI run 41672201696](https://github.com/NOI56/PostDeeMobile/actions/runs/41672201696)
  passed both Backend API and Flutter Mobile, with the same full-suite counts.
  The final documentation commit's checks are visible in
  [Draft PR #58](https://github.com/NOI56/PostDeeMobile/pull/58/checks).
- C: filled during Flutter compilation. Only this session's generated Mobile
  build, API dependencies and pinned Node runtime were moved to
  `D:\PostDeeCaptionScratch\20261103-edit-scheduled-caption` with junctions;
  TEMP/TMP use `D:\PostDeeCaptionTestTemp`. Existing work was not deleted.
- Final diff review excludes Windows generated files, scratch/cache files,
  environment/feature-flag changes and schema/migration edits.
- The isolated PostgreSQL fixture was stopped and retained under
  `D:\PostDeeCaptionScratch\20261103-edit-scheduled-caption\pg55441`;
  `pg_isready` confirms port 55441 is closed. No existing database was changed.
- Final remote freshness check still found `origin/main` at `9c05fa8e`.
  Root remains on `codex/store-premium-themes` with its separate work; none
  of that work is included in this feature branch.

Additional build-only Staging verification was requested for the exact feature
source in [CI run 41673269143](https://github.com/NOI56/PostDeeMobile/actions/runs/41673269143).
Its job and receipt report the build outcome, package identity and artifact hash.
The build uses the existing Test Store secret, not a new configuration or live
purchase. Intended identity is `com.postdee.postdee_mobile.staging`, API
`https://postdee-api-staging.onrender.com`, Firebase project
`project-798caf7e-85b8-45e3-af7`, Firebase auth enabled and local mock auth disabled.
No native account/entitlement acceptance or device installation is claimed.

Changed source is limited to API post routes/stores/settings and the shared
publish worker/publisher; Mobile post DTO/client, caption editor/localizations,
post details, calendar preview and the reused caption-field platform filter.
Regression tests accompany these changes. Product docs are synchronized in
`API.md`, `README.md`, `ROADMAP.md`, `ARCHITECTURE.md` and `apps/mobile/README.md`.

## Delivery limits

No new migration. Deploy API before compatible Mobile. Keep the PR in Draft
and include `[skip render]` in its commit/title so a later main merge cannot
accidentally trigger Production delivery. This task does not merge or deploy.
After separately authorized Staging deployment, verify a real scheduled post
delivers the edited text with `postdee-publish-e2e`, then use the guarded updater
from `postdee-android-build` for device acceptance. Those actions are pending
owner instruction; no device/account/entitlement acceptance is claimed here.
