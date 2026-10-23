# Sentry error reporting — 2026-10-22

## Request, baseline and scope

The user chose Sentry for PostDee Mobile and API, then confirmed that no Sentry
project existed. The 2026-10-23 continuation resumes that work. Remote `main`
freshness and the `ecbc33e940a917896692628cb700a844ab31bc4a` baseline were verified
before implementation on `codex/sentry-monitoring` in
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`.
The pre-implementation remote freshness recheck used `ecbc33e`, ahead/behind
`0/0`; the authorized release follow-up below records the later main revisions.
Preserve unrelated pre-existing generated Windows plugin changes. The stale
D-drive checkout is not the implementation source; its artifact/test paths do
not change that baseline.

Scope is opt-in error reporting for Flutter, Node API/current in-process
publishing and the existing optional standalone worker. No performance tracing,
log/metric export, Replay, screenshots, view hierarchy, attachments, social
posting or purchase is required. No endpoint, API contract, database schema,
migration, entitlement, billing, publishing mode or worker deployment change.
The user's subsequent 2026-10-23 `main/push/deploy` request authorizes main
integration, GitHub push and Staging API activation for this feature. Main/GitHub
delivery and Staging activation are complete with health/runtime checks passed.
The user's subsequent explicit cloud API test verifies deployed monitoring-module
ingestion through an isolated authenticated Render Web Shell process. The initial
`35512aa` event is accepted with a processing warning; the minimal API fix
`12e0589` is Live and its repeated event has no processing error. Current-source
Backend and Flutter Mobile CI both pass; the Mobile tree is unchanged.

## Account/project setup

- The authenticated Sentry organization is `postdeemobile`.
- The Mobile project was created on 2026-10-22, project ID `4512297633054720`.
- The API project was created in the same organization, project ID
  `4512302958706688`, with suggested alerts off. Project creation is distinct
  from transport acceptance or cloud activation.
- Keep suggested alerts off, do not connect GitHub or change a paid plan, and
  do not add an organization authentication token to tracked configuration.
- Project DSNs belong in the target's untracked runtime/build configuration.
  Do not print them in this work record or commit them. No Sentry source-map
  upload/auth-token pipeline is included in this candidate.
- The first synthetic event exposed Sentry-inferred coarse geography even
  though the outbound application event had no `user`. Both projects now have
  IP storage prevention enabled and an advanced scrub rule `[Remove] [Anything]
  from `[$user.**]` saved. The initial source `user` was corrected to `$user.**`;
  those sources are not interchangeable. Existing default scrubbers are
  retained. Both latest API/Mobile dashboard events show geography absent after
  the corrected settings. User identifiers and customer URL/body fields are
  excluded by source boundaries and outbound allowlist tests; do not infer
  their absence solely from a generic dashboard placeholder.

## Implemented candidate

### Node API and optional worker

- Pin `@sentry/node` to `11.8.0` and initialize the reporter before app/scheduler
  startup. The standalone worker uses its own initialization of the same
  boundary; it is not a newly provisioned service.
- Use explicit request/error middleware, handled provider/publisher/scheduler
  reports and the SDK `onUncaughtExceptionIntegration`. Capture unexpected
  5xx/unhandled server errors and bounded operation/platform/status labels.
  Expected 4xx responses are not reported, and reporting does not resend or
  retry a post.
- Disable default automatic integrations except `onUncaughtExceptionIntegration`;
  retain Node's default unhandled-rejection path and fatal exit, including named
  rejected errors. Do not install Sentry's separate rejection integration.
  Disable tracing, Express auto-instrumentation, breadcrumbs and logs. Final
  outbound events and transport envelopes are rebuilt from safe error types,
  repository-relative source frames and allowlisted tags. Discard raw messages,
  request and provider payloads, identities, credentials, URLs, media keys and
  attachments.
- SDK/transport failures are contained and shutdown flush is bounded. Invalid
  enabled server configuration is rejected at startup, with sanitized messages.
  No DSN means the disabled reporter and existing behavior.

### Flutter Mobile

- Pin `sentry_flutter` to `9.30.1`, retain the existing CocoaPods path and use a
  single-start app runner. Absent/invalid configuration disables Sentry. SDK
  initialization failure restores fallback before running the app once.
