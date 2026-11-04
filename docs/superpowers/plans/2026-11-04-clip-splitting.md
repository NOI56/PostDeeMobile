# Local clip splitting from the clip step — 2026-11-04

Status updated 2026-11-05: the owner approved implementing the grouped-review
prototype in the real app. The active `codex/clip-group-review` worktree uses
verified `main` `8a340638` and preserves the earlier splitting feature, searchable
109-language picker and PR #63's connection-screen change. Current group-flow
full-suite, exact-build/install, emulator smoke and final diff verification are
pending. APK 12104/12105 evidence below belongs to the prior independent-draft
version; it does not establish the new grouped flow. No merge, push or hosted
deployment is included.

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
6. Review a shared caption or edit individual captions, covers and publishing
   settings. Member editors retain the planned source and destination membership.
7. Choose immediate delivery or set each clip's date/time independently. There
   is no interval rule; remembered desired times survive switching to immediate.
8. Review the final set and explicitly confirm. Pending members use the existing
   single-post pipeline serially with fresh checks. Save/reopen the whole set as
   one Drafts row. Accepted members keep their recorded result; partial completion
   resumes only remaining clips. Platform-feed ordering is not guaranteed.

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
- No server deployment order is introduced. Earlier guarded Staging builds are
  recorded below; current grouped-flow verification remains pending.
- Existing and original drafts, scheduled posts, publishing records, purchased
  credits and all retired-feature boundaries remain in place.
- The `AGENTS.md` retirement table is unchanged because this time-based uploader
  utility does not restore any retired AI-editing feature.

## Current grouped-flow verification — 2026-11-05

The primary agent will fill this record from completed commands and exact build
evidence. Current status: **full Mobile suite pending; analysis pending; exact
Staging build/install and emulator group-flow smoke pending; final baseline diff
audit pending**. Component checks do not replace those gates. Physical phones,
iOS, real publishing and live 109-language model quality remain separate checks.
No API deployment, database migration, environment/bootstrap change, merge or
push is required or authorized by this implementation task.

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
