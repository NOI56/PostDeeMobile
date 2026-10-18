# Unified publishing settings — 2026-10-18

## Scope and baseline

The user approved the four-platform settings plan with **เริ่มไล่แก้ไขเลย**.
This covers a consistent settings UI, TikTok lazy Direct options, optional Meta
AI-media declarations, end-to-end data plumbing and regression verification.
The subsequent **push/deploy** request authorizes merging/pushing the tested
source, deploying Staging API first and then updating the user's logged-in
emulator while preserving its data. Real publication, OAuth grants, purchases,
historical-data repair and Production changes remain outside this release.
The subsequent **เพิ่มพื้นที่ให้หน่อย** request also authorizes expanding this
emulator's available storage and completing the app update while preserving the
existing account and drafts. Its recovery and verification are recorded below.

Canonical `grouped-account-ui` main and remote were freshly fetched and verified
at **c813eef72d1bc98e958b86ae2928e80a20939f8a**, 0 ahead/0 behind. The already
attached `tiktok-native-session-results/PostDeeMobile` worktree was reused with
branch **codex/platform-settings-unified** starting at that exact main. Three
pre-existing generated Windows plugin changes remain untouched/excluded; the
stale dirty `D:/PostDeeMobile` checkout and canonical untracked artifacts remain.

## User-visible changes

- One `PlatformSettingsScaffold` supplies platform logo, account identity,
  Cancel/Save actions, validation and a scrollable body bounded to available
  height (maximum 86% of the screen). Short Inbox forms shrink to their content.
  The footer stays above the keyboard; labels wrap with larger system text.
  An actual short-phone/keyboard test also exposed overflow in the underlying
  composer header. Its toolbar/progress now shrink within a scrollable header
  capped at 45% of available height; main content and sticky actions are retained.
- TikTok Inbox explains the handoff, real quota use and final TikTok action.
  It does not load Direct capabilities. Direct loads on entry, clears consent
  and binds the fresh response to the current owner/account/generation. Leaving
  Direct clears the options and invalidates any late completion; reentry reads
  fresh options. Existing creator restrictions and manual music/branded consent
  remain enforced. Grouped controls retain privacy, interactions, commercial and
  AI settings; no default privacy or invented permission is introduced.
- YouTube groups title/visibility and audience/content choices. Existing
  blank-only title suggestions, required kids/synthetic-media answers and manual
  certification are preserved, with a visible reason when Save is disabled.
- Instagram retains feed sharing; Facebook retains explicit publish/Page-draft
  selection. Both show the selected cover context and optional AI-media answers.
  Cover selection remains in the clip step. Facebook is Page Video, with no
  unsupported Reels claim. Page drafts still upload/use quota; local drafts do not.
- Review includes explicit Meta AI answers and all TikTok Direct interactions,
  commercial/AI/music/branded declarations, alongside existing destination,
  schedule, YouTube answers and cover context.

## Additive contract and compatibility

IG and FB platform settings accept optional **isAiGenerated: boolean**. Mobile
uses nullable `instagramIsAiGenerated` / `facebookIsAiGenerated`; null means
unanswered and is omitted from draft/API/recovery serialization. It is never
silently defaulted to false. Explicit true/false can be saved or cleared and
participate in equality/hash and immutable post-intent comparison.

The strict backend parser accepts the existing exact old shape or the exact
shape with a boolean declaration. Null, strings, numbers and unknown fields are
rejected. Persistence, BullMQ, accepted replay and owner-scoped recovery preserve
the original shape. A changed declaration conflicts with an already accepted
request ID. Provider mapping emits explicit true/false only when present.
Captions written by AI do not determine media disclosure.

No database/schema/migration, dependency, environment, plan, quota or destination
change is needed. **Deploy the API and every publishing worker before Mobile**:
the previously deployed parser rejects new fields, and old workers must not read
new declaration snapshots. Existing old clients remain accepted by the new API.
The owner barriers, media/upload receipts, original request IDs and no-resend
recovery protections remain intact.

## Verification

- Regression-first backend tests reproduced 13 failures for unsupported flags;
  the corrected targeted run passed 299 tests. Final full API suite passes
  **127 files / 2,207 tests**, using `--maxWorkers=2` (47.15 seconds).
  An initial default-parallel run timed out two unrelated catalog checks under
  concurrent work; the complete rerun passes without changing timeouts or skips.
