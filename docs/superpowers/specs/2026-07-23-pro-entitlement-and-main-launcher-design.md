# Pro Entitlement Consistency and Main Launcher Design

## Context

The AI editing screen can display a cached Pro badge after a RevenueCat Test
Store entitlement expires. The process action performs a fresh backend check,
sees Basic, and opens the Pro paywall without first updating the badge.

The desktop shortcut currently runs
`D:\PostDeeMobile\apps\mobile\tool\launch-postdee-android.ps1`. That script
builds the dirty root worktree, which is not `main`, so installing from the
shortcut can bring older UI back.

## Goals

- Keep the AI editing package badge consistent with the latest backend result.
- Give the current staging tester a longer-lived Pro entitlement without
  creating a global billing bypass.
- Make the existing desktop shortcut build and open the checked-out `main`
  worktree while preserving all old branches and uncommitted work.

## Design

### Subscription state

`AiEditingScreen._processVideo` remains the final entitlement guard. Whenever
that guard loads a subscription, it also writes the returned subscription into
the screen state before deciding whether to continue. A Basic response
therefore updates the badge before the existing Pro-required sheet appears.

The current staging Firebase user receives a time-bounded promotional Pro
entitlement in RevenueCat. This is account-specific and does not change
production package rules or introduce a client-side override.

### Desktop launcher

The existing shortcut path stays unchanged. Its PowerShell launcher discovers
the Git worktree whose branch is exactly `refs/heads/main`, then uses that
worktree's `apps/mobile` directory for Android Studio, Flutter build output,
and APK installation.

Ignored local configuration remains sourced from
`D:\PostDeeMobile\apps\mobile\staging.local.json`. The launcher will not pull,
merge, delete, or rewrite any branch. It fails clearly if no cleanly resolved
`main` worktree exists.

A `-ResolveOnly` switch prints the resolved source branch and paths without
starting Android Studio, the emulator, or a build. This provides a safe,
repeatable launcher verification.

## Error handling

- Missing `main` worktree: stop with a clear launcher error.
- Missing local staging configuration: stop before building.
- Expired or missing Pro entitlement: show Basic and the existing Pro sheet.
- RevenueCat grant failure: leave backend data unchanged and report the
  external blocker.

## Verification

- Widget regression test: initial badge is Pro, process-time check returns
  Basic, badge becomes Basic, and no upload starts.
- Launcher dry run: resolved branch is `main` and source path is the current
  main worktree.
- Full Flutter test/analyze and API test/build suites.
- Pixel 8: refresh package badge and confirm Pro after the promotional grant.
- Git: `main` remains clean and matches `origin/main` after push.
