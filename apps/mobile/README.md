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

The Android Release application id is `com.postdee.postdee_mobile`; Android
Debug uses `com.postdee.postdee_mobile.staging` so Firebase Staging can be
installed alongside Production. The iOS bundle id is
`com.postdee.postdeeMobile`. Keep Firebase, RevenueCat, Google Play, and App
Store configuration aligned with the build being tested.
Android builds still require Android Studio and the Android SDK.
Production iOS builds require Xcode on macOS.

## Auth Handoff

`PostDeeApiClient` accepts an optional `authTokenProvider`. When it returns a Firebase ID token, every backend JSON request sends `Authorization: Bearer <token>`. When no token is available, the client falls back to local mock headers from `POSTDEE_MOCK_USER_ID` and `POSTDEE_MOCK_SUBSCRIPTION_PLAN`.

The app now has a shared `PostDeeAuthSessionStore`, an `AuthStatusBar`, and a Firebase/Google auth gateway. A successful auth gateway stores the Firebase ID token in the shared session, and the API client can use that token automatically.
Account-deletion confirmation and token refresh are bound to a session generation.
Sign-in/logout invalidate older operations; token/name updates preserve the
binding. Native login/logout, Apple deletion revocation and phone linking share a queue, and
late deletion responses cannot clear a new session. The new regression tests
remain unrun in the current security-audit environment.
RevenueCat Starter/Pro purchases await `POST /billing/purchase-readiness`
before calling the Store SDK; only `purchaseReady: true, preparationProtocol: 1`
permits purchase. Missing/unsupported readiness or 404/501 shows a Thai
compatibility message and prevents buy/polling. Subscription
GET is read-only. Coordinate rollout with the API because older clients depend
on GET bootstrap; restore continues to use the existing resync flow.
Session binding covers availability/readiness, native configuration/product
lookup, buy/restore completion and polling/backoff. The real RevenueCat gateway
serializes SDK operations across instances. Default readiness/resync/polling use
bound HTTP headers and response owner checks. Already-dispatched native work
cannot be canceled by these checks and still needs device validation.

Release the additive API preparation endpoint, then preparation-aware apps,
retire/disable builds that skip preparation, then deploy read-only GET. The
current branch bundles that GET change and cannot safely be deployed while
legacy builds can still buy after a failed subscription GET.

Auth gateways and restored sessions include the stable Firebase UID. OTP
requests bind their verification ID to the original UID/session, ignore late or
duplicate callbacks and cancel on resend/dispose/account changes. The real
gateway requires the auth controller's bound native queue for link/reload/token
steps; direct SDK auth changes outside that controller are not serialized.

Link in Bio persists drafts per UID. Old unowned keys are left untouched and
ignored; there is no automatic migration to the next signed-in user. Account
changes clear visible draft fields and close the owned link editor. Local data
is retained on this device. FCM clears in-app history on account changes,
filters real messages by recipient `data.userId`, and registers tokens using
bound auth headers. Messages without that UID are ignored. Background OS
display, backend token detachment and requests already sent before a transition
still need validation/work. The newly added tests/analyze remain unrun.

Firebase auth is off by default for local scaffold runs. To enable the real gateway, configure Firebase for Android/iOS, then run with:

```powershell
..\..\.tools\flutter\bin\flutter.bat run --dart-define=ENABLE_FIREBASE_AUTH=true --dart-define=GOOGLE_SERVER_CLIENT_ID=121898224944-1hkh1mrfb5lc1ltraapu10lj1ib465vj.apps.googleusercontent.com
```

The Firebase project files are installed locally. Android Emulator Google
Sign-In, Firebase ID token verification, and the authenticated Staging API/Home
response pass. Physical Android/iOS and Phone Auth tests remain.

If `ENABLE_FIREBASE_AUTH=true` is used before Firebase project files are available, the app keeps running and the Google Sign-In button reports the setup issue instead of crashing during startup.

See `../../FIREBASE_SETUP.md` for the full Firebase Auth and Google Sign-In checklist.

### Android Debug Staging

`android/app/src/debug/google-services.json` is the dedicated Firebase Staging
config. Copy the checked-in non-secret example to the ignored local file, then
run Debug only:

```powershell
Copy-Item staging.local.example.json staging.local.json
..\..\.tools\flutter\bin\flutter.bat run --debug --dart-define-from-file=staging.local.json
```

Do not pass `staging.local.json` to `--profile` or `--release`; those build types
still use Firebase Production. A different machine/CI debug keystore also needs
its SHA-1 and SHA-256 registered in Firebase Staging.

For the one-click Windows development flow, run
`tool/launch-postdee-android.ps1`. It opens this Flutter project in Android
Studio, starts the existing `Pixel_8` emulator when needed, builds the latest
Debug Staging APK with `staging.local.json`, installs it, and launches PostDee.
The Desktop shortcut named `PostDee Android` points to this helper. Its status
window stays visible, opens the already-installed app as soon as Android boots,
then installs and relaunches the latest build. This workstation stores its AVDs
in `D:\.android\avd`, which the helper sets explicitly.

## Production / Sandbox Run

Use this when testing the real Render API, Firebase Auth, and RevenueCat flow.
The checked-in example keeps backend secrets out of the mobile app and blocks
local mock auth:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command run
```

The script reads only the ignored `production.local.json` file. Start from
`production.local.example.json`, keep the production flags such as
`API_BASE_URL=https://postdee-api.onrender.com`, `ENABLE_FIREBASE_AUTH=true`,
and `ALLOW_LOCAL_MOCK_AUTH=false`, then add the platform RevenueCat SDK key to
that same local file. Android Play builds require
`REVENUECAT_ANDROID_API_KEY`. Never add backend webhook tokens or server REST
API keys to this mobile config.

