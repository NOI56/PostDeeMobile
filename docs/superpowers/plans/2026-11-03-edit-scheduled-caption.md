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

## Verification record

Verification is in progress; pending checks are not passes.

- Workspace Flutter SDK: `D:\PostDeeMobile\.tools\flutter\bin\flutter.bat`.
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
- Full API and Flutter suites and exact-commit CI are still running/pending.
  The first local API attempt hit a cold Sentry SDK timeout; Sentry 14/14 and
  app 18/18 passed in isolation, and the complete suite is being rerun with
  one worker and a temporary diagnostic reporter. No Sentry source/test change.
- C: filled during Flutter compilation. Only this session's generated Mobile
  build, API dependencies and pinned Node runtime were moved to
  `D:\PostDeeCaptionScratch\20261103-edit-scheduled-caption` with junctions;
  TEMP/TMP use `D:\PostDeeCaptionTestTemp`. Existing work was not deleted.
- Final diff review excludes Windows generated files, scratch/cache files,
  environment/feature-flag changes and schema/migration edits.

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