- Capture Dart/Flutter unhandled errors and safe handled API 5xx reports.
  Handled reports accept bounded operation/status labels only; no URL, body or
  exception message enters this boundary.
- Rebuild outbound events from safe error types, Dart source locations and
  allowlisted labels. Retain only bounded nonidentifying technical contexts:
  manufacturer/model, OS name/version/build and Dart/Flutter runtime. Device
  IDs/names, user records and arbitrary context maps are excluded. Rebuild final
  Dart HTTP event envelopes too, dropping unknown envelope items, header baggage
  and attachments.
- Turn off native auto-initialization, native crash/ANR handling and native
  scope sync because native Sentry envelopes bypass the Dart sanitizer.
  **Sentry-native crashes/ANRs remain outside this integration.** Preserve
  existing native Crashlytics collection whenever Firebase monitoring is
  available, without a new native bridge. This is retained baseline coverage,
  not a new native crash or iOS acceptance result.
- Keep tracing/performance, trace propagation, breadcrumbs, log/metric export,
  Replay, screenshots and view hierarchies off.
- Successful Sentry initialization owns only Dart `FlutterError` and
  `PlatformDispatcher` hooks, avoiding duplicate Dart Crashlytics reports.
  `enableDartCrashReporting` controls those hooks; it does not disable native
  Crashlytics collection. With Sentry disabled/unavailable, retain Crashlytics
  Dart hooks too. Firebase Analytics, Auth and FCM stay connected in both paths.

## Configuration and activation

| Setting | API | Mobile |
| --- | --- | --- |
| `SENTRY_DSN` | API project's HTTPS DSN in untracked server configuration | Mobile project's HTTPS DSN in untracked Dart defines/build file |
| `SENTRY_ENVIRONMENT` | Explicit `development`, `staging` or `production` when enabled | Set explicitly for the intended build; Staging must be `staging` |
| `SENTRY_RELEASE` | Optional safe identifier such as `postdee-api@<commit-sha>` | Optional safe identifier such as `postdee-mobile@<version>+<build>` |

Examples keep `SENTRY_DSN` empty. Mobile's
`apps/mobile/staging.local.example.json` declares `SENTRY_ENVIRONMENT=staging`;
the API `.env.example` uses `development` for local work. On Render Staging,
explicitly use `staging` even with `NODE_ENV=production`. Never infer the Sentry
environment from that Node variable or mix the Mobile/API project DSNs.

API monitoring is default-off and does not require a database migration or an
API-first compatibility release. Each API/worker still needs its own authorized
cloud configuration and deployment to start reporting. Mobile needs an exact
build containing its defines. Do not claim that saving a DSN or creating a
project proves that events arrived.

For pre-deployment verification, use a generic synthetic event from the local
API and from the exact Staging Android build. Check their matching project,
environment and safe release fields, and inspect the outbound payload for
customer data. Do not add a public error-test endpoint or use a real publication,
purchase, customer video or forced native crash. No real native crash test can
validate this candidate's intentionally disabled native handler.

## Backward compatibility and preserved capabilities

Keep Firebase Auth/FCM/Analytics, existing native Crashlytics collection and
Dart Crashlytics fallback, social settings,
consent/receipt recovery, Calendar selected covers and one-line captions,
publishing status refresh, owner-scoped reads, monthly/purchased-credit behavior,
AI provider boundaries and graceful shutdown/drain behavior intact. Existing
disabled/default feature flags and the current single-instance publisher mode
must not change. Monitoring failure is not publication failure or permission to
retry an ambiguous provider result.

## Verification and release status

The unchanged API candidate passes local synthetic acceptance. APK12040 passed
intermediate Mobile checks and exact Android event acceptance, but a final
baseline review found that it disabled the existing native Crashlytics
collector while Sentry-native collection was off. The minimal preservation fix
passes final-3 Mobile tests/analysis and exact APK12041 build/source/startup/event
checks. Native Crashlytics collection is verified enabled on the installed
APK12041; no actual native crash was triggered. APK12040 remains intermediate
evidence superseded by APK12041. The API source and its 2,420-test/Staging event
acceptance are unchanged. Results below were supplied by the coordinating agent on
2026-10-23; project creation is not counted as transport acceptance.