The production helper rejects empty RevenueCat keys, Test Store keys beginning
with `test_`, and example placeholders beginning with `replace_with_`. The
`build-apk` and `build-appbundle` commands specifically require a valid
`REVENUECAT_ANDROID_API_KEY`; a generic `REVENUECAT_API_KEY` does not count for
an Android release build. Use the direct Flutter command in the local testing
section below when testing with the RevenueCat Test Store.

Build a release Android APK with the same production flags:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command build-apk
```

Build the signed Android App Bundle used for Google Play Internal testing:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-production.ps1 -Command build-appbundle
```

The generated bundle is written to
`build/app/outputs/bundle/release/app-release.aab`.

Android release builds also require a local signing key. Copy
`android/key.properties.example` to `android/key.properties`, create or place the
matching keystore file under `android/`, and keep both files out of Git. Missing
`storeFile` means the production flags are valid, but the APK/AAB cannot be
packaged for release until Android signing is configured. See
`../../docs/ANDROID_SIGNING_KEYS.md` for the safety checklist.

## Store Subscription

The Home Starter/Pro CTAs can run in two modes:

- Default local mode uses the legacy Flutter `in_app_purchase` scaffold and
  `POST /billing/store/verify`.
- RevenueCat mode uses `purchases_flutter` and waits for
  `POST /billing/revenuecat/webhooks` to update the backend entitlement.

For local RevenueCat Test Store testing, use the ignored
`revenuecat.local.json` file that contains the dashboard SDK key. This file is
only for the direct staging command below; the production helper never reads it:

```powershell
..\..\.tools\flutter\bin\flutter.bat run --debug --dart-define-from-file=staging.local.json --dart-define-from-file=revenuecat.local.json
```

Use `STORE_STARTER_MONTHLY_PRODUCT_ID=postdee_starter_monthly` and
`STORE_PRO_MONTHLY_PRODUCT_ID=postdee_pro_monthly` as the default product ids.
The SDK key in the local `revenuecat.local.json` file is for the RevenueCat Test
Store; do not use that file for App Store or Google Play releases. As recorded
in the root README and ROADMAP, the RevenueCat Play Store app/products,
entitlements, default offering, production Android public SDK key, and signed
AAB are prepared. Play Console app/subscriptions, service credentials, internal
testing, physical-device verification, and real Google Play/App Store purchase
lifecycle tests remain pending. Production billing still requires purchase,
restore, renewal, cancellation, and refund verification against the real stores.

## Video Preparation

The built-in manual timeline editor has been removed. Pro AI auto editing
remains: select a clip and AI settings, process it, review the result, then
continue to Upload/Post. This flow still requires real-provider and
physical-device verification before production launch.

## Publishing Status

The managed PostPeer connection trial opens HTTPS authorization URLs in an
Android Custom Tab and falls back to an external browser when unavailable or
launching fails. It avoids the URL-launcher plugin's embedded WebView fallback.
Other platforms keep opening the external browser. A pending attempt refreshes
connection status through the backend after the app leaves the foreground and
the original signed-in session returns; manual refresh remains available.
There is no automatic browser-to-app redirect in this trial. Native social-app
handoff and password-free login still require real-device checks. See the
[mobile trial guide](../../docs/superpowers/plans/2026-10-25-postpeer-mobile-connection-trial.md).

Direct TikTok native connection remains a proposed design pending developer
registration and sandbox setup before implementation. No native social
SDK/gateway, native authorization contract, direct token exchange, or direct
publisher has been added for that proposal. Follow the
[TikTok setup and security plan](../../docs/superpowers/plans/2026-10-21-tiktok-native-connection.md)
before implementing and testing a direct connection.

YouTube Shorts uses one shared caption by default. Before publishing, the app
previews a title from the first sentence of the first nonempty caption line,
limited to 100 Unicode code points after removing `<`/`>`; the full caption
remains unchanged as the description. The title field stays hidden until
`ปรับชื่อเฉพาะ YouTube` is selected. Caption edits do not overwrite a custom
title; `ใช้ชื่อจากแคปชัน` resumes deriving it from the caption.
Custom titles must not contain `<` or `>` and must fit the 100-code-point limit.
The API client sends `youtubeTitle` only for a selected YouTube destination
with a nonempty override; automatic requests omit it and let the backend derive
the title. A blank caption is valid only for YouTube-only posts
with a nonempty custom title; other destinations still require a caption.

The uploader loads the authenticated user's social connections and only allows
connected, supported destinations to be selected. A successful `POST /posts`
response means the post was accepted as `QUEUED` (or scheduled); the mobile UI
must describe that state as queued, not as proof that every platform has already
published it. Final platform success or failure comes from the publish worker.
The app requests `multipart-v1` from `POST /uploads`. When the server runs in
`dual` or `multipart` mode, it uploads exact file ranges to just-in-time part
URLs, retries the same failed part up to three times, retains each ETag, and
calls the completion endpoint before creating a post. It checks upload status
after an ambiguous completion response with bounded 1s/2s/4s backoff instead of
creating a second session. If the server still reports `COMPLETING`, the app
preserves that session and never sends a competing abort request.

The server defaults to `legacy`, and production uses `dual` while older clients
are upgraded. If the server returns the legacy signed-`PUT` response, the app
keeps the existing 30-second expiry safety margin and requests one fresh URL
only after an explicit expiry response. The legacy path remains replayable
until production switches to strict `multipart` mode.

## Profile Draft

Display name and store name edits are currently saved only on the user's
device; they are not yet synchronized to Firebase or the PostDee backend. Email
verification badges come from Firebase's real `emailVerified` value and must
not be inferred merely because an email address is present.
