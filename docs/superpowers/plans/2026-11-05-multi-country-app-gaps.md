# Multi-country app gaps (2026-11-05, local review candidate)

## Baseline and scope

- Fresh `git fetch origin`; canonical integration branch: `origin/main`.
- Exact base: `8a340638630fcb960490ee23e95c271870b42a82`.
- Worktree: `C:\Users\stopp\.codex\worktrees\multi-country-app-gaps\PostDeeMobile`.
- Branch: `codex/multi-country-app-gaps`; started clean, merge base equals base,
  ahead/behind `0/0`. The original dirty checkout and pending
  `claude/multi-country-docs` checkout are excluded from source edits.
- The owner decided that PostDee serves multiple countries, with Thailand the
  first market. This patch handles only the three requested app gaps.
- Root docs are deliberately unchanged: the pending docs branch and reviewer
  will synchronize AGENTS.md, CLAUDE.md, README.md, ROADMAP.md, ARCHITECTURE.md
  and API.md after review. This record is the requested temporary contract record.

## Behavior and decisions

### App language

- Added a small language preference-store interface and SharedPreferences adapter,
  following the theme controller pattern. The new device-local key is
  `postdee_language`, containing `th` or `en`.
- Real app startup awaits `loadSavedLocale()` before Firebase initialization and
  `runApp`: a saved supported choice wins; otherwise the first Thai/English entry
  in the phone's preferred-language list wins; otherwise English is used.
- Region variants are normalized to Thai/English. Unsupported or malformed stored
  values behave as no saved choice. A failed read also follows the phone fallback.
- Explicit selection persists even if it matches the detected language. Writes
  are serialized so rapid switches keep the latest choice. Read/write failures
  do not escape the controller; a failed write leaves the session language active,
  although a later launch may have to detect it again.
- A late load cannot overwrite a newer explicit selection. Notifications remain
  synchronous; no app/shell keys, routes, controllers or draft stores are replaced.
- The constructor's pre-bootstrap Thai fallback remains for existing callers;
  production startup always resolves the saved/device language before showing UI.
  The picker remains Thai/English and `supportedLocales` is unchanged.

### Country-neutral pricing copy

- Scheduling says a paid plan (Starter or higher) is required, in Thai/English,
  without amounts, currency or advertising Business.
- The top-up card says the user pays the price shown by their store, in both
  languages. Its purchase button still displays loaded store product metadata.
- Internal `priceThb`, legacy product IDs, SKU matching, credit/entitlement logic
  and the Business sales switch remain unchanged.
- `AiToolsScreen` (`lib/features/ai/ai_tools_screen.dart`) and
  `CaptionAssistantScreen` (`lib/features/captions/caption_assistant_screen.dart`)
  still contain old prices. Searching all `lib/` imports, class references and
  routes found only their own declarations/constructors, with no entry points.
  They are left unchanged as explicitly requested.

### Public store page

- `GET /p/:slug` negotiates Thai/English using Express's existing
  `acceptsLanguages('en', 'th')`, respecting q-values, regional tags and excluded
  (`q=0`) languages. Missing/unsupported headers and an unconstrained wildcard
  default to English; equal explicit preferences follow header order.
- `renderLinkInBioPage(profile, nonce, language = 'en')` keeps existing callers
  source-compatible and localizes only HTML `lang`, the default description,
  footer, link CTA and cover/logo alt text. Both invalid and missing/unpublished
  page 404 messages are localized.
- `Vary: Accept-Language` is added before page lookup. `Cache-Control: no-store`
  and the existing CSP/nonce remain. Owner text is escaped as before and is never
  translated or written back, even if it matches the old default description.
- Themes, templates/catalog releases, membership fallback, artwork/fonts, link
  destinations and Thai avatar-initial handling remain intact. The Flutter
  decorated preview is unchanged.

## Compatibility and rollout

- No schema, migrations, dependencies, environment variables or feature flags
  change. No stored server data or owner content is rewritten. No database rollout
  is needed; the preference key is additive and device-local.
- API and Mobile changes can ship independently; use API first, then Mobile for
  the normal rollout sequence after review. This task only creates a local commit
  with `[skip render]`; no push, PR, merge, deploy or app installation is authorized.
- Monthly quota windows, phone examples, legal docs, additional UI languages,
  admin console and all retired features are outside scope and unchanged.

## Verification

- Runtime: Node `22.23.3` / npm `10.9.9`; workspace Flutter `3.44.1` / Dart `3.12.1`.
  Dependencies installed from existing lockfiles, with no lockfile changes. The
  first npm install used system npm/Node 24 despite PATH; all API verification
  uses the pinned Node 22 bundle. Prisma client generated locally from the
  unchanged schema; no migration or hosted database access.
