# Mobile UI Refresh Implementation Plan

> Navigation update (2026-10-05): the second tab is Profile link. Home has one
> profile-link shortcut above analytics. AI editing and Subtitle Studio no
> longer have an active entry; uploader AI captions and other tabs remain.

> **Document status:** historical execution record. The current app uses the
> light theme by default and later approved screen designs supersede the
> ultra-dark direction described below. Unchecked boxes are not current product
> TODOs; use `README.md`, `ROADMAP.md`, and the current Flutter screens for the
> active UI.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the Flutter mobile app into the approved Thai ultra-dark creator UI while preserving the current backend, auth, billing, upload, caption, template, and analytics behavior.

**Architecture:** Keep the existing feature screens and service classes. Improve shared visual primitives first, then refresh one screen per round so every change can be tested and viewed on the Android emulator. Templates move out of the main bottom navigation only after a Profile entry point exists, so no existing feature disappears.

**Tech Stack:** Flutter, Dart, Material 3, existing PostDee API client, Flutter widget tests, Android Emulator Pixel_8.

---

## Current Addendum: Full-Screen Create Post (2026-10-07)

This addendum supersedes the long, simultaneous uploader form and its separate
pre-publish review route. The historical steps below remain an execution record,
not a direction to restore the old dark UI or removed editing entry points.

**Status:** the initial four-step implementation and approved navigation-clarity
follow-up are verified. The latest Staging APK is installed on the Android
emulator with the existing account preserved. The user has authorized push and
Staging deployment; the delivery record below tracks the exact candidate and
remote verification separately from the earlier local checks.

**Baseline:** isolated `codex/post-create-wizard` worktree at
`fc087c4119cd46503c569879e61cddf99e402fb2`, from the verified current integration
branch. Verified `origin/main` and merge base are
`bcd7153f196cd381a786b333b9b61a67dbe95ca3`; baseline is 0 behind / 15 ahead.
Existing 100 profile logos, 100 profile templates and prior systems are retained;
uncommitted work in the original integration worktree is not overwritten.

The user chose the combined Pinterest 1 + 2 direction, four separate steps,
full-screen composition and manually requested AI. The selected implementation
uses a small local poster opening a full-screen local player; draft saving stays
explicit, with continue/discard/save-and-exit choices for a changed form.

The navigation-clarity follow-up uses the existing step heading to show
`ขั้นตอนที่ N จาก 4 · <ชื่อขั้นตอน>` and names the next destination in each bottom
Next button. Valid previous steps show a check; directly jumping ahead with
empty input must not invent completion. Progress buttons retain optional
shortcut navigation and expose the current/completed state to accessibility
services. Narrow-screen and large-text checks must cover the longer labels.

1. **Clip:** choose a real device file, inspect the poster or local player,
   change the clip, optionally edit its cover, and open secondary EP tools.
2. **Caption:** a large text field with the selected clip nearby; AI assistance
   and saved caption templates open as secondary groups. AI does not run when
   selecting a clip or moving between steps.
3. **Destinations:** select connected accounts explicitly and complete the
   existing per-platform settings. Unknown connection status, missing account
   identity and incomplete settings remain blocking states.
4. **Review and send:** choose now or a future time, inspect the reusable inline
   summary, edit the original steps, then confirm once. No duplicate review
   route precedes the unchanged publishing progress/result flow.

`UploaderScreen` retains one state/controller owner across steps and guards late
AI/poster results. `PublishReviewSummary` owns content only, with optional edit
callbacks and `showSchedule: false` when the surrounding schedule panel already
shows the timing. The standalone review wrapper remains compatible. Shell entry
`/create-post` hides the dock, guards duplicate opens and stale route callbacks,
and closes composer/child routes when the authenticated owner changes. Calendar
uses the same entry and retains its previous state when the composer closes.

Keep existing 9:16 checks, future/30-day scheduling limits, Basic phone and
package gates, paid AI rules, cover/watermark cleanup, per-user local draft
copies, automatic pre-submission persistence, stable request ID retries and
truthful queued/partial/provider-draft results. TikTok remains inbox draft,
Facebook remains Page Video with publish/page-draft choices, and YouTube's
required visibility/compliance settings remain explicit. No provider mapping,
endpoint, request/response contract, schema, flag, price or entitlement changes;
no database migration is required.

Implementation areas: shell routing, uploader wizard, local video preview,
reusable review summary and related Mobile regression tests. Verification status:

