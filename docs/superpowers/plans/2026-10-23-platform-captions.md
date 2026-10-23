# Four-platform advanced captions — 2026-10-23

## Request and baseline

The user approved the advanced-caption prototype: opening advanced settings
hides the shared caption, permits manually writing separate text for all four
supported destinations, or explicitly asks AI to write the four variants.
The implementation baseline is verified `origin/main`
`39a97a64acfc7ca5a44130b58b1214373f5fbbe6` on `codex/platform-captions`, in
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`.
Preserve unrelated existing generated Windows plugin changes.

Scope includes TikTok, YouTube Shorts, Instagram Reels and Facebook Page Video.
`FACEBOOK_REELS` remains the internal compatibility key for Page Video. This
feature adds no unsupported destinations, new provider integration, credential,
environment variable, database column or migration.

## Intended behavior

- Shared mode retains the original caption editor and text. Advanced mode hides
  it, shows four editable platform cards and retains the hidden shared text.
- First activation initializes variants from the shared caption; subsequent
  toggles retain manual edits. Returning to shared mode retains advanced text
  locally but omits platform overrides from publishing requests.
- Local drafts preserve mode and per-platform text. Reusable saved channel
  defaults retain their existing settings without capturing post-specific
  captions or the caption mode.
- Explicit AI generation analyzes the selected clip once for a requested set,
  retaining Starter audio mode and Pro selected-frame support, plus saved
  writing style and evidence rules. Preview all four before applying; users can
  dismiss without overwriting text, or apply and edit further. Undo restores
  the pre-AI text and review state; mode toggles retain this local undo action.
- Account/clip ownership, request identity, mode and concurrent edits invalidate
  stale results. Do not overwrite newly edited text when a late result arrives.
- Review, validation, submission and worker/provider delivery use each
  destination's effective caption. YouTube's automatic title derives from its
  effective description; an explicit custom title is preserved.

## Contract and persistence

`platformSettings.<platform>.caption` is an optional, trimmed string inside the
existing per-post JSON snapshot. TikTok, Instagram and Facebook reject empty
overrides. YouTube permits `""` or whitespace, normalized to an explicit empty
description; it does not fall back to shared text and still requires a valid
title and all existing YouTube settings. Missing values use top-level
`caption`, maintaining old clients and stored posts. Required privacy,
disclosure, target and platform-specific settings are still required. The
top-level caption remains the compatibility summary; Mobile uses selected
effective text for it in advanced mode while keeping original shared text in
the local draft. Overrides participate in immutable intent comparison and
read-only recovery, so changed accepted text does not silently replace a prior
submission. JSON persistence and queued execution preserve the chosen values.

`POST /captions/generate-from-clip` accepts optional `platforms`, an array of
1–4 unique supported enum values. It adds `platformCaptions`, a map of every
requested key to `{ caption: string, hashtags: string[] }`, alongside the
existing shared fields. Omission preserves the legacy behavior. A set reserves
one monthly/add-on generation and calls the provider generation operation once;
existing transient HTTP retries within that operation remain possible.

The prompt adapts wording by platform from the same supplied clip evidence and
style. It forbids invented prices, product claims, promotions and copied facts
from style examples. Parsing requires all selected variants; missing/malformed
results trigger the whole-set fallback rather than a partial AI success.
Selected local templates contain explicit editable placeholders, not inferred
clip facts, and are labeled `isFallback: true`. `quota.charged` is false only
when the reservation release succeeds; failed releases remain charged. Existing
owner checks, media errors/limits, cleanup, plan gates and quota fences apply.

## Files

- API captions: `captionService.ts`, `captionRoutes.ts`,
  `realClipCaptionProvider.ts` and `platformCaptionGeneration.test.ts`.
- API post/settings/validation and worker/provider files carry effective
  captions through parsing, immutable persistence and destination delivery.
- Mobile: API DTOs, uploader/platform settings, caption editors and preview,
  preflight validation, local draft/settings behavior and targeted tests.
- Product/contract notes: `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`
  and this record.

## Verification recorded so far

Tests were added before caption-provider implementation; the initial run had
23 expected failures for unsupported multi-platform behavior. After the patch:

- `npm.cmd run test -- src/modules/captions`: **8 files, 164 tests passed**.
- `npm.cmd run typecheck`: passed after the complete captions patch.
- `git diff --check`: passed for the checked working tree; unrelated generated
  Windows plugin files still emit existing line-ending notices.

New caption tests cover invalid/empty/duplicate platforms, legacy shape,
four distinct structured outputs, selected-only output, one provider operation
and reservation, malformed/missing variants, alternate-adapter validation,
transparent refunded fallback/no-provider behavior, paid/owner/monthly limits,
expired media and owned R2 cleanup. All provider and storage interactions here
are test doubles, not remote acceptance.

Final combined checks on this candidate:

- Production-matching Node **22.23.3**, npm **10.9.9**:
  `npm.cmd run test -- --maxWorkers=2` passed **2,489 tests**, with **25 skipped**
  (**149 suites passed, 4 skipped**). Typecheck, build, Prisma schema validation
  and Prisma helper TypeScript checks also passed. No database was migrated.
- `flutter analyze`: **No issues found**.
- `flutter test --concurrency=2 --reporter expanded`: **2,767 passed, 6 skipped**
  in **5:11**, exit 0. This includes existing uploader, owner, disclosure,
  quota, draft, retry and UI regressions.
- The final focused uploader/submission/preflight/review run passed **51 tests**.
  It verifies main-field hiding, four edits/mode retention, one AI request,
  preview cancellation/application/undo, stale-result protection, owner changes,
  exact create/recovery values, replacement-clip draft retention, TikTok-only
  consent invalidation, YouTube title-only posts and 320px/1.7 text-scale layout.
- The first full Mobile run exposed four old tests tapping progress before
  pending keyboard scrolling had completed. The shared test navigation helper
  now flushes that frame before locating/tapping; no runtime timing or production
  timeout was changed. All 57 existing uploader-screen tests and the final full
  suite pass.
- A separate read-only final review found no material issue in the requested
  Mobile/API behavior and persistence boundaries.
- Fresh fetch confirms candidate HEAD and `origin/main` both at the baseline
  above (0 ahead/0 behind before these uncommitted changes). Source whitespace
  checks pass, excluding the three unrelated generated Windows files.

Logs are retained in the local ignored artifact directory
`D:\PostDeeMobile\artifacts\platform-captions-20261023`: see
`backend-validation-summary.json`, `api-node22-*`,
`mobile-targeted-final.log`, `mobile-analyze-final.log` and
`mobile-full-tests-final.log`.

Android candidate verification also passed:

- `tool/postdee-staging.ps1 -Command build-apk --build-number=12042
  --build-name=0.1.0`: debug APK built successfully in **149.8 seconds**, exit 0.
- APK badging confirms package `com.postdee.postdee_mobile.staging`, label
  `PostDee Staging`, version code **12042**, version name **0.1.0-staging**,
  minSdk **24**, target/compile SDK **36**, and arm64-v8a/armeabi-v7a/x86_64.
- The compiled Dart kernel contains the Staging API, new caption contract and
  exact Sentry release `postdee-mobile@platform-captions+12042`. Packaged
  resources confirm Firebase project `project-798caf7e-85b8-45e3-af7`.
  Existing Firebase auth, mock-auth prohibition, RevenueCat Test Store overlay
  and Sentry configuration were preserved; no credentials are recorded here.
- APK size **292,726,049 bytes**; SHA-256
  `cf6299086be72b9deb129e829b2cb876151410f17e24a87943be8c71dfed8980`.
  Artifact: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` in the
  candidate worktree. Build and APK check metadata are in
  `mobile-build-result.json` and `mobile-apk-verification.json` beside the logs.