- Tests were added before source patches. Old pricing: **0 pass / 4 fail** on the
  new Thai/English regressions. Old language controller: compilation fails for
  the new preference APIs. Old public page: **3 pass / 22 fail** on the new suite.
- API targeted: **83 pass** across the 3 changed/new suites; all Link-in-Bio suites:
  **1,137 pass / 5 skipped**, 24 suites pass / 2 opt-in DB suites skipped.
- API full `npm.cmd run test -- --maxWorkers=2`: **4,022 pass / 80 skipped**
  (4,102 total), **207 suites pass / 15 skipped** (222 total). The 15 skipped
  suites are the existing opt-in PostgreSQL suites; no fixture database was
  started. Worker count is limited for available memory; no suites are filtered.
- `npm.cmd run build`, `npm.cmd run typecheck`, `npm.cmd run prisma:validate`
  and the AGENTS.md TypeScript check for `prisma/seed.ts` / `prisma.config.ts` all
  pass. Schema validation uses the documented localhost placeholder URL without
  connecting to a database.
- Compiled API smoke (`dist`, four local HTTP requests) passes: default English,
  Thai region, weighted q-values and English 404, with owner content, Vary,
  no-store and matching CSP nonce verified.
- Flutter analyze: **no issues**.
- Mobile targeted: **411 pass / 0 fail**, 13 files, using
  `flutter test --no-pub --concurrency=1 --reporter expanded` with
  `language_controller_test`, `post_schedule_policy_test`, `paywall_english_test`,
  `calendar_screen_test`, `review_localizations_test`,
  `uploader_schedule_english_test`, `uploader_screen_test`, `app_test`,
  `postdee_shell_test`, `profile_english_test`, `onboarding_flow_english_test`,
  `login_flow_english_test` and `uploader_calendar_schedule_test`. Includes Thai/
  English, light/dark and small-phone paywall coverage, and live-switch form/draft
  preservation. New language suite: **18 pass**; new price regressions: **4 pass**.
- Full Mobile `flutter test --no-pub --concurrency=1 --reporter expanded`:
  **5,291 pass / 10 skipped / 0 fail**, 5,301 total across 298 test files, completed
  in **17 minutes 14 seconds** without a memory failure. The 10 skipped tests are
  the existing optional image-preview exports gated by output-directory variables;
  none of the new regressions is skipped.
- Final staged diff checked against the exact base: 18 intended files, no deleted
  files, unrelated rewrites, root-doc edits, dependency/schema/config/feature-flag
  changes, or missing capability wiring. `git diff --cached --check` passes.
  The original checkout still has HEAD `f4715b754d8704679c8a6289e42dfb3c1303819b`
  and the same two tracked generated Windows-file changes present at task start.

## Changed-file inventory

All paths below are relative to this worktree; 18 files total.

| Area | Files |
| --- | --- |
| API implementation | `apps/api/src/modules/linkInBio/linkInBioRenderer.ts`, `linkInBioRoutes.ts`, new `linkInBioLocalizations.ts` in the same directory |
| API tests | `apps/api/src/modules/linkInBio/linkInBioRoutes.test.ts`, `linkInBioThemes.test.ts`, new `linkInBioLocalization.test.ts` in the same directory |
| Mobile implementation | `apps/mobile/lib/core/localization/language_controller.dart`, `apps/mobile/lib/main.dart`, `apps/mobile/lib/features/shared/post_schedule_policy.dart`, `apps/mobile/lib/features/billing/paywall_screen.dart` |
| Mobile tests | New `apps/mobile/test/language_controller_test.dart`; `post_schedule_policy_test.dart`, `paywall_english_test.dart`, `calendar_screen_test.dart`, `review_localizations_test.dart`, `uploader_schedule_english_test.dart`, `uploader_screen_test.dart` in `apps/mobile/test/` |
| Work record | `docs/superpowers/plans/2026-11-05-multi-country-app-gaps.md` |

## Environment and limits

- Verification uses local memory/mock API fixtures and Flutter widget tests,
  including store-price fixtures in non-Thai currencies and language-switch
  preservation of forms/drafts. Production services and real store purchases are
  not exercised. Default local Mobile API is `http://localhost:4000`, Firebase and
  RevenueCat are disabled unless tests explicitly inject fakes; no Staging defines
  or installed app are used or changed.
- No APK/device/store build is produced in this task. Real device restart and
  hosted public-page language checks remain follow-up checks after review.
- Generated Windows Flutter registrant changes from `pub get` are excluded from
  the commit. Generated Mobile build output is redirected via a local junction to
  `E:\codex-task-artifacts\2026-11-05-multi-country-app-gaps\mobile-build` to avoid
  filling the C: drive. Verification logs are in that artifact directory.
