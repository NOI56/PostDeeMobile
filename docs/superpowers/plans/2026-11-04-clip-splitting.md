# Local clip splitting from the clip step — 2026-11-04

## Member route Material hotfix — 2026-11-05

The owner reported missing-Material error widgets and oversized red/yellow
debug typography after opening a split clip's Caption / AI editor in APK 12110.
The earlier 5,518-test run did pass, but its coverage did not navigate into this
standalone editor. The earlier native member check read UI semantics without
visually validating that route; that evidence was insufficient to claim correct
member rendering. The owner's screenshot and native logcat reproduced the defect.

Baseline: `afa61453`, runtime `3e52737a`, verified `origin/main` / merge base
`8a340638` (ahead 11 / behind 0), branch `codex/clip-group-review`. Existing
generated Windows changes and scratch output are preserved. Runtime fix source:
`8f3b25c7d71972cfb8242a0179ad9f81d9a57d99`.

`uploader_clip_group.dart` now wraps the pushed member route in the same themed
DecoratedBox → Scaffold → SafeArea boundary used by the main composer. Both
caption/AI and channel routes use it. The shared inline factory remains body
content beneath the group Scaffold, with no nested Scaffold. No provider, quota,
subscription, API, database, submission identity or environment change.

`test/uploader_clip_group_route_material_test.dart` opens the real saved group
and presses the actual member AI/channel actions. Both tests reproduced
`No Material widget found` before the fix and pass afterward. They check the
route's Material/Scaffold ancestors, normal inherited typography, usable caption
input, unchanged source draft, no automatic API writes, and no Scaffold nested
inside the shared inline editor. Related group/owner/caption/submission tests:
31 passed. Final regression rerun: 2 passed. Analysis: No issues, 14.4 seconds.
Final complete Mobile run for the frozen source:
`flutter test --no-pub --concurrency=4 --reporter expanded` passed **5,520 tests,
10 optional skips**, exit 0, **8m12s**. Log:
`output/caption-material-fix/full-mobile.log`. The final diff adds one route-shell
fix and its regression file; no unexpected deleted files, imports, assets,
routes, configuration or feature-flag changes.

Guarded Staging x86_64 APK 12111: base build number 8111 plus Flutter's x86_64
split offset, actual manifest version verified before install. Build 71.6s;
APK SHA-256 `4f84cf1323179923315031e2343c7dfc0ddad5a97ae85cd2c61c5d8092158a43`.
Permanent artifact: `E:\PostDeeBuildArchive\clip-group-review-12111\app-x86_64-12111.apk`.
Installed hash matches on emulator-5554, package
`com.postdee.postdee_mobile.staging`, unchanged UID 10197 and internal volume.
All 69 draft/media files matched byte-for-byte immediately before/after update.
The signed-in Basic account and Staging Firebase/API/Test Store settings remain.
After native navigation all 69 files still existed; only the opened group
journal changed through its normal save/reload path. The other 68 files,
including the originals, member manifests and media, stayed identical.

Native verification opened both real member routes, visually inspected normal
header/body/footer text, confirmed the caption keyboard opens with Save above
the keyboard, and found zero missing-Material/Flutter layout errors for the new
process (PID 5104). No AI generation, credit spending or post submission was
performed. A temporary mode-toggle test was discarded; no caption was typed or
saved on the device. Screenshots: `output/caption-material-fix/member-fixed.png`,
`member-keyboard.png` and `channels-fixed.png`. No push, merge or hosted deploy.

Remaining usability observations from the owner's requested read-only follow-up
(not changes in this rendering fix): clarify whether AI reads the whole original
or this particular part; distinguish the two caption-edit actions; provide an
actual package link where the schedule notice says to view packages; identify
the channel needing repair and link to the existing connection screen while
preserving the prepared group. These are source/UI observations, not measured
customer usability results.

## Posting usability follow-up — 2026-11-05

The owner authorized implementing the posting-flow audit. Baseline: branch
`codex/clip-group-review`, HEAD `22f1fcfe`, source `54b222638`, freshly fetched
`origin/main` `8a340638` (merge base identical, ahead 8 / behind 0).
Existing generated Windows changes and untracked output are preserved.

