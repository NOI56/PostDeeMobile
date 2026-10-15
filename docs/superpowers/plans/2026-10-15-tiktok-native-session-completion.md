# TikTok native session completion with background Flutter engines

## Verified baseline and reported failure

- Start from freshly fetched `origin/main`
  `9189e7b60b2d5a641c079ed03ed52e9a1f59904b` in clean managed worktree
  `tiktok-native-session-results`, branch `codex/tiktok-native-session-results`.
  Preserve the generated Windows changes and QA artifacts in other worktrees.
- At diagnosis, Staging API runtime was `0f2941b` and the installed Staging APK was
  version 12020, SHA-256
  `84468A674619A4FEAF95C36275177ECDE8CFBD344692B4AC00FA814F47F801E9`.
- The user tries a TikTok-only post and receives the generic local preparation
  error. This occurs before remote upload or publication. The selected media
  is the existing QA video, 30,199 bytes, 180x320, about 1.064 seconds.
- Read-only PID-scoped logs show the UI FFmpeg plugin attached at 11:31:57 UTC,
  then Firebase creating a background FlutterEngine and a second plugin instance
  at 11:31:59 UTC. The source FFprobe session finishes at 11:49:51 UTC but its
  completion event targets a null event sink. No video encoder starts.
- In the pinned FFmpeg plugin 2.3.2, each engine overwrites the native global
  session-completion callbacks. A background engine without a Dart event
  subscriber can therefore receive the UI session's completion. The existing
  Dart adapter waits only for that callback and eventually times out.
- The earlier five-case native harness has one engine and warmup commands. Its
  media checks remain useful, but do not cover this production multi-engine
  completion failure. The default temporary-directory implementation is the
  same in both harness and product and is not the diagnosed cause.
