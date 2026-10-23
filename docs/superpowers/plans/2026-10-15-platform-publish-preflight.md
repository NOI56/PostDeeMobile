# Channel publishing preflight — 2026-10-15

## Scope and baseline

The user authorized the proposed channel publishing improvements after a read-only
audit of YouTube, Instagram and Facebook settings. Initial implementation approval
excluded release and user-device installation; the later explicit **ทำเลย**
authorized the API-first Staging delivery recorded below. Real clip publication,
OAuth permission grants, account repair and Production remain outside that scope.
Source `2e86634` is now on main and Live on Staging, followed by Android **12023**
on the user's emulator. The previous TikTok Direct delivery is recorded separately
in `2026-10-15-tiktok-direct-post.md`.

Implementation starts from freshly fetched canonical `main`/`origin/main`
`c1e70cfcd145aad05161208466ac4d6f889caa47` in the existing
`tiktok-native-session-results/PostDeeMobile` worktree, on
`codex/platform-publish-preflight`. The canonical `grouped-account-ui` main and
its old artifacts are preserved. Three pre-existing generated Windows changes,
the stale original checkout and unrelated user work are not reset or included.

## Caption contract

- YouTube: exact trimmed description must fit 5,000 UTF-8 bytes and contain no
  `<` or `>` characters. A Thai or emoji caption can reach this limit sooner
  than an ASCII caption of the same character count.
- Instagram: use a conservative 2,200 UTF-16-unit limit, matching the cap exposed
  by PostPeer's own Instagram Reels scheduler without claiming Meta counts every
  Unicode sequence in exactly this way.
- Facebook: use the documented 63,206-character cap with conservative UTF-16
  counting in both Mobile and API. No emoji boundary mismatch or text truncation.
- Existing TikTok Direct 2,200-unit validation and Inbox behavior remain intact.

New invalid requests receive safe HTTP 400 `PLATFORM_CAPTION_INVALID`, with
`platform`, a stable reason and optional `maxLength`/`unit`. Guards precede media
readiness, provider/account lookup, quota or post mutations. The provider publisher
repeats the same guard. Existing accepted idempotent requests are recovered before
new-request validation, keeping their stored caption and original request ID.

## Read-only channel readiness

Authenticated `GET /social-connections/publishing-readiness` returns private,
non-cacheable `{status: "ok", checkedAt, connections}`. Each supported platform has
a state plus optional local connection ID and opaque revision. Revisions cover
all platforms; provider IDs, tokens, raw metadata and provider reasons stay private.
The ordinary connection-list DTO uses the same opaque revision for every
platform, allowing identity comparison across list/readiness requests even when
an upsert retains its local connection ID and connected-at timestamp.

The server uses only the caller's existing stored profile ID and connections.
It performs bounded GET integration listing, never remote profile discovery or
creation, synchronization, reconnect, permission granting or publishing. Provider
reads reject redirects and cap response size, pagination and duration. Owner
activity and the local profile/target binding are checked around the read.
Read-only failures are captured inside the owner lifetime so they release their
ticket normally; ambiguous external write barriers are not weakened or deleted.

Only explicit `platformMetadata.capabilities.publish: true` produces `ready` if
no explicit reconnect flag is set. Explicit false produces `permission_missing`;
`tokenStatus.reconnectRequired: true`, a missing stored integration or missing
stored profile asks for reconnection. Successful integrations with unknown
capability data are `connected`/unverified rather than guessed ready or blocked.
Unconfigured/provider failures return safe 503; concurrent account/profile
replacement returns safe 409. Caller query overrides are ignored.

Mobile loads the snapshot when opening channels and rechecks before upload and
before POST, with owner/generation/connection/revision checks. Explicit bad states
block submission and offer refresh/reconnect guidance. A new server failure blocks
new work; only HTTP 404 from an older API enables the compatibility fallback.
Unknown successful capability data remains usable with an unverified label.
The snapshot cannot guarantee future provider permissions after a scheduled post
is queued. This change does not add readiness GETs to historical accepted requests
or workers and does not claim that `ready` proves actual publication.

## Actual outgoing media