Scope: explicit AI costs and same-context result reuse; usable balance display;
clear caption modes; conditional split advice and per-platform part names;
local/platform draft distinction; current journal caption previews; review
prerequisites; scheduling access; YouTube visibility; clip context during TikTok
consent; group activity and links to existing actual post status. Preserve the
approved caption-first sequence, originals, manual edits/overrides, individual
dates, account binding, recovery identities, Reels settings and quota accounting.
No API/schema/provider/environment/entitlement change; no migration, push, merge,
hosted deployment, real publishing or paid AI request is authorized by this UI
follow-up. Emulator updates use the guarded Staging updater and preserve data.

Verification completed for runtime source `3e52737aed5e1fd8b6139e5f275beed170b87114`
(implementation commits `60090d9b` and `3e52737a`). The older APK/suite receipts
below remain evidence only for their named source. Regression tests preceded
implementation; existing invalid-flow tests now exercise the earlier guard.

- Final `flutter analyze --no-pub`: **No issues**, 14.7 seconds.
- Final `flutter test --no-pub --concurrency=4 --reporter expanded`: **5,518
  passed, 10 optional skips**, exit 0, **7m11s**. Source/tests stayed frozen for
  this complete passing run. Log: `output/posting-ux-audit/full-mobile-12110-final.log`.
- Fresh `origin/main` remained `8a340638`, merge base identical and behind 0.
  Final source diff has no unexpected deleted files, API, Android configuration,
  package/plugin, feature-flag, schema or environment changes. Existing generated
  Windows changes and scratch output remain outside the commits.
- Universal Staging APK built successfully (66.6 seconds), but the guarded
  updater correctly stopped on `INSTALL_FAILED_INSUFFICIENT_STORAGE`; existing
  version 12109, UID 10197 and internal volume stayed intact. No uninstall,
  data clear, storage migration or guard bypass was used.
- Built an x86_64 split APK through the same Staging helper, preserving the
  Firebase/RevenueCat Test Store configuration. Flutter adds 4,000 to x86_64 split
  version codes, so base `--build-number=8110 --target-platform=android-x64
  --split-per-abi` produces actual package **12110**; verified with `aapt` before
  installation. This avoids an artificial version jump for later updates.
- Installed on **emulator-5554**, package `com.postdee.postdee_mobile.staging`,
  UID **10197**, original internal volume, actual version **12110**. Built and
  installed APK SHA-256 both:
  `364386b1a49ec88cb55912421cb3a51a615093f8f86b0503e3536d3e77dab1f9`.
  Preserved artifact: `E:\PostDeeBuildArchive\clip-group-review-12110\app-x86_64-12110.apk`.
  Universal artifact is retained separately as `app-debug-universal-12110.apk`.
- Helper validated Staging API `https://postdee-api-staging.onrender.com`,
  Firebase enabled, mock auth disabled, Staging Firebase project
  `project-798caf7e-85b8-45e3-af7`, and Test Store billing (SDK key never logged).
  Native startup showed STAGING and retained the signed-in Basic account:
  unverified phone, zero connected channels, and dormant purchased credits.
- Immediately before/after update all **60 local draft/media files matched
  byte-for-byte**. Native checks reopened the existing 3-part set, showed
  Facebook part 1/2 → full clip for TikTok/YouTube/Instagram → Facebook part 2/2,
  exercised the visible AI shortcut and per-part AI editor (correct 0:00–1:30
  source, no generation), and returned to a visible Step 1 + saved feedback.
  Draft count remained **14**. An empty review shortcut was blocked with the
  missing-clip explanation. Screenshots: `output/posting-ux-audit/12110-*.png`.
- After these navigation checks all 60 files remained; only the opened group
  journal changed from its normal Back save. All source/media files and ordinary
  draft manifests stayed identical. No captions or schedules were edited.
- No live AI credits, real posts, subscription changes, API deployment, database
  migration, push or merge. Paid/connected delivery/results paths are verified
  by mock/widget tests, not claimed as a new real-account publishing proof.

Integration regression checks retained publishing/consent/recovery assertions
while preparing valid clips, captions and platform settings before review.
Invalid intents now assert the earlier blocked section rather than expecting
an inaccessible review page. Settings helpers flush pending caret scrolling
before explicit consent taps. The AI shortcut initially used a reparented
GlobalKey; an existing draft-delete test reproduced a modal semantics assertion.
The fix uses the currently mounted Builder context instead, retaining the
shortcut without reparenting its render tree. AI reuse and draft deletion then
passed together. Expired/invalid scheduling errors now reveal their notice.
Resource-failed/aborted concurrent test attempts are not passing evidence;
the final full run uses one Flutter command with scoped build/temp caches on E:.

