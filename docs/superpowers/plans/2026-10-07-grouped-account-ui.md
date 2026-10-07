# Grouped mobile Account screen — 2026-10-07

## Accepted direction

The user selected Pinterest option 2, a compact profile header and clearly
grouped settings: https://in.pinterest.com/pin/818529301071282919/.
Use the existing white/light-gray PostDee palette with green accents and retain
the dark palette. Scope is the Account tab only.

## Baseline and isolation

- Verified remote `main`: `bcd7153f196cd381a786b333b9b61a67dbe95ca3`.
- Feature baseline: `630e20a097b3929f7749b6684d927b62d6ba5532`, zero commits
  behind and sixteen ahead of `origin/main` after a successful fetch.
- Worktree: `C:/Users/stopp/.codex/worktrees/grouped-account-ui/PostDeeMobile`.
- Branch: `codex/grouped-account-ui`.
- Account edits were isolated after another task began changing template files
  in the previous integration checkout. Those edits and the separate post
  wizard checkout are preserved and are outside this delivery.

## Resulting behavior

1. **บัญชีของฉัน**: compact profile with an explicit edit label, email status,
   and the existing phone verification action.
2. **ช่องทางและเครื่องมือ**: a single live connection count in the connection
   row, caption templates, and profile links.
3. **แพ็กเกจของฉัน**: show only the server-reported current plan and available
   quota. Keep loading/error/retry states; never assume Free when data fails.
   All plans remain available through the existing paywall. Store membership
   management has its own row.
4. **ตั้งค่าและช่วยเหลือ**: language and display mode are short rows opening
   selection sheets. Security, help, privacy, and terms remain reachable.
5. A clearly named logout action sits at the bottom, separate from account
   deletion. The original deletion confirmation and subscription warning remain.

Rows use outline icons, thin dividers, rounded white groups and generous tap
targets. Values move under labels with large text. Sheets scroll on small
screens. Existing controllers, authentication, OAuth validation, stale-request
protection, profile draft undo and billing flows remain wired.

## Contract and release impact

`API.md`, `ARCHITECTURE.md`, `README.md`, and `ROADMAP.md` were checked. This is a
mobile presentation change: no API, schema, entitlement, price, provider,
dependency or feature-flag change; no database migration or API deployment is
required. The 100-logo and 100-template systems at the baseline are retained.
Publication and staging deployment are not authorized by this selection.

## Verification

Regression tests were updated before implementation. The new group/current-plan
test failed against the earlier UI. Targeted Account, profile editing and app
navigation tests passed: 49 tests. The final isolated-worktree Flutter suite
passed 1,426 tests; `flutter analyze --no-pub` reported no issues. Diff validation
passes. Auth/loading, stale-response protection, legal/help content and account
deletion confirmation were also compared against the baseline and preserved.
Native visual inspection found that loose flex values shifted setting arrows
away from the right edge. A regression test reproduced the 243dp gap; values
are now width-bounded beside an expanded label, keeping arrows at the same
right padding as other rows. This fix is covered by the final full suite.

The real Staging APK builds with the existing `staging.local.json`: package
`com.postdee.postdee_mobile.staging`, API
`https://postdee-api-staging.onrender.com`, Firebase project
`project-798caf7e-85b8-45e3-af7`; Firebase Auth enabled, local mock auth disabled,
RevenueCat billing and experimental beat-sync/AI-hook disabled. It was installed
and launched on a new, separate Android API-34 QA emulator. The installed APK
hash matched the saved file. The original signed-in emulator was not modified.
The final saved Staging APK SHA-256 is
`db2ce9cd9688aa75904cd7fa14682e6fa7c395a06a5380ea2f80dba8a03fe0c8`.
Final APK build and full tests passed after the arrow-alignment correction.
Generated Android build output was moved to
`D:/PostDeeMobile/artifacts/grouped-account-build`, with a junction at the
worktree's normal `apps/mobile/build` path, after C: ran out of space. No user
data, shared emulator or project configuration was moved. A visual-preview
Flutter run hit host memory pressure; building its APK with the QA emulator
stopped succeeded. These were host resource failures, not UI test failures.

The QA emulator has no signed-in real account. `tool/account_ui_preview.dart`
renders the actual ProfileScreen with fictional local data for visual checks;
its API reads are fakes, not verified live subscription/social data. It does
not call the production Dart authentication bootstrap or enable publishing/deletion.
Android's native Firebase providers still initialize with the Staging configuration.
Never distribute its APK as the app. Native authenticated Account access still needs a signed-in-user
check before release; widget tests cover those routes with controlled fixtures.
No real account deletion, purchase, phone OTP or social connection mutation was
performed.

The first saved preview APK lacked the Dart kernel/snapshot assets, so launching
it directly stayed at the Android splash screen with no main Dart isolate.
The saved main Staging APK contains those assets. Rebuilding the preview with
the full Android target set produced all three required Dart runtime assets;
the rebuilt preview SHA-256 is
`157b976407bb8a93b9b8545f835c2824e5213a81c91895a7bdde61f419ad2f0f`.
It rendered successfully on Android API 34 at 1080×1920 / 420dpi. Native checks
confirmed the aligned arrows, light/dark choice sheet, language choice sheet,
Thai/English setting change, and separate logout/deletion controls. No overflow
was observed in these default-text captures; narrow-screen/large-text behavior
is covered by the widget regression tests.

Final screenshots are saved under
`C:/Users/stopp/.codex/visualizations/2026/10/07/01a115cb-9d62-7722-8fa5-1494b0f29e4b`:
`account-grouped-final-top.png`, `account-grouped-final-settings.png`,
`account-grouped-dark.png`, `account-grouped-english.png`,
`account-theme-sheet.png`, and `account-grouped-bottom.png`.
These show the actual Flutter screen with explicitly fictional account,
connection and package data. The QA emulator was then returned to the saved
main Staging APK, whose installed hash again matched the final saved file.
The main APK reached its Google/email sign-in screen with default Impeller
rendering. This verifies launch and the unauthenticated entry screen, not a
successful real sign-in or authenticated live Account data.
