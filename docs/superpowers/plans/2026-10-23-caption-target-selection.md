# Choose AI caption channels — 2026-10-23

## Request and baseline

The user wants advanced caption mode to generate only the channels they choose,
instead of always generating four variants. This avoids requesting unwanted
variants. Existing pricing is unchanged: a request for any set of 1–4 supported
channels consumes one AI credit, not one credit per channel and not a fractional
credit for smaller sets.

Implementation starts from verified fresh `origin/main`
`eee9e6ae1bdcbb4d465b9a243ee2aed7a93ca83c`, with HEAD/main at the same revision
(0 ahead/0 behind), on `codex/platform-captions` in
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`.
Preserve the three unrelated dirty generated Windows plugin files. The prior
four-caption feature and owner-transaction startup fix are already in this
baseline; its installed Staging APK is 12042. That prior release does not count
as delivery or verification of the new selector.

## Intended behavior

- Advanced mode still hides the main caption and shows all four manual editors:
  TikTok, YouTube Shorts, Instagram Reels and Facebook Page Video. The internal
  `FACEBOOK_REELS` key remains Page Video, not Facebook Reels support.
- AI targets start empty. Users choose 1–4 supported channels, with select-all
  and clear-selection actions, before explicitly requesting generation. Empty
  selection must make no AI request and consume no credit.
- Generation targets are independent of publishing destinations. Selecting or
  clearing an AI target does not choose/deselect a posting destination or erase
  any caption. Manual editing stays available for every supported channel.
- Send only selected API enum values to the existing real-clip endpoint. Require
  a valid result for every requested target, then preview only those captions.
  Dismissal leaves text intact. Apply merges selected results into current text;
  unselected captions are preserved. Undo restores selected pre-AI values and
  leaves unselected edits intact. Users can edit accepted captions afterward.
- Preserve existing account/clip ownership, asynchronous stale-result guards,
  effective-caption validation, review/submission and TikTok consent boundaries.
  Mode changes, changed targets and concurrent edits cannot apply stale results.
- Local drafts remember chosen targets alongside caption mode and all text,
  including after returning to shared mode or reopening the draft. Do not turn
  generation targets into reusable account/channel defaults.

## Contract, quota and persistence

The deployed `POST /captions/generate-from-clip` contract already accepts
`platforms`, 1–4 unique values from `TIKTOK`, `YOUTUBE_SHORTS`,
`INSTAGRAM_REELS` and `FACEBOOK_REELS`. The response's `platformCaptions` map
contains requested variants, while legacy shared result fields remain present.
This follow-up requires no API runtime or deployment change. Tests may expand
to cover subsets without altering server behavior.

One request/set reserves one monthly/add-on AI generation and uses the existing
provider operation, with existing transient retries. Selecting one, two or
three channels still costs one credit, just as selecting four does. No plan,
package, credit price, lifetime, consumption order or add-on rule changes.
Incomplete/malformed output retains the existing whole-request fallback and
refund path; `quota.charged` is false only when release succeeds, and failed
refunds remain charged. Existing owner, paid-plan, media and cleanup checks stay.

`PlatformPublishSettings.aiCaptionPlatforms` is a local `Set<SocialPlatform>`
with an empty default. `copyWith`, equality and hash include it. Its optional
draft JSON list uses only supported API enum values in stable order; historical
drafts without it default to empty. Malformed/unsupported target metadata is
rejected consistently with other draft settings. No draft version bump is
required. The field never enters `toApiJson` or `toRecoveryApiJson` and never
enters reusable account/channel preferences. Existing effective per-platform
caption overrides remain the only caption changes in publishing intent.

There is no new column, migration, dependency, environment variable, credential
or external integration. Shared-caption requests remain unchanged.

## Files

- Mobile uploader: generation target selector, request scope and selective
  preview/apply/undo integration.
- `platform_caption_fields.dart`: selector and requested-only preview UI.
- `platform_publish_settings.dart`: local target state and draft serialization.
- Mobile contract/draft/defaults, widget and uploader regression tests.
- API caption subset regression tests; backend runtime remains unchanged.
- `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md` and this work record.

## Verification

Model/draft tests were written first. The red proof failed compilation because
`aiCaptionPlatforms` did not exist. After the model patch:

- Contract, real file-draft store and reusable-default tests: **62 passed**.
- Analyze of the model and the two edited test files: **No issues found**.
- Scoped `git diff --check`: passed.

These checks verify stable set equality/order, mode retention, actual draft
round trips, legacy empty defaults, supported-only serialization, malformed
metadata rejection, unchanged post/recovery payloads and exclusion from
reusable preferences. Logs are in the ignored local artifact directory
`D:\PostDeeMobile\artifacts\caption-target-selection-20261023`:
`settings-tests-red.log`, `settings-tests-green.log` and `settings-analyze.log`.

Uploader regressions were also added before integration. The red proof failed
because the selector was absent. Existing four-caption cases now explicitly
choose all four targets, retaining their prior coverage. Final combined results:

- Full Mobile tests: **2,787 passed, 6 skipped**, exit 0; full Flutter analyze:
  **No issues found**.
- Uploader/submission regressions: **17 passed**. Default empty selection makes
  no upload/request; one/two target requests have stable exact platform lists;
  extra returned variants are ignored; missing requested output changes no text.
  Tests cover preview dismissal, stale selected edits/account/mode changes,
  unselected edits during generation, scoped undo, draft reopening, clip-change
  retention, partial-generation review gates and TikTok consent isolation.
- Standalone selector/preview tests: **11 passed**, including 1–4 result maps,
  select/remove/all/clear/disabled controls, fallback charge/refund copy and
  320px screens at 1.7 text scale.
- Same **28 widget regressions passed** through the validated Staging helper
  with Staging API/Firebase/monitoring defines. Responses and account/plan data
  were injected fixtures; this does not claim a real provider call or device
  test. Device builds additionally use the existing validated Test Store overlay.
- Full API on production-matching Node **22.23.3**: **2,504 passed, 25 skipped**
  across 150 passing/4 skipped suites. The selected-caption subset suite passed
  **168 tests**. Added single/two-channel tests assert selected-only output,
  one generation/reservation per request and one fallback refund without
  refunding earlier usage. Runtime API diff is empty.
- API typecheck/build, Prisma schema validation and separate Prisma helper
  typecheck: **passed**. No schema/migration changes or database writes.
- Exact-source Staging debug APK **12043** built successfully. Packaged ID is
  `com.postdee.postdee_mobile.staging`; packaged Firebase project is
  `project-798caf7e-85b8-45e3-af7`. The compiled kernel contains the intended
  Staging API, new selector/draft field and monitoring release
  `postdee-mobile@caption-target-selection+12043`. The validated helper preserves
  Firebase auth, disables local mock auth and uses the existing RevenueCat Test
  Store overlay. No credential or feature-flag changes were introduced; only
  the ignored local monitoring build label advances from 12042 to 12043.
- APK SHA-256:
  `d9953e089b8e2ae1c88b806edc7d4184614e6fac1b7ed0606bb66b7c92b778d4`
  (292,733,545 bytes). Build and package checks are recorded in
  `mobile-build.log` and `mobile-build-result.json` under the artifact directory.
- Final remote freshness check still reports HEAD and freshly fetched
  `origin/main` at `eee9e6ae1bdcbb4d465b9a243ee2aed7a93ca83c`, 0/0.
  Diff review and whitespace checks pass, with no deleted files, dependency,
  platform wiring, API runtime or feature-flag changes. The three unrelated
  generated Windows files remain excluded from this task.

Additional logs include `uploader-selection-red.log`,
`uploader-selection-tests.log`, `widget-tests.log`, `mobile-full-tests.log`,
`mobile-analyze.log`, `staging-widget-smoke.log`, `api-full-tests-node22.log`
and the API static-check logs in the same ignored artifact directory.
The new APK has **not** been installed: an ADB read still shows emulator
`emulator-5554` on **12042**, preserving its currently open app/data. New-device
selector/draft smoke and actual provider acceptance remain unverified.
No live AI request, credit consumption, purchase or post was performed.

## Release boundary and remaining limits

The implementation request was followed by explicit `main/push/deploy`
authorization. Release work is now in progress: commit only this feature's
files, fast-forward the current main without touching unrelated local changes,
push, verify CI, deploy the confirmed Staging service, then update the emulator
with the exact verified APK while preserving its package data/storage. Do not
claim release until remote commit, live deploy and installed version are read
back successfully.

The already deployed API supports the subset contract, so this Mobile-only
runtime change introduces no backend deployment order requirement or migration.
Any later release must preserve the known Staging environment, existing account,
Firebase, billing/Test Store and monitoring configuration. No real post or
purchase is necessary for selector/draft smoke. Automated contract tests and
mock AI responses do not establish actual Gemini quality or publication.
