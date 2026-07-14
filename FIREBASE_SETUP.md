# FIREBASE_SETUP.md

Firebase setup checklist for PostDee.

## Goal

Use Firebase Auth with Google Sign-In on the Flutter app. Basic free posting also requires Firebase Phone Auth so the verified ID token includes `phone_number`. The Flutter app then sends the Firebase ID token to the PostDee backend through:

```text
Authorization: Bearer <Firebase ID token>
```

The backend verifies that token when `AUTH_PROVIDER=firebase`.

## What Must Stay Secret

Do not put service account keys or backend secrets in the mobile app.

Keep these on the backend only:

- Firebase service account JSON, if one is ever needed for backend admin tasks.
- Social platform client secrets.
- Gemini API keys.
- Cloudflare R2 secret keys.
- Apple and Google Play private keys.

Firebase mobile project config files are allowed in the mobile app, but production access must still be protected with Firebase Security Rules, App Check where appropriate, and backend token verification.

## Mobile Checklist

1. Create a Firebase project.
2. Enable Authentication.
3. Enable Google as a sign-in provider.
4. Enable Phone as a sign-in provider for SMS OTP verification.
4c. Enable Cloud Messaging for push notifications. The mobile code is already
   wired (`FirebasePushMessagingGateway` + in-app notification center); it stays
   a no-op until Firebase is enabled. To deliver pushes you also need:
   - iOS: an APNs auth key uploaded to Firebase and the "Push Notifications"
     capability on the Runner target.
   - Current backend status: `POST /devices` stores per-user tokens and the
     firebase-admin sender is implemented. Securely set
     `FIREBASE_SERVICE_ACCOUNT_JSON`, switch `PUSH_SENDER=firebase`, and test on
     a real device. The default remains `mock`.
   - For complete in-app account deletion, also set
     `FIREBASE_AUTH_DELETE_ENABLED=true`. This makes the backend delete the
     Firebase UID last and reject deleted/revoked ID tokens through Firebase
     Admin. Test with a dedicated account before production.
   - Native Apple token revocation is available only on iOS/macOS. Do not expose
     Apple Sign-In on Android/web until PostDee has a server-side Apple token
     revocation flow.
4b. Enable Apple as a sign-in provider (App Store policy requires Apple Sign-In
   whenever Google Sign-In is offered). The mobile code is already wired
   (`FirebaseAppleAuthGateway` via `signInWithProvider('apple.com')`); it only
   needs this provider enabled plus the platform setup below:
   - iOS: add the "Sign in with Apple" capability to the Runner target in Xcode
     and configure the App ID in the Apple Developer portal.
   - Android/Web (optional, only if you support them): create an Apple Service ID
     and set its return URL to the Firebase auth handler.
5. Add the Android app with package name:

```text
com.postdee.postdee_mobile
```

5a. Register the certificate fingerprints from the exact keystore used to sign
the release build. The current PostDee upload/release certificate is:

```text
SHA-1   42:1E:22:8A:13:03:5C:D1:5F:54:83:07:69:76:BB:BD:25:44:68:07
SHA-256 1B:75:C5:A9:24:D1:2E:F0:76:50:DD:2A:EC:5D:C7:3A:A5:58:AE:04:C5:0A:C5:8E:F1:4F:7D:3D:28:C1:6C:9D
```

After adding or changing a fingerprint, download `google-services.json` again.
Google Sign-In can reject an otherwise valid release APK when its signing
certificate is missing from Firebase/OAuth.

Completed on 2026-07-14: both Release fingerprints are registered in Firebase,
and the local Android config includes the generated Release OAuth client
`121898224944-6rcv02n4mq2a33tbem8leeptvoisb1ir.apps.googleusercontent.com` for
package `com.postdee.postdee_mobile` and certificate hash
`421e228a13035cd15f5483076976bbbd25446807`.

6. Download Android config to:

```text
apps/mobile/android/app/google-services.json
```

7. Add the iOS app with bundle id:

```text
com.postdee.postdeeMobile
```

8. Download iOS config to:

```text
apps/mobile/ios/Runner/GoogleService-Info.plist
```

9. Set the Web client id as the mobile server client id:

```powershell
--dart-define=GOOGLE_SERVER_CLIENT_ID=121898224944-1hkh1mrfb5lc1ltraapu10lj1ib465vj.apps.googleusercontent.com
```

10. Run the app with Firebase enabled:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat run --dart-define=ENABLE_FIREBASE_AUTH=true --dart-define=GOOGLE_SERVER_CLIENT_ID=121898224944-1hkh1mrfb5lc1ltraapu10lj1ib465vj.apps.googleusercontent.com
```

11. Test Google Sign-In on a real Android or iOS device.
12. Use the Home screen Phone verification card to send an SMS OTP, verify the code, link the phone number to the Firebase user, and refresh the Firebase ID token before testing Basic posting.

## Backend Checklist

Set backend auth to Firebase after mobile sign-in works:

```env
AUTH_PROVIDER="firebase"
FIREBASE_PROJECT_ID="postdee-3c163"
```

Then test:

- `GET /auth/me` with a real Firebase ID token.
- `POST /posts` with the same token after phone verification. Basic should be blocked until the token includes `phone_number`.
- `POST /captions/generate` with the same token and Starter or Pro entitlement.

## Local Development Mode

Firebase Auth is off by default in local scaffolding. In that mode, the Flutter app uses mock development headers such as:

```text
x-postdee-user-id: local-dev-user
x-postdee-subscription-plan: PRO
x-postdee-phone-verified: true
x-postdee-phone-number: +66812345678
```

This is useful for development only. Production must use Firebase ID tokens.

## Current Project Behavior

- If Firebase Auth is disabled, the app shows a local mock auth message.
- If Firebase Auth is enabled but project files are missing, the app keeps running and shows the setup issue instead of crashing.
- If Firebase Auth is initialized, the Google Sign-In gateway can create a Firebase session and the API client sends the ID token automatically.
- The Apple Sign-In gateway is implemented the same way. With Firebase
  initialized it presents the native Apple sheet on iOS; it still needs the Apple
  provider enabled and the iOS "Sign in with Apple" capability to work on device.
- The Home screen can send and confirm Firebase Phone OTP codes after the user signs in with Google.
- The backend unlocks the Basic 3-post free quota only when the authenticated user has a verified phone number.
