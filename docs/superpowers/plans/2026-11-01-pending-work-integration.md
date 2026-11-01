# Pending work integration — 2026-11-01

## Scope and verified baseline

The owner asked to fix the four remaining groups after the main/push/deployment
audit. Work starts from freshly fetched `origin/main`
`2f6d0feb4d9833fff2f7b54c98f48bf14e8d1e6a`, merge base equal and ahead/behind
0/0, in the clean delivery checkout on `codex/pending-work-integration-20261101`.
The dirty root, all 44 registered worktrees, six stashes and combined APK source
remain preserved. Port only intended changes, never entire stale worktrees.

The four groups are integrated on main and the API is delivered to Staging at
`449b465704e5a649f92ec3f9315b6e35ce7730ca`. Mobile source is on main, but the
owner's APK has not been updated and native acceptance remains unverified.
See the delivery receipt below. Production remains outside this task.

## Four work groups

1. **Store-link readability**, from `eb3367a2`: useful Thai avatar initials,
   phone-number runs kept together, no letter spacing through Thai heading
   marks, and full-width odd final classic grid tiles. HTML stays escaped.
   Preserve all ten 3D heroes/assets/materials/geometry, custom imagery,
   category controls and catalog 2 compatibility. Regressions combine the
   readability rules with each new 3D theme.
2. **Publishing contrast**, from the root patch: use theme error colors for
   failed channel status/reason and paired error-container/icon colors. Give
   unavailable-preview labels an opaque fill above arbitrary cover images.
   Result states, publishing calls and navigation do not change.
3. **Push diagnostics and permission timing**, from PR #49 / `5ea2d387`: keep
   only allowlisted Firebase codes as Sentry `push_error`, with `initialization`
   for setup and `other` for unknown values. Never send provider messages,
   tokens, recipients or notification contents. Keep dead-token cleanup and
   best-effort delivery. Bound gateway initialization work at ten seconds and
   the native permission prompt separately at two minutes. The shell trusts
   these budgets; owner/session/queue checks remain.
4. **Conditional app-first connection**, from the preserved launcher candidate:
   Android 11+ tries the exact trusted HTTPS OAuth URL with `ACTION_VIEW`,
   `CATEGORY_BROWSABLE` and `FLAG_ACTIVITY_REQUIRE_NON_BROWSER`. Unsupported
   URLs/apps and older Android retain the secure Custom Tab then external
   browser path. iOS tries universal-link-only external launch, then the
   external browser. This depends on OS/provider link support; not every
   authorization URL is guaranteed to open natively.

Both Dart and Android reject untrusted hosts, non-HTTPS URLs, userinfo and
backslashes. OAuth URLs are not logged, rewritten or loaded in an embedded
WebView. Re-check initiating owner, operation and mounted screen before each
fallback, including after an asynchronous native result. Preserve nonce,
expiry, authoritative completion and lifecycle refresh: launch/return alone
does not prove an account is connected. Thai and English explain the app or
trusted-browser path.

