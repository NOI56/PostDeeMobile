# Bottom navigation finite UI motion

สถานะ: LOCAL COMPLETE — final frozen source passes tests/analysis; exact Staging
x64 APK 4015/8015 is installed and safe native navigation verified. No new
commit/push/deploy or main merge; prior Shop/Account server release stays unchanged.

## Accepted scope and baseline

ผู้ใช้ขอเพิ่มลูกเล่นให้แท็บด้านล่างจากภาพ dock ห้าเมนูปัจจุบัน ใช้ลูกเล่นสั้น
เพื่อบอกว่าเลือกแท็บไหนและตอบสนองการกด โดยรักษาระบบเดิมและไม่เพิ่มข้อมูลใหม่

Root fresh-fetch baseline: worktree
`C:\Users\stopp\.codex\worktrees\audit-system-fixes\PostDeeMobile`, branch
`codex/audit-system-fixes`, HEAD
`0e8d797bf95a7b07de8c34eed7de22e0092f66a3`; origin/main and merge-base
`c4e52201a58b556f5f47529027549a2fc16af84c`, 27 ahead/0 behind, remote feature
matches. Three preexisting Windows generated-plugin changes remain excluded.
Prior combined feature source `904a3f89c3601a1fac28eedfaf8781434b19bd49` is Live
through `dep-db66eh8473hc73dabfcg`, with documentation receipt `0e8d797`.
At baseline, installed Staging APK 4014/8014 and 126-lib source manifest
`2B7E4D05D08AE00099F97288A28C5F2751A248F32EFC70EFAC72CA942B992403`
are the preceding release, not verification of this new motion.

Read before patch: current `PostDeeShell` navigation, `_PostDeeBottomNav`,
`_RunningNavDot`, native `InkWell`/semantics and center press feedback; existing
shell navigation/owner/composer/reduced-motion/RTL/large-text tests; the prior
2026-10-06 flat-bottom-navigation plan and current five shared documents.

## Presentation changes

- Keep the finite 260 ms running dot, including rapid-tap retargeting, RTL and
  absence for Create post/Analytics.
- Four ordinary icons use a selected 36 dp mint halo at .12 alpha without
  shadow, finite 220 ms scale to 1.08/lift by two pixels and gray-to-green color.
  Native press affects the icon only: .9→1 over 80/180 ms.
- Retain the center solid green action, 44 dp surface/25 dp upload icon,
  hidden visible label with localized tooltip/accessibility name, no selection
  dot and existing 80/180 ms pulse. Add safe mounted/disposal handling.
- Reduce-motion/lifecycle/parent-`TickerMode` guards settle motion, including
  changes mid-flight, and do not replay stale animations when reactivated.
  Keep native gestures/feedback operational; add no looping effects.

## Capabilities preserved

Keep visual order Home → Calendar → Create post → Shop link → Account and
existing shell indices 0/3/2/1/5. Keep full-width opaque safe-area dock, rounded
24 dp top corners, 84 dp controls, stable tap target/semantics, `extendBody` and
116 dp content-overlap allowance; no external shadow or floating frame.
Create post remains one guarded `/create-post` route above the shell, with no
hidden uploader, previous-tab return, owner-change closure and existing
Calendar/Home/draft/publishing callbacks. Analytics remains secondary index4
without a selected dock dot. Retain owner-scoped state, existing subscription,
connections, local drafts/autosave and all screen/business actions. Presentation
adds no API request/persistence trigger/business callback, package rule, schema,
configuration, dependency, backend change or migration. Public pages unchanged.

## Verification and inventory

Tests first in `apps/mobile/test/postdee_shell_test.dart`; runtime change only
`apps/mobile/lib/features/shell/postdee_shell.dart`. Check selected/press
geometry and stable semantics/hit targets, rapid taps, reduced motion,
background/parent-ticker mid-flight settling/no replay, safe held-press disposal,
RTL/large-text layout, composer exclusion and existing owner/navigation flows.
Targeted new cases, the full Flutter suite, analysis and exact Staging split x64
helper build passed on the frozen source below, with package/environment verified
before native QA.

