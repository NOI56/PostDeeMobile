# Calendar selected covers — 2026-10-21

## Request and baseline

The user requested that Calendar post cards display the video cover selected
when creating the post. Remote `main` was checked at
`8c957abaacfa5d4f94353e4e2841fcb4cb20834f`. Candidate branch
`codex/calendar-cover-preview` starts at that exact baseline in the existing
`platform-consent-preserve` worktree. Preserve the three pre-existing generated
Windows changes and exclude them from this delivery. The stale D-drive source
is not the implementation baseline.

This request authorizes the Calendar implementation. A subsequent explicit
approval allowed the data-preserving native update without retaining the open
composer form. The user's subsequent 2026-10-21 main/push request authorizes
main integration and GitHub push. No API deployment or migration is required;
no manual cloud deployment, real post, purchase or account mutation was used
to verify the display behavior.

## Implementation

- Retain the existing `coverImageS3Key` and saved `coverFrameTimeMs` in
  `PostSummaryResult` and `CalendarPostResult`. Legacy metadata remains valid.
- Keep the complete metadata-only `GET /posts` read unchanged. Enabling
  `includeMedia` on that list would invoke its 50-post preview cap and hide
  calendar history; do not use that path for Calendar.
- For selected-day rows with a stored image or video key, use the existing exact-owned
  `GET /posts/:id?includeMedia=true`. Prefer the safe signed `coverImageUrl`;
  a supplied safe image URL needs no extra read. A legacy post without an image
  key may extract its saved frame, including zero, from that owned read's signed
  video URL. When no frame choice was recorded, use the first frame at time zero.
  Do not use an arbitrary video URL supplied by list metadata. A stored image
  key never falls back to a video frame when its image is unavailable.
- Legacy extraction uses existing FFmpeg support to create one static 144 by
  256 JPEG, with an eight-second deadline, a 512 KiB output limit, scoped
  cancellation and temporary-file cleanup. No video player or full local video
  file is created, but Dart may fetch remote video data/ranges. It recovers
  only a saved video frame or the first frame, not an old gallery image or text
  overlay that was never stored.
- The existing native FFmpeg video package lacks TLS. Route its input through
  a per-extraction `CalendarCoverVideoProxy` bound only to `127.0.0.1` with a
  random 24-byte (192-bit) path. Fix the upstream URI to the freshly read owned signed URL,
  keep Dart HTTPS certificate verification, disable redirects and use identity
  encoding. Accept only GET/HEAD and one byte range; answer a local HEAD probe
  through upstream signed GET with `Range: bytes=0-0`, preserving signature
  compatibility. Stream with backpressure under a shared 8 MiB total,
  24-request and three-active-request budget per proxy. FFmpeg receives only
  loopback HTTP; no full video file/buffer, native bridge or new dependency.
  Close the proxy/upstream work with the extractor's deadline, completion or
  owner/day invalidation.
- Cache per view and sign-in lifetime, deduplicate requests, and allow at most
  three active read/extraction operations. Rebuilds and silent status polling
  reuse results. Evict
  rows leaving the selected day/filter, and recreate the cache on manual
  refresh. Reject stale owner/session/disposed results and stop dispatching
  queued work while inactive or backgrounded. Already active HTTP requests may
  finish, but cannot restore a discarded row.
- Display a 48 by 85.33 logical-pixel 9:16 thumbnail on the left. Keep the time
  above the caption and retain actual status, platform chips, activity motion,
  accessibility and original tap behavior. Loading, missing, failed and unsafe
  images use a static placeholder. Failed reads retry only after refresh or
  eviction; no automatic network retry loop or arbitrary video fallback.
- The user's latest follow-up limits the card caption to one line with an
  ellipsis. Keep the complete caption in the card's accessibility label and the
  original post-detail navigation; only the compact visual text is shortened.
- Preserve cover metadata when replacing a rescheduled row, including when
  its follow-up list refresh fails, and when reconciling an ambiguous cancel
  response through the existing owned single-post read.
- For new publish requests, upload the chosen cover image for all four supported
  destinations through the existing cover path and include its digest in media
  identity. Previously only Instagram/Facebook submitted the chosen JPEG.
  Historical non-Meta receipts without a cover image key retain their original
  fingerprint/request identity, avoiding duplicate upload/publication on retry.
  This preserves PostDee's selected image without claiming additional provider
  thumbnail support.

## Changed files

- `apps/mobile/lib/core/network/postdee_api_client.dart`
- `apps/mobile/lib/features/calendar/calendar_screen.dart`
- New `apps/mobile/lib/features/calendar/calendar_cover_preview_cache.dart`
- New `apps/mobile/lib/features/calendar/calendar_legacy_cover_frame.dart`
- New `apps/mobile/lib/features/calendar/calendar_cover_video_proxy.dart`
- `apps/mobile/lib/features/uploader/uploader_screen.dart` and
  `publish_draft_store.dart` for forward cover retention and legacy receipt
  compatibility.
- New tests `calendar_cover_api_test.dart`, `calendar_cover_test.dart`,
  `calendar_cover_preview_cache_test.dart` and `calendar_cover_mutations_test.dart`
  under `apps/mobile/test/`, plus the
  existing complete-calendar transport regression in
  `postdee_api_client_test.dart`. Legacy extraction/cache regressions are in
  `calendar_legacy_cover_frame_test.dart`, `calendar_legacy_cover_cache_test.dart`
  and `calendar_cover_video_proxy_test.dart`;
  upload/receipt regressions update `uploader_cover_flow_test.dart`,
  `publish_draft_store_test.dart` and `support/test_publish_media_identity.dart`.
- `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md` and this work record.

