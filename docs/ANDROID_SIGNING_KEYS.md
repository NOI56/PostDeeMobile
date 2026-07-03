# Android Signing Keys

Last updated: 2026-07-03.

This file explains the local Android release signing files for PostDee. Do not
paste real passwords, key contents, or keystore files into this document.

## What These Files Are

| File | Purpose | Commit to Git? |
| --- | --- | --- |
| `apps/mobile/android/upload-keystore.jks` | Local Android upload signing key used to sign release APK/AAB builds. | No |
| `apps/mobile/android/key.properties` | Local Gradle config that points to the keystore and contains signing passwords. | No |
| `apps/mobile/android/key.properties.example` | Safe template with placeholder values only. | Yes |

The release APK contains a signature produced by the keystore. It should not
contain `key.properties` or the signing passwords as readable app files.

## Current Local Status

The local workspace has these signing files:

- `apps/mobile/android/upload-keystore.jks`
- `apps/mobile/android/key.properties`

They are ignored by `apps/mobile/android/.gitignore`:

- `key.properties`
- `**/*.keystore`
- `**/*.jks`

## Safety Rules

- Do not commit `upload-keystore.jks`.
- Do not commit `key.properties`.
- Do not paste signing passwords into chat, docs, issues, or pull requests.
- Do not send these files over normal chat or email.
- Keep a backup in a password manager, encrypted drive, or another approved
  secure location.
- If this upload key is used for Google Play, do not lose it. Future app
  updates may need the same upload key.

## How To Check They Are Not Tracked

From the repository root:

```powershell
git check-ignore -v apps\mobile\android\key.properties apps\mobile\android\upload-keystore.jks
git status --short --ignored apps\mobile\android\key.properties apps\mobile\android\upload-keystore.jks
```

Expected result: both files should appear as ignored files, not staged or
tracked files.

## How To Recreate On Another Machine

If another build machine needs release signing:

1. Copy `apps/mobile/android/key.properties.example` to
   `apps/mobile/android/key.properties`.
2. Put the real keystore file under `apps/mobile/android/`.
3. Fill `key.properties` with the real local values.
4. Confirm both real files are ignored by Git.
5. Run the production APK build:

```powershell
cd apps\mobile
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command build-apk
```

## What To Do If They Leak

If `upload-keystore.jks` and its passwords leak, treat it as a security incident.

- Remove the leaked files from the place they were shared.
- Do not rely on the leaked key for future releases unless the platform still
  requires it and the risk is accepted.
- If Google Play App Signing is enabled, follow Google Play Console's upload key
  reset process.
- If a public Git commit contains these files, rotate/reset the upload key and
  remove the files from the repository history.