Native QA remains safe navigation/browsing/open-and-close only. Do not save,
edit links/apply themes, publish, invoke AI/OAuth, purchase, delete or sign out.
Positive business/mutation and reduced-motion/background/accessibility paths
can use controlled fixtures; do not claim them as real native success.

Final inventory: eight intended files, plus three preserved/excluded preexisting
Windows generated-plugin changes. Runtime: `apps/mobile/lib/features/shell/postdee_shell.dart`;
tests: `apps/mobile/test/postdee_shell_test.dart`; docs: `README.md`, `ROADMAP.md`,
`API.md`, `ARCHITECTURE.md`, `apps/mobile/README.md` and this plan. Runtime diff is
201 insertions/42 deletions limited to navigation classes; no unexpected deleted
files. Baseline remains 27 ahead/0 behind main. Prior Staging deployment is not a
deployment of this new feature; no external release action was requested.

## Final local receipts (2026-10-12)

- New navigation widget cases: **13/13 passed, 7 s**, exit0,
  `D:\Temp\postdee-bottom-nav-motion-green-20261012.log`. The first runtime run
  caught an unused lazy center controller being created during disposal; eager
  initialization fixes it without changing business callbacks. Read-only semantic
  review accepted scope. Motion/guard/accessibility checks are controlled fixtures.
- `flutter analyze`: **No issues, 11.1 s**, exit0,
  `D:\Temp\postdee-bottom-nav-analyze-20261012.log`.
- Full `flutter test`: **1,979/1,979 passed, 2 m 18 s**, exit0,
  `D:\Temp\postdee-bottom-nav-full-20261012.log`.
- All126-lib runtime manifest SHA256 (relative mobile path:SHA rows, sorted/LF):
  `27EB7DE65D9E7D3E0E04088354EB0E53C764CD5311A4CEDCA081E8296DBB820D`,
  unchanged after build. Prior 126-lib `2B7...`/8014 is baseline history only.
- Exact Staging helper build **66.4 s total /59.4 s Gradle**, exit0,
  `D:\Temp\postdee-bottom-nav-build-8015-20261012.log`, build-number4015,
  split-per-ABI/android-x64. Delivered `app-x86_64-debug.apk` SHA256
  `7EF08409A6758703F2D75B3779B789427D04A07B5EB5791927842380A9871EBE`.
  Package `com.postdee.postdee_mobile.staging`, versionCode8015/
  versionName`0.1.0-staging`, x86_64 only, activity
  `com.postdee.postdee_mobile.MainActivity`; unchanged signer SHA256
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  Helper validated the canonical ignored RevenueCat TestStore overlay with SDK
  key hidden; Staging API/FirebaseAuthtrue/localmockfalse/Staging badge and
  Firebase project remain unchanged. No credentials copied/configuration changed.
- `adb install -r` **Success** at **18:41:20 GMT+7**, no downgrade/data clear;
  installed8015 confirmed, firstInstallTime`2026-10-05 06:30:36` unchanged.
  Native login retained: HomeFree0/3, connections0/4; Calendar empty0; Shop
  published noikub2/20 with original Shopee/YouTube links; AccountFree0/3,
  connections0/4. All four ordinary tabs show the selected mint halo/green icon/
  dot correctly. Center opens one empty clip-step composer with dock hidden;
  closing returns to previous Account with restored halo/dot, then Home.
  Final actual Home8015 remains displayed; unmodified native Home screenshot:
  `C:/Users/stopp/.codex/visualizations/2026/10/12/01a12dc1-f51c-7ec2-9a95-f89a5069c32c/bottom-nav-motion-8015.jpg`.
  Fresh-state recovery handled user
  window interference without acting on the wrong app.
- No native edit/save/theme Apply/AI/OAuth/publication/purchase/delete/signout.
  Positive business/mutation and reduced-motion/background/ticker/large-font/
  disposal paths use fixtures. Recent PID16550 log: **0 critical hits/131 lines**
  at **18:44:02 GMT+7**.
- Existing backend `/health` and `/ready` HTTP200 with database/queueok at
  **18:38:18 GMT+7**, still prior `904a3f8`; this is availability, not new deployed
  source proof. No backend/schema/config/dependency change, new backend suite or
  migration execution; no new commit/push/deploy or main merge for this feature.
