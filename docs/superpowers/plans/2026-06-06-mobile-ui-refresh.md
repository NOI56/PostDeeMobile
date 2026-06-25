# Mobile UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the Flutter mobile app into the approved Thai ultra-dark creator UI while preserving the current backend, auth, billing, upload, caption, template, and analytics behavior.

**Architecture:** Keep the existing feature screens and service classes. Improve shared visual primitives first, then refresh one screen per round so every change can be tested and viewed on the Android emulator. Templates move out of the main bottom navigation only after a Profile entry point exists, so no existing feature disappears.

**Tech Stack:** Flutter, Dart, Material 3, existing PostDee API client, Flutter widget tests, Android Emulator Pixel_8.

---

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

Keep `_createPost`, `_pickVideoFile`, `_loadTemplates`, `_selectedPlatforms`, and subscription checks intact. Rebuild only the visible layout into: top title row, vertical 9:16 preview, edit-thumbnail action, platform toggle grid, schedule mode selector, date/time controls, template entry point, error/success messages, and one gradient Post button.

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
