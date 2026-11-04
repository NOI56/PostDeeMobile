# Local clip splitting from the clip step — 2026-11-04

Status: Staging APK 12104 is installed and the native success path is verified.
The full Mobile suite and analysis passed. Live native cancellation, iOS,
physical phones, real social publishing and final source-diff audit remain
unverified as detailed below. No merge, push or hosted deployment was performed.

## Approved behavior and baseline

The owner selected **design 1, the inline card on the existing clip-selection
screen**, after reviewing an interactive prototype. When a measured clip is too
long for a destination, the card offers a split plan instead of silently cutting
or posting it. The default splits only affected channels; another mode uses the
same parts for every selected channel. The source is retained in both cases.

The isolated managed worktree starts at freshly fetched `origin/main`
`927a302002841aab770aeba30cc6302f89783261` (`927a3020`) on branch
`codex/clip-parts`. It was verified at zero ahead/behind before implementation.
The older root checkout and its unrelated uncommitted work are preserved.

Existing capabilities to retain include the four-step composer, local draft
ownership and recovery, AI captions and output-language selection, cover
editing, channel-bound settings, source/outgoing duration checks, TikTok Direct
consent, Facebook Page Reels delivery choices, scheduling entitlements,
idempotent submission and per-channel post-unit accounting.

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
   source instead of unnecessary encoding. Open the first result for caption
   review; the other results remain available through the existing draft list.
6. The seller reviews each draft's caption, cover, destination settings and
   schedule through the current composer. There is no automatic bulk submission
   or promise that separate platform feeds display parts in submission order.

Opening the plan, previewing, encoding and saving drafts create no API upload,
post or AI request and consume no post units or caption credits. The existing
`POST /posts` path remains the point at which the existing quota rules apply.

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

On a live failure or cancellation, remove only newly intended draft IDs,
including an ID whose filesystem promotion may have succeeded before save
reported an error. Never delete a pre-existing or original draft. Always attempt
temporary cleanup, and surface residual IDs or cleanup failures rather than
reporting success. A process killed during persistence can leave a subset of
local part drafts, because this change does not add a cross-process batch
transaction. Inspect Drafts before retrying; no part has been posted by this
preparation step.

Facebook delivery retains `platform: 'facebook'` and
`platformSpecificData.contentType: 'reel'`, existing `PUBLISH|PAGE_DRAFT` and
optional `isAiGenerated`. There is no Page-feed-video fallback and no reuse of
Facebook Page Video limits for Page Reels.

## Compatibility and delivery

- Mobile-only preparation, using the existing API contract and draft manifest.
- No route, DTO, Prisma model, migration, entitlement, price, environment variable
  or hosted-service configuration changes are required.
- No server deployment order is introduced. The guarded Staging Mobile build
  and in-place emulator update are recorded below; no hosted service changed.
- Existing and original drafts, scheduled posts, publishing records, purchased
  credits and all retired-feature boundaries remain in place.
- The `AGENTS.md` retirement table is unchanged because this time-based uploader
  utility does not restore any retired AI-editing feature.

## Verification record

Final component checks reported by the primary agent:

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

### Complete Mobile checks

- `flutter test --no-pub --concurrency=2`: **5,326 tests passed, 10 skipped**,
  completed in 11m47s.
- `flutter analyze` for Mobile: **no issues found**, completed in 14s. The
  primary agent is doing the final source audit/analysis pass separately; this
  records the completed analysis run rather than predicting that later result.
- Guarded `tool/postdee-staging.ps1` APK build: passed in 116.7s. Source is
  branch `codex/clip-parts`, baseline `927a3020` plus the task's working diff;
  this is not a claim that the unchanged baseline commit contains the feature.
- Staging package `com.postdee.postdee_mobile.staging`, version code **12104**,
  APK SHA-256
  `b4fe4da62868e3b2adac57c75d45c5354376ebf0f00ee28e8fe01f8fbfe6c52e`.
  The installed hash matches the built APK.

### Native emulator success path

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

### Remaining verification boundaries

- **Live native cancellation was not completed.** External user input was
  detected twice in the Emulator, so automation stopped and control was handed
  back. Scoped cancellation and owner changes have automated native-service and
  uploader coverage; that is not a passed live-device cancellation check.
- iOS, physical phones and real-account social publishing were not tested.
- Process-kill recovery still has the documented partial-local-draft limitation.
- The primary agent's final diff audit against `927a3020`, including unchanged
  API/schema/flags, remains in progress. No unexplained issue was reported at
  the time of this record; this is not a completed-audit claim.
- No merge, push, Production deployment, hosted configuration change or
  real-account end-to-end publishing test was performed.

The native success path and complete automated suite do not close these
remaining checks or establish production publishing readiness.
