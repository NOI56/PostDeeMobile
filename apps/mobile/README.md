# PostDee Mobile

Flutter mobile app scaffold for PostDee.

## Smooth publishing progress (2026-10-20, locally verified and Staging APK installed)

The selected first full-screen design adds one orbiting dot, a clipped light,
destination chips and stage indicators. Time does not advance progress or report
success. Motion stops for background/reduced motion/TickerMode and is disposed
when publishing ends. Existing outcomes and remembered settings remain intact.
The 51 focused cases and full Mobile suite (2,488 passed / three optional skips)
pass, followed by an explicit final preview run with five controlled pending
screen captures. Analysis is clean. Staging x86_64 APK12028 is built and its
package/environment verified; its guarded update from 12027 passes with the
signed-in Home, existing draft, quota, channels and history retained. Motion is
verified using controlled production-widget fixtures.
No real provider publish, API/configuration/schema/dependency change or migration.
Source is integrated into `main` on 2026-10-20 for the authorized main/push
delivery. APK12028 remains the installed, verified runtime; no API deploy is needed.
[Verification record](../../docs/superpowers/plans/2026-10-20-publish-progress-smooth-motion.md).

## Remembered channel settings (2026-10-20, YouTube native restart verified)

Remember only reusable choices for this device and connected channel: TikTok
Inbox/Direct mode, YouTube visibility/audience, Instagram feed sharing and
Facebook Publish/Page draft. New clips review their own AI/synthetic content and
confirmations; TikTok privacy/interactions have no remembered selection. Explicit
Save updates defaults; Cancel does not. Existing drafts retain their own values.
No API migration or server deployment is needed. Full tests pass 2,480 with two
optional skips; analysis is clean. Staging APK12027 is built and installed on the
x86_64 emulator. After login, YouTube Save and force-stop/restart verify that
visibility/audience return in a fresh composer while synthetic-media and
community confirmation stay unanswered. Cancel/reopen retains the saved audience;
final Home retains the existing draft entry, quota and channel count. Meta
coverage remains automated fixtures. Integrated into `main` with smooth progress
on 2026-10-20; its runtime is retained in APK12028.
See the
[work record](../../docs/superpowers/plans/2026-10-18-remember-platform-defaults.md).

## Publishing activity (2026-10-18, Android Staging delivered)

Selected variant 3 combines the shared sending badge, indeterminate rail and
per-channel delivery results in Home, Calendar and detail. One guarded clock per
post keeps badge/channel activity together, stops for reduced motion, inactive
tickers and background state, and never invents a progress percentage. Draft,
private, unlisted, live, failed and unconfirmed outcomes remain distinct.

Home refreshes its existing recent-post read every 30 seconds only while a
loaded post is `PUBLISHING`, the app is resumed, Home is active, its route is
current and the same stable owner is signed in. Calendar retains its existing
visible `QUEUED`/`PUBLISHING` polling. Detail is a snapshot: refresh the parent
list and reopen it for newer results; there is no single-post GET. No API,
schema, dependency, flag, entitlement or migration changes. Targeted tests pass
145/145; full Flutter passes 2,437 with two optional previews skipped, and
analysis reports no issues. CI builds Staging 12026 with the existing Test Store
configuration after repeating the suite and 17 build-guard tests. APK inspection,
local signing and the guarded adopted-volume update pass; Home, Calendar,
existing detail and Account retain Pro 244/250, drafts and connected channels.
The compatible API is Live. There was no new provider post or native active-sending
FPS measurement. See the
[plan and verification record](../../docs/superpowers/plans/2026-10-18-publishing-motion.md).

## Automatic YouTube title (2026-10-18, local implementation)

The shared caption supplies the YouTube title preview automatically. An empty
raw `youtubeTitle` means automatic; `resolvedForCaption` takes the first sentence
of the first nonempty line, removes `<`/`>`, and limits it to 100 Unicode code
points. The full caption remains the description under its existing validation.
`ปรับชื่อเฉพาะ YouTube` reveals the custom input. Caption edits preserve an
explicit title; `ใช้ชื่อจากแคปชัน` clears it and resumes the live preview.
Drafts retain that raw automatic/custom choice and existing explicit titles.