The probe reads the file actually selected for upload after watermark/TikTok
preparation. Its native FFprobe session is pre-created and completed through its
own MethodChannel execution, with bounded timeout/output and scoped cancellation;
it does not depend on global callbacks from another Flutter engine.

- YouTube Shorts: duration at most 180 seconds; existing 9:16 uploader policy stays.
- Instagram Reels: MOV/MP4 container, 3–900 seconds, maximum 300,000,000 bytes, width at most 1,920,
  23–60 FPS, H.264 or HEVC; when audio is present, AAC mono/stereo at at most
  48 kHz. Missing required measurements remain unverified and block upload.
- Facebook Page Reels (2026-10-24 contract): remove the Page Video duration and
  width caps; do not invent Reel limits. Preserve verified media metadata and
  general upload validation; the provider validates the actual Reel. Recommendations
  such as 30 FPS, dimensions divisible by 16 and preferred encoders are not
  introduced as mandatory rejection rules.

These are Mobile preflight checks, not new trusted server media validation. The
provider still validates the actual upload. Optional `videoMetadata` is retained
with the existing uploaded-media receipt and media-content fingerprint. Old draft
formats remain readable. A cached render whose actual metadata cannot be proven
is retained and blocked, never silently thrown away or uploaded again. Original
source media, owner scope and unknown-post request identity remain preserved.
The native check does not currently inspect MOV/MP4 atom ordering, edit lists,
progressive scan, closed GOP, chroma subsampling or bitrate. Passing preflight
therefore does not certify every Instagram media requirement.

`POST /posts/submissions/recover` reads an existing accepted request before these
new guards. Its body contains the original creation intent, including the request
ID, caption, media keys/fingerprint, platform settings, schedule and cover options.
POST avoids putting private intent into URLs; it is not a creation/retry action.
Owner-scoped lookup and the existing immutable comparison accept persisted legacy
settings but reject changed content or destinations. Recovery alone may fill an
omitted Facebook entry with its known
historical `PUBLISH` default in a mixed platform settings object. It cannot match
an accepted Page draft, fix other missing/malformed platform entries or relax new
post validation. The mixed YouTube-private/Facebook-omitted regression and strict
negative controls cover this legacy case. A match returns the ordinary
redacted post with `idempotentReplay: true` and `recovered: true`, without quota,
provider, media, profile or queue work. FAILED stays FAILED. Missing lookup is 404,
intent mismatch is 409, malformed input is 400 and sanitized read failure is 503.
Owner activity is checked before/after lookup under the durable lifetime. The
outer owner router retains admission/completion but exempts only this exact POST
path from treating a 503 read failure as an ambiguous external write. Neighboring
write routes retain their existing stronger protection. Mobile retains unverified
drafts/receipts and the original request ID; recovery never uploads or publishes.
The visible **ตรวจผลการส่งเดิม** action looks up the persisted original draft,
independently of current caption/media/permission guards, schedule expiry or form
edits. It shows the stored status, including failures, and keeps the draft and
receipt even when the original post is found; it does not discard unsaved edits.
A matched result blocks another normal send from that draft until the existing
explicit new-request action is used. An absent lookup or unavailable old API
never falls through into creating a post. Recovery-only serialization preserves
known legacy YouTube visibility without inventing title/audience/AI/certification
answers. Normal publishing serialization remains strict.

## Settings and review UX

An empty YouTube title may be suggested from the caption with safe angle-bracket
removal and a 100-character boundary; an edited title is never overwritten. Privacy,
made-for-kids, realistic synthetic-media disclosure and community certification
remain explicit user decisions. Review displays all YouTube answers, the selected
Instagram feed choice, and YouTube's linked Terms notice with copyright/privacy
guidance beside confirmation. Facebook now requests Page Reels only through
PostPeer `contentType: 'reel'`, preserving publish/Page-draft and AI disclosure
with no Page feed fallback. Real-account Reel E2E remains pending; Shopee and
Lazada are not advertised as working destinations.

The generic old YouTube audit warning is not proof of a particular PostPeer
account's visibility. Current Google endpoint prose and its generated page summary
conflict on the old unverified-project Private rule, so wording stays neutral and
actual provider/publication verification remains a separate test.

## Verification

Primary implementation files are grouped below; associated regression tests
cover the same areas.

