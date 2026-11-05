# App-language pushes and automatic caption fallback

Date: 2026-11-05. Status: local candidate for Claude Code review; no push, PR,
merge, deployment, installation or real provider call is authorized here.

## Baseline and workspace

- Fetched `origin`; canonical branch is `main`.
- Exact base: `e4004355a6cf9a3c5c18a47f2f14b1234569d6b8` (`origin/main`).
- Branch: `codex/multi-country-push-caption-language`.
- Worktree: `C:/Users/stopp/.codex/tmp/multi-country-push-caption-language-20261105/source`.
- Initial worktree was clean, merge base equaled the base above, ahead/behind
  was `0/0`. The original `D:/PostDeeMobile` checkout was 38 commits behind
  main with unrelated dirty files; none were ported or modified. The separate
  `multi-country-docs` checkout was not modified.
- The managed worktree creation tool stalled after checkout. Git created the
  working branch in the separate path above. The unused managed checkout later
  registered at `C:/Users/stopp/.codex/worktrees/multi-country-push-caption-language/PostDeeMobile`;
  its archive request was refused because the app treats it as the primary
  checkout. It remains an untouched detached baseline, not the review branch.
- C: filled during the first npm install. Only this task's generated dependencies,
  PostgreSQL fixture and build output were moved to
  `D:/codex/2026-11-05/multi-country-push-caption-language-runtime`, with local
  ignored junctions where needed. No dependency/lockfile or application
  configuration change was made. Subsequent test temporary files use that D:
  scratch directory. No unrelated files were deleted.

## Behavior and compatibility

The API previously stored no device language and sent Thai copy to every
device. The clip-caption provider also used Thai as Automatic's final fallback.

- Optional device `language` and clip-caption `appLanguage` share normalization:
  strip region tags, retain `th`/`en`, unsupported → `en`, missing/null → legacy.
- Nullable `DeviceToken.language` is stored by memory and Prisma repositories.
  Re-registration updates language; omission clears it to null for old clients.
  There is no backfill. Owner scope, the ten-token limit, unregister and account
  deletion cascade are retained.
- All three notifiers group an owner's tokens into English and Thai (`th`/null).
  Publish texts exactly match the existing English Mobile texts. Support copy
  is generic and contains no chat content or customer identity. Data payloads
  retain their original keys. Each group's send and dead-token cleanup settle
  independently; token lookup/send/cleanup failures remain best-effort.
- Mobile sends app language with registration, observes language switches, and
  refreshes only an existing registration bound to the current signed-in session.
  Existing serialized synchronization, token rotation and late-session cleanup
  remain in use. A late metadata write reasserts the latest language when a
  current registration still exists. A language switch does not request push
  permission or initialize a missing/failed registration.
- Known publish (three outcomes) and support-reply templates map Thai ↔ English
  in the in-app list. Unknown copy, receipt identity and payloads are unchanged.
- Every Mobile generate-from-clip HTTP request sends app language, including
  Automatic and explicit caption output choices. Automatic keeps speech → main
  on-screen text → seller guidance priority and uses app language only last.
  Missing/Thai app language produces the exact old Thai prompt. Explicit output
  language still wins. Grounding, per-channel captions, response shape, the
  109-language catalog, credit cost/reservation/refunds are unchanged.
- Confirmed `PostDeeApiClient.generateCaption` has no caller in Mobile `lib/`;
  uploader callbacks with a similar name are clip-caption callbacks. The keyword
  caption endpoint/provider remains unchanged, including legacy Thai prompts.
- No new environment variable, feature flag, dependency, UI language, quota
  window, entitlement, legal text, admin-console change or retired feature.

## Migration and rollout

Migration: `20261105010000_device_token_language`:
`ALTER TABLE "DeviceToken" ADD COLUMN "language" TEXT;`.

Order: migration and API first, then Mobile. Existing clients omit both fields
and retain Thai pushes and the exact Thai caption fallback. Do not ship Mobile
before this API if it must provide the new behavior.

PostgreSQL 18 fixture listens only on `127.0.0.1:55439`. Repository tests use
`postdee_admin_fixture` with `ADMIN_TEST_DATABASE_URL` and an explicit host,
port and database guard. Upgrade proof uses a separate disposable database
`postdee_language_upgrade_fixture` in the same owned cluster. No 5432 or Render
database was accessed.

The exact baseline's 30 migrations were extracted with `git archive` and
applied with `prisma migrate deploy`. A User and DeviceToken were inserted
before the new migration. Deploy then applied migration 31; SQL assertions
confirmed all 31 migrations and the retained legacy token/platform with null
language. The Prisma repository save/read/update, old-client null and cascade
tests also passed. `prisma migrate status` confirmed the schema up to date;
the owned cluster was stopped afterward and retained only as a local fixture.

## Verification

All logs below are under
`D:/codex/2026-11-05/multi-country-push-caption-language-runtime/logs/`
unless otherwise stated. Node `22.23.3`, Prisma `6.19.3`, and the workspace
Flutter 3.44.1 / Dart 3.12.1 from the workspace SDK
`D:/PostDeeMobile/.tools/flutter/bin/flutter.bat` were used (`flutter-version.log`).

Tests were added before implementation. Caption red run: 5 failed / 4 passed;
push red run: 14 failed / 20 passed (the notifier patch was still absent).
Mobile red run recorded the expected missing language API/compiler errors and
was stopped when it stalled. Earlier dependency/space and intermediate test
failures are retained in logs; the final verification below is authoritative.

