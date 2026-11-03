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

## YouTube title follow-up (2026-11-04)

The owner requested this correction on the same branch/worktree through
`artifacts/codex-briefs/2026-11-03-pr58-youtube-title-fix.md`. The clean PR head
and remote branch were both `e378ec5df90a35f569ac9a8165c5977bdc1af7f4`;
freshly fetched `origin/main` remained `9c05fa8e`, merge base unchanged,
ahead/behind `2/0` against main and `0/0` against the remote feature branch.

The composer resolves automatic titles before submission, so a nonempty saved
title does not establish that the seller chose a custom title. Treating every
stored title as custom kept old prices/text in the title after a caption edit.
The editor now compares the trimmed saved title with the same
`safeYouTubeTitleSuggestion` used by `PlatformPublishSettings.resolvedForCaption`,
using the loaded post's effective YouTube caption (override if present,
otherwise shared). An absent or matching title starts automatic mode; a
different title starts custom mode. The initial dirty-state flag uses this
same classification, so opening and immediately leaving does not ask to discard.

Automatic title preview and the submitted `youtubeTitle` follow edits to the
shared caption or the YouTube override. Editing only another platform's text
does not change that title. Custom-title and reset controls retain their behavior.
The shared helper preserves composer normalization: first usable line/sentence,
angle-bracket removal, whitespace normalization, 100 Unicode code points and
final trim, matching the server's stored caption/title trimming.

Accepted limitation: an intentionally custom title identical to the generated
title cannot be distinguished without a stored mode flag. It is treated as
automatic; its initial text is identical, but it follows later caption edits.
No API contract, route, store, worker, schema, migration or new flag is changed.
`ARCHITECTURE.md` was checked and needs no structural change.

Follow-up checks and evidence:

- Tests-first: 86 Thai/English editor cases ran before the production patch;
  74 passed and 12 failed on automatic-mode/preview/override behavior. Evidence:
  `D:\PostDeeCaptionTestTemp\pr58-title-red.log`.
- Added 18 Thai/English cases generated with the actual composer's
  `PlatformPublishSettings.resolvedForCaption`, covering shared price edits,
  server trimming/whitespace, the 100-code-point boundary and final trim,
  removed angle brackets, YouTube overrides independently of TikTok edits,
  distinct custom titles, untouched back navigation and customize/reset.
- An older custom/reset fixture had a title identical to its caption. It now
  uses a distinct custom title so that it continues testing the custom case;
  matching titles have dedicated automatic-mode coverage.
- Targeted 5 files / 139 tests passed, including the existing API-client,
  composer settings and platform-contract tests. Analyze passed with no issues.
  Logs: `pr58-title-targeted.log` and `pr58-title-analyze.log` in the directory above.