Status updated 2026-11-05: the owner selected **variant 2, shared caption first**
for the real grouped flow. After splitting/reopening, the shared caption and
existing AI panel open directly inline. Source `54b222638` builds on `cffe7191`
and verified `main` `8a340638`, retaining the split utility, 109-language picker
and connection-screen update. Final analysis, the 5,489-test complete Mobile suite
(10 optional skips), guarded Staging APK 12109 build/install and fresh native
shared-caption/override/context restart checks passed within the limits below.
APK 12108 proves the earlier grouped-review
version; APK 12104/12105 prove older splitting behavior. Those checks do not
verify the new inline shared-AI flow. No merge, push or hosted deployment.

## Approved behavior and baseline

The owner selected **design 1, the inline card on the existing clip-selection
screen**, after reviewing an interactive prototype. When a measured clip is too
long for a destination, the card offers a split plan instead of silently cutting
or posting it. The default splits only affected channels; another mode uses the
same parts for every selected channel. The source is retained in both cases.

The isolated managed worktree initially started at freshly fetched `origin/main`
`927a302002841aab770aeba30cc6302f89783261` (`927a3020`) on branch
`codex/clip-parts`. It was verified at zero ahead/behind before implementation.
The older root checkout and its unrelated uncommitted work are preserved.

During implementation, `main` advanced to `3b7da9d3` with PR #62's searchable
109-language catalog. The feature was committed locally and rebased onto that
verified baseline, preserving both the language work and splitting sections in
the documentation conflicts. That phase's feature commit was
`8b8ac033736d6fec4e5803842e3fd62846894444`. Runtime implementation code did not
change between that commit and its APK 12105 checks.
The 12104 checks below belong to the initial `927a3020` candidate, not a claimed
complete-suite result for the rebased source.

Existing capabilities to retain include the four-step composer, local draft
ownership and recovery, AI captions and output-language selection, cover
editing, channel-bound settings, source/outgoing duration checks, TikTok Direct
consent, Facebook Page Reels delivery choices, scheduling entitlements,
idempotent submission and per-channel post-unit accounting.

On 2026-11-05 the owner approved reviewing every result in a single set, editing
captions/covers/settings, selecting each clip's date/time independently and
explicitly confirming the final set. When `main` advanced during implementation,
the intended work was checkpointed and ported into a new managed worktree from
`8a340638` rather than continuing on the stale baseline. The earlier checkout and
unrelated files remain preserved.

The later same-day prototype decision selects **shared-caption-first variant 2**,
separate from the original choice of inline split card. The shared editor opens
expanded, with the existing AI panel and compact member rows in the same flow.
Manual generation uses the full original; member overrides and independent
dates/times remain. The retained original backup is never rewritten by shared
caption/context edits.

## User flow

1. Select or resume a clip. Keep the existing quota and duration guide, adding
   the approved inline offer when a known duration exceeds a channel limit.
2. Open the Thai/English split-plan screen. Choose destinations, affected-channel
   or matching-part mode, inspect each source interval and preview it without
   encoding. A valid first boundary can be adjusted while retaining all content.
3. Show the number of resulting local drafts and the post-unit estimate. This
   is an estimate for later creation of posts, not a quota reservation or a
   guarantee that the connected accounts are publish-ready.
4. On explicit confirmation, save the entire current form and original media
   in the existing owner-bound draft store before preparing any parts.
5. Encode required ranges locally, verify outputs and copy them into independent
   drafts with new submission identities. Full-length destinations use a copied
   source instead of unnecessary encoding. Commit one local group and open all
   results together for review. Keep the original stored as the group's source.
6. Open directly into the expanded shared caption and existing inline AI panel.
   AI runs only when clicked and uses the full retained `group.sourceDraftId`.
   Use compact member rows for a manual override, member AI, cover or channel
   settings. Shared changes preserve overrides, accepted results and unresolved
   receipt intents. Confirm explicitly before restoring a member's inheritance.
   Member editors retain the planned source and destination membership.
7. Choose immediate delivery or set each clip's date/time independently. There
   is no interval rule; remembered desired times survive switching to immediate.
8. Review the final set and explicitly confirm. Pending members use the existing
   single-post pipeline serially with fresh checks. Save/reopen the whole set as
   one Drafts row. Accepted members keep their recorded result; partial completion
   resumes only remaining clips. Platform-feed ordering is not guaranteed.

Opening the plan, previewing, encoding and saving drafts create no API upload,
post or AI request and consume no post units or caption credits. The existing
`POST /posts` path remains the point at which the existing quota rules apply.
Choosing AI is a separate explicit action using the existing caption upload/API
and credit rules; entering this screen or reopening a group never starts it.

