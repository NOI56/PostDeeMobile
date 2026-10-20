# Remember publishing settings per connected channel

สถานะ: LOCAL VERIFIED — automated checks and YouTube native Save/restart/Cancel
pass; Staging APK12027 is installed. After login, a fresh YouTube composer
restores saved visibility/audience across a native process restart while
clip-specific declarations remain unanswered. Final Home shows the existing
draft entry, quota and connected-channel count.
This feature has not been merged to main, pushed or deployed to a server.
Native receipt updated on 2026-10-20; build/install evidence is from 2026-10-18.

## Request and baseline

จำการตั้งค่าที่ใช้ซ้ำ เพื่อไม่ต้องกรอกใหม่เมื่อสร้างคลิปครั้งถัดไป
โดยร่างคลิปเดิมยังใช้ค่าของร่าง และการกดยกเลิกไม่เปลี่ยนค่าที่จำไว้

- Canonical `main` and fresh `origin/main`: `644fea90bb4b0b70078cf2f3642514d57a434447`,
  initially 0 ahead / 0 behind; branch `codex/remember-platform-defaults`.
- Reuse the attached `admin-usage-accuracy/PostDeeMobile` worktree. Preserve its
  three pre-existing Windows generated-plugin metadata changes and unrelated work.
- Existing platform settings are initialized per composer; local publish drafts
  already preserve same-clip choices and reset current capability/consent proof.

## Reusable settings and fresh clip declarations

| Platform | Remember for the next new clip | Review per clip |
| --- | --- | --- |
| TikTok | Inbox / Direct mode | Manual privacy and interactions, commercial/AI disclosure, music/policy confirmation, creator capabilities |
| YouTube | Visibility and explicit audience choice | Title, synthetic-media answer, community certification |
| Instagram | Share to feed | AI disclosure and cover |
| Facebook Page Video | Publish / Page draft | AI disclosure and cover |

