# Compact caption AI panel — 2026-10-23

## Request and baseline

The user approved a compact AI panel for advanced caption mode. The existing
selector takes too much vertical space when combined with style, guidance,
selection actions and repeated credit information. Consolidate those controls
while preserving the already released selective generation behavior.

The implementation starts on `codex/platform-captions` in
`C:\Users\stopp\.codex\worktrees\platform-consent-preserve\PostDeeMobile`,
at `385c949f83551d1e99449351246df2691934a6b0`. Local tracking `origin/main`
and HEAD have the same merge base and 0 ahead/0 behind; release freshness is
verified separately by the root task. Preserve the three unrelated dirty
generated Windows plugin files. The earlier selector's source, CI and installed
APK 12043 evidence remain in the
[selection record](2026-10-23-caption-target-selection.md); they do not verify
this new UI candidate.

## Approved presentation

- Compact header: `ให้ AI ช่วยเขียน`, with a `สไตล์` action.
- Helper: `เลือกช่องทางที่ต้องการ`.
- Four equal channel choices in a uniform two-by-two grid: TikTok, YouTube
  Shorts, Instagram Reels and Facebook Page Video. The internal compatibility
  value `FACEBOOK_REELS` still means Page Video, not supported Facebook Reels.
- Remove the visible select-all/clear actions and separate selected-count/cost
  row from this advanced panel. Each channel remains individually toggleable.
- Keep one primary action, `สร้างแคปชั่น · 1 เครดิต`, disabled with zero
  targets. Opening the panel or changing a selection must not call AI.
- Move clip guidance and writing-style controls behind the style action. Keep
  the existing full profile, saved owner-scoped preferences and supported rich
  controls; do not replace the saved profile with a simplified second model.
- Preserve clear busy, unavailable, error and fallback feedback where those
  states apply. Controls must remain usable on narrow screens and enlarged text.

## Behavior that remains unchanged

Advanced mode still hides the main caption and retains all four manual editors.
AI targets start empty and are independent of publishing destinations. Local
drafts remember targets, mode, captions and guidance through mode toggles and
reopening. Editing presentation must not clear those values or let an old
profile/guidance sheet write into a different account or clip. In advanced mode,
the existing style sheet stages guidance locally: successful scoped style save
also commits guidance to the post; Cancel discards staged guidance. Clearing
learned examples does not commit guidance. Basic mode keeps its existing editor.

Generation sends only chosen targets to the existing real-clip endpoint.
Preview, application and undo remain scoped to requested targets and preserve
unselected text. Existing owner/clip/target/mode/selected-edit stale-result guards,
review gates, effective caption delivery, automatic YouTube titles and TikTok
consent boundaries remain in place. The shared/basic caption flow retains its
existing behavior unless the final code explicitly shares a presentation helper.

The price is still **one monthly/add-on AI credit per request/set of 1–4
channels**. Fewer chosen channels do not reduce the charge. Keep existing
reservation, fallback/refund, paid-plan, media and cleanup behavior.

## Contracts and scope

This is a Flutter presentation change. `API.md` was checked: the existing
`platforms` subset request, `platformCaptions` response, local draft metadata
and post settings contract require no edits. No API runtime, quota, package,
schema, migration, dependency, environment, credential or integration change is
introduced. Reusable channel defaults still do not capture per-post AI targets.

Inspect and change only the uploader AI presentation, selector widgets, related
style/guidance sheet wiring and their regression tests. Product documents synced
for this follow-up are `README.md`, `ARCHITECTURE.md`, `ROADMAP.md`, the link in
the earlier selection record and this plan. Keep the earlier release history.

## Changed files

- `apps/mobile/lib/features/uploader/uploader_screen.dart`: compact advanced
  panel and the existing owner-scoped style sheet with staged post guidance.
- `apps/mobile/lib/features/uploader/platform_caption_fields.dart`: two-column
  selector, full names and accessible selected state. Four manual editors and
  selected-only preview remain intact.
- `apps/mobile/lib/features/shared/postdee_card.dart`: optional natural-height,
  wrapping button label. Existing callers retain their fixed-height defaults.
