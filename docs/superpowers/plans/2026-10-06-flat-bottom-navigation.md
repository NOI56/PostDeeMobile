# Flat rounded mobile bottom navigation

## Accepted scope

The user selected a white surface with dark text and green primary actions for
the broader app direction, and accepted the proposed order Home, Calendar,
Create post, Store link, Account. The latest request is to implement the attached
navigation reference, with a follow-up correction to dock the bar at the bottom,
remove the visible center label and use green selected states. This round changes
the bottom navigation only; it does not claim completion of the wider
Pinterest-inspired app redesign. The correction specification below supersedes
the initial floating-bar specification and its historical acceptance comparison.

The preceding approved upload icon (`Icons.ios_share_outlined`) remains the
center create-post action. Keep actual data, upload/caption/publish/schedule
flows, profile-link editing, analytics access, auth, billing, and templates.

Verified integration baseline: origin/main
`bcd7153f196cd381a786b333b9b61a67dbe95ca3`; branch
`codex/pinterest-mobile-ui` in
`D:\PostDeeMobile\.worktrees\recover-main-systems`.
Preserve the preexisting upload-icon changes and untracked artifacts, and leave
the dirty root checkout untouched.

## Current correction specification

The user supplied two comparison images after reviewing the first revision:

- `C:\Users\stopp\AppData\Local\Temp\codex-clipboard-da057780-0080-4681-b288-cef7cb1599a8.png`
- `C:\Users\stopp\AppData\Local\Temp\codex-clipboard-3045eb63-26c7-4c71-8790-b82437d4ffac.png`

Accepted correction:

- Use a full-width opaque dock to the bottom edge, including the SafeArea
  background. Remove outer gutters, outline border and outer shadow. Round only
  the top corners at 24 dp; the bottom corners are square.
- Keep an undecorated outer reference container. Position the Material surface
  from 8 dp below its top through its bottom. The control row is inside
  SafeArea (top disabled), with 12 dp horizontal padding and 84 dp height:
  the original 76 dp control layout plus 8 dp raised-action reserve.
- The solid green 44 dp upload circle translates up 8 dp from its column,
  projecting approximately 7.5 dp above the Material top while remaining inside
  the outer 84 dp layout and hit area. Keep the 25 dp upload icon.
- Hide the center Create post label visually. Retain a 15 dp spacer so the
  peripheral labels keep their baseline, and retain the localized tooltip,
  semantic label, button role, selected state and tap action.
- Selected peripheral icons, labels and the selected dot use `AppTheme.navActive`
  in light/dark mode. Inactive icons/text use readable `textSecondary`.
- Keep the five callbacks/screen indices 0, 3, 2, 1, 5, all account flows,
  `extendBody: true`, and `AppTheme.navOverlap` at 116 dp. Keep Analytics at
  index 4 without marking another navigation destination selected.
- Use a shell-local `AnnotatedRegion<SystemUiOverlayStyle>` for system
  navigation-icon brightness and status-bar contrast matching the theme. Set
  `statusBarIconBrightness` and `statusBarBrightness` as well: for shell screens
  without an AppBar, Flutter can use the bottom annotation as its fallback for
  both system bars. This avoids retaining dark status icons after switching to
  a dark background. Flutter's target SDK is 36:
  Material painted through the bottom inset supplies the system navigation
  background; a navigation-bar color property alone cannot provide this.
  No Android platform configuration or edge-to-edge opt-out is required.

Fresh remote verification still uses origin/main
`bcd7153f196cd381a786b333b9b61a67dbe95ca3` with the branch 0 ahead / 0 behind.
Existing worktree changes are preserved. The correction introduces no API,
schema, package, environment, feature flag or dependency change.

### Current correction verification

The regression `uses docked bottom navigation in the approved tab order` failed
before the correction because Create post was still visible in the navigation
(`artifacts/docked-nav-red-20261006.log`). The final tests retain its accessible
name and tap action while checking that its visible Text widget is absent.

The latest runs include the final status-bar contrast fix. The log files below
contain these completed reruns; no production code changed afterward.

| Check | Final automated correction result | Evidence |
| --- | --- | --- |
| Targeted shell and app tests | 41 passed | `artifacts/docked-nav-targeted-tests-20261006.log` |
| Complete Flutter suite | 1,128 passed, approximately 54 seconds | `artifacts/docked-nav-full-tests-20261006.log` |
| Flutter analyze | No issues, 7.6 seconds | `artifacts/docked-nav-analyze-20261006.log` |
| Staging debug APK | Build succeeded, 14.8 seconds; existing future KGP warning remains | `artifacts/docked-nav-build-20261006.log` |