| Area | Files |
| --- | --- |
| Composer readiness, media checks and recovery action | `apps/mobile/lib/features/uploader/uploader_screen.dart`, `apps/mobile/lib/features/shell/postdee_shell.dart` |
| Rules and native probe | `apps/mobile/lib/features/uploader/platform_publish_preflight.dart`, `apps/mobile/lib/features/uploader/publish_media_probe.dart` |
| Settings and review | `apps/mobile/lib/features/uploader/platform_publish_settings.dart`, `apps/mobile/lib/features/uploader/publish_review_screen.dart` |
| Retained upload receipt and API DTOs | `apps/mobile/lib/features/uploader/publish_draft.dart`, `apps/mobile/lib/features/uploader/publish_draft_store.dart`, `apps/mobile/lib/core/network/postdee_api_client.dart` |
| Caption and original submission routes | `apps/api/src/modules/posts/platformCaptionValidation.ts`, `apps/api/src/modules/posts/postRoutes.ts` |
| Readiness and account revisions | `apps/api/src/modules/socialConnections/publishingReadinessRoutes.ts`, `postPeerConnectClient.ts`, `socialConnectionStore.ts`, `prismaSocialConnectionRepository.ts` in the same directory |
| Wiring and safe errors | `apps/api/src/app.ts`, `apps/api/src/modules/account/ownerOperationRouter.ts`, `apps/api/src/workers/postPeerPublisher.ts`, `apps/api/src/workers/publishWorker.ts` |

The preserved flows include TikTok Inbox/Direct privacy and consent, exact prepared
media, owner changes and retained uncertain submissions, YouTube explicit answers,
Instagram feed/cover choices, Facebook publish/Page draft, entitlement and schedule
limits, Home-to-calendar handover, AI captioning, shop links and account controls.
No files or capabilities were removed. The final diff is checked against `c1e70cf`.

Backend regression-first checks reproduced missing caption protection and
readiness metadata/security behavior before implementation, including the
conservative Facebook UTF-16 emoji boundary. Independent review then reproduced
18 all-platform revision/recovery failures and two exact-route lifetime failures;
the corrected code passes the real protected-router release checks. The final
full run passes 127 files / 2,163 tests (81.83 seconds), including the final
mixed legacy Facebook recovery and strict negative controls. API whole-project
typecheck/build, Prisma schema validation and
Prisma seed/config helper compilation passed. Compiled app smoke verified the
new authenticated route, one fake provider GET, zero provider/profile writes,
redacted output and invalid-caption HTTP 400. This smoke used injected data,
not a real social account or publication. A final compiled `createApp` smoke
created one mock in-memory post, recovered the same original ID/status with the
new route, kept the list at one record, blocked a foreign owner and confirmed
changing all-platform connection revisions. It made zero external provider calls.

The root Mobile integration checks pass **13 tests**, covering native preflight,
Thai YouTube byte limits, initial account revision disagreement, reconnect changes,
API rollback labels, retained receipts/request IDs, legacy recovery without new
YouTube answers, accepted/failed/absent original results, and owner changes during
recovery or metadata probing. Whole-project `flutter analyze --no-pub` passes
with no issues. The exact Staging debug x86_64 APK builds through the validated
helper using base build number 8023 / versionCode **12023**. An initial build
attempt before the recovery serializer was available failed; the final build
after implementation succeeds. After adding the shell's matching optional test
injection seams, the source-final build also passes (31.8 seconds). The full
Mobile suite passes **2,351 tests**, with one optional Direct preview skipped,
in 2m32s using `--no-pub --concurrency=4 --reporter=expanded`. An earlier full run
found one shell/calendar fixture still using a real HTTP request; the targeted
regression and final full suite pass after making that fixture explicit. The
production defaults still use the real API and native probe. Final log:
`D:/Temp/postdee-platform-preflight-mobile-full-final-20261015.log`.
Independent review found and prompted
the revision, legacy recovery and rollback fixes above.

These local verification results preceded the authorized delivery below. No new
database migration, schema, environment or dependency is needed; rollout deploys
the API before Mobile. No historical post, owner blocker, queued job or Production
service was repaired or altered by this change.

## Exact Android diagnostic validation

This account-free diagnostic phase preceded the authorized user-device update.