Test-first Mobile RED evidence is retained outside tracked source at
`D:\PostDeeMobile\artifacts\sentry-monitoring-20261022\mobile-red.log`.

| Check | Actual result |
| --- | --- |
| Initial API full suite, Node `22.23.3` | 2,420 passed, 25 skipped; 147 test files passed, four skipped. The initial parallel run had four timeouts; a clean sequential one-worker repeat passed with no product-code change for the timeouts. |
| API static/build/schema checks | Typecheck, build, Prisma schema validation and Prisma helper compilation pass. |
| API fatal regressions | Real child processes preserve fatal uncaught-error and Node-default unhandled-rejection behavior, including named errors. |
| Intermediate Mobile focused suite | 116 passed before the native Crashlytics preservation fix. |
| Intermediate Mobile final-2 full suite | 2,741 passed, six optional skips before the native collector preservation fix. |
| Intermediate Mobile analysis | No issues before the preservation fix. |
| Intermediate Android build | Staging APK12040 build passes in 557.5 seconds; exact 589 source hashes match. Package, Staging API, Firebase, Google client, existing billing SDK key, signer, x86_64, 16 KiB alignment and retained source features pass inspection. The later native collector regression blocks treating it as final acceptance. |
| Android installation/UI | Guarded update of existing alternate QA `Pixel_8`, `emulator-5556`, version 1 to 12040 preserves UID `10197` and its internal volume without uninstall/clear. Home opens with a retained draft and cached history. The original adopted-volume `PostDee_Pixel` package was unavailable and was not repaired or modified. |
| Local API synthetic transport | A generic local Express 500 was accepted in Sentry as `POSTDEE-API-1`, issue `7807886345`, environment `staging`, release `postdee-api@ecbc33e-sentry-verify-20261023`. This is not a deployed API test. |
| Intermediate exact Android synthetic transport | Production reporter `capturePostDeeApiServerError('api', 500)` completes on APK12040. Sentry accepts `POSTDEE-MOBILE-1`, issue `7807904646`, event `1cd4932a703d43b08f636e7c02f8e650`, environment `staging`, release `postdee-mobile@0.1.0+12040`. Debugger attach/detach only; no hot reload, reinstall or native crash. This does not verify the subsequent preservation fix. |
| Final-3 Mobile focused/full suites | 116 focused tests pass; full suite has 2,741 passed and six optional skips on the native Crashlytics preservation source. |
| Final-3 Mobile analysis/build | Analysis has no issues. APK12041 build passes in 178.8 seconds total (173.9-second Gradle phase); exact 589 source hashes match. |
| Final-3 Android update/startup | Guarded update 12040 to 12041 on QA `Pixel_8`, `emulator-5556`, preserves UID `10197` and internal volume. Home opens with the existing draft and cached history retained. Exact compiled Staging config/release matches APK12041. |
| Final Mobile/native collector preservation | Source gives Sentry only Dart hooks. On the installed APK12041, querying `FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled` returns `true`. Final-3 tests/analysis/build and startup/Sentry acceptance pass; no actual native crash is triggered. |
| Final APK12041 synthetic event | Exact production reporter `capturePostDeeApiServerError('api', 500)` completes. The latest `POSTDEE-MOBILE-1` event is `317c50d701764b0caa37595fb5478bad`, release `postdee-mobile@0.1.0+12041`, environment `staging`, operation `api`, status `500`, with a generic message and no geography. Debugger attach/detach only; no hot reload, reinstall, post, purchase or native crash. The app remains running after detach. |
| Post-setting privacy check | Both projects' IP prevention and advanced `$user.**` removal settings are saved. The latest API event `096d12c2ae7743fe88c71ac19f8d50a7` and Mobile event show geography absent in the dashboard. Source/tests cover the customer URL/body/user allowlist boundary. |
| Existing live account scope | An earlier Home observation showed a temporary plan error while Staging `/health` returned HTTP 200. Latest QA Home shows Free 0/3, so the earlier error is not current state. Live entitlement retrieval, checkout and publishing were not verified end to end; cached Home/history and a visible plan label are not that proof. No real post or purchase was submitted. |

Accepted issues, using the browser-verified organization and issue paths:

