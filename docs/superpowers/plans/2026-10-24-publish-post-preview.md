# Preview from final post review — 2026-10-24

## Request and baseline

The user wants one preview action under the thumbnail in the final post review,
replacing `แก้คลิป` and the caption's `แก้ไข` link. Keep `แก้ไข` for channel
selection and existing wizard Back navigation for returning to previous steps.
The preview should show the actual video with approximate selected-platform
post presentation, without publishing or generating media.

Implementation initially started from root-verified fresh `main`
`a4efd650d7a74b26fc81e11ccb8bf59d2eeaa79a`, on `codex/platform-captions` in
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`.
That initial fresh-fetch HEAD/tracking `origin/main` shared the same merge base
and 0 ahead/0 behind. Before final delivery checks, main advanced to
`342470fbc2f656ca4a3d289ddcd500ce58177a6e`. The root preserved exactly the
13 feature files with scoped stash `f65a7e0d2d811f9b7801c82b57837dc9ddfac102`,
fast-forwarded the working branch and restored those changes. README/ROADMAP
top-section conflicts keep both the incoming Facebook contract and this preview
record; no side was selected wholesale. The incoming publisher, settings,
preflight, documentation and test capabilities remain preserved. The three
unrelated dirty Windows generated files and other checkout changes stay separate.
The final refreshed baseline is
`6afe4d6b07fe53032467031b4575aa62c9751912`, a docs-only child of `342470f`
that adds the verified Staging deployment record in `docs/STAGING.md`. The root
advances the working branch to that baseline before the final tests/build.
Initial `a4efd65` → incoming runtime `342470f` → deployment record `6afe4d6`
are distinct checkpoints; none commits or publishes this preview feature.

Reviewed the summary/player/uploader entry points, their tests, cover capability
notes and `API.md`. The existing contract needs no edit for this local feature.
Earlier release/build results do not establish delivery of this candidate.

## Intended behavior

- `PublishReviewSummary` replaces `onEditVideo`/`onEditCaption` with nullable
  `onPreview`. A single `พรีวิว` icon button appears below the thumbnail and
  stays visible but disabled without a callback. An available thumbnail may
  invoke that same callback, with an accessible preview label.
- No clip/caption edit control remains in this summary. Keep `onEditPlatforms`,
  wizard Back, all publication outcomes/settings, cover notices, schedule and
  confirmation guards unchanged.
- The uploader opens its selected local video with a snapshot of selected
  destinations only. Each platform view uses its effective caption and connected
  display identity. YouTube also uses the resolved automatic or explicit custom
  title; preview must not overwrite that title or apply shared text over an
  intentionally empty YouTube description.
- Present a clear approximate-post preview. Playing the actual video does not
  claim an exact screenshot of future TikTok/YouTube/Instagram/Facebook layout.
  Use generic **Facebook** in this preview: its local appearance proves neither
  provider delivery nor Facebook Reels production readiness. Preserve the
  refreshed main's `FACEBOOK_REELS` mapping and settings without reinstating an
  older provider route. No Shopee Video or Lazada Video support is added.
- Preserve chosen cover information and platform capability notes. A local
  chosen-cover preview is not a promise that YouTube receives a custom thumbnail;
  Instagram image, Facebook provider-dependent best-effort thumbnail and TikTok
  frame behavior remain separate. Do not promise that Facebook uses the chosen
  thumbnail or that a real Reel/draft delivery has been verified.
- Preserve watermark status/explanation, including existing TikTok restrictions.
  Do not imply preview has burned a watermark into the local video: real
  destination-specific preparation remains in the explicit publish flow.
- Preview is local and read-only: no AI, upload, publish/schedule call, FFmpeg
  render, purchase or post/AI quota mutation.

## Approved TikTok-style and volume follow-up

After testing the initial installed preview, the user asked for a TikTok-like
presentation and playback volume controls. This remains within the same
original 13-file feature scope, later extended by one narrowly bounded Sentry
test-fixture fix; no API/schema/configuration/dependency change.

- TikTok portrait uses a bottom gradient instead of a black rounded details
  card, with the actual selected channel identity and effective caption.
- Heart, comment, save and share form an inert decorative rail, with no fake
  counts or interactions. Do not present decorative controls as actionable
  publishing/social features. `เสียงจากคลิป` labels clip audio without inventing
  a song/artist. Keep bounded scrolling for an expanded long caption and safe
  fallbacks for narrow screens, enlarged text and landscape.
- Preview volume runs from **0–100%**, separate from position seeking. Dragging
  changes the staged value; release commits the value to the native player.
  Mute sets preview playback to zero and unmute restores the previous audible
  level. Switching selected-platform tabs and a local retry retain that setting.
- Volume belongs to this player preview, not the system mixer, saved video,
  export or destination publication. It does not render a modified media file.
  Existing command timeout/failure, owner-session revocation, background pause
  and controller-disposal safeguards remain in force.

## Ownership and playback boundaries

Post-preview metadata can contain a user's caption and channel identity. Capture
the owner's sign-in binding before navigation, pass it with the local snapshot,
and revoke access after that binding changes, including A-to-B-to-A transitions.
Do not bind delayed metadata from one account to a newer session. Stop/release
the active video when access is revoked and retain existing lifecycle/error/
timeout/retry fences.

Plain local playback without post metadata keeps its original behavior. Existing
temporary network playback still starts from an authenticated owned-post read
and retains its own signed-in ownership fence; this feature must not loosen it
or fetch a network URL to render a local preview. Preserve player disposal,
background pause and explicit resume behavior.

This preview feature introduces no API contract, backend runtime,
database/schema/migration, dependency, credential, environment or feature-flag
change relative to refreshed main `6afe4d6` (runtime `342470f`). Its incoming Facebook publisher
contract is retained: `platform: 'facebook'`, `contentType: 'reel'`, required
video, no feed fallback, unchanged publish/Page-draft/AI/caption/target settings,
and no reinstated Feed Video duration/width ceilings. Actual-media verification
still applies; real-account Reel/draft/thumbnail E2E remains pending. `API.md`
was checked and needs no additional contract edit from this preview work.
The incoming Staging receipt records runtime `342470f` Live in deployment
`dep-dbdqk7sipgvc739q4r50`, health/readiness and same-source CI checks, but
explicitly no real Facebook publication. Preserve that receipt and its
environment settings; deployed routing/readiness does not prove provider
delivery or authorize production claims. The generic Facebook preview adds no
new provider capability promise.
Runtime scope is the review summary, uploader route wiring,
existing player and local selected-platform presentation; tests cover those
boundaries. Documentation scope is `README.md`, `ARCHITECTURE.md`, `ROADMAP.md`
and this record.

The frozen feature inventory contains **14 intended files**, excluding the three
unrelated Windows generated files:

- Runtime (4):
  `apps/mobile/lib/features/uploader/publish_post_preview.dart`,
  `apps/mobile/lib/features/uploader/post_video_preview_screen.dart`,
  `apps/mobile/lib/features/uploader/publish_review_screen.dart`,
  `apps/mobile/lib/features/uploader/uploader_screen.dart`.
- Tests (6): `apps/mobile/test/publish_post_preview_test.dart`,
  `apps/mobile/test/publish_post_preview_visual_test.dart`,
  `apps/mobile/test/post_video_preview_screen_test.dart`,
  `apps/mobile/test/publish_review_screen_test.dart`,
  `apps/mobile/test/uploader_post_preview_test.dart`,
  `apps/mobile/test/postdee_sentry_monitoring_test.dart`.
- Documentation (4): `README.md`, `ARCHITECTURE.md`, `ROADMAP.md` and
  `docs/superpowers/plans/2026-10-24-publish-post-preview.md`.

## Historical verification: APK 12047 before the latest follow-up

The following automated/build/native evidence belongs to the original preview
candidate before the TikTok-gradient and volume changes. It must not be reported
as final verification of the latest follow-up or refreshed-base APK 12049.

Tests were changed before the review-summary implementation. The red proof
failed because `onPreview` did not yet exist. The review-summary patch then
passes **30 tests**, including:

- One preview action below the thumbnail and the same thumbnail callback, with
  a semantic label; clip/caption edit controls absent and channel editing intact.
- Visible disabled preview without a callback, including an empty clip name.
- A 320px screen at 2× text scale retains working preview and channel actions.
- Existing effective captions, title/disclosure/outcome/identity, chosen-cover,
  schedule/watermark and explicit confirmation regressions remain passing.

Evidence is under
`D:\PostDeeMobile\artifacts\publish-post-preview-20261024`:
`review-tests-red.log`, `review-tests-final.log` and `review-analyze.log`.
Scoped analysis of the review summary and its tests reports **No issues found**.
Temporary test files use that directory's `tmp` subdirectory. These targeted
fixtures do not establish native playback or real publication.

Additional confirmed candidate results:

- Local presentation/data unit and widget tests: **13 passed**; real-font visual
  checks: **6 passed**, covering four supported platforms, light/dark, enlarged
  text and landscape. Images are in the artifact directory's `visual` folder.
- Review-summary regressions: **30 passed**. Player regressions: **30 passed**
  in the final Staging run, including the added rotation test. Coverage includes
  local metadata/session revocation, pending initialization/ABA, normal local
  and network playback, disposal and cover-to-playback behavior.
- Uploader integration regressions: **4 passed**, including selected-only shared
  captions, independent advanced captions/custom title/cover/schedule, explicit
  empty YouTube description, no clip and no upload/AI/publication side effects.
- Final full Flutter analyzer: **No issues found**, exit 0, **12 seconds**.
- Final Staging-configured regression run: **110 passed**, exit 0, **51 seconds**,
  across seven files: review 30, player 30, presentation/data 13, visual 6,
  uploader preview 4, shared time picker 14 and uploader scheduling 13. This
  covers the new preview alongside the preceding schedule feature. Evidence:
  `staging-regression-tests.log` in the artifact directory. Injected fixture
  playback/account/API responses do not constitute native or cloud acceptance.
- Exact-source Staging debug APK **12047** built successfully in **74.9 seconds**.
  Package is `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`,
  label `PostDee Staging`. All four changed runtime source files match their
  complete source in the compiled kernel, with source hashes recorded.
- Packaged Firebase project/app/web client checks match the intended environment.
  Project is `project-798caf7e-85b8-45e3-af7`, API is
  `https://postdee-api-staging.onrender.com`, Firebase auth is enabled and local
  mock auth is disabled. The validated existing RevenueCat Test Store overlay
  is unchanged. The ignored local monitoring label is
  `postdee-mobile@publish-post-preview+12047`; no checked-in feature flag,
  credential, dependency or runtime service configuration changed.