- `apps/mobile/test/platform_caption_widgets_test.dart`,
  `uploader_platform_captions_test.dart`, `uploader_caption_style_test.dart` and
  new `uploader_compact_ai_panel_visual_test.dart`: selection, guidance,
  asynchronous owner/save guards and rendered responsive regressions.
- The five documentation files described above. The unrelated dirty generated
  Windows plugin files are preserved and excluded from this work.

## Verification

- Test-first compact-panel regression failed against the old presentation,
  then passed. Real-font checks additionally caught inherited Chip one-line
  defaults and a three-pixel selected-border measurement difference. The final
  selector resets inherited wrapping limits, reserves border space and uses
  natural row heights. Regression checks require the final word and all rendered
  text boxes to remain within the label; no font shrinking or line cap is used.
- Final selector + real-font rendering tests: **15 passed**. Actual Anuphan
  rendering inspected at light 430px and dark 320px / 1.7x text. Image capture
  also includes a clean card rendered from the actual widget at the same size.
- Caption style suite: **26 passed**, including failed save, owner change while
  a save is pending, Cancel and clear-examples guidance isolation.
- Staging-configured target suites: **35 passed**, covering zero-target
  disabling, subset requests, preview/application/undo, draft restore, effective
  submissions, YouTube title-only and TikTok consent preservation.
- Full Mobile suite on the final runtime: **2,797 passed, 6 skipped**
  (`flutter test --concurrency=4 --reporter expanded`, 3m57s). No failures.
- Full `flutter analyze`: **passed**, no issues. The optional card-capture test
  helper was also analyzed separately after its final test-only update.
- Exact-source debug Staging APK **12044** built successfully. Package is
  `com.postdee.postdee_mobile.staging`; packaged Firebase project matches the
  existing debug configuration, Firebase auth is enabled and local mock auth is
  disabled. The staging helper validated the existing RevenueCat Test Store
  overlay without exposing its SDK key. API remains
  `https://postdee-api-staging.onrender.com`; Sentry uses staging release
  `postdee-mobile@compact-ai-panel+12044`.
- APK SHA-256:
  `66f9591ad86d1d18ceafc6c9cde9de03cc8c2457f750dfd0d3053e4f4d7903c8`
  (292,736,357 bytes). Compiled kernel checks confirm the release/API, selector,
  draft selection, staged guidance and wrapping action are present.
- Evidence is under
  `D:\PostDeeMobile\artifacts\caption-target-selection-20261023\compact-*`.
  Use `compact-mobile-tests-final.log`, `compact-mobile-analyze-final.log`,
  `compact-mobile-build-final.log`, `compact-mobile-build-result.json` and
  `compact-staging-tests-final.log`. Earlier provisional runs were stopped to
  fix the visual truncation; they are not final suite/build evidence. Old
  `*-detail.png` files are stale. Current clean images are
  `compact-ai-panel-light-card.png` and `compact-ai-panel-dark-card.png`.
- Final source/docs `git diff --check`: passed; no deleted files or unrelated
  runtime/flag/contract changes. Remote main re-fetched and remains at baseline
  `385c949`, 0 ahead/0 behind before candidate changes.
- Installed-app/native acceptance: not performed for this follow-up. No API
  runtime or schema changes, so backend test/build and migration revalidation
  are not required for this presentation-only candidate.

Earlier selector test counts, cloud deployment and APK 12043 smoke are historical
evidence, not results of this compact-panel change. No live AI request, credit
spend, purchase or publication is required for local presentation checks.

## Delivery boundary

The implementation handoff completed without merging, pushing or installing.
The user subsequently requested `main/push/deploy`, authorizing this follow-up's
integration and delivery. Release checks and the final delivery receipt are
recorded below when complete. Preserve existing local work, app account/data
and any unsaved composer before updating the installed package.
The API already supports the behavior, so no backend deployment or migration
is required for the compact UI. Actual provider quality, real handset behavior
and social publication remain outside this presentation verification.
