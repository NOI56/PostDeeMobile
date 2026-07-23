# Pro Entitlement and Main Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the AI editing package UI consistent with the backend, give the current staging tester a durable Pro entitlement, and make the desktop shortcut install only the `main` app.

**Architecture:** The process-time entitlement request remains authoritative and now refreshes the cached badge state. The existing desktop launcher resolves the worktree whose branch is exactly `main` and keeps ignored staging configuration in the root checkout. RevenueCat receives an account-specific promotional entitlement instead of a global bypass.

**Tech Stack:** Flutter/Dart widget tests, PowerShell, Git worktrees, RevenueCat, Firebase Auth, Render staging.

## Global Constraints

- Do not delete, reset, move, or overwrite the dirty root worktree.
- Do not add a client-controlled Pro bypass to Firebase-authenticated requests.
- Keep the desktop shortcut path unchanged.
- Use a time-bounded promotional Pro entitlement for only the current staging tester.

---

### Task 1: Refresh the package badge during the final entitlement check

**Files:**
- Modify: `apps/mobile/test/ai_editing_screen_test.dart`
- Modify: `apps/mobile/lib/features/ai_editing/ai_editing_screen.dart`

**Interfaces:**
- Consumes: `EditorSubscriptionLoader`, `SubscriptionStatusResult.isPro`
- Produces: `_processVideo` updates `_aiEditSubscription` with its fresh result

- [ ] **Step 1: Write the failing widget test**

Add a test whose loader returns Pro for initialization and Basic for the
process-time check. Assert that the process action starts no upload, opens the
existing Pro sheet, and changes the badge text to `แพ็กเกจ Basic`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test --no-pub test\ai_editing_screen_test.dart --plain-name "refreshes a stale Pro badge when the process check returns Basic"
```

Expected: FAIL because the badge still displays the cached Pro quota.

- [ ] **Step 3: Implement the minimum state update**

In `_processVideo`, after `loadSubscription()` returns and before checking
`subscription.isPro`, call `setState` when mounted:

```dart
setState(() {
  _aiEditSubscription = subscription;
  _aiEditSubscriptionLoadFailed = false;
});
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: PASS.

### Task 2: Route the desktop launcher to `main`

**Files:**
- Modify local-only: `D:\PostDeeMobile\apps\mobile\tool\launch-postdee-android.ps1`
- Verify: `C:\Users\stopp\OneDrive\Desktop\PostDee Android.lnk`

**Interfaces:**
- Consumes: `git worktree list --porcelain`
- Produces: a `-ResolveOnly` mode and a resolved `main` mobile source path

- [ ] **Step 1: Verify the existing launcher fails the routing contract**

Run a PowerShell assertion that requires `refs/heads/main` resolution and a
`ResolveOnly` parameter.

Expected: FAIL before the launcher change.

- [ ] **Step 2: Implement main worktree resolution**

Parse `git worktree list --porcelain`, pair each `worktree` entry with its
`branch` entry, and choose only `refs/heads/main`. Use the selected worktree's
`apps/mobile` directory for Android Studio, Flutter, the APK path, and logs.
Keep `staging.local.json` sourced from the root checkout.

- [ ] **Step 3: Add and verify dry-run mode**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\PostDeeMobile\apps\mobile\tool\launch-postdee-android.ps1" -ResolveOnly
```

Expected output includes:

```text
SourceBranch=main
SourceMobileRoot=D:\PostDeeMobile\.worktrees\main-integrate-duration\apps\mobile
```

- [ ] **Step 4: Read back the desktop shortcut**

Use `WScript.Shell.CreateShortcut` and confirm its target is PowerShell and its
arguments still reference the existing launcher path.

### Task 3: Grant the staging tester durable Pro access

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: current Firebase UID already linked to the RevenueCat customer
- Produces: a time-bounded promotional `pro` entitlement for that customer

- [ ] **Step 1: Open the current RevenueCat customer**

Use the signed-in RevenueCat dashboard, search the exact current Firebase UID
without exposing it in output, and confirm the existing Test Store Pro
entitlement has expired.

- [ ] **Step 2: Grant promotional Pro**

Grant `pro` for a 30-day period. Do not grant lifetime access.

- [ ] **Step 3: Verify backend synchronization**

Refresh the package badge on Pixel 8 without starting an AI edit. Confirm it
shows Pro and preserves the existing minute usage.

### Task 4: Full verification, install, and publish

**Files:**
- Verify all files changed in Tasks 1-2 and this plan.

**Interfaces:**
- Consumes: completed application and launcher changes
- Produces: tested `main`, installed Pixel 8 app, and synchronized GitHub main

- [ ] **Step 1: Run full checks**

Run:

```powershell
cd apps\api
npm.cmd run test
npm.cmd run build

cd ..\mobile
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat analyze --no-pub
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat test --no-pub
D:\PostDeeMobile\.tools\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=D:\PostDeeMobile\apps\mobile\staging.local.json
```

Expected: all commands exit 0.

- [ ] **Step 2: Install and launch on Pixel 8**

Install the APK from the resolved main worktree with `adb install -r`, launch
`com.postdee.postdee_mobile.staging`, and inspect the AI editing package badge.

- [ ] **Step 3: Commit and push**

Stage only the tracked mobile test, mobile implementation, and plan. Commit
with:

```text
fix(ai-edit): sync package badge with entitlement
```

Push `main` and verify `origin/main...HEAD` is `0 0`.