- APK size is **292,765,577 bytes**, SHA-256
  `b86fbc7d6a4c67bf99f809788e6027b0d30d4b1c20b74c0a80ac9620726bd26c`.
  APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` in the active
  worktree. Build/source/environment evidence is in `preview-build-result.json`,
  `staging-build.log` and `mobile-analyze-final.log` under the artifact directory.

Earlier 12047 integration results:

- Final full Mobile suite (`mobile-full-tests.log`): **2,851 passed / 6 skipped**,
  exit 0, **5m41s**. An earlier run was stopped before the final landscape patch
  and retained as `mobile-full-before-landscape-interrupted.log`; it is not the
  final verification result.
- Staging-configured regression run across seven files: **110 passed**.
- Scoped source/documentation whitespace/path checks and `git diff --check`:
  **passed**; independent complete integrated diff review: **passed**. No tracked
  API, dependency, Android/iOS, workflow or Render changes; the three unrelated
  Windows generated files remain separate.
- Installed with the existing storage-aware helper (`install -r`), upgrading
  **12046 to 12047** on `emulator-5554`. UID **10197** and internal storage
  remained unchanged. The form was inspected without a selected clip before
  restart; no app data was cleared or app uninstalled.
- First launch was interrupted by a guest Android **system_server SIGSEGV**
  at **2026-10-23 18:14:42 UTC**, followed by automatic Android runtime recovery.
  Storage, package version, activity resolution and unlocked user state were
  rechecked before relaunch. The app then rendered its sign-in screen. The
  first Google sign-in attempt displayed a missing-device-account message.
  The user subsequently logged in successfully; the original pending-login
  checkpoint is superseded by the native results below. The startup event did
  not establish deletion of account data. Recovery screenshots include
  `native-upgrade-check.png`, `native-recovery.png`, `native-current.png` and
  `native-after-login.png` in the artifact directory.
- Logged-in **APK 12047 native preview checks pass** using the existing local
  demo `1000000946.mp4` and caption `PostDee preview demo only`. The three
  connected destinations were TikTok, YouTube Shorts and Instagram Reels;
  their actual display identities, selected captions and YouTube title appeared
  on the appropriate tabs. Account names are omitted from this record.
- Actual local play, pause and seek were observed. Back returned to the review
  form with the same clip, caption and three chosen destinations. No AI request,
  upload, actual post, purchase or draft write was made by this native demo.
- Facebook was not connected, so it has **no native acceptance result** in
  this run; fixture/rendering coverage remains the only evidence for that view.
- Native evidence includes `native-preview-tiktok.png`,
  `native-preview-tiktok-ready.png`, `native-preview-playing.png`,
  `native-preview-youtube.png`, `native-preview-instagram.png`,
  `native-preview-return.png` and `native-review-preserved.png`. These screenshots
  precede the TikTok-gradient/volume follow-up and do not verify its final UI.

## Historical TikTok-style/volume candidate: APK 12048 on the original base

- APK **12048** built in **195.7 seconds**, with all four changed runtime source
  files matched in its compiled kernel. Analyzer completed with no issues in
  **74.7 seconds**, and the Staging-configured regression run passed **125**.
  These results preceded the main refresh and do not verify the refreshed base.
- The old-base full-suite run was interrupted at **2,865 passed / 6 skipped**
  with **one Sentry case** blocked by the Windows WMI OS-context path. This is
  **not a full-suite pass**; the later test-fixture/tooling mitigation below does
  not turn the interrupted run into a successful result.
- APK 12048 was installed while preserving UID/storage. The existing form was
  saved as **one local draft** before update. Startup showed an ANR involving
  native FlutterJNI with observed I/O pressure. That initial app-launch screenshot
  was not preview acceptance. It is superseded by the app-only restart and
  explicit native checks below; the startup observation remains historical.
- Local artifacts include `preview-build-result-12048.json`,
  `postdee-staging-12048.apk`, `native-install-12048.json`,
  `native-12048-draft-saved.png`, `native-12048-draft-check.png`,
  `native-12048-launch.png` and `native-12048-ready.png` under the same artifact
  directory. No real post, AI, purchase or upload was made; the one deliberate
  local draft save is separate from the earlier no-draft-write 12047 demo.
- After an **app-only restart**, 12048 recovered Home with the existing Pro plan,
  remaining post quota **235/250** and **one local draft**. Restoring that draft
  retained the same clip, caption and three selected destinations.
- Native TikTok preview then showed the new bottom gradient, real caption and
  decorative icons. The preview slider was changed to **35%**, mute showed
  **0%**, and unmute restored **35%**. This verifies controls/readback, not an
  audible-gain measurement on the dummy clip. No system volume or export edit
  is claimed, and no upload/AI/post/purchase occurred.
- Evidence includes `native-12048-tiktok-ready`, `native-12048-volume-35`,
  `native-12048-muted` and `native-12048-volume-restored` screenshots in the
  artifact directory. These are old-base APK 12048 checks, not acceptance of
  the final refreshed-base APK 12049.

## Verified tooling blocker and isolated Sentry fixture

Windows WMI's operating-system query was verified to block Dart's native
`Platform.operatingSystemVersion` call. Flutter tool analytics constructs OS
context before ordinary command output; analyzer startup adds a child Dartdev
language-server process with its own analytics initialization. The verified
process-only bypass uses **`FLUTTER_SUPPRESS_ANALYTICS=true` and `CI=true`**
before launching those tools. It changes neither OS/WMI services nor the SDK,
repository runtime, production telemetry or customer environment configuration.

One named reporter-forwarding unit test in `postdee_sentry_monitoring_test.dart`
now removes its default SDK integrations through the public `removeIntegration`
API and uses a **20-second** timeout bound. It continues to exercise that test's
intended monitoring wiring without querying the broken host WMI service. Production
Sentry initialization/integrations are unchanged. This is the 14th scoped file,
not a disabled production monitoring feature or a skipped full-suite result.

## Final refreshed-base validation: APK 12049

- Fresh-base targeted regression run: **38 passed** (13 Sentry, 15 presentation/
  data, 10 visual). Command/runtime fixtures remain local, not provider E2E.
- Final Staging-configured regression run across nine files: **150 passed**, exit
  0, **26 seconds**. It covers the preview/volume/owner/lifecycle regressions
  alongside uploader, schedule and monitoring boundaries.
- Fresh-base relevant API regressions: **187 passed across four files**. API
  typecheck also passes, exit 0. API runtime diff for this feature remains empty.
- Final refreshed-base analyzer with process-only CI/analytics suppression:
  **No issues found**, exit 0, **16 seconds**.
- The first refreshed-base full Mobile run reached **2,866 passed / 6 skipped**
  with **one Windows `RenameAccessDenied` failure** in the unchanged draft store.
  The standalone draft-store suite then passed **28 tests in 20 seconds**.
  That first run is not a pass. The complete rerun using a unique temporary
  directory subsequently passes **2,867 tests / 6 skipped**, exit 0, **3m59s**,
  with no remaining failures. Its result supersedes the transient rename
  checkpoint without erasing that history. Evidence:
  `mobile-full-rerun-final-12049.log`.
- Final real-font visual rerun: **10 passed in 3 seconds**. Four freshly
  generated captures were visually checked and pass; these remain local
  rendering evidence, not provider appearance or publication acceptance.
- The original-base 12047/12048 results above remain historical evidence only.
- Fresh fetch confirms final baseline
  `6afe4d6b07fe53032467031b4575aa62c9751912` and 0 ahead/0 behind before the
  feature's local changes. No incoming Facebook capability was reverted.
- Exact-source Staging debug APK **12049** builds successfully in **32.4 seconds**.
  Package is `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`,
  label `PostDee Staging`. All **eight** checked complete sources match the
  compiled kernel: the four preview runtime files, incoming `social_platform`,
  `platform_publish_preflight`, `platform_caption_fields` and unchanged production
  `postdee_sentry_monitoring`.
- Packaged Firebase project, app and web-client checks all match. The project is
  `project-798caf7e-85b8-45e3-af7`, API is
  `https://postdee-api-staging.onrender.com`, Firebase auth is enabled and local
  mock auth is disabled. The existing validated RevenueCat Test Store overlay
  remains unchanged; no SDK key is recorded here. The ignored local build label
  is `postdee-mobile@publish-post-preview+12049`; no persistent SDK, OS-service,
  repository runtime config or production monitoring setting changed.