Review/submission use the resolved existing nested
`platformSettings.YOUTUBE_SHORTS.title`. There is no top-level API `youtubeTitle`
or manifest/schema migration. Blank captions are allowed only for YouTube-only
posts with a valid custom title and all required visibility, audience,
synthetic-media and certification answers. Other destinations retain caption
requirements. Required consent, account/readiness checks and recovery protections
are unchanged. Local automated verification passes; [results and delivery limits](../../docs/superpowers/plans/2026-10-18-unified-platform-settings.md#youtube-title-follow-up-2026-10-18-local-implementation)
include APK12025 build/install on the existing volume and basic Home launch with
retained drafts/posts. Entitlement loading, exact updated API deployment and
provider publication remain unverified; blank descriptions need the updated API.

## Trial access and purchase confirmation (2026-10-18, local implementation)

Effective subscription `plan` controls features and may include an administrator
trial; optional `purchasedPlan` is used only to confirm a paid store purchase.
RevenueCat purchase/restore polling cannot treat a Pro trial as a paid Pro receipt
and can confirm paid Starter while retaining effective Pro access. The purchase
resync client reads paid metadata separately from AI recovery, preserving the
original session binding. Older API responses without the new field retain the
existing behavior.

Purchase preparation advertises `purchaseConfirmationProtocol:2`; acknowledgement
remains `preparationProtocol:1`. New APIs gate incompatible clients before buying
when a trial raises access above the purchased plan. Deploy the API and applicable
workers before this Mobile update, and use compatible Mobile before giving
customer trials. No real purchase, administrator grant, deployment or installation
is part of this local implementation. See the [admin guide](../../docs/ADMIN_CONSOLE.md).

The separate admin usage/report/refresh follow-up changes only API reads and web
assets. It keeps these Mobile quota and purchased/trial contracts intact and
requires no Mobile installation. Source `fc457b2` is merged/pushed to main and
Live on Staging deploy `dep-dba64iqjnfac73egt8i0`; API/Flutter CI passes and fresh
owner sign-in/report reads pass. The installed Mobile package is not replaced
for this API/web-only update; see the
[usage accuracy record](../../docs/superpowers/plans/2026-10-18-admin-usage-accuracy.md).

## Unified publishing settings (2026-10-18, Android Staging delivered)

All four settings sheets share a logo/account header, grouped controls, adaptive
height and fixed Cancel/Save actions above the keyboard. Inbox opens without
Direct creator reads; switching to Direct fetches current options, and returning
to Inbox invalidates in-flight results. TikTok privacy/interaction restrictions
and consent remain enforced. YouTube retains editable blank-title suggestions,
manual audience/synthetic-media answers and certification.

Instagram/Facebook show cover context and optional AI-generated video disclosure.
Null is unanswered and serializes without a key; true/false are explicit choices,
can be cleared, survive draft round trips and appear in review. AI captions alone
do not imply AI-generated media. Facebook remains Page Video, with a clear
distinction between sending a Page draft and saving a local PostDee draft.

Source `866f0e3`, based on main `c813eef`, is merged/pushed to main and Live on
Staging deploy `dep-dba2oieq1p3s73a3g6qg`. Exact-source Backend/Flutter CI
`39089186176` and unsigned iOS build `39089186129` pass; health/readiness return
HTTP 200. Android **12024** is installed after a verified full AVD backup, adding
a separate **16 GiB private volume** and recovering the existing app data. A
guarded same-volume reinstall and cold boot retain version 12024, the original
UID and the mounted volume. Native Home retains the same signed-in account and
two local drafts; actual saved-video playback completes. The compact TikTok
Inbox sheet was checked read-only with Cancel. Other new platform dialogs were
not checked natively in this storage follow-up; their widget previews/full
regression results above remain separate from connected-account publication.
One existing draft displays a connection warning despite both selected channels
being connected. The recorded source analysis suggests stale early validation;
this storage-only follow-up does not change that Dart flow or prove publishing.
The separate installer/tool follow-up has local validation and requires no new
API deployment; the CI IDs above cover the original feature source `866f0e3`.
Other environments must deploy API and publishing workers before Mobile. Draft
manifest version stays 3; no dependency/configuration/migration change is needed.
Checks and preview evidence:
`../../docs/superpowers/plans/2026-10-18-unified-platform-settings.md`.
Full Mobile verification passes **2,371 tests** with two optional preview skips,
whole-project analysis and the exact Staging APK12024 build. The new five-sheet
preview runs separately with bundled Thai fonts and fixture accounts. Real
connected-account publication and iOS/physical-device checks remain unverified.

## Channel publishing preflight (2026-10-15, Android Staging delivered)

The new uploader validates the exact trimmed caption for selected channels:
YouTube 5,000 UTF-8 bytes/no angle brackets, Instagram 2,200 conservative UTF-16
units and Facebook 63,206 conservative UTF-16 units. An owned FFprobe session with
bounded execution checks the final outgoing file after rendering, rather than
guessing from the original clip. YouTube Shorts is limited to 180 seconds;
Instagram checks MOV/MP4 container/duration/size/dimensions/FPS/codecs/audio, and Facebook keeps its
Page Video limits. Unknown metadata blocks the affected media check.

Channel-readiness loads at channel selection and is refreshed before upload and
post creation. Explicit reconnect/permission problems block submission; unknown
capabilities are labeled unverified and an old API's 404 is the only fallback.
The response is a snapshot, not a promise about a delayed post's future access.
Optional metadata stays bound to an upload receipt's media fingerprint. Legacy
receipts/drafts and unknown post request IDs are retained; an unproven cached
render is not silently discarded and re-uploaded. Existing accepted submissions
can first be recovered through a read-only original-intent lookup, including
legacy receipts without media metadata; missing/unverified items stay protected
and a recovered FAILED result stays failed. Ordinary connection lists expose
revisions for every platform for list/readiness binding. A YouTube title suggestion fills
only a blank title; audience/AI/certification answers remain manual. Review shows
those answers, Instagram feed choice and the YouTube Terms/copyright notice.

Source `2e86634` is merged/pushed to main and Live on Staging before Android
**12023** was installed on emulator 5556 with the same signer and permissions.
Login and both local drafts remain; Home loads the package and 2/4 connected
channels after refresh. The real Mobile API client reads current connections
and readiness successfully, with matching TikTok/YouTube revisions and unknown
capabilities correctly labeled unverified. Instagram/Facebook are disconnected.
No upload/publication or account reconnection was performed.
The full Mobile suite passes **2,351 tests** with one optional preview skipped;
analysis, exact Android build, Backend/Flutter CI `38766556966` and unsigned iOS
CI `38766556987` pass. No iOS device check or schema/env/dependency change is
included. Earlier TikTok sections are historical delivery records. Validation:
`../../docs/superpowers/plans/2026-10-15-platform-publish-preflight.md`.

## TikTok Direct Post (2026-10-15, Android Staging delivered)

TikTok settings now offer Inbox or Direct Post using current account-bound
creator options. Direct requires a manual privacy choice, permitted interaction
settings, commercial/AI disclosure and explicit music/policy confirmation. Fresh
options are checked around native preparation/upload and before submission;
account/content changes and restored drafts clear consent. Prepared-video
duration is retained in optional receipt metadata for safe reuse, while older
draft manifests remain readable and unproven receipts cannot silently be resent.

No TikTok watermark is added. Inbox delivery, native CFR/H.264/AAC preparation,
local draft ownership, upload reuse and idempotent submission are preserved.
Staging API `5681602` is Live and Android **12022** is installed with `install -r`,
preserving login, first-install identity and the locally saved open form. The
actual account-bound sheet fetched current creator options: public/friends/self
privacy choices, no privacy default, restricted Duet disabled, interactions and
consent unchecked, and Save disabled. Only the privacy menu was opened; no
settings were saved, media uploaded or post submitted. Backend/Flutter CI
`38757735457` passes; iOS CI `38757735448` passes its unsigned build and IPA
artifact checks. iOS device delivery, provider audit/public approval and actual
Direct publication are still unverified. Other environments
must deploy API first; older APIs leave Direct unavailable. Validation:
`../../docs/superpowers/plans/2026-10-15-tiktok-direct-post.md`.

## TikTok native completion with background engines (2026-10-15)

The real-app timeout occurs when a Firebase background engine owns FFmpeg's
global completion callback without an event subscriber. The native TikTok
adapters now await each pre-created session's MethodChannel execution result
and retain its cancellation ID before work finishes. Existing deadlines, media
checks, draft/receipt/request safety, Firebase messaging, and Calendar stay intact.
The upload copy normalizes into TikTok's 360–4096-pixel dimension range (the
actual 180x320 QA clip needs 360x640), with original media retained and a local
v2 preparation policy guarding reuse of older receipts.
All 2,252 Mobile tests and analysis pass. Six native two-engine cases, a cold
start and scoped cancellation pass with the exact final helper. Staging APK
12021 passes startup/configuration checks and is installed on the user emulator;
the account and original draft remain, with TikTok selected at review. Fresh
Home/Profile show Free 0/3 and an unverified phone; phone verification is needed
for the free allowance. Actual publication is unverified. No push/merge,
API/schema/configuration/dependency change, or real post is included. Receipt:
`../../docs/superpowers/plans/2026-10-15-tiktok-native-session-completion.md`.

