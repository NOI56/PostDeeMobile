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
   - A backend that stores each device's FCM token (exposed via the gateway's
     `onToken` callback) and sends messages — not built yet.
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