## Planning and media preparation

`ClipSplitPlan` is independent of native rendering. It uses the same duration
policy as the uploader guide and preflight, normalizes measured boundaries and
balances parts so an almost-exact multiple does not produce an invalid tiny
tail. Facebook and Instagram minimum durations are retained. TikTok Direct
uses the connected creator's verified maximum, capped by PostDee; an unknown
Direct maximum disables that selection rather than assuming the inbox limit.
The existing inbox-transfer rule remains separate from Direct Post.

Identical source intervals across selected channels become one file/draft job.
For a 270-second source under the current rules, affected-channel mode yields
three Facebook parts, two YouTube parts and one shared full-length TikTok/
Instagram draft: six drafts and seven eventual post units. Matching-part mode
can use three shared 90-second drafts for all four channels: twelve eventual
post units. These illustrate the app's rules; they are not universal consumer
app limits or proof of a particular account's readiness. At most **64 distinct
output jobs** are allowed per plan.

`FfmpegClipSegmenter` uses the existing native FFmpeg dependency, H.264 encoding,
CFR30 and AAC when source audio exists. It uses safe generated output paths in
an owned temporary directory, keeps the source immutable, and validates each
output's measured duration, dimensions, codecs, audio and decodable video.
Hard channel limits remain enforced after encoding. Timeouts and cancellation
target only that operation's native sessions; they never globally cancel other
FFmpeg work. There is no AI cut-point detection, subtitle burn-in, music or
editing-minutes system. The retired AI editor and `/ai-edits/*` remain retired.

## Draft and failure boundaries

`ClipSplitDraftService` validates native results before any part draft is saved.
Each new draft gets a fresh safe identity and its own existing submission ID;
existing IDs are checked and never intentionally reused. Source and owner/session
checks surround asynchronous work. Matching source ranges can carry multiple
destinations under the current single-video post contract.

Retain user publishing choices such as TikTok Direct/inbox mode, Facebook
`PUBLISH|PAGE_DRAFT`, optional Meta AI disclosures, caption-language preference
and watermark choice. Reset per-media TikTok music/branded-content confirmations,
creator revision/duration and YouTube community-guidelines certification. New
parts do not inherit the original upload receipt, cover-frame position or
schedule. Existing text is marked for review; later submission still performs
the current readiness, consent, actual-file preflight and entitlement checks.

`ClipGroupDraft` stores a version-1 owner-bound journal under the existing draft
owner directory. Optional `clipGroupId`/source-role fields keep draft manifest
version 3 and older drafts compatible; no abstract draft-store API is broken.
Group writes use the same owner serialization queue, atomic file promotion and
revision comparison. Source/member identities, ranges and destinations remain
immutable. A valid manifest controls the single group row/source visibility;
projection repairs tags and leaves orphan/conflicting records visible ordinarily.

The group journal retains shared text, each member's shared/custom choice and
desired schedule independently of effective child schedules. Group intent is
saved before child edits; reopening/retrying reconciles interrupted local writes.
Child editors bind to the opening auth lifecycle, including sign-out/sign-in to
the same UID. Runtime media consent is reviewed again rather than restored as
fresh consent from disk.

An optional `captionContext` in the same version-1 journal stores `aiGuidance`
and canonical `captionLanguage` (`auto` plus the existing 109 output choices).
Older journals omit it and read as null; unrelated copies retain it. Unknown
language/context data is rejected, and the existing 262144-byte journal ceiling
still applies. Completed groups cannot rewrite context. The source backup's
caption, guidance, language, media, cover, settings, schedule and submission ID
remain untouched. Pending upload receipts lock shared/context changes before CAS.

The shared editor reuses existing AI quota, style, undo and fallback behavior.
Its generation context binds the current auth lifecycle, group revision and
full-source identity; stale asynchronous results cannot apply after those change.
Per-member overrides remain separate. This adds no provider, API, database or
AI-credit-rule change and does not restore retired AI editing.

On a live failure or cancellation, remove only newly intended draft IDs,
including an ID whose filesystem promotion may have succeeded before save
reported an error. Never delete a pre-existing or original draft. Roll back a
new group only at its untouched revision with no accepted member. If user edits
or accepted receipts exist, preserve the group, children and source and report
residual IDs. Tag/untag operations reload the source and preserve its latest
caption/cover/schedule. Always attempt temporary cleanup and report failures.
Process termination can leave partial local drafts; no cross-process batch
transaction is added. Inspect Drafts before retrying preparation.