## Calendar activity and TikTok preparation (2026-10-15, Staging delivered)

Calendar loads all owner-scoped post activity through `GET /posts`, including
immediate and partial results. Its new nullable-schedule model preserves strict
scheduled callers and exposes queue actions only for queued real schedules.
TikTok-selected uploads run on-device H.264/AAC constant-30-FPS preparation and
validate the stream and a bounded decoded-video prefix before upload. Cancel,
timeout, account changes, or invalid output retain source/draft data and stop
remote submission. A persisted
preparation-policy receipt guards upload reuse; incompatible old receipts use
the existing explicit-new-attempt confirmation instead of silent reposting.
Known provider frame-rate rejections show specific Thai guidance. No new
dependency, subscription rule, or backend schema is introduced. Source
`0f2941b` is merged/pushed to main and CI `38725833299` passes Backend/Mobile,
including 2,226 Flutter tests and analysis. The API is Live first on Staging
deploy `dep-db8bdj2vcj2c738t2ke0` with health/readiness HTTP200. After the user
approves discarding one old uncommitted installer to free space, the exact
APK12020 replaces12019 on emulator5556 without clearing data. The existing
account remains signed in; the Oct14 immediate partial post appears in Calendar
under both All and Shorts. No real social retry is performed. Full tests,
native codec results, exact Staging APK, and delivery status are recorded in
`../../docs/superpowers/plans/2026-10-14-tiktok-media-and-calendar-activity.md`.