- [x] Test-first regression cases and the reusable summary implementation.
- [x] Targeted review tests: 19/19 passed, including wrapper confirmation,
  no duplicate confirmation, provider/account checks and 320 dp / 200% text.
- [x] Targeted shell tests: 30/30 passed, including no hidden uploader, duplicate
  open guard, full-screen close/return, Calendar state/refresh, stale callbacks,
  owner changes and the existing auth/navigation/accessibility flows.
- [x] Complete combined targeted regressions and inspect the final baseline diff.
- [x] Full Flutter suite and analysis on the final combined implementation.
- [x] Exact Staging debug build, environment/package verification and native
  smoke/visual checks preserving existing account/data.
- [x] Record actual delivery state and remaining provider/device limits.

Initial four-step verification on 2026-10-07:

- `flutter test --no-pub --concurrency=2 --reporter expanded`: 1469/1469 passed.
  `flutter analyze --no-pub`: no issues. Final log names are
  `post-wizard-full-test-final-verified.log` and `post-wizard-analyze-verified.log`.
- AI regression cases cover obsolete frame extraction/uploads/retries, owner
  and clip changes, manual edits, and an old completion not unlocking a newer
  request. Local player and exit/draft tests cover lifecycle, timeouts, errors,
  retry, unsaved changes and save failure. Existing publishing business tests
  remain enabled; the suite also covers the retained profile systems.
- `flutter build apk --debug --no-pub` used the existing `staging.local.json`.
  APK package is `com.postdee.postdee_mobile.staging`, Firebase project is
  `project-798caf7e-85b8-45e3-af7`, and API base is
  `https://postdee-api-staging.onrender.com`. Firebase auth is enabled, local
  mock auth/RevenueCat billing/experimental beat sync/AI hook are disabled.
  Build log: `post-wizard-staging-build-verified.log`.
- Installed with `adb install -r` on `PostDee_Pixel`, Android API 34. Built and
  installed APK SHA-256 both equal
  `de62319dbe11bd6fc4f067c50da9fe517b17ee62600e7d8ff20835aaf04557e1`.
  The existing logged-in account and Free entitlement remained available;
  the existing YouTube connection loaded from Staging.
- Native smoke/visual checks: fullscreen entry without dock, four steps and
  back navigation, real local poster and full-screen video playback, manual
  caption, saving/exiting and restoring the copied clip/caption across an APK
  update, destination selection and required YouTube settings, real account
  identity/private visibility in review, and disabled confirmation when no
  destination is selected. Screenshot names start `postdee-wizard-final-`.
- Baseline diff review found no deleted files or changes to backend/schema/
  configuration/catalog assets; 100 logos and 100 profile templates remain.
  Fresh `origin/main` is still `bcd7153` (0 behind / 15 ahead before these local
  changes). No database migration is required. Native QA did not send a real
  social post, invoke paid AI, or verify iOS hardware. Provider outcomes, AI
  rules and scheduling gates are covered by regression tests, not a new live
  provider publishing run. Earlier interrupted/resource-limited attempts are
  superseded by the successful final logs above.

Navigation-clarity follow-up verification on 2026-10-07:

- Added `uploader_wizard_navigation_cues_test.dart` test-first: 6/6 passed.
  Cases cover all four headings and destination labels, truthful previous-step
  checks, empty shortcuts, accessibility button/current/completed semantics,
  retained clip/caption/channel input, cleared captions, missing account
  identity, and 320 dp / 200% text without overflow or unintended submission.
  Final targeted log: `post-wizard-navigation-cues-verified.log`.
- Full Flutter suite: 1474 passed / 1 failed. The only failure was Windows
  locking a temporary fixture during teardown of the existing legacy upload
  deadline test, not a failed behavior assertion. The complete deadline test
  file was rerun sequentially with task-specific TEMP/TMP on D: and passed 8/8,
  including that case. Logs: `post-wizard-cues-full-test.log` and
  `post-wizard-cues-deadline-rerun.log`. Do not describe this as a single clean
  1475/1475 full-suite run.
- `flutter analyze --no-pub`: no issues; log `post-wizard-cues-analyze.log`.
  Read-only review found the destination/confirmation gates unchanged and the
  documentation consistent with the implementation.
- Exact Staging build with the same `staging.local.json` passed; final log
  `post-wizard-cues-staging-build-verified.log`. Package, Firebase project,
  API base and flags remain the Staging values recorded above. No source, SDK,
  API, schema, dependency, package rule or flag changed during build recovery.