- Exact APK size is **292,769,533 bytes**, SHA-256
  `2dda138c37d2d90e60a8efb1280619f2e2027fa42f58c9994b2018a2bd1828ca`.
  Durable artifact:
  `D:\PostDeeMobile\artifacts\publish-post-preview-20261024\postdee-staging-12049.apk`.
  Full build/source/environment receipt: `preview-build-result-12049.json` in
  the same directory; earlier APK hashes are not receipts for this candidate.
- Local **12048 → 12049** installation passes final readback: package UID
  **10197**, internal storage and version **12049** match the intended update.
  No uninstall or app-data clear occurred. One local draft was saved before
  updating. Its earlier Pro demo context is distinct from the current Home state;
  this follow-up does not establish restoration of that original demo draft.
- Android's framework/zygote restarted during launch: `system_server` changed
  from PID 7083 to 15794 while kernel uptime continued. The latest filtered logs
  do not establish a new PostDee FATAL or SIGSEGV, and the restart cause remains
  unconfirmed. Boot/unlocked state, mounted storage, package UID/version and
  activity resolution were verified again before relaunching.
- The recovered app initially rendered its sign-in screen. The user subsequently
  completed manual login; authentication was not automated or bypassed. Earlier
  recovery evidence includes `native-install-12049.json`,
  `native-12049-recovery.png` and `native-12049-restored-home.png` (the last file
  shows sign-in, despite its capture filename).