- [POSTDEE-API-1](https://postdeemobile.sentry.io/issues/7807886345/)
- [POSTDEE-MOBILE-1](https://postdeemobile.sentry.io/issues/7807904646/)

The intermediate APK12040 SHA-256 is
`4285178ec271d6a39f71fb2aa619f1169a225688aca3ef6e8d2ad3f3682dd6d0`.
The final-3 APK12041 SHA-256 is
`ee18af0da960a713294b1e47ec707371a040f7e7ea95e7c95eb969a55dd62ad7`.
Evidence is retained outside tracked source under
`D:\PostDeeMobile\artifacts\sentry-monitoring-20261022\`:

- `api-checks-node22-final-2.json` and `api-source-node22-final-2.json`
- `mobile-targeted-final-2-result.json`, `mobile-full-final-2-result.json`,
  `mobile-analyze-final-2-result.json`, `mobile-build-final-2-result.json` and
  `mobile-source-final-2.json`
- `apk-verification-12040.json`, `native-update-12040.json` and
  `app-staging-12040-x86_64-debug.apk`
- `mobile-targeted-final-3-result.json`, `mobile-full-final-3-result.json`,
  `mobile-analyze-final-3-result.json`, `mobile-build-final-3-result.json`,
  `mobile-source-final-3.json`, `apk-verification-12041.json`,
  `native-update-12041.json` and `app-staging-12041-x86_64-debug.apk`
- `api-live-smoke.json`, `mobile-live-smoke.json`,
  `sentry-api-dashboard-acceptance.json`,
  `sentry-mobile-dashboard-acceptance.json`, `sentry-api-event.png` and
  `sentry-mobile-event.png`

`finalize-evidence.ps1` completed and the current live-smoke/dashboard records
mark acceptance. Historical earlier `dashboardAcceptance: pending` values are
superseded, not failed transports. `sentry-mobile-event.png` shows the latest
APK12041 event. A Mobile UI predicate looking for the API-specific
`url --` placeholder was not a valid proof of URL presence/absence. Use the
allowlist tests/source and explicit dashboard geography evidence instead.
No DSN, authentication token, customer content or media is included in this
work record or the synthetic issue descriptions.

Final-3 Mobile tests/analysis/build/source checks and exact APK12041
startup/Sentry event verification pass. Sentry-native crash/ANR,
new native Crashlytics crash acceptance, iOS, physical-device performance and
live entitlement/publish/checkout checks remain separate work. Initial cloud
ingestion was accepted with a processing warning; the later API correction and
repeated isolated-process event pass without that warning. There is
no claim of forced Express-main-process HTTP-error acceptance, tracing/performance
monitoring or full production
readiness. Main/push and Staging API activation are authorized by the user's
2026-10-23 request. Feature, lockfile repair and minimal sanitizer correction are
on `main`/GitHub; source `12e0589` is Live with health/runtime checks passed.
Current-source Backend and Flutter Mobile CI both pass; earlier
Backend/Mobile CI and unsigned iOS compilation pass. No Mobile edit/rebuild is
part of the API correction, and Mobile empty/async-stack metadata handling is
not live-validated by the cloud API result.

## Authorized release follow-up — 2026-10-23

- User instruction: `main/push/deploy`.
- Scope: integrate the verified candidate into `main`, push to GitHub and deploy
  Sentry-enabled Staging API in the existing Render `My Workspace`, service
  `postdee-api-staging` (`srv-d9bb72ojs32c739osa5g`). Do not provision a separate
  worker or change Production, social posting, billing or unrelated feature flags.
- Feature source is integrated/pushed as
  `b486ca3aee317e79f55b926ef6aed5b422372580`; the subsequent generated-lockfile-only
  fix is integrated/pushed as `35512aa6d5a2f6fd1fbe9b95e34bcf96925f62d0`.
  Staging deploy `dep-dbdciulg1s2s73b17ss0` is Live on the repaired source,
  with runtime/release/health checks below. Exact-source Backend and Flutter
  Mobile CI pass. A later explicit cloud test accepts one generic event with a
  processing warning. The minimal API correction is subsequently pushed as
  `12e05895755b16d21f7eabb90a75d1824dac0b1e`, Live in
  `dep-dbdcvlmi0phs739c9m20`; its repeated event has no processing error.
- Release preflight found a CI-only compatibility gap: the Staging build-define
  validator rejected the new Sentry fields. The targeted fix in
  `scripts/prepare_staging_ci_defines.py` accepts and validates `SENTRY_DSN`,
  `SENTRY_ENVIRONMENT` and `SENTRY_RELEASE` without logging their values or
  admitting an authentication token. Its Python suite passes 21 tests, including
  the actual checked-in example with billing disabled/enabled. Tests are in
  `scripts/test_prepare_staging_ci_defines.py`. No Mobile/API runtime source or
  exact APK12041 evidence changes; cloud delivery is recorded separately below.
- Use the API project's DSN only in the target runtime's private configuration,
  with `SENTRY_ENVIRONMENT=staging` and a safe exact release identifier. Do not
  write DSNs, authentication tokens or environment payloads into tracked docs.
- Retain all earlier API/Flutter test and APK12041/native-collector evidence.
  Sentry-native/actual native-crash/iOS acceptance and live entitlement,
  checkout/publication E2E remain separate work. No real post or purchase is
  required to verify this release.

### First cloud build and lockfile-only repair

- The Render MCP environment merge added only `SENTRY_DSN`,
  `SENTRY_ENVIRONMENT` and `SENTRY_RELEASE` to the verified existing Staging
  service. The UI key-name diff was 54 to 57, with no removed keys and no raw
  environment values read. This update triggered deploy
  `dep-dbdcfelg1s2s73b0t4j0` despite auto-deploy being off.
- That build failed at `npm ci` with `EUSAGE`: missing
  `@emnapi/core`/`@emnapi/runtime` `1.11.3` and a `@emnapi/wasi-threads`
  lockfile mismatch. Existing live source `8c957ab` was retained; a failed build
  is not Sentry activation or a change to the serving API binary.
- The failure was reproduced using Node `22.23.3` and npm `10.9.9`. The generated
  lockfile-only fix in `35512aa` preserves `package.json`, all 78 optional
  dependency packages and the intended runtime boundary; only the WASM peer
  dependency graph is repaired. No API/Mobile runtime source or APK12041 changes.
- A clean Linux-target dependency installation on Windows with scripts disabled
  installs 467 packages successfully, with zero npm graph problems and zero
  production-audit findings. This is dependency-graph evidence, not an actual Linux runtime
  or hosted CI pass.
- Backend and Flutter Mobile on actual hosted
  [CI run 39890752750](https://github.com/NOI56/PostDeeMobile/actions/runs/39890752750)
  both pass for exact source `35512aa`; success was confirmed at
  `2026-10-23T02:46:27Z` (09:46:27 Thailand time). Local test counts above are
  not presented as hosted counts.
  The original Mobile
  [run 39890262199](https://github.com/NOI56/PostDeeMobile/actions/runs/39890262199)
  passes, and its exact Mobile tree is unchanged between `b486ca3` and
  `35512aa`. The unsigned
  [iOS run 39890262207](https://github.com/NOI56/PostDeeMobile/actions/runs/39890262207)
  passes compilation with Sentry disabled. This is not iOS monitoring runtime,
  native crash or physical-device acceptance.
- After the Backend CI pass, the Sentry release key alone was updated to
  `postdee-api@35512aa6d5a2f6fd1fbe9b95e34bcf96925f62d0`, triggering the
  successful follow-up deploy. The API DSN and `staging` environment were already
  configured; no other environment key was added or removed for this follow-up.

### Live Staging verification

- Render deploy `dep-dbdciulg1s2s73b17ss0` serves exact source
  `35512aa6d5a2f6fd1fbe9b95e34bcf96925f62d0` and is Live, finished
  `2026-10-23T02:43:57.148Z` (09:43:57 Thailand time).
- Post-Live checks at `2026-10-23T02:44:33Z` return `/health` HTTP 200 and
  `/ready` HTTP 200, with database and queue healthy.
- Sanitized startup evidence from 02:42:40Z onward confirms the API is listening,
  22 migrations were found with none pending and the existing in-process
  scheduler started. Sentry introduces no new schema/migration. There is
  no monitoring-init failure or fatal startup diagnostic. No private values or
  raw logs are included in this record.
- At the initial Live check, a deployed synthetic event was not triggered: a
  read-only SSH probe stopped at an unknown trusted-host key. No host trust,
  SSH keys or permissions changed. Configured startup/health alone was not
  counted as ingestion. The later authenticated Web Shell test below proves
  deployed monitoring-module ingestion without changing SSH trust.
- Main/push/Staging delivery and exact-source Backend/Mobile CI are complete at
  source `35512aa`; the later isolated deployed-module event is accepted with
  a processing warning requiring remediation.
  The source
  Mobile 589-file hashes and APK12041 are unchanged. In the 456-file API source
  inventory, only the lockfile differs from local full checks; the final Linux
  Backend CI pass covers that repair. No real post, purchase or
  native crash was triggered. This initial record did not require a runtime
  change; the later processing correction has its own verified deploy below.

### Explicit cloud ingestion follow-up — 2026-10-23

- The user explicitly requested the cloud API test. This initial probe and its
  record start from `72c7fd64b09974d1eebff5e22b23ee9d028d1057`, freshly
  verified against `origin/main` at ahead/behind `0/0`. Preserve the three
  unrelated generated Windows files. The initial isolated probe itself changed
  no source/configuration and needed no deployment. The subsequently discovered
  processing warning led to the separately tested/released correction below.
- Use the authenticated Render Dashboard Web Shell on current Staging instance
  `78mh7`, directory `~/project/src/apps/api`. One isolated Node process imports
  only deployed `dist/monitoring/sentryConfig.js`, `sentryMonitoring.js` and SDK
  event/close accessors. It does not import the app, server or worker or use the
  database. No SSH key, host-trust or permission changes are needed.
- Runtime identity checks match the exact Render service and deployed Git source
  `35512aa6d5a2f6fd1fbe9b95e34bcf96925f62d0`. Configuration checks match
  `staging`, release
  `postdee-api@35512aa6d5a2f6fd1fbe9b95e34bcf96925f62d0` and API project
  `4512302958706688`. Store only match booleans, never the DSN or raw environment.
- Capture one handled synthetic `TypeError` with allowlisted operation
  `server.startup`. This label is a diagnostic test context, not a real startup
  failure. The returned event is `08fa034ea34e49ffa5afb5a8c7bcd090`; flush and
  SDK close return true, the child exits and the shell prompt returns.
- At `2026-10-23T02:58:38Z` (09:58:38 Thailand time), the latest dashboard event
  is accepted as
  [POSTDEE-API-2](https://postdeemobile.sentry.io/issues/7807957893/), exact event
  ID `08fa034ea34e49ffa5afb5a8c7bcd090`. Environment, full release and operation
  match. The displayed message is generic `PostDee server error`; the raw test
  message and geography are absent.
- Subsequent inspection of the event's `Processing Error` button shows
  `Discarded invalid value` at `exception.values.0.stacktrace.frames`, expected
  to be nonempty. The event is accepted/grouped, but it is not a warning-free
  processing result. Preserve its accepted issue/event ID as initial evidence.
- Health/readiness are HTTP 200 before and after the test. Post-test checks at
  `2026-10-23T02:56:17Z` confirm database/queue healthy. No post, purchase,
  customer content, HTTP failure, native crash, service restart or main-process
  failure is triggered.
- Scope: this proves the deployed module, runtime configuration and cloud
  network path to Sentry. It does not prove an error flowing through the running
  Express main process, its HTTP middleware or native crash handling. Existing
  local middleware tests and APK12041 acceptance remain separate evidence.
- Sanitized evidence in
  `D:\PostDeeMobile\artifacts\sentry-monitoring-20261022\`:
  `cloud-api-live-smoke.json`, `cloud-api-dashboard-acceptance.json`,
  `cloud-api-smoke-health.json`, `cloud-api-shell-smoke.png` and
  `cloud-api-sentry-accepted.png`. The original cloud probe changed no runtime
  source/configuration; the correction below requires its own verified release.

### Cloud processing warning remediation — Live and repeated event accepted

- Cause: the API sanitizer excludes private/unsafe source frames, including
  the synthetic cloud error's eval frames, but still emits `stacktrace` with
  `frames: []` when none remain. Sentry requires a nonempty frame list and
  discards that invalid value during processing.
- Regression tests were added first. The minimal correction omits `stacktrace`
  when no safe frames remain, preserving known-safe nonempty stacks and all
  privacy restrictions. Private/eval frames are not retained to silence the warning.
- Runtime scope is only `apps/api/src/monitoring/sentryMonitoring.ts` and its
  regression tests. Source `12e05895755b16d21f7eabb90a75d1824dac0b1e` is
  fast-forwarded to `main` and pushed. Targeted 30 tests pass; the full API suite
  on Node `22.23.3` passes 2,422 tests with 25 skips (147 files passed/four
  skipped). Typecheck, build, Prisma schema validation and helper compilation
  all exit zero; source hashes match. No Mobile source changes or rebuild.
- [CI run 39893356044](https://github.com/NOI56/PostDeeMobile/actions/runs/39893356044)
  passes Backend and Flutter Mobile on exact source `12e0589`; successful final
  status is verified at updated time `2026-10-23T03:14:52Z` (10:14:52 Thailand
  time). Backend completes at 03:08:47Z and Mobile at 03:14:51Z. Evidence is
  `ci-39893356044.json`. The Mobile tree is unchanged and its earlier acceptance
  remains as recorded above; this API correction requires no Mobile rebuild.
- Render deploy `dep-dbdcvlmi0phs739c9m20` is Live on exact source `12e0589`,
  finished `2026-10-23T03:10:35.988195Z` (10:10:35 Thailand time). Only
  `SENTRY_RELEASE` changes to
  `postdee-api@12e05895755b16d21f7eabb90a75d1824dac0b1e`; auto-deploy stays off.
  Startup finds 22 migrations/none pending and no monitoring-init/fatal failure.
- `/health` and `/ready` return HTTP 200 with database/queue healthy before
  the repeated cloud test at 10:10:43 Thailand time and in the initial
  post-capture check at 10:11:26. The final check after dashboard inspection at
  `2026-10-23T10:14:47.8292270+07:00` again confirms both endpoints HTTP 200
  with database/queue healthy.
- On current instance `dtc4r`, one isolated authenticated Web Shell Node process
  verifies deployed module/service/source, Staging configuration/full release
  and API project `4512302958706688`. Capture returns event
  `1d062ef96a624d039d6f87ccdfa0dc0f`; flush/close return true and the prompt
  returns. No app/server/worker import, HTTP failure, real post/purchase,
  customer content or main-process crash is triggered.
  The dashboard event timestamp is `2026-10-23T03:11:21.435Z`; the smoke
  record's `verifiedAt` `03:11:48.288Z` records the result after command exit.
- At `2026-10-23T03:12:47.597Z` (10:12:47 Thailand time), Sentry's latest
  [POSTDEE-API-2](https://postdeemobile.sentry.io/issues/7807957893/) event exactly
  matches `1d062ef96a624d039d6f87ccdfa0dc0f`, `staging`, the full `12e0589`
  release and `server.startup`. The message is generic, raw test text and
  geography are absent. Full accessibility-tree and visual inspection find
  neither `Processing Error` nor `Discarded invalid value` on this event.
- Preserve initial event `08fa034ea34e49ffa5afb5a8c7bcd090` as accepted-with-warning
  history; the new event verifies the API correction without relaxing privacy.
  Scope remains deployed monitoring module/configuration/network ingestion,
  not a forced Express-main-process HTTP error or native crash. Mobile
  empty/async-stack metadata handling has not been live-validated.
- Final sanitized evidence under
  `D:\PostDeeMobile\artifacts\sentry-monitoring-20261022\`:
  `api-source-empty-stack.json`, `api-checks-empty-stack.json`,
  `ci-39893356044.json`, `staging-empty-stack-release.json`, `cloud-api-fixed-smoke.json`,
  `cloud-api-fixed-dashboard-acceptance.json`, `cloud-api-fixed-before-health.json`,
  `cloud-api-fixed-after-health.json`, `cloud-api-fixed-final-health.json`,
  `cloud-api-fixed-shell.png` and
  `cloud-api-fixed-sentry-accepted.png`.