TikTok explicitly requires no default privacy value and interactions initially
off: [Content Sharing Guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines).
YouTube allows a channel audience default with per-video overrides:
[audience settings](https://support.google.com/youtube/answer/9527654?hl=en).
PostDee saves its own editable local preference; it does not fetch or modify
YouTube Studio defaults. Studio's browser-upload defaults do not automatically
apply to mobile/editor uploads:
[upload defaults](https://support.google.com/youtube/answer/2660027?hl=en).

## Implementation boundary

- Allowlisted SharedPreferences data only, scoped by API endpoint, stable owner
  and verified connection identity/revision; never use the display name as a key.
- Load when opening a fresh platform form and before entering review, including
  the progress-control shortcut. This honors optional Instagram choices and does
  not silently replace remembered TikTok Direct with Inbox when a sheet is skipped.
  Keep same-form saved choices and restored drafts ahead of defaults. Distinguish
  an actual restored draft from a new form that has merely been saved locally;
  saving early or selecting another platform after saving cannot skip defaults.
  Loading is cancellable in the sheet and bounded to eight seconds before review;
  stale owner, connection or form results cannot replace current intent.
- Persist only after explicit platform Save. Storage errors leave the current
  clip usable and explain that remembering did not succeed. Cancel/dismiss does
  not write. Explicit saved preferences can finish persisting after the
  composer closes when its auth lifecycle is still current. Account deletion
  clears the deleted owner's local defaults.
- Serialize writes, guard auth lifecycles and invalidate pending reads/writes
  during owner cleanup. Corrupt or unsupported stored values fail closed.
- Clip replacement carries only reusable choices with their source-channel
  binding and resets clip-specific declarations. Replacing the clip of a restored
  legacy draft reads current channel preferences afresh, because that draft has
  no stored channel-default provenance. Do not auto-select destinations or send anything.
- No dependency, API field, server behavior, database, plan, entitlement,
  feature-flag or environment change; no migration or API deployment required.

## Verification

Tests were written before runtime changes. The initial widget compile RED records
the missing Uploader constructor dependency, not a functional storage failure.
The first targeted run found an immediate failed-future handling bug, which was
fixed by consuming storage errors before the modal's first frame. Separate new
draft regressions reproduced remembered Instagram `false` becoming `true` before
the restored-draft provenance fix. Independent source reviews covered the
allowlist, owner/channel isolation, async writes and optional-sheet paths.

The initial complete targeted batch passes **131**, with one optional visual-preview case skipped,
including **23** new widget cases and **20** store cases. The existing unified
settings and shell/account-deletion tests also pass in this batch. Evidence:
`D:\PostDeeMobile\artifacts\remember-settings-tooling-20261018\remembered-widget-targeted-final.log`;
the eight relevant source/test files match their D: verification copies by SHA-256.

The first full run passes 2,479 with two optional skips and finds one old recovery
test that confirms a replacement video without re-answering its declarations.
The updated test first proves confirmation is disabled, then explicitly answers
the new clip's fields and retains every existing assertion: same request ID,
changed media fingerprint/key, retained draft and server 409 rejection. Runtime
recovery is unchanged. The expanded targeted batch then passes **144**, with one
optional preview skipped. Evidence: `remembered-recovery-targeted-final.log`.

### Exact-source automated and build receipt

- Runtime/test source: `5ac9b5b7d3b81fa92c336055e357d6d5dae27175`, following
  feature commit `0312fa1` and recovery-test update `50301f5`. The final commit
  adds required control-flow braces; no additional runtime change follows it.
- Full Mobile suite: **2,480 passed / 2 optional preview skips**, exit 0.
  `full-test-delivery.log` records the final exact-source run. The recovery test
  retains its original lost-response/idempotency checks after explicitly
  completing the replacement clip's fresh declarations.
- `flutter analyze --no-pub`: **No issues found**, exit 0; see
  `analyze-delivery.log`. Expanded targeted verification remains **144 passed /
  1 optional preview skip**, including 23 new widget cases and 20 store cases.
- Local SDK: Flutter **3.44.1** / Dart **3.12.1**. This is distinct from the
  previous release CI's Flutter 3.47.7 / Dart 3.13.5; no new CI run is claimed.
- **571** source/input file hashes match the C: worktree's D: verification
  snapshot before and after the build. Manifest:
  `D:\PostDeeMobile\.tmp\remember-platform-defaults-verify-20261018\source-manifest-delivery.json`.
  D: temp and Gradle cache paths and process-only memory/worker limits were used
  because C: space was constrained. No SDK upgrade, cache replacement or source
  configuration change was needed.
- Staging build exits 0 in **612.8 seconds**:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk --no-pub --target-platform android-x64 --build-number 12027
  ```

- Artifact: **197,044,698 bytes**, SHA-256
  `18230e861b8c792e65171a8091aa7eee2771e800dac13700b2efb3d8a27c1d0b`;
  `com.postdee.postdee_mobile.staging`, versionCode **12027**, versionName
  `0.1.0-staging`. The Flutter engine in this verification APK is **x86_64 only**;
  existing ARM plugin libraries do not make it an ARM delivery build.
- Signature v2 and 16 KiB zip alignment pass. Signer certificate SHA-256:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
- Actual APK resources/kernel match Staging API
  `https://postdee-api-staging.onrender.com`, Firebase project
  `project-798caf7e-85b8-45e3-af7`, enabled Firebase auth and RevenueCat,
  disabled local mock auth and experimental AI hook/beat sync, the existing
  public Test Store configuration and the remembered-settings store. No secret
  values were copied into this record. Detailed receipt:
  `apk-verification-12027.json`, with build/signature/resource logs beside it.
- Existing plugin Kotlin/Java deprecation warnings remain; they did not fail
  this build. No API code, contract, schema, dependency, feature flag, billing
  rule or environment setting changed. No migration or API deployment is needed.

### Installation and native QA receipt (2026-10-20)

The existing guarded Android updater updated emulator `emulator-5556` from
12026 to **12027** without uninstalling, clearing data or moving its storage.
The helper's immediate post-install read reported a package-path/volume mismatch.
No second installation was attempted: an independent package inspection followed
by **three stable helper probes** confirmed version 12027, UID **10190** and the
same mounted adopted volume `470668ed-4e40-4628-acb4-8704efc6b257`.
The cause of the transient read mismatch is not confirmed. Evidence:
`native-package-before.json` and `native-package-after.json`. The candidate APK
hash and verified signature plus Android's accepted update establish the install
path; the installed file itself was not readable for a new byte-hash comparison.

The initial post-update Home snapshot (`native-updated-home.xml`/`.png`) retains
Pro **242/250**, the existing draft `fhhhhh`, **2/4** connected channels and
existing post history. The subsequent `native-fresh-composer.xml`/`.png` shows
login; the cause of that transition was not confirmed. On resuming the emulator
on **2026-10-20**, its adopted volume was mounted again and read-only package
checks confirmed the same UID **10190**, volume UUID and version **12027**;
see `native-resume-package.json`. No reinstall, data clear or storage migration
was used for this resumed check. After the user logged in, native feature QA
continued on the same installed build.

- Create a fresh controlled QA clip and explicitly save YouTube **Private /
  Not made for kids**, completing that clip's declarations only to enable the
  platform-settings Save. Leave the composer without saving a new draft.
- Force-stop and reopen the app, with process PID changing **5593 → 9124**.
  Create a second fresh composer, titled **Remember settings QA again**.
- Reopen YouTube settings and confirm **Private / Not made for kids** are
  restored. The new title is retained, the synthetic-media answer remains
  unanswered, community certification is unchecked, and Save is disabled until
  the new clip's declarations are completed. The local-memory explanation is
  visible. Evidence: `native-yt-restored-top-stable-20261020.png`/`.xml` and
  `native-yt-restored-declarations-20261020.png`/`.xml`.
- Change the audience to **Yes**, tap **Cancel**, then reopen settings in the
  same composer: **No** remains selected. This confirms native Cancel/reopen
  preserves the saved choice. Evidence: `native-yt-cancel-change-20261020`,
  `native-yt-cancelled-20261020` and `native-yt-cancel-reopened-20261020`
  `.png`/`.xml` pairs. No raw-preference inspection is claimed.
- Leave the second QA composer without saving a draft. The final Home retains
  **Pro 242/250**, existing draft **fhhhhh**, **2/4** connected channels and
  existing post history; the composer draft list still contains two entries.
  Evidence: `native-final-home-20261020.png`/`.xml`. That immediate screenshot
  caught thumbnail loading and a grey Continue before its XML already reported
  enabled. A later read-only stable capture confirms the loaded thumbnail and
  green/enabled Continue, matching the initial Home:
  `native-final-home-stable-20261020.png`/`.xml`. The draft was not opened or
  changed; media playback and the Continue navigation flow were not exercised.
- PID-scoped crash summaries for both runs report **0 FATAL EXCEPTION / 0
  Unhandled Exception**. See `native-before-restart-crash-summary.json` and
  `native-after-restart-crash-summary.json`. These are bounded QA log checks,
  not a claim that all production crash paths have been tested.

The complete native receipt is `native-resume-final-receipt-20261020.json`.
Private was also the initial default, so its native display alone does not
distinguish persisted visibility from fallback. The initially unanswered,
explicitly saved **Not made for kids** choice returning after a real process
restart provides the positive persistence check; non-default visibility values
are covered by automated tests. Home initially failed to load connections once;
one visible Try Again action recovered the existing two channels. The resumed
boot, connection retry and login did not require installation or data changes.

No real platform post, AI generation, purchase, new draft save or account
deletion was performed for this verification. Instagram/Facebook coverage is
automated fixture coverage; neither a connected native Meta flow, ARM device
nor iOS build was tested for this feature. TikTok privacy/interactions and all
clip-specific disclosures/confirmations still require fresh manual choices.

### Changed files and delivery boundary

- Store and uploader: `platform_publish_defaults_store.dart`,
  `uploader_screen.dart`, `platform_settings_scaffold.dart`,
  `tiktok_publishing_settings_sheet.dart`.
- Account cleanup: `postdee_shell.dart`.
- Verification: `platform_publish_defaults_store_test.dart`,
  `remembered_platform_settings_test.dart`, `postdee_shell_test.dart`,
  `publish_draft_flow_test.dart`.
- Documentation: root README, ROADMAP, API and ARCHITECTURE, Mobile README and
  this work record.

The three pre-existing Windows generated-plugin metadata changes remain
uncommitted and excluded from this feature. The verified integration baseline
is still `644fea90bb4b0b70078cf2f3642514d57a434447`; this receipt does not claim
remote freshness beyond the recorded baseline checks. Runtime source remains
local on `codex/remember-platform-defaults`. There is no main merge, push,
new CI run or server deployment for this feature. Automated verification and
native YouTube Save/restart/Cancel with final Home preservation are complete.
Connected TikTok/Meta native flows, physical ARM and iOS remain outside this
verification scope; no release to main or a remote service was performed.
