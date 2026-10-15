# TikTok Direct Post — 2026-10-15

## Scope and baseline

The initial authorization covered checking PostPeer Direct Post capability and
implementing the complete PostDee publishing/settings flow, without publishing a
test clip, changing old records, granting new OAuth permissions, or releasing it.
The subsequent explicit user reply “ทำเลย” authorized merge/push, Staging deploy
and the emulator update. It did not authorize actual clip publication; the
authorized delivery and read-only UI evidence are recorded below.
Implementation starts at verified `main` / `origin/main`
`41e38e9a87e88f12f1e0799b5d41af261a1cc0e8` (fetch succeeded; 0 ahead/behind), in
the existing `tiktok-native-session-results` worktree on `codex/tiktok-direct-post`.
Three unrelated generated Windows files were already dirty and are preserved.
The stale original checkout and its unrelated work are not touched.

## Provider evidence

Official sources:

- [PostPeer creator-info contract](https://www.postpeer.dev/docs/api/tiktok/getTikTokCreatorInfo)
- [PostPeer TikTok options](https://www.postpeer.dev/docs/platforms/tiktok)
- [TikTok required publishing UX](https://developers.tiktok.com/docs/en/content-sharing-guidelines)
- [TikTok creator-info and scope](https://developers.tiktok.com/docs/en/content-posting-api-reference-query-creator-info)
- [TikTok Direct Post schema/caption limit/receipt](https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post)

A read-only check on the existing Staging service used its server-side credential
and only the current TikTok integration belonging to the owner of the previously
investigated post. No token, account ID, username or nickname is copied here.
`GET /v1/tiktok/creator-info?accountId=<stored integration>` returned HTTP 200,
`success: true`, complete camel-case data, public/friends/self options,
comments allowed, Duet disabled, Stitch allowed and creator duration 3600 seconds.
The effective API upload limit is still 600 seconds. No clip was uploaded or
published by this check. Creator-info succeeds for `video.publish`, but this
does not prove the provider client's audit/publication approval.

## Implementation contract

- Owner-scoped `GET /social-connections/TIKTOK/publishing-options` returns
  local connection ID, opaque creator-info revision and validated latest creator
  info, with private/no-store response and a bounded provider request.
- Revision covers owner and immutable target identity, not just local ID/time.
  New Direct settings require that revision, explicit privacy, three disabled
  interaction flags, branded/own-brand and AI disclosure flags, positive actual
  media duration, music confirmation and branded-policy confirmation when needed.
- Privacy has no default. Interactions are off until enabled and cannot override
  creator restrictions. Commercial disclosure starts off; enabling it requires a
  disclosure type. Third-party branded content cannot be SELF_ONLY.
- Direct captions use TikTok's 2,200 UTF-16-unit limit. Mobile rejects before
  draft save/submission effects; API rejects before creator lookup/write/quota,
  and the worker checks again. Inbox and other destinations keep their behavior.
- Music/policy links and explicit consent precede upload. Account/content changes
  or restored drafts invalidate freshness/consent. Current nickname, editable
  caption and video preview identify the intended publication.
- API validates latest options and revision before new post/quota/queue effects.
  Worker checks again before one CREATE, including scheduled work. Choice changes
  never silently fall back to Inbox or another privacy level.
- Worker forwards documented provider flags only. New Direct results require
  selected-platform final status and Direct video/receipt proof; Inbox receipts
  and messages URLs cannot be presented as Direct success. Ambiguity uses bounded
  GET on the original provider ID and never another POST.
- Existing JSON settings/target snapshots are sufficient; no schema migration.
  Preserve Inbox/legacy private TikTok, other destinations, local drafts,
  native H.264/AAC/CFR preparation, no TikTok watermark, upload reuse, quota,
  immutable intent, owner lifecycle and unknown-outcome duplicate prevention.

## Pre-release verification record

- Worker regression tests added first: 22 tests, 20 failed before implementation.
- Initial worker/inbox/delivery targeted suite: 132 passed. Added revision,
  malformed/5xx/receipt and pre-CREATE owner-state regressions first (each failed
  before its fix); the final worker-related targeted suite passes 172 cases.
  The documented `v_pub_file~v2-1.<digits>` Direct receipt and caption-unit limit
  also have RED/GREEN coverage. The latest compiled guard smoke blocks an
  overlong emoji caption before provider calls, then confirms one private Direct
  receipt without inventing a public URL; all provider work is injected.
- Final full API suite: 124 files / **2093 tests pass** with `--maxWorkers=2`
  in 48.68s.
  The first highly concurrent run timed out in the existing 100-logo hash test;
  all other tests passed. No logo or timeout configuration was changed. Reducing
  worker contention made the complete suite pass.
- Latest API TypeScript including tests and build pass. Prisma schema validation,
  seed/config helper compilation, shared catalog parity and all 22 generator
  tests pass. No schema/dependency/configuration changes were made.
- Compiled `dist` API smoke passes with an injected provider: owner options →
  accepted intent → worker → published result → idempotent replay; three creator
  checks, one CREATE and one local post. This makes no real provider request.
- Backend read-only lifetime regression uses the actual coordinator: failed
  creator GET releases its ticket; actual unknown publishing outcomes keep the
  existing reconciliation barrier. Exact revision/owner activity are checked
  again just before Direct CREATE. Independent source review found no remaining
  critical issue in these paths.
- Mobile API/settings 109 cases, PostDetail 18 cases and the UI/native-duration/
  draft/review targeted 154-case suite pass. The final Direct file passes 15
  cases, including caption boundaries, fresh identity/permission changes,
  missing duration, old receipt preservation and idempotent reuse.
- Complete Mobile suite passes **2285 tests**, with one optional preview export
  skipped, in 2m29s (`flutter test --no-pub --concurrency=4 --reporter=expanded`).
  Whole-project `flutter analyze --no-pub` finds no issues (15.8s). Flutter 3.44.1,
  Dart 3.12.1; logs `D:/Temp/tiktok-direct-mobile-full-20261015.log` and
  `D:/Temp/tiktok-direct-mobile-analyze-20261015.log`.
- The actual settings widget renders two local fixture previews with the real
  Anuphan/MaterialIcons fonts at 390×844 logical pixels. Defaults have no privacy,
  interactions off, restricted Duet disabled and Save disabled; the commercial
  variant has explicit consent and Save enabled. PNGs under
  `D:/Temp/postdee-direct-post-preview-20261015/` are visually checked. This is
  widget rendering with example identity, not a live account publication.
- Before release, source and tests were committed locally as
  `2f86d0633174080ad2ca74e4e3c97e38214c1fc3` on `codex/tiktok-direct-post`.
  Before the commit, a fresh fetch still showed baseline `origin/main` at
  `41e38e9` with no divergence. The task-only 50-file staged diff contains no
  unexpected deletion, dependency/schema/env/manifest change or generated
  Windows file. The remaining changes below are documentation evidence only.
- Exact Staging x86_64 debug APK builds from that source in 26.9s through the
  validated `tool/postdee-staging.ps1` helper, with `--no-pub`, `--split-per-abi`,
  `--target-platform=android-x64`, and base build number 8022. Package
  `com.postdee.postdee_mobile.staging`, versionCode **12022**, versionName
  `0.1.0-staging`, min SDK 24/target SDK 36; 127,762,902 bytes. Artifact:
  `C:/Users/stopp/.codex/worktrees/tiktok-native-session-results/PostDeeMobile/apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`.
  SHA-256 `BB0A91F600CFFFA5F4E4FDCEA8F0B20D8781FAEB5A8C303EA353D1BD5385A173`.
  Build log: `D:/Temp/tiktok-direct-staging-apk-12022-20261015.log`.
- APK signer matches the previous installed Staging build:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  All 14 permissions remain unchanged. The compiled kernel/resources contain the
  expected Staging API origin, new Direct revision wiring, matching Firebase
  project/app/Web OAuth resources and the validated RevenueCat Test Store key.
  No credential or resource values are printed. Firebase auth is enabled, local
  mock auth disabled, and Staging build marker enabled.
- Exact installed APK SHA matches on the existing account-free diagnostic AVD
  `postdee_codec_probe_20261015` / emulator 5558. The first launch immediately
  after AVD boot exceeded `am start -W`'s wait limit, although the process resumed
  with surfaces and no fatal/unhandled/Flutter errors. After the AVD settled, a
  fresh stopped-process cold launch returns `Status: ok`, COLD, 6445ms total /
  6487ms wait. Final scoped readback confirms resumed activity, 8 matching surfaces,
  zero fatal/unhandled/Flutter errors, and a running process. These observations
  are startup checks, not performance measurements or Direct provider E2E.
- No login, permission grant, purchase, clip upload or real publication was
  performed in the diagnostic app. Its emulator is stopped gracefully after the
  check. At this pre-release checkpoint, user emulator 5556 remained at **12021**,
  with no install, restart or UI input from the implementation task. No raw app
  logs or private account data were saved.
- At that checkpoint, the Staging server and user's APK remained the prior
  release, without a new push, deploy or installation. The authorized delivery
  below supersedes that release status, while preserving the evidence above.

## Authorized Staging delivery and device verification

- Following the user's explicit “ทำเลย”, canonical `main` and `origin/main`
  fast-forwarded from `41e38e9a87e88f12f1e0799b5d41af261a1cc0e8` to
  `568160294df45c942223c89a22d89e0d327fbfb4`. The code is the tested `2f86d063`
  implementation plus documentation evidence. Unrelated generated Windows files,
  `artifacts/`, and other worktrees are preserved.
- Exact-head [GitHub CI `38757735457`](https://github.com/NOI56/PostDeeMobile/actions/runs/38757735457)
  passes Backend and Flutter: **2093 API** tests and **2285 Mobile** tests, with
  one optional preview skipped. Exact-head [iOS CI `38757735448`](https://github.com/NOI56/PostDeeMobile/actions/runs/38757735448)
  completes successfully at `2026-10-15T15:19:11Z`: unsigned build, IPA payload
  and artifact upload pass. `PostDee_iOS` artifact `11984897106` is 44,434,066
  bytes. This is compile/package evidence; no iOS device installation or
  publication is claimed.
- Render Staging deploy `dep-db8ep7brjlhs73e46qc0` is Live at
  `2026-10-15T15:11:08.379387Z` on exact source `5681602`. Global queued/publishing
  backlog was zero before deploy and the enforced startup guard passed. Existing
  memory queue/PostPeer mode remains in use. All **18** migrations are applied,
  with none pending; no schema or environment change was needed.
- `/health` and `/ready` return HTTP 200; unauthenticated publishing-options
  returns HTTP 401. No error logs were observed in the bounded
  `2026-10-15T15:11:03Z`–`15:16:50Z` interval. These checks are service health and
  access-control evidence, not provider publication evidence.
- The exact APK documented above, with matching hash/signature, updates user
  emulator 5556 using `install -r`: **12021 → 12022**, success. First install
  remains 2026-10-05 and login is retained. The stopped-process cold launch
  returns `Status: ok` in 6091ms; this is a launch check, not a performance claim.
- Before installation, the open form was saved locally using Save Draft;
  the local draft count changed **1 → 2**, without upload or quota consumption.
  The same form reopened successfully after the update. An initial Home
  connection fetch failed during the transition; a read-only server repository
  probe confirmed valid TikTok/YouTube connections and the app retry succeeded
  at **2/4**. A second read-only probe after UI inspection confirms the owner
  still has **3** remote posts, global `QUEUED`/`PUBLISHING` remains **0**, and
  retained owner operations remain **5**, with no creator-GET ticket leak.
- The actual logged-in TikTok sheet fetched owner-bound creator info and showed
  Direct Post. The privacy menu contains `PUBLIC_TO_EVERYONE`,
  `MUTUAL_FOLLOW_FRIENDS` and `SELF_ONLY`, with no default selection. Duet is
  disabled by the creator restriction; interactions and consent are unchecked,
  and Save is disabled. Only the dropdown was opened: no privacy selection,
  consent, settings save, media upload, post POST or provider CREATE was made.
  Live settings and privacy-menu screenshots are
  `D:/Temp/postdee-direct-live-settings-20261015.png` and
  `D:/Temp/postdee-direct-live-privacy-options-20261015.png`. A bounded read of
  the current Android process's last 800 logcat lines found zero fatal,
  unhandled or Flutter errors.
- No real Direct publication, historical-data repair or Production change was
  performed. Provider TikTok audit/public approval remains **unverified**.

## Rollout and remaining proof

Staging API and Android delivery are complete as recorded above. In other
environments, deploy the new API before Mobile; an older API or failed creator-info
response must keep Direct unavailable. iOS compilation/package CI passes, while
iOS device rollout remains unverified. Verify provider audit/scope behavior
without assuming that available privacy options prove public
posting approval. A real
publication requires a separate user-selected clip, destination and explicit
publish action. Record public/friends/self delivery and status behavior after
that controlled test. Do not resend old Inbox posts to test the new feature.

## Changed files

Backend source:

- `apps/api/src/app.ts`
- `apps/api/src/modules/account/ownerOperationRouter.ts`
- `apps/api/src/modules/posts/platformSettings.ts`
- `apps/api/src/modules/posts/postRoutes.ts`
- `apps/api/src/modules/posts/tikTokDirectSettings.ts`
- `apps/api/src/modules/socialConnections/postPeerTikTokClient.ts`
- `apps/api/src/modules/socialConnections/tikTokPublishingOptionsRoutes.ts`
- `apps/api/src/modules/socialConnections/socialConnectionStore.ts`
- `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts`
- `apps/api/src/workers/platformDeliveryOutcome.ts`
- `apps/api/src/workers/platformPublisherFactory.ts`
- `apps/api/src/workers/postPeerPublisher.ts`
- `apps/api/src/workers/publishWorker.ts`
- `apps/api/src/workers/publishWorkerRunner.ts`

Backend tests:

- `apps/api/src/modules/account/ownerOperationRouter.test.ts`
- `apps/api/src/modules/posts/platformSettings.test.ts`
- `apps/api/src/modules/posts/postRoutes.test.ts`
- `apps/api/src/modules/posts/tikTokDirectSettings.test.ts`
- `apps/api/src/modules/socialConnections/postPeerTikTokClient.test.ts`
- `apps/api/src/modules/socialConnections/tikTokPublishingOptionsRoutes.test.ts`
- `apps/api/src/modules/socialConnections/socialConnectionRoutes.test.ts`
- `apps/api/src/modules/socialConnections/socialConnectionStore.test.ts`
- `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.test.ts`
- `apps/api/src/tikTokDirect.flow.test.ts`
- `apps/api/src/workers/postPeerDirectPublisher.test.ts`

Mobile source:

- `apps/mobile/lib/core/network/postdee_api_client.dart`
- `apps/mobile/lib/features/legal/legal_document_screen.dart`
- `apps/mobile/lib/features/posts/post_detail_screen.dart`
- `apps/mobile/lib/features/uploader/platform_publish_settings.dart`
- `apps/mobile/lib/features/uploader/publish_draft.dart`
- `apps/mobile/lib/features/uploader/publish_draft_store.dart`
- `apps/mobile/lib/features/uploader/publish_review_screen.dart`
- `apps/mobile/lib/features/uploader/tiktok_publishing_settings_sheet.dart`
- `apps/mobile/lib/features/uploader/tiktok_video_preparer.dart`
- `apps/mobile/lib/features/uploader/uploader_screen.dart`

Mobile tests:

- `apps/mobile/test/legal_document_screen_test.dart`
- `apps/mobile/test/platform_publish_settings_test.dart`
- `apps/mobile/test/post_detail_screen_test.dart`
- `apps/mobile/test/postdee_api_client_test.dart`
- `apps/mobile/test/publish_draft_store_test.dart`
- `apps/mobile/test/tiktok_video_preparer_test.dart`
- `apps/mobile/test/uploader_screen_test.dart`
- `apps/mobile/test/uploader_tiktok_direct_post_test.dart`
- `apps/mobile/test/tiktok_direct_settings_preview_test.dart`

Documentation: `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`,
`apps/mobile/README.md`, and this feature record. Existing generated Windows
files and all other worktrees are excluded from the change.