- Source-final build: `apps/mobile/tool/postdee-staging.ps1 -Command build-apk
  --split-per-abi --target-platform=android-x64 --build-number=8023`, using the
  workspace Flutter SDK and actual Android SDK. Final log:
  `D:/Temp/platform-preflight-staging-apk-12023-source-final.log`.
- Artifact: `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`,
  SHA-256 **3CE07DC0C3ED2791BDE0AA13EE5292B79054B7C7218F65D504C3CE1B8EF37A9A**.
  Package `com.postdee.postdee_mobile.staging`, versionCode **12023**, min SDK
  24/target SDK 36, x86_64; **127,805,646 bytes**. Signer matches delivered 12022; all 14 permissions
  remain unchanged.
- During this phase, installed only on newly created, account-free diagnostic AVD
  `postdee_platform_qa_20261015` / emulator **5558**. The user's emulator **5556**
  remained at delivered **12022**, without restart, installation, form changes or
  account actions during this diagnostic phase.
- APK resources match the Staging Firebase project/app/Web OAuth configuration.
  Debug VM field reads verify the Staging marker/API, Firebase auth enabled,
  local mock auth disabled, RevenueCat enabled with its Test Store key, and
  experimental AI Hook/Beat Sync disabled.
  Only matching booleans are recorded; credential values are not printed.
- The production `FfmpegPublishMediaProbe` executes on this APK and reads an
  owned synthetic local MP4 correctly: **5 seconds, 720×1280, H.264/AAC,
  30 FPS, 48 kHz stereo, 12,284 bytes**. No source or app code was replaced to
  perform the native check. Generated diagnostic files stay outside tracked
  product code.
- Native Instagram validation accepts the measured 30 FPS clip and rejects an
  owned 15 FPS fixture with `INSTAGRAM_FRAME_RATE_INVALID`. Native evidence:
  `D:/Temp/platform-preflight-native-valid-12023.jsonl`.
- The final installed APK hash matches the artifact above. The Staging login
  screen renders completely, independently inspected in
  `D:/Temp/postdee-platform-qa-12023.png`. Scoped final-process diagnostics find
  zero fatal, unhandled or native-crash errors. On this fresh headless AVD,
  `am start -W` cold-start waits exceeded their 10.8–12.7 second limits even
  though the activity, Flutter frame and native probe work; this is not a
  successful cold-start latency measurement or a physical-device performance
  result.
- Flutter attach is detached cleanly, diagnostic forwarding is removed and only
  AVD 5558 was stopped. The user's 5556 remained running at 12022 at this checkpoint.
- No login, provider connection, clip upload, real publication or purchase was
  performed. Pro entitlement and provider request paths are covered by injected
  tests, rather than a new authenticated end-to-end provider run. Instagram and
  Facebook still require a connected-account publication check. No migration or
  database operation was run during this diagnostic phase.

## Authorized Staging delivery

The user's explicit **ทำเลย** approves the annotated API-first push/deploy and
user-emulator update. Canonical `main` and `origin/main` were freshly verified
at `c1e70cf`, then fast-forwarded and pushed to tested source
**2e866346767acd0c1322d9d0dc830dfa6c708154** (0 ahead / 0 behind). The three
pre-existing generated Windows changes and canonical untracked `artifacts/`
remain preserved and excluded from the commit.