`ClipGroupSubmission` snapshots confirmed group/member intent and persists each
accepted post ID, status and effective schedule before deleting that child draft.
Accepted posts are never rolled back or submitted again. Upload receipts and
independent request IDs remain the recovery source if acknowledgement saving
fails. An unknown outcome first performs the existing read-only recovery. Only
explicit Not Found allows a freshly reviewed retry using the exact original ID
and upload receipt; network/lookup errors never imply Not Found. An expired
unknown schedule permits recovery only, with no new POST. Quota/readiness are
checked freshly for every member; the server's existing accounting remains final.

Facebook delivery retains `platform: 'facebook'` and
`platformSpecificData.contentType: 'reel'`, existing `PUBLISH|PAGE_DRAFT` and
optional `isAiGenerated`. There is no Page-feed-video fallback and no reuse of
Facebook Page Video limits for Page Reels.

## Compatibility and delivery

- Mobile-only group storage/review, using existing publishing API contracts and
  backward-compatible draft metadata plus a separate local group journal.
- No route, DTO, Prisma model, migration, entitlement, price, environment variable
  or hosted-service configuration changes are required.
- No server deployment order is introduced. Current and earlier guarded Staging
  build evidence is recorded separately below; no hosted service changed.
- Existing and original drafts, scheduled posts, publishing records, purchased
  credits and all retired-feature boundaries remain in place.
- The `AGENTS.md` retirement table is unchanged because this time-based uploader
  utility does not restore any retired AI-editing feature.

## Current variant 2 verification — 2026-11-05

### Source and automated verification

- Final source: **`54b222638dbbc5085f2096a0a952f8b7e727076c`**, building on
  `cffe7191` and verified `main` **`8a340638`**. Final diff capability review
  found only intended changes and no deleted files or API/schema/environment/
  dependency/entitlement changes.
- Final whole-project Mobile analysis passed in **18.0s** with no issues.
- Final complete Mobile suite on **`54b222638`**:
  `flutter test --no-pub --concurrency=4 --reporter expanded` passed **5,489 tests
  with 10 optional skips** in **8m01s** (exit 0, final log: All tests passed).
- Root integration passed **39 tests** in **22s**, including full-original AI
  source/manual generation, explicit preview, overrides/dates/IDs, source-backup
  preservation and existing submission recovery. The two audit regressions prove
  guidance-only Back saves/reopens and a receipt appearing while open cannot trap
  recovery review or rewrite context. Other component runs include 13 child-editor
  cases, 18 group-screen cases, 4 visual fixtures and the related 108-test store/
  submission/split/draft run. These overlap; do not add them to the full-suite count.
  Context tests cover legacy reads, copy/clear, CAS, unknown-language/byte bounds
  and completed-context immutability.

### Exact Staging APK and data preservation

- Guarded helper built APK **12109** in **42.8s**, package
  **`com.postdee.postdee_mobile.staging`**. Built/installed SHA-256:
  **`bdfc5338181cad46dd3e97f2acc198d83cfbe05e0952d169653c656a72f2179b`**.
- Guarded in-place update on **`emulator-5554`** retained **UID 10197** and the
  same internal storage. All **22 JSON files** (20 draft manifests and two group
  journals) had identical hashes after install and before launch. An in-progress
  normal form was explicitly saved before updating; Drafts moved 11 → 12 rows
  as expected from that save.
- Staging API health returned **HTTP 200**. Firebase project remained
  **`project-798caf7e-85b8-45e3-af7`**, Firebase auth enabled/mock auth disabled,
  with **Test Store** billing mode. No hosted configuration changed.
- C: fell to approximately 97 MB free after build. Only this task's completed
  generated `apps/mobile/build/app` was moved to
  `E:\PostDeeBuildArchive\clip-group-review-12109\app`, freeing 1.7 GB; no user
  data was removed. The archived `outputs\flutter-apk\app-debug.apk` retained
  the same checksum while the full tests continued.

### Fresh native inline-flow verification

On exact APK **12109**, a fresh 180-second 360x640 source cut into two Facebook
parts plus one full-length TikTok/YouTube/Instagram member: **three clips in one
set, five estimated post units**. It opened **เขียนแคปชั่นทั้งชุด** directly. The
existing AI panel showed the full-original filename, 109-language picker and style
controls on the same page. The Basic account showed the expected Starter/Pro gate
with zero available AI credits. No AI/provider request, spend, upload or post ran.