- API typecheck/build, Prisma schema validation with a local dummy URL and
  Prisma seed/config helper compilation pass. No live database mutation was used.
  Logs: `C:/Users/stopp/AppData/Local/Temp/postdee-meta-ai-full-test-retry.log`
  and sibling `postdee-meta-ai-{typecheck-final,build,prisma,prisma-helper}.log`.
- Independent backend review finds no actionable issue in optional-field
  parsing, equality, replay/recovery, persistence, queue or provider mapping.
- Compiled `dist/app.js` smoke with injected dummy Prisma rows passes `/health`
  and owner-scoped `/posts` reads: missing/false/true disclosures survive DTO
  normalization, private/no-store is retained, with one injected read and zero
  external fetches/writes. Log:
  `C:/Users/stopp/AppData/Local/Temp/postdee-meta-ai-compiled-smoke.log`.
- Mobile settings/draft/review regression checks pass **81 tests**; separate
  recovery-client checks pass **8 tests**. New UI tests reproduced eager Inbox
  reads and missing declaration controls before production edits. Scaffold checks
  cover compact content, sticky actions, large text and keyboard constraints.
- Source-final `flutter analyze --no-pub` passes with no issues (16.0 seconds).
  Full Mobile suite passes **2,371 tests / 2 optional preview skips** in 3m29s,
  using `--no-pub --concurrency=4 --reporter=expanded`. The new opt-in five-sheet
  preview was executed separately and passes. Final logs:
  `C:/Users/stopp/AppData/Local/Temp/postdee-unified-settings-mobile-full-final.log`
  and `postdee-unified-settings-analyze-final.log` in the same directory.
- The initial whole Mobile run found 24 failures: 23 old global-first-scroll
  selectors targeted the new header instead of the composer, plus one existing
  Instagram copy assertion. Selectors now explicitly target main/header/modal
  according to the interaction; existing assertions and skips were preserved.
  The familiar Instagram wording is retained. The affected 183 checks pass
  (182 together plus the isolated wording case) before the final whole-suite run.
  No tests were removed or disabled to obtain a green result.
- Independent UI/data review verifies Cancel discards local edits, current
  owner/binding checks remain, stale Direct results cannot restore consent, and
  all YouTube/TikTok required declarations remain enforced. Whitespace-normalized
  review confirms underlying composer content and sticky actions are preserved
  around the new responsive header wrapper.
- The implementation checks made no connected-account publication, store
  purchase, login grant, user draft modification, emulator installation or
  Production change. The separately authorized delivery is recorded below.

## Android build and visual checks

- Exact local Staging APK builds using the validated helper and base build
  number 8024 / versionCode **12024**, x86_64, min SDK 24/target SDK 36,
  package **com.postdee.postdee_mobile.staging**, version **0.1.0-staging**.
  Source-final build time 24.3 seconds. Artifact size **127,815,906 bytes**, SHA-256
  **FF67B6268B1CE92FA3ED2D6E623BF38890E21871E191D564378DDDED88A31A6C**.
  Signer SHA-256 matches delivered 12023:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  Build log: `C:/Users/stopp/AppData/Local/Temp/postdee-unified-settings-apk-12024-final.log`.
- Helper inputs verify Staging API, Firebase auth enabled, local mock auth
  disabled, RevenueCat enabled with the existing Test Store overlay, and both
  experimental AI Hook/Beat Sync disabled. AAPT verifies the package/version and
  packaged Firebase project matches the Staging Google-services file. Only
  matching booleans are printed; credential values are not exposed. These are
  build/configuration checks, not a new authenticated emulator session.
- Actual Flutter widget previews use bundled Anuphan fonts and platform assets,
  with fixture accounts and no real publishing. Inspected all five: compact
  TikTok Inbox, grouped Direct, YouTube, Instagram and Facebook Page Video.
  Short-phone tests use 360×640 with a 220-pixel keyboard and 1.5× text.
  Dropdowns expand to available width; the last real controls and fixed actions
  remain reachable. The preview-only run passes separately.
- Preview files are outside product source at
  `C:/Users/stopp/.codex/visualizations/2026/10/18/01a14cae-8651-76f3-814e-ae06034fa8e8/platform-settings-unified/`:
  `tiktok-inbox.png`, `tiktok-direct.png`, `youtube_shorts.png`,
  `instagram_reels.png`, `facebook_reels.png`. A few background toolbar glyphs
  use a test-font fallback; the real sheet text and bundled logos render correctly.