- C: ran out of space during earlier verification. Only this worktree's
  generated build directory was relocated to the task artifact directory on
  D: with a junction. A subsequent APK lacked the three debug runtime assets
  and opened only the native logo. Mixed old/new output paths in Flutter's
  cache were consistent with an alias cleanup after this relocation. Repeating
  the same build regenerated the missing assets; their presence and nonzero
  contents were checked in both intermediate output and the final APK before
  reinstalling. Final kernel is 66,800,224 bytes; VM and isolate snapshots are
  13,646 and 11,093,091 bytes. The earlier incomplete APK is superseded.
- Installed with `adb install --no-streaming -r` on `PostDee_Pixel`, Android
  API 34. Final built and installed APK SHA-256 both equal
  `b6715f7d42ff29928f0fb88869b0a13d13ad32cea0da7cfbaf8b7efcb050b5f0`.
  Cold launch reached Home with the existing authenticated account, Free
  entitlement and existing YouTube connection available. Installation log:
  `post-wizard-cues-native-install-verified.log`.
- Native checks confirmed all four step headings, all three named Next labels,
  real clip selection, previous clip/caption checks, the unchanged Next gate
  when no destination is selected, optional shortcut navigation, disabled final
  confirmation with no destination, and retained clip/caption after going back
  from Review. Screenshots: `postdee-wizard-cues-step1.png`,
  `postdee-wizard-cues-caption.png`, `postdee-wizard-cues-platforms.png`, and
  `postdee-wizard-cues-review.png`. No post, paid AI call or draft save was
  triggered by this follow-up QA. After the exit prompt the device changed to
  Account outside the QA actions; further taps stopped to avoid interrupting
  live use, so draft/discard actions by that interaction were not verified.
- Updated README, ROADMAP, ARCHITECTURE and this plan; checked the existing API
  presentation record without another contract change. No database migration
  is required. No push/deploy, live provider publishing or iOS hardware check
  was performed in this follow-up.

---

## Staging Delivery Preparation (2026-10-07)

- Delivery uses the clean `codex/post-create-wizard-staging` worktree based on
  freshly verified `origin/codex/pinterest-mobile-ui` at
  `630e20a097b3929f7749b6684d927b62d6ba5532`. That baseline includes the latest
  100-template delivery documentation, and is 0 behind / 16 ahead of
  `origin/main` at `bcd7153f196cd381a786b333b9b61a67dbe95ca3`.
- Ported only the 22 composer/navigation-cue source, test and documentation
  paths. Concurrent Account edits in the original worktree were preserved and
  excluded, including mixed Account hunks in app tests, README and ROADMAP.
  Existing logo/template catalogs, backend, configuration and package rules
  have no new changes in this candidate.
- The API tree is identical to the currently Live Staging commit `fc087c4`:
  tree `71d0136e4c0b1bab16b346d7d127037245031722`. No new migration is needed.
  Render still tracks `main` with Auto-Deploy disabled. Deliver through a
  specific candidate commit only after its workflow-dispatch CI passes.
- Mobile UI is delivered in an Android APK. Render deployment alone does not
  update an installed mobile app. The earlier native checks above used the
  same composer runtime and Staging base configuration; new delivery build
  and remote results are recorded separately when verified.

## File Structure

- Modify: `apps/mobile/lib/core/theme/app_theme.dart`
  - Owns shared color tokens, button styles, input styles, and bottom navigation styling.
- Modify: `apps/mobile/lib/features/shared/postdee_card.dart`
  - Owns the reusable glass card container.
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
  - Owns app shell, bottom navigation order, labels, and screen routing.
- Modify: `apps/mobile/lib/features/home/home_screen.dart`
  - Owns Home dashboard content and first-screen status cards.
- Modify: `apps/mobile/lib/features/uploader/uploader_screen.dart`
  - Owns video preview, platform selection, caption input, schedule controls, and post action.
- Modify: `apps/mobile/lib/features/ai/ai_tools_screen.dart`
  - Owns AI tab/header structure.
- Modify: `apps/mobile/lib/features/captions/caption_assistant_screen.dart`
  - Owns AI Caption generation UI and generated-caption result.
- Modify: `apps/mobile/lib/features/analytics/analytics_screen.dart`
  - Owns KPI cards, trend chart, and platform comparison.
