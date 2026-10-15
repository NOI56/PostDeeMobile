# TikTok media preparation and complete Calendar activity

## Baseline and verified problem

- Canonical remote `main` was fetched at
  `3725744b1967760ff6351eee1e49be598df95402` before implementation. The managed
  worktree uses branch `codex/publish-calendar-tiktok-fps`; existing dirty work in
  other checkouts is preserved.
- Staging is already enabled for real PostPeer publishing by the user's separate
  authorization. The live source is `3725744`, publisher `postpeer`, memory queue,
  one instance, and the empty-backlog activation guard is retained. This fix does
  not change those flags or Production.
- A read-only lookup of the user's existing mixed-destination post confirmed
  YouTube succeeded and TikTok failed. PostPeer reports
  `TikTok publish failed: frame_rate_check_failed`. TikTok's official media guide
  requires 23–60 FPS; the exact frame rate of this uploaded file has not been
  independently measured. No post is resubmitted or database record rewritten.
- That immediate post has `scheduledAt = null`. Calendar calls
  `GET /posts?scheduled=true`, which excludes it before client filtering. The
  existing scheduled DTO also rejects a missing schedule. Refresh and the Shorts
  filter cannot recover records omitted by this fetch.

## Intended implementation

1. Add regression tests before each behavior change.
2. Prepare TikTok-selected media after optional watermarking and before upload:
   constant 30 FPS, supported H.264/AAC output, and a validated video stream. Keep
   source media, audio, dimensions, cover selection, and draft ownership intact.
   A failed encoder or output probe must stop before upload rather than publish
   an invalid or audio-only file.
3. Reuse uploaded TikTok media only when its persisted preparation policy proves
   that it passed the new checks. Preserve immutable client request IDs and the
   logical source-media fingerprint. Historical incompatible receipts must fail
   visibly without silently changing an already submitted intent or reposting.
4. Add a Calendar loader for all owner-scoped posts. Use nullable schedules and
   real activity dates; retain the strict scheduled-only loader and mutation API
   for existing callers. Immediate and partially published posts appear on the
   appropriate local day, including under their selected platform filter.
5. Keep reschedule/cancel/publish-now controls restricted to actual queued
   scheduled posts. Finished activity opens the existing read-only detail flow.
   Preserve foreground/owner guards, refresh, pending polling, and motion.
6. Translate only the allowlisted TikTok frame-rate failure into a fixed public
   message. Retain generic messages and secret-free logs for unknown provider
   errors; do not expose raw provider bodies, account IDs, media URLs, or tokens.

## Compatibility and delivery

- No database migration, new subscription rule, or provider posting mode is
  intended. TikTok remains inbox-draft mode; YouTube and other destination
  settings and duplicate-post guards remain unchanged.
- Backend error copy remains in the existing `errorMessage` string field.
  Existing generic historical failures cannot be retroactively diagnosed from
  that field alone; this change must not relabel them by guessing.
- The Calendar change uses the existing unfiltered `GET /posts` contract. Update
  `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`, and the Mobile README to
  distinguish complete Calendar activity from the historical scheduled-only UI.
- Verify targeted regressions, complete Mobile tests/analyze, complete API
  tests/typecheck/build/Prisma validation, and the exact Staging APK. Native
  preparation checks must use controlled local media without social posting or
  production data changes. Do not claim real delivery from unit tests or API
  readiness alone.
- No merge, push, source deployment, account mutation, or actual social retry is
  included in implementation-only authorization. Present a concrete tested
  result before requesting any further delivery action that needs authorization.

## Changed areas

- Calendar model/network loading: `apps/mobile/lib/core/network/postdee_api_client.dart`.
- Calendar dates, queued actions, and detail navigation:
  `apps/mobile/lib/features/calendar/calendar_screen.dart` and
  `apps/mobile/lib/features/shell/postdee_shell.dart`.
- TikTok preparation and safe draft/upload reuse:
  `apps/mobile/lib/features/uploader/tiktok_video_preparer.dart`,
  `uploader_screen.dart`, `publish_draft.dart`, and `publish_draft_store.dart` in
  the same feature directory.