- The full Mobile suite uses the workspace Flutter 3.44.1 / Dart 3.12.1 SDK,
  `test --no-pub --concurrency=4 --reporter expanded`, after freezing source.
  Its execution log is `D:\PostDeeCaptionTestTemp\pr58-title-full.log`.
  Final local counts and the exact-head Backend API/Flutter Mobile CI results
  are published in [Draft PR #58](https://github.com/NOI56/PostDeeMobile/pull/58)
  and [its checks](https://github.com/NOI56/PostDeeMobile/pull/58/checks).
- API and DB suites are not rerun locally for this Mobile-only correction, as
  requested. Their source is unchanged; Backend API CI still checks the new head.
- Diff review against `e378ec5d` is limited to the editor, tests and directly
  related behavior documentation. No Windows generated files or configuration
  changes are included. The original architecture and rollout order are unchanged.

No merge, deploy, app installation or real posting is authorized. The earlier
APK build below predates this title correction and is not current device
acceptance. After authorized merge/deployment, use a new guarded update and
prove an edited scheduled YouTube post's actual title as well as its caption.

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
A missing YouTube title, or a stored title matching the composer's suggestion
from the saved effective YouTube caption, starts automatic mode and follows
caption edits. A distinct custom title is preserved. Resetting or clearing it
uses the same suggestion. The post contract stores only the resolved title;
the matching-custom-title limitation is documented in the follow-up above.

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

The initial feature and title-follow-up scope kept the PR in Draft and did not
authorize merge, deployment or installation. No new migration is required;
deploy API before compatible Mobile and retain `[skip render]` on main commits.
The owner subsequently authorized merge, Staging deployment and installation;
that separate delivery phase is recorded below. Real-account publishing still
requires the approved accounts and modes from `postdee-publish-e2e`.

## Owner-authorized Staging delivery — 2026-11-04

The owner authorized merge/deploy/install and explicitly selected Render
My Workspace. The same worktree was retained for source changes and the build;
root and other worktree sources were preserved. The shared workspace SDK and
the helper's existing ignored Test Store overlay resolution were reused without
printing or copying configuration/signing files. Fresh `origin/main`
was `f4715b754d8704679c8a6289e42dfb3c1303819b`, with the premium storefront
work already integrated. Only README/ROADMAP section conflicts needed resolution;
both feature histories were retained. Combined head `32b38cb3` preserved
catalog 5 (160 themes, including 20 premium), membership, TikTok consent,
Facebook Page Reels and retired-feature boundaries without flag/schema changes.

- [Combined-head CI 41690204459](https://github.com/NOI56/PostDeeMobile/actions/runs/41690204459)
  passed API 3,757 / 80 opt-in skipped and Mobile 5,208 / 10 optional skipped.
- PR #58 was merged as `2893dabd62731b69418ae70265fd2c24e0f7e58e` with
  `[skip render]`. Its entire tree equals tested head `32b38cb3`, tree ID
  `af18d6803fe3c28998f706641bcea243b94ce013`.
- [Exact-main CI 41692387613](https://github.com/NOI56/PostDeeMobile/actions/runs/41692387613)
  passed Backend API and Flutter Mobile before the Staging deploy.
- Local full API passed 3,757 / 80 skipped with default timeouts and one worker
  after an initial adminRefresh timeout; that suite passed 33/33 in isolation.
  Typecheck, build, Prisma validate, seed/config tsc, catalog and 152 artwork
  checks passed. No test or timeout setting was changed to obtain the final pass.
- Local combined Mobile passed 2,652 / 6 skipped before paging-file/OOM failure.
  This interrupted run is not a full-suite pass; the exact-source CI provides
  complete coverage as permitted by the brief. CI uses Flutter 3.47.9; local
  build uses workspace Flutter 3.44.1 / Dart 3.12.1.
- Dedicated PostgreSQL post claim/caption and theme membership suites passed
  8/8 with the original default timeout after a warm retry. The fixture retained
  30 migrations, was stopped and no longer answered on port 55441. No regular
  or Render database was used for these tests.
- Built Staging APK 12100 from clean exact merge SHA `2893dabd`, package
  `com.postdee.postdee_mobile.staging`, matching the existing installed signer.
  The first build failed in Java-resource packaging after the process-only
  memory cap omitted the existing en/US locale flags. Restoring those flags
  passed without source, helper or global-cache changes.
- Staging deploy `dep-dbl2grtbedkc73etcei0` is Live at exact `2893dabd`;
  health/readiness, database/queue, auth guards and migration/error-log checks
  passed. APK 12100 was installed through the guarded updater after API health
  verification. UID 10197/internal storage stayed unchanged, installed APK hash
  matched and all 78 persisted-file hashes matched before launch.
- Native retained the STAGING Basic session and saved draft, loaded old posts,
  hid caption editing on a published post and refreshed the calendar. No eligible
  queued post exists, so positive native editing and real delivery remain
  unverified. A first-screen Android system ANR cleared with Wait once and did
  not recur during checks; 2,110 app-log lines contained no fatal/Flutter error
  or overflow. No post was created/saved/published and no purchase was attempted.
- Automatic iOS workflow could not acquire a macOS runner and ended before any
  compile/test step; it provides no iOS acceptance. Android/API CI passed.

Deploy ID/times, health/log checks, APK hash and guarded-update/native evidence
are recorded in [docs/STAGING.md](../../STAGING.md). No production delivery or
real social post is claimed. A saved custom title identical to the automatic
suggestion retains the accepted automatic-mode ambiguity.

Rollback must retain the new persisted legacy-YouTube settings reader, the
latest-caption-after-claim worker and catalog-5 reader once edited posts or
new designs exist. No migration does not make every older reader compatible;
never clear saved posts or designs to roll back.