- Current signed-in Home shows **Free, 0/3**, only **YouTube connected (1/4)** and
  **one existing local draft**. This differs from the earlier Pro/three-platform
  demo context. The existing `1000000795.mp4` draft (720×406, approximately 2.1 MB,
  45 seconds) opens through step 4 into the initialized preview with no caption
  and no selected destinations. No account switch or connection change was
  performed to manufacture additional platform coverage.
- Native **APK 12049 playback controls are verified** on that draft: actual
  playback advances to 0:07 and 0:26, explicit pause reaches 0:32, and seeking
  back to 0:09 succeeds. Volume changes **100% → 36% → mute 0% → restore 36% →
  increase 62%** display without an error. This checks the native player controls,
  not measured audible gain, Android system volume or an exported audio change.
- The first earlier pause showed `ยังเล่นคลิปไม่ได้ ลองอีกครั้ง` while the clip
  was actually paused at 0:23. Later explicit resume/pause and seek succeed
  without that message. This is a recovered transient observation; its cause is
  unconfirmed and it is not erased by the successful follow-up checks.
- Back to review preserves `1000000795.mp4`, the empty caption, zero selected
  destinations and the single draft. This follow-up performs **no draft save,
  field edit, AI request, upload, publication or purchase**. The app is left on
  review with the existing draft intact.