## Shop-logo Positioning (2026-10-13)

Shop information and decoration now open the same circular crop preview after
gallery selection. Drag, pinch/slider zoom and reset determine the square PNG
uploaded only on confirmation. Cancel keeps the previous logo and draft; an
account change closes the dialog. A route guard prevents a late export from
closing the appearance editor underneath a dismissed crop dialog. Main and
Staging APK verification passes 2,185 Flutter tests, analysis and the exact x64
build/install12019 with retained shop data and native crop-cancel checks. Receipt:
`../../docs/superpowers/plans/2026-10-13-shop-logo-position-main.md`.

## Main Integration (2026-10-13, completed)

The user-authorized latest branch is fast-forwarded and pushed to main at
`be7732f6a14f9f91e6eda4a39179b30c385427ab`, after exact-head CI `38386971185`
passed 2,058 Mobile tests and analysis (No issues, 8.9 s), plus Backend checks.
Runtime matches Staging Live `7b0c51d` and the existing exact8016 APK; no rebuild,
reinstall or new native full-flow claim. Preserve the original data and Oct12
receipts, including unverified physical-device FPS. Staging auto-deploy stays
disabled; Production API/database remain user-suspended with no new deploy.
The earlier “no main merge” statements are historical. Plan:
`../../docs/superpowers/plans/2026-10-13-main-motion-audit-integration.md`.

