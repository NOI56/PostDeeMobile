# PostDee

PostDee is a cross-platform mobile app and backend for Thai e-commerce sellers,
affiliate marketers, and creators. The product is Thai-first and has an
8-locale foundation (th, en, vi, zh, id, ms, tl, ja), but many active screens
still contain Thai copy and are not fully localized. The Flutter app supports
light and dark palettes (light is the current default), backed by Express,
Prisma, and provider adapters that remain mock-safe until explicitly enabled.

## Compact post quota after clip selection (2026-10-25, implementation candidate)

The uploader's clip-selection step shows a small post-quota strip after a clip
is selected. It uses the existing authenticated `GET /billing/subscription`
snapshot: effective plan, monthly remaining/limit in `หน่วย`, used post units
and a thin remaining bar. Paid members see a short purchased-credit line when
their post bank is nonempty. Basic users who still need phone verification see
that explanation rather than mistaking the gated balance for used-up quota.

Load or refresh for an initial handed-in clip, selection/reselection, app
resume, auth-session changes, successful in-composer subscription resync and
post acceptance/failure or recovery while the composer remains open. Billing or
phone-verification changes are reread on the next such refresh. Owner/session/
request/clip guards reject late results;
loading, missing data or errors show loading/retry without inventing zero.
Selecting a clip does not spend quota, publish, generate AI or open checkout.
Existing post-unit rules, paid add-on access, phone gates and caption-credit
work remain unchanged. No new endpoint, schema, migration or provider change
is required. This is not deployment evidence; see the
[post-quota strip plan](docs/superpowers/plans/2026-10-25-post-quota-strip.md).

## AI caption credits per channel (2026-10-25, implementation candidate)

Advanced AI caption generation costs **one credit per selected channel**:
one, two, three or four selected channels cost 1, 2, 3 or 4 credits. The button
shows `สร้างแคปชั่น · N เครดิต` without adding another cost row. Shared-caption
generation and the legacy keyword endpoint still cost one credit. Starter/Pro
monthly allowances (50/120), plan and add-on prices, and credit expiry rules
remain unchanged.

The API derives the cost from the validated channel selection and reserves the
whole amount atomically, using monthly credits before the retained add-on bank.
Insufficient total credits produce no partial debit or provider call. One
provider operation still produces the selected set. A fallback or failed set
releases the entire reservation; dismissing a successfully generated preview
does not refund it. Responses report requested and actually charged credits.

New Mobile sends `expectedCredits` with the displayed cost. Multiple-channel
requests without a matching confirmation return `409
AI_CAPTION_COST_CONFIRMATION_REQUIRED` before any charge, so older apps cannot
silently spend more than their displayed one-credit price. Coordinate the API
and Mobile rollout: older multi-channel clients need an update, while new
Mobile against the older API can quote more than that API charges. No schema,
migration, provider or flag change is required. This is not deployment evidence;
see the [credit-per-channel plan](docs/superpowers/plans/2026-10-25-caption-credit-per-channel.md).

## Compact AI caption quota strip (2026-10-25, implementation candidate)

The composer adds a small quota strip directly above its existing AI generation
action: effective plan, monthly remainder/limit, used count and a thin remaining
quota bar. A purchased bank adds only a small `+ เครดิตเติม N เครดิต` line when
nonzero. Monthly exhaustion does not block generation while paid add-on credits
cover the selected cost; known total availability below that cost disables the
AI action. Manual caption editing and posting keep their existing rules.

`GET /captions/quota` loads the authenticated quota on composer entry and app
resume. Generation responses update it even if the user changes text or cancels
the advanced-caption preview. Failures and pending refund refreshes reread it;
loading/errors never become a fabricated zero and offer retry when unavailable.
The pushed four-step wizard, account guards, per-platform captions, nonexpiring
credits and existing generation/refund behavior are preserved.

Deploy the additive API before the Mobile build. Older APIs returning `404`
show quota unavailable/retry. There are no package-rule, flag, schema or
migration changes, and this candidate is not a deployment receipt. See the
[implementation plan](docs/superpowers/plans/2026-10-25-caption-quota-strip.md).

## Facebook Page Reels contract (2026-10-24)

Facebook now requests Page Reels only through the existing PostPeer integration.
`FACEBOOK_REELS` always sets `contentType: 'reel'`, with no Page feed fallback.
Existing publish/Page-draft choices, optional AI disclosure, per-platform captions
and immutable target snapshots are preserved. Real-account Reel/draft/thumbnail
E2E remains pending; the contract change alone does not establish production readiness.

## Identity and pre-auth hardening (2026-10-24, security Batch 4)

The API stores a Firebase email only when the ID token marks it verified;
unverified accounts keep `firebase-<uid>@postdee.local`. A verified address
still held by another PostDee row also falls back instead of failing with `500`.
The built-in Firebase verifier shares one certificate refresh, times out after
5 seconds and briefly reuses a failed refresh. Per-IP rate limiters sweep at
most once per window and cap remembered addresses at 10,000. No schema change,
migration or mobile change. See
[`2026-10-24-identity-preauth-security-batch4.md`](docs/superpowers/plans/2026-10-24-identity-preauth-security-batch4.md).

## Review post preview (2026-10-24, local candidate)

The final review step replaces clip/caption edit links with one `พรีวิว` action
under the thumbnail. Channel editing and wizard Back remain available. Preview
plays the selected local clip and shows an approximate post view only for chosen
destinations, using each effective caption, connected identity and YouTube title.
Chosen-cover capability and watermark notes remain explicit; platform layouts
can differ. The current follow-up gives TikTok portrait preview a bottom gradient,
real identity/caption and decorative heart/comment/save/share icons without
invented counts. Preview volume is 0–100%, with mute/restoration of the previous
audible level; it changes playback only, not system volume or the exported clip.
Opening preview does not upload, generate AI, render with FFmpeg, publish or
consume quota. Owner-bound post metadata is separated from existing plain local
playback and authenticated network playback.

On fresh main `6afe4d6`, the full Mobile rerun passes **2,867 tests / 6 skipped**,
with **150** Staging checks, **187** API regressions/typecheck, analyzer and **10**
real-font visual checks also passing. Verified Staging APK **12049** builds with
eight complete-source matches and the intended environment. It is installed
with the same package UID/storage. After manual sign-in, native playback, pause,
seek and volume changes (100% → 36% → mute → 36% → 62%) pass on an existing
45-second draft. Returning to review preserves its clip, empty caption, zero
selected destinations and the single draft. One initial pause showed a transient
player error; later explicit resume/pause and seek work without an error. Its
cause is unconfirmed. The current Home shows Free with only YouTube connected,
so this run does not verify TikTok/Instagram tabs or restoration of the earlier
Pro demo draft. TikTok-specific evidence remains the older 12048 native checks
and final visual tests. No draft save, AI, upload, post or purchase occurred in
this follow-up. This preview uses generic Facebook wording and establishes no
provider-delivery claim. It is not merged, pushed or cloud-deployed.
Earlier build/native results and resolved verification issues are in the
[preview work record](docs/superpowers/plans/2026-10-24-publish-post-preview.md).

## Immersive post preview (2026-10-24, local APK 12051)

The next local candidate follows the user's full-screen reference: post preview
removes the bottom seek/replay/time/volume panel and places white navigation,
caption and decorative social icons over the video. Tap the video to play or
pause; a top speaker button opens the playback-only volume controls on demand.
The video keeps its natural aspect ratio without cropping. Chosen destinations
retain their own real captions, identities and YouTube titles. With no chosen
destination, the shared caption and a generic social rail appear without an
invented account or counts. Compact inline information keeps publishing/cover/
watermark caveats available, pauses playback and is removed with the owner-bound
preview. The plain local/network clip viewer retains its existing controls.

The working baseline is now `8872f0e`, preserving nine incoming API-security/docs
commits. No incoming Mobile or schema change was introduced; all ten candidate
Mobile runtime/test hashes remain identical across that refresh.