- TikTok is disconnected in this current context. Latest **12049 native TikTok/
  Instagram tabs and the TikTok overlay remain unverified**; no selected
  destinations means there are no platform tabs to test on this draft. The older
  **12048 native TikTok** result and **10 final visual tests** retain their stated
  scope and do not substitute for connected-platform native acceptance on 12049.
- Latest screenshots are under
  `D:\PostDeeMobile\artifacts\publish-post-preview-20261024`, with prefix
  `native-12049-`: `user-signed-in`, `draft-restored`, `review-ready`,
  `preview-ready`, `playing-later`, `paused` (the first transient), `volume-lower`,
  `muted`, `volume-restored`, `volume-increased`, `resume`, `pause-recheck`, `seek`
  and `review-after-preview` (all `.png`).

## Immersive reference follow-up: candidate APK 12050

After the signed-in 12049 checks, the user asked to remove the bottom playback
controls shown in their first image and match the immersive social-video layout
in the second image. This supersedes the bottom-panel presentation only for
metadata-bearing post previews; the preceding 12047–12049 evidence remains
historical and is not relabeled as acceptance of this new UI.

During validation, main advanced by nine API-security/documentation commits to
`8872f0e54f7b3d835a3a052b29e1803e905d59d9`. The root retained exactly the three
tracked candidate docs in a scoped stash, fast-forwarded and restored them,
preserving both incoming identity/security notes and both preview sections.
The untracked plan, runtime/tests and unrelated Windows generated files remained
untouched. The retained scoped stash is not dropped. Fresh tracking is 0/0;
there are no incoming Mobile or schema changes. All ten candidate Mobile
runtime/test hashes match before and after the refresh, so the in-progress full
Mobile run remains valid for the same code bytes. Fresh API installation/static/
targeted validation is tracked separately below. This checkpoint
does not alter the historical 12049 baseline or merge/push the preview feature.