## Mobile Motion Smoothness Audit (2026-10-12, Staging delivered)

Audit all main tabs, composer, video preview, publish results and account sheets.
Settle interrupted press/selection/entrance feedback, remove outgoing Home hero
controls, release background thumbnail decoding and prevent shop-preview entrance
replay. Preserve native actions/semantics, data, all 100 templates and requested
ambient effects. Final source passes 2,058 Flutter tests and analysis (No issues,
8.6 s). Exact Staging x64 4016/8016 is built/installed; safe native tab/day/filter,
preview background/resume and composer-return checks preserve data. Debug emulator
samples are diagnostic and do not prove a speedup or certify physical-device
60/120 FPS. Populated-content physical profile-mode measurement remains unverified.
No API/schema/config/dependency change or new migration. Combined source
`7b0c51d71090e5c080182daa8630d5b90e6d3d49` is pushed to
`origin/codex/audit-system-fixes`; CI `38249605630` passed both jobs/2,058 Mobile
tests/analysis14.2 s. CI APK build/upload was skipped; installed8016 is retained.
Render `dep-db6d96vavr4c73b21o2g` is Live at 19:39:44 GMT+7 with 16 existing
migrations/no pending and health/readiness HTTP200. Post-Live safe Home→Shop→
Account→Home preserves data; disabled publishing/memory queue stay unchanged.
No main merge or second source deployment for the docs-only receipt. Keep the
initial 8015 receipt below separate. Plan:
`../../docs/superpowers/plans/2026-10-12-mobile-motion-smoothness-audit.md`.

## Bottom Navigation Motion (2026-10-12, Staging delivered)

The approved shell-only follow-up adds selected-icon halo/lift/scale/color and
native press feedback to the four ordinary tabs. Retain the running dot, center
Create post pulse, 84 dp controls, labels/semantics, route callbacks and retained
owner-scoped screen state. Reduced motion, lifecycle and parent `TickerMode`
settle effects without replay. No API/persistence/business/schema/config/
dependency or migration change. Initial dock-only source passed 1,979 Flutter
tests and analysis, including 13 new cases. Exact Staging x64 APK4015/8015 was
installed then with retained account/shop data. Native four-tab feedback and one
composer open/close/previous-tab return pass; guard/accessibility paths use
fixtures. Combined source `7b0c51d` passes CI `38249605630` and is Live through
`dep-db6d96vavr4c73b21o2g`; current8016 has the separate 2,058-test audit receipt.
Keep initial8015 verification distinct; no main merge. Plan:
`../../docs/superpowers/plans/2026-10-12-bottom-nav-ui-motion.md`.

## Account UI Motion (2026-10-12, Staging delivered)