- APK12024 is now installed after the confirmed Staging API rollout and the
  authorized storage follow-up below, including a same-volume reinstall/cold
  boot. Native Home/account, two local drafts, actual saved-video playback and
  a read-only compact TikTok Inbox check pass. Other new native dialogs were
  not checked in this follow-up. No connected
  Instagram/Facebook publication, provider label or physical-device check is
  claimed. The exact-source unsigned
  iOS CI build passes; no iOS device test or installation is claimed.

## Authorized Staging delivery

- Tested source **866f0e39a43029b5a45d4a5976d9b984bb2148e7** was fast-forwarded
  into canonical main and pushed to origin. Unrelated generated Windows plugin
  changes and untracked artifacts were excluded and preserved.
- Exact-source Backend/Flutter CI **39089186176** passes, completing at
  **2026-10-18 02:16:01 UTC**: Backend 1m12s, Flutter 4m47s, with the full
  2,207 API and 2,371 Mobile tests and analysis passing. The two optional Mobile
  preview skips remain; the new preview also passed its separate local run.
- Exact-source unsigned iOS CI **39089186129** passes at **02:18:09 UTC**
  (6m51s), including no-codesign build, IPA creation and upload. Artifact
  `PostDee_iOS`, ID **12122615342**, is **44,466,099 bytes** with digest
  `0ea2a9ac890abc2d4efd823ec1d920a0d3b867d928290d2a70cf8ce0aec8e9a9`.
  This proves the build/artifact checks only, without an iOS device test.
- Staging service **srv-d9bb72ojs32c739osa5g** was manually deployed once at
  **02:17:45 UTC**. Deploy **dep-dba2oieq1p3s73a3g6qg** is **Live** at
  **2026-10-18 02:19:41.984629 UTC / 09:19:41 Asia/Bangkok** (1m56s),
  confirmed through Render MCP and Dashboard with the exact source above.
  Public `/health` returns HTTP 200 `ok`; `/ready` returns HTTP 200 with
  database/queue `ok` and `Cache-Control: no-store`.
- Fresh pre-deploy and post-Live aggregate reads both show **10 posts**, **0 global
  QUEUED/PUBLISHING posts**, **5 retained ManagedOwnerOperation markers**,
  **0 deletion runs**, and **18 applied / 0 unfinished migrations**. The
  publisher is PostPeer, the queue is memory, and the empty-backlog guard stays
  enabled. Staging has no separate publishing worker service; deploying the API
  updates its in-process publisher. No schema, dependency, environment or
  publishing-mode change was needed. The post-Live Shell read confirms the
  exact source above on the new instance; no database writes or marker clearing
  were performed. Render Live screenshot:
  `C:/Users/stopp/.codex/visualizations/2026/10/18/01a14cae-8651-76f3-814e-ae06034fa8e8/postdee-unified-settings-staging-live.jpg`.
- A read-only in-memory probe of the deployed compiled parser at the exact
  source passes for both Instagram and Facebook: absent/false/true values are
  accepted and preserved; null/string/number values are rejected; absent, false
  and true remain distinct immutable intents. The probe makes **0 writes / 0
  provider calls**; it is not a real authenticated HTTP post/publication test.
  Fresh startup logs at **02:19:37 UTC** confirm PostPeer publishing enabled,
  the enforced empty-backlog activation guard passing and listening on port
  10000. No publishing configuration was changed for this deployment.
- The initial data-preserving Android **12024** debug installation safely failed
  with `INSTALL_FAILED_INSUFFICIENT_STORAGE`, with about **572 MiB** free.
  No application data/cache was cleared and the existing app was not uninstalled.
  Its composer has no clip or caption; Save Draft refused because no video was
  selected. The **2 existing local drafts** remain unchanged, with **0 upload
  receipts**. One official `--streaming --fastdeploy -r` attempt fell back to
  streamed installation and failed for the same storage reason. The APK has no
  `.idsig`, so an incremental install is unavailable. The validated helper does
  not permit a smaller profile/release Staging build; bypassing it would use a
  Production package/key and was rejected. No source/configuration or disk
  change was made to force that attempt. It left **12023 installed** and
  new-version device/UI checks unverified. The later authorized storage recovery
  below supersedes this initial installation boundary.
