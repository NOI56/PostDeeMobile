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
config. Use the staging helper for every Debug build installed on a device:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command run
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk
```

The helper validates the Staging API, Firebase flag, mock-auth flag, and Google
server client id before invoking Flutter. It uses an ignored
`staging.local.json` when present and otherwise falls back to the checked-in,
non-secret `staging.local.example.json`. Do not use a raw `flutter build apk`
for an installed Staging build: omitting the Dart define file safely disables
Firebase Auth. The helper rejects `--profile`, `--release`, and Dart-define
overrides because those could mix Staging and Production configuration. A
different machine/CI debug keystore also needs its SHA-1 and SHA-256 registered
in Firebase Staging.

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
The ignored local RevenueCat file contains a Test Store key, so do not submit an
App Store or Google Play release with that file. RevenueCat's Play app,
products, entitlements, default offering, and production Android public SDK key
are prepared. Release work still needs the Play Console app/subscriptions,
service credentials, Internal Testing purchase/restore on a physical Android
device, the matching App Store setup, and renewal/cancel/refund verification.

## Publishing Status

The uploader loads the authenticated user's social connections and only allows
connected, supported destinations to be selected. After the user confirms, the
current client calls authenticated `GET /publishing/readiness` before
watermarking or uploading. A `503 SOCIAL_PUBLISHING_UNAVAILABLE` stops the flow
with title `ระบบรับงานโพสต์ยังไม่เปิดใช้งานในขณะนี้` and body
`วิดีโอยังไม่ได้อัปโหลด กรุณาลองใหม่ภายหลัง`; no new upload is started by that
client path.

The readiness response is only a server-configuration gate. Even
`acceptingPosts: true` does not verify PostPeer, R2/S3, the queue/worker, or the
selected user's connection. `POST /posts` is still the authoritative check and
can return the same `503` if configuration changes after preflight. Older app
versions do not run the preflight, and a race can leave media that was uploaded
before the `503`; the current client then says that no post was created and the
video may be stored temporarily. Normal temporary-media cleanup must cover that
object. Reschedule/publish-now surfaces a separate Thai unavailable message,
while cancel remains usable.

A successful `POST /posts` response means the post was accepted as `QUEUED` (or
scheduled); the mobile UI must describe that state as queued, not as proof that
every platform has already published it. Final platform success or failure
comes from the publish worker.
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

## AI Editing and Subtitle Studio

AI Editing renders a lightweight preview and opens result review before any
subtitle editor. The user opens Subtitle Studio explicitly from review. Local
text/time/style edits and re-renders reuse the prepared recipe and do not consume
another AI-editing minute.

Every optional AI capability starts off when setup opens. The user explicitly
enables subtitles, silence cleanup, repeated-speech cleanup, or colour
adjustment. Leaving all of them off runs only target-length shortening. Isolated
acceptance tests keep the original duration and enable exactly one capability;
combined tests are separate.

Validated cue-level word timing can drive active-word colour in preview and ASS
export. Edited, incomplete, malformed, or rejected word timing falls back to a
static one-line subtitle. Bundled Thai-safe Bai Jamjuree, Anuphan, and Prompt
fonts share the same safe-area sizing in preview and export. Prepared Thai cues
with multiple tokens are capped server-side at five semantic words and 20
graphemes. An indivisible longer brand/URL token remains whole in an isolated
cue, and mobile shrinks its font from measured preview/export width. Source clips are
limited to 10 minutes; the shortening slider runs from 5 seconds to at most 3
minutes (or from 1 second for a source under 5 seconds), and its right edge keeps
the original. Opening pre-roll
uses only a real subtitle-free gap, and a target that would end on a dangling
Thai connector keeps its opening/internal cuts and moves only the tail to the
first complete phrase. Semantic overrun is 10% of target, bounded to 1–3
seconds, and the renderer uses the same cap; if no phrase fits, the dangling cue
is omitted. This is independent of the disabled three-second hook feature. The
uploader tool area remains intentionally EP-only.
Entitlement preflight releases after 30 seconds. A render with no processed
time, terminal session, or exact `progress=end` signal stops after 30 seconds
for preview and 90 seconds for full export. Static SRT/ASS events are authored
on the original source timeline before kept ranges are compacted, so diagnostic
subtitle time can extend past a shortened result without appearing in it.

## Profile Draft

Display name and store name edits are currently saved only on the user's
device; they are not yet synchronized to Firebase or the PostDee backend. Email
verification badges come from Firebase's real `emailVerified` value and must
not be inferred merely because an email address is present.