The approved Account-only follow-up adds passive press feedback and finite
content/setting-sheet entrances. Keep native actions and stable content state;
provider updates do not replay entrances. Reduced motion, lifecycle,
`TickerMode` and inactive tabs stop feedback. Preserve owner/generation guards,
email/phone, billing/settings/delete/sign-out and existing subscription refresh.
No API/schema/config/dependency/migration change. Final source
passes 1,966 Flutter tests and analysis, including 29 new Account cases; exact
Staging x64 APK 4014/8014 is built/installed with the retained account. Native
edit/connections/paywall browse, settings close/help/tab-return checks pass with
unchanged account/settings and retained scroll. Motion/accessibility and positive
business actions use fixtures. Prior Shop 1,937/8013 is separate history. Combined
source `904a3f89c3601a1fac28eedfaf8781434b19bd49` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38205149761` passed both jobs
with 1,966 Mobile tests. CI APK build was skipped; local installed 8014 is retained.
Render `dep-db66eh8473hc73dabfcg` is Live at 11:53:11 GMT+7; 16 existing migrations/
no pending and health/readiness HTTP 200. Post-Live Home → Shop → Account keeps
account/shop data; no main merge or change to disabled publishing/memory queue.
Plan: `../../docs/superpowers/plans/2026-10-12-account-ui-motion.md`.

## Shop-link UI Motion (2026-10-12, Staging delivered)

The approved mobile follow-up adds brief manager/button feedback, current-only
section/category entrances and guarded drag-proxy feedback. Respect reduced
motion, lifecycle, `TickerMode` and hidden tabs. Preserve existing owner-scoped
local autosave, explicit publication, confirmed-URL sharing, 100 templates and
all retained link/media/font settings. No public-page motion or API/schema/
configuration/dependency change or migration is required. The earlier Shop-only source passed
1,937 Flutter tests and analysis, including 22 new motion cases. Exact Staging
x64 APK 4013/8013 was installed at that Shop release with retained account/shop data. Native manager/
info/Add cancel/theme browse/preview cancel/review/navigation checks pass;
mutation/Save/Apply/publication paths use controlled fixtures. Combined source
`904a3f8` passed CI `38205149761` and is Live via `dep-db66eh8473hc73dabfcg`;
installed 8014 is retained. Post-Live Shop keeps its two original links/confirmed URL. See
`../../docs/superpowers/plans/2026-10-12-shop-link-ui-motion.md`.

## Guided Create Post (2026-10-12, Staging delivered)

The approved “ทีละขั้น” presentation keeps clip, caption, destinations and
review/time/send as four steps. The AI action is visible with optional controls
collapsed; destination account names, known clip metadata and a concise
step/channel-count footer make the next action clearer. Date/time remains in
the shared review and schedule panel. Preserve
explicit drafts, cover editing, caption-style learning, SEO/fallback handling,
owner guards and all publishing/package/scheduling rules. Connection owner/request
generation guards reject old results and hide names during loading/error or
owner mismatch without adding requests. Home press feedback
and current-only step entrance must respect reduced motion, `TickerMode` and
background state. No API, migration, dependency or environment change is required.
The connector follow-up adds three thin lines between the four circles and
outlines pending steps. Latest feedback work adds focused inline caption
validation, an AI wait/full-response reveal tied to the existing operation and
a temporary check after verified explicit local Save. The final rapid-save
guard rejects busy callbacks before clearing success-feedback generation.
Final feedback includes 10 new tests; guard/save tests pass 86/86, the full suite
passes 1,915/1,915 and analysis passes. At that composer release, APK 4012/8012
was installed with the retained account; native empty-caption Next showed inline
error/focus/keyboard, then clean empty step two was left open. Prior
187/187, 1,914/1,914 and native 8011 validation are pre-guard history; AI/save
success uses fixtures. The preceding connector
source passed 1,905 Flutter tests and analysis; Staging APK 4010/8010 was installed
with the same signer/session, and native checks showed lines/outlines, active selection
and no invented completion. The base 8009 four-step/AI/blocked-confirmation
checks are a separate receipt.
Positive identity/metadata/schedule/AI and narrow/large-text/motion cases use
widget fixtures. The agent left the earlier user-selected form untouched;
installation followed the user's return to Calendar.
Authorized source `430f82ad1c493b5a8bcf1f51b007e2a7604dae1e` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38200231563` passed both
jobs. No remote APK build was requested; installed 8012 was unchanged in that delivery. Render
specific-commit deploy `dep-db65d08473hc73d6fp50` is Live at 10:41:35 GMT+7;
16 existing migrations have none pending and health/readiness return HTTP 200.
Social publishing stays disabled, the queue remains memory and main is not merged.
Receipts are separate from Calendar/Home in
`../../docs/superpowers/plans/2026-10-12-create-post-guided-ux.md`.