- Create or modify: `apps/mobile/lib/features/profile/profile_screen.dart`
  - Owns account, plan, connected-platform, and app settings entry points when Profile is added.
- Modify: `apps/mobile/test/app_test.dart`
- Modify: `apps/mobile/test/home_screen_test.dart`
- Modify: `apps/mobile/test/uploader_screen_test.dart`
- Modify: `apps/mobile/test/caption_assistant_screen_test.dart`
- Modify: `apps/mobile/test/analytics_screen_test.dart`

---

### Task 1: Shared UI Baseline

**Files:**
- Modify: `apps/mobile/lib/core/theme/app_theme.dart`
- Modify: `apps/mobile/lib/features/shared/postdee_card.dart`
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
- Modify: `apps/mobile/test/app_test.dart`

- [ ] **Step 1: Add/confirm widget test coverage for Thai navigation**

Update `apps/mobile/test/app_test.dart` so the shell confirms the user-facing bottom navigation labels are Thai and readable.

```dart
expect(find.text('หน้าแรก'), findsOneWidget);
expect(find.text('อัปโหลด'), findsOneWidget);
expect(find.text('AI'), findsOneWidget);
expect(find.text('วิเคราะห์'), findsOneWidget);
```

- [ ] **Step 2: Run shell test and confirm current behavior**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart
```

Expected: pass if the current shell labels are already correct, or fail if any label is still old, English, or encoded incorrectly.

- [ ] **Step 3: Implement shared polish**

Keep the current `AppTheme` and `PostDeeCard` ownership. Add only reusable tokens that are needed by the next screens: gradient button decoration, muted panel color, warning color, and helper text styles if the current theme cannot express them cleanly.

- [ ] **Step 4: Run shared verification**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart
```

Expected: `No issues found!` from analyze and all tests pass.

### Task 2: Home Dashboard Finish

**Files:**
- Modify: `apps/mobile/lib/features/home/home_screen.dart`
- Modify: `apps/mobile/test/home_screen_test.dart`

- [ ] **Step 1: Add Home dashboard expectations**

Update `apps/mobile/test/home_screen_test.dart` to confirm the Home screen has the core reference sections.

```dart
expect(find.textContaining('สวัสดี'), findsOneWidget);
expect(find.text('สถานะโพสต์ล่าสุด'), findsOneWidget);
expect(find.text('ทางลัด'), findsOneWidget);
expect(find.text('อัปโหลด'), findsWidgets);
expect(find.text('AI แคปชั่น'), findsWidgets);
```

- [ ] **Step 2: Run Home test and confirm current gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\home_screen_test.dart
```

Expected: pass for sections already added in the first UI round; fail only for missing final Home labels or layout sections.

- [ ] **Step 3: Finish the Home UI**

Polish the existing Home dashboard without changing API calls: greeting, plan/status cards, latest platform rows, quick actions, and compact performance summary. Keep existing buttons for API health, Gemini smoke test, subscription refresh, and phone verification reachable lower in the scroll.

- [ ] **Step 4: Verify Home**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\home_screen_test.dart
```

Expected: Home tests pass.

### Task 3: Upload Screen Refresh

**Files:**
- Modify: `apps/mobile/lib/features/uploader/uploader_screen.dart`
- Modify: `apps/mobile/test/uploader_screen_test.dart`

- [x] **Step 1: Add Upload UI expectations**

Update `apps/mobile/test/uploader_screen_test.dart` with user-facing labels from the reference flow.

```dart
expect(find.text('อัปโหลด'), findsOneWidget);
expect(find.text('เลือกแพลตฟอร์ม'), findsOneWidget);
expect(find.text('ตั้งเวลาโพสต์'), findsOneWidget);
expect(find.text('โพสต์'), findsOneWidget);
```

- [x] **Step 2: Run Upload test and confirm current gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\uploader_screen_test.dart
```

Expected: fail until the current scaffold form is replaced with the refreshed Thai UI.

- [x] **Step 3: Refresh Upload layout**

Keep `_createPost`, `_pickVideoFile`, `_loadTemplates`, `_selectedPlatforms`,
and subscription checks intact. The former edit-thumbnail placeholder is now a
functional cover editor: select a source-video frame, style Thai text, render a
1080x1920 JPEG, preview it before confirmation, and send only the cover controls
supported by each destination. The rest of the refreshed layout remains the top
title row, vertical 9:16 preview, platform selection, schedule controls,
template entry point, error/success messages, and one gradient Post button.

- [x] **Step 4: Verify Upload**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\uploader_screen_test.dart
```