| Check | Result | Log |
| --- | --- | --- |
| Caption targeted | 5 files, 286 tests passed | `caption-language-targeted.log` |
| Push/device targeted | 8 files, 56 tests passed | `push-targeted.log` |
| Prisma repository opt-in | 1 file, 2 tests passed | `device-language-database.log` |
| API full `npm.cmd run test -- --maxWorkers=2` | 211 files passed, 16 skipped; 4,086 tests passed, 82 skipped (130.51s) | `api-test-full-final.log` |
| API build | Passed | `api-build.log` |
| API typecheck | Passed | `api-typecheck.log` |
| Prisma generate / validate | Passed | `prisma-generate.log`, `prisma-validate.log` |
| Prisma seed/config tsc | Passed | `prisma-helper-typecheck.log` |
| Baseline 30 → migration 31 | Passed; legacy row retained and language null | `prisma-migrate-baseline-30.log`, `migration-legacy-before.log`, `prisma-migrate-upgrade-31.log`, `migration-legacy-after.log` |
| Mobile targeted | 5 files, 176 tests passed | `mobile-targeted-final.log` |
| Flutter analyze `--no-pub` | Passed; no issues (14.4s) | `flutter-analyze.log` |
| Flutter full tests `--no-pub --concurrency=2 --reporter expanded` | 5,583 tests passed, 10 optional skips; exit 0 (12m04s) | `flutter-test-full.log` |

The first API full run (`api-test-full.log`) had 4,085 passed, 82 skipped and
one timeout in the unchanged 100-platform image/hash test (15-second limit).
Repeating the complete suite with two workers passed all 4,086 tests without
source changes. The default API run skips opt-in DB suites; the two affected
device-language DB tests were explicitly executed above. Other opt-in database
suites were not enabled. Both the first successful repeat
(`api-test-full-workers2.log`) and the final full run after the Mobile lint fix
(`api-test-full-final.log`) passed with identical counts.

The first Mobile analyze found two new lint infos (explicit braces and a
BuildContext mounted guard); both were fixed. The simultaneous initial Mobile
full run was stopped, and analyze/full tests restarted after that final source
edit. `flutter-analyze-before-fix.log` and
`flutter-test-full-before-lint-fix.log` preserve those intermediate results;
they are not claimed as passes. Final Mobile commands use `--no-pub` to avoid
regenerating unrelated Windows plugin files, and full tests use `--concurrency=2`.

All source checks run after the final relevant source edit. The API is built
locally; HTTP regression tests use mock auth/providers and known fixture
entitlements, not an installed app or hosted environment. Mobile tests use fake
Firebase messaging and local HTTP fixtures; no APK or Firebase deployment was
created. Android package/flavors, API URL/Firebase configuration, feature flags,
billing and publishing configuration are unchanged. Real-device/iOS lock-screen
delivery, live Gemini caption quality, hosted migrations and old installed-build
acceptance remain unverified and belong to a later authorized rollout.

## Changed files

API:

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20261105010000_device_token_language/migration.sql`
- `apps/api/src/modules/shared/appLanguage.ts`
- `apps/api/src/modules/shared/appLanguage.test.ts`
- `apps/api/src/modules/devices/deviceRoutes.ts`
- `apps/api/src/modules/devices/deviceTokenStore.ts`
- `apps/api/src/modules/devices/prismaDeviceTokenRepository.ts`
- `apps/api/src/modules/devices/deviceLanguage.test.ts`
- `apps/api/src/modules/devices/deviceTokenLanguage.database.test.ts`
- `apps/api/src/modules/notifications/localizedPush.ts`
- `apps/api/src/modules/notifications/publishNotifier.ts`
- `apps/api/src/modules/notifications/supportReplyNotifier.ts`
- `apps/api/src/modules/notifications/supportTeamNotifier.ts`
- `apps/api/src/modules/notifications/notificationLanguage.test.ts`
- `apps/api/src/modules/captions/captionService.ts`
- `apps/api/src/modules/captions/realClipCaptionProvider.ts`
- `apps/api/src/modules/captions/captionAppLanguage.test.ts`

Mobile:

- `apps/mobile/lib/core/network/postdee_api_client.dart`
- `apps/mobile/lib/features/notifications/firebase_push_messaging_gateway.dart`
- `apps/mobile/lib/features/notifications/push_messaging_gateway.dart`
- `apps/mobile/lib/features/notifications/notifications_screen.dart`
- `apps/mobile/lib/features/shell/postdee_shell.dart`
- `apps/mobile/lib/features/uploader/uploader_screen.dart`
- `apps/mobile/test/multi_country_language_api_test.dart`
- `apps/mobile/test/notifications_message_copy_test.dart`
- `apps/mobile/test/postdee_shell_test.dart`
- `apps/mobile/test/push_messaging_test.dart`
- `apps/mobile/test/uploader_caption_language_test.dart`

Docs: `API.md`, `ARCHITECTURE.md`, `README.md`, `ROADMAP.md` (Global Readiness
Plan), `apps/mobile/README.md`, and this record. Generated Windows plugin changes
from Flutter dependency resolution are excluded. Final staged diff review:
34 files (17 API, 11 Mobile, 6 docs), no deletions, unrelated rewrites,
dependency/config/flag changes or lost routes/assets. `git diff --cached --check`
passed and there were no unstaged edits. A second fetch still resolved
`origin/main` to the exact base above. The original checkout's status matched
its initial dirty/untracked list (`original-checkout-status.log`). Stop at the
local commit with an English message ending in `[skip render]`; Claude Code
reviews before any integration or rollout.