- A read-only package check confirms the emulator still has **12041**. Candidate
  **12042 has not been installed**. Device and actual remote-provider acceptance
  remain unverified; API-first release order still applies.

## Release order and remaining limits

The user authorized implementation, followed by an explicit `main/push/deploy`
request after local verification. At the start of this release run, the candidate
has not been merged to main, pushed, deployed or installed. The verified 34-file
source inventory and APK hash matched before staging the intended files;
unrelated dirty Windows files and launcher work in the main checkout remain
outside the release. Record the resulting commit, CI and exact Render deployment
after completion. Deploy the API before the new Mobile app because
older exact platform-settings parsers may reject optional caption overrides.
No database migration is required. Verify both legacy shared-caption clients
and new per-platform immutable submissions against that exact API revision.

Then verify the new Mobile build, retained drafts, mode toggles, manual edits,
AI preview cancel/apply, owner/clip switching, actual Gemini output and
destination-specific publishing. No real posts, purchases, remote AI generation
or customer quota mutations were performed by the automated tests documented
above. UI/contract tests do not establish live provider quality or publication.

## Release smoke finding: startup owner conflicts

The initial release commit `6b06c63fba5504437b7f3577f1d3c7cf1a5ac467`
passed GitHub API/Flutter CI run `39945496579` and iOS no-codesign build
`39945497035`. Render deployment `dep-dbdka3jrjlhs73djk010` became Live at
2026-10-23 18:30:45 GMT+7. Node 22.23.3, all 22 existing migrations/no pending,
the empty-backlog guard, scheduler, health/readiness and authentication barriers
passed. APK 12042 was then installed over 12041, preserving the package UID,
storage and app data, with no uninstall or data clearing.

Installed-app smoke found the Home subscription failed with HTTP 503 during
concurrent startup requests. Runtime logs at 11:32:22Z show `P2034` on
`managedUploadOwner.updateMany()` in `lockActiveOwner`, called from coordinator
admission. The pre-existing policy immediately retried Serializable transactions
only three times. No caption code or migration introduced that shared marker
row, but the release cannot be treated as ready while this normal flow fails.

The narrow follow-up shares one bounded `P2034` retry helper between coordinator
admission/deletion and `runActiveOwnerTransaction`. It keeps Serializable
isolation, row locks, deletion checks, error propagation and external-operation
lifetimes unchanged. Six attempts add positive randomized waits of 25–49,
50–99, 100–199, 200–399 and 200–399ms after failed transactions, at most
1,145ms of backoff; other errors never retry. Existing billing outer retries
can therefore make 18 failed transaction attempts, with at most 3,495ms of total
backoff including their existing outer waits; production billing code is unchanged.
No provider call, purchase, queue acknowledgement or publication is replayed by
this transaction-only helper.

Red/green regressions reproduce eight simultaneous admissions and combined
admission/store contention, preserving eight concurrently running callbacks.
Three attempts with delays still recovered only four of eight admissions;
six recover the tested burst. Tests retain bounded exhaustion/original errors,
zero failed add-on grants, other-owner progress and deletion/tombstone fences.
Follow-up validation passed on Node 22.23.3: **2,500 tests passed, 25 skipped**
(**150 suites passed, 4 skipped**, 70.94s), plus typecheck, build, Prisma schema
validation and Prisma helper checks. The focused owner/billing regressions pass
**33 tests**. No API contract, schema, environment variable or Mobile source
changed in this follow-up; APK 12042 remains the exact verified Mobile candidate.
Evidence: `owner-conflict-targeted.log`,
`owner-conflict-full-tests-final.log` and `owner-conflict-check-results.json`
in the ignored artifact directory. The replacement deploy and installed-app
dashboard verification will be recorded after they pass.