Entering **Shared caption 12109** updated the caption count to **3/3**. The first
member was saved as **Shared caption 12109 - part1**; changing the main text to
**Shared caption 12109 - updated** kept that custom text and updated the other
two members. Native journal/child-manifest checks confirmed the first member's
`usesSharedCaption=false` and the remaining two `true`. The per-clip date/time
page was reachable; paid native date/time selection remains unverified.

After returning to the caption page, changing **only** the AI output language
from Automatic to Thai and pressing Back without Save persisted
`captionContext.captionLanguage=th`. Drafts increased **12 → 13** as one new set.
A force-stop/restart without clearing app data followed by Home's **Review entire
set** reopened stage 0 with the updated main text and Thai selected. All three
rows retained the custom first caption and the two shared captions. Opening
**กลับไปใช้แคปชั่นหลัก** and cancelling its confirmation preserved the override.

All **22 pre-existing JSON files** retained their hashes after this native flow.
The new source backup's manifest and video hashes also matched the snapshot
captured before edits (`output/caption-first/source-before-edit.json`). Video
SHA-256 remained
**`eacbf06116ec259b2f6da526aef9831f2bbf1c6431aba7a97491bea452e32fab`**.
Current APK 12109 screenshots include `output/caption-first/final-caption.png`
(reopened shared text, Thai and existing AI controls),
`output/caption-first/overrides-reopened.png` (all three members in one card)
and `output/caption-first/landing.png`. The final screenshots were visually
inspected; these are fresh native evidence, separate from the prior APK 12108
grouped-review screenshots. The app was left at the caption page's top.

The current Basic account has zero usable post quota, dormant balances of 550
post units/300 AI credits and no connected destinations; these gates remain in
force. No actual AI generation, credit spend or social posting is claimed.
Paid-account native scheduling pickers, physical phones, iOS and real publishing
remain unverified. A Basic AI/schedule lock is an expected entitlement result,
not evidence of live provider success. Controlled pipeline tests verify the
full-original source/request, credit handling, preview, undo and stale-result
guards; they do not replace paid live AI acceptance. No API deploy, migration, hosted
environment/bootstrap change, merge or push occurred.

## Prior grouped-review verification — APK 12108, 2026-11-05

The following source/build/native evidence predates shared-caption-first variant
2 and its optional caption context. Preserve it as the earlier grouped version's
record, rather than current proof.

### Source and automated verification

- Final app source: **`b6efa3e5b22abca1892231bdefcba2e9db75001f`**, following the
  `f3b97910` implementation checkpoint and final copy correction. Freshly fetched
  `main` remains **`8a340638`**; this source is 5 ahead / 0 behind.
- Final complete Mobile suite on **`b6efa3e5`**:
  `flutter test --no-pub --concurrency=4 --reporter expanded` passed **5,460 tests
  with 10 optional skips** in **7m01s** (exit 0, final log: All tests passed).
- Final Mobile analysis passed in **19.3s** with no issues.
- Final baseline diff review and whitespace checks passed: no deleted files or
  API/schema/environment/dependency/entitlement changes. Existing caption
  languages, connection-screen changes, source IDs and compatibility remain.

### Exact Staging APK and preserved data

- Guarded helper built version **12108** in **42.3s** from the final source.
  Package: **`com.postdee.postdee_mobile.staging`**. Built and installed APK
  SHA-256: **`503bc8852b6726453df199d9394432ba2a88b2d357d7306a29c28a1ad5e41bf4`**.
- Guarded in-place update on **`emulator-5554`** retained **UID 10197** and the
  same internal volume. All **16 local JSON files** (15 draft manifests and one
  group journal) retained identical checksums across the 12108 update. After
  member editing, all original 11 draft manifests were still unchanged.
- Staging API health returned **HTTP 200**. Firebase project is
  **`project-798caf7e-85b8-45e3-af7`**, Firebase auth enabled, mock auth disabled,
  with **Test Store** billing mode. No API deployment or environment change.
- The first 12107 build stopped solely because C: had approximately 16 MB free.
  Only this task's old generated build directory (2.94 GB) was moved to
  `E:\PostDeeBuildArchive\clip-parts-20261105\build`; no user data was deleted.
  Idle Gradle daemons were stopped to release a stale lock, and guarded APK
  12107 then built in 240.3s before the final 12108 copy-fix build.

### Native group-flow evidence and limits