- Before the storage follow-up, old-app readback confirmed version **12023** with the
  existing signed-in state visibly retained. The same **2 local drafts** retain
  schema **3**, **0 upload receipts** and aggregate SHA-256
  `7D0E32A2C89E3F8B741DD190C97D55D02A871D10D119CC14613A5CF685CB5E23`.
  No active installer or temporary install residue remains; free space returns
  to **585,472 KiB** (about 571.75 MiB). Only this task's forwards/attachments
  were removed. The running app remains visibly on the **Shop** tab; native
  automation stopped on repeated `user-input-detected` responses without forcing
  navigation to Home. Final screenshot:
  `D:/Temp/unified-release-12023-preserved-shop.png`.
  A new authenticated client GET smoke is **unverified**: the installed VM's
  compilation/attach service was unavailable, so the attempt was stopped without
  claiming an HTTP result. This old-app/data check does not verify APK12024 UI
  or the new declaration fields. The storage follow-up below records the later
  successful installation separately.
- Production remains untouched. No new connected-account upload/publication,
  AI generation, OAuth grant, purchase, post repair or provider resend is part
  of this release. Real Instagram/Facebook labeling/publication, TikTok Direct
  public approval and physical/iOS device delivery remain unverified.

## Authorized emulator storage follow-up

- Before changing storage, the stopped original AVD and its pointer were fully
  copied to `D:/PostDeeBackups/PostDee_Pixel-before-storage-20261018-1/`.
  `verified-file-manifest.json` verifies all **56 files / 13,493,218,099 bytes**
  (55 AVD files plus the pointer) with source/copy SHA-256 matches. Private ACLs
  limit access to the owner, SYSTEM and administrators. This backup is retained.
- The existing internal data disk was not resized. A **new 16 GiB** NTFS-sparse
  RAW image at `D:/.android/avd/PostDee_Pixel.avd/postdee-storage-16g.img` was
  verified blank, attached to the same AVD and adopted by Android as a separate
  encrypted F2FS private volume. Only the new disk was partitioned. Its UUID is
  **470668ed-4e40-4628-acb4-8704efc6b257**. This adds storage; it does not turn
  the existing internal `/data` disk into a 16 GiB disk.
- A standard Android compile step resolved the initial package-move missing-oat
  error; moving only PostDee retained UID **10190**. Native checks on old 12023
  then retained the signed-in Home, two draft rows and readable saved media.
  Android's adopted-storage `run-as` guard was not bypassed with permission or
  ownership changes. The package external-storage override remained unset.
- A subsequent plain `adb install -r` installed the exact APK12024 but selected
  an internal data location and initially showed login. The original account,
  two schema-3 drafts and saved media remained on the adopted volume. Readback
  of that original CE data matched the pre-move draft aggregate
  `7D0E32A2C89E3F8B741DD190C97D55D02A871D10D119CC14613A5CF685CB5E23`.
  Six private original CE/DE archives and two filtered recovery archives were
  retained. After on-device transport SHA-256 verification, the persistent CE/DE
  entries were coherently restored for the same UID, excluding old Flutter
  runtime/assets/callback files. No Google account, Keystore, permission or
  security setting was changed. Native 12024 then restored the signed-in Home,
  existing account connections and draft thumbnail without a fresh login grant.
- After moving 12024 back to the private volume, the new shared updater performed
  a real same-volume reinstall of the unchanged, validated Staging APK with
  `--force-uuid` and `-r`. Package UID **10190**, versionCode **12024** and the
  same volume UUID were verified before/after. A full cold boot without the
  command-line `-sdcard` override proves the durable AVD config mounts that
  same image. Cold-boot readiness waits for the private volume/package metadata,
  since `sys.boot_completed=1` can precede storage availability. Post-boot free
  space is **16,242,952 KiB** on the private volume (about **15.49 GiB**) and
  **786,552 KiB** internally. The image remains a separate added volume.
- `android-install-volume.ps1` now verifies package identity, UID, version and
  current volume. The launcher requires that exact adopted volume to be mounted,
  pins it for updates, preserves the installed build number and refuses unknown
  or conflicting state without migration, uninstall, data clearing or fallback.
  Staging `run` refuses unsafe adopted Android installs; `build-apk`/`test`
  remain device-free. Use the guarded launcher then `flutter attach` for debug
  work rather than raw `flutter run`/plain `adb install -r` on this emulator.
  The Android desktop shortcut was SHA-verified/backed up and retargeted to the
  canonical launcher with `-AvdName PostDee_Pixel`; the separate Electron
  shortcut was not changed. Independent guard verification passes **64/64 mock
  tests** on both Windows PowerShell 5.1 and PowerShell 7, four script AST
  parses, launcher `-ResolveOnly` and diff checks. The launcher now waits within
  its existing bounded boot deadline for private volumes and package metadata;
  it does not infer a fresh install from a transient empty package list while
  an adopted volume or retained package data exists. Other probe/metadata errors
  fail closed. An independent root rerun passes all 64 tests on PowerShell 7;
  actual read-only final helper probes report boot/storage ready, UID 10190,
  version/build number 12024 and the same adopted UUID. Windows PowerShell 5.1
  `-ResolveOnly` resolves the canonical main paths. These are local tool checks,
  separate from the prior feature CI and native checks below.