- The post-preview route uses a black full-bleed canvas with the actual native
  video at its natural aspect ratio, without cropping or changing the media.
  White Back/title/speaker controls sit over the top. No external white header,
  rounded video card or bottom seek/replay/time/volume panel remains on this path.
- Tap the canvas to play/pause; paused playback has a central play affordance.
  The top speaker action opens inline playback-only volume/mute controls on
  demand. The previous audible level and existing command/timeouts, background
  pause, explicit resume, owner revocation and controller disposal remain guarded.
  No system volume or exported/published audio is modified.
- `PublishPostPreviewPane.immersive` defaults to false, preserving its previous
  standalone presentation. The post-preview route opts in. Real captions,
  selected account identities, YouTube titles and only selected destination
  chips appear over the video. With no destinations, the shared caption and a
  generic rail appear with no invented identity or counts. Generic Facebook
  wording and the upstream Facebook delivery contract remain unchanged.
- The white right rail shows decorative profile/heart/comment/save/share/audio
  symbols, has no fake counts and is excluded from interactive semantics. Audio
  is labeled `เสียงจากคลิป`, with no invented song or artist. Caption expansion
  remains bounded and scrollable at narrow widths, 2× text scale and landscape.
- Cover toggling remains directly accessible; capability, publishing, watermark
  and approximate-appearance notes move into a compact inline information panel.
  Opening it pauses/cancels pending playback. Its own opaque gesture handler
  prevents reading/tapping panel content from toggling the parent video. The
  panel stays inside the owner-bound preview subtree and uses no separate
  Navigator route, so revoking/removing the preview also removes its metadata.
- Plain local and authenticated temporary-network viewing keeps its original
  bottom controls. This follow-up changes no API, schema, dependency,
  configuration, backend deployment, publishing settings, quota or export flow.

Latest-source verification checkpoints:

- Full Mobile suite: **2,880 passed / 6 skipped**, exit 0, **9m26s**.
  Evidence: `mobile-full-12050.log` in the existing task artifact directory.
  Mobile code hashes are identical across the baseline refresh above.
- Analyzer: **No issues found**, exit 0, **16.7 seconds**.
  Evidence: `mobile-analyze-12050.log`.
- Joint preview integration/regression suite: **76 passed**, exit 0,
  **10 seconds**. Evidence: `immersive-joint-tests-12050.log`.
- Fresh `8872f0e` API validation: `npm ci` succeeds in **30 seconds**, resolving
  the intended `body-parser` **2.4.0**. Prisma client generation succeeds with a
  task-local dummy URL and no database connection. Typecheck and build pass,
  exit 0; **206 tests across 11 targeted files** pass in **11.36 seconds**.
  Logs are `fresh-main-12050-api-{npm-ci,prisma-generate,typecheck,build,targeted}.log`.
  This scope does not mean all **187** historical 12049 API checks were rerun.
  API source diff remains clean against the refreshed baseline; there is no
  preview-specific backend change, migration or deployment.

- Final Staging nine-file suite: **163 passed**, exit 0, **58 seconds**.
  Evidence: `staging-12050.log`.
- Final exact-color real-font visual rerun: **15 passed**, exit 0, **4 seconds**.
  Evidence: `visual-final-12050.log` and `immersive-final-12050-visuals/`.
  Root visually checks the final portrait and 2× text captures: dark chips are
  correct. The earlier translucent-chip captures in `immersive-pane-visuals/`
  are historical only. The final source uses opaque dark chips because Material
  otherwise composites translucent black against its light canvas.