Expected: Upload tests pass and existing create-post behavior still submits the same request fields.

### Task 4: AI Caption Refresh

**Files:**
- Modify: `apps/mobile/lib/features/ai/ai_tools_screen.dart`
- Modify: `apps/mobile/lib/features/captions/caption_assistant_screen.dart`
- Modify: `apps/mobile/test/caption_assistant_screen_test.dart`

- [x] **Step 1: Add AI Caption UI expectations**

Update `apps/mobile/test/caption_assistant_screen_test.dart` with the Thai labels and result sections.

```dart
expect(find.text('AI แคปชั่น'), findsOneWidget);
expect(find.text('หัวข้อ / คีย์เวิร์ด'), findsOneWidget);
expect(find.text('สร้างแคปชั่น'), findsOneWidget);
expect(find.text('โทนเสียง'), findsOneWidget);
expect(find.text('แฮชแท็กแนะนำ'), findsOneWidget);
```

- [x] **Step 2: Run AI Caption test and confirm current gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\caption_assistant_screen_test.dart
```

Expected: fail until the old keyword-only scaffold is refreshed.

- [x] **Step 3: Refresh AI Caption layout**

Keep `_generateCaption`, paid-plan gate, `CaptionResult`, and API call intact. Rebuild the visible layout into: title/history row, keyword textarea, gradient Generate button, suggested caption card with Copy action, tone chips, hashtag chips, and friendly Thai error messages.

- [x] **Step 4: Verify AI Caption**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\caption_assistant_screen_test.dart
```

Expected: AI Caption tests pass and the generated caption result still renders caption plus hashtags.

### Task 5: Analytics Refresh

**Files:**
- Modify: `apps/mobile/lib/features/analytics/analytics_screen.dart`
- Modify: `apps/mobile/test/analytics_screen_test.dart`

- [x] **Step 1: Add Analytics UI expectations**

Update `apps/mobile/test/analytics_screen_test.dart` with the reference dashboard sections.

```dart
expect(find.text('วิเคราะห์'), findsOneWidget);
expect(find.text('30 วัน'), findsOneWidget);
expect(find.text('ภาพรวม'), findsOneWidget);
expect(find.text('แนวโน้มยอดวิว'), findsOneWidget);
expect(find.text('เปรียบเทียบแพลตฟอร์ม'), findsOneWidget);
```

- [x] **Step 2: Run Analytics test and confirm current gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\analytics_screen_test.dart
```

Expected: fail until the old list-style analytics scaffold is refreshed.

- [x] **Step 3: Refresh Analytics layout**

Keep `_loadAnalytics`, `AnalyticsSummaryResult`, and platform metric mapping intact. Rebuild the visible layout into: date filter chips, four KPI cards, mini trend chart painter using local sample points until real time-series data exists, platform comparison bars, loading state, and Thai empty/error states.

- [x] **Step 4: Verify Analytics**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\analytics_screen_test.dart
```

Expected: Analytics tests pass and existing summary data still appears.

### Task 6: Profile Navigation and Template Preservation

**Files:**
- Create or modify: `apps/mobile/lib/features/profile/profile_screen.dart`
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
- Modify: `apps/mobile/lib/features/uploader/uploader_screen.dart`
- Modify: `apps/mobile/test/app_test.dart`
- Modify: `apps/mobile/test/uploader_screen_test.dart`

- [x] **Step 1: Add navigation expectations**

Update `apps/mobile/test/app_test.dart` so the bottom navigation target matches the reference direction.

```dart
expect(find.text('หน้าแรก'), findsOneWidget);
expect(find.text('อัปโหลด'), findsOneWidget);
expect(find.text('AI แคปชั่น'), findsOneWidget);
expect(find.text('วิเคราะห์'), findsOneWidget);
expect(find.text('โปรไฟล์'), findsOneWidget);
expect(find.text('เทมเพลต'), findsNothing);
```

- [x] **Step 2: Add template preservation expectation**

Update `apps/mobile/test/uploader_screen_test.dart` so Templates are still reachable from Upload.

```dart
expect(find.text('เทมเพลต'), findsOneWidget);
```