- Safe provider failure mapping: `apps/api/src/workers/postPeerPublisher.ts`,
  `apps/api/src/workers/publishWorker.ts`, and
  `apps/mobile/lib/features/posts/post_detail_screen.dart`.
- Regression tests accompany these changes. Existing dummy-media TikTok widget
  fixtures inject a test preparer; production uses the native implementation.
- Related documentation: root `README.md`, `ROADMAP.md`, `API.md`,
  `ARCHITECTURE.md`, `apps/mobile/README.md`, and this plan. No schema, dependency,
  subscription, production environment, or publisher mode change is included.

## Verification receipt

Implementation and verification continued on 2026-10-15. Delivery is not yet
approved or complete.

- API publisher/worker regressions: 63 tests passed. Typecheck, build, and Prisma
  schema validation passed. The initial unrestricted full run encountered three
  timing/resource failures while other builds were running; the complete suite
  rerun with `npm test -- --maxWorkers=2` passed all 1,914 tests in 119 files.
  The rerun log is `D:/Temp/postdee-tiktok-calendar-api-full-bounded-20261015.log`;
  the initial failed run is retained beside it.
- Calendar/client/shell regressions: 216 tests passed, plus four focused date
  fallback checks. Final TikTok preparation/draft/retry/watermark regressions:
  59 tests passed, including actual draft restoration, owner-change cleanup, and
  decoded-prefix rejection of corrupt video with valid-looking metadata.
- Initial pre-encoder-workaround complete Mobile suite:
  `flutter test --no-pub --concurrency=2
  --reporter=expanded` passed all 2,224 tests in 6m17s.
  Log: `D:/Temp/postdee-tiktok-calendar-mobile-full-20261015.log`.
  `flutter analyze --no-pub` passed with no issues in 20.4s.
- Firebase debug configuration was compared semantically with the common and
  canonical main workspaces: the Staging client and project match. The Staging
  build configuration uses the Staging API, Firebase authentication, and no mock
  authentication. No client or server secret is recorded here.
- Native testing uses a separate local harness application
  `com.postdee.codecprobe.test` and fresh diagnostic AVD on port 5558. The user's
  Staging app is not reinstalled, relaunched, or used to send a test post.
- Initial real-media diagnosis on Android 14 x86_64 found that the native
  `h264_mediacodec` command can return success while producing audio-only output.
  The new output probe correctly rejects all three controlled 6/30/60 FPS input
  cases before upload. The initial native report is retained at
  `D:/PostDeeMobile/.tmp/tiktok-fps-native-probe-20261015/native-codec-report-initial-5af84e83.json`.
- A harness-only Android candidate, `-flags:v -global_header` with
  `-bsf:v extract_extradata`, passed actual decoding at 360x640, 720x1280, and
  1080x1920: H.264/AAC, 30 decoded frames with constant presentation timestamps,
  1-second duration, original display dimensions, and finite audio energy. This
  avoids FFmpeg's dummy-frame/EOS/encoder-flush header initialization while
  preserving SPS/PPS for the MP4 muxer. Async-only encoding was not selected:
  its NDK callback requires Android API 28, beyond this app's minimum API 24.
  The candidate report is retained beside the initial report as
  `native-codec-report-variants-fb99ccd9.json`.
- A separate JNI test reproduced a second concrete failure: declared H.264,
  30 FPS, 1-second duration, and `nb_frames=30`, but only two frames decode.
  The final output-only probe uses `-count_frames -read_intervals 0%+2` and checks
  `nb_read_frames` against the expected prefix count with a two-frame boundary
  tolerance. Missing, negative, insufficient, and excessive decoded counts fail
  before upload. Source metadata probing stays inexpensive. The existing
  30-second probe deadline and per-session cancellation remain in force.
- Exact final production helper SHA-256:
  `F89FFF91A3E2210757173CE7B406929B0B527C747E6DAE58F695B32540D13DAF`.
  Branch, copied helper, and embedded diagnostic helper hashes match. On Android
  14/API 34 x86_64 with native FFmpeg n8.1.2, all five actual helper cases passed:
  6 FPS 720x1280, 60 FPS 1080x1920, 30 FPS 360x640 with AAC, silent 30 FPS
  720x1280, and a 3-second 6 FPS 720x1280 input. The one-second outputs have 30
  decoded frames/prefix count 30; the three-second output has 90 full decoded
  frames/prefix count 60. Output is H.264/CFR30, original dimensions/duration are
  preserved, AAC audio has finite energy where present, and the silent input
  remains without an audio track. PTS interval error is at most 6.67e-7 seconds.