- Exact-source Staging APK **12050** builds, exit 0, in **44.2 seconds**.
  It is **292,783,165 bytes**, SHA-256
  `eae11bb656ea9bd7221e844c6b641d29f3e90cf7556ddb4225ec5fbd5ee2bbd5`.
  Durable artifact: `D:\PostDeeMobile\artifacts\publish-post-preview-20261024\postdee-staging-12050.apk`.
  All **eight complete-source** comparisons and package/version, Firebase,
  intended Staging API and local release/flag checks pass. Receipt:
  `preview-apk-checks-12050.json`. The ignored local release label changes only
  to `postdee-mobile@publish-post-preview+12050`; production Sentry is unchanged.

Installation/readback and native 12050 checkpoints:

- **12049 → 12050** update succeeds, exit 0, with version 12050, package UID
  **10197** and the same internal volume/storage. No uninstall, data clear or
  Android reboot occurs. Receipt: `native-install-12050.json`.
- Before updating, Channels shows only YouTube connected and no dirty editing
  form; the local draft is already retained. Initial cold launch later records
  an **ANR**. One app-only force-stop/restart recovers Home. Its cause remains
  unconfirmed; initial launch success is not claimed. No app data is cleared.
- The active signed-in account remains **Free, 0/3**, YouTube **1/4**, with one
  existing draft `1000000795.mp4`. Its **zero destinations and empty caption**
  remain intact. This proves neither connected TikTok-tab native acceptance nor
  restoration of the historical Pro/three-channel demo context.
- The actual immersive preview is rendered and checked: canvas tap plays and
  pauses; the prior bottom control panel is absent; the inline speaker panel
  changes volume **100% → 34% → mute 0% → restore 34%**. The generic social rail
  is appropriate for this zero-target draft; no account/caption/count is invented.
- These are native player/UI checks, not measured audible gain, system-mixer
  changes, exported audio or provider appearance/publication. No AI, upload,
  publication or purchase is performed. Earlier pane/visual checks preserve the
  original default-mode behavior.

### Final cosmetic Staging status-bar follow-up: local APK 12051

Native inspection finds white status icons against Staging's light status area.
The player conditionally uses `SystemUiOverlayStyle.dark` only when
`POSTDEE_STAGING_BUILD` is true **and the outer theme is light**. Dark Staging
and normal immersive routes retain light icons for their dark status surface.
The existing light-theme assertion is extended by a new dark-outer-theme test;
the latter first fails (RED), confirming the unconditional Staging-only choice
was incorrect. Final player/Staging/analyzer checks follow that correction.
Earlier intermediate 12051 player 42/Staging 163 passes precede this last fix
and are not final verification of its light/dark behavior.
The pane/data/visual source stays frozen. The ignored local release label becomes
`postdee-mobile@publish-post-preview+12051`; production Sentry, API/schema,
dependencies, publishing and app data are unchanged. Earlier 12050 full-suite/
build/native results keep their own scope and are not relabeled as a complete
12051 full-suite rerun.

Final 12051 verification:

- The post-cosmetic player suite passes **43**, Staging passes **164** and
  analysis finds no issues. One further information-panel integration test is
  then added to verify pause/no automatic resume, changing tests only. Final
  ordinary player checks pass **44 in 5 seconds**, final Staging checks pass
  **165 in 11 seconds**, and analysis finds **No issues** in **11.8 seconds**,
  all exit 0. Authoritative logs are `info-final-player-12051.log`,
  `info-final-staging-12051.log` and `info-final-analyze-12051.log`.
- The runtime remains frozen after the cosmetic fix; the final test addition
  requires no APK rebuild. Exact-source APK **12051** builds, exit 0, in
  **93.9 seconds** (`build-12051.log`). It is **292,783,813 bytes**, SHA-256
  `37b369324908a9e66ba59963b31befc85420150b838d97d2d46632985bfe04a9`.
  Durable artifact:
  `D:\PostDeeMobile\artifacts\publish-post-preview-20261024\postdee-staging-12051.apk`.
  Receipt `preview-apk-checks-12051.json` verifies all **eight complete-source**
  comparisons, package/version and Firebase checks. The final runtime still
  matches this APK after the test-only addition. Consolidated final evidence is
  in `preview-build-result-12051.json` in the same task artifact directory.
- **12050 → 12051** installation succeeds with UID **10197** and internal
  storage preserved; no data clear or uninstall. Receipt:
  `native-install-12051.json`. Cold launch takes approximately **45 seconds**
  and reaches signed-in Home **without an app-only restart**. The 12050 initial
  ANR/recovery remains historical; it is not attributed to 12051 or erased.
- Home retains **Free, 0/3**, YouTube **1/4** and one existing draft
  `1000000795.mp4`. Opening it through step 4 shows the same empty caption and
  zero destinations. The actual landscape clip is letterboxed at its natural
  aspect ratio without cropping. No connected account, caption or count is
  invented for the generic social rail.