References: [Android non-browser intents](https://developer.android.com/training/package-visibility/use-cases#non-browser-apps)
and [url_launcher launch modes](https://flutter.googlesource.com/mirrors/plugins/+/refs/heads/main/packages/url_launcher/url_launcher/lib/src/url_launcher_uri.dart).

## Compatibility and delivery

No Prisma schema/migration, API request/response shape, dependency, manifest
permission/query, environment value, feature flag or entitlement changes.
Existing installations remain supported. API before Mobile aligns public
readability and push diagnostics. Keep `[skip render]` on delivery commits;
do not deploy or resume Production.

Use the guarded Staging updater and verify package, UID, volume, version and
APK hash. Do not clear data or uninstall. Full provider-account authorization
and social publishing remain separate from routing-only acceptance checks.

## Verification record

- [x] Tests first: contrast fails six cases / eight pass; push API fails 14 /
  26 pass and Mobile slow-permission behavior fails before the fix; readability
  fails 30 API cases including ten 3D initials; OAuth routing/config/English
  fails 29 / 82 pass, plus two owner/screen-cancellation cases before the guard.
- [x] Targeted API after integration: 419 passed (readability, classic/3D
  rendering, push delivery and monitoring sanitization).
- [x] Targeted Mobile: 460 passed; two new tests initially fail Flutter's
  platform-override teardown invariant. Switching their setup to the existing
  `TargetPlatformVariant` preserves every assertion and passes both isolated.
- [x] Final full Mobile suite: 4,558 passed / seven optional previews skipped,
  exit 0, with two workers. Analysis reports no issues. The full run takes
  15:25 on this Windows machine while the native builds also run.
- [x] Final full API: 3,210 passed / 67 opt-in PostgreSQL cases skipped across
  191 passed / 11 skipped files with Node 22.23.3 and one worker. Typecheck,
  build, catalog check, Prisma validate and Prisma helper typecheck pass.
  Only a loopback placeholder database URL was used; no SQL integration suite
  or hosted migration is claimed. The first full run had 3,209 passes and one
  fatal-process subprocess exceeding its unchanged six-second harness during
  concurrent startup work. Its unchanged isolated suite passes 4/4; the final
  complete run passes, including all fatal cases, without changing timeouts.
- [x] Browser checks use compiled routes and memory fixtures on loopback port 4321,
  with no accounts/database/providers. All ten 3D plus three classic layouts
  load at 320px without horizontal overflow, with the correct Thai initial,
  three links, telephone spans and loaded 3D art. The 390px 3D case and desktop
  classic case also pass (520px main / 480px full-row tile). Gallery navigation
  and keyboard focus on the real telephone link work; external destinations
  are not activated. No application console error is found; warnings belong
  to the installed MetaMask extension. Temporary viewport overrides are reset.
- [x] Actual application APK 12092 builds with the guarded Staging helper,
  separate from the offline QA entrypoint. Its SHA-256 is
  `7b1021076d6f81f02fd225cb6247a7d58ece75edf88ff81ad46c36b7cd362be4`
  and size is 252,441,424 bytes. Package/version, correct Staging API/Firebase
  project, real auth, disabled mock auth, existing Sentry and guarded RevenueCat
  Test Store mode are verified. All ten bundled 3D artwork hashes match source.
  The kernel contains no offline-QA identity; the separate QA APK does. All
  1,055 frozen source hashes match after tests and both builds. Local receipt:
  `artifacts/pending-candidate-apk-receipt.json`. Root ignored settings are
  reused through a temporary hard link without changing their bytes; the link
  is removed after builds and the original configuration remains intact.
- [ ] Native routing and visual QA, retained owner-device data and explicit
  provider/device limitations.
- [x] Final diff review against baseline: deletions, retired features, assets,
  dependencies and environment flags.
- [x] Record delivery only when authorized and performed (main/push/Staging API;
  no installed Mobile delivery or native acceptance claim).

## Native QA blocker and retained candidate

The source candidate is `ac62a01a89ed99e7e4677f6c84f5ecc45d584bc9`
(`abd6e29e` plus the reviewed PR #49 ancestry/documentation merge). A fresh
fetch still finds `origin/main` at the baseline above. All 1,055 frozen source
hashes match after that merge; the difference from the baseline is the 37
intended files, with no deletion or dependency/schema/config/catalog/asset
change. The six-file PR merge delta is documentation only. Diff checking passes.

Native checks use the separate, visibly marked offline fixture APK on
`PostDee_Account_QA_20261007`, not the owner's installed application. Some
settled frames verify the 3D Thai initial/phone rendering and readable dark
post-error text, but the overall interaction check does not pass: Android
reports an input-dispatch ANR, including a repeat after restarting the same
AVD headlessly with 4 GB RAM and software rendering. No userdata is cleared,
and the QA package retains UID 10190 and version 12092. The owner Pixel_8
installation remains version 12090/UID 10197; the actual application APK
12092 has not been installed there.

Read-only diagnostics also find ANRs/timeouts in Android system services,
heavy guest I/O wait and host D: storage latency around 410 ms for reads and
311 ms for writes while host memory has headroom. These observations support
an environment/storage-pressure explanation but do not prove the exact cause
of the application ANR. There is no successful native OAuth-routing acceptance
check, real provider authorization, iOS-device check or live publishing test.
Do not mark those flows verified from the automated tests or screenshots.

Historical gate, superseded only by the owner-directed delivery decision below:
delivery was stopped under the repository's no-regression policy, with the four
groups committed locally and no main/push/Staging delivery at that time.
Repeat the guarded native acceptance checks on a responsive Android device
or emulator before claiming native acceptance. No migration or environment
change is needed. Production remains unchanged.
Local evidence is retained in `artifacts/pending-qa-native-diagnostic.json`,
the full test/build logs, the source manifest and the APK receipts.

## Owner-directed Staging delivery follow-up

After receiving the native ANR findings and the explicit report that main,
push and deploy were held, the owner instructed `main/push/deploy` on
1 November 2026. Proceed with that reviewed candidate to main and Staging
only, retaining the unverified native flow as a known limitation. This
instruction changes the delivery decision; it does not turn native QA into
a passing check or establish the ANR's cause.

Use fast-forward integration from freshly verified `origin/main` at
`2f6d0feb4d9833fff2f7b54c98f48bf14e8d1e6a`, preserve the original dirty
checkout and `[skip render]`, and wait for exact-main-SHA CI before the
manual Staging deploy. Do not install/distribute an APK or change Production,
environment values, package rules or schemas as part of this follow-up.
Record the actual deploy and live checks in `docs/STAGING.md` after success.

### Completed main and Staging API receipt

- Fast-forwarded and pushed main at `449b465704e5a649f92ec3f9315b6e35ce7730ca`;
  PR #49 is merged through `ac62a01a`. Original dirty work remains preserved.
- Exact-SHA [CI 41316009628](https://github.com/NOI56/PostDeeMobile/actions/runs/41316009628)
  succeeds at 14:35:33 UTC: API 3,210 passed / 67 opt-in SQL skipped; Mobile
  4,558 passed / seven optional previews skipped; analyze clean; configuration
  guards 21 passed. [iOS build 41316009633](https://github.com/NOI56/PostDeeMobile/actions/runs/41316009633)
  succeeds at 14:36:31 UTC, no codesign and no device installation.
- Manual Staging deploy `dep-dbjksp2jnfac738a57h0` starts 14:36:20 UTC and is
  Live at 14:37:44 UTC (21:37:44 Bangkok), with exactly that commit. Previous
  Live reference is `859d2a86` / `dep-dbjimstg1s2s73fs0q2g`.
- Startup finds 28 migrations with none pending; publishing activation guard
  passes with empty backlog. No schema, environment or entitlement changes.
- GET-only live verification finishes 14:38:13 UTC: health/ready 200 with
  database/queue OK and readiness no-store, unauthenticated posts 401, private
  profiles 401 with catalog Vary/no-store, all ten 3D PNG hashes equal source,
  valid MIME/nosniff/cache, unknown artwork 404. No app error/warn logs through
  14:38:21 UTC. PowerShell supplies this evidence after local Node HTTP times out.
- This delivers the API and source, not native acceptance. APK 12092 remains
  uninstalled; owner installation stays 12090. Native ANR cause, native OAuth,
  real provider authorization, push-failure drill, iOS device and real social
  publishing remain unverified. No profile writes or Production operations.
- [Staging record](../../STAGING.md) contains the dashboard link and full Thai
  receipt. Later receipt commits change documentation only; runtime stays at
  `449b4657`. Local JSON receipts retain CI and GET evidence.
