# Make Home sending feedback as visible as Calendar

Status: LOCAL VERIFIED — tests, analysis, render checks and Staging APK passed;
not merged, pushed, deployed
or installed. The user's current app/form has not been interrupted.

## Request and baseline

ผู้ใช้ต้องการลูกเล่นระหว่างกำลังโพสต์ในหน้าหลักให้เหมือนหน้าปฏิทิน
ตรวจพบว่าทั้งสองหน้าใช้ shared motion อยู่แล้ว แต่ Home วางป้ายด้านข้าง
และแสงวิ่งชิดขอบล่าง ทำให้เห็นกิจกรรมไม่ชัดเท่า Calendar

- Freshly fetched `main`/`origin/main`:
  `324c38e20a561afaf8bf09054f1e546c6e24e7a3`, 0 ahead / 0 behind.
- Reuse the clean attached `platform-consent-preserve/PostDeeMobile` worktree,
  fast-forward to this baseline and create `codex/home-publishing-feedback`.
- Preserve the recent TikTok confirmation fix, remembered platform defaults,
  smooth full-screen progress and latest Node22/dependency/FCM API integration.
  Leave canonical main's three unrelated generated Windows files and artifacts
  and the stale original checkout untouched.

## Scoped presentation change

- Change only `_LatestPostRow` in `home_screen.dart`: for actual sending posts,
  place the badge below a two-line caption, omit the duplicate platform-name
  subtitle, place the inset rail before real per-channel outcomes and use a
  subtle accent border. Keep the thumbnail and row tap behavior.
- Ordinary rows retain one-line captions, subtitle/color blocks, status badge
  alignment, border and terminal labels. Calendar and shared motion are unchanged.
- Keep the same sending predicate and unknown-outcome guard. No invented
  percentage, timed success, another clock or extra network/publish operation.
- Preserve retained phase, reduced motion/TickerMode/lifecycle/visibility guards,
  owner-safe refresh, mixed Draft/Publishing/Failed/Missing outcomes and navigation.
- Existing Home data is still the latest three posts. An older scheduled post
  outside that list can appear in Calendar without appearing on Home; this
  presentation change does not broaden fetching or polling.
- No API contract, schema, configuration, flags, dependencies, entitlement or
  migration change. `API.md` checked; no contract update or API deploy needed.

## Verification

- Tests first: baseline **12 passed / two expected failures** reproduce the
  missing Calendar-style layout order/inset and one-line/duplicate subtitle.
- New **eight** Home cases cover order/insets, two-line caption/no duplication,
  mixed real outcomes and one retained clock across rebuilds, unknown outcome,
  inactive/reduced/TickerMode pause and tapping existing post details.
- Six-file Home/shared/Calendar focused run: **184 passed**, 16.8 seconds.
- Evidence/tooling: `D:\PostDeeMobile\artifacts\home-publishing-feedback-20261020`.
- Optional real-Home render fixture uses bundled Thai fonts and only local
  loaders for light/dark, two activity frames, reduced motion and 320px/200% text.
  Explicit fixture run: **1 passed**, 5.6 seconds. Captures visually checked:
  `preview/home-sending-light-frame-1.png`, `home-sending-light-frame-2.png`,
  `home-sending-dark.png`, `home-sending-reduced-motion.png` and
  `home-sending-320-text-200.png` under the evidence directory.
  No HTTP or provider post is used; account/usage values are local fixtures.
- Complete Flutter suite: **2,512 passed / four optional skips**, 232.3 seconds.
  `flutter analyze`: **no issues**, 13.4 seconds (16.1 seconds including startup).
- Staging Android x86_64 debug build **12030**: passed, 165.2 seconds. This is a
  fresh build from a source snapshot matching all **650** manifest input hashes.
  Flutter 3.44.1 / Dart 3.12.1; no SDK, dependency or feature-flag change.
- APK checks passed: package `com.postdee.postdee_mobile.staging`, version
  `0.1.0-staging`, x86_64 Flutter engine, expected debug signer, signature and
  16KiB alignment. Compiled resources/kernel confirm the expected Staging
  Firebase project `project-798caf7e-85b8-45e3-af7`, existing Google client,
  API `https://postdee-api-staging.onrender.com`, Firebase auth enabled,
  mock auth/experimental AI hook/beat sync disabled and existing public billing
  configuration. The selective TikTok consent reset and remembered defaults
  remain in the compiled artifact.
- APK: **197,045,786 bytes**, SHA-256
  `c3a33d38c1c5dd3959da12f1be1632178a581608d06698b3ef1b20bbe93809b5`.
  Receipt: `apk-verification-12030.json` in the evidence directory. Preserve the
  verified prior 12029 APK separately; no device installation or restart occurs.
- Independent source review found no lost ordinary-row behavior or extra
  fetching/publishing, controller, status-gate or navigation change.
- Native active-sending/FPS and real provider acceptance are not claimed.
  No API deployment, schema migration or entitlement change is required.
- This completion note is the only documentation-only change after the immutable
  build/test source manifest; runtime, tests and preview inputs are unchanged.

## Files changed

- `apps/mobile/lib/features/home/home_screen.dart`
- `apps/mobile/test/home_publishing_motion_test.dart`
- `apps/mobile/test/home_sending_preview_test.dart`
- `README.md`, `ROADMAP.md`, `ARCHITECTURE.md`, `apps/mobile/README.md`
- This work record.