The final APK was installed with `adb install -r` on `emulator-5554`, AVD
`PostDee_Pixel`, package `com.postdee.postdee_mobile.staging`. Local and installed
APK SHA-256 both equal:

`14023C225C9FDEB3B346F905C53F572049E453E69A73B12BAC142252070A4CBD`.

The earlier E08F dock APK was an interim geometry proof before the status
contrast fix and is not the final delivered build.

The Staging define file, API origin, Debug Firebase project and selective feature
flags remain the same verified configuration recorded below. The AVD runs
Android API 34; this native check is distinct from the code's target SDK 36.
Initial light mode and the existing account A / Free 0/3 state are preserved.

Interim native QA confirmed the dock geometry and all five destinations, but
switching Light to Dark exposed black status icons over the dark Home background.
The shell-local overlay now supplies both status brightness fields. Two
theme-mode `SystemChrome.latestStyle` regression checks first failed because the
status icon brightness was null
(`artifacts/docked-nav-system-icons-red-20261006.log`).

### Current final native evidence and comparison

Native checks on the exact final 14023 APK are complete. Tapping each of the five
destinations and reading fresh hierarchy XML confirms its expected page header
and exactly the corresponding selected navigation label. All eight screenshot /
XML pairs exist under `artifacts/`, with the pattern
`docked-nav-final-<state>-20261006.{png,xml}` and states:
`home`, `calendar`, `upload`, `link`, `account`, `home-dark`, `link-keyboard`,
`upload-keyboard`.

The final Calendar, Home dark and both keyboard screenshots were visually
inspected. Home, Store link, Account and Upload dock geometry had also been
visually inspected on the preceding identical-geometry build; the final build
adds the verified status-contrast correction. This does not claim separate
visual inspection of every final image. The final Home dark image confirms white
status icons after Light to Dark, correcting the observed black-on-dark issue;
the system gesture icon and selected green navigation also remain readable.
The two theme-mode system-style regression checks pass in the final suites.

Final native footer bounds (physical pixels) stay above navigation touch top
y=2117, with Material beginning approximately y=2138: uploader post ends at
y=2080 and draft save at y=2090; Store link edit ends at y=2033. With keyboards
open at approximately y=1515, Store link Next ends at y=1213, uploader post at
y=1480 and draft save at y=1491. All remain reachable. The keyboard was closed
and Home light restored. No field text, save or publish action was performed;
the account, existing drafts, connection and Free 0/3 state remain intact.
A scan of the final application's process log found no FATAL EXCEPTION,
Unhandled Exception, RenderFlex overflow or EXCEPTION CAUGHT BY entries.

| Comparison point | Latest requested correction | Final evidence |
| --- | --- | --- |
| Center label and accessibility | Hide visible Create post text, retain action meaning | No visible center label; localized tooltip and semantics retain Create post, selected state and tap action; regression passes |
| Edge attachment and surface | Full-width dock to the bottom, with no floating gap or external shadow | White light-mode surface reaches the physical bottom/system inset; rounded top only, no outer gutters/shadow; final Calendar visual and native geometry confirm this |
| Active state | Green icon, text and dot for the selected destination | Final Calendar and dark Home visuals confirm green treatment; fresh XML verifies the exact selected destination on all five routes |
| Raised upload and navigation | Raised green upload control that remains usable | 44 dp upload circle stays inside the outer hit area; all five native taps reach correct headers with the existing screen/callback mapping preserved |
| System contrast and footer clearance | Readable light/dark chrome and clear actions above dock/keyboard | Final dark status icons are white and readable; light/dark style tests pass; native footer and both keyboard bounds above confirm clearance |

The correction is verified against the latest requested reference in the
inspected Android emulator states, with localized labels and the approved green
upload icon as intentional PostDee adaptations. Native testing used Android API
34. The code targets SDK 36, but native API 36, physical Android, iOS and native
narrow-device testing were not performed; narrow layouts and enlarged text are
covered by widget regressions. Existing public-page/browser/R2 checks remain
deferred. Baseline remains `bcd7153` with 0 ahead / 0 behind, and final
`git diff --check` passes. No migration, flag/configuration change, backend
deployment, push or merge was performed. The sections below are historical
first-revision evidence only.

## First revision reference and native specification (historical)

Reference image supplied by the user:
`C:\Users\stopp\AppData\Local\Temp\codex-clipboard-69ca0201-6088-4000-988d-db891a0be696.png`.

- Opaque navigation surface: white in the light theme and the matching existing
  dark surface in dark mode. Rounded 24 dp corners, a subtle neutral border and
  soft shadow; no background blur, glow, gradients, or moving notch.
