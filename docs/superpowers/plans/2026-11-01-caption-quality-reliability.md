# Caption quality and recovery (2026-11-01, local candidate)

## Baseline and scope

- Freshly fetched `origin/main`: `353cb0115ef3aa886d10618c7efd87e046a5f3f4`.
- Work branch: `codex/caption-quality-reliability` in a separate checkout. The
  original `claude/store-link-polish` checkout and its uncommitted work are retained.
- Fix grounded caption writing, bounded generation and credit recovery,
  platform-output validation, large silent clips, and shared-caption selection/undo.
- Preserve per-channel costs and `expectedCredits`, purchased credits, owner
  isolation, draft recovery, writing styles, publishing targets, scheduling,
  Facebook Page Reels settings and all retired-feature boundaries.
- No schema migration, entitlement change, dependency upgrade or new environment
  variable. API first, then Mobile; no merge, push or deployment is included.

## Evidence behind the change

The initial direct-provider probes used synthetic Thai WAV audio and the local
configured Gemini `gemini-2.5-flash-lite`, without consuming an account's caption
credits. They did not exercise the hosted API, upload pipeline or native plugins.

- A factual notebook description retained 60 pages, 49 baht and blue/pink covers
  across four channels (about 5 seconds for the provider request).
- A negative bag review changed a stuck zipper into a positive claim even though
  an independent transcription retained the original negative wording.
- Valid silent audio with no frames invented a menu/screen scene.
- Local injected-provider probes also reproduced held media slots/credits after
  client disconnect, and charged output that publishing validation rejected.

## Implementation contract

The provider reads actual media into evidence before writing from that evidence,
then audits/repairs the draft against the same evidence with a text-only request.
All three calls share an 85-second budget and the caller's cancellation signal;
only the first sends media. User credit costs do not increase. A second live
round caught an invented product/promotion and an English-to-Thai language drift
after evidence separation, which motivated the final audit and explicit language
lock. This model-based check reduces errors; it cannot prove all claims correct.
Pure audio cannot supply visual observations. A lack of usable evidence must
return the existing uncharged fallback with optional `fallbackReason`, rather
than a fabricated scene. Seller guidance and style examples remain untrusted
writing direction, never a source of product facts. Preserving negative meaning
is explicitly required; model correctness still needs representative live checks.

The route owns a 90-second request lifetime, propagates cancellation to downloads
and AI, refunds the request's reservations on timeout/failure, and releases its
media slot. Generated captions including their appended hashtags must pass the
same constraints as publishing before they count as a successful generation.
The existing account-operation fence releases a timeout ticket only for the
exact caption route and a confirmed zero-charge refund; uncertain outcomes
retain the ticket. Disconnect handling also waits for the reservation refund.

Mobile prepares a bounded visual proxy when a large source has no extractable
audio, using the retained media helper without restoring retired editing UI.
Shared captions offer up to three distinct choices when available and preview
before replacing existing text. Undo restores the prior caption. An uncharged
fallback leaves manual text intact and explains how to try again in Thai/English.

## Changed areas

- `apps/api/src/modules/captions/realClipCaptionProvider.ts`: evidence, drafting,
  audit/repair, language and emoji enforcement; associated provider/style/platform
  tests and new `realClipCaptionEvidence.test.ts`.
- `apps/api/src/modules/captions/captionRoutes.ts` and `captionService.ts`:
  request lifetime, refunds, safe templates and platform constraints; new
  `captionGenerationSafety.test.ts` and updated route/media/quota tests.
- `apps/api/src/app.ts`, `modules/storage/mediaDownload.ts` and
  `clipMediaFetch.test.ts`: cancellation through downloads and stream reads.
- `apps/api/src/modules/account/ownerOperationRouter.ts` and its tests: narrow
  refunded-timeout completion; `modules/billing/monthlyAddonQuotaRoutes.test.ts`
  retains paid-success coverage and adds clip-failure purchased-credit refunds.
- Mobile `core/network/postdee_api_client.dart`, uploader screen, caption
  localizations and `platform_caption_fields.dart`: preview/choices/undo,
  fallback notice and bounded proxy, with affected widget/state/English tests
  and new `caption_options_preview_test.dart`.
- `API.md`, `ARCHITECTURE.md`, `README.md`, `ROADMAP.md` and this record describe
  compatibility, unchanged credit rules and actual acceptance limits.
- Generated Windows plugin files, dependency locks, environment files and
  database schema/migrations have no delivered changes.

## Verification record

