# Pending work integration — 2026-11-01

## Scope and verified baseline

The owner asked to fix the four remaining groups after the main/push/deployment
audit. Work starts from freshly fetched `origin/main`
`2f6d0feb4d9833fff2f7b54c98f48bf14e8d1e6a`, merge base equal and ahead/behind
0/0, in the clean delivery checkout on `codex/pending-work-integration-20261101`.
The dirty root, all 44 registered worktrees, six stashes and combined APK source
remain preserved. Port only intended changes, never entire stale worktrees.

This is the integrated local candidate. Main integration, push, Staging deploy
and installed-build verification are recorded only after they occur.
Production remains outside this task.

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
- [ ] Final diff review against baseline: deletions, retired features, assets,
  dependencies and environment flags.
- [ ] Record delivery only when authorized and performed.