- Keep the 76 dp bar height, SafeArea and padding (20, 4, 20, 12). Keep
  `AppTheme.navOverlap` at 116 dp for existing content/footer clearance.
- Four peripheral outline icons at 22 dp. The center action uses a solid green
  44 dp circle and 25 dp upload icon, lifted 4 dp inside the bar. Keep its label
  visible.
- Selected icons and labels use primary text ink; inactive items use readable
  secondary text. A 4 dp dot below the selected label provides a second cue.
- Localized navigation labels are separate from page headings for all eight
  supported locales. Retain one accessible button label and selected state per
  item; decorative icons/dots must not duplicate announcements.
- Reorder visible buttons only: Home (screen 0), Calendar (3), Create post (2),
  Store link (1), Account (5). Keep the existing IndexedStack order and callbacks,
  with Analytics at screen 4 and no selected dot when that screen is active.

The supplied reference has generic English labels and a black center action.
PostDee uses its accepted localized destinations and green upload action. These
are intentional product-specific adaptations. Native text and icons render the
navigation; the screenshot is not shipped as a static interface.

## Compatibility and first revision verification (historical)

No API contract, Prisma schema, entitlement, provider, dependency, credential,
feature flag or publication rule changes are required. API.md was reviewed and
does not need an edit. Existing user-scoped draft/publication boundaries remain.
No migration or backend deployment is required for this navigation revision.

Tests were added first. The old navigation failed the approved-order test because
the Store link destination label was missing. A separate accessibility regression
failed because the excluded child InkWell did not provide a tap action on the
outer button semantics. The final Semantics node explicitly exposes `onTap`;
the test checks label, button role, selected state and tap action for every
destination. Existing routing, deletion, calendar, uploading and profile-link
behavior assertions remain in place.

Recorded first-revision results (2026-10-06, paths relative to the canonical
worktree); these do not verify the later dock/hidden-label correction:

| Check | Result | Evidence |
| --- | --- | --- |
| Targeted shell, app, localization and widget tests | 50 passed | `artifacts/flat-nav-targeted-tests-20261006.log` |
| Complete Flutter suite | 1,127 passed, approximately 59 seconds | `artifacts/flat-nav-full-tests-20261006.log` |
| Final Flutter analyze | No issues | `artifacts/flat-nav-analyze-20261006.log` |
| Final shell navigation semantics regression | 1 passed after test-only matcher migration | `artifacts/flat-nav-semantics-final-test-20261006.log` |
| Staging debug APK | Build succeeded | `artifacts/flat-nav-build-20261006.log` |

After the full suite, analyzer feedback prompted a test-only migration from the
deprecated `containsSemantics` matcher to `isSemantics`. The final affected shell
test was rerun and passed, and final analyze reports no issues. No production
code changed after the full suite. The build reports an existing future Kotlin
Gradle Plugin migration warning in the FFmpeg, Firebase Analytics and purchases
plugins; this change modifies no dependency or build configuration.

Responsive widget regressions pass at 360, 393 and 411 dp widths with 1.45x and
2.0x text settings, including label containment and button targets at least
44 dp. These are widget checks, not native narrow-device testing.

The final diff contains only the two mobile library files (shell and
localization), four directly related test files and documentation. No route,
business flow, account scope, environment configuration, dependency, asset or
feature flag was changed or removed. Main and origin/main remain at the verified
baseline with 0 ahead / 0 behind; the dirty root checkout is untouched.

Push, merge and deployment are not part of this round unless separately
authorized. Saved Staging/Cloudflare browser access blocks remain deferred; this
navigation change does not claim new acceptance of those external checks.

## First revision delivery evidence (historical)

Changed files:

- `apps/mobile/lib/features/shell/postdee_shell.dart`
- `apps/mobile/lib/core/localization/postdee_localizations.dart`
- `apps/mobile/test/postdee_shell_test.dart`
- `apps/mobile/test/app_test.dart`
- `apps/mobile/test/widget_test.dart`
- `apps/mobile/test/postdee_localizations_test.dart`
- `README.md`, `ROADMAP.md`, `ARCHITECTURE.md`
- `docs/superpowers/plans/2026-10-06-flat-bottom-navigation.md`

The exact Staging debug APK was installed with `adb install -r` on
`emulator-5554`, AVD `PostDee_Pixel`, retaining application data. Local APK and
installed `base.apk` SHA-256 both equal:

`9255734113D668FCF97370CA4E691ED32FCB23DC3A03280A61E3858079A36D69`.

Verified delivery environment:

- Package: `com.postdee.postdee_mobile.staging`.
- Define file: `D:\PostDeeMobile\apps\mobile\staging.local.json`.
- API origin: `https://postdee-api-staging.onrender.com`.
- Android Debug Firebase project: `project-798caf7e-85b8-45e3-af7`.
- Firebase authentication enabled, RevenueCat disabled, experimental flags
  disabled, matching the existing Staging configuration.
- Existing avatar/account A and Free 0/3 state remain. One YouTube connection,
  the existing store-link draft and local publish draft state (0 drafts) remain.

Native interactions reached all five correct screens. Screenshots and fresh UI
hierarchy XML are retained under `artifacts/` with the following basenames and
extensions `.png` / `.xml`, except Home dark, which has `.png` only (the initial
startup hierarchy dump failed; native inspection used the retried screenshot):

- `flat-nav-home-dark-20261006`
- `flat-nav-home-light-20261006`
- `flat-nav-calendar-20261006`
- `flat-nav-upload-20261006`
- `flat-nav-link-20261006`
- `flat-nav-account-20261006`
- `flat-nav-link-keyboard-20261006`
- `flat-nav-upload-keyboard-20261006`
- `flat-nav-home-final-20261006`

The reference and final Home (light/dark), Calendar, Upload, Store link, Account
and keyboard screenshots were inspected through native Node image emission because
`view_image` returned a 1 px rendering in this environment. This is Flutter
Android UI, so native emulator screenshots and hierarchy-based interactions
replace browser testing for the changed surface.

Native footer bounds remain clear of the navigation top at physical y=2106:
the uploader post action ends at y=2059 and the store-link edit action at y=2033.
In the store-link keyboard screenshot, Next ends at y=1213, above the visible
keyboard area beginning approximately y=1515. It remains reachable; no field
text was edited during this check.

The empty uploader caption was focused without changing its text. The sticky
post action ends at y=1480, above the keyboard beginning approximately y=1515.
The keyboard was then closed and Home selected. The final UI hierarchy marks
Home selected and clickable, and the other four destinations unselected and
clickable. All navigation button bounds are 200 physical px tall (about 76 dp)
and 190–191 px wide, exceeding 44 dp touch targets. A current-process runtime
log scan matched no FATAL EXCEPTION, Unhandled Exception, RenderFlex overflow
or EXCEPTION CAUGHT BY entries.
Parsed saved hierarchy XML for all five destinations confirms exactly the
expected selected label on each screen.

The first revision left the emulator on Home in light mode for review of the white
reference; its initial dark mode was also verified. Existing account/data remain;
native QA did not publish, save, or alter field text.

## First revision reference comparison (historical)

| Comparison point | Supplied reference | Native result and intentional adaptation |
| --- | --- | --- |
| Bar shape and surface | Opaque white bar with soft rounded corners | White opaque light-mode surface, 24 dp corners, neutral border/shadow; existing dark-mode surface remains supported |
| Icon treatment | Thin outline peripheral icons | Four native outline icons at 22 dp; no raster icons or screenshot shipped as UI |
| Center action | Solid black circular flame action | Accepted PostDee solid green 44 dp upload circle with 25 dp upload icon, inside bar bounds; no glow or gradient |
| Destinations and copy | Generic English fitness destinations | Accepted Thai order `หน้าหลัก · ปฏิทิน · สร้างโพสต์ · ลิงก์ร้าน · บัญชี`, with dedicated labels for all eight locales and unchanged screen headings |
| Selected state | Darker bold active label and dot below | Primary-ink selected icon/label and 4 dp dot; Home, Calendar, Upload, Store link and Account dots appear in the corresponding first through fifth slots; semantics expose actual selected state |
| Content clearance | Distinct content/navigation area | Original 76 dp bar, safe area and 116 dp overlap reserve retained; native uploader/store-link actions remain above the bar |
| Interaction and secondary flows | Reference shows navigation appearance | Real callbacks still select screens 0, 3, 2, 1, 5; Analytics screen 4 remains available with no misleading selected dot |

Visible navigation copy differs intentionally from the reference's generic
English labels to the accepted localized PostDee destinations. Existing page
headings, customer data, plan state, loading/errors and actions are retained.
The black flame becomes the accepted green upload icon; the 76 dp native bar
and existing safe-area allowance preserve readability and footer compatibility.
These are product-specific adaptations, not invented feature or metric content.

This table records the first implementation's comparison. Subsequent user review
identified a dock/center-label/selected-color mismatch and requested the correction
specified above. The old screenshots, APK hash and checks do not verify the new
revision. Physical
Android and iOS device checks and native narrow-device checks were not performed.
Existing deferred public-page/browser/R2 checks remain outside this navigation
revision. No push, merge, backend deployment or database migration was performed.