- After the config-only cold boot, Android **12024** retains the same signed-in
  account. Home shows **Free 0/3**, recent posts, the existing TikTok/YouTube
  **2/4** connected channels and a draft thumbnail. A transient channel read
  recovers after one GET-only retry. The draft header and list both show the
  same **2 existing drafts**; actual local one-second video playback completes
  at **0:01 / 0:01**. No fatal, unhandled, player, Keystore or FileSystem error
  was observed. The compact TikTok Inbox shared-logo/explanation/Cancel-Save UI
  was inspected read-only and cancelled. No form/settings/draft was saved and
  no media was uploaded. YouTube/Instagram/Facebook new native dialogs were not
  checked in this storage follow-up; their widget previews/full regressions are
  separate evidence. No real publication or publishing capability is proved.
  Final screenshots: `D:/Temp/postdee-12024-final-coldboot-home.png`,
  `D:/Temp/postdee-12024-final-coldboot-drafts.png`,
  `D:/Temp/postdee-12024-final-coldboot-playback.png`.
  The app is left on Home with all owned forwards/attachments removed.
- One existing draft still displays the warning **“บางช่องทางในร่างยังไม่ได้เชื่อมต่อ
  กรุณาเชื่อมใหม่ก่อนโพสต์”** although
  Home shows both relevant channels connected. The original backup's two draft
  target sets are `[TIKTOK]` and `[TIKTOK, YOUTUBE_SHORTS]`; this is not evidence
  of missing restored draft targets. Source inspection shows `_restoreDraft`
  validates against initially empty `_connectedPlatforms`, while the initial
  unawaited `_loadConnections` can finish later and update availability without
  clearing `_errorMessage`. A stale early validation message is the **inferred
  likely cause**, not a captured end-to-end publishing diagnosis. This existing
  Dart flow was not changed by the storage-only patch. A separate targeted
  regression/fix is needed; no post was submitted to test it.
- API source `866f0e3` and its already Live Staging deployment are unchanged;
  this separate installer/tool follow-up does not require an API redeploy. No real
  publication, AI generation, OAuth grant, purchase, historical post repair or
  provider resend was performed. Earlier Backend/Flutter/iOS CI IDs apply to
  feature source `866f0e3`, not these later tool changes; independent local guard
  verification is recorded above. The verified native scope preserves the
  account/drafts and closes the local storage
  update; real publishing, other native dialogs and iOS remain separate checks.
- The subsequent **push เลย** request authorizes committing/pushing this
  installer/tool follow-up separately: **10 files**, comprising the **4
  PowerShell tools and 6 related documents** listed below. This preserves the
  storage-safe update path in source control without a new API deployment.
  Authorization is recorded here; completion is verified from the resulting
  commit and remote push rather than inferred from this entry.

## Primary changed files

| Area | Files |
| --- | --- |
| Shared sheet, layout and controls | `apps/mobile/lib/features/uploader/platform_settings_scaffold.dart`, `uploader_screen.dart`, `tiktok_publishing_settings_sheet.dart` |
| Draft/request model and review | `apps/mobile/lib/features/uploader/platform_publish_settings.dart`, `publish_review_screen.dart` |
| API parser/immutable intent and provider mapping | `apps/api/src/modules/posts/platformSettings.ts`, `apps/api/src/workers/postPeerPublisher.ts` |
| Regression evidence | Associated API tests, Mobile model/draft/review tests, `platform_settings_scaffold_test.dart`, `unified_platform_settings_test.dart`, existing uploader interaction/scroll helpers |
| Installer/tool follow-up and regression checks | `apps/mobile/tool/android-install-volume.ps1`, `launch-postdee-android.ps1`, `postdee-staging.ps1`, `test-android-install-volume.ps1` |
| Documentation | `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `apps/mobile/README.md`, this record |

## Primary provider evidence

- [Instagram AI-media declaration, feed and cover](https://www.postpeer.dev/docs/platforms/instagram)
- [Facebook Page Video declaration, drafts and cover](https://www.postpeer.dev/docs/platforms/facebook)

These optional fields are provider-supported according to current docs. Mocked
mapper/route tests do not prove a real connected account's publication or label.