- Exact-source [CI 38766556966](https://github.com/NOI56/PostDeeMobile/actions/runs/38766556966)
  passes Backend API (2,163 tests, typecheck, build, Prisma and dependency audit)
  and Flutter Mobile (analysis and tests), completed **16:14:43 UTC**.
  [Unsigned iOS 38766556987](https://github.com/NOI56/PostDeeMobile/actions/runs/38766556987)
  passes build/IPA packaging/artifact upload at **16:19:58 UTC**; artifact
  `PostDee_iOS` / `11990147858` is 44,460,714 bytes. No iOS device test is claimed.
- Render service `srv-d9bb72ojs32c739osa5g` in the previously human-confirmed
  My Workspace remains on `main`, auto-deploy off, one Staging instance. Runtime
  source **2e866346767acd0c1322d9d0dc830dfa6c708154** is Live on manual deploy
  **dep-db8focbrjlhs73bs5s90** at **16:17:56.838159 UTC**, before Mobile installation.
  No cache clear, environment change, database network change or Production
  deployment was performed. A later documentation-only main commit records this
  delivery without deploying another runtime.
- Fresh service-Shell aggregate preflight confirms PostPeer + memory queue,
  empty-backlog guard enabled, zero global QUEUED/PUBLISHING posts, 18 applied
  migrations and zero unfinished migrations. The five retained owner operations
  are preserved; their count is not a queue and is not cleared for deployment.
  Render MCP DB access is unavailable under the existing closed external IP
  allowlist; that network protection was left unchanged. New instance `wv2lg`
  startup confirms 18 migrations/no pending, PostPeer, enforced empty-backlog
  activation guard with zero backlog, and the service listening on port 10000.
- Post-deploy read-only Shell aggregate on new instance `wv2lg` confirms exact
  source `2e866346767acd0c1322d9d0dc830dfa6c708154`, memory queue, PostPeer and
  the enabled guard. Global totals are **10 posts, 0 QUEUED/PUBLISHING, 5 retained
  owner operations, 0 deletion runs, 18 applied migrations and 0 unfinished**.
  No database records or network permissions were changed for this check.
- Public API `/health` returns HTTP 200. Unauthenticated publishing-readiness
  GET and submission-recovery POST return HTTP 401 without owner operations.
  Source identity comes from Render deployment metadata, not the health response.
- Read-only preflight found logged-in Account, version 12022 and two version-3
  local drafts with no upload receipt. During CI wait the user opened an unsaved
  composer and edited a draft. Before installation the settings sheet was closed
  without supplying YouTube declarations. Save Draft rejected the empty clip/text
  form, so no dummy content or additional draft was created. The intervening user
  edit at 16:11 UTC explains the changed aggregate manifest hash; it preceded the
  update and is not attributed to installation.
- `install -r` updates emulator **5556** to exact **12023** with the artifact hash,
  signer and permissions above. First-install identity, login and both local
  drafts remain; post-install draft aggregate stays unchanged through final
  verification. No data clear, uninstall, unrelated cleanup or installation was
  used. Cold launch reports Status OK (8,475 ms); this is an emulator observation,
  not a physical-device performance acceptance result. Final free space is about
  **666 MiB**.
- The app's real `PostDeeApiClient` using the current captured session reads
  connections and publishing-readiness successfully (HTTP 200) against the new
  API. TikTok and YouTube connection IDs/revisions match between the two GETs;
  both correctly report `connected` / `PUBLISH_CAPABILITY_UNCONFIRMED`, rather
  than invented `ready`. Instagram/Facebook report `not_connected`. The masked
  diagnostic is `D:/Temp/platform-preflight-user-auth-readonly-12023.jsonl`.
- Initial Home request errors clear after a GET-only refresh. The final Home
  displays the package and **2/4** connected channels normally, with no scoped
  fatal/unhandled/native crash. Debug attach is detached, its owned forwarding
  removed, diagnostic AVD 5558 stopped, and user emulator 5556 remains open on Home.

No real upload, publication, AI generation, purchase, OAuth grant, account repair
or submission-recovery POST using user data was performed. Connected-account
publication, Instagram/Facebook setup and physical iOS/Android acceptance remain
separate checks. This delivery does not certify provider public-post approval.

## Primary sources

- [YouTube upload minimum fields and description limit](https://developers.google.com/youtube/terms/required-minimum-functionality)
- [YouTube required upload notice](https://developers.google.com/youtube/terms/api-services-terms-of-service)
- [YouTube current insert contract](https://developers.google.com/youtube/v3/docs/videos/insert)
- [YouTube three-minute Shorts](https://support.google.com/youtube/answer/15424877?hl=en)
- [PostPeer YouTube settings](https://www.postpeer.dev/docs/platforms/youtube)
- [PostPeer Instagram capabilities and media requirements](https://www.postpeer.dev/docs/platforms/instagram)
- [PostPeer Instagram Reels scheduler caption limit](https://www.postpeer.dev/free-tools/instagram-reels-scheduler)
- [PostPeer Facebook Page Reels routing and reconnect flag](https://www.postpeer.dev/docs/platforms/facebook)