## Calendar Compact Revision (2026-10-12, Staging delivered)

The compact-list Calendar has week/month, Today,
real day counts, all/four-platform filters and concise time/status rows. It starts
in week view and retains the existing upcoming-day selection if today has no post.
Creating
from Calendar passes the selected local date into the existing composer;
it must preserve saved-draft schedules and existing future/paid-plan checks.
Refresh retains confirmed content and exposes retryable failures. API,
publishing, provider and environment contracts remain unchanged. Composer date
labels share its injected local clock; `DateTime.now` remains the default.
Authorized SHA `3368f4d` is pushed; exact-source CI `38187776818` passes 1,883
Flutter tests and analysis. Local APK 4007/8007 installs with retained data/session
and a post-deploy Home cold-launch smoke. Full native Calendar/date-handoff/Free-guard/refresh
checks belong to the preceding 8006 revision. Positive queue/partial/mutations
are fixtures for the empty real account. Exact-source Render deploy
`dep-db62jdvlot8c738l37q0` is Live at 07:30:34 GMT+7 on 2026-10-12; 16 existing
migrations have none pending and health/ready return HTTP 200. Staging social
publishing remains disabled. The Home release is a separate receipt.
See `../../docs/superpowers/plans/2026-10-11-calendar-ux.md`.

### Calendar Motion Follow-up (2026-10-12, Staging delivered)

The Calendar reuses Home's press feedback and initial-loading skeletons.
Day/view/platform selection takes 160 ms, week/month grid height 220 ms, and
the current owner/day/filter section enters with a 180 ms fade/eight-pixel
translation. Outgoing post controls are unmounted immediately. Silent refresh
keeps confirmed data and selection. Reduced motion, inactive tabs and background
state stop effects. Owner guards, date handoff, scheduling/package rules and API
behavior stay unchanged; no migration, environment setting or dependency is
added. Authorized source `df8df1d` is pushed; exact-source CI `38189859822`
passes 1,891 Flutter tests and analysis. Render deploy
`dep-db6327ajnfac73c7vr90` is Live at 08:02:20 GMT+7; 16 existing migrations
have none pending and health/readiness return HTTP 200. At that Calendar release,
locally verified Staging APK 4008/8008 was installed with its account;
post-Live native refresh preserved the selected date/filter and account state.
The later guided revision updates the local APK. Check the separate
follow-up receipt in `../../docs/superpowers/plans/2026-10-11-calendar-ux.md`;
the preceding Staging release does not verify these effects.
## Security integration delivery (2026-10-13)

Current-main UI, Store link publication/appearance, scheduling/composer,
Firebase UID credential refresh and billing pending-confirmation cache remain.
The selective security port adds session-generation guards, bound HTTP clients,
native auth serialization for OTP/Apple revocation, protocol-1 purchase readiness
and scoped in-app push history/recipient matching. New readiness failure stops
a new buy; a previously dispatched payment keeps the confirmation/retry flow.

The API rollout is additive and retains legacy GET user preparation, now owner
fenced. Deploy that API before installing this preparation-aware Staging app;
read-only GET is deferred until incompatible buying builds are retired.
Full Flutter tests pass (2,171) and analyze has no issues. Exact Staging debug
APK8017 from `9244f16` builds and retained-data Emulator smoke passes after the
compatible API reaches Staging Live. Shop remains published with both original
links; Account, paywall prices and phone-form open/cancel work. No actual
purchase, OTP send, post publish or account deletion was performed. Delivery evidence:
`../../docs/superpowers/plans/2026-10-13-security-main-delivery.md`.

The native auth queue retains actual SDK settlement after a caller/UI timeout,
including the Google picker and Firebase exchange. Mock sign-in uses the
configured mock UID; existing server profiles reload under that owner, while
older drafts stored under `local-mock-user` remain in their original local scope.
This patch does not migrate or delete those drafts.

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

