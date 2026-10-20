# Preserve same-form platform confirmations

Status: LOCAL VERIFIED — automated regressions, controlled production-widget
smoke, analysis and Staging APK12029 build/package inspection pass. Not merged,
pushed, deployed or installed. The installed Staging app remains APK12028 and
the user's current composer was not interrupted.

## Request and baseline

ผู้ใช้พบว่าติ๊กยืนยันสิทธิ์ใช้เพลง TikTok แล้วไปเลือกผู้ชม ติ๊กหายไป
ให้แก้ไขและตรวจตัวเลือกการตั้งค่าของแพลตฟอร์มอื่นด้วย

- Freshly fetched `main`/`origin/main`:
  `b14ea996d9ade1b3751ad345e7b051f815d13d27`, 0 ahead / 0 behind.
- New clean worktree `platform-consent-preserve/PostDeeMobile`, branch
  `codex/platform-consent-preserve`. Existing checkout dirt is untouched.
- Root cause: every TikTok `_change` cleared both music and branded-policy
  consent, including viewer/interaction/AI changes and same-value selections.
- Official [TikTok requirements](https://developers.tiktok.com/docs/en/content-sharing-guidelines)
  require manual viewer/interaction choices and consent before posting; the
  cited page does not require clearing music acknowledgment on a viewer edit.

## Minimal change and preserved behavior

- Preserve the user's explicit music/policy checks while editing viewers,
  Comment/Duet/Stitch or AI in the same open TikTok sheet.
- Commercial switch, own-brand and third-party disclosure still reset both
  acknowledgments because their declaration context changes.
- Keep all existing resets on reopening, latest creator-capability loads, mode,
  account, connection, clip or caption/content changes. Keep manual initial
  choices, forbidden interactions, private/branded exclusions and Save validation.
- Do not change the outer TikTok consent-intent fingerprint, final immutable
  submission, preparation/duration checks, retry/idempotency, defaults allowlist,
  account isolation, Save/Cancel or local draft behavior.
- Audit YouTube/Instagram/Facebook handlers and defaults/draft scopes. No
  equivalent reset bug found; cover order-of-edit, Save/reopen, Cancel and
  cross-platform preservation with additional regression tests.
- No dependencies, API/contracts, backend code, flags, configuration, schema,
  entitlements or migrations change. No real post/AI/purchase is required.

## Verification

- Tests first: targeted run against unchanged runtime reproduced **six failures**
  for music-before-viewers, interaction/AI changes and branded acknowledgments.
  **40 passed / one optional preview skipped**. All six new other-platform
  sequence regressions passed against the baseline runtime.
- Evidence/tooling: `D:\PostDeeMobile\artifacts\platform-consent-preserve-20261020`.
- Targeted eight-file settings/preflight/defaults suite: **149 passed / one
  optional preview skipped**, 25.1 seconds. Includes **10 new TikTok and six new
  YouTube/Meta regression cases**, final injected submission payloads, explicit
  Save/Cancel/reopen, account/channel isolation and unchanged retry checks.
- Full Mobile suite: **2,504 passed / three optional previews skipped**, 183
  seconds. All runtime and non-preview test hashes match final build inputs.
  Only the opt-in screenshot harness's theme setup changed afterward; it was
  explicitly rerun against the final source and passed **1/1**, 6.2 seconds.
- Whole-project `flutter analyze --no-pub`: no issues, 11.1 seconds (12.9 seconds
  wrapper elapsed). Flutter 3.44.1 / Dart 3.12.1. No SDK/dependency changes.
- Exact-source Staging x86_64 APK12029 build: pass, 164.7 seconds. The same
  resource-limited D: verification snapshot/cache was reused; source and
  snapshot match **648 SHA-256-tracked inputs** after the build. This final work
  record update is documentation only and is made after those checks.
- APK package `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`,
  **197,047,094 bytes**, SHA-256
  `2e6cb30a9c03d647587af2a8e42d3046bc620bef0970731a173f36cae9535774`.
  Signature/same existing signer and 16-KiB ZIP alignment pass; Flutter engine
  is x86_64 only, so this is not an ARM delivery build.
- Compiled Staging API is `https://postdee-api-staging.onrender.com`; Firebase
  project `project-798caf7e-85b8-45e3-af7` / app
  `1:948899042298:android:945921b397cb7f261a4a43` and Google client match existing
  Staging. Existing Firebase auth and RevenueCat remain enabled, mock auth and
  experimental AI hook/beat sync remain disabled. Compiled kernel contains the
  selective consent reset, remembered defaults and smooth progress. Public SDK
  key is checked without printing/copying it. No account/entitlement state changed.
- Controlled real-widget preview uses manual music confirmation followed by a
  viewer change, verifies the check and Save remain enabled, then verifies
  commercial disclosure clears it. The harness now sets/restores the actual
  shared light palette as well as MaterialApp's theme; no product theme change.
  Four final captures in `preview-final/` were generated; the viewer and retained
  consent captures were visually inspected.
- Build emits the existing future KGP plugin migration warning for ffmpeg,
  Firebase Analytics and RevenueCat; the build succeeds. No unrelated plugin
  upgrade was attempted.
- Independent read-only reviews found no actionable issue in the patch or the
  outer consent fingerprint. Editing settings of already selected other
  destinations does not clear TikTok; adding/removing destinations still does,
  as required by the existing shared publishing-intent boundary.
- Receipt: `apk-verification-12029.json`; focused RED/GREEN, full-suite, preview,
  analyze/build logs and source manifests are in the evidence directory above.
- No native process restart, install, data clear, real upload or publication has
  been performed for this change; the user's current composer is preserved.

## Changed files and remaining delivery

- Runtime: `apps/mobile/lib/features/uploader/tiktok_publishing_settings_sheet.dart`.
- Regression tests: `apps/mobile/test/uploader_tiktok_direct_post_test.dart`,
  `apps/mobile/test/unified_platform_settings_test.dart`.
- Controlled render: `apps/mobile/test/tiktok_direct_settings_preview_test.dart`.
- Documentation: README, ROADMAP, ARCHITECTURE, API, Mobile README and this record.
- Source review shows no backend, contract, schema, config, dependency, defaults
  store, outer uploader or existing animation changes, deletions or lost wiring.
- Native verification of this new checkbox sequence remains pending until a safe
  app update. ARM/iOS and real-provider publishing were not tested. No actual
  external post is authorized or needed for the local settings regression.
- Merge/push and app installation remain separate delivery steps; an API deploy
  or migration is not required for this Mobile-only fix.