- A second required compatibility issue is verified against TikTok's current
  [media transfer guide](https://developers.tiktok.com/docs/en/content-posting-api-media-transfer-guide):
  both video dimensions must be between 360 and 4096 pixels. The selected QA
  clip's 180x320 frame is below that range. Fixing callback delivery alone would
  prepare a file that still fails the platform's documented size restriction.

## Minimal implementation and preserved behavior

1. Add production-adapter regressions before changing code: native method calls
   complete without any EventChannel completion, and known-session cancellation
   still works while execution is pending.
2. Create each FFprobe/FFmpeg session first so its ID is available immediately.
   Run it through the plugin's per-session MethodChannel execute operation and
   read its return code/output after that operation completes. Android executes
   these calls on its executor; iOS dispatches to its background queue.
3. Normalize only the upload copy's dimensions proportionally into TikTok's
   360–4096 range, using even pixels and the same expected target for encoding
   and validation. The selected 180x320 clip becomes 360x640. Valid sizes retain
   their existing even-floor behavior; oversized frames downscale. An impossible
   extreme aspect ratio fails clearly before encoding. Do not crop, pad, extend
   duration, replace source media, or change audio content for this normalization.
4. Retain the existing bounded futures, owner-change checks, ID-scoped cancel,
   H.264/AAC CFR30, decoded-prefix validation, source media, local draft,
   immutable request ID, and duplicate-post guards. Advance the local preparation
   receipt policy to `tiktok-cfr30-h264-aac-v2` so old receipts without validated
   target dimensions cannot silently bypass preparation. Historical receipts use
   the existing explicit-new-attempt confirmation and keep their immutable IDs.
5. Keep Firebase messaging/background engines enabled. Do not replace global
   callbacks, weaken validation, add arbitrary delays, or modify the pinned
   plugin/dependencies. Calendar, schedules, billing, and server contracts stay
   unchanged. No migration, provider flag, API deployment, or Production change
   is needed for this mobile-only correction.

## Verification and delivery boundary

- Reproduce the old callback failure in an isolated Android harness with two
  engines and no subscriber on the second engine. Verify the exact fixed helper
  in cold-first and two-engine cases, with real controlled media and retained
  cancellation/timeout behavior. Do not post a clip from that harness.
- Run the new adapter regressions, the existing TikTok/uploader/draft regressions,
  the complete Mobile test suite and analysis. Build the exact Staging APK and
  compare package, API/Firebase configuration, signer, permissions, and flags.
- The user's current composer and account are preserved during diagnosis and
  isolated tests. No send/retry, save, restart, reinstall, data/cache clear, or
  account reconnection is performed on the user emulator during diagnosis.
- A passing local preparation check does not prove actual TikTok provider
  delivery. Record any required user action separately and do not publish on
  the user's behalf without explicit authorization.

## Verification receipt

- Baseline production-adapter regression fails on `9189e7b`: native execution
  completes, but without an EventChannel completion the old source probe times
  out after 300 ms. The retained RED log is
  `D:/Temp/runtime-session-baseline-red.log`.
- After the minimal native-adapter correction, all nine new MethodChannel
  regressions pass without injected video runners/probes or any completion event.
  They cover pending source execution, full source/render/decoded-output flow,
  probe/render timeout cancellation of only the known session, failed/null return
  codes, native execution errors, and missing IDs. GREEN log:
  `D:/Temp/runtime-session-native-adapter-green.log`.
- Callback-only checkpoint helper SHA-256:
  `367221B88F42DA18FACB420D0BE690CD3D4DBFEEF61C8BD15352A98EA23D53F7`.
- The callback-only checkpoint passes all 2,235 Mobile tests in 4m06s with
  `flutter test --no-pub --concurrency=4 --reporter=expanded`. This is before the
  new size-normalization behavior; the complete suite must run again after that
  change. Log: `D:/Temp/runtime-session-mobile-full-20261015.log`.
- Isolated two-engine native reproduction with the old helper `F89FFF91...`
  and the exact QA file fails after about 35 seconds although source FFprobe is
  completed with return code 0 and output present. Single-engine cold control
  succeeds. The callback-only `367221B8...` helper passes all six two-engine
  cases (QA clip plus the earlier 6/30/60 FPS, audio/silent, and three-second
  fixtures), with actual decoded-frame/PTS/audio validation. That checkpoint
  proves callback correction, but its unchanged 180x320 QA output is not a
  platform-compatible size and is not the final candidate.
- Size-normalization RED is retained at
  `D:/Temp/runtime-session-dimensions-red.log`: the previous helper rejects the
  required 180x320 to 360x640 output. Final dimension tests cover the minimum,
  maximum, odd/even rounding, parsed rotation, impossible aspect ratios, wrong
  rendered geometry, v2 receipts, and byte-for-byte original source preservation.
  The existing uploader receipt-recovery test additionally checks both missing
  and v1 receipts are preserved and blocked until explicit new-attempt approval.
- All 85 final targeted regressions pass across six test files. Log:
  `D:/Temp/runtime-session-targeted-final-green.log`. Final helper SHA-256:
  `ADF16A1CDC65E1155497C1D4882EB6C68552A9AD07052333386E40FCE44BEAED`.
- The exact final helper passes all six isolated two-engine native cases. The
  actual selected QA clip produces 360x640 H.264/AAC, average/real rate 30/1,
  30 actual decoded frames and prefix count 30. Other fixtures keep their existing
  360/720/1080 geometry; three-second video has 90 full frames/prefix 60. PTS and
  non-silent AAC energy checks pass, silent source stays silent, and original
  input bytes remain unchanged in every case. Fresh single-engine cold start
  also passes. ID-scoped cancellation stops the active helper render with
  return code 255 while an unrelated simultaneous control finishes with code 0.
  Heartbeat/frame observations confirm a responsive harness, not a performance
  benchmark. JSON receipts are under
  `D:/PostDeeMobile/.tmp/tiktok-fps-native-probe-20261015/session-results/`:
  `final-dual-adf16a1.json`, `final-cold-adf16a1.json`, and
  `final-cancel-dual-adf16a1.json`.
- Final `flutter analyze --no-pub` passes with no issues in 32.2s. Log:
  `D:/Temp/runtime-session-mobile-final-analyze-20261015.log`.
- The complete final Mobile suite passes all **2,252 tests** in 5m11s with
  `flutter test --no-pub --concurrency=4 --reporter=expanded`, exit 0. The exact
  final helper hash remains `ADF16A1C...44BEAED`. This final run includes both
  the native completion and size-normalization/legacy-v1 receipt changes. Log:
  `D:/Temp/runtime-session-mobile-final-full-20261015.log`.
- Exact Staging x86_64 debug APK builds in 168.4s using the validated
  helper with `--split-per-abi`, `--target-platform=android-x64`, and base build
  number 8021. The APK is 127,730,770 bytes, SHA-256
  `611A36D0483697396EAB72C0F0EDFCD9E7147DD5F5344DDCDCAC4AC51CCF114F`,
  at `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`. Build log:
  `D:/Temp/runtime-session-staging-apk-12021-20261015.log`.
- Source and tests are committed locally as `656b2bd`, based on `9189e7b`.
- The APK is Staging package `com.postdee.postdee_mobile.staging`, versionCode
  **12021**, versionName `0.1.0-staging`, x86_64, min SDK 24/target SDK 36.
  Its signer, 14 permissions, sole Staging API origin, Firebase project/app/OAuth
  resources and RevenueCat Test Store configuration match installed 12020.
  No secret values are recorded. The installed code hash matches `611A36D0...`.
- The exact product APK passes cold startup on isolated emulator 5558 and the
  user emulator 5556, with no fatal/unhandled/Flutter errors in the observed
  intervals. Isolated emulator 5558 is then stopped. These APK checks verify
  launch and configuration; native preparation is verified separately in the
  exact-helper harness. Neither verifies social publication or physical-device
  performance. Receipts: `STAGING12021_SMOKE_RECEIPT.md` and
  `USER12021_UPDATE_RECEIPT.md` in the session-results directory above.
- The user emulator updates in place to 12021. Package UID 10190 and original
  first-install timestamp remain; no uninstall, wipe, cache/data clear or account
  reconnection is performed. The original public QA media retains its SHA-256
  `3717CF4B44388EB2380994CD99060F83181E8A4D35A94A40DE2CFC899A232D5A`.
- Read-only GUI inspection confirms the signed-in account, the original saved
  draft/clip/caption, TikTok account `Welcome` selected, and the draft open at
  review. No publication send/retry, draft save, billing action or new post is performed.
  Proof: `session-results/user12021-restored-review.png` under the harness path.
- Restoring the draft briefly shows an existing stale connection warning: restore
  runs before connection loading, and the later success does not clear that
  error string. Navigating to Channels clears it and shows the selected account.
  This uploader behavior is unchanged from `9189e7b`; it remains a UX follow-up.
- Fresh Home and Profile show Free with 0/3 available; Profile specifically shows
  the phone as unverified. Existing free-plan rules require phone verification
  for any available posting units. Closing the unchanged draft to inspect the
  account does not trigger a save/discard prompt or remove the saved draft.
  The app is left on Account so the user can complete verification themselves.
  Proof: `session-results/user12021-account-ready.png` under the harness path.
- Profile initially fails to load connections. One read-only reload recovers to
  2/4 connected at 12:30 UTC without reconnection or any saved change. Public
  Staging `/health` and `/ready` both return HTTP 200/status ok at 12:29:30–31 UTC.
  Scoped Render request metadata for `/social-connections` at 12:27–12:30 UTC is
  empty, so no server error cause is asserted from that transient read failure.
- The old composer had a cached Pro snapshot. The authorized RevenueCat Dashboard
  is accessible; the latest sandbox Pro Monthly transaction expires on October
  15 at 12:13 UTC. That customer is not conclusively matched to the current app's
  Firebase UID, so expiry is not asserted for this account. No subscriber data,
  entitlement, purchase, or subscription setting is changed. Posting re-reads
  eligibility before preparation; passing native checks does not grant eligibility.
- At completion of local native verification, public TikTok publication,
  physical Android devices and iOS runtime remain unverified. No provider flag,
  billing mutation or Production delivery is performed for this native fix.

## Subsequent authorized main and Staging delivery

- The user-authorized integration fast-forwards and pushes main from `9189e7b`
  to `7a55fe8a0b4152ee4ad4d9a5238c918656b67a61`, including native source
  `656b2bd`, verification docs `744ebf0`, and the subsequent backend-only Inbox
  result correction `7a55fe8`.
- Exact-head [CI `38741265826`](https://github.com/NOI56/PostDeeMobile/actions/runs/38741265826)
  passes Backend API (119 files / 1,947 tests) and Mobile (2,252 tests and clean
  analysis). Push CI skips APK building/uploading. The installed APK12021,
  helper SHA-256 `ADF16A1C...44BEAED`, and exact local native/APK receipts above
  remain unchanged; this delivery does not claim a new APK or native retest.
- Staging deploy `dep-db8d6gss728c7391ajp0` is Live at
  `2026-10-15T13:23:04.671572Z` on that exact source. All 18 migrations are
  applied with none pending; the empty-backlog guard passes. Health/readiness
  return HTTP200 at 13:23:51 and 13:25:33 UTC. The bounded post-Live log query
  has no errors/5xx, with incomplete request coverage.
- Environment/provider configuration, flags and Production remain unchanged.
  The observed user-created Inbox handoff and separate historical receipt repair
  belong to `2026-10-15-tiktok-inbox-delivery-status.md`. Its one-time guarded
  repair completes around 13:36 UTC, changing only the matched parent/receipt
  with DRAFT semantics. Independent readback and APK12021 Calendar/detail show
  `ส่งเป็นร่างแล้ว` without error at 13:37 UTC. All five unresolved operation
  markers, quota and other immutable data remain unchanged; no provider resend
  or queue replay is performed. Proofs `user12021-inbox-repaired.png` and
  `user12021-inbox-repaired-calendar.png` are in the session-results directory.
  This corrects PostDee history; user-side TikTok Inbox confirmation and public
  publication remain unverified. Physical Android and iOS runtime also remain
  unverified.