- [x] **Step 3: Run navigation tests and confirm current gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart test\uploader_screen_test.dart
```

Expected: fail until Profile exists and Templates has a secondary entry point.

- [x] **Step 4: Add Profile and update shell order**

Add a simple Profile screen with account status, plan status, connected platform placeholders, and settings entry points. Update bottom navigation to `หน้าแรก`, `อัปโหลด`, `AI แคปชั่น`, `วิเคราะห์`, `โปรไฟล์`. Keep Templates reachable from Upload through the existing template loading flow.

- [x] **Step 5: Verify navigation**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart test\uploader_screen_test.dart
```

Expected: navigation tests pass and no Template test coverage is removed.

### Task 7: Emulator QA Pass

**Files:**
- No source file changes unless visual QA finds a concrete issue.

- [x] **Step 1: Run full Flutter verification**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
..\..\.tools\flutter\bin\flutter.bat build apk --debug
```

Expected: analyze passes, all widget/unit tests pass, and debug APK builds.

- [x] **Step 2: Install and open on Android emulator**

Run from `apps/mobile` with `ANDROID_AVD_HOME` pointing at the local AVD folder:

```powershell
$env:ANDROID_AVD_HOME='D:\.android\avd'
..\..\.tools\flutter\bin\flutter.bat devices
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5554 shell monkey -p com.postdee.postdee_mobile -c android.intent.category.LAUNCHER 1
```

Expected: Pixel_8 emulator shows the app and it opens to Home.

- [x] **Step 3: Capture screenshots for review**

Capture Home, Upload, AI Caption, Analytics, and Profile screenshots into `.tmp`. Compare them against the approved reference for spacing, Thai text readability, button fit, and no overlapping UI.

Expected: screenshots are readable on mobile size and each screen can be reviewed before the next implementation round.

### Task 8: Template UI Polish

**Files:**
- Modify: `apps/mobile/lib/features/templates/templates_screen.dart`
- Modify: `apps/mobile/lib/features/profile/profile_screen.dart`
- Modify: `apps/mobile/test/templates_screen_test.dart`
- Modify: `apps/mobile/test/app_test.dart`

- [x] **Step 1: Add refreshed Template UI expectations**

Update `apps/mobile/test/templates_screen_test.dart` so the template screen uses Thai labels and keeps the existing load/create behavior.

- [x] **Step 2: Confirm current Template UI gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\templates_screen_test.dart
```

Expected: fail until the screen has the refreshed Thai UI.

- [x] **Step 3: Refresh Templates layout**

Update Templates with the dark glass card style, Thai text fields, Thai save/load actions, and a readable empty state. Keep the existing loader/creator callbacks and API flow.

- [x] **Step 4: Make Profile template entry easier to tap**

Update the Profile template card so the whole card opens Templates, while keeping the `เปิด` button.

- [x] **Step 5: Verify Templates on Emulator**

Run analyze, all tests, debug APK build, install the latest APK, open Templates from Profile, and capture `.tmp/postdee-templates-ui-v1.png`.

### Task 9: Profile Summary Polish

**Files:**
- Modify: `apps/mobile/lib/features/profile/profile_screen.dart`
- Modify: `apps/mobile/test/app_test.dart`

- [x] **Step 1: Add Profile summary expectations**

Update `apps/mobile/test/app_test.dart` so Profile must show the scaffold account summary chips: `โหมดทดสอบ`, `0/4 เชื่อมต่อ`, and `พร้อมลอง UI`.

- [x] **Step 2: Confirm current Profile gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart
```

Expected: fail until the Profile status card has the summary chips.

- [x] **Step 3: Add summary chips to Profile**

Update the account status card with compact chips that explain this is a test account, no platforms are connected yet, and the UI is ready to try. Keep all values as scaffold/mock text.

- [x] **Step 4: Verify Profile on Emulator**

Run analyze, all tests, debug APK build, install the latest APK, open Profile, and capture `.tmp/postdee-profile-ui-v2.png`. If ADB cannot see the emulator, set `ANDROID_AVD_HOME=D:\.android\avd` before listing or launching AVDs.

### Task 10: Compact App Shell Chrome

**Files:**
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
- Modify: `apps/mobile/lib/features/auth/auth_status_bar.dart`
- Modify: `apps/mobile/test/app_test.dart`

- [x] **Step 1: Add compact shell expectations**

Update `apps/mobile/test/app_test.dart` so the shell has a compact `PostDee logo`, `แจ้งเตือน`, `บัญชีผู้ใช้`, and a short `Google` auth action.

- [x] **Step 2: Confirm current shell gap**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart
```

