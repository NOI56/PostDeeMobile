# Shop-logo positioning: main delivery (2026-10-13)

Status: final mobile verification and Staging Emulator delivery completed;
user-authorized main integration uses the commit carrying this receipt.

## Scope and baseline

The user authorizes moving the tested logo-positioning work into main. Canonical
checkout is the existing grouped-account-ui main worktree. Local HEAD and freshly
fetched origin/main agree at `17e880d8bc0c6c690c4f66daf7718954db790f28` with zero
ahead/behind. Port only the five logo source/test files already implemented on
this baseline, plus related documentation. Preserve unrelated generated Windows
files, local artifacts and the original dirty `D:/PostDeeMobile` checkout.

The earlier security delivery remains intact: session generations, owned modals,
draft serialization/image protection, explicit publication and all existing
templates. This mobile change adds no API field, database migration, dependency,
credential, entitlement or provider integration. It needs no API deployment.

## Behavior and review fix

- Both shop information and decoration use a circular preview with drag,
  pinch/slider zoom from 1 to 4 and reset-to-center.
- Preview and square PNG export share a source rectangle. Export is capped at
  512 pixels per side, then passes through the existing PNG normalizer and
  owner-scoped upload flow. Cover/background image selection is unchanged.
- Confirmation is required before upload; cancel retains the previous logo and
  unsaved draft settings. Account changes close the owned dialog and reject late
  results. Rapid taps open only one picker.
- Pre-push review finds an asynchronous export race: a dismissed dialog can
  remain mounted during reverse animation, allowing a late Navigator.pop to
  close the appearance editor below it. Capture its ModalRoute before awaiting
  export and check mounted plus route.isCurrent on both success and error.
  Keep the cloned image alive until export finishes and dispose it in finally.
- A controlled pending exporter reproduces the issue before the guard
  (editorClosed incorrectly becomes true), then passes with the guard. Production
  keeps the original exporter; only tests inject the controlled future.

## Verification

- Regression first: the dismissal-during-export case fails against the old
  mounted-only guard, then passes after the route guard.
- Targeted three-file suite: 32 tests pass, including crop pixels/bounds,
  cancellation, retained draft media, decoration, account changes, duplicate taps,
  narrow layout and large text.
- Final `flutter analyze --no-pub`: exit 0, No issues found (11.6 seconds).
- Final `flutter test --no-pub --reporter expanded`: exit 0, all 2,185 tests
  pass (3 minutes 47 seconds), adding 14 cases over the 2,171-test baseline.
  All five source/test SHA256 hashes match before and after verification/build.
- Initial verification on C: Temp encounters OS errno 112 (disk full), so that
  incomplete run is not a passing full-suite result. Final verification uses
  dedicated temporary files on D: without deleting user data.
- Installed predecessor APK12018 is byte-identical to its local build with
  SHA256 `b17297e9638e5b1bdcc6697ddf80ae527de8bbd47ff9cb4dbe16fc1cb1a5a610`.
  Its debug kernel contains the original two logo runtime sources exactly. It
  predates the route-guard fix and does not certify the final main source.
- Final Staging x64 build with helper build-number8019 (ABI versionCode12019):
  exit 0, assembleDebug succeeds in 157.9 seconds. Package is
  `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`, Firebase project
  `project-798caf7e-85b8-45e3-af7`, Staging API, Firebase auth on/local mock off,
  and the existing ignored RevenueCat Test Store overlay (key not retained).
- APK SHA256: `cd7551ef370c15df922c872212ccfc623a5a3e3afcda8fa10eb61008293a0d8f`.
  Canonical build and D: build-output APK files match. Signature verification
  passes with retained signer SHA256
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  Debug kernel contains both final logo runtime sources exactly. Their staged
  Git blobs match the files verified and built: screen
  `1434e41b9a7619b5bf39467d7f9b065b315c6b7c` and crop
  `b4882737b69d695e35bf85c1163817f2db3d19c8`.
- `adb install -r` succeeds for12019 without uninstall, clear-data or storage
  threshold changes. Package metadata confirms12019 and the retained first
  install time. Installed base.apk SHA256 matches the final built APK above.
- Safe native Home → Shop → information checks retain the existing shop name,
  slug, logo and two links. Gallery selection opens crop; slider zoom changes
  from1.0 to2.8, dragging moves the image, reset restores1.0 and cancel returns
  with the original logo and draft fields. No upload/publication is performed.
- All six unrelated generated Windows/artifact files retain their original
  SHA256 hashes and remain outside this commit.

Local detailed logs and APK receipts are retained under
`D:/PostDeeMobile/.tmp/logo-main-delivery`; do not commit account screenshots,
local credentials, APK files or unrelated artifacts.

## Delivery and limits

The delivery commit contains only five mobile source/test files and six related
documents. Main is freshly verified against the baseline before committing;
use an ordinary non-force push and verify remote main against the resulting
commit. Its exact SHA is recorded by Git history. `[skip ci] [skip render]` avoid
an automatic Production deployment; local tests/build provide the recorded
verification and no new CI run is claimed. No Production resume/deploy and no
Staging API redeploy are part of this mobile-only delivery.

Native confirmation/upload/publication against live account data is not added
by these fixture regressions. Preserve the preceding deployment receipts and
their outstanding provider/billing/OTP acceptance checks separately. Full real
social publishing remains a later controlled end-to-end task.