- Native preview checks confirm readable dark status icons above the light
  Staging surface, the right social rail and no bottom seek/play/replay/time/
  volume panel. Canvas play/pause and replay from the end pass. Inline volume
  changes **100% → 34% → mute 0% → restore 34%**. Tapping the canvas dismisses
  the volume panel without starting playback. A controlled repeat of information
  open/close leaves the video paused with the central play affordance visible;
  the final integration test separately verifies the native-command wiring.
- Back returns to review with the same clip, empty caption, zero destinations
  and one draft. Reopening preview leaves it **paused for the user**. No draft
  field edits/saves, AI request, upload, publication or purchase are performed by
  these checks. Native iOS, connected TikTok tabs and actual platform delivery
  remain unverified. Volume checks do not measure audible gain or change export
  audio/system volume.
- Latest native evidence uses prefix `native-12051-` in the task artifact folder:
  `ready-current.png` (Home), `review-ready.png`, `playing.png`, `volume.png`,
  `volume-lowered.png`, `volume-restored.png`, `muted.png`,
  `volume-dismissed.png`, `paused.png`, `back-review.png`, `final-info.png`
  and `final.png`. The final capture shows the paused immersive preview.
  `final-still.png` rereads the same paused frame and central play affordance
  approximately one minute later, corroborating no automatic resume after info.

Do not reuse the 12049 build receipt or connected-account evidence as proof for
this candidate. These checks precede the subsequent `main/push` instruction
recorded below; they do not establish a cloud deployment.

## Local-validation delivery boundary (before main/push instruction)

At this checkpoint the work is local implementation and review. No main
integration, GitHub push or cloud deployment has occurred for this follow-up;
the implementation request alone does not authorize those release actions.
The subsequent main/push instruction is recorded below. Refreshing the branch to
already-published main preserves upstream work; it does not merge/push this
preview feature into main or deploy its provider changes. Earlier APK 12047 and
then 12048 were updated in the emulator as recorded above. A durable earlier copy is
`D:\PostDeeMobile\artifacts\publish-post-preview-20261024\postdee-staging-12047.apk`.
The user has completed sign-in. The original preview native demo and the latest
12049 control checks retain their distinct account/draft and platform coverage.
Retain the active account, app storage, clip/caption/selected destinations and drafts
before any local candidate update. Inspect the active form and preserve its
state before restarting. Do not clear data, uninstall or bypass authentication.
Retain the deliberate local draft saved before installing 12048. Refreshed-base
APK 12049/build/full-suite validation and retained-data installation now pass.
Latest signed-in native playback/volume/seek/Back checks pass on the current
existing draft, with the recovered transient and connected-platform limitations
recorded above. No further login is requested. The earlier native 12048 TikTok
checks do not replace final-candidate connected-platform acceptance.

The existing API supports this local UI, so no backend deployment or migration
is required. Automated fixtures and the verified build do not establish actual
platform appearance, provider quality or real publication. No live AI credit,
purchase or post was consumed by the verification recorded here.

The latest installed candidate is **12051**. Its final targeted/analyzer/build/
native evidence is recorded separately above; the full **2,880 passed / 6 skipped**
result belongs to 12050 before the cosmetic status-bar follow-up. Account,
storage and the existing draft remain retained, and the current preview is left
paused. These local checkpoints precede the subsequent main/push instruction;
they do not establish a cloud deployment.

## Authorized main/push handoff (2026-10-24)

After reviewing the installed preview, the user explicitly requests `main/push`.
Fresh `git fetch origin main` confirms the integration baseline remains
`8872f0e54f7b3d835a3a052b29e1803e905d59d9`, with HEAD/origin/main sharing the
same merge base and 0 ahead/0 behind before the feature commit.

The handoff includes exactly fourteen feature files: four Mobile runtime files,
six tests and these four documentation files. The three unrelated Windows
generated-file changes are excluded. Runtime hashes still match all eight
source checks in the installed APK 12051 receipt; the only new edits during
handoff describe the user's release authorization. The final 44 player and
165 Staging checks, analyzer, APK and native evidence above retain their scope.

Use a normal fast-forward main integration and push, preserving existing local
work. The canonical main checkout contains an unrelated launcher/STAGING-doc
edit, generated files and untracked launcher artifacts; these must remain
outside this commit. Any scoped preservation stash is retained until its
restoration has been verified. Git history and the final remote readback identify
the delivered commit. The commit carries `[skip render]` because this request
does not require an API deployment. No schema, configuration, dependency,
provider or exported-media change is introduced by this handoff.