On APK 12107, an actual 180-second 360x640 source prepared two Facebook parts
(0–90 and 90–180 seconds) and one full-length TikTok/YouTube/Instagram member:
**three clips in one set, five estimated post units**. The source SHA-256 was
**`eacbf06116ec259b2f6da526aef9831f2bbf1c6431aba7a97491bea452e32fab`**.
Shared caption plus an individual override saved, and preview played at
0:16 / 1:30. Drafts increased from 9 to 10 rows as one group. All original 11
draft manifests survived installation unchanged.

After the guarded 12108 update and restart, Home's **Review entire set** reopened
all three parts and their captions. The last-part preview showed 0:00 / 1:30
with the source's burned-in 1:30 marker. The member channel-settings editor
opened in save-only mode and saved back to the group. The per-clip scheduling
page was reachable; the Basic account correctly refused scheduling. Paid-account
native date/time pickers were **not verified**; automated tests cover independent
UTC schedules and remembered desired times.

Confirmation stayed disabled for zero usable quota, unavailable channels and
the unverified Basic account. Home retained dormant balances of 550 post units
and 300 AI credits while usable post quota was zero. No upload, POST/publishing
request or live AI generation occurred. Screenshots and supporting output are
under `output/clip-group-review`.

Physical phones, iOS, real publishing and live 109-language model quality remain
separate checks. These local checks do not establish real-account delivery.
No API deployment, database migration, environment/bootstrap change, merge or
push was performed.

## Prior-version verification record — 2026-11-04

The remaining evidence applies to the earlier independent-draft implementation,
before the 2026-11-05 grouped-review changes.

Prior-version final component checks reported by the primary agent:

| Area | Reported component result |
| --- | --- |
| Native segmenter | 35 tests passed |
| Draft batch service | 20 tests passed; focused Dart analysis found no issues |
| Planner | 9 tests passed |
| Plan screen | 8 tests passed |
| Visual fixtures | 4 tests passed |
| Uploader integration | 7 tests passed |

These are 83 new component/regression cases; they are not an additional count
to add to the complete suite below.

The service cases cover grouped output and post-unit estimates, full-length
source copies, unique identities, retained Facebook/TikTok choices, reset media
consent, owner cancellation, early/late save failures, rollback leftovers,
temporary cleanup failure, source mutation and invalid native metadata. Native
and planner cases cover minimum/maximum duration, small tails, grouping,
scoped cancellation and output validation. UI fixtures use controlled inputs;
actual native evidence is separated below from those automated tests.

### Initial candidate: APK 12104 on baseline `927a3020`

- `flutter test --no-pub --concurrency=2`: **5,326 tests passed, 10 skipped**,
  completed in 11m47s.
- `flutter analyze` for the initial Mobile candidate: **no issues found**,
  completed in 14s.
- Guarded `tool/postdee-staging.ps1` APK build: passed in 116.7s. Source is
  branch `codex/clip-parts`, baseline `927a3020` plus the task's working diff;
  this is not a claim that the unchanged baseline commit contains the feature.
- Staging package `com.postdee.postdee_mobile.staging`, version code **12104**,
  APK SHA-256
  `b4fe4da62868e3b2adac57c75d45c5354376ebf0f00ee28e8fe01f8fbfe6c52e`.
  The installed hash matches the built APK.

### Initial APK 12104: native emulator success path

The guarded in-place update on **`emulator-5554` / Pixel_8** retained package
UID **10197** and internal storage, increasing version code **12103 → 12104**.
No uninstall, data clear or storage migration was used.

The test source is a synthetic **360x640, 30 FPS, 180-second** video with audio,
**24,770,593 bytes**, SHA-256
`eacbf06116ec259b2f6da526aef9831f2bbf1c6431aba7a97491bea452e32fab`.
The source-range preview was sought to 90 seconds and playback was observed.
Confirming the affected-channel plan saved the original separately and created
three result drafts: **two 90-second Facebook parts** and **one shared
full-length TikTok/YouTube/Instagram draft**, with **five estimated post units**.

Both encoded outputs were checked from their actual files:

| Output | Verified media | Bytes | SHA-256 |
| --- | --- | --- | --- |
| First Facebook part | H.264, 360x640, 30 FPS, 2,700 frames, 90.000000s; AAC 48 kHz mono, 90s | 52,061,976 | `ae3d4dd8f86c43ab6d0a21005e91fa305c868eb14d2f5ea4553954100c607bda` |
| Second Facebook part | H.264, 360x640, 30 FPS, 2,700 frames, 90.000000s; AAC 48 kHz mono, 90s | 52,813,456 | `112cfecac7af8ccc37c834fcb406b0dc06d7aab9e4fba99c90813e0440943435` |