Before the cosmetic follow-up, full Mobile validation on 12050 passes
**2,880 tests / 6 skipped**;
analysis reports no issues, and the joint preview suite passes **76** checks.
Fresh-baseline API static/build checks and **206 tests across 11 targeted files**
also pass; their scope is separate from the historical 187 API checks above.
Final **163** Staging checks and **15** exact-color visual checks also pass.
APK **12050** builds with eight complete-source and package/Firebase checks
matching. Installed 12050 retains the same UID/storage, signed-in Free account,
YouTube connection and existing draft. Native immersive play/pause, removal of
the bottom panel and inline volume 100% → 34% → mute → 34% pass. An initial
startup ANR recovered after one app-only restart; its cause is unconfirmed.
The draft has no destinations/caption, so this proves the generic view rather
than connected TikTok tab acceptance. Final **12051** improves Staging status-bar
contrast, passes **44** player/**165** Staging checks and analysis, and builds
with eight exact-source/package/Firebase matches. Its retained-data installation
and native play/pause/replay, volume, information panel and Back checks pass.
Cold launch reaches Home in approximately 45 seconds without an app restart;
the 12050 startup ANR remains a separate historical observation. The current
landscape clip is letterboxed without cropping, and the preview is left paused.
Connected TikTok tabs and native iOS remain unverified. The subsequent user
instruction authorizes `main/push` for this verified UI. The source-only handoff
preserves the tested runtime and requires no backend deployment.
The 12049 results above describe the previous UI and
retain their account/platform limitations. This follow-up needs
no API, database, dependency, configuration or backend deployment change and
does not change exported audio or perform publication. See the
[preview work record](docs/superpowers/plans/2026-10-24-publish-post-preview.md).

## Expired-plan reason on post detail (2026-10-24)

A scheduled post that the API stopped because the owner's Starter/Pro plan
ended before its time (platform reason `PAID_PLAN_REQUIRED`, see PR #29) now
shows a Thai reason on post detail instead of the raw code: "แพ็กเกจหมดอายุก่อนถึงเวลาโพสต์
จึงยังไม่ได้ส่งโพสต์นี้ ต่ออายุแพ็กเกจ Starter หรือ Pro แล้วสร้างโพสต์ใหม่". The
channel-review button is hidden for that reason. No API or schema change. See
[`2026-10-24-paid-plan-failure-message.md`](docs/superpowers/plans/2026-10-24-paid-plan-failure-message.md).

## Wheel time selection (2026-10-24)

Create Post and Calendar rescheduling share a 24-hour Flutter wheel picker.
Hours and minutes loop independently (`23 → 00 → 01`, `59 → 00 → 01`), without
changing the chosen date. Existing time is preselected; a new uploader schedule
keeps its 18:30 default. Cancel leaves the previous time intact. The selected
time uses the device's local timezone and the existing UTC request serialization.
Future-time checks, Starter's 14-day/Pro's 30-day rolling limits, quotas and
account safeguards remain unchanged. No API, schema or backend change is needed.
The full Mobile suite (2,819 passed / 6 skipped), analysis, 93 Staging-configured
checks and exact-source Staging APK 12046 pass. Real-font checks cover both
themes and narrow enlarged text. The user authorized main/push after verifying
the implementation. APK installation and native acceptance remain pending;
the installed app is unchanged. See the
[wheel-picker work record](docs/superpowers/plans/2026-10-24-wheel-time-picker.md).

## Per-owner resource caps (2026-10-24, security Batch 5)

The API now bounds what one account can keep in the shared database and
process:
- Templates: 200 per owner, with 120/5000-character title/body.
- Device tokens: 10 per owner, FCM-shaped, oldest evicted first.
- Managed upload sessions: 10 open per owner, 255-character file names,
  exact video/image types.
- New post captions: at most 63,206 characters.

Limited post lists and single-post reschedule/publish-now no longer read the
full history. No schema change, migration or mobile change. See
[`2026-10-24-resource-caps-security-batch5.md`](docs/superpowers/plans/2026-10-24-resource-caps-security-batch5.md).

## Compact caption AI panel (2026-10-23, Staging delivered)

The advanced caption panel uses the header `ให้ AI ช่วยเขียน`, a `สไตล์`
action and a uniform two-by-two channel grid beneath `เลือกช่องทางที่ต้องการ`.
The action shows `สร้างแคปชั่น · N เครดิต` for the selected channel count and
stays disabled until a channel is chosen.
Select-all/clear actions and a separate cost row are removed; writing style and
clip guidance remain available behind the style action. The four manual
editors, remembered draft targets and selected-only preview/apply/undo are
retained. The original fixed one-credit label and accounting are superseded by
the 2026-10-25 credit-per-channel contract above. The original presentation
release changed no backend runtime. Follow-up source `4a1c0f9` is on main and
Staging APK
**12045** is installed with the existing account and storage retained. Selected
channels now use only a green outline, with no checkmark covering their logos.
The follow-up passes analysis, 35 Staging-configured checks and light/dark
real-font rendering checks. Native checks confirm the new appearance and
zero/two-target behavior; complete four-target native interaction was stopped
when the screen changed independently. Earlier compact-panel full-suite and
style-cancel evidence remains recorded separately. No AI credit was spent or
post published. The original presentation used the then-current API without a
redeploy; the later pricing change requires coordinated delivery. See the
[compact-panel record](docs/superpowers/plans/2026-10-23-caption-ai-compact-panel.md).

## Mobile and CI hardening (2026-10-24, security Batch 6)

- **Android:** backup and device-to-device transfer of app data are off
  (`allowBackup="false"` plus data extraction rules), so a signed-in Firebase
  session does not move to another device. The unused `postdee://billing`
  deep link is removed.
- **iOS:** the CI IPA now passes the production `API_BASE_URL`. A release
  build with Firebase sign-in refuses any non-HTTPS API base URL before
  sending a request (`INSECURE_API_BASE_URL`).
- **AI captions:** frame extraction passes FFmpeg arguments as a list.
- **Workflows:**
  - read-only `contents: read` token;
  - checkouts without persisted credentials;
  - actions pinned by commit SHA;
  - a manual `apk_source_ref` must be a commit on a branch of this
    repository.

See [`2026-10-24-mobile-ci-security-batch6.md`](docs/superpowers/plans/2026-10-24-mobile-ci-security-batch6.md).

## Choose AI caption channels (2026-10-23, Staging Live)

Advanced mode keeps all four manual caption editors, but AI generation starts
with no channels selected. Choose 1–4 channels independently of the publishing
destinations, then explicitly request AI for that selection. The preview,
application and undo cover only those channels; other captions remain intact.
Local post drafts remember the selection through mode switches and reopening.
It is not a reusable channel/account preference or a field in post submissions.

The original release used one credit per set; that rule is superseded by the
2026-10-25 per-channel contract above. The selection release's deployed API
already accepted a selected `platforms` subset; that follow-up introduced no
backend runtime, schema, migration or configuration change. The user explicitly
requested a synchronized Staging deployment during release.
Checks pass: 2,787 Mobile tests, 2,504 API tests, Mobile analyze,
API static/schema checks and 28 Staging-configured widget smoke tests.
Feature `dab94fb` is on `main`/GitHub, Backend/Mobile CI passes, and its Staging
deployment is Live. Verified APK **12043** is installed with account/data
preserved. Emulator smoke confirms empty initial selection, one-channel mode
retention, and a two-channel draft restored after a cold restart. No AI request,
credit spend, purchase or post was made. iOS no-codesign CI also passes;
actual provider quality and publication remain unverified. See its
[scope and verification record](docs/superpowers/plans/2026-10-23-caption-target-selection.md).

## Four-platform captions (2026-10-23, Staging Live)

The post composer's optional advanced caption mode hides the shared input and
shows separate editable captions for TikTok, YouTube Shorts, Instagram Reels
and Facebook Page Reels. Users can write them manually or explicitly request
AI for all four, inspect the preview, then apply the set and edit it. An undo
action restores the text from before applying AI, including across mode toggles.
Switching back retains the original shared text and saved advanced text; shared
mode does not send the retained platform overrides. Local drafts retain the mode
and text. Saved channel defaults do not carry captions into the next post.

The API stores an optional `caption` inside each existing
`platformSettings.<platform>` JSON snapshot. Missing overrides use the shared
caption, keeping old clients compatible. Validation and publishing use the
effective caption for that destination; YouTube's automatic title follows its
own effective caption while an explicit custom title remains unchanged.
YouTube alone accepts an explicitly empty/whitespace override, normalized to an
empty description without falling back to shared text. TikTok, Instagram and
Facebook overrides must remain nonempty; YouTube's existing title/settings
requirements still apply.
`POST /captions/generate-from-clip` accepts optional selected `platforms` and
returns a matching `platformCaptions` map alongside its existing fields. One
provider operation produces the selected set, retaining the existing transient
retry policy. Under the 2026-10-25 contract, the set atomically reserves one
credit per channel. Incomplete/malformed AI output becomes a labeled local
fallback, with the entire batch refunded when release succeeds.

The feature is merged and pushed to `main`; Staging API `a391bc4` includes
the caption implementation and a bounded owner-transaction conflict fix found
during release smoke. APK **12042** was installed after the API, preserving app
data. Final CI passes **2,500 API tests** and **2,767 Mobile tests**; the unchanged
Mobile tree also passes the iOS no-codesign build. No database migration,
provider credential or new integration is introduced. Real AI output and real
publication have not been tested for this feature. See the
[implementation and verification record](docs/superpowers/plans/2026-10-23-platform-captions.md).

## Sentry error reporting (2026-10-23, candidate verified)

The candidate adds opt-in error reporting for Flutter and the Node API/current
in-process publisher, with the same reporting boundary in the optional standalone
worker. `SENTRY_DSN` is empty and disabled by default. Set
`SENTRY_ENVIRONMENT` explicitly to `development`, `staging` or `production`;
the Staging API still uses `staging` when `NODE_ENV=production`. An optional
`SENTRY_RELEASE` identifies the deployed build without customer information.

Outbound events retain allowlisted error types, safe source locations and
bounded operation/status labels. Mobile also retains bounded nonidentifying
manufacturer/model, OS name/version/build and Dart/Flutter runtime metadata;
device identifiers/names, user records and arbitrary context maps are excluded.
Customer captions, media URLs/keys, request
bodies, credentials, user/account identifiers and raw provider errors are not
sent. Tracing, performance monitoring, log export, Replay, screenshots, view
hierarchies and attachments are off. This is error reporting, not a complete
cross-service performance or native crash monitoring rollout.

Flutter's automatic native SDK/crash collection is disabled because native
envelopes bypass the Dart sanitizer. Dart/Flutter unhandled failures and safe
handled API 5xx reports use Sentry. Existing native Crashlytics collection stays
enabled whenever Firebase monitoring is available, including when Sentry is on.
Sentry owns only the Dart `FlutterError`/`PlatformDispatcher` error hooks; when
Sentry is absent/unavailable, Crashlytics retains those hooks too. Firebase
Analytics, Auth and FCM remain connected. Sentry-native crash/ANR and iOS
acceptance remain separate work; retained native Crashlytics is not a new native
crash acceptance result.

The pinned SDKs are `sentry_flutter: 9.30.1` and `@sentry/node: 11.8.0`; iOS
remains on its existing CocoaPods integration. No endpoint, schema, migration,
publishing or billing change is required. No real post or purchase is needed to
verify reporting. Full API checks and final-3 Mobile tests/analysis/build pass.
The exact APK12041 is installed on QA Pixel_8 with UID/data retained; Home opens,
native Crashlytics collection reads enabled, and a generic production-reporter
API 500 event reaches Sentry with the correct build/environment. A local API
synthetic error also reaches its own project. Both latest dashboard events have
no geography after enabling IP storage prevention and scrubbing `$user.**`.
No native crash was triggered. Live entitlement/publish/checkout acceptance
remains unverified. The user's 2026-10-23 `main/push/deploy` request authorizes
main integration, GitHub push and Staging API activation. Feature `b486ca3` is
on `main`/GitHub, followed by lockfile-only CI fix `35512aa`. The first Staging
build failed at `npm ci`; `35512aa` repaired that build, then cloud inspection
found an empty-stack processing warning. The two-file API sanitizer fix
`12e0589` is on `main`/GitHub; its unchanged API tree is now served by Staging
source `a0540a3` after the separately authorized main-process drill, with health/readiness
HTTP 200, 22 migrations/none pending and no monitoring-init failure. Full API
checks pass 2,422 tests; the earlier isolated `12e0589` module event matched its
own source/release/environment and had no processing warning. It was emitted through
an isolated Render Web Shell process, verifying deployed module/configuration/
network ingestion without forcing an Express-main-process HTTP failure.
Local API and exact Android acceptance are retained. Prior Backend/Mobile CI
and unsigned iOS compilation pass; exact-source CI `39893356044` also passes
Backend and Flutter Mobile. The API-only correction changes no Mobile code/APK.
The later controlled drill records an actual uncaught fatal in the API's own
process after graceful drain, Sentry's matching Fatal/Unhandled event, exit code
1 and Render recovery. The temporary hook is removed and the clean redeploy is
healthy. Observed 502s last about 33 seconds. This does not test a crash during
active publishing or a forced HTTP-500 middleware path; no real post/purchase
is submitted.
Acceptance scope and remaining device/native limits are recorded in the
[Sentry work record](docs/superpowers/plans/2026-10-22-sentry-monitoring.md).
Live deployment and remaining acceptance evidence are recorded in the work record.
Release preflight also updates the CI-only Staging-define validator to accept
and validate the three Sentry fields; its 21 Python tests pass, including the
checked-in example with billing disabled/enabled. That CI-only validator change
does not change runtime code; the later API sanitizer fix changes no Mobile
source or APK12041. iOS compilation uses Sentry disabled and does
not establish iOS monitoring runtime acceptance.

## Calendar history pages (2026-10-24, security follow-up)

Calendar no longer asks the API for the complete post history in one response.
The app reads `GET /posts?pageSize=100` pages, newest created first, following
`nextCursor`. Since 2026-10-25 it asks only for posts active since the start
of the oldest month or week the user has viewed (`activeSince`: created,
scheduled or published since then), so posts rescheduled far from their
creation date are included. The first load also covers the current week when
it starts in the previous month. It stops at the last page or after 20 pages.
Browsing to an earlier period, or switching week/month view, loads further
back. Plain `GET /posts` is
unchanged for installed apps, and a new app works with an older API, which
returns everything at once. No schema change or migration. Deploy the API
before shipping the app build, although either order works. See
[`2026-10-24-calendar-post-pagination.md`](docs/superpowers/plans/2026-10-24-calendar-post-pagination.md).

## Calendar selected covers (2026-10-21)

Calendar post cards add the saved selected cover as a small portrait thumbnail,
while retaining time, caption, actual channel status and existing navigation.
The full calendar history read is unchanged; only selected-day cover previews
use the existing owned single-post endpoint. Older posts without an image use
the saved selected frame, or the first frame when no choice was recorded, as a
small static image. A bounded proxy inside the device handles HTTPS video reads
for the existing thumbnail extractor. New posts retain
the chosen image for all four supported destinations; this does not add provider
thumbnail capabilities. Missing or unavailable covers use a placeholder.
The user authorized main integration and GitHub push on 2026-10-21. No API
deployment, migration or dependency is required on the current Staging API.
Verification and delivery are tracked separately in the
[work record](docs/superpowers/plans/2026-10-21-calendar-post-covers.md).

## Usability follow-up (2026-10-21)

The 100 synthetic-scenario review is followed by owner-scoped single-post reads,
live detail refresh, clearer result/recovery navigation, searchable post history,
visible composer validation, accessible onboarding and clearer account/quota
actions. New reads never publish a video or consume quota. Native checkout and
public posting are not used for verification. The selected smooth progress
animation and existing draft/consent/receipt safeguards remain in place.

Deploy the API before updating Mobile: `GET /posts/:id` is new and the optional
`monthlyQuotaResetsAt` describes the included allowance's next UTC month boundary.
Purchased credits still never expire, and add-on sales remain disabled. No schema
migration or dependency change. The
[work record](docs/superpowers/plans/2026-10-21-ux-review-fixes.md)
tracks tested source, release order and remaining limits. Deployment and native
installation are verified separately for each release.

## Publishing progress motion (2026-10-20, locally verified and Staging APK installed)

A local Home follow-up places its sending badge below the caption, the activity
rail above real channel results, and a subtle accent border, matching Calendar's
feedback order. Verification/delivery state is tracked in the
[Home work record](docs/superpowers/plans/2026-10-20-home-publishing-feedback.md).

The selected smooth progress screen adds a gentle orbit, a light confined to
the filled progress bar, destination labels and three stage indicators. Activity
never advances the reported percentage or implies publication. Background,
reduced-motion and TickerMode guards stop it. The 51 focused cases, full Mobile
suite (2,488 passed / three optional skips), final opt-in render and analysis pass.
Staging x86_64 APK12028 is built and installed with the original app data and
signed-in Home preserved. Motion uses controlled production-widget fixtures;
no real post was submitted. No API/configuration changes or migration.
Source is integrated into `main` on 2026-10-20 under the user's main/push
request. The delivery changes no backend runtime and requires no API deployment.
See the [work record](docs/superpowers/plans/2026-10-20-publish-progress-smooth-motion.md).

## Remembered channel settings (2026-10-20, YouTube native restart verified)

Mobile remembers reusable choices on this device per signed-in owner and
connected channel: TikTok delivery mode, YouTube visibility/audience, Instagram
feed sharing and Facebook Page Reels delivery mode. New clips still require
content declarations and current confirmation; TikTok privacy/interactions
remain manual. Saved drafts keep their own values. No API change or migration.
Within an open TikTok settings sheet, changing viewers, interactions or the AI
answer preserves explicit music/policy confirmation. Changing commercial/brand
disclosure still clears confirmation; opening a new sheet or changing the
account/clip/content still requires fresh confirmation. This follow-up is
integrated into `main` on 2026-10-20 for the authorized main/push delivery;
APK12029 remains built but not installed. Details are recorded in
[the consent work record](docs/superpowers/plans/2026-10-20-platform-settings-consent.md).
Local verification passes: 2,480 tests, two optional skips, clean analysis and
Staging APK12027 built and installed. After login, a native force-stop/restart
check confirms YouTube visibility/audience return in a fresh post while its AI
answer and community confirmation stay unanswered; Cancel preserves the saved
audience. Home still shows the existing draft entry and unchanged quota.
Instagram/Facebook remain covered by automated fixtures. This feature is now
integrated into `main` together with smooth progress, retaining the tested
runtime used by APK12028. See the
[work record](docs/superpowers/plans/2026-10-18-remember-platform-defaults.md).

## Publishing activity (2026-10-18, Android Staging delivered)

The selected variant 3 adds a shared sending badge, indeterminate rail and real
per-channel delivery row to Home, Calendar and post detail. Each post uses one
guarded motion clock; the activity indicator does not estimate a percentage or
turn a partial result into confirmed completion.

Home silently refreshes its existing recent-post read every 30 seconds only
while a loaded post is `PUBLISHING`, with the app resumed, Home active, its route
current and the same signed-in owner. Calendar retains its existing visible
`QUEUED`/`PUBLISHING` polling. Detail was a navigation snapshot in this release;
the 2026-10-21 usability follow-up adds a single-post read and refresh. No API,
schema, dependency, flag,
entitlement or migration changes are required. Targeted tests pass 145/145; the
full Flutter suite passes 2,437 with two optional previews skipped, and analysis
reports no issues. Release CI repeats those checks and builds Staging APK 12026
with the existing Test Store configuration. Local signing and the guarded update
preserve the account, drafts, Pro quota and adopted volume; Home, Calendar,
existing detail and Account smoke checks pass. Staging API is Live with the same
API runtime as the release candidate. Native active-sending/FPS and a new provider
publication remain unverified because no real sending post was created. See the
[plan and verification record](docs/superpowers/plans/2026-10-18-publishing-motion.md).

## YouTube title from shared caption (2026-10-18, local implementation)

Write the shared caption once. The YouTube sheet shows a live title preview
from the first sentence of its first nonempty line, removing `<`/`>` and
limiting the title to 100 Unicode code points. `ปรับชื่อเฉพาะ YouTube` reveals
an optional custom title; caption edits preserve it and `ใช้ชื่อจากแคปชัน`
resets it to automatic. The full caption remains the description and keeps its
existing validation; title cleanup does not alter the description.
With the 2026-10-23 advanced-caption candidate, these automatic rules use the
YouTube-specific effective caption; shared mode retains the behavior above.

The local empty `youtubeTitle` means automatic. Before review/submission Mobile
resolves it into the existing `platformSettings.YOUTUBE_SHORTS.title`; there is
no top-level API field or new database column. A blank caption is allowed only
for a YouTube-only post with a valid explicit nested title and all existing
visibility, audience, synthetic-media and certification settings. Create,
accepted replay and read-only recovery use the same exception. Other selected
destinations still require a caption. Existing explicit draft titles remain.

Local automated verification passes; [results and delivery limits](docs/superpowers/plans/2026-10-18-unified-platform-settings.md#youtube-title-follow-up-2026-10-18-local-implementation)
are recorded separately. Staging Android **12025** builds, installs on the existing
volume and opens Home with retained drafts/posts. No new migration is needed.
Entitlement loading, the exact updated API deployment, provider publication and
Production remain unverified; blank descriptions require the updated API.

## Unified channel settings (2026-10-18, Staging delivered)

TikTok, YouTube, Instagram and Facebook Page Reels share a content-sized settings
sheet with account identity, grouped controls, visible validation and fixed
Cancel/Save actions above the keyboard. TikTok Inbox no longer requests Direct
creator options; each Direct opening fetches fresh account-bound options and
discards stale responses when switching mode. Required consent stays manual.
Instagram/Facebook add optional AI-generated media disclosure, retained in drafts,
review, immutable post intent and provider requests. Omitted legacy values remain
omitted, distinct from an explicit false. This is media disclosure, not AI caption
generation. Existing feed, cover, privacy, quota and recovery behavior remains.

Source `866f0e3`, based on verified main `c813eef`, is merged/pushed to main and
Live on Staging deploy `dep-dba2oieq1p3s73a3g6qg`. Exact-source Backend/Flutter
CI `39089186176` and unsigned iOS build `39089186129` pass. Health and readiness
return HTTP 200. Staging runs publishing in the API's memory queue, with no
separate worker. Android **12024** is now installed on the same emulator after a
verified full backup, adding a separate **16 GiB private volume** and recovering
the existing app data. A guarded same-volume reinstall and cold boot retain
version 12024 and the original UID. After cold boot, the signed-in Home, both
existing drafts and actual local video playback pass native checks. TikTok
Inbox was checked read-only with Cancel; this storage follow-up
does not claim native checks of every new platform dialog or real publication.
One existing draft still shows a connection warning despite both selected
channels being connected; the work record separates this remaining UI issue
from the completed storage/data recovery.
The Android desktop launcher now preserves the installed storage volume rather
than allowing an update to select a fresh data location. This separate
installer/tool follow-up has local validation; the CI IDs above cover source
`866f0e3`. The tool/document delivery does not require another API deployment.
No schema/migration, dependency, environment or plan change is required.
API **2,207 tests**, Mobile **2,371 tests** (two optional previews skipped),
analysis and the exact Staging APK build pass; the new preview runs separately.
Connected-account publication and iOS device delivery remain unverified.
See [implementation and checks](docs/superpowers/plans/2026-10-18-unified-platform-settings.md).
Earlier sections record their respective deliveries.

## Private admin console and trials (2026-10-18, Staging enabled)

The API can serve a Thai `/admin` console for overview, members, posts, trials,
connections, usage reports/CSV and administrator history. Owner and read-only
viewer roles use explicit server-side Firebase UID allowlists and revocation-checked
Firebase Admin authentication. Both admin and trial feature flags default to off.
No administrator or customer access is granted by the source configuration.

Time-limited Starter/Pro grants are stored separately from purchased subscriptions.
API and publishing workers use the higher valid plan; expiry/revocation preserves
paid access and existing usage. RevenueCat remains responsible for paid purchases.
The additive trial migration and existing platform-enum history reconciliation
must precede enabling trial access on API **and workers**.
Update Mobile purchase confirmation before granting customer trials; it reads the
separate purchased plan rather than treating trial access as proof of a purchase.
Source `50fba5e` is Live on Staging in `dep-dba5im61egvs739eoteg`; health/readiness,
admin assets and public configuration return HTTP 200. Both additive migrations
were applied earlier. The read-only Firebase Admin credential is installed and
both admin/trial flags are enabled. Owner identity, Firebase Web app and the
Staging sign-in domain are verified/configured. After manual Google sign-in,
the live owner session passed read-only inspection of all seven views, member
search/detail, post filters and trial-form validation/review/cancel. Mobile menu,
overview and drawer layout were checked at 390px. Real trial writes, nonempty
CSV export and live ordinary-user denial remain separate acceptance checks.
No customer trials were granted.
The admin UX follow-up translates overview/channel results, distinguishes
TikTok Inbox drafts from publication, opens neutral member details before trial
actions, and explains empty Trials/Reports/Audit pages and disabled CSV. API
status/filter values and trial safeguards are unchanged. CI run `39100690775`
passed API and Flutter checks. Post-deploy JS/CSS match the release commit;
the existing owner session verified Thai overview, two TikTok draft results and
five legacy unknown-outcome results. Fresh owner sign-in/member UI verification
after this deploy remains separate; the new UI was exercised with local fixtures.
Configuration, the local fixture preview and
report limitations are in [the admin guide](docs/ADMIN_CONSOLE.md); implementation
and verification evidence are in [the plan](docs/superpowers/plans/2026-10-18-admin-console-and-trial-access.md).

The admin usage update adds all-account/date-range usage reports, whole-cohort
summaries, separate quota and recorded delivery outcomes, consistent read snapshots
and safe visible-page refresh. Registered accounts do not mean online users;
reserved usage does not mean successful AI work or public posts. This update needs
an API/admin-asset release only, with no Mobile update, migration or flag change.
Source `fc457b2` is merged/pushed to main and Live on Staging deploy
`dep-dba64iqjnfac73egt8i0` at 13:10:11 Bangkok on 18 October 2026. Exact-source
API/Flutter CI `39102818467` passes. Health/readiness and source-matching assets
pass; fresh Google owner login and all-account reports return three accounts
with matching row/summary totals. No trial or customer data was changed.
Its verification and remaining delivery limits are tracked in the
[usage accuracy plan](docs/superpowers/plans/2026-10-18-admin-usage-accuracy.md).

## Channel publishing preflight (2026-10-15, Staging delivered)

The uploader checks YouTube/Instagram/Facebook captions before upload and
checks the actual rendered file before sending it. A read-only, owner-scoped
channel-readiness endpoint exposes explicit reconnect/permission problems without
creating profiles, synchronizing accounts or publishing. Missing provider
capability evidence is shown as unverified, never as a promise of successful
publication. YouTube offers a title suggestion only for an empty title; audience,
AI disclosure and certification still require the user's answers.
All connected platforms now expose the same opaque account revision in ordinary
connection lists. A separate read-only submission-recovery lookup can return an
already accepted original request before new media/readiness/caption guards,
without creating a post or enqueueing it again.

Source `2e86634` is merged into main, pushed and Live on Staging deploy
`dep-db8focbrjlhs73bs5s90`. Exact-source Backend/Flutter CI `38766556966` and
unsigned iOS build `38766556987` pass. API was deployed before installing Android
Staging **12023** on the user's emulator, preserving login and both local drafts.
Authenticated connection/readiness GETs and the refreshed Home screen pass;
TikTok/YouTube are connected with unconfirmed publishing capabilities, while
Instagram/Facebook are not connected. No real upload/publication or iOS device
test is claimed. There is no schema, dependency or environment change.
Earlier release sections below are historical delivery records.
See [scope, checks and remaining validation](docs/superpowers/plans/2026-10-15-platform-publish-preflight.md).

## TikTok Direct Post (2026-10-15, Staging delivered)

The new explicit Direct Post path reads the connected creator's latest options
through PostPeer before showing settings, before accepting a post, and again
before the worker sends it. Privacy has no default, interactions require opt-in,
and music/commercial-content consent is collected in the publishing flow. A
creator revision binds those choices to the same owner and account. Inbox remains
available and existing Inbox receipts retain their DRAFT outcome.

Source `5681602` is on main and Live on Staging deploy
`dep-db8ep7brjlhs73e46qc0`; exact-head Backend/Flutter CI `38757735457` passes.
Android Staging **12022** is installed without clearing user data. The logged-in
app fetched current creator options and showed public/friends/self choices with
no privacy default. Duet remained disabled by the creator restriction; Save
remained disabled pending valid choices and consent.
This read-only check made no upload or publication; provider TikTok audit/public
approval and real Direct delivery remain unverified. iOS CI `38757735448` passes
its unsigned build and IPA artifact checks; no iOS device test is claimed.
No historical-data repair or Production change is included. Other
environments must deploy API before Mobile; no new database migration is needed.
See [the implementation and validation record](docs/superpowers/plans/2026-10-15-tiktok-direct-post.md).

## TikTok Inbox CREATE confirmation (2026-10-15, Staging delivered)

A later TikTok-only post was FAILED locally although its canonical PostPeer GET
confirms a completed Inbox handoff. The documented CREATE response example omits
the selected-platform status and Inbox ID required by the mapper. An injected
example reproduces rejection before GET; the real historical CREATE payload was
not captured, so this is a reproduced contract gap and an inferred incident
explanation. The correction uses the genuine CREATE post ID for a bounded
read-only GET when the successful selected summary lacks status and ID, retaining
strict Inbox proof without another POST. Regression-first tests reproduce 21
failures; all 102 publisher and 1,981 full API tests pass, together with
typecheck/build, Prisma checks and two compiled confirmation/unknown smokes.
Independent review finds no blocker. Source `e191ed7` is on main and Live on
Staging deploy `dep-db8dr449v7es738gr9vg`; exact-head CI `38747979249` passes
Backend and Mobile (2,252 tests/analysis). Health/readiness pass twice; all 18
migrations and the empty-backlog guard pass. The separately guarded two-row
repair and independent readback complete; APK12021 Calendar/detail show
`ส่งเป็นร่างแล้ว` at 14:13 UTC. All five unresolved operation markers remain
untouched, with no resend or new APK. User-side Inbox/public posting remains
unverified. The completed 12:43 repair stays separate. Receipt:
`docs/superpowers/plans/2026-10-15-tiktok-inbox-create-confirmation.md`.

## TikTok Inbox delivery status (2026-10-15, Staging delivered)

A completed PostPeer TikTok Inbox job can return `published` with an Inbox
receipt rather than literal `draft`. The correction recognizes that strict
receipt only for the requested INBOX_DRAFT delivery and retains DRAFT semantics,
without claiming public publication or retrying the provider request. Historical
FAILED rows require a separately verified repair; deploying the mapper alone
does not rewrite them. No mode, schema, quota or native preparation changes are
needed. All 1,947 API tests, typecheck/build, Prisma checks and the compiled
worker smoke pass. Source `7a55fe8` is merged and pushed to main; exact-head CI
`38741265826` passes Backend API (119 files / 1,947 tests) and Mobile (2,252 tests
and clean analysis). Staging deploy `dep-db8d6gss728c7391ajp0` is Live at
13:23:04 UTC with health/readiness HTTP200, 18 migrations/no pending and the
empty-backlog guard retained. A separately guarded one-time repair corrects the
matched historical post to DRAFT delivery; Calendar and post detail now show
`ส่งเป็นร่างแล้ว` without the error. All five unresolved operation markers remain
untouched. No provider resend, environment/configuration, Production or installed
APK12021 change is included. The user must still finish the TikTok Inbox flow;
public publication is unverified. Evidence and verification:
`docs/superpowers/plans/2026-10-15-tiktok-inbox-delivery-status.md`.

## TikTok native completion with background engines (2026-10-15, local app updated)

The real Staging app exposed a lost FFprobe completion event when Firebase's
background FlutterEngine became the FFmpeg plugin's global callback owner.
TikTok preparation now awaits each pre-created session's native MethodChannel
result, retaining its own cancellation ID and existing media checks. The upload
copy also normalizes dimensions to TikTok's 360–4096-pixel range; the local v2
receipt policy prevents reusing older unvalidated sizes. Source media is retained.
Firebase messaging, API contracts, package rules, and Calendar stay unchanged.
All 2,252 Mobile tests and analysis pass; the exact helper also passes six native
two-engine cases, a cold start, and scoped cancellation. Staging APK 12021 is
installed on the user emulator with its account and original draft retained.
The draft opens at review with TikTok selected. Public TikTok publication is
unverified. At the earlier account check, Home/Profile showed Free with 0/3
remaining and an unverified phone; existing free-plan rules require phone
verification. The native source
is included in the main/CI/Staging delivery above; APK12021 remains installed.
Push CI skips APK building/uploading and does not replace its native receipt.
Full receipt:
`docs/superpowers/plans/2026-10-15-tiktok-native-session-completion.md`.

## TikTok media and Calendar activity (2026-10-15, Staging delivered)

Calendar now reads all owner-scoped posts through the existing `GET /posts`, so
immediate and partially published activity appears alongside scheduled posts.
Real schedules remain optional, and queue actions require a queued scheduled
post. TikTok-selected uploads prepare and validate H.264/AAC constant-30-FPS
media on-device, including a bounded decoded-frame check before upload;
historical upload receipts without the preparation
policy require explicit recovery rather than an automatic repost. Known TikTok
frame-rate rejections have fixed Thai guidance; unknown provider details remain
private. No schema or package-rule change is required. Source `0f2941b` is merged
and pushed to main; exact-head CI `38725833299` passes Backend and Mobile (1,914
API / 2,226 Flutter tests). Staging deploy `dep-db8bdj2vcj2c738t2ke0` is Live with
health/readiness HTTP200 and the empty-backlog guard retained. Exact APK12020
is installed on the existing emulator with its account retained; the Oct14
immediate partial post now appears in Calendar, including the Shorts filter. Verification,
APK delivery, and limits:
`docs/superpowers/plans/2026-10-14-tiktok-media-and-calendar-activity.md`.

## Main integration (2026-10-13, completed)

The user-authorized latest `codex/audit-system-fixes` branch is fast-forwarded
into main and pushed at `be7732f6a14f9f91e6eda4a39179b30c385427ab`, after exact-head
CI `38386971185` passed Backend and Mobile (2,058 tests, analysis8.9 s). All 29
verified commits are included; no old dirty worktree content was copied. Runtime
is identical to Staging Live `7b0c51d` and installed8016; no new build/migration
or Production deployment. Staging stays Live with auto-deploy disabled;
Production API/database remain user-suspended, with no new deploy observed.
Earlier Oct12 “no main merge” statements describe that historical delivery.
Details: `docs/superpowers/plans/2026-10-13-main-motion-audit-integration.md`.

## Mobile motion smoothness audit (2026-10-12, Staging delivered)

Audit every main tab and the composer, video preview, publish results and account
overlays. Fix interrupted press/selection/entrance feedback, hidden Home actions,
background thumbnail decoding and replayed shop-preview entrances while retaining
existing data and business flows. Final source passes 2,058 Flutter tests and
analysis (No issues, 8.6 s). Exact Staging x64 4016/8016 is built/installed with
retained account/shop data; native navigation, preview background/resume and
composer return pass without data changes. Debug emulator frame samples are
diagnostic only; physical-device 60/120 FPS remains unverified and the two sample
windows do not prove a speedup. No API/schema/config/dependency change or new
migration. Combined source `7b0c51d71090e5c080182daa8630d5b90e6d3d49` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38249605630` passed Backend
and Mobile (2,058 tests, analysis14.2 s; CI APK build/upload skipped). Render
`dep-db6d96vavr4c73b21o2g` is Live at 19:39:44 GMT+7 with 16 existing migrations,
none pending; health/readiness return HTTP200. Installed8016 and disabled
publishing/memory queue stay unchanged. Post-Live Home→Shop→Account→Home
preserves account/shop data. No main merge; the following receipt is docs only.
Preserve the initial 8015 receipt below. Details:
`docs/superpowers/plans/2026-10-12-mobile-motion-smoothness-audit.md`.

## Bottom navigation motion (2026-10-12, Staging delivered)

The approved mobile-only follow-up adds a soft selected-icon halo, finite icon
lift/scale/color transitions and native press feedback to the four ordinary dock
tabs. Keep the existing running dot, center Create post action, tap targets,
semantics and navigation/state/owner guards. Reduced motion, lifecycle and parent
`TickerMode` settle feedback without replay. No new API request, persistence,
business callback, schema/config/dependency or migration. The initial dock-only
source passed 1,979 Flutter tests and analysis, including 13 new navigation cases.
Exact Staging x64 APK 4015/8015 was installed at that verification with the account/shop data retained. Native four-tab
halo/icon/dot and one composer open/close/previous-tab return checks pass without
changing data; motion/accessibility guards use controlled fixtures. Combined dock/
audit source `7b0c51d` passes CI `38249605630` and is Live through
`dep-db6d96vavr4c73b21o2g`; current installed8016 and its 2,058-test receipt are
separate from initial8015. Post-Live account/shop data are retained. Plan:
`docs/superpowers/plans/2026-10-12-bottom-nav-ui-motion.md`.

## Account UI motion (2026-10-12, Staging delivered)

The approved Account-only follow-up adds brief press feedback and a finite
220 ms/six-pixel entrance to the existing content and setting sheets. Preserve
native controls, owner/request guards, email/phone verification, billing,
settings, deletion confirmation and sign out. Stop effects for reduced motion,
lifecycle, `TickerMode` and inactive tabs without adding persistence or provider
requests. Final source passes 1,966 Flutter tests and analysis, including 29 new
Account cases. Exact Staging x64 APK 4014/8014 is built and installed with the
retained account. Native edit/connections/paywall browse, setting-sheet close,
help and tab-return checks pass without changing data; the existing scroll
position and account values remain. Mutation/business actions use controlled
fixtures. No API/schema/config/dependency/migration change. Combined source
`904a3f89c3601a1fac28eedfaf8781434b19bd49` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38205149761` passed both jobs
with 1,966 Mobile tests. Render `dep-db66eh8473hc73dabfcg` is Live at 11:53:11
GMT+7; 16 existing migrations have none pending and health/readiness return HTTP
200. Disabled publishing/memory queue and installed 8014 are unchanged.
Post-Live Home → Shop → Account navigation retains account/shop data; no main merge. Plan:
`docs/superpowers/plans/2026-10-12-account-ui-motion.md`.

## Shop-link UI motion (2026-10-12, Staging delivered)

The approved mobile follow-up adds brief press feedback, current-only section
entrances and drag-proxy feedback to the existing shop-link manager and theme
controls. Preserve owner-scoped serialized local draft autosave, explicit
publish/update/unpublish, confirmed-URL sharing and all 100 templates. Public
page motion and API/schema/configuration/dependencies remain unchanged; no new
migration is required. The earlier Shop-only source passed 1,937 Flutter tests and analysis,
including 22 new motion cases. At that Shop release, exact Staging x64 APK 4013/8013 was installed with
the account and original shop data preserved. Native manager/info/Add cancel/
theme browse and preview cancel/review/navigation checks pass; Save, theme Apply,
edit/reorder and publication outcomes use controlled fixtures. Combined Shop/
Account source `904a3f8` passes CI `38205149761` and is Live through Render
`dep-db66eh8473hc73dabfcg`; installed 8014 is retained. Post-Live Shop remains
published/saved clean with its two original links and confirmed URL. Plan:
`docs/superpowers/plans/2026-10-12-shop-link-ui-motion.md`.

## Guided create-post revision (2026-10-12, Staging delivered)

The approved “ทีละขั้น” direction keeps the existing four-step composer and
explicit draft saving. It makes the AI action visible while collapsing optional
writing controls, shows verified destination account names and clip metadata,
and keeps a concise step/channel-count summary beside the confirmation action.
Date/time remains in the shared review and schedule panel.
Connection refreshes reject stale owner/request results and withhold account
names while the latest lookup is loading, failed or belongs to another owner.
Home press feedback and current-only step entrance effects must respect reduced
motion, `TickerMode` and background state. Publishing, caption-style learning,
cover editing and all account/package/scheduling gates remain unchanged; no API,
schema, dependency or environment change or migration is required. The latest
local feedback follow-up adds focused inline caption validation, a waiting
indicator tied to the existing AI request/full returned caption and a temporary
check only after a verified explicit local-draft Save. The final rapid-save guard
rejects duplicate busy callbacks before clearing success-feedback generation.
Final feedback has 10 new tests; guard/save tests pass 86/86, the full Flutter
suite passes 1,915/1,915 and analysis passes. At that composer release, APK
4012/8012 was installed with the retained account. Native blank-caption Next
showed inline error/focus/keyboard; the app was left on clean empty step two.
Prior 187/187, 1,914/1,914 and native validation on 8011 are pre-guard receipts;
AI/save success uses widget fixtures.
The preceding connector source passed 1,905 Flutter tests and analysis. It adds
three thin lines between the four progress circles and outlines pending steps.
At that release Staging APK 4010/8010 was installed with the same signature and
retained session; native checks showed lines/outlines and the active circle moving from
clip to caption without inventing completion. The base 8009 four-step/AI/
zero-destination checks are separate history; positive identities, metadata,
schedules, AI and narrow/large-text cases use widget fixtures. Authorized source
`430f82ad1c493b5a8bcf1f51b007e2a7604dae1e` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38200231563` passed Backend
and Mobile. No remote APK build was requested; local 8012 was unchanged in that delivery.
Render specific-commit deploy `dep-db65d08473hc73d6fp50` is Live at 10:41:35
GMT+7 on the existing Staging service. Its 16 existing migrations have none
pending; `/health` and `/ready` return HTTP 200. Social publishing stays disabled
and the queue remains memory; no new migration or main merge was required.
Scope, source/build hashes and separate native/fixture receipts belong in
`docs/superpowers/plans/2026-10-12-create-post-guided-ux.md`.

## System audit fixes (2026-10-09)

The audit-fix branch starts from verified `main` `c4e5220`. It preserves the
four-step composer, all 100 profile templates, package limits and disabled
Staging social publishing. It adds safe media-aware publish replay with saved
upload receipts, owner-bound notifications, nonblocking session restore, a full
post list, fresh entitlement state, local shop-draft autosave and durable image
protection. Store prices come from the device store; a timed-out purchase keeps
its existing operation for rechecking instead of starting a second purchase.
Failed AI-provider requests identify their fallback and release only their own
quota reservation. Local/mock template generation retains scaffold quota rules.

API commit `9f0b72904d610c7161c8fca863e7d21f0ff1a1f6` is Live on Staging at
14:16 GMT+7 on 2026-10-09, deploy `dep-db498ejl550s73b0qu20`; all 16 migrations
are applied with none pending. Exact-source CI `37897827978` passed API and Mobile.
The exact split x64 APK is installed locally with the account preserved. An
injected Android VIEW URI returned to the same Connections screen with its 1/4
state retained; real provider/browser handoff, Open App confirmation and cold
callback remain unverified. Direct Staging web checks remain blocked by browser
access settings. Test private posting, actual payment/OTP and
two-account native notification delivery separately with authorization.
Details and verification:
`docs/superpowers/plans/2026-10-09-system-audit-fixes.md`.

## Calendar compact revision (2026-10-12, Staging delivered)

The compact-list Calendar has week/month views, Today, real per-day
post counts, all/four-platform filters and readable time/status rows. Its create
action passes the selected local date to the existing full-screen composer;
choosing a date does not publish, save or bypass scheduling entitlement/time
validation. The initial view is week; the existing first upcoming-day selection
is retained when today has no post in the current month. Refresh retains confirmed content and selection while showing
read errors/retry. Existing queue actions, real publish timestamps, partial/
unknown outcomes and visible-only polling remain. This mobile-only revision adds
no API/schema/provider/configuration change. The composer date labels now use
its injected local clock consistently; the default remains `DateTime.now`.
Authorized feature SHA `3368f4d` is pushed; exact-source CI `38187776818` passes
1,883 Flutter tests, analysis and Backend checks. Staging APK 4007/8007 installs
with the same signature and retained data/session; the post-deploy native cold
launch opens Home. Full native Calendar/date-handoff/Free-guard checks passed on the
preceding 8006 revision, without saving. The real account has no posts;
positive queue/partial/mutation cases use fixtures. Render deploy
`dep-db62jdvlot8c738l37q0` is Live at 07:30:34 GMT+7 on 2026-10-12 with this
exact source; all 16 existing migrations are applied with none pending, and
`/health` plus `/ready` return HTTP 200. Staging social publishing remains disabled.
The preceding Home release is a separate receipt. Plan:
`docs/superpowers/plans/2026-10-11-calendar-ux.md`.

### Calendar motion follow-up (2026-10-12, Staging delivered)

Calendar now reuses Home's brief press feedback and initial-loading skeletons.
Day/view/platform selection transitions over 160 ms; week/month height adjusts
over 220 ms. Only the current owner/day/filter content is mounted during its
180 ms fade and eight-pixel entrance, so outgoing post actions do not linger.
Silent refresh keeps confirmed data visible. Reduced motion, inactive tabs and
background state stop the effects. Existing owner guards, date handoff,
scheduling limits and API behavior are preserved; no migration, environment
setting or dependency is added. Authorized source `df8df1d` is pushed;
exact-source CI `38189859822` passes 1,891 Flutter tests, analysis and Backend
checks. Render deploy `dep-db6327ajnfac73c7vr90` is Live at 08:02:20 GMT+7;
16 existing migrations have none pending and health/readiness return HTTP 200.
At that Calendar release, the locally verified Staging APK 4008/8008 was
installed with its account. Post-Live native refresh preserved the selected
date/filter and account state; the later guided revision updates the local APK.
Verification and delivery are recorded separately from the preceding release in
`docs/superpowers/plans/2026-10-11-calendar-ux.md`.

## Home next-action revision (2026-10-11, Staging delivered)

Home prioritizes continuing the latest saved draft or creating a post, followed
by a compact connection summary, the next future queued post, recent posts and
the store-link publication state. The package row stays compact and retains
the existing authoritative subscription refresh and failure states. Drafts
are account-scoped and device-local; an unsaved composer is not a saved draft.
Connection counts cover the four currently supported destinations and do not
promise valid tokens or publishing readiness. Failed reads remain unknown,
with a retry action, rather than fabricated empty or disconnected states.
The store-link row reports publication only from the server-confirmed profile
and public URL. This mobile revision uses existing API reads, keeps the
full-screen composer and five-item navigation, and adds no analytics request,
provider, package rule, configuration flag or database migration.
Implementation, concept fidelity and verification:
`docs/superpowers/plans/2026-10-11-home-ux.md`. The base Home checks pass: 1,825 Flutter
tests, clean analysis, 1,781 API tests across 109 files, API build and Prisma
validation/helper type-check. The exact-source Staging x86_64 APK (build 4003,
installed version code 8003) is installed without clearing account data. Native
Home reads the current Free 0/3 quota and three existing local drafts; create,
resume, Connections, Calendar and the published shop shortcut open correctly.
Checks closed forms without saving and performed no purchase, OAuth connection
or social post. Future-queue/partial-outcome cases use tests and sample widgets,
not customer writes. These results and version 8003 cover the base revision,
before the subsequently approved motion follow-up.

The selected interactive-preview variant is “พร้อมภาพปก”: a full-width real
saved-draft cover, or a muted paused first frame of its local clip when no cover
is usable. The preview is a compact 120 logical-pixel crop matching the selected
prototype, with `BoxFit.cover`, rather than a full video player. Initialization
has a five-second limit and falls back to a static
icon; the decoder is disposed when hidden, backgrounded or replaced. This
preview never plays the clip, writes a thumbnail, uses FFmpeg or uploads media.
The card also has a next-required-step hint derived from existing draft fields,
brief press feedback and accessible loading skeletons
and pull-to-refresh across the existing Home sections. Drafts do not persist
an exact current wizard step. Refresh awaits/coalesces all six existing data
sources, retains current content including previously confirmed empty results,
and never announces that everything updated when a read failed. Narrow layouts,
large Thai text and reduced-motion preferences are verified by the final
1,863-test Flutter suite (2m54s, concurrency 2). Intermediate native
version 8004 confirms the real Free 0/3 state, initial loading, retained
content during pull refresh, press feedback and existing composer/Connections/
Calendar/shop navigation without saving. Final source adds the 120-pixel cover
correction and accessible notification-button action. The frozen-source APK is
built and installed at version 8005; clean analysis and final native bell/pull/
create-and-close checks pass with the existing account preserved. The emulator has no draft for
this follow-up, so positive draft/cover acceptance uses fixtures instead of
creating customer data. These are pre-delivery local verification receipts.
Feature source `ce89a0e464517f87f5902dd8ab32c764f2e67a72` is pushed to
`origin/codex/audit-system-fixes`. Exact-source CI `38125004499` passes API and
Mobile; Render deploy `dep-db5kk4h42hec739a7gg0` is Live at the same source.
Post-deploy health/readiness return 200, and native version 8005 refreshes
successfully with the same Free 0/3 and connections 0/4. CI intentionally skips
APK build/upload; the verified local Staging debug/Test Store APK stays
installed. Main and Production remain unchanged; detailed receipts are in the plan.
## Security integration delivery (2026-10-13)

Branch `codex/security-main-delivery` initially started from verified main
`c4e5220`; delivery now reconciles the newer verified remote main
`f5dea16f59bfb317c92971c6bbef60d8b742ea5d`. It selectively ports the earlier
security work while retaining current Store link publication/customization,
the four-step composer, scheduling/idempotency and pending billing confirmation.
The old audited worktree remains untouched; its unrun cases and dated CI/smoke
results are not verification of this branch.

Purchase readiness is an additive protocol-1 POST before a new RevenueCat buy.
Legacy GET user preparation remains during this stage, subject to the final
owner write fence; read-only GET cutover is deferred until incompatible mobile
builds are retired. Session-bound auth/native operations, push recipient UID
and final User/Post/Subscription transactions are integrated in this branch.
Source review, API 1,816 tests/build/schema and Flutter 2,171 tests/analyze pass.
Runtime source `9244f16` is pushed to main and deployed Live to Staging. Exact
Staging debug APK8017 is installed over the existing Emulator app with the same
signature; published shop data and signed-in state are retained. Basic device
smoke passes. Production remains outside this delivery stage. See
[`2026-10-13-security-main-delivery.md`](docs/superpowers/plans/2026-10-13-security-main-delivery.md).

## Shared owner operation drain (2026-10-14, delivered to Staging)

The follow-up started from typing commit `1b5a403` on
`codex/staging-regression-and-test-types`, based on verified main `f07ee30`.
Source `7576ee3` is now pushed on main and Live on Staging through
`dep-db7gsd3bc2fs73f64600` at 12:09:57 Asia/Bangkok. PostgreSQL records admitted
owner-operation lifetimes and an exclusive account-cleanup claim. Deletion seals
the owner, waits for admitted
work in upgraded processes, and re-reads provider cleanup scope before cleanup.
HTTP handler/finally work, managed uploads, queue admission and worker execution
participate. Unknown outcomes, process crashes and unconfirmed releases keep
private blockers; no timer expires them. Actual local PostgreSQL 18.1 with all
18 migrations and two independent Node processes passes 10/10 checks using a
loopback synthetic provider. The full API suite passes 1,909/1,909 in 119 files;
typecheck, production build, Prisma schema/helper validation and independent
review pass locally. Exact-source [feature CI `38514367627`](https://github.com/NOI56/PostDeeMobile/actions/runs/38514367627)
passes 1,909 API and 2,189 Mobile tests, typecheck, build, analyze and Prisma
checks. Exact-source [main CI `38514981824`](https://github.com/NOI56/PostDeeMobile/actions/runs/38514981824)
also passes; real Redis/provider/Firebase deletion acceptance remains unverified.
HTTP/worker lifetimes run concurrently; explicit queue/store FIFO remains intact.

Additive migration `20261014020000_track_owner_operations` is applied on
`postdee_staging` with all 18 migrations complete before the upgraded API
started. Authenticated account and synthetic R2 part/recovery/abort checks pass;
the retained Staging app/session/shop draft remain intact. Before activation in
another environment, apply the migration and upgrade/quiesce/drain every
API/worker process. Hosted flags remain unchanged and no disposable account was
created; Production stays user-suspended and receives no deployment.
Keep `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled` and the
existing single-instance Staging memory queue. Real Redis/provider/Firebase,
OAuth and legacy signed-PUT acceptance remain gates. See
[`2026-10-14-shared-owner-operation-drain.md`](docs/superpowers/plans/2026-10-14-shared-owner-operation-drain.md).

## Staging regression and test typing (2026-10-14, delivered to Staging)

Starting from verified main `f07ee30`, the local branch
`codex/staging-regression-and-test-types` repairs all 142 existing test-inclusive
TypeScript errors with typed fixtures. `npm run typecheck` now checks tests as
well as runtime source, and CI runs it after Prisma generation. Targeted tests
pass 474/474; the full API suite passes 1,871/1,871 in 116 files, with typecheck,
production build and Prisma validation passing at the typing-only phase.
That commit leaves runtime, schema, dependencies and mobile source unchanged;
it is included in the later `7576ee3` main/Staging delivery above. The existing
Staging app retains its session and original shop draft after restart and a
temporary edit/restore. Two independent processes on a local
PostgreSQL instance verify durable owner admission, while a simulated remote
operation demonstrated the cross-process drain gap addressed by the later
shared-operation implementation. Real Redis/provider acceptance remains pending.
A disposable Staging deletion account does not exist yet; creation steps are
prepared only. Keep
deletion and social publishing disabled. Native synthetic clip/manual-caption
checks and authenticated Staging R2 part transfer/recovery/abort pass; upload
completion and social delivery remain unverified. Evidence and enablement gates:
[`2026-10-14-staging-regression-and-typecheck.md`](docs/superpowers/plans/2026-10-14-staging-regression-and-typecheck.md).

## Account deletion retry authorization (2026-10-14, delivered to Staging)

The follow-up starts from main `1bf125c` and separates a lifecycle tombstone
from permission to finish account deletion. A missing Firebase UID by itself
must not let an old token delete PostDee data. The API must first persist a
server-generated deletion authorization for the same UID after a recent
Firebase authentication; only that proof can authorize a later retry. The
observed failure used a Firebase SDK fixture, not a confirmed real-Firebase
exploit. Local verification passed 1,871 API cases, the production API build,
Prisma generation/schema/helper checks, 159 mobile compatibility cases and
Flutter analyze. Disposable PostgreSQL execution passed 16 checks and actual
migration deployment. Source `3481f3f` is pushed on main and Live on Staging at
`dep-db785nvavr4c73a1cm80`; migration 17 is applied and health/readiness pass.
Exact-source CI `38452410378` passed 1,871 API and 2,189 Mobile cases plus
build/analyze/schema checks. The logo follow-up adds `await` to normalization
before resource disposal to satisfy the newer Flutter analyzer. No new APK
was installed. At that delivery, full test-inclusive TypeScript
checking retained main's 142 existing fixture errors with no new errors;
the separate local follow-up above repairs them.
This is not a Production-readiness claim.

The nullable `ManagedUploadOwner.deletionAuthorizedAt` column requires migration
`20261014003000_authorize_account_deletion` and a regenerated Prisma client
before deploying the API. Existing tombstones remain `NULL` and cannot be
automatically treated as authorized. A legacy account whose Firebase identity
is gone without proof needs verified operator recovery. This patch does not
change mobile response fields, dependencies or feature flags. See
[`2026-10-14-account-deletion-authorization.md`](docs/superpowers/plans/2026-10-14-account-deletion-authorization.md).

## Pending-work integration (2026-10-08)

The mobile UI cleanup is on remote `main` at `b1f793c`; its app source is
`aafd076`, verified by CI `37749129032`. The completed source integration is
`36dbaccb1d23ee46f9c970f2fdd8fff3d32b01d0`, pushed on both the integration
branch and remote `main`. Exact-source CI `37754460435` passed both Backend API
and Flutter Mobile jobs. The main-push CI intentionally skipped APK building;
the installed APK uses the separately validated local build receipt.
This integration adds bounded
owner-only Home media previews, `/ready`, graceful shutdown, evidence-only
interrupted-publish recovery, and complete coverage of mutating reads inside
the existing account mutation barrier. Relational user preparation already
exists on main in individual routes after their validation/quota gates;
the integration preserves it without adding a generic duplicate upsert.
It changes no database schema, provider
activation, dependency lock, package entitlement or Render topology.

Home requests `GET /posts?includeMedia=true&limit=3`. The API signs only owned
objects, prefers a cover, and omits unavailable URLs without hiding the post.
Older APIs still show the mobile placeholder. `/ready` probes the database and
queue, not a social provider, account connection or separate-worker heartbeat.
The memory scheduler and owner locks remain limited to one API process; unknown
publishing outcomes require reconciliation rather than automatic resending.
Case/trailing-slash variants of social/billing reads and `GET`/`HEAD`
`/uploads/:uploadId` retain the owner barrier. Upload status can reconcile
durable state, so its guard drains through response completion.

Staging API delivery completed on 2026-10-08: source
`9baa18c3483b2abd9b6f0ac619e74c00e15cbec6` (same API/runtime as tested `36dbacc`)
is Live on Render deploy `dep-db3m2g59fdbs73ecbib0`. Health/readiness return
`200`; authenticated empty-owner contracts and separate R2 image/video delivery,
range and cleanup checks pass. The checked owner has zero posts, so nonempty
native Home and two-account isolation remain unverified. Configuration is
preserved; full evidence/limits are in the integration plan linked below.

The validated Staging helper sets `POSTDEE_STAGING_BUILD=true`, showing a small
noninteractive strip above the app. Production defaults off. Windows developers
can inspect launcher paths without opening or installing anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apps\mobile\tool\launch-postdee-android.ps1 -ResolveOnly
```

Omit `-ResolveOnly` to build the exact checked-out `main` through the Staging
helper and update the emulator. Pass `-AvdName PostDee_Pixel` to select this
project's AVD explicitly. The updater checks the existing package UID, version
and storage; for an adopted private volume it requires that exact mounted UUID
and uses `install -r --force-uuid` with that UUID. It does not migrate, uninstall,
clear data or retry on another volume. The build number preserves the installed
version instead of defaulting to a lower version. SDK paths come from the local
environment/configuration; the existing debug keystore and validated ignored
RevenueCat Test Store overlay remain in use. On adopted storage, use this
launcher and then `flutter attach -d emulator-5556` for debugging; raw
`flutter run` or a plain `adb install -r` can select another data location.
The Staging `run` helper refuses that unsafe Android path before installation.
Delivery/current verification is tracked in
`docs/superpowers/plans/2026-10-08-integrate-pending-main-work.md`.
The capacity roadmap in `docs/superpowers/plans/2026-07-17-scaling-roadmap.md`
is a future proposal, not enabled infrastructure or a capacity guarantee.

## Profile Link Replaces AI Editing (2026-10-05)

The active mobile navigation is Home, Calendar, Create post, Store link, and
Account. Store link opens the internal link manager; Account opens the
existing profile/settings screen. The navigation uses a full-width opaque dock
painted through the bottom safe area, rounded top corners, outline icons, and a
raised solid green upload action. Selected items use green icons/text/dots. The
center action has no visible label but retains its localized tooltip and
accessible Create post name.
Create post is a full-screen action rather than a retained tab: the composer
hides the dock and returns to the previous tab when closed. Its current
four-step flow is described under Mobile below.
This navigation-only revision is recorded in
`docs/superpowers/plans/2026-10-06-flat-bottom-navigation.md`.
The Account tab uses a compact profile and four labeled menu groups. Only the
current package is shown; all packages open in the existing paywall. Language
and display mode open selection sheets, and logout sits at the bottom.
The Channels/tools group contains the social-connection row. Profile links open
from the Store link tab, and saved caption templates are selectable in Create
post. Their former shortcuts are removed from Account.
See `docs/superpowers/plans/2026-10-07-grouped-account-ui.md` for the mobile-only
scope and verification.
Home now puts a saved-draft/new-post action before compact connection,
upcoming-post, recent-post and profile-link sections. The monthly
views/likes cards remain removed, and Home does not request
`GET /analytics/summary`. Analytics remains available from publish results and
individual post details. AI video
editing and Subtitle Studio no longer have a product entry point, and the
paywall/profile no longer advertise editing minutes or top-ups. AI captions in
the upload flow remain available. The editing implementation and shared media
helpers below are retained as compatibility code, not an active product offer.
Since 2026-10-24 the API also stops serving it: every `/ai-edits/*` request
returns `410 AI_EDITING_RETIRED` without provider work unless the
`AI_EDITING_ENABLED=true` rollback switch is set. Real-clip AI captions now
accept only image frame keys, cap frames at 5 MiB, and return
`503 AI_MEDIA_BUSY` when two requests already hold media on the instance. See
`docs/superpowers/plans/2026-10-24-ai-editing-retirement-security-batch3.md`.

Each authenticated account can publish one profile page with up to 20 enabled
custom links on every package. The page is hosted by the existing PostDee API at
`/p/<slug>`; the app resolves the URL against its configured API domain. No
`postdee.link` domain or third-party statistics subscription is assumed.
Since 2026-10-24 a slug left by a rename or account deletion stays reserved for
30 days, so another seller cannot take over an old shared link. Only the
previous owner can reclaim it, and only after a rename. Brand and system names
(any slug containing `postdee`, `admin`, `support` and similar) cannot be
newly claimed. The app shows its existing "name already used" message. See
[`2026-10-24-link-in-bio-slug-reservation.md`](docs/superpowers/plans/2026-10-24-link-in-bio-slug-reservation.md). Public
pages show the store information, images, and links the owner explicitly publishes.
Draft edits remain private until Publish/Update is pressed. Publishing, copying
the confirmed URL, opening the page, and unpublishing are supported. Scheduled
post auto-updates and click analytics are not included.

All packages have the same profile customization: seven starting themes
(`minimal`, `shop`, `pastel`, `dark`, `pink`, `garden`, `cards`), separate text colors/fonts for names,
descriptions, categories, buttons and branding, per-link overrides, button
shapes, categories/order, and one featured promotion. Logo, cover, and image
backgrounds use the existing private media bucket; solid/gradient backgrounds
are also available. Draft customization stays private until Publish/Update.
The preview and public page share the same appearance contract and palettes.
Product cards/prices are not part of this release.

The 2026-10-07 decoration expansion adds pink pastel, cottage garden and lavender
storefront link cards. A collapsed `ลูกเล่น` group controls background movement,
link entrance, a featured-button lift and heart/flower/sparkle decorations.
Reduced-motion settings disable animations. The four earlier presets remain still by default. Cards
contain existing outbound links, not product inventory or prices. Free-position
dragging and animated media uploads are not included. No paid provider, dependency,
flag or schema change is required. Deploy the API theme/optional-effects contract
before distributing the new mobile build; older mobile builds need updating to
read the new theme IDs. The feature was pushed and deployed to Staging at
`8d96ea66d8086c66bf800920871ac5d71c65b209` on 2026-10-07; API and Mobile CI
passed on that exact commit. Deployment and remaining verification limits are in
`docs/superpowers/plans/2026-10-07-profile-themes-motion.md`.

The profile customization revision adds 100 layout/style templates in five
categories (minimal, cute/pastel, nature/warm, luxury/premium, creative/colorful),
twenty per category. A category picker opens a real draft preview before
applying; legacy themes remain available. The visitor/preview pause buttons are
removed as requested; owner effects controls and OS reduced motion remain.
The shared catalog and nullable version-1 `templateId` require API delivery
before Mobile, without a schema migration. The earlier API silently drops the
new template selection; older clients sending a complete appearance without
`templateId` can clear it. Update clients before editing new-template profiles.
This revision was pushed at `fc087c4119cd46503c569879e61cddf99e402fb2` and
deployed to Staging on 2026-10-07 at 16:18:19 GMT+7. Exact-commit CI passed
1,469 API tests and 1,422 Flutter tests; the running service also validated and
rendered all 100 templates in a read-only check. The matching Android Staging
APK was installed with existing account/draft data preserved. Delivery evidence
and verification limits:
`docs/superpowers/plans/2026-10-07-profile-template-categories.md`.

The subsequent Pinterest-inspired composition revision is **delivered to the
Staging API and installed on the Android emulator**. On 2026-10-07 the user accepted all fifteen
short-page directions A1–E3 and asked to expand them into one hundred choices.
Each category now has twenty different `layout.composition` values, replacing
the earlier five-header/four-button variation model. All hundred published
template IDs, appearance version 1, seven legacy themes, editable content and
custom styling remain supported. The chooser uses scaled instances of the real
native page renderer instead of schematic thumbnails; the selected preview
uses the owner's draft before explicit apply/publication.

This local revision bundles eight ImageGen raster decorations in
`apps/api/assets/profile-decorations` and
`apps/mobile/assets/images/profile_decorations`. The read-only allowlisted
`GET /profile-decorations/:file` serves local PNGs with one-day public caching
and nosniff; Pinterest is visual inspiration, never a runtime image source or
API dependency. Public HTML and Mobile share the generated catalog and matching
composition strategies. Pages remain short lists of existing links, with no
product or multi-section website builder. No database migration, credentials,
new provider or dependency is introduced, and the hundred brand-logo assets
remain unchanged. Pre-integration local checks passed: 1,555 API tests, 1,499
Flutter tests, analysis, API build/schema checks and the pre-integration Staging
debug APK build; that APK is not the combined release artifact.
Browser/IAB checks cover all hundred pages at 320px and native captures cover
all twenty structures. Initial integrated source `9c7fa74` preserves the latest
Account UI from `main` (`ebc9c47`) and the live four-step composer (`550f73a`).
Exact-source CI run `37623591224` passes 1,555 API and 1,556 Flutter tests plus
analysis/build/schema/audit checks. Render deployment `dep-db342ek9v7es73astung`
became Live; read-only runtime fixtures verify 100 stable IDs, five groups of twenty
compositions, eight PNGs and seven legacy themes. No migration is added.
Windows Flutter-tool startup prevented a new local build; opt-in manual CI
`37627939566` built the exact `9c7fa74` APK with Flutter 3.47.6 / Dart 3.13.5
after passing the same checks. Its tracked Staging example matches all nine
local configuration values. The APK was re-signed locally with the existing
debug key and installed in-place on emulator-5556. Installed bytes match the
verified artifact, and account/draft/preference fingerprints remain unchanged.
Keys and private JSON stay local. Provisional native QA opens/cancels all fifteen
accepted base previews, confirms five groups of twenty, and opens Account and
the four-step composer without changing the saved account/draft. It exposed
logo clipping in a tall gallery frame: a follow-up uses centered `contain` for
uploaded shop logos across all new compositions, retaining frame geometry and
cover/background-photo cropping. Correction source
`ae65b9d5eacddf6f9cf000bdb4efb44b4e82b3e0` passes exact-source CI
`37633935019` (104 API files / 1,556 tests; Flutter analyze / 1,559 tests;
Staging APK build). It is Live on `dep-db35c71srm7s73e5sf1g`; read-only compiled
fixtures confirm 100 centered contain-fit logos, retained IDs, cover cropping
and eight PNGs. Its separately verified/re-signed APK is installed in place on
emulator-5556 with the stored account/draft/preferences unchanged immediately
after installation. The initial `9c7fa74` APK receipt above is historical.
Public Staging browser/owned-image, iOS and physical-device checks remain
unverified. Signing keys and private configuration remain local.
Current delivery evidence and visual adaptations are recorded in the same plan.

The 2026-10-06 mobile revision opens the internal link manager for both new and
existing profiles. It shows the shop identity, separate Store information,
Appearance, and Preview actions, a primary Add link button above the list, and
cards for editing, visibility and drag ordering. The existing move up/down,
featured-promotion and delete menu actions remain available. Store information,
theme customization and review open as separate views; the manager does not
replace or redesign the public page. Advanced options retain their values.
The footer exposes Save draft and review, with Publish/Update kept as an explicit
action in review. Confirmed publication returns to the manager. Copy/open uses
only the confirmed public URL; status refresh and unpublishing remain available.
The mobile draft still holds at most 20 links, including disabled links, and
publishes only enabled links. At that 2026-10-06 revision drafts saved explicitly;
the later system audit adds owner-scoped serialized local autosave. Publication
still requires the explicit review action.
This revision requires no API/schema/configuration change. All 1,132 Flutter
tests, analysis, the Staging debug build and native Android emulator checks pass.
Evidence and remaining device/server limits are recorded in
`docs/superpowers/plans/2026-10-06-link-manager-ui.md`;
the earlier wizard's evidence remains in its dated plan.

The URL-title follow-up fills an empty link title from a recognized platform
name or the destination hostname. Generated titles follow URL changes until
the user enters a custom title; existing saved titles are preserved. Suggestions
use local URL rules only, without fetching page metadata or calling AI. The
follow-up passes 1,144 Flutter tests, analysis, the Staging debug build and native
Android emulator checks, with evidence and limits in the same plan. The earlier
verification above records the manager before this follow-up.

The 2026-10-06 platform-logo follow-up uses the same bundled full-color marks
for YouTube, Shopee, Lazada, LINE, TikTok, Instagram, Facebook, Messenger,
WhatsApp and Google Maps in mobile link
cards, the mobile preview and public pages. Marks occupy a transparent 40 x 40 slot.
Trusted source bounds fit the visible artwork's longest side to 40 and center it,
preserving its original aspect ratio and colors; this avoids shrinking marks
with large transparent canvases. All ten platforms have explicit bounds.
Website, email and telephone destinations use decorative vector icons;
manual generic-link and brand overrides remain available. Unknown HTTP(S)
destinations use the website icon. Draft/publication behavior remains unchanged.
The API serves only these ten PNGs at
`/profile-platforms/:file` from the page origin under the existing self-only CSP.
The earlier background correction uses the official transparent YouTube PNG and removes
the added white frame fill; original white elements inside marks stay intact.
Public YouTube images use `/profile-platforms/youtube.png?v=2` to bypass the
previous image cache. Other six files are unchanged.
The size-normalization follow-up changes display geometry only: all seven PNGs
retain their exact bytes, original white/colored artwork and public asset URLs.
Only transparent margins may fall outside the slot; visible content is retained.
Deploy the API with `apps/api/assets/profile-platforms` to update existing
published pages without republishing; this follow-up needs no database migration.
Verification and delivery status are recorded separately in
`docs/superpowers/plans/2026-10-06-profile-platform-logos.md`.

The contact expansion recognizes Messenger, WhatsApp and trusted Google Maps
domains/paths locally, without fetching linked pages or calling an AI/provider.
Empty titles are suggested as `Messenger`, `WhatsApp`, `Google Maps`,
`ส่งอีเมล` or `โทรหาร้าน`; custom titles and the hostname fallback remain intact.
The mobile destination field also accepts a plain email address or a phone
number (optional `+`, 7–15 digits), then normalizes it to `mailto:` or `tel:`
before saving/publishing; users do not have to enter those prefixes themselves.
Alongside existing credential-free HTTP(S), links may use a single plain ASCII
`mailto:` address without query, fragment, percent encoding or multiple recipients,
or `tel:` with an optional leading `+` and 7–15 digits. Other URI schemes and
malformed contact destinations remain rejected. These are outbound contact
links, not chat, maps, email or telephony integrations. The app lets the visitor's
installed software handle the selected destination.
Deploy the updated API/assets before distributing the new mobile build: older
APIs reject the added icon values and `mailto:`/`tel:` destinations. Existing
HTTP(S) links and icon values remain valid. This expansion changes the profile
URL/icon contract but adds no schema, database migration, dependency, package
benefit, environment flag or paid-provider call. Its verification/release status
is tracked in the same platform-logo plan; earlier test totals above are historical.

The 2026-10-07 global-logo expansion provides **100 brand logos in total**:
the ten existing marks plus 90 additional destinations associated with China,
Korea, Japan, India, Southeast Asia, Europe, the Americas and global services.
This is a curated selection, not a ranking of the world's 100 largest apps.
Website, email, telephone, generic link and automatic-selection values do not
count as brand logos. In Mobile, one searchable picker finds logos by brand
name, alias and country; recognized URLs suggest a platform name only when the
user has not supplied a custom button title. Existing manual overrides, contact
validation, draft/publication behavior and the 20-link limit are preserved.

`shared/profile-platforms.json` is the common catalogue for domains, display
names, search aliases, sources, PNG hashes and audited visible bounds. Its
generator produces the TypeScript/Dart catalogues; the generator's `--check`
mode checks generated output and the 100 API/Mobile asset copies for parity.
Both surfaces retain transparent 40 x 40 display slots, original proportions
and colors. No extra white badge is added; any original app-icon background
and visible white artwork remain intact. Public `/profile-platforms/:file`
accepts exactly the 100 bundled PNG filenames. No runtime vendor-logo fetching,
paid API, provider integration, dependency, feature flag, schema or migration is
added. Deploy API/assets before distributing Mobile because older APIs reject
the new icon IDs. Current verification and release status are tracked in
`docs/superpowers/plans/2026-10-07-global-profile-platform-logos.md`;
earlier release results above do not verify this expansion.

Migration `20261005193000_customize_link_in_bio_profile` adds nullable appearance
JSON and owner-scoped image metadata. Old profiles use the original cream/green
defaults; clients omitting the entire appearance object can publish links
without overwriting customization. Old clients sending a complete appearance
do not preserve fields they do not understand.
Deploy the generated Prisma client, migration, API and bundled font assets
before distributing the new mobile build. Staging now runs this migration/API
at `9195211f16519fd58c9cc01d6949dd8486190d01`; real logo upload and authenticated
image reload after restarting the app passed. Public page/image and unpublishing
checks remain unverified for this customization release. The user deferred live
browser and R2 lifecycle checks after access was blocked. See the dated verification in
`docs/superpowers/plans/2026-10-05-profile-page-customization.md`.

The 2026-10-13 mobile logo-positioning follow-up lets the owner drag and zoom
the chosen shop image inside a circular preview before confirming it. Both
shop information and decoration use the same crop flow; cancel retains the
previous logo and draft. Export produces a bounded square PNG through the
existing owned-image upload contract. Delivery verification is recorded in
`docs/superpowers/plans/2026-10-13-shop-logo-position-main.md`.

Production persistence uses `POST_STORE=prisma` and the additive LinkInBioProfile
migration. In-memory mode is local scaffolding and loses pages when restarted.
Deploy the API and run its migrations before shipping the mobile build. This
change is deployed on the existing Staging service; Production remains unchanged
and no new domain was registered. Hosting/database availability and their
existing costs still apply.

## Project Structure

```text
apps/
  api/      Node.js, Express, TypeScript, Prisma, PostgreSQL scaffold
  mobile/   Flutter source scaffold for iOS and Android
```

## Deployment Environments

- เตรียมชุดแก้ Staging วันที่ 20 ตุลาคม 2026 ใน worktree แยกจาก remote `main`
  `c2777a8` ที่ตรวจแล้ว: dependency fixes, modular FCM และ Blueprint/tests/docs
  โดยคง Mobile/admin/CI/ElevenLabs/Gemini ปัจจุบัน ไม่มี migration ใหม่
  ปรับโครงสร้าง local ให้ตรง Starter/main/manual และ Basic 256 MB/1 GB/
  PostgreSQL 18 แล้ว ผล API 2,305 tests (`--maxWorkers=2`), typecheck/build/Prisma และ clean install
  ผ่าน; audit รวม optional dependencies เหลือ 0 findings ส่วน DB integration
  18 tests ข้ามในรอบก่อน deploy ต่อมาตรวจบน PostgreSQL 18.1 local fixture แยก
  ผ่าน 18/18 ทั้ง UTC/Asia/Bangkok และ API เต็มผ่าน 2,323 tests ไม่มี skip
  ล้างข้อมูลจำลอง/ปิด cluster แล้ว Predeploy อ่าน live DB/environment พบ Social `postpeer`
  ต่าง YAML `disabled` จึงรักษา Dashboard flags และ manual deploy เฉพาะ SHA
  ที่ตรวจแล้ว โดยรอบ deploy เดิมไม่ sync Blueprint/merge `main`
  ส่งมอบ source `0a43e7b` เป็น Live
  บน Staging deploy `dep-dbbmva3bc2fs73bnpemg` แล้ว instance ใหม่ยืนยัน SHA,
  Node 22.23.3, health/ready 200 และ 20 migrations ไม่มี pending;
  Node 26.12.0 เป็นข้อมูลก่อน deploy Provider/device E2E ยังต้องตรวจต่อ
  ไม่ใช้ checkout เก่าที่มีงานค้างเป็นชุดปล่อย
  ภายหลังผู้ใช้อนุมัติ main/push จึงรวม runtime และเอกสารผล DB เข้า `main`
  แล้ว โดยใช้ `[skip render]` กับ commit เอกสารสถานะ ไม่ deploy ซ้ำหรือเปลี่ยน
  บริการที่ Production user-suspended / Staging auto-deploy off
  รายละเอียดและสถานะผลตรวจอยู่ใน [Staging delivery](docs/STAGING.md)
- `render.yaml` จัดการ Production (`postdee-api` และ `postdee-postgres`)
- `render.staging.yaml` เป็น Blueprint แยกสำหรับ Staging แบบต้นทุนต่ำ และต้องใช้
  database, R2 bucket, Firebase project, RevenueCat webhook และ PostPeer account
  ชุดทดสอบเท่านั้น
- ขั้นตอนและข้อจำกัดค่าใช้จ่ายอยู่ใน `docs/STAGING.md` ปัจจุบันสร้างทรัพยากร
  Staging บน Render แล้ว, `/health` ผ่าน และ Android Debug ใช้ Firebase project
  แยกพร้อมผ่าน Google Sign-In → Firebase token → Staging API บน Emulator แล้ว
  RevenueCat Test Store/offering/webhook ตั้งค่าแล้ว และทั้ง purchase กับ true
  Restore/resync E2E ผ่านบน Android Emulator ด้วย Firebase UID หลัง deploy backend
  และตั้ง `REVENUECAT_REST_API_V1_KEY` ใน Render Staging (เป็นราคาทดสอบและไม่มีการ
  เรียกเก็บเงินจริง) ฝั่ง RevenueCat มี Play Store app, Starter/Pro products,
  entitlements, default offering และ production Android public SDK key แล้ว พร้อม
  signed AAB สำหรับอัปโหลด แต่ Play Console app/subscriptions, internal testing,
  service credentials และ Google Play purchase จริงยังทำไม่ได้จนกว่าจะยืนยันสิทธิ์
  ด้วยมือถือ Android จริง; Emulator ใช้ยืนยันขั้นตอนนี้ไม่ได้
- Render Staging ติดตาม branch `main` แล้ว บันทึกการทดสอบเดิมระบุว่าการอัปโหลด
  R2 จากแอปผ่านและเคยตั้ง `GEMINI_API_KEY`/`ELEVENLABS_API_KEY` ชุด Staging
  รอบเดิมที่ส่งวิดีโอ 38 MB ทั้งไฟล์หยุดที่ transcription เพราะเกินขนาดไฟล์ของ
  provider โดยโควตาไม่เปลี่ยน โค้ดปัจจุบันจึงแยกเสียง M4A ขนาดเล็กก่อนอัปโหลด;
  backend ปัจจุบัน deploy แล้ว แต่ยังต้องยืนยัน secret ใน Dashboard และทดสอบคลิป
  เดิมซ้ำบน release candidate ก่อนนับว่า AI edit ผ่าน E2E

## Backend Runtime Dependency Boundary

GitHub CI installs all optional packages because native build and test tools use
platform-specific optional binaries. Its production audit excludes optional
packages that are not part of the PostDee runtime. Render completes the build
and Prisma migration first, then prunes development and optional packages before
starting the API. PostDee uses `firebase-admin` for Auth and FCM only; the
optional Firestore and Google Cloud Storage clients are not shipped in the
running service. Video storage continues to use Cloudflare R2.

The lockfile resolves Firebase Admin's compatible `@fastify/busboy` dependency
to `3.2.3`, including fixes for the multipart parser advisories
`GHSA-xjh9-v7x6-24jw` and `GHSA-x8mw-p69m-v3mx`. CI continues to reject high
severity findings in the production dependency audit.

The compatible Express dependency `proxy-addr` is locked to `2.0.8` to patch
`GHSA-jqcg-44mw-7w3h`. Express's existing single-hop `trust proxy = 1` policy is
unchanged. A dependency regression covers the advisory's mapped-IPv6 subnet
case, and a global rate-limit integration test verifies that changing the
untrusted forwarded prefix cannot change the established client's bucket.
The 2026-10-05 pre-merge audit recorded no high/critical findings and four
moderate findings in `docs/superpowers/plans/2026-10-05-profile-link-simpler-ui.md`.
That is a historical result; current candidate dependency checks are recorded
separately in `docs/STAGING.md`.

## Legacy AI Editing Runtime Reference

The following runtime notes describe retained compatibility code. Since
2026-10-05 this flow is absent from the current mobile navigation and package
marketing; it is not a release requirement for the replacement profile page.

- Both `render.yaml` and `render.staging.yaml` set
  `TRANSCRIPTION_PROVIDER=elevenlabs`, `EDIT_PLAN_PROVIDER=gemini`, and
  `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite`. ElevenLabs Scribe v2
  produces timed Thai transcripts; Gemini 3.5 plans from the full visual proxy
  and transcript with structured JSON and provider-default sampling (no
  explicit `temperature`); deterministic PostDee rules are the final fallback.
  Groq is not selectable in runtime configuration.
- Transcript gaps are silence candidates only. The Android/iOS client confirms
  each candidate against the source waveform before rendering; failed or
  ambiguous verification keeps the original audio. The verifier uses FFmpeg
  `silencedetect`, keeps only padded intersections away from source edges and
  protected speech, and passes those verified ranges through preview, review,
  subtitle re-render, and export. Local retry does not transcribe, upload, call
  `/ai-edits/prepare`, or consume another AI-edit minute. A successful probe
  with no safe range is shown separately from a probe failure.
- The retained color-only compatibility path renders original-duration edits
  locally for Pro users and does not consume AI editing minutes. It does not
  extract audio, upload media, or call `/ai-edits/prepare`; the seller-facing
  setup card is now hidden. Colour plus shortening or any audio-dependent
  capability keeps the normal API path. Unknown enabled capabilities fail
  closed before either route starts side effects.
- Fresh device measurements for output codec, FPS, file size, audio peak, and
  A/V sync remain a release gate. The local colour-only path now has one exact
  Pixel 8 export measurement, but the API-dependent matrix is blocked and the
  repository does not claim the renderer acceptance checks are complete.
- The verified Tasks 3–8 implementation is committed locally in `43fa6e0`.
  Task 9 Steps 1–5 are complete, with exact deployed Staging SHA/health and the
  fresh APK/fixture hashes recorded. Step 6 is `BLOCKED`: a new 30-day,
  Speech-to-Text-only Staging key was installed and deployed on the unchanged
  code SHA, but `target-30` still failed closed with upstream HTTP 401 at 21:57
  ICT, without output or PostDee quota use. ElevenLabs showed 9,994/10,000
  workspace credits used (6 remaining), so provider-side quota exhaustion is
  the leading diagnosis; the upstream response detail was not available to
  prove the exact cause. Colour-only local render/export evidence passed
  without consuming quota, while direct zero-upload/prepare log evidence
  remains pending.
  Remaining matrix rows are open.

## Backend

Path: `apps/api`

Current backend pieces:

- `GET /health`
- Mock-safe route implementations for uploads, posts, captions, templates,
  analytics, and billing
- In-memory stores for local posts, templates, and single-process publish queue testing
- Optional BullMQ publish queue adapter selectable with `PUBLISH_QUEUE=bullmq`
- Optional Cloudflare R2 video storage adapter selectable with `VIDEO_STORAGE=r2`, including signed upload and signed download access scaffolds
- Optional Gemini caption adapter selectable with `CAPTION_PROVIDER=gemini`
- ElevenLabs Scribe v2 adapter selectable with
  `TRANSCRIPTION_PROVIDER=elevenlabs`; brand-name keyterms are opt-in because
  the provider charges extra for keyterm prompting
- Legacy S3/OpenAI adapters remain available with `VIDEO_STORAGE=s3` and `CAPTION_PROVIDER=openai`
- Mock/Firebase auth middleware selectable with `AUTH_PROVIDER=firebase`
- RevenueCat webhook receiver for Starter and Pro subscription entitlements
- Authenticated RevenueCat subscriber resync for reconciling restored purchases
- Legacy store subscription verification scaffold for Apple App Store and Google Play purchases
- Store notification handler that updates paid entitlement state for known verified store purchases
- Mock publish worker scaffold for the `publish-posts` queue
- Prisma schema for users, posts, platform publishing records, saved templates, and subscriptions
- Prisma schema and repository for persistent real-clip AI caption usage
  counts
- `.env.example` with required environment variables

Run backend checks:

```powershell
cd apps/api
npm.cmd install
npm.cmd run prisma:generate
npm.cmd run typecheck
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'; npm.cmd run prisma:validate
```

Prepare a local PostgreSQL database after `DATABASE_URL` is set:

```powershell
cd apps/api
npm.cmd run prisma:generate
npm.cmd run prisma:migrate:dev
npm.cmd run prisma:seed
```

The seed command upserts the mock auth user from `MOCK_USER_ID`, `SEED_USER_EMAIL`, and `SEED_USER_DISPLAY_NAME`.

Start the backend in development:

```powershell
cd apps/api
npm.cmd run dev
```

The API listens on port `4000` by default.

Start the publish worker scaffold after Redis is available and `PUBLISH_QUEUE=bullmq`, `POST_STORE=prisma`, and `DATABASE_URL` are configured:

```powershell
cd apps/api
npm.cmd run worker:publish
```

The worker currently uses mock platform publishing and mock video cleanup by default. When `ANALYTICS_STORE=prisma`, it records platform publish results into `PlatformPublish` so the analytics summary can read them from PostgreSQL. It claims posts with `QUEUED -> PUBLISHING` before calling external publishers, skips jobs for posts that are already running or finished, skips stale scheduled jobs whose `runAt` no longer matches the post's current schedule, and treats optional R2/S3 cleanup failures as best-effort cleanup results instead of changing a successfully published post to failed. It is the handoff point for real TikTok, YouTube Shorts, Instagram Reels, Facebook Page Reels, and R2/S3 cleanup integrations. The existing `FACEBOOK_REELS` value always sends PostPeer `platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`, preserving `PUBLISH|PAGE_DRAFT` and optional `isAiGenerated`. Facebook requires a video and never falls back to a Page feed video; real-account E2E remains pending.

PostPeer `202 pending/publishing` responses are polled through
`GET /v1/posts/{postId}` for roughly two minutes. A platform is marked
`PUBLISHED` only when PostPeer returns a real platform URL or id; the backend no
longer invents an external id. Only errors explicitly known to be safe may be
retried. An uncertain provider outcome fails closed with instructions to check
the platform before trying again, so a retry cannot silently create a duplicate.

### Backend API

The API defaults to mock-safe/local adapters. When explicitly configured, it
can call real R2, Gemini, ElevenLabs, Firebase, PostPeer, and RevenueCat services.
Having an adapter in code does not mean its provider-level production test has
passed; see `docs/GO_LIVE.md` for the current activation checklist.

#### `GET /health`

Returns service status.

```json
{
  "status": "ok",
  "service": "postdee-api"
}
```

#### `GET /publishing/readiness`

Authenticated configuration preflight for new social posts. A `200` response
with `{ "status": "ok", "acceptingPosts": true,
"platformSettingsVersion": 1 }` means that this API process is not configured
with `SOCIAL_PUBLISHER=disabled` and accepts the Phase 2 settings contract. It
does not probe
PostPeer, object storage, the publish queue, or the signed-in user's connected
accounts, and it is not provider-level readiness evidence.

Roll out this contract API-first: apply the Prisma migration, deploy the API,
and verify `platformSettingsVersion: 1` before releasing Mobile that sends
per-platform settings. The version is an operational compatibility signal, not
a provider-health check; current Mobile also fails closed before upload when the
field is missing, malformed, or lower than `1`.

Both the accepting `200` response and disabled `503` response set
`Cache-Control: private, no-store` so a previous readiness result is not stored
for reuse. This is a defensive response contract; it does not establish that
caching caused any earlier observation.

When publishing is disabled, the route returns `503` with
`SOCIAL_PUBLISHING_UNAVAILABLE`. Current mobile clients call this endpoint
before watermarking or uploading media and show a Thai unavailable message.
`POST /posts`, `PATCH /posts/:id`, and `POST /posts/:id/publish-now` repeat the
same authoritative gate in case the configuration changes after the preflight;
`DELETE /posts/:id` remains available so an existing queued post can still be
canceled.

#### `GET /auth/me`

Returns the current scaffold auth user. With `AUTH_PROVIDER=mock`, the API uses `MOCK_USER_ID` by default and supports development headers such as `x-postdee-user-id`, `x-postdee-email`, `x-postdee-display-name`, `x-postdee-phone-verified`, and `x-postdee-phone-number`.
`AUTH_PROVIDER=mock` is for local development only; startup rejects it when
`NODE_ENV=production`.

Response:

```json
{
  "status": "ok",
  "user": {
    "id": "local-dev-user",
    "provider": "mock"
  }
}
```

#### `POST /uploads`

Creates upload metadata and returns a temporary object key; local mock storage
keeps this flow provider-safe during development.
This route requires the current authenticated user. In local mock mode, the
mobile app sends `x-postdee-user-id`; in Firebase mode, it sends a bearer token.

Request:

```json
{
  "fileName": "demo reel.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 12345678,
  "width": 1080,
  "height": 1920,
  "uploadProtocol": "multipart-v1"
}
```

Response includes `upload.videoS3Key`, the existing legacy field name for the temporary object key that can be passed to `POST /posts`. New upload keys are scoped to the authenticated user, for example `uploads/<user-id>/<upload-id>/<file>`.
For generic uploads, provided `width` and `height` must describe a vertical
9:16 video, such as `1080x1920`. AI caption clip uploads use the explicit
`"purpose": "ai-caption-video"`: an `.mp4` file with `video/mp4` can have any
aspect ratio. Mobile retains known source dimensions, so `1080x2400` (9:20)
can be analyzed without changing its metadata. Dimensions may be omitted
together; when supplied, both must be positive finite integers. Generic upload
and mobile posting validation keep their existing 9:16 policy.
The backend rejects uploads above `UPLOAD_MAX_SIZE_BYTES` (default `524288000`, or 500 MiB).

This additive upload purpose is Live in Staging API `9f0b729`. Other environments
must deploy the API before the new mobile build; no database migration is
required for this purpose. An older API ignores the unfamiliar purpose and still
rejects known non-9:16 dimensions.

New mobile clients opt in with `"uploadProtocol": "multipart-v1"`. In `dual`
or `multipart` mode, the response contains an opaque session `id`,
`partSizeBytes`, `partCount`, and `sessionExpiresAt`. The client requests each
part URL just in time from `POST /uploads/:uploadId/parts/:partNumber`, uploads
that exact byte range, and sends the returned ETags to
`POST /uploads/:uploadId/complete`. A managed `videoS3Key` can be used by
`POST /posts` only after the session reaches `COMPLETED`; status and abort are
available through `GET /uploads/:uploadId` and `DELETE /uploads/:uploadId`.
Ambiguous completion responses are polled with bounded backoff, and the API can
reconcile a `COMPLETING` session by checking the completed R2 object's exact
size before marking it `COMPLETED`.

`UPLOAD_PROTOCOL_MODE` defaults to `legacy`, so existing clients still receive
the original signed `PUT` fields (`uploadUrl`, `uploadMethod`, `uploadHeaders`,
and `uploadExpiresAt`). Production uses `dual` during rollout: opted-in clients
use managed multipart while older clients keep working. The legacy URL remains
a replay risk until all supported clients are upgraded and production can move
to strict `multipart` mode.

#### `POST /captions/generate`

Generates a local Thai affiliate caption template from 1 or 2 keywords. This route requires a paid plan, either Starter or Pro, limits each keyword to 80 characters, and consumes the same monthly AI caption generation quota used by paid caption features.

Current product direction: AI captioning should start from a selected real
clip. Starter uses audio-only understanding, while Pro can combine audio with
selected visual frames. The app should let AI detect the spoken language and
best caption direction from the clip automatically; if a seller wants a
different language, market, or style, they can write that in optional guidance.
The keyword endpoint remains a temporary scaffold and should not be the main
paid package promise.

Request:

```json
{
  "keywords": ["กันแดด", "ผิวใส"]
}
```

Response includes `caption`, `hashtags`, `[ใส่ลิงก์ Affiliate ที่นี่]`, and the remaining monthly `quota`.

If the authenticated user is Basic, the API returns `402` with code `PRO_REQUIRED`. If the monthly caption quota is exhausted, it returns `429` with code `AI_CAPTION_QUOTA_REACHED`.

#### `POST /captions/generate-from-clip`

Generates the new mock-safe real-clip AI caption package after a clip is
selected. This route accepts `videoS3Key`, optional `guidance`, optional
`writingStyle`, optional `selectedFrameKeys`, and optional `deleteAfterUse`.
The mobile upload flow sends `deleteAfterUse: true` for AI-only clip/frame
uploads so the backend attempts
R2/S3 cleanup after the caption request. The route also checks that media keys
belong to the authenticated user and reserves monthly quota before calling the
AI provider.

AI caption generation uploads the selected clip and optional Pro frames to
configured storage/providers and may consume mobile data. Existing Starter/Pro
access, owner checks, media limits and generation quota remain unchanged. This
fix has not performed real remote user uploads, provider generation or paid
state changes; production generation remains unverified.

- Starter retains the historical `AUDIO_ONLY` mode and 50 caption credits/month.
- Pro retains `AUDIO_WITH_FRAMES`, adds up to three selected frames, and has
  120 caption credits/month. Both Gemini modes receive the whole MP4; the mode name
  does not mean an isolated audio upload or a new package rule.
- Shared-caption generate/change requests cost one credit; advanced requests
  cost one credit per selected channel. The API atomically reserves the full
  cost, using monthly quota before nonexpiring add-on credits.
- The current scaffold returns caption options, hooks, hashtags, SEO keywords,
  a search title, auto language/market context, source mode, and remaining
  quota.
- Local development can keep usage in memory with `CAPTION_USAGE_STORE=memory`;
  production should use `CAPTION_USAGE_STORE=prisma` after the Prisma migration
  is applied.
- In local mode, `TRANSCRIPTION_PROVIDER=mock` returns a safe Thai transcript.
  In production, `TRANSCRIPTION_PROVIDER=elevenlabs` or legacy `openai` downloads the stored
  clip through signed storage access and sends it to the speech provider.
- The backend does not sample frames; Pro's mobile flow extracts them.

The caption-quality follow-up asks Gemini to ground a natural opening hook and
caption in observed speech, visible actions and legible text. Silent clips must
not invent speech, tutorial steps, product claims or incidental identifiers.
Thai is the prompt default unless actual speech or dominant meaningful text
across the clip clearly establishes another language; brands, account names,
dates and numbers do not override it. Captions use the creator's voice for the
viewer, rather than an analysis summary, in one or two short sentences.
Silent menu navigation should preview only the menus/data actually visible,
without inferred store creation, business setup or promotional benefits.
Visible buttons, plan or link labels do not prove setup, editing, purchase,
scheduling or integrations. Real-clip generation temperature is reduced from
0.8 to 0.4 to discourage speculative claims. Prompt instructions cannot
guarantee accuracy; sellers must review
the result. Gemini hashtags and SEO keywords are normalized and deduplicated,
with at most five each; missing or invalid metadata stays empty instead of receiving
unrelated generic defaults. Hooks remain a separate response field.

Mobile inserts the caption and only hashtags not already present; it does not
append a literal `SEO:` paragraph. Suggested search keywords stay in the collapsed
`คำค้นที่ AI แนะนำ` area for the current screen. Replacing a clip retains existing
caption and guidance and asks for review; applied fallback AI also requires
review. The optional local draft `captionNeedsReview` flag defaults to false in
existing version-3 manifests and persists until `ตรวจแล้ว` or an applied
non-fallback AI result. Ordinary text edits do not clear it. This follow-up adds
no API field, migration, model, retry, quota or publishing-platform change.
Limited direct-provider probes improved the final primary caption but still
returned incorrect silent-language metadata; they do not establish general
quality or deployed API/quota behavior. The local Staging APK is installed;
authenticated caption-screen smoke remains pending at the user's choice, and
this caption patch has not been pushed or deployed.

The subsequent caption-style follow-up is in progress. Optional `writingStyle`
selects tone (`auto`, `friendly`, `playful`, `direct_review`, `soft_sell`), length
(`auto`, `short`, `medium`) and emoji (`auto`, `none`, `light`). Omitted fields
default to `auto`, with no examples; an omitted object keeps legacy requests.
The prompt requests 1–2 sentences for auto/short and 3–4 for medium, without
inventing facts to fill the length. Presets outrank remembered style; examples
are untrusted style data, not clip evidence or instructions. Compliance is not
guaranteed and local fallback retains its existing labeled behavior.

Mobile keeps the selected style and up to three human-edited caption examples
on this device, separately per account. Each stored example is trimmed and
limited to 500 UTF-16 code units. The visible remember-edits switch defaults on;
when off, examples are neither learned nor sent. Clear memory keeps manual
style choices; successful account deletion clears that owner's whole profile.
An example is learned only after editing an applied non-fallback AI caption
for the same account/clip, with review cleared, then tapping Next from caption
to platforms. Progress jumps, draft saves, cancellation, unchanged AI and
fallback do not learn. Style/examples accompany manually requested generation
to the configured AI; there is no cloud style profile or social-history import.

Deploy the additive API support before installing/shipping this mobile feature;
an older API ignores `writingStyle`. Automated checks and the local `089dcb52`
APK build pass. Staging API source `7d568458` is Live; the new APK remains
uninstalled to preserve the open form. Native, real paid AI/style-quality and
live HTTP verification remain pending. Prices, rights, quotas, model/provider
settings, schema and environment remain unchanged; see the chronological audit
follow-up for the exact-source CI and deployment receipt.

#### Removed: `POST /clip-reviews`

The legacy AI Clip Review endpoint is no longer mounted. Requests to
`/clip-reviews` return `404`.

Reason: it overlaps with AI caption from the real clip and made the package
copy confusing. Useful ideas from the old mock review output should move into
AI caption from the real clip or the Pro ElevenLabs + Gemini auto-editing flow.

#### `GET /templates` and `POST /templates`

Stores reusable text templates for the current authenticated user. Template
lists and creates are scoped by `userId`.

Create request:

```json
{
  "title": "Affiliate disclosure",
  "body": "ลิงก์นี้เป็นลิงก์ Affiliate"
}
```

#### `GET /posts` and `POST /posts`

Stores queued posts in the configured memory/Prisma post store and creates a
publish job in the configured queue.
The mobile publish-draft feature is deliberately outside this API: saving a
draft copies its video, optional cover, and manifest into app-owned Application
Support storage scoped by the signed-in stable user ID (the Firebase UID with
real authentication). It does not create
an API post, upload to R2, contact PostPeer/social platforms, enqueue work, or
consume post quota. Consequently there is no `DRAFT` value in the backend post
status contract and `GET /posts` never returns these local drafts. They are not
synced between devices, although the operating system may include app-owned
files in a device/cloud backup according to its backup settings.

The scaffold can still accept `subscriptionPlan` as a temporary request override
only in local mock development. When `NODE_ENV=production`, the backend rejects
request-body plan overrides and uses the configured subscription store instead.
If no plan is available, the request is treated as `BASIC`.
Posts are scoped to the current auth user. With `AUTH_PROVIDER=mock`, use `x-postdee-user-id` to simulate different sellers during development.
With the memory subscription store, use `x-postdee-subscription-plan: STARTER` or `PRO` to simulate a paid seller.

Create request:

```json
{
  "clientRequestId": "submit_2d7d3b0b7d8e4ec58c0e4d72",
  "caption": "ของดีต้องลอง #ของดีบอกต่อ",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
  "coverFrameTimeMs": 4200,
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "platformSettings": {
    "TIKTOK": { "publishMode": "INBOX_DRAFT" },
    "YOUTUBE_SHORTS": {
      "title": "รีวิวสินค้าชิ้นใหม่",
      "visibility": "private",
      "madeForKids": false,
      "containsSyntheticMedia": false,
      "communityGuidelinesCertified": true
    }
  },
  "subscriptionPlan": "PRO",
  "scheduledAt": "2026-06-02T10:00:00.000Z"
}
```

Phase 2 keeps the main screen compact: selecting a connected destination reveals
one short outcome summary and a settings button; the detailed controls open in
that platform's sheet instead of placing every platform field on the main form.
The review also names the connected account/channel/page using its display name
or external account id. Mobile fails closed when that identity is missing, a
required setting is incomplete, or the requested outcome cannot be determined;
the seller must refresh or reconnect instead of confirming an inferred target.
The complete explicit settings shapes are:

- TikTok: `INBOX_DRAFT`, or the complete `DIRECT_POST` shape documented in
  `API.md`. Direct requires current creator options, an account revision,
  explicit privacy/interaction/disclosure choices and consent. The old two-field
  `DIRECT_POST`/`SELF_ONLY` shape remains readable only for persisted legacy work.
  Production/public enablement still requires provider approval verification and
  controlled publication testing.
- YouTube Shorts: a title (1–100 characters, no `<` or `>`),
  `private|unlisted|public`, the made-for-kids answer, the realistic synthetic
  media answer, and `communityGuidelinesCertified: true`.
- Instagram Reels: `shareToFeed: true|false`; there is no per-post Private mode.
- Facebook Page Reels: `publishMode: PUBLISH|PAGE_DRAFT`. The user must choose;
  the internal compatibility platform name remains `FACEBOOK_REELS`.

“Save draft in PostDee” and provider drafts are different. A PostDee draft stays
local and has no remote side effect. TikTok `INBOX_DRAFT` and Facebook
`PAGE_DRAFT` run only after Post: they upload media, create a server post, enter
the queue, contact the provider, and consume one post unit for that destination.

The new-post response includes `post` and `publishJob`. If `scheduledAt` is
present, the job status is `SCHEDULED`; otherwise it is `READY`. A replay of a
post that has already advanced beyond `QUEUED` can return the existing `post`
without a job.
For new connected-account posts, the API also saves an immutable internal target
snapshot and revalidates that account before the final database write and again
before the worker calls PostPeer. A disconnected or changed account fails
closed. Provider account ids in `platformTargets` and the provider-level
`providerPostId` are internal and are removed from public post, queue, and
platform-result responses.
Current Mobile stores one stable `clientRequestId` in each local draft. The
first accepted request returns `201`; a matching retry returns the same durable
post with `200` and `idempotentReplay: true`, repairing its missing queue job
when it is still `QUEUED`. A committed key reused for a different publishing
intent—including different platform settings—or one whose original post is
terminal `FAILED`, returns a safe `409`
instead of reporting a new queue success. Legacy requests may omit the field,
but every such call is treated as a new attempt and has no deduplication
guarantee.
After `409 IDEMPOTENT_POST_FAILED` or `409 IDEMPOTENCY_KEY_REUSED`, Mobile keeps
the original local draft and records the block against that draft ID in the
current Upload state, so another Post tap does not upload again. The only way to
submit again from this state is the explicit “เริ่มรายการโพสต์ใหม่” action: it
warns that the old attempt may already exist, requires confirmation, then saves
the same editable content as a new draft with a new request ID while retaining
the original draft for inspection.
An accepted schedule must be strictly in the future and no more than 14 days
ahead for Starter or 30 days for Pro, measured from the server's current time.
The current plan's window applies when creating or rescheduling a post. Existing
accepted schedules keep their original time after this policy change or a plan
downgrade; listing and automatic publishing do not reapply the shorter window.
`videoS3Key` and optional `coverImageS3Key` must come from `POST /uploads` for
the same authenticated user; the backend rejects media keys owned by another
user. `coverFrameTimeMs` stores the selected source-video frame in milliseconds.
Cloud Scheduling requires Starter or Pro, both when a post is scheduled and,
since 2026-10-24, again when it comes due. A scheduled post whose owner is back
on `BASIC` by then is not sent: it becomes `FAILED` with platform reason
`PAID_PLAN_REQUIRED`, its units stay used, and the usual failure push is sent
(see
[`2026-10-24-scheduled-post-plan-check.md`](docs/superpowers/plans/2026-10-24-scheduled-post-plan-check.md)).
The `BASIC` scaffold path supports
real-time posting only after phone verification and is limited to 3 post units
per month. Starter is limited to 120 post units per month, and Pro is limited
to 250 post units per month. A post unit is counted per selected platform, so
one video posted to four platforms uses four units. Repeated platform values
are collapsed, and the quota check plus post insert is atomic. `scheduledAt`
must be a valid future RFC 3339 timestamp with `Z` or an explicit `±HH:mm`
timezone, and stay within the current plan's 14/30-day window. The API rejects
impossible calendar dates and normalizes accepted offsets to UTC.

When `SOCIAL_PUBLISHER=disabled`, `POST /posts` returns
`503 SOCIAL_PUBLISHING_UNAVAILABLE` before managed-upload readiness checks,
subscription/quota reads, post persistence, or queue enqueue. The mobile
preflight normally prevents the media upload too, but an old client or a race
between preflight and submit can already have uploaded an object; that orphan
must be handled by the normal temporary-media cleanup policy.

Post creation is database-first: the durable owner-scoped `QUEUED` row remains
when queue enqueue returns `503 PUBLISH_QUEUE_UNAVAILABLE`, and a retry with the
same supplied request ID repairs the queue without a second post/quota charge.
The draft now persists completed remote video/cover keys with a stable source
media fingerprint before submitting the post. A matching retry reuses them;
changing the clip or cover conflicts with an already accepted request and keeps
the draft. Pre-upgrade uncertain drafts without upload receipts cannot infer
the old media safely; check the existing post before explicitly starting anew.
Interrupted pre-submit uploads still need a verified R2 lifecycle rule.
Since 2026-10-24 the scheduler retires unfinished managed multipart sessions:
every 10 minutes it aborts the R2 upload of up to 25 sessions that expired more
than five minutes ago and marks them `ABORTED`. Completed objects that never
reached a post, and R2 multipart uploads with no session row, still rely on
that lifecycle rule. See
[`2026-10-24-upload-session-sweeper.md`](docs/superpowers/plans/2026-10-24-upload-session-sweeper.md).

Mobile bounds each ordinary JSON request to 20 seconds from authentication
refresh through connection and response-body completion. AI transcription,
prepare, planning, and caption-generation POST requests allow 120 seconds;
legacy file PUTs and each multipart part PUT allow 180 seconds. A local
`API_REQUEST_TIMEOUT` (`ApiException` status `408`) aborts a pending HTTP request
or cancels its response-body subscription. It does not prove that server work
was canceled: Mobile retains the draft and original `clientRequestId`, and does
not automatically retry `POST /posts`. These durations are injectable in tests.

#### `POST /posts/:id/publish-now`

Moves an authenticated user's still-queued scheduled post into the ready queue
without pretending that the scheduled time is the current time. The route is
owner-scoped, returns `404 SCHEDULED_POST_NOT_FOUND` when the post is missing or
no longer an editable schedule, and returns `503 PUBLISH_QUEUE_UNAVAILABLE` if
the queue replacement fails. It first clears the exact persisted schedule with
a compare-and-set, then replaces the job; failure conditionally restores the
original schedule only if no newer state has advanced. It also returns
`503 SOCIAL_PUBLISHING_UNAVAILABLE` before reading or changing the post when
social publishing is disabled.

#### `GET /queue/jobs`

Lists publish job placeholders created by `POST /posts` for the current
authenticated user.

Response:

```json
{
  "status": "ok",
  "jobs": [
    {
      "id": "mock-job-id",
      "queueName": "publish-posts",
      "postId": "mock-post-id",
      "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
      "runAt": "2026-06-02T10:00:00.000Z",
      "status": "SCHEDULED",
      "createdAt": "2026-06-01T00:00:00.000Z"
    }
  ]
}
```

#### `GET /analytics/summary?range=30d`

Returns a unified analytics summary for the 4 supported platforms. This route requires the Pro plan.
In local mock mode, use `x-postdee-subscription-plan: PRO` or call `POST /billing/mock-success` for the same mock user before requesting analytics.
Supported ranges are `today`, `7d`, `30d`, `90d`, and `year`. The response
includes platform totals plus a UTC `daily` series grouped by platform publish
date, so the mobile date filters and chart use backend data instead of sample
numbers.

- TikTok
- YouTube Shorts
- Instagram Reels
- Facebook Page Reels (existing API value: `FACEBOOK_REELS`; real-account E2E pending)

#### `GET /billing/subscription`

Returns the current authenticated user's plan status and feature flags for the mobile Home screen.

Basic response example:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "BASIC",
    "status": "INACTIVE",
    "monthlyPostLimit": 3,
    "usedPostsThisMonth": 0,
    "remainingPostsThisMonth": 0,
    "phoneVerified": false,
    "requiresPhoneVerification": true,
    "canUseFreePostQuota": false,
    "canSchedule": false,
    "canUseAiCaptions": false,
    "canUseAnalytics": false,
    "canUseAiAudioReview": false,
    "canUseAiVideoReview": false
  }
}
```

After phone verification, Basic keeps `monthlyPostLimit` at `3`, sets `remainingPostsThisMonth` from current-month usage, and sets `canUseFreePostQuota` to `true`.
Starter response sets `plan` to `STARTER`, `status` to `ACTIVE`,
`monthlyPostLimit` to `120`, enables AI captions and scheduling, and keeps
analytics locked.
Pro response sets `plan` to `PRO`, `status` to `ACTIVE`, `monthlyPostLimit` to
`250`, enables scheduling, analytics, and the higher AI caption tier.
Compatibility AI review flags may still appear for older clients, but they
remain `false` and should not be shown in package copy.

If the current-plan lookup fails, Mobile disables new purchases until a
successful reload; retry and Restore remain available. A completed store
purchase whose PostDee confirmation fails is shown as awaiting confirmation,
not as a failed purchase. Receipt verification or subscription reads can be
retried without buying again, and paid benefits require backend confirmation.
The pending receipt/read state stays in memory for the same stable signed-in
UID when the paywall is reopened. Sign-out or account changes clear it and
reject stale results. An app restart requires Restore; receipts are not
persisted locally by this cache.

#### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when `BILLING_PROVIDER=revenuecat`.
The webhook requires `Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>`.
RevenueCat `app_user_id` must match the PostDee user id, which should be the
Firebase uid in production. The backend maps RevenueCat entitlement or product
ids to Starter or Pro, then updates the configured subscription store.

Request shape:

```json
{
  "event": {
    "id": "event-id-from-revenuecat",
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "environment": "PRODUCTION",
    "store": "PLAY_STORE",
    "event_timestamp_ms": 1780444800000,
    "expiration_at_ms": 1780531200000
  }
}
```

Active purchase and renewal events activate the mapped plan. `EXPIRATION`
removes paid access. `CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE`
are acknowledged without revoking access immediately because the subscription
can still be active until the paid period actually expires. Actionable events
require `id` and `event_timestamp_ms`; the per-user cursor and subscription
change are atomic, so retries and older events cannot overwrite newer state.

Subscription webhooks and subscriber resync enforce
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT` (`PRODUCTION` by default). Production
accepts only verified App Store/Play Store purchases. Sandbox and Test Store
access requires an isolated server configured as `SANDBOX`; missing purchase
provenance cannot grant paid access. Mismatched subscription lifecycle webhooks
are acknowledged with HTTP 202 without changing access or the ordering cursor.

RevenueCat promotional grants do not unlock paid access. A fresh resync with
only promotional entitlements lacking verified purchase provenance cancels the
matching RevenueCat subscription. Use PostDee's audited admin-console trial
flow instead; an independent valid admin trial remains available.

`TRANSFER` re-reads both source and destination subscribers for existing active
PostDee users, then reconciles each through the same durable per-user cursor.
It does not grant from the transfer payload alone or create unknown users.
Provider errors or snapshots older than the transfer return a retryable error
without guessing a cancellation. See the
[Batch 1 rollout and validation plan](docs/superpowers/plans/2026-10-23-billing-security-batch1.md).

#### `POST /billing/revenuecat/resync`

Reconciles the authenticated Firebase user's subscription. Explicit mobile
Restore calls RevenueCat `restorePurchases` first; this server endpoint does not
require SDK Restore. The backend reads the RevenueCat subscriber
with the server-only `REVENUECAT_REST_API_V1_KEY`, prefers Pro when both paid
entitlements are active, and updates the configured subscription store. If
RevenueCat has no active entitlement, only the matching RevenueCat-backed local
subscription is deactivated. An active but unmapped entitlement returns a safe
configuration error without removing existing access.
Clients must not send or choose another RevenueCat app user id; the route always
uses the authenticated PostDee user id.

In the implemented AI preflight, only a successful initial subscription GET
denying AI access, with RevenueCat enabled, triggers one
authenticated server resync per Generate action, then a fresh subscription GET.
That second GET is authoritative; the resync reply's plan is ignored. Paid users,
disabled RevenueCat and a failed initial GET do not trigger extra resync calls.
Failures keep the paid gate closed and show a Thai rights-verification error;
the user can retry manually. This adds no SDK Restore, purchase or free grant,
and keeps owner/source guards, Pro frames, Starter mode and quota unchanged.
Automated checks pass; the exact-source Staging APK is built and installed.
Native Free/denied gating and button usability pass. Live HTTP sequencing and
active-paid reconciliation/generation remain unverified, as recorded in the
audit plan.

Subsequent authorized Staging delivery on 2026-10-09 pushed source `c8e463d`
on the audit branch. Exact-source CI `37918977276` passed both jobs, and Render
deploy `dep-db4ccku0tbcc73dtlasg` is Live. The installed `24266aa` APK has the
same runtime; the intervening changes are documentation only. This delivery
keeps the paid AI/HTTP-trace limits above and leaves `main` and Production
unchanged. The chronological delivery receipt is in the audit plan.

The subscriber response's `request_date_ms` and webhook `event_timestamp_ms`
share one per-user serializable ordering cursor. Older or equal snapshots/events
are acknowledged without overwriting newer state. If `request_date_ms` is
absent, local API receipt time is used; synchronized server clocks are required
because skew can temporarily suppress a legitimate webhook as apparently old.

This route is not operational in an environment until the current backend is
deployed and its RevenueCat REST API v1 secret is configured. Provider failures
return an error without downgrading the existing plan.

#### `POST /billing/store/verify`

Legacy direct Apple/Google store verification scaffold. It can verify a Starter
or Pro subscription purchase from the mobile store flow and activates the
matching plan for the authenticated user based on `productId`. In
`BILLING_PROVIDER=mock`, `provider` is `mock-store`. In `BILLING_PROVIDER=store`,
Android purchases use Google Play verification when Google credentials are
configured, and iOS purchases use App Store Server API verification with Apple
signed transaction verification when Apple credentials and root certificates are
configured. Production billing should use RevenueCat instead of this custom
store verifier.

Request:

```json
{
  "platform": "ANDROID",
  "productId": "postdee_pro_monthly",
  "purchaseToken": "google-play-purchase-token"
}
```

Use `productId: "postdee_starter_monthly"` for Starter 199 THB/month and `productId: "postdee_pro_monthly"` for Pro 299 THB/month. For iOS, send `platform: "IOS"` with `transactionId`. When the App Store verifier decodes `originalTransactionId`, the backend uses it as the durable Apple billing id so renewal notifications can match the same subscription even when later transaction ids change.

Response includes the verified store purchase metadata and the activated subscription:

```json
{
  "status": "ok",
  "purchase": {
    "provider": "mock-store",
    "platform": "ANDROID",
    "productId": "postdee_pro_monthly",
    "verifiedAt": "2026-06-04T00:00:00.000Z"
  },
  "subscription": {
    "userId": "local-dev-user",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

#### `POST /billing/mock-success`

Activates the Starter or Pro plan for the authenticated mock user. This endpoint exists only for local scaffold testing before real Apple/Google store receipt verification is connected.
It is disabled when `NODE_ENV=production` or when real store billing mode is enabled.
Startup also rejects `BILLING_PROVIDER=mock` when `NODE_ENV=production`.

Request:

```json
{
  "plan": "STARTER"
}
```

#### `POST /billing/google-play/notifications`

Receives Google Play Real-time Developer Notifications through a Pub/Sub push payload. The endpoint requires `Authorization: Bearer <GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN>`, decodes the Pub/Sub `message.data`, supports subscription, test, and voided purchase notifications, maps clear subscription events to local entitlement status, and returns an acknowledgement. It updates only subscriptions that were previously bound through `POST /billing/store/verify`.

Current Google status mapping:

- `1`, `2`, `4`, `6`, `7` -> `ACTIVE`
- `5` -> `PAST_DUE`
- `12`, `13`, `20` -> `CANCELED`
- `voidedPurchaseNotification` with `productType: 1` -> `CANCELED`
- `3` is intentionally ignored because user cancellation can still leave entitlement active until the paid period ends.

#### `POST /billing/apple/notifications`

Receives App Store Server Notification V2 payloads. The scaffold requires `signedPayload` verification through Apple `SignedDataVerifier` or an injected test decoder, extracts the decoded transaction id and original transaction id when available, maps clear subscription events to local entitlement status, and returns an acknowledgement. It updates only subscriptions that were previously bound through `POST /billing/store/verify`.

Current Apple status mapping:

- `SUBSCRIBED`, `DID_RENEW`, `DID_RECOVER`, `REFUND_REVERSED` -> `ACTIVE`
- `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD` -> `ACTIVE`
- `DID_FAIL_TO_RENEW` without subtype `GRACE_PERIOD` -> `PAST_DUE`
- `EXPIRED`, `REFUND`, `REVOKE`, `GRACE_PERIOD_EXPIRED` -> `CANCELED`

Response includes the parsed notification event and `status: "ok"` after the handler finishes.

## Mobile

Path: `apps/mobile`

Current mobile pieces:

- Light and dark Flutter themes (light is the current default)
- Generated Android and iOS platform folders with app display name `PostDee`
- Home dashboard with a compact current-plan row, an owner-local saved-draft or
  new-post action, supported-channel connection summary, the earliest future
  queued post, recent posts and the server-confirmed store-link state. Load
  failures stay distinct from empty states; the monthly views/likes cards remain
  removed. Local revision verification is tracked in
  `docs/superpowers/plans/2026-10-11-home-ux.md`.
- Full-screen create-post flow with four steps: choose clip, write caption,
  choose connected destinations, then review/send now or schedule. Step headers
  show the current step out of four, and the primary Next action names its
  destination. Previous steps show a check only when their input is ready;
  progress buttons remain optional shortcuts. It uses a
  small local poster that opens a full-screen local video player on tap, a large
  caption field, manually requested AI help, and collapsed caption templates
  and additional tools. Back/edit actions retain the current form. Save draft
  stays explicit; closing a changed form offers continue editing, discard, or
  save and exit. The fourth step combines scheduling and the shared review
  summary with one publish confirmation, without a second review route.
  9:16 validation, future schedules capped at 14 days for Starter or 30 days for
  Pro, explicit account selection,
  package/phone gates and required per-platform settings are preserved. A
  functional cover editor lets a seller scrub to a source-video frame, add Thai
  text, choose Prompt or Anuphan, adjust weight, size, colors, and position, then
  review the cover before posting. Mobile renders a 1080x1920 JPEG; Instagram
  and Facebook receive the image, TikTok receives the frame time, and YouTube
  Shorts leaves final cover selection to the YouTube mobile app. The compact
  tool area still exposes only `ตัดคลิปเป็น EP`; the removed manual editor,
  automatic-watermark, and advanced-mode cards must not return.
  The shell does not create a hidden uploader or load its connections before
  the composer is opened. Calendar uses the same full-screen entry; closing it
  keeps the previous calendar state. This mobile-only revision adds no API,
  schema, provider, pricing, entitlement or environment change, and needs no
  database migration. Final whole-suite/build/device verification is tracked
  in `docs/superpowers/plans/2026-06-06-mobile-ui-refresh.md`.
- Publish drafts are copied into per-stable-UID Application Support storage with
  their video, optional cover, caption/settings, selected destinations, and
  optional schedule. Saving locally does not call publishing readiness, upload,
  post, provider, queue, or quota paths. Drafts do not sync across devices and
  may be included in OS backup. After an active draft is accepted into the post
  queue, Mobile deletes its local copy; a failure before queue acceptance
  retains it, and a local cleanup failure is reported rather than hidden. This source-level path
  still needs real-device save/restore/storage/backup verification.
- The pre-publish review shows the requested per-platform outcome and connected
  account/channel/page before confirm: TikTok inbox draft, the completed YouTube
  visibility/compliance choice, Instagram share-to-feed, and Facebook Page Reels
  publish/page-draft. A missing account identity, incomplete setting, or unknown
  outcome blocks confirmation and asks the seller to refresh/reconnect or fix the
  setting. Scheduled-post detail uses the dedicated authenticated
  `POST /posts/:id/publish-now` command.
- The result screen reports the server lifecycle truth: `QUEUED` means accepted
  into the queue, `PUBLISHING` means still sending, `PUBLISHED` means every
  requested delivery was confirmed (which may be private or a provider draft),
  and `PARTIAL_PUBLISHED` means only some destinations succeeded. An
  unrecognized status is not shown as success and the local draft is retained;
  an idempotent replay is labelled as the existing item.
- A failed connection-status lookup is shown as unknown, never as
  zero connected accounts or a confirmed disconnect; connection actions stay
  disabled until status is successfully refreshed.
- Social account authorization opens the PostPeer URL in a browser-owned
  surface, never a Flutter WebView. Android uses a dedicated native Custom Tab
  bridge with external-browser fallback. New Android connect requests use the
  fixed `android` or `android-staging` return target. A native return preserves
  the original screen while the app process is alive, then triggers one
  authenticated `POST /social-connections/refresh`; the return itself does not
  prove that connection succeeded. A cold start uses the normal authentication
  gate and cannot restore a previous screen that existed only in memory.
  Browsers may require an Open App confirmation. Closing with X and manual
  refresh remain available; iOS keeps the legacy external-browser flow without
  an automatic-return claim. The fixed-target API is Live on Staging; other
  environments must deploy API before mobile. Create a new connect link to use
  the return target; links already open retain their prior flow.
  No new permission, provider OAuth app, database schema or environment setting
  is required. An injected VIEW URI verified warm return to the original
  Connections screen on the installed Staging APK. Real provider/browser
  handoff, Open App confirmation and cold callback remain unverified.
- Calendar tab that refreshes when opened, polls queued/publishing posts while
  visible, uses the real publish time, and opens completed results read-only;
  plus AI caption entry points from Upload after a clip is selected
- Mobile API client and Upload UI call `POST /captions/generate-from-clip` for
  the new real-clip caption scaffold after a clip is selected.
- Pro AI editing backend exposes `POST /ai-edits/prepare`, which turns the
  selected clip, UI capability toggles, style/prompt, and settings into a
  mobile FFmpeg render recipe. It meters the same 200 monthly AI editing minutes
  as transcription only after the requested edit plan and recipe succeed; a
  failed planner/recipe retry does not consume quota. The final atomic
  reservation still enforces the monthly limit. It does not render video
  server-side. ElevenLabs transcription returns timed words, segments, and
  non-speech audio-event tags without a free-form spelling prompt. Optional segment confidence/no-speech/compression
  signals are retained for highlight quality checks and to omit unreliable ranges
  or clearly unexpected mixed-script recognition noise from burned subtitle
  lines. Normal Latin product/place names remain allowed. The backend validates the
  complete provider timing timeline before using it for subtitles, planning,
  repeated-speech cleanup, or silence candidates. A malformed, missing,
  overlapping, backwards, clipped, or out-of-range timed event fails closed for
  editing; a partial display subset may still be retained for diagnostics but is
  never treated as safe cut evidence.
- The AI editing setup starts every optional capability switch off. The seller
  can explicitly enable subtitles, silence cleanup, repeated-speech cleanup, or
  `AI ใส่เอฟเฟกต์เสียงให้`; leaving all switches off still permits base
  target-length shortening. The seller-facing colour/light and audio-cleanup
  cards remain hidden while their internal contracts stay compatible with older
  results. SFX is an AI analysis path, not a manual sound editor: the provider
  may return only an allowlisted PostDee `soundId` and trusted source timestamp,
  while mobile fixes volume at 25%, maps each surviving anchor through the final
  cut timeline, and reuses the same recipe for preview and full export. The app
  contains no seller-facing sound picker, placement slider, or manual SFX Studio.
  Provider/timing/parse failure keeps the clip unchanged and does not meter an
  unavailable-only request; a completed analysis, including a valid empty
  selection, uses the normal AI-edit minute policy. Real-device listening and
  A/V-sync acceptance remain required before Production.
- For the production capability set, mobile extracts mono 16 kHz AAC at 64 kbps
  into balanced temporary `.m4a` chunks no longer than 30 seconds, uploads them
  with `purpose=ai-edit-audio`, and sends ordered `audioChunks` to the backend.
  This keeps the whole source timeline while avoiding a tiny final chunk and
  long-form leading-speech omissions. The backend transcribes each chunk,
  restores source-relative timestamps, and merges one transcript only when no
  timed item had to be clipped or dropped at a chunk boundary. Any such timing
  damage marks the combined result untrusted so planning stops safely instead
  of cutting from a repaired-looking subset. A successful metered prepare
  reserves usage at most once for the combined request. The original video
  stays on the phone for FFmpeg
  rendering. Local and remote temporary audio are cleaned best-effort after the
  prepare call; legacy single `audioS3Key` and `videoS3Key` clients remain
  compatible.
- When the requested result is shorter than the source transcript, mobile also
  creates a temporary whole-duration 360 px MP4 visual proxy at 1 fps with its
  complete audio track. It uploads that bounded proxy with
  `purpose=ai-edit-visual-proxy`; `POST /ai-edits/plan` sends the proxy through
  Gemini Files API together with timestamped Thai transcript segments. Gemini
  selects the story window after seeing the entire proxy, while the full-quality
  source never leaves the phone for rendering. If visual analysis is unavailable,
  the existing audio/transcript plan remains the safe fallback. Mobile reuses
  the local proxy when only the target duration changes, then deletes it when
  the source is replaced, removed, or the editing screen closes. R2 and Gemini
  temporary files are cleaned best-effort after each planning request. Gemini
  file upload, processing-state polling, and deletion use Google's official
  `@google/genai` server SDK so the app does not maintain a fragile resumable
  upload protocol itself.
- The full source duration is sent as `durationSeconds` for quota pre-check,
  planning, and recipe timeline recovery. The backend uses the longer valid
  value between that client-reported media duration and the provider transcript
  duration. This recovers trailing video/silence when the official app reports
  native FFprobe duration. A server-side media-duration probe and API-side
  10-minute limit remain release blockers before public billing can treat the
  value as tamper-resistant.
  Current mobile accepts source clips up to 10 minutes. After selection, one
  duration slider requests from 5 seconds up to 3 minutes (or from 1 second for
  a source shorter than 5 seconds), capped by the source length. Its rightmost
  stop means “keep original” and omits `targetDurationSeconds`, so provider
  timing drift cannot trim the final fraction of the clip or trigger an
  unnecessary visual proxy. The edit
  planner excludes known prompt leakage and low-quality segments, then uses
  transcript selling signals (hook, benefit, proof, offer, and CTA) to choose one
  continuous story window. Thai continuation fragments such as `แต่`, `แล้ว`,
  `โดย`, `ซึ่ง`, and `ของมาจาก` receive a soft opening penalty when a complete
  nearby sentence is available; the local duration cap remains a
  safety guard for old or malformed recipes. If incomplete transcript/silence
  timing would leave less media than requested, mobile restores neighboring
  context around the selected moments so a slider-selected request does not
  collapse into a near-empty result. The recipe carries repaired
  `transcript.boundarySegments` separately from visible
  `subtitles.segments`. Mobile uses only those strict transcript boundaries for
  opening/tail alignment, including when the subtitle capability is off, while
  the renderer still receives no subtitle overlay. If the field is missing or
  its evidence is unavailable, mobile keeps the planner story-window cut,
  displays a boundary-evidence warning, and never guesses from raw provider
  segments. If a leading target-length cut intersects a repaired transcript
  boundary cue, mobile moves the cut just before that cue and balances the
  result at the tail, preventing the shortened clip from opening mid-sentence.
  The 0.15-second pre-roll is used only when that time is a real subtitle-free
  gap. If the target would end on a dangling Thai connector such as `ก็`, mobile
  keeps the opening/Hook and internal AI cuts unchanged, then moves only the
  trailing boundary to the first nearby complete phrase. The semantic allowance
  is 10% of the selected target, bounded to 1–3 seconds; if no complete phrase
  fits, the dangling cue is removed instead. The renderer uses the same limit,
  and this does not enable or duplicate the separate three-second hook feature.
- After the first successful metered prepare, changing only the duration slider
  reuses the same in-memory transcript and calls non-metered
  `POST /ai-edits/plan`.
  Audio is not uploaded or transcribed again unless the source or analysis
  settings change.
- When automatic subtitles are available, mobile first renders a lightweight
  result and opens result review. Subtitle Studio opens only from the explicit
  “edit subtitles” review action. The user can edit text and
  timing, add/delete/split/merge cues, undo/redo, and change the bundled
  Bai Jamjuree/Prompt/Anuphan font, size, text colour, outline, shadow, and the
  free subtitle position while the Flutter preview updates immediately. The
  setup screen shows a paused real frame from the selected clip, lets the seller
  scrub to another frame, and lets them drag the subtitle directly. The chosen
  preview frame is local-only: it is not uploaded and is not used as a cover.
  Subtitle cues use one line in both new and restored drafts; legacy two-line
  draft styles are migrated to one line when loaded.
  Draft JSON is autosaved in app-owned storage and reopening the same source
  and AI setup restores it. These local edits and retries do not call a metered
  AI endpoint.
- Thai subtitle preparation rejects unsafe character-fragment timing and keeps
  the API's readable Thai cue boundaries instead of splitting an unspaced phrase.
  The API expands provider fragments to semantic Thai words and enforces a final
  safety ceiling of five words and 20 graphemes for multi-token cues. An
  indivisible brand name, URL, or other single token may exceed 20 graphemes so
  it is not cut in half; it is isolated from neighboring tokens and mobile
  measures its real width before shrinking the font for preview/export.
  The setup choices now state the real density contract: karaoke is at most one
  word, readable is at most three words, and complete is at most five words.
  One metered prepare response can include all three cue variants from the same
  transcript, so changing only 1/3/5, colour, outline, or position in the current
  editing session does not transcribe the clip or reserve minutes again. Preview
  and export use the same one-line ASS coordinate contract; an overlong manual
  cue is rejected with a correction message instead of being silently clipped.
- Transcription-provider failures return structured HTTP 502
  `AI_TRANSCRIPTION_PROVIDER_FAILED` without consuming AI-edit quota or exposing
  provider details; the mobile screen translates this into a retryable Thai error.
- After the first phone-side render, the mobile app stays on the AI editing
  screen so the user can preview the result, remove supported AI edits they do
  not want, or add them back. Each review checkbox automatically re-renders a
  new preview from the original clip without another metered prepare call while
  keeping the last successful preview safe on failure. The accepted result can
  then go directly to Upload/Post or open in the manual editor for further changes.
- AI review uses a disposable lightweight preview: sources longer than 60 seconds
  render at up to 540p/20 fps/1 Mbps, while shorter sources use up to
  720p/24 fps/2 Mbps. FFmpeg writes real processed-time progress for the UI,
  and mobile accepts FFmpeg's own `progress=end` marker when an Android
  completion callback is lost. The output must still contain a real video
  stream. At 99%, the UI says that it is verifying the video instead of leaving
  users with what looks like a frozen progress screen. A Pro entitlement
  preflight releases the screen after 30 seconds instead of locking the editor.
  FFmpeg startup with no processed-time, terminal session, or exact
  `progress=end` signal times out after 30 seconds for preview and 90 seconds
  for full export. Renders can be cancelled or retried, and identical local
  results are reused.
  Choosing Post creates a separate full-source-dimension export before opening
  Upload/Post, so the lightweight preview is never published.
- The AI editing header loads `GET /ai-edits/quota` and shows the authenticated
  user's exact remaining and used Pro minutes. It updates immediately from the
  metered `prepare` response and can be tapped to refresh without consuming a
  minute.
- `POST /ai-edits/prepare` reserves minutes only when at least one requested AI
  outcome is usable. Repeat or silence analysis with unsafe timing does not
  consume minutes when no other requested analysis succeeds. A safe silence
  analysis still counts when it completes but finds no gap. Explicit empty or
  colour-only capability requests stop before transcription. After the local
  Pro entitlement check, the official mobile client handles colour-only edits
  that keep the original duration with a cut-free full-duration recipe on the
  phone: it does not extract audio, upload media, call `prepare`, or change the
  minute balance. Colour plus a shortened target, subtitles, silence cleanup,
  or repeated-speech cleanup stays on the normal audio/API route. Any unknown
  enabled capability fails closed before those side effects. Legacy clients
  that omit the capability field keep their previous metered behaviour.
- Android subtitle export gives libass the selected bundled Thai-safe
  Bai Jamjuree, Prompt, or Anuphan font explicitly and maps the selected colour,
  active-word colour, fade/pop effect, outline, shadow, and safe alignment into
  the final MP4. Validated complete word timing uses escaped ASS active-word
  events; missing, incomplete, edited, or unsafe timing falls back to readable
  static SRT without inventing word timing. Subtitles are burned against the
  original source timeline before kept ranges are compacted, so a diagnostic
  SRT can legitimately end later than the shortened MP4; cues inside removed
  ranges do not appear in the final video. The output name ends in
  `_subtitled.mp4` only when real subtitle content is rendered; otherwise it
  ends in `_edited.mp4`.
  Silence removal compacts kept audio ranges with
  `atrim` + `concat` so the audio ends with the shortened video instead of
  continuing after the final frame.
- Pace cleanup settings are real recipe inputs. `silencePreset` maps to internal
  gaps in a complete validated word timeline, or a complete reliable segment
  timeline when safe word evidence is unavailable, with thresholds of `natural`
  = 1.0 s, `balanced` = 0.6 s (the default), and `compact` = 0.4 s. Leading and
  trailing gaps are not candidates. Mobile treats those gaps as non-executable
  candidates until its waveform verifier succeeds; only verified intersections
  enter the final cut list. Successful verification, including an empty result,
  is cached for the exact source and timing evidence. Failed verification is not
  cached so the user can retry locally.
  The setup offers `AI เลือกให้` (default) and `เลือกเอง`. Both choices send
  `speechReductionMode: "auto"` so one analysis can report repeated
  Thai words or phrases with stable occurrence IDs and source timing. Only
  adjacent repeats within 0.35 seconds are selected for removal by default;
  the last occurrence is retained. A word used three or more times in separate
  sentences is shown for awareness but kept, because removing a product name or
  important subject could damage meaning. Thai provider fragments are usable
  only when they reconstruct one exact NFC-normalized semantic word in raw
  provider order, inside one reliable segment, with no internal gap above 0.15
  seconds. This evidence is used only for repeated-speech detection and does not
  replace subtitle word timing. Negation, `ๆ`, numbers/prices, fragments that
  cannot be proven exact, timed audio events, and unsafe timing fail closed. AI
  mode starts with those recommendations selected; manual mode starts with none selected. The review
  then lets the user keep or remove each safe occurrence before re-rendering.
  `fillerWords` and `fillerRanges` remain as a legacy-client compatibility path;
  the current setup no longer displays a fixed filler-word chip list, and
  manual mode never applies legacy filler ranges automatically.
- Mobile keeps the setup's pending source separate from the accepted source used
  by review, Subtitle Studio, retry, and export. Source, duration, recipe,
  verified silence, subtitle project, selected repeat occurrences, and rendered
  result become active together only after a render succeeds. A failed render
  for a newly selected clip therefore leaves the previous result intact. The
  same rule covers local colour retry: retry repeats only the phone-side render,
  while a failed source B attempt cannot replace the accepted source A state.
- Build-time rollback flags can disable verified-silence cuts and automatic
  repeat cuts independently. With repeat cutting disabled, detected groups stay
  visible as read-only information, all selected occurrence IDs are empty, and
  every render/export path keeps the speech. Other selected capabilities are
  unchanged.
- Result review shows detected silence and repeated-speech groups, the number
  of selected safe occurrences, and their combined detected time. These are pre-render
  detections, not a promise that the exported clip saves exactly that duration.
  Mobile fits the AI story plan to the requested length before applying these
  cleanup ranges, so duration restoration cannot put removed silence or repeated speech
  audio back; the final export may therefore be slightly shorter than requested.
  When subtitles are enabled, the selected word is also removed from its
  source-timeline cue before burn-in. If that word cannot be mapped safely, the
  media cut is rejected too so subtitle text and speech never disagree.
- Production exposes only seller-selectable AI editing capabilities with a real
  mobile path: subtitle, silence, repeated-speech cleanup, and AI-selected sound
  effects. The existing color/light renderer remains compatibility-tested
  internal support, but its setup card and the audio-cleanup card are hidden.
  Auto-reframe, zoom, translation, price tags, CTA cards, and the AI-page
  watermark remain locked as `เร็ว ๆ นี้`. AI SFX uses ten procedural WAV
  assets with recorded hashes; the model selects only an allowlisted ID and
  trusted timestamp, while mobile owns volume, cut-timeline mapping, and local
  rendering. No manual sound-effect UI remains.
- Beat-sync advanced settings now let the user keep the original audio or pick
  an owned MP3/M4A/WAV file through Flutter's `file_selector`, confirm usage rights, choose
  cut intensity, music volume, and voice ducking, and send those choices in the
  prepare recipe. The licensed PostDee catalog and the real beat-analysis/music
  mixing renderer are still pending, so the UI does not claim beat sync was
  applied to the exported clip yet. Catalog tracks remain unavailable until
  their license explicitly covers all six PostDee publishing destinations.
- Production keeps beat sync locked off with a `เร็ว ๆ นี้` state through the
  compile-time `ENABLE_EXPERIMENTAL_BEAT_SYNC` flag, whose default is `false`.
  Internal QA may set it to `true` to inspect the setup-only UI; the flag does
  not enable beat analysis, music mixing, ducking, or any other renderer work.
- Production also keeps the 3-second hook/highlight capability locked as
  `เร็ว ๆ นี้` through default-false `ENABLE_EXPERIMENTAL_AI_HOOK`. An internal
  QA build may expose the control, but the API still marks it `planned` and the
  mobile renderer does not reorder the opening timeline.
- AI editing advanced settings use an accordion so only one capability section
  is expanded at a time. No section is expanded by default.
- Legacy AI Clip Review UI, `/clip-reviews` route, config, and internal
  mock/provider code have been removed from the active app path.
- Saved templates wired to `GET /templates` and `POST /templates`
- Unified analytics wired to `GET /analytics/summary?range=...`, including real
  range selection and a publish-date daily chart without simulated numbers.
  The fourth bottom-navigation slot opens the internal link manager; analytics
  remains available from publish results and individual post details.
- Home plan status refresh wired to `GET /billing/subscription`; Basic Phone OTP
  UI unlocks the 3-post free quota. Home refreshes the plan after returning from
  the paywall without requesting analytics.
- Upload AI captions keep the customer flow simple: select a clip, optionally add guidance, then let AI infer language and market from the clip.
- Starter and Pro CTAs on Home can use the legacy Flutter `in_app_purchase`
  scaffold by default, or the RevenueCat `purchases_flutter` path when
  `ENABLE_REVENUECAT_BILLING=true`; purchases are confirmed through
  `POST /billing/revenuecat/webhooks`, while user-initiated Restore runs the SDK
  restore then `POST /billing/revenuecat/resync`

Local API config can be passed with Dart defines:

```powershell
flutter run --dart-define=API_BASE_URL=http://localhost:4000 --dart-define=POSTDEE_MOCK_USER_ID=local-dev-user
```

Use `STORE_STARTER_MONTHLY_PRODUCT_ID=postdee_starter_monthly` and `STORE_PRO_MONTHLY_PRODUCT_ID=postdee_pro_monthly` when testing non-default store subscription product ids.
Use `POSTDEE_MOCK_SUBSCRIPTION_PLAN=STARTER` or `PRO` when testing scheduled posts against the mock backend.
For local RevenueCat Test Store billing, keep the public `test_` SDK key in the
ignored `apps/mobile/revenuecat.local.json`, then run
`powershell.exe -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command run`
from `apps/mobile`. The helper validates and supplies both the Staging base
defines and Test Store overlay, including when invoked from a Git worktree. It
fails closed when the overlay is missing or contains a non-Test-Store key or a
server secret. Never use that overlay for App Store or Google Play release
builds.
For internal beat-sync UI QA only, add `--dart-define=ENABLE_EXPERIMENTAL_BEAT_SYNC=true`. Keep this define absent or `false` in production builds until the renderer is implemented and verified.
For internal hook UI QA only, add `--dart-define=ENABLE_EXPERIMENTAL_AI_HOOK=true`. Keep it absent or `false` in production; this flag does not add highlight analysis or timeline rendering.

A local Flutter SDK is available at `.tools/flutter` for this workspace and is ignored by Git. If you do not add Flutter to the system `PATH`, run mobile checks through the local SDK:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
```

Android build/run still requires Android Studio and the Android SDK. Production iOS build/run requires Xcode on macOS.

If platform folders ever need to be regenerated:

```powershell
cd apps/mobile
..\..\.tools\flutter\bin\flutter.bat create --platforms=android,ios .
```

## Required Environment Variables

Copy `apps/api/.env.example` to `apps/api/.env` and replace the placeholder values before connecting real services.

Required services for later milestones:

- PostgreSQL for app data
- Redis for BullMQ scheduling
- Cloudflare R2 for temporary video storage
- Firebase Auth for Google Sign-In and Phone OTP verification
- Gemini API for Thai caption generation
- PostPeer for real TikTok, YouTube Shorts, Instagram Reels, and Facebook Page
  Reels publishing (`FACEBOOK_REELS` always sets `contentType: 'reel'`, with no
  Page feed fallback; real-account E2E is still required)
- RevenueCat subscriptions for Starter and Pro, backed by Apple App Store and Google Play products

The post/caption add-on is a separate, repeatable consumable purchase: target
price 49 THB for 100 additional post units and 50 additional real-clip caption
credits. Native Android and iPhone use the same non-expiring purchased
credit policy. Only effective Starter/Pro members can buy/use it. Included
monthly quota is consumed first; purchased credits cover only the remainder
and carry over across monthly resets. A post to two destinations uses two
units. AI caption generation costs one credit per selected channel, or one for
a shared-caption request. Purchased balances remain stored during a downgrade
to Basic and become usable again with Starter/Pro. Existing tier features and subscription prices
do not change. The app displays the store's actual localized checkout price.

Purchases stay disabled by default (`BILLING_ADDONS_ENABLED=false`) until the
add-on migration/API, RevenueCat webhook verification, and the matching
consumable store products are ready. This gate controls new sales, not access
to existing purchased balances for paid members. Server-verified transactions
grant once; subscription Restore is not a second grant. See the
[non-expiring credit implementation and rollout record](docs/superpowers/plans/2026-10-21-nonexpiring-post-caption-credits.md).
Native purchase/refund acceptance on both stores remains required before sale;
the shared non-expiring policy does not imply store review approval.

See `FIREBASE_SETUP.md` for the Firebase Auth and Google Sign-In setup checklist.

Production account deletion is temporarily disabled with
`FIREBASE_AUTH_DELETE_ENABLED=false`; the shared drain is delivered to Staging,
while Production rollout and real-provider acceptance remain pending. In a
controlled environment, enabling the path also requires
`FIREBASE_SERVICE_ACCOUNT_JSON`. When enabled, `DELETE /account` disconnects
the user's PostPeer integrations, removes
the R2 owner prefix (or an S3-compatible client that implements owner-prefix
listing), deletes local data, and deletes the Firebase identity last. Active
Firebase users starting deletion must present a finite `auth_time` within five
minutes, with no more than 60 seconds of future clock skew, while the Firebase
identity still exists. The API atomically marks the owner `DELETING` and records
the server time in `ManagedUploadOwner.deletionAuthorizedAt` before cleanup.
This owner record is separate from `User` so the proof survives data deletion.
A dedicated account-only retry path accepts a still-valid token for the same
UID, including an older token or an already-missing Firebase identity, only
when a valid stored proof exists on a `DELETING` or `DELETED` owner. Revoked
tokens remain rejected. Missing identity alone, a lifecycle marker alone, and
legacy `NULL` proof never authorize deletion. If proof storage is unavailable
or cannot be read/written, the API fails closed with
`503 ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE` before cleanup or a local
deleting mark. Authorization is rechecked under the owner lock before cleanup.
RevenueCat webhooks do
not recreate users that no longer exist. PostPeer cleanup follows every page of
the profile's integrations and fails before local deletion when provider cleanup
is unavailable or any external disconnect fails. A durable marker protects the
managed-upload owner prefix before queue/provider cleanup. In the Prisma-backed
implementation delivered to Staging, `ManagedOwnerOperation` records span
admitted HTTP handler/finally work, managed uploads, queue admission and worker
execution across upgraded
Prisma-backed processes. Admission and sealing share the owner row lock;
remote I/O runs outside SQL transactions. Deletion waits for these records and
claims `ManagedOwnerDeletionRun` before cleanup. Crashes, ambiguous outcomes
and release failures block cleanup until verified reconciliation, without TTL
expiry. Memory-only coordination remains process-local. Keep the Production
feature disabled until the migration/all-process rollout, real Redis/provider,
legacy upload/OAuth and device/slow-network gates pass.

Queue/storage scaffold switches:

- `TEMPLATE_STORE=memory` keeps saved templates in memory; `TEMPLATE_STORE=prisma` uses PostgreSQL through Prisma.
- `POST_STORE=memory` keeps posts in memory; `POST_STORE=prisma` uses PostgreSQL through Prisma and upserts the current auth user before creating posts.
- `SUBSCRIPTION_STORE=memory` reads mock subscription headers and local mock billing activations; `SUBSCRIPTION_STORE=prisma` reads and upserts active subscriptions through PostgreSQL.
- `BILLING_PROVIDER=mock` keeps the local billing scaffold; `BILLING_PROVIDER=store` keeps the legacy direct Apple/Google verifier; `BILLING_PROVIDER=revenuecat` receives RevenueCat webhooks and is the production billing path.
- `REVENUECAT_WEBHOOK_AUTH_TOKEN` is required when `BILLING_PROVIDER=revenuecat` in production.
- `REVENUECAT_REST_API_V1_KEY` is a server-only RevenueCat secret used by the
  authenticated restore/resync route and TRANSFER reconciliation. Never put it in Flutter or commit it.
- `REVENUECAT_SUBSCRIPTION_ENVIRONMENT=PRODUCTION|SANDBOX` isolates Starter/Pro
  purchases. The production Blueprint pins `PRODUCTION`; Staging pins `SANDBOX`.
  Configure the environment before rolling out the API. No mobile or schema
  migration is required. `REVENUECAT_ADDON_ENVIRONMENT` remains independent;
  `TEST_STORE` is accepted only when that purchase environment is `SANDBOX`.
- `REVENUECAT_STARTER_ENTITLEMENT_ID` and `REVENUECAT_PRO_ENTITLEMENT_ID` map RevenueCat entitlements to PostDee plans.
- `REVENUECAT_STARTER_PRODUCT_ID` and `REVENUECAT_PRO_PRODUCT_ID` map RevenueCat products to PostDee plans when entitlement ids are not present in the webhook.
- `GOOGLE_PLAY_PACKAGE_NAME` is the Android package name registered in Google Play Console.
- `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON` is the preferred production credential source for Android Publisher API OAuth.
- `GOOGLE_PLAY_ACCESS_TOKEN` is a temporary scaffold access token fallback for Android Publisher API calls.
- `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` is required by the Google Play Real-time Developer Notifications endpoint.
- `APPLE_APP_BUNDLE_ID` is the iOS bundle id registered in App Store Connect.
- `APPLE_APP_STORE_ISSUER_ID`, `APPLE_APP_STORE_KEY_ID`, and `APPLE_APP_STORE_PRIVATE_KEY` are used to sign App Store Server API JWTs.
- `APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64` is a comma-separated list of DER root certificates encoded as base64 for Apple's signed transaction verifier.
- `APPLE_APP_APPLE_ID` is the numeric App Store app id. It is optional for sandbox but should be set for production verification.
- `APPLE_APP_STORE_ENVIRONMENT=sandbox|production` selects the App Store Server API base URL. Keep sandbox for development.
- `ANALYTICS_STORE=memory` returns in-memory analytics metrics; `ANALYTICS_STORE=prisma` reads platform publish metrics from PostgreSQL through Prisma and lets the publish worker record platform results.
- `CAPTION_USAGE_STORE=memory` keeps real-clip AI caption usage in memory;
  `CAPTION_USAGE_STORE=prisma` persists monthly usage in PostgreSQL through
  Prisma.
- `PUBLISH_QUEUE=memory` keeps publish jobs in memory; `PUBLISH_QUEUE=bullmq`
  uses Redis/BullMQ. Create commits the durable post before enqueue; a queue
  failure returns `503 PUBLISH_QUEUE_UNAVAILABLE` and a same-key replay repairs
  the job. Reschedule/publish-now update the post first and use a conditional
  rollback if queue replacement fails.
- `PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` so the API and separate worker process share the same post records.
- Publish workers claim only `QUEUED` posts before calling a publisher. Duplicate
  retry jobs for posts already `PUBLISHING`, `PUBLISHED`,
  `PARTIAL_PUBLISHED`, or `FAILED` are skipped. Scheduled jobs whose `runAt`
  no longer matches the post's current `scheduledAt` are also skipped.
- Provider publishing retries are bounded and run only for an explicitly safe
  pre-accept failure. Network/timeouts or a PostPeer result that cannot be
  confirmed are not submitted again; the user must check the destination first.
- `SOCIAL_PUBLISHER=mock` returns fake success only in local development;
  `SOCIAL_PUBLISHER=disabled` fails closed without contacting a platform and is
  the initial Staging setting. It also makes publishing readiness, post create,
  post reschedule, and publish-now fail with
  `503 SOCIAL_PUBLISHING_UNAVAILABLE`, while cancel remains available.
  `SOCIAL_PUBLISHER=postpeer` calls PostPeer and requires `POSTPEER_API_KEY` plus
  `VIDEO_STORAGE=r2|s3`.
- `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG=true` is an opt-in activation guard for
  the single-process `PUBLISH_QUEUE=memory` scheduler. Before a real PostPeer
  process starts its scheduler or listens for traffic, it runs one atomic
  global aggregate count with status in `QUEUED` or `PUBLISHING`; future
  schedules are therefore included. A non-zero total or inspection error blocks startup
  without loading post/user/media details. Staging enables this guard; its
  default is `false`, and the Production Blueprint is unchanged.
- Each memory-scheduler poll reads due posts in batches of 50 (all owners
  combined) with only the fields needed to publish, at most 10 batches per
  poll. A cursor kept across polls resumes after the last post tried, so posts
  it cannot start are visited once per cycle and never block other owners. See
  [`2026-10-24-due-post-read-bound.md`](docs/superpowers/plans/2026-10-24-due-post-read-bound.md).
- API startup reads server configuration once and passes that same object to the
  app and scheduler diagnostics. It logs only the non-secret social mode,
  publisher name, and whether the empty-backlog guard is enforced. When that
  guard is enforced, a guard-pass message is emitted only after scheduler
  startup succeeds. Staging SHA `208b4e580ddd2291a7a32e718c2519d785730895`
  recorded the enabled mode and guard-pass before one authorized YouTube Shorts
  Private publish passed, then recorded the disabled mode after restoration.
  This evidence does not retroactively prove that an earlier deployment ran the
  guard.
- `POSTPEER_TIKTOK_ACCOUNT_ID`, `POSTPEER_YOUTUBE_ACCOUNT_ID`, `POSTPEER_INSTAGRAM_ACCOUNT_ID`, and `POSTPEER_FACEBOOK_ACCOUNT_ID` are non-production/operator smoke-test integration ids only. Production rejects them and must publish through per-user social connections.
- New per-user PostPeer profiles use versioned 128-bit HMAC pseudonyms. A lost
  mapping to one older 40-bit profile may be repaired temporarily with both
  `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` and
  `POSTPEER_LEGACY_RECOVERY_PROFILE_ID`. The fingerprint is the full
  `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`;
  remove both values immediately after that user's refresh restores the
  mapping. Partial, malformed, duplicate, or mismatched recovery data fails
  closed.
- `PostPeerProfile.profileId` is uniquely claimed by one PostDee user at the
  database boundary. The first mapping remains authoritative for same-user
  races; cross-user claims fail safely without exposing the existing owner.
- `VIDEO_STORAGE=mock` creates mock S3-style upload keys and mock read placeholders; `VIDEO_STORAGE=r2` uses Cloudflare R2 through the S3-compatible API for signed upload and signed download access; `VIDEO_STORAGE=s3` remains available as a legacy AWS S3 path.
- `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID`, and `CLOUDFLARE_R2_SECRET_ACCESS_KEY` configure R2 uploads.
- `CLOUDFLARE_R2_ENDPOINT` can override the default `https://<accountId>.r2.cloudflarestorage.com` endpoint when needed.
- `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS=300` keeps R2 signed upload URLs usable for five minutes. Legacy upload retries request one fresh URL after explicit expiry; managed multipart retries request a fresh URL only for the affected part.
- `UPLOAD_PROTOCOL_MODE=legacy|dual|multipart` selects the upload rollout. It
  defaults to `legacy`; production uses `dual` while old clients are upgraded,
  then can move to strict `multipart` to remove the legacy signed-URL replay
  window.
- `MULTIPART_UPLOAD_PART_SIZE_BYTES=16777216` sets the server-selected managed
  part size (16 MiB by default).
- `MULTIPART_UPLOAD_SESSION_EXPIRES_SECONDS=3600` sets how long an unfinished
  managed upload session remains usable.
- `UPLOAD_MAX_SIZE_BYTES=524288000` controls the maximum declared upload size accepted by `POST /uploads`.
- `RATE_LIMIT_WINDOW_MS=60000` and `RATE_LIMIT_MAX_REQUESTS=300` cap requests per IP per window; exceeding the cap returns `429` with code `RATE_LIMITED` (`GET /health` is exempt). Auth, upload, AI, and social-connection routes also have tighter fixed per-IP buckets.
- `AWS_S3_UPLOAD_EXPIRES_SECONDS=900` controls how long legacy S3 signed upload URLs remain usable.
- `CAPTION_PROVIDER=mock` uses the local Thai template; `CAPTION_PROVIDER=gemini` calls the configured primary `GEMINI_CAPTION_MODEL=gemini-2.5-flash-lite` with `GEMINI_API_KEY`, retries transient failures, then falls back directly to the local template without trying a secondary Gemini model; `CAPTION_PROVIDER=openai` remains available as a legacy path.
- `EDIT_PLAN_PROVIDER=gemini` uses `GEMINI_EDIT_PLAN_MODEL=gemini-3.5-flash-lite` for transcript and visual planning. Both requests require structured JSON and use provider-default sampling without an explicit `temperature`.
- `TRANSCRIPTION_PROVIDER=mock` uses the local Thai transcript for AI caption
  language detection and AI editing; `TRANSCRIPTION_PROVIDER=elevenlabs` calls Scribe v2 with
  `ELEVENLABS_API_KEY`, `ELEVENLABS_TRANSCRIPTION_MODEL`, and optional
  `ELEVENLABS_TRANSCRIPTION_KEYTERMS`; `TRANSCRIPTION_PROVIDER=openai` remains
  available as a legacy path.
- `AUTH_PROVIDER=mock` uses development headers; `AUTH_PROVIDER=firebase`
  requires `FIREBASE_PROJECT_ID`. It verifies Google Secure Token certificates
  by default, or Firebase Admin revocation/user existence when
  `FIREBASE_AUTH_DELETE_ENABLED=true`.
- The mobile app has an auth session store, Google Sign-In UI, and
  Firebase/Google auth gateway. In the production Firebase path, each API header
  refresh reads the live UID and ID token as one credential snapshot and checks
  that UID against the stable session/draft owner before and after the async
  refresh. If the signed-in account changes or no longer matches, the request
  fails closed; Upload also rechecks ownership around remote steps and stops the
  remaining publish flow so one account's draft/video cannot continue under
  another account. Without a Firebase token, local development keeps using mock
  headers. If Firebase auth is enabled before project files are configured,
  startup falls back to a readable sign-in setup message.

Seed helpers:

- `MOCK_USER_ID` controls the default local auth user.
- `SEED_USER_EMAIL` and `SEED_USER_DISPLAY_NAME` control the Prisma seed user.

## Roadmap

See `ROADMAP.md` for the build roadmap. The current product keeps real-clip AI
captions and replaces AI video editing with a publishable profile link. Prices
remain Basic free, Starter 199, and Pro 299. EP tools, hashtag radar, AI comment
center, viral alerts, and team access retain their separate future release gates.

## Current Limits

The backend defaults to mock-safe adapters and in-memory stores for local work,
while production can use Prisma and real provider adapters. Per-user PostPeer
social connections and the connect/refresh/provider-first disconnect API flow
are implemented. A fresh Firebase user is ensured locally before its PostPeer
profile is persisted, and the provider receives a stable pseudonymous profile
name rather than the Firebase UID/email. `GET /posts` now returns user-scoped
`platformResults` for each post. Phase 2 persists one explicit settings snapshot
and reports `deliveryOutcome` as `LIVE`, `PRIVATE`, `UNLISTED`, or `DRAFT` so a
provider draft/private delivery is not described as publicly live merely because
the internal platform result reached `PUBLISHED`. Existing rows may have a null
outcome and continue to use their legacy status display. New TikTok requests can
use Inbox or the complete Direct settings flow on the delivered Staging API when
current creator options can be verified; other environments need API-first
rollout. The provider's audit approval and a real public Direct Post remain
unverified. One immediate Staging YouTube Shorts Private
connected-account E2E passed on 2026-08-10 with a real non-mock external
reference and exactly one post unit, but it predates the complete Phase 2
settings/target/delivery matrix. Production, provider-draft behavior, and the
remaining platforms/scheduling paths still require controlled E2E tests and
never use shared `POSTPEER_*_ACCOUNT_ID` values. The internal
`FACEBOOK_REELS` value targets Facebook Page Reels only through PostPeer
`platform: 'facebook'` with `platformSpecificData.contentType: 'reel'`, with no
Page feed fallback. Optional signed thumbnails remain best effort; their display
on a Reel needs real-account verification, and the provider may choose the cover.
Page Video duration/width limits are not Reel limits. Deploying the updated
publisher also routes existing queued/scheduled Facebook jobs to Page Reels,
retaining their accepted `PUBLISH|PAGE_DRAFT`, optional `isAiGenerated` and
immutable target snapshots; no new client fields, environment variables or
migrations are needed. The repository's Production Blueprint currently selects
`SOCIAL_PUBLISHER=postpeer` even though broader provider-level E2E is still
pending. Treat this as an unresolved configuration risk, not proof that the
deployed Production environment or a user connection is ready; this safety
change does not alter the Production Blueprint.
Owner/post mutation maps remain local optimizations. The 2026-10-14 implementation
delivered to Staging adds PostgreSQL operation tickets and exclusive cleanup claims,
including worker provider/status/notification lifetime, and passes separate-
process synthetic tests. It is not production-safe: before activation in any
other environment, apply the additive migration, upgrade and drain all older
API/worker processes, then
validate actual Redis/BullMQ, real provider/Firebase cleanup and legacy signed-
PUT/OAuth effects. No ticket or cleanup claim may expire by elapsed time.
The in-app Privacy Policy and Terms are still labelled working drafts. Final
hosted legal text, Android/iOS backup behavior for app-owned draft media, Data
Safety/App Privacy disclosures, physical-device draft/replay tests, the
`platformSettingsVersion: 1` API-first migration, legacy-null backlog review,
immutable target revalidation, and the full controlled social
scheduling/provider-draft/recovery matrix remain release gates.
Real-clip AI captioning/editing,
Firebase device auth, RevenueCat Google Play purchases, R2 media flow, and
renewal/refund/cancel handling still need their listed real-device/provider
checks. RevenueCat Test Store purchase and true Restore/resync E2E pass on the
Emulator after the Staging deploy and server REST key configuration. The
RevenueCat Play app/products/entitlements/default offering, production Android
public SDK key, and signed AAB are prepared, but Play Console app/subscriptions,
internal testing, service credentials, and a real Google Play purchase remain
blocked until the developer account is verified with a physical Android device;
the Emulator cannot complete that verification. Platform
views/likes ingestion, Sentry activation/native-crash acceptance, beat/hook
rendering, and AI minute top-ups are not
complete production features yet. See `docs/GO_LIVE.md` and
`LAUNCH_CHECKLIST.md` for the operational truth.
