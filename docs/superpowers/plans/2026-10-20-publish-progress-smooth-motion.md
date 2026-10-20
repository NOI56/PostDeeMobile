# Smooth activity feedback during publishing

สถานะ: LOCALLY VERIFIED / STAGING APK12028 INSTALLED — selected the first (เรียบเนียน)
full-screen mockup. Focused/full tests, final controlled render, analysis and
Staging APK12028 build pass. Guarded native update and signed-in Home preservation
pass without submitting a real post.
No main merge, push or server deployment is part of this delivery.

## Baseline and scope

- Fresh `origin/main`: `644fea90bb4b0b70078cf2f3642514d57a434447` on 2026-10-20.
- Start from `777db096ecbab93dcaa228c9aa0d18c3c86bd94f`, which contains the
  locally verified remembered-settings feature. Keep that feature and the three
  unrelated Windows generated-plugin metadata changes intact.
- Work on `codex/publish-flow-smooth-motion`; no merge, push or deployment is
  part of this selection.
- The selected mockup is the full publishing-progress screen, rather than the
  previous Home/Calendar post-card animation. Change only its presentation.

## Intended behavior

Keep the real reported stage/fraction, stage-progress semantics, error/retry,
back-navigation guards and truthful accepted/queued/provider outcomes. Add an
upload emblem with one gently orbiting dot, a light clipped inside the filled
portion of the real progress rail, destination labels and a compact three-step
summary (preparing, uploading, creating a queue). Do not advance percentages or
report publication merely because an animation completes.

Use one retained animation clock for the dot and light. Pause/reset it for
background lifecycle, disabled TickerMode and reduced motion; dispose it when
the pending view ends. Stage updates must not repeat publishing or restart the
clock unnecessarily. The layout must fit a narrow screen and enlarged text.

No dependency, API contract, schema, entitlement, provider configuration or
feature-flag change. README/ROADMAP/ARCHITECTURE/Mobile README will reflect the
final local status. API.md was checked and requires no contract update.

## Verification plan

Write regression tests first, including fixed progress while the activity loops,
one publish operation, motion guards, truthful completion/error and small-screen
layout. Run the focused tests, complete Mobile suite and analysis on the exact
source, then build Staging Android x86_64. Prefer a controlled local render for
the pending screen so verification does not create a real social post. Verify
the installed Staging package/environment and retain the user's data.

## Verification receipt

- Runtime implementation: `a5aefac4f421e26293cdaab1e6ac09138aacb4d6`.
  Exact delivery candidate: `5eeb1a7f7441fb98a632a1b27751fbb45e75697e`.
- Tests-first RED: 17 existing cases pass and eight new cases fail because the
  orbit, steps and destination chips do not exist yet. The implemented focused
  batch passes **51/51**, including the draft-flow and owner-change preflight
  checks. Only six deliberately pending waits switch to bounded pumps; their
  original assertions and post-completion settlement remain intact.
- Full Mobile suite: **2,488 passed / 3 optional preview skips**, exit 0 in
  171.8 seconds. Real progress does not advance with elapsed animation time;
  publishing is called once. Lifecycle/reduced-motion/TickerMode, outcome
  disposal, all nine stages and 320dp / 200% text coverage pass.
- Full-suite runtime and all non-preview tests match delivery candidate
  `5eeb1a7` byte-for-byte. After that run, only the skipped optional render
  harness and documentation changed; the final harness is explicitly run
  separately. See `tested-to-delivery-comparison.json`.
- Use a local production-widget render fixture, not a real post. The initial
  harness omitted the app's global theme synchronization; it was corrected to
  match the real Light/Dark palettes. Outcome button fonts fall back to Ahem
  in the widget tester, so final PNG captures cover the pending screen only;
  outcome behavior remains asserted without changing its production UI.

Evidence is under
`D:\PostDeeMobile\artifacts\smooth-publish-progress-20261020`.

### Final controlled render and analysis

- The final opt-in `publish_flow_preview_test.dart` run passes **1/1**, exit 0,
  5.4 seconds (`targeted-preview-delivery.log`). Five actual production-widget
  PNGs are in `preview-final/`: `publish-smooth-queue-90-frame-1.png`,
  `publish-smooth-queue-90-frame-2.png`, `publish-smooth-upload-55.png`,
  `publish-smooth-queue-90-dark.png` and
  `publish-smooth-queue-reduced-motion.png`. They cover two animation frames at
  unchanged 90%, 55% upload, the app's Dark palette and static reduced motion.