Expected: fail until the shell header exposes the compact app chrome.

- [x] **Step 3: Refresh shell header and bottom nav**

Update the global AppBar with a small gradient logo, compact action buttons, and a purple-accented bottom navigation. Add a compact mode to `AuthStatusBar` for shell use, while keeping the full default auth bar behavior for standalone tests.

- [x] **Step 4: Verify shell on Emulator**

Run analyze, all tests, debug APK build, install the latest APK, open Home, and capture `.tmp/postdee-shell-ui-v1.png`.

### Task 11: Login Gate Before Main App

**Files:**
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
- Modify: `apps/mobile/lib/features/auth/firebase_google_auth_gateway.dart`
- Modify: `apps/mobile/test/app_test.dart`
- Modify: `apps/mobile/test/firebase_google_auth_gateway_test.dart`

- [x] **Step 1: Add Login Gate expectations**

Update `apps/mobile/test/app_test.dart` so unauthenticated users see `เข้าสู่ระบบ PostDee`, `เชื่อมอีเมลก่อนเข้าใช้งาน`, and no bottom navigation. Update the signed-in shell test to seed an authenticated session before expecting Home.

- [x] **Step 2: Add local mock auth expectation**

Update `apps/mobile/test/firebase_google_auth_gateway_test.dart` so local mock auth returns a signed-in session with `demo@postdee.local` when Firebase Auth is disabled.

- [x] **Step 3: Confirm current gate/auth gaps**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\app_test.dart test\firebase_google_auth_gateway_test.dart
```

Expected: fail until the app has a Login Gate and local mock auth can sign in.

- [x] **Step 4: Add Login Gate and remove shell auth bar**

Update `PostDeeShell` so unauthenticated users see a full-screen Login Gate. After sign-in, show the normal shell without the compact `บัญชีทดลอง / Google` bar. Keep account icon sign-out available in the shell header.

- [x] **Step 5: Verify Login Gate on Emulator**

Run analyze, all tests, debug APK build, install the latest APK, capture `.tmp/postdee-login-gate-v1.png`, sign in with local mock auth, and capture `.tmp/postdee-after-login-v1.png`.

### Task 12: Real-Use Home Cleanup and Post-Time Phone Gate

**Files:**
- Modify: `apps/mobile/lib/features/home/home_screen.dart`
- Modify: `apps/mobile/lib/features/shell/postdee_shell.dart`
- Modify: `apps/mobile/lib/features/uploader/uploader_screen.dart`
- Modify: `apps/mobile/test/home_screen_test.dart`
- Modify: `apps/mobile/test/uploader_screen_test.dart`

- [x] **Step 1: Add real-use Home expectations**

Update `apps/mobile/test/home_screen_test.dart` so the Home screen only exposes user-facing sections: dashboard overview, platform status, real shortcuts, and schedule preview. Assert developer/test controls such as backend checks, Gemini smoke tests, subscription buttons, phone verification forms, and the old Next step card are not visible.

- [x] **Step 2: Add post-time phone verification expectation**

Update `apps/mobile/test/uploader_screen_test.dart` so pressing `โพสต์` on a Basic plan that still requires phone verification checks the current subscription and shows `ยืนยันเบอร์โทรก่อนโพสต์ฟรี 3 ครั้งต่อเดือน` before creating a post.

- [x] **Step 3: Confirm current UI/flow gaps**

Run from `apps/mobile`:

```powershell
..\..\.tools\flutter\bin\flutter.bat test test\home_screen_test.dart test\uploader_screen_test.dart
```

Expected: fail until Home no longer exposes developer tools and Upload checks subscription before real-time posting.

- [x] **Step 4: Clean Home for real users**

Update Home to remove visible developer/testing/billing/phone-verification controls. Add real shortcuts for Upload, AI captions, Templates, and Analytics, and wire them through `PostDeeShell` so the shortcuts open real app surfaces.

- [x] **Step 5: Gate Basic posting by phone verification**

Update Upload so every post action checks the current subscription before creating an upload/post. If the plan still requires phone verification, stop and show the Thai warning instead of sending the post request.

- [x] **Step 6: Verify on Emulator**

Run analyze, all tests, debug APK build, install the latest APK, open Home and Upload, and capture `.tmp/postdee-home-real-use-v1.png` plus a phone-verification gate screenshot.