Full video and audio desktop decoding passed without errors. The saved original
and copied full-length result match the source SHA-256 exactly. Opening the
second part from Drafts passed; the pre-existing `1000000795` user draft remained
available. New local manifests had no `uploadedMedia` receipts. This preparation
did not upload a file, create a post, publish through an API or consume post quota.

Local evidence is in `D:\PostDeeMobile\output\clip-parts`:

- `emulator-split-prompt.png`
- `emulator-split-result.png`
- `flutter-test.log`
- `staging-build.log`

### Final rebased candidate: APK 12105

- Baseline: updated `main` **`3b7da9d3`**, preserving the searchable
  **109-language** catalog from PR #62.
- Feature/runtime source: **`8b8ac033736d6fec4e5803842e3fd62846894444`** on
  `codex/clip-parts`; the runtime code was unchanged after this commit.
- Final Mobile analysis: **no issues found**, completed in **12.9s**.
- Generated caption-language catalog parity check: **passed**, retaining all
  109 API/Mobile entries. This is catalog compatibility evidence, not new live
  provider or per-language caption-quality validation.
- Guarded Staging build: **passed**, completed in **36.0s**, version code
  **12105**. Built APK SHA-256:
  `4ab5741d6148e1265dcb6c19e31ee4c76a90cf86efda284349d9ee6211cac3c5`.
- Guarded update on `emulator-5554` / Pixel_8: **12104 → 12105**, retaining
  **UID 10197** and **internal storage**. Installed and built APK hashes match.
- Final complete Mobile suite, `flutter test --no-pub --concurrency=4`:
  **5,351 tests passed, 10 optional tests skipped**, completed in **6m51s**.
  Evidence is `D:\PostDeeMobile\output\clip-parts\flutter-test-integrated.log`.
  This is the result for the rebased source; the initial 5,326-test result above
  remains attached only to the earlier candidate.
- Final diff review against `main` `3b7da9d3`: **passed**. Only intended feature
  and verification-document files were present, with no unexpected deletion or
  API, schema, configuration, feature-flag or dependency change. The existing
  109-language picker and generated catalog remain intact.
- No API deployment, database migration, bootstrap configuration, entitlement
  or environment change is introduced by splitting. No remote merge or push
  was performed.

### Final APK 12105: actual native cancellation

The first cancellation attempt paused after external user input was detected
twice. The owner then explicitly authorized continuing Emulator testing. On
the final installed APK, the source and saved parts were reopened, an actual
new native cut started, and Stop was pressed while progress was **0/3**. The
progress dialog closed without creating new part drafts.

Read-only inspection confirmed the relevant existing native render session:

- Session **6**, generating **`part_0000.mp4`**, returned **255 (cancelled)**.
- Started **2026-11-04 15:53:24.388 UTC** and ended
  **15:53:33.761 UTC**, corresponding to **22:53:24.388–22:53:33.761** in
  Asia/Bangkok on 4 November.
- Active native sessions afterward: **0**.
- All **five current-owner draft IDs** remained unchanged, including the older
  user draft; no `postdee-clip-parts` temporary-cache directory remained.
- The saved original and full-length copy retained source SHA-256
  `eacbf06116ec259b2f6da526aef9831f2bbf1c6431aba7a97491bea452e32fab`.
  All four test-media drafts (original, two parts and full-length copy) still
  had no `uploadedMedia` receipt.

The inspection helper only read the existing native/session and local-file
state; it did not start a render, create a job, call a publishing API or execute
another UI action. The actual render and Stop action came from the app flow.
The six core native/planner/service UI files are byte-identical between the
successful APK 12104 splitting implementation and final APK 12105 source. Thus
the initial successful-file evidence and final cancellation evidence remain
separate, with neither attributed to a run that did not happen.

### Remaining verification boundaries

- iOS, physical phones and real-account social publishing were not tested.
- Retaining all 109 output-language choices and passing generated-catalog parity
  do not prove live provider acceptance or generation quality for every language;
  those checks are outside this clip-splitting task.
- Process-kill recovery still has the documented partial-local-draft limitation.
- No remote merge, push, Production deployment, hosted configuration change or
  real-account end-to-end publishing test was performed.

The prior-version automated suite, native success/cancellation evidence and
source audit establish that earlier Staging implementation's checked behavior.
They do not establish the new grouped flow, production publishing readiness or
close the out-of-scope checks.