- Analysis reports **No issues found**, exit 0; analyzer time 13.3 seconds
  (15.4 seconds including the wrapper), in `analyze-final.log`.
- Local Flutter **3.44.1 / Dart 3.12.1** were used. This is local verification,
  not a new remote CI run or a claim about the earlier CI SDK version.
- The broad suite was not repeated after fixture-only adjustments: comparison
  verifies that every runtime input and non-preview test matches the successful
  2,488-case suite. Only the skipped opt-in harness and documentation changed;
  the final harness was then explicitly executed successfully.

### Android build and package verification

- Exact Staging x86_64 build exits 0 in **195.8 seconds**:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\postdee-staging.ps1 -Command build-apk --no-pub --target-platform android-x64 --build-number 12028
  ```

- All **647** copied C-source/D-verification input SHA-256 hashes match before
  and after build (`source-manifest-delivery.json` and
  `source-verification-delivery.json`). Resource limits affect only the build
  process; no SDK/dependency/configuration upgrade was made.
- Candidate APK: **197,047,058 bytes**, SHA-256
  `26b491c65ad9f4d81d06bad5df0608860fe5ae9e1c5d79de19214dacf9d30081`.
  Package `com.postdee.postdee_mobile.staging`, versionCode **12028**,
  versionName `0.1.0-staging`. Flutter engine is **x86_64 only**; other plugin
  libraries do not provide an ARM Flutter runtime.
- Existing v2 signature passes, certificate SHA-256
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`;
  16 KiB zip alignment passes. Evidence: `apk-signature-12028.txt`,
  `apk-alignment-12028.txt` and `apk-verification-12028.json`.
- Actual compiled API remains `https://postdee-api-staging.onrender.com`.
  Firebase project remains `project-798caf7e-85b8-45e3-af7` and its Android app
  ID remains `1:948899042298:android:945921b397cb7f261a4a43`; Google server
  client configuration matches. Firebase auth and RevenueCat remain enabled,
  local mock auth and experimental AI hook/beat sync remain disabled, and the
  Staging banner remains enabled. Existing public SDK key values were not
  printed or copied into documentation. Actual kernel checks find the motion
  widgets and retained remembered-settings store.

### Native delivery status and limits

- The guarded updater successfully updates **12027 to 12028** on
  `emulator-5556`. No transient package-probe failure occurs on this update.
  Three post-update probes retain UID **10190**, adopted volume UUID
  `470668ed-4e40-4628-acb4-8704efc6b257` and report versionCode **12028**.
  The first-install time is retained. No uninstall, data clear or storage
  migration is performed.
- Signed-in Home opens successfully. `native-after.png` / `native-after.xml`
  retain Pro **242/250**, existing `fhhhhh` draft with its thumbnail and enabled
  Continue action, **2/4** connected channels and the existing history. No draft
  save, real post, AI generation or purchase is performed during this check.
- Opening an empty composer confirms the existing draft count is still **2**;
  closing it without saving returns to Home. Final evidence is
  `native-final.png` / `native-final.xml` and `native-final-receipt.json`.
  The final app PID **11754** has **0 FATAL** and **0 unhandled Dart** matches in
  the collected process log. Immediate UIAutomator snapshots briefly return a
  null root during screen transitions; subsequent captures succeed, with no app
  crash. This automation timing issue does not alter the app or its data.
- Native smoke verifies installation/environment and retained data. The pending
  screen's motion, real-stage mapping, reduced motion and truthful outcomes are
  verified by the hash-matched production-widget fixtures and tests, rather
  than submitting a real provider post merely to expose the progress screen.
  The candidate APK hash is verified before installation; a fresh installed-byte
  hash is not claimed.

The change affects only Mobile presentation. There is no API, database,
entitlement, dependency, flag or provider configuration change; no migration or
server deployment is required. No real post, AI generation or purchase is used
for the motion verification. Physical ARM and iOS builds are not delivered.
Main/origin main remain at the verified `644fea9` baseline; this feature and the
prior local remembered-settings feature remain on the local feature branch.
The three pre-existing Windows generated-plugin metadata changes are preserved
and excluded from this work.

### Changed files

- Runtime: `apps/mobile/lib/features/uploader/publish_flow_screen.dart`.
- Tests: `publish_flow_screen_test.dart`, `publish_draft_flow_test.dart`,
  `uploader_platform_preflight_test.dart` and the optional
  `publish_flow_preview_test.dart`, under `apps/mobile/test/`.
- Documentation: root README/ROADMAP/ARCHITECTURE, Mobile README and this record.
  `API.md` was checked; its contracts are unchanged.
