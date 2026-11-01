---
name: postdee-android-build
description: Build, install, and verify a PostDee Android Staging build on an emulator or phone without losing the installed app's data. Use when the owner wants to see a change in the real app, test on a device, or check which build is installed; not for Production or store builds.
---

# PostDee Android builds

The device usually holds the owner's signed-in Staging app with saved drafts on adopted (external) storage. Losing that data is the main risk; the helpers in `apps/mobile/tool/` exist to prevent it. Read `apps/mobile/README.md` → "Android Debug Staging" for the full helper contract before acting.

## Never do these without the owner's explicit approval

- Uninstall the app, clear its data, wipe or recreate an emulator, or move the app to another storage volume.
- Run raw `flutter run`, `flutter install`, or `adb install` against a device that already has the app. Every Debug build uses package `com.postdee.postdee_mobile.staging`, so it overwrites the owner's app; a failed `flutter run` can uninstall it, and a plain install can land on internal storage and expose an empty data location.
- Build an installed Staging app with raw `flutter build apk`. Without the helper's Dart-define files, Firebase sign-in and RevenueCat are silently disabled.
- Print or copy `staging.local.json`, `revenuecat.local.json`, `production.local.json`, or signing files.

## Choose the build path

All commands run from `apps/mobile` in PowerShell.

| Goal | Command |
| --- | --- |
| Show the latest `main` on the emulator | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\launch-postdee-android.ps1 -AvdName <avd>` |
| Dry run: which source, SDK, and APK the launcher would use | same command with `-ResolveOnly` (no adb, build, or install) |
| Build a feature branch APK without touching any device | `powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk` in that branch's checkout |
| Install a feature branch APK | shared updater `Invoke-PostDeeAndroidApkUpdate` in `tool/android-install-volume.ps1` (read its parameters first) |
| Build when local tooling cannot | `ci.yml` manual run with `build_staging_apk` and an exact `apk_source_ref`; see `docs/STAGING.md` |

Key facts:

- **The launcher always builds `main`**, from whichever worktree has `main` checked out, even when started from another branch. It cannot demonstrate a feature branch. It fails if no worktree is on exact `main`.
- The launcher reuses the installed build number so the install is an update, never a downgrade. The number on screen therefore does not identify the source; the APK hash does.
- The updater pins the app's existing storage volume (`install -r --force-uuid`) and refuses when that volume is not mounted or the package UID, volume, or version would change. If it stops, report why; do not work around it.
- `postdee-staging.ps1 -Command run` refuses an adopted-storage target. After the launcher installs, debug with `flutter attach -d <device>` using the Flutter path the launcher prints as `Flutter=`.
- In a linked worktree the helper finds the ignored `revenuecat.local.json` in the root checkout automatically. If it is missing, the build stops; ask the owner rather than creating one.

## Pick the device

List devices with `adb devices` (when adb is not on `PATH`, it is `platform-tools\adb.exe` under the `AndroidSdk=` path that `-ResolveOnly` prints) and ask which one holds the owner's app if more than one is online. Do not reuse a device ID from an old note. On the owner's machine, emulator data partitions can be nearly full; check free space before a large install rather than deleting apps to make room.

The emulator may be shared with another agent that can also drive it. Before trusting a result, confirm nobody else installed a different APK in the meantime (see below), and prefer single taps with a screenshot after each over swipes, which can register as taps under load.

## Verify what is installed

Before saying "the new build is on the device", check all of these:

1. **Same APK:** compare `adb shell sha256sum <path from 'pm path com.postdee.postdee_mobile.staging'>` with the hash of the APK you built (`build/app/outputs/flutter-apk/app-debug.apk`).
2. **Source:** the commit the launcher or helper reported, and that it matches what you meant to show.
3. **Runtime:** the app starts natively, shows the STAGING strip, signs in, and talks to the Staging API (`https://postdee-api-staging.onrender.com`, from `staging.local.example.json`).
4. **The change itself:** exercise the changed screen or flow and capture a screenshot. `exec-out screencap` sometimes returns 0 bytes; `screencap -p /sdcard/s.png` then `pull` is reliable. From Git Bash set `MSYS_NO_PATHCONV=1` for `/sdcard/...` paths.

The emulator clock may be on GMT, so in-app times can read 7 hours behind Thai time; that is not a bug in itself. Push notifications cannot be verified on a device where `POST_NOTIFICATIONS` is not granted.

Report the device, package, APK hash, source commit, and what was exercised. If any step was skipped, say so.
