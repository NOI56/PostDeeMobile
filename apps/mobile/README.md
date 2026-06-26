# PostDee Mobile

Flutter mobile app scaffold for PostDee.

## Local Commands

Run commands from this folder with the workspace-local Flutter SDK:

```powershell
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

## Platform Folders

Android and iOS folders are generated from Flutter templates with package org `com.postdee`.
Android builds still require Android Studio and the Android SDK.
Production iOS builds require Xcode on macOS.

## Auth Handoff

`PostDeeApiClient` accepts an optional `authTokenProvider`. When it returns a Firebase ID token, every backend JSON request sends `Authorization: Bearer <token>`. When no token is available, the client falls back to local mock headers from `POSTDEE_MOCK_USER_ID` and `POSTDEE_MOCK_SUBSCRIPTION_PLAN`.

The app now has a shared `PostDeeAuthSessionStore`, an `AuthStatusBar`, and a Firebase/Google auth gateway. A successful auth gateway stores the Firebase ID token in the shared session, and the API client can use that token automatically.

Firebase auth is off by default for local scaffold runs. To enable the real gateway, configure Firebase for Android/iOS, then run with:

```powershell
..\..\.tools\flutter\bin\flutter.bat run --dart-define=ENABLE_FIREBASE_AUTH=true --dart-define=GOOGLE_SERVER_CLIENT_ID=121898224944-1hkh1mrfb5lc1ltraapu10lj1ib465vj.apps.googleusercontent.com
```

The Firebase project files are installed locally. The next Firebase milestone is
testing Google Sign-In on an actual Android/iOS device.

If `ENABLE_FIREBASE_AUTH=true` is used before Firebase project files are available, the app keeps running and the Google Sign-In button reports the setup issue instead of crashing during startup.

See `../../FIREBASE_SETUP.md` for the full Firebase Auth and Google Sign-In checklist.

## Production / Sandbox Run

Use this when testing the real Render API, Firebase Auth, and RevenueCat flow.
The checked-in example keeps backend secrets out of the mobile app and blocks
local mock auth:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command run
```

The script merges:

- `production.local.json` for non-secret production app flags such as
  `API_BASE_URL=https://postdee-api.onrender.com`,
  `ENABLE_FIREBASE_AUTH=true`, and `ALLOW_LOCAL_MOCK_AUTH=false`.
- `revenuecat.local.json` for the RevenueCat mobile SDK key. This file is
  ignored by Git and must not contain backend webhook tokens.

Build a release Android APK with the same production flags:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command build-apk
```

## Store Subscription

The Home Starter/Pro CTAs can run in two modes:

- Default local mode uses the legacy Flutter `in_app_purchase` scaffold and
  `POST /billing/store/verify`.
- RevenueCat mode uses `purchases_flutter` and waits for
  `POST /billing/revenuecat/webhooks` to update the backend entitlement.

For local RevenueCat Test Store testing, use the ignored
`revenuecat.local.json` file that contains the dashboard SDK key:

```powershell
..\..\.tools\flutter\bin\flutter.bat run --dart-define=ENABLE_FIREBASE_AUTH=true --dart-define=GOOGLE_SERVER_CLIENT_ID=121898224944-1hkh1mrfb5lc1ltraapu10lj1ib465vj.apps.googleusercontent.com --dart-define-from-file=revenuecat.local.json
```

Use `STORE_STARTER_MONTHLY_PRODUCT_ID=postdee_starter_monthly` and
`STORE_PRO_MONTHLY_PRODUCT_ID=postdee_pro_monthly` as the default product ids.
The current RevenueCat SDK key is a Test Store key, so do not submit an App
Store or Google Play release with this local file. Production still needs real
Apple App Store / Google Play subscription products, RevenueCat offerings,
sandbox/device purchase testing, and renewal/cancel/refund webhook verification.