- New Android flags also pass all three JNI output sizes. The old corrupt JNI
  file reports actual prefix count two and is rejected by the exact final
  production validator. The final report is `finished=true, passed=true` at
  `D:/PostDeeMobile/.tmp/tiktok-fps-native-probe-20261015/native-codec-report-final-f89fff91.json`;
  the generated summary is `native-codec-verification-receipt.json` beside it.
  Only the fresh diagnostic AVD on port 5558 was shut down after testing; the
  user's emulator on 5556 and installed Staging versionCode 12019 were preserved.
- Final-source Mobile suite: `flutter test --no-pub --concurrency=4
  --reporter=expanded` passed all 2,226 tests in 2m32s. The exact-source
  `flutter analyze --no-pub` passed with no issues in 14.0s. Logs:
  `D:/Temp/postdee-tiktok-calendar-mobile-final-20261015.log` and
  `D:/Temp/postdee-tiktok-calendar-mobile-final-analyze-20261015.log`.
- Exact Staging APK build passed in 102.9s through the validated
  `tool/postdee-staging.ps1 -Command build-apk` helper with `--split-per-abi`,
  `--target-platform=android-x64`, and `--build-number=8020`. The split APK's
  versionCode is 12020, versionName `0.1.0-staging`, package
  `com.postdee.postdee_mobile.staging`, ABI x86_64, minimum API 24, target API 36,
  and debug signing is verified. APK:
  `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk` (127,730,038
  bytes), SHA-256
  `84468A674619A4FEAF95C36275177ECDE8CFBD344692B4AC00FA814F47F801E9`.
  Build log: `D:/Temp/postdee-tiktok-calendar-staging-apk-20261015.log`.
  Flutter 3.44.1/Dart 3.12.1/framework `924134a44c189315be2148659913dda1671cbe99`
  match between the test SDK and the helper's configured SDK. Native helper hash
  remains identical to the verified final source after building.
- Exact-APK technical startup smoke passed on the empty diagnostic AVD 5558:
  package/version/hash match, installation succeeds, the application process
  remains alive, MainActivity is resumed/visible, ActivityTaskManager reports
  Displayed/Fully drawn in 23.693s, and the Flutter Surface presents eight
  nonzero frame timestamps. The 12.15s `am start -W` wait timed out before this
  later first-frame confirmation; it is not a performance pass. PID-scoped crash
  buffer is empty and FATAL/Unhandled count is zero. Nonfatal resource and Google
  Dynamite/GMS warnings were observed on this fresh emulator. No account login,
  purchase, signed-in UI flow, or actual post is exercised by this startup check.
  The user's emulator 5556, installed version 12019, and account data are untouched.
- Physical
  Android/iOS, arbitrary full-length clip integrity beyond the bounded prefix,
  and actual TikTok delivery remain unverified. No source push or deployment is
  claimed yet.

Primary references:

- [TikTok media restrictions](https://developers.tiktok.com/docs/en/content-posting-api-media-transfer-guide)
- [TikTok failure reasons](https://developers.tiktok.com/docs/en/content-posting-api-reference-get-video-status)
- [PostPeer read-only post listing](https://www.postpeer.dev/docs/api/posts/listPosts)
- [FFmpeg MediaCodec header initialization](https://github.com/FFmpeg/FFmpeg/blob/n8.1.2/libavcodec/mediacodecenc.c#L872)
- [FFmpeg extract_extradata](https://ffmpeg.org/ffmpeg-bitstream-filters.html#extract_005fextradata)
- [Android MediaCodec states and encoder flush](https://developer.android.com/reference/android/media/MediaCodec.html#states)
- [Android NDK async callback availability](https://developer.android.com/ndk/reference/group/media#amediacodec_setasyncnotifycallback)