## Contracts and preserved capabilities

No API implementation, request/response contract, dependency, migration,
configuration or entitlement change is required. The owned single-post route
was delivered by the preceding usability release and exists at baseline
`8c957ab`. This follow-up requires an updated Mobile app; it does not require
another API deployment on that Staging baseline.

Preserve all immediate/scheduled/history records, local date handling,
date/platform filters, refresh/status polling, queue rescheduling/cancellation,
post detail navigation and existing consent/receipt/publishing safeguards.
Existing posts with neither an image nor a usable owned video keep a
placeholder. A legacy frame can be recovered only while its owned video remains
available; a gallery image/overlay not uploaded by the old app cannot be exactly
reconstructed.

## Verification and delivery record

Evidence is collected under
`D:/PostDeeMobile/artifacts/calendar-cover-20261021`. The baseline red probes
capture missing cover metadata/presentation before implementation. Focused
coverage includes exact selected-image use, no arbitrary video fallback,
missing/failed and unsafe URLs, narrow/enlarged-text layout, cache concurrency/deduplication,
manual refresh, silent polling and stale-account results. The existing full
calendar transport regression retains more than 50 records.

The initial image-key-only candidate passed 186 focused tests. Both additional
mutation regressions were observed failing before the two metadata-copy fixes
and pass afterwards.

That initial candidate's full Mobile run passed 2,686 tests with six existing
optional previews skipped; analysis reports no issues. An old untracked render probe in the verification
snapshot's build directory initially triggered a filename lint. It was archived
outside Mobile with its hash preserved; no candidate source changed. Analysis
was repeated successfully. Its exact 582 Mobile/shared source hashes match that
earlier candidate, and its Staging x86_64 debug build passes.

APK12035 is verified for the existing Staging package, API URL, Firebase project,
Google client, Test Store SDK configuration, signer, 16 KiB alignment and retained
feature wiring. SHA256:
`799fb6c9d2634a8abd0ac59d5b79131c6bb822f0a545a13a34fc54e8198eb273`.
The existing KGP future-compatibility warning does not prevent this build; no
dependency change was introduced here.

The user explicitly approved installing without retaining the open composer
form. The guarded update installs 12035 over 12031 on `emulator-5556`, preserving
UID10190 and adopted volume `470668ed-4e40-4628-acb4-8704efc6b257`. No uninstall,
clear, cross-volume move or real publication was used. Native checks retained
the signed-in account, Pro quota at 238/250 and existing drafts. Calendar then
showed placeholders for old TikTok/YouTube records. A later read-only inspection
of aggregate field presence confirmed that all seven loaded existing records
had neither an image key nor a frame timestamp. No IDs, captions, private media
URLs or tokens were included in that readout. The earlier assumption that these
records retained a frame timestamp was incorrect. The previous uploader sent
cover images only for Instagram/Facebook, and some historical records retained
no frame choice either. This native image acceptance failed despite successful
installation and automated image-key coverage, requiring the default-first-frame
and forward-upload fixes above.

## Expanded candidate verification

The 2,686-test result and APK12035 belong to the earlier image-key-only revision.
The intermediate saved-frame/uploader revision passed 2,715 tests with six
optional previews skipped and clean analysis. APK12036 was installed for a
read-only native component probe, without new posts or quota changes. Its actual
HTTPS extraction returned null; sanitized output reported a missing protocol,
matching the video package's documented lack of TLS. The default-first-frame
revision also passed 2,715 tests with six optional skips and clean analysis;
APK12037 was built but not installed. Those results do not verify the subsequent
loopback proxy integration.

APK12038 was installed while preserving UID and the adopted volume. Its earlier
native UI check was stopped by the user's Escape action; image acceptance on
the Calendar screen is not claimed. A later read-only Dart VM probe of the
production frame extractor on that installed app returned a 5,042-byte JPEG
(`Uint8List`), confirming the actual native extraction path works. This is
component evidence, not a replacement for rendered Calendar image acceptance;
no real post was submitted.

The latest one-line-caption follow-up passes 12 focused tests, including Thai
text at 320dp with 1x/2x scaling, actual single-line height, complete accessibility
caption and unchanged detail callback. Before integration, remote `main` was
refreshed and verified at `8c957abaacfa5d4f94353e4e2841fcb4cb20834f`.
The final `one-line` candidate
passes the full Mobile suite: 2,725 tests, with six existing optional previews
skipped. Analysis reports no issues, and the Staging x86_64 debug build passes.
All 587 Mobile/shared input hashes match the verified source and build snapshot.

APK12039 SHA256:
`c24a64eab9fa7edeaae9ffe1bc6de891f846d493d98ad71563c6b3d4d1415861`.
Package, API URL, Firebase/Google project configuration, existing billing SDK
configuration, signer, 16 KiB alignment and retained feature wiring pass
inspection. The guarded update from 12038 preserves the existing UID and adopted
volume, with no uninstall or clear. Native checks retain the authenticated Pro
account, quota at 238/250, the existing draft and two connected channels.

Native Calendar acceptance now passes on APK12039: the two existing October 20
posts display static cover images, the long Thai caption occupies one line with
an ellipsis, and the short caption remains readable alongside time, status and
platforms. The historical images are recovered first frames because those posts
never stored their selected covers; this does not reconstruct an old gallery
image or overlay. No full local video, real post, duplicate publication or
purchase was needed. New-post publishing and store checkout were not exercised.

No API/schema/environment/dependency change or migration is needed. The user
authorized main integration and GitHub push on 2026-10-21. This release requires
no API deployment; no manual cloud deployment, real post or purchase was
performed. Production and external publishing behavior are unchanged.