The helper validates the Staging API, Firebase flag, mock-auth flag, Google
server client id, and RevenueCat Test Store overlay before invoking Flutter. It
uses an ignored `staging.local.json` when present and otherwise falls back to
the checked-in, non-secret `staging.local.example.json`. Device `run` and
`build-apk` commands additionally require an ignored `revenuecat.local.json`
with `ENABLE_REVENUECAT_BILLING=true` and a public Test Store SDK key beginning
with `test_`. In a Git worktree the helper first checks that worktree, then
searches ancestor workspaces for `apps/mobile/revenuecat.local.json`; it never
copies or prints the key. Missing or invalid billing configuration stops the
device build instead of silently selecting the unusable direct Google Play
path for the `.staging` package. The `test` command does not require the local
overlay.

Do not use a raw `flutter build apk` for an installed Staging build: omitting
the Dart define files safely disables Firebase Auth and RevenueCat. The helper
rejects `--profile`, `--release`, Dart-define overrides, non-Test-Store SDK
keys, and server secrets because those could mix Staging and Production
configuration. A different machine/CI debug keystore also needs its SHA-1 and
SHA-256 registered in Firebase Staging.

When local tooling cannot build, `ci.yml` supports a manual `build_staging_apk`
with an exact `apk_source_ref`. `staging_test_store_billing` defaults to false;
opt in only with the existing public `test_` Android SDK key stored as the
repository secret `POSTDEE_REVENUECAT_TEST_STORE_ANDROID_API_KEY`. The guarded
helper creates merged defines only in `RUNNER_TEMP`, without printing values
or uploading configuration/signing keys. Optional `staging_build_number` accepts
1–2100000000 to preserve normal upgrades; empty retains pubspec behavior.
Only the APK and a source/config/hash/billing-mode/build-number receipt are
uploaded. Re-sign the downloaded copy with the existing local debug key before
updating an installed app, preserve its Test Store mode, and verify native
startup. See [CI delivery details](../../docs/STAGING.md#สร้าง-apk-staging-ผ่าน-github-actions-แบบเลือกเปิด).

For an Android app already on adopted private storage, use the guarded launcher
instead of `-Command run`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\launch-postdee-android.ps1 -AvdName PostDee_Pixel
flutter attach -d emulator-5556
```

The launcher builds from the canonical `main` worktree and preserves the
installed build number. Its shared updater verifies package UID, version and
code path, requires the current adopted UUID to be mounted, and pins that same
volume with `install -r --force-uuid`. Unknown or conflicting storage state
stops installation; it never migrates, clears data, uninstalls or retries on a
different volume. `-ResolveOnly` checks launcher paths without build/install.
The Staging `run` helper refuses an adopted Android target before Flutter can
install; `build-apk` and `test` do not inspect or change the device. Raw
`flutter run` and plain `adb install -r` can select internal storage and expose
a fresh data location even while the adopted-volume data still exists. Use
`flutter attach` after the guarded launcher when debugging this emulator. If
Flutter is not on `PATH`, run the SDK executable printed as `Flutter=` by the
launcher's `-ResolveOnly` output with the same `attach` arguments.
This storage guard is a separate installer/tool follow-up; its checks are recorded
in the 2026-10-18 implementation plan, separate from the original feature CI.

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
an Android release build. Use the Staging helper in the local testing section
below when testing with the RevenueCat Test Store.

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
`revenuecat.local.json` file that contains only
`ENABLE_REVENUECAT_BILLING=true` and either `REVENUECAT_API_KEY` or
`REVENUECAT_ANDROID_API_KEY` with the dashboard's public `test_` SDK key. Never
put the webhook token, subscriber REST key, Google service account, or another
backend secret in this file. The production helper never reads it:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command run
powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk
```

Use `STORE_STARTER_MONTHLY_PRODUCT_ID=postdee_starter_monthly` and
`STORE_PRO_MONTHLY_PRODUCT_ID=postdee_pro_monthly` as the default product ids.
The helper passes the base Staging defines first and the validated Test Store
overlay second, so billing is enabled without moving the key into Git. Do not
submit an App Store or Google Play release with that file. RevenueCat's Play app,
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