- Tests-first: nine new evidence/cancellation regressions failed the original
  provider; new route and Mobile regressions also failed before implementation.
- Node `22.23.3`: final full API run with `--maxWorkers=3` passed **3,266 tests**;
  **60 tests in 10 unrelated opt-in suites remain skipped**. The seven caption
  batch PostgreSQL tests were enabled and passed, using a disposable server on
  `127.0.0.1:55449`, database `postdee_caption_test_quality`, schema
  `caption_batch_quality`. All 28 existing migrations applied on that fixture;
  the everyday development and hosted databases were not used.
  The fixture server was stopped after verification. Automatic approval review
  rejected recursive deletion with `blocked by policy`; its stopped data remains
  at `D:/PostDeeMobile/.tools/task-artifacts/caption-quality-pg-20261101`.
- API `npm.cmd run typecheck`, `npm.cmd run build`, Prisma validation, and the
  independent seed/config TypeScript check passed. No new migration was created.
- Mobile final full suite (`--no-pub --concurrency=3`) passed **4,571 tests**, with
  **7 skipped**, in 7 minutes 31 seconds. Targeted Mobile tests and full analysis
  also passed. Real-font shared-preview QA passed at
  360x640 with 1.5x text in Thai/light and English/dark; PNGs are in
  `.tmp/caption-quality/ui-light.png` and `ui-dark.png` (local test artifacts).
- The final three-stage provider was exercised through the local HTTP route
  with real Gemini and synthetic M4A, using memory auth/stores and an injected
  media downloader. Thai notebook facts were preserved across four channels
  (**8.615 s**); the negative bag review preserved zipper/strap problems and
  the recommendation against buying (**7.622 s**); silent audio returned
  `INSUFFICIENT_EVIDENCE` with **zero charged credits** (**2.866 s**).
- The English final probe hit Gemini `429`: the local test project's free tier
  allows 20 generation calls/day. The route returned an uncharged provider
  fallback. A diagnostic confirmed the daily limit, rather than an inferred
  network failure. The owner chose to retain the same key and wait for reset
  (approximately 2026-11-02 15:00 Asia/Bangkok). English's final live check and
  a silent visual-video live case remain pending; mock regressions do not replace
  them. No automatic retry or scheduled job was created.

## Native candidate and remaining acceptance

The guarded Staging helper built an Android x64 debug APK, version `12090`,
package `com.postdee.postdee_mobile.staging`, using the repository Flutter
3.44.1 SDK, Staging API URL and Firebase auth, with local mock auth disabled
and the existing RevenueCat Test Store overlay. Firebase Staging project:
`project-798caf7e-85b8-45e3-af7`.

- APK SHA-256:
  `d9a60b83fbfa0db365b4e0a4354c64a8cdfe0e727a93023e80f794e4c1dae7e5`.
- Updated `emulator-5554` using `Invoke-PostDeeAndroidApkUpdate`; UID **10197**,
  internal storage and version **12090** stayed unchanged. Installed APK hash
  matched the candidate. No uninstall, clear-data or storage move occurred.
- Native startup succeeded with the STAGING strip, the existing signed-in Basic
  account and one saved draft still visible; create-post navigation opened.
  AndroidRuntime showed no crash. Startup screenshots are in
  `.tmp/caption-quality/native-startup.png` and `native-draft.png`.
- The account is Basic and the hosted API still runs its previous implementation.
  No entitlement was changed and no real-account AI/publishing action was run.
  The new selection sheet was checked with widget fixtures; native generation,
  FFmpeg proxy preparation on Android, R2 cleanup and hosted end-to-end acceptance
  remain separate checks. API and then Mobile rollout still require authorization.
- This is a local candidate. No merge, push or API deployment has occurred.

## Resume live verification after the same key resets

Do not retry the exhausted key before reset or substitute another project. The
owner explicitly chose to wait. The local synthetic M4A fixtures and an opt-in
probe remain in `.tmp/caption-quality/`; its syntax check passed. From `apps/api`:

```powershell
& D:/PostDeeMobile/.tools/task-artifacts/node-v22.23.3/node.exe --import tsx ../../.tmp/caption-quality/run-live-probe.mjs --live --cases=english-facts
```

Check that the final response is real-provider output, all four captions are in
English, `detectedSpokenLanguage` and caption context agree, the 60-page/49-baht
facts remain correct and emoji:none is honored. A provider fallback does not pass
this quality check even though the refund path works. Then test a controlled
silent video with actual visual evidence and the Android proxy path separately.
Keep the result and timing in this record before claiming those checks passed.
