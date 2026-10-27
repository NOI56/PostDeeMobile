# Managed PostPeer Mobile Connection Trial

Date: 2026-10-25

## Purpose and implemented scope

Try PostPeer's recommended Android Chrome Custom Tab approach using its
existing managed OAuth apps. The customer still authorizes the connection;
this trial does not require PostDee to register a new social developer app.

- Open HTTPS connect URLs with Android `CustomTabsIntent` through a small
  platform channel. Use an external browser when Custom Tabs are unavailable
  or opening fails. Avoid the installed URL-launcher implementation's internal
  fallback to an embedded WebView. Other platforms retain external launching.
- Bind the mobile pending attempt and asynchronous results to the starting
  PostDee auth session. After the app leaves the foreground and that session
  returns, call the existing authenticated
  `POST /social-connections/refresh`. Keep manual refresh available.
- Derive connected status from the backend's PostPeer profile integrations.
  Opening a browser, returning to the app, or a successful launch result alone
  does not mean authorization succeeded. Social tokens remain at PostPeer.

No API fields, `redirectUri` contract, mobile deep-link completion handler,
signed completion response, direct social SDK, or direct publisher are added.
Users return to PostDee themselves in this trial. A cold start can recover
provider state through the existing manual refresh flow.

## Provider correspondence and remaining boundaries

PostPeer's 2026-10-09 email says it uses TikTok web OAuth and recommends Chrome
Custom Tabs; it says installed TikTok may continue the flow in-app. This is
not a guarantee for every device, account, browser, or social platform.

Its 2026-10-25 reply says connect links are single-use, expire in ten minutes,
and are bound to project/profile rather than browser. Forwarding a live link
can connect the recipient's account to that profile. The consent screen does
not identify the PostPeer profile. PostPeer supplies its own CSRF state and
does not sign the return response. A client nonce alone would not prove that
the intended customer owns the resulting account. This trial does not remove
these provider-link ownership limitations or claim customer rollout approval.

PostPeer says `platformUserId` is stable across reconnects/profiles for the
four current destinations; TikTok `open_id` is scoped to its developer app.
One account can belong to multiple profiles, and reconnecting the same
account/profile can reuse an integration ID. Integrations are saved before
redirect and can be recovered using the authenticated integrations list.
These are provider statements; real connected-account verification remains
required. Publishing targets remain TikTok, YouTube Shorts, Instagram Reels,
and Facebook Page Reels, subject to that verification.

## Physical-device acceptance checks

Record Android/browser/TikTok versions, outcome, selected account, whether a
password was requested, and whether a handoff actually occurred. Do not record
connect URLs, tokens, passwords, or account-identifying screenshots in logs.

| Case | Expected check |
| --- | --- |
| TikTok installed and signed in | Observe browser versus installed-app handoff; confirm the intended account in PostDee after authorization. |
| TikTok absent or signed out | Browser authorization remains usable; additional login may be required. |
| Custom Tabs unavailable or opening fails | External browser opens; no embedded WebView is used. |
| Cancel or deny authorization | Returning does not invent a connected status. |
| Return before authorization completes | Provider status controls the result; manual refresh can retry later. |
| App closed during authorization | Reopen and use manual refresh to recover provider state. |
| Sign out or change PostDee session mid-flow | No late result or automatic refresh is applied to the replacement session. |
| Link expired or already used | Starting a new attempt gets a fresh link; no success is inferred from launch. |

Automated checks cover local launch/fallback and lifecycle behavior only;
record actual commands and results when run. Physical-device login reuse,
native handoff, cancellation, and connected-account publishing remain pending
until they are exercised with authorized test accounts. Run any publishing
check separately with the intended account and explicit privacy choices.

## Follow-up: the other three platforms

The same launcher and session-bound return refresh already apply to TikTok,
Facebook Pages, Instagram, and YouTube. There is no TikTok-only runtime branch.
The added four-platform widget coverage exercises the actual default launcher
through a mocked Android channel, preserves each provider URL including its
encoded state, and checks that only the server-confirmed platform becomes
connected. These are simulated responses, not live social authorizations.

On 2026-10-25 the user reported that TikTok's `Use TikTok app` button opened
TikTok. This confirms that observed handoff only; password reuse, completed
consent, the final saved connection, and publishing were not reported verified.
Facebook, Instagram, and YouTube still need their own real-account checks.

The platform controls its login UI and any installed-app option. YouTube
authorization uses a Google account, so a Google account-selection/consent page
is expected rather than an identical `Use YouTube app` button. Instagram's
default Direct Instagram Login is preserved; changing to Facebook Login is
not an installed-app handoff switch. Do not rewrite OAuth URLs into social-app
schemes or strip their state/scopes/callback parameters.

## Local verification recorded on 2026-10-25

- `flutter test --no-pub test/connections_screen_all_platforms_test.dart
  test/connections_screen_lifecycle_test.dart
  test/social_connection_url_launcher_test.dart test/profile_screen_test.dart`:
  all 39 tests passed. Coverage includes all four platforms' URL forwarding
  and provider-confirmed status, browser failures, cancellation/retry, duplicate
  resume, resume before launch completes, session changes, late responses, and
  disposal.
- Targeted `flutter analyze --no-pub` on both implementation files and both new
  test files: no issues found. Dart formatting checks passed.
- Android `:app:compileDebugKotlin`: passed with Android Studio's bundled JDK.
- Debug APK built using the existing local staging defines and build number
  `12052`; installed over the emulator's staging app using `adb install -r`.
  The old build number `1` was rejected as a downgrade; no app uninstall or
  data reset was performed.
- Scoped `git diff --check`: passed. Existing unrelated workspace changes
  were preserved.

The APK is generated at
`apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`. It is a staging
debug build, not a production release or proof of social authorization.

Implementation files:

- `apps/mobile/lib/features/platforms/connections_screen.dart`
- `apps/mobile/lib/features/platforms/social_connection_url_launcher.dart`
- `apps/mobile/android/app/src/main/kotlin/com/postdee/postdee_mobile/MainActivity.kt`
- `apps/mobile/android/app/src/main/AndroidManifest.xml`
- `apps/mobile/android/app/build.gradle.kts`
- `apps/mobile/test/connections_screen_lifecycle_test.dart`
- `apps/mobile/test/connections_screen_all_platforms_test.dart`
- `apps/mobile/test/social_connection_url_launcher_test.dart`

Current-behavior documentation is synchronized in `README.md`, `API.md`,
`ARCHITECTURE.md`, `ROADMAP.md`, `apps/mobile/README.md`, the 2026-06-26
PostPeer plan, and the separate 2026-10-21 direct-native proposal.

## References

- [PostPeer connection flow](https://www.postpeer.dev/docs/social-accounts/connect)
- [PostPeer Instagram login methods](https://www.postpeer.dev/docs/platforms/instagram)
- [Google/YouTube authorization](https://developers.google.com/youtube/data/guides/auth/installed-apps)
- [Direct TikTok proposal](2026-10-21-tiktok-native-connection.md)
- [Current API](../../../API.md)
- [Architecture](../../../ARCHITECTURE.md)
