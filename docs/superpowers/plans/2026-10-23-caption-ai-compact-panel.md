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
- Installed-app/native acceptance was deferred at the implementation handoff;
  it is completed in the authorized delivery receipt below. No API runtime or
  schema changes belong to this UI follow-up.

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

## Authorized delivery receipt — 2026-10-23

- The user requested `main/push/deploy`. Feature commit
  `2ef83998d0a1bce52e113a23de18ae4f9a0359bf` was fast-forwarded into canonical
  main and pushed to origin. Only the twelve intended files were committed;
  unrelated launcher, Staging-document and generated-Windows work is retained.
- During release, another task merged billing-security PR #18 as `5313f262`.
  Both this worktree and canonical main incorporated that descendant without
  overwriting its work. The existing local Staging-document patch was preserved
  in a named stash and applied cleanly over the new document. The complete
  `apps/mobile` Git tree is identical at the UI source and `5313f262`:
  `64c46731f68f50cdf16b6859a4d4717cd4bea928`. APK 12044 therefore still matches
  the latest Mobile source; no rebuild or test repeat for an unchanged tree is
  needed. No billing source or rollout configuration was modified by this task.
- [Source CI](https://github.com/NOI56/PostDeeMobile/actions/runs/39984007174)
  **passed** for `2ef8399`: Backend tests, typecheck, build, Prisma validation,
  dependency audit, Flutter analyzer and full Flutter tests. These API results
  validate the UI release's original API tree, not the later billing batch.
- [iOS build](https://github.com/NOI56/PostDeeMobile/actions/runs/39984009024)
  **passed**, finishing at 16:17:58 UTC. The no-codesign Xcode build, IPA payload
  and artifact upload all succeeded (job 11m17s). The unsigned IPA artifact is
  `12515860935`; this is not an App Store/TestFlight distribution.
- [Subsequent main CI](https://github.com/NOI56/PostDeeMobile/actions/runs/39984512876)
  also **passed** for `5313f262`, including its Backend and Flutter jobs. This
  verifies that integrated source; it does not accept the billing batch's live
  configuration or provider rollout prerequisites.
- Verified APK 12044 / hash above was installed through the existing
  `Invoke-PostDeeAndroidApkUpdate` helper with `install -r`. UID **10197** and
  internal storage volume remained unchanged. The prior UI had no selected clip
  and zero saved drafts. The authenticated Pro account remained available after
  cold launch, showing the same 235/250 remaining monthly post quota.
- Native UI acceptance passed: full four-name 2x2 grid; zero selection disables
  the one-credit action; selecting only YouTube enables it and leaves the other
  three targets unselected. The style action exposes the guidance field and all
  saved-profile controls. Entering a temporary guidance value, Cancel and reopen
  returns the original empty guidance. No style profile was saved. Final app is
  open at advanced caption step, zero AI targets, no clip and zero saved drafts.
- No live AI request, AI credit charge, video upload, post, purchase, OAuth
  connection, account deletion or existing-draft mutation was performed.
- Render **My Workspace**, service `srv-d9bb72ojs32c739osa5g`, remains Live on
  existing `dab94fb` / `dep-dbdl0mbncjis73aihrh0`. `/health` and `/ready` returned
  HTTP 200 with database/queue `ok`. Its API tree equals the UI release's
  `2ef8399` API tree (`717151f9c4505e850edf2e28490e01cfba9f853f`), so this Mobile
  delivery needs no API redeploy, migration or environment change.
- The billing batch added by another task has a different API tree and explicit
  rollout prerequisites in its own plan: live Staging SANDBOX subscription
  environment and RevenueCat TRANSFER/webhook configuration must be verified
  before that API is deployed. This compact-UI release does not claim to deploy
  or accept that batch. Production service/configuration remains untouched.
- Native evidence: `compact-release-preinstall-*`,
  `compact-release-installed-package.json`, `compact-release-advanced-empty-*`,
  `compact-release-youtube-selected-*`, `compact-release-style-sheet-*`,
  `compact-release-guidance-staged-ui.xml`,
  `compact-release-guidance-cancelled-ui.xml`, `compact-release-final-*` and
  `compact-release-result.json` in the existing artifact directory.
- The final receipt commit changes documentation only and uses the repository's
  established `[skip ci] [skip render]` suffixes. It does not replace the tested
  runtime or request another deployment. Remaining limits are real-handset,
  live AI/provider and signed-iOS/store acceptance outside this UI release.

## Outline-only selection follow-up — implementation verification

The user requested removing the green checkmarks over platform logos and using
only a green outline for selected AI targets. Baseline `34076ef` was fetched and
matches origin/main. The existing unrelated generated-Windows edits are retained.
Only `PlatformCaptionAiTargets` changes: hide the checkmark and use the normal
surface for selected tiles. The existing selected border, logos, accessible
selected state, independent toggling, generation, drafts and pricing stay intact.
No other checkboxes or platform confirmations are changed.

Updated existing selector regressions verify outline-only presentation in both
themes and selected semantics before/select/clear. Selector plus real-font
rendering checks pass (15); the final selector file passes all 13 tests after
updating the semantics matcher. Staging-configured selector/composer/submission/
rendering suites pass all 35 tests. Full analyzer passes with no issues. The
rendered light/dark cards were inspected, including 320px / 1.7x text; logos are
unobscured. This local presentation change is not cross-cutting, so the earlier
2,797-case full Mobile result remains historical and is not claimed as a new run.

Exact-source Staging APK **12045** builds and its package, release and embedded
selector source match the candidate. Existing Firebase auth, mock-auth boundary,
API URL and RevenueCat Test Store setup are retained. Evidence is under
`D:\PostDeeMobile\artifacts\caption-target-selection-20261023\border-only*`.
The clean preview is `border-only/compact-ai-panel-light-card.png`.

README, ROADMAP, API and ARCHITECTURE were checked; there is no product-plan,
quota, contract, schema or architecture change requiring further edits. No
backend rebuild/deploy or migration is needed. The implementation handoff did
not merge, push or install; the user subsequently requested `main/push/deploy`.
The authorized delivery results are recorded below after verification. There
were no live AI requests, charges, publications or account-data changes during
local implementation.

## Outline-only authorized delivery — 2026-10-23

- The user authorized `main/push/deploy`. Feature source
  `4a1c0f9c1d77d622460bc9eb0d3d82eaf81f52cf` was fast-forwarded into canonical
  main and pushed to origin. The commit contains only the selector, its existing
  regression test and this plan. Unrelated launcher, Staging-document and
  generated-Windows edits are preserved and excluded.
- [Current source CI](https://github.com/NOI56/PostDeeMobile/actions/runs/39987082397)
  passed for exact head `4a1c0f9`: full Flutter tests **2,797 passed / 6 skipped**,
  Flutter analysis and Staging configuration guards; Backend tests **2,566
  passed / 25 skipped**, typecheck, build, Prisma validation and dependency audit.
  The Backend result covers current main's integrated code, including the later
  billing batch. It does not establish its live rollout prerequisites or deploy
  that API. Local presentation checks above remain separately scoped evidence.
- [iOS CI](https://github.com/NOI56/PostDeeMobile/actions/runs/39987082402) also
  passed for `4a1c0f9`, including the no-codesign Xcode build, IPA payload and
  artifact upload. This is an unsigned CI artifact, not an App Store or
  TestFlight release.
- Exact-source Staging APK **12045** was updated using the existing
  `Invoke-PostDeeAndroidApkUpdate` helper with `install -r`. Package
  `com.postdee.postdee_mobile.staging`, UID **10197** and internal volume are
  retained. APK SHA-256 is
  `56928fffd7236d7685ba52f3d86c0e22e1da876058093a41d32344ba5b023b4d`
  (292,736,825 bytes), release `postdee-mobile@caption-target-border+12045`.
  Embedded selector source matches the committed source. Firebase auth remains
  enabled, local mock auth disabled and RevenueCat uses the existing Test Store.
- After launch, the existing authenticated Pro account still showed 235/250
  remaining monthly posts. Native checks confirm zero targets disable the AI
  action and TikTok/YouTube can be selected. The final read-only screenshot shows
  TikTok selected with a green outline, no checkmark and unobscured logos.
- Complete four-target native interaction was not accepted: the emulator screen
  changed independently during inspection, so all automated input was stopped.
  Current advanced-caption state is preserved with one TikTok target selected.
  Full four-target behavior remains covered by the selector/widget tests;
  partial native smoke must not be reported as complete four-target acceptance.
- No live AI request, credit charge, upload, post, purchase, draft save or writing
  profile save was performed. No uninstall, app-data clearing or volume move was
  used. Evidence includes `border-release-native-acceptance.json`,
  `border-release-native-final.png` and `border-release-installed-package.json`
  in the existing artifact directory.
- Render My Workspace's Staging API remains Live at `dab94fb` /
  `dep-dbdl0mbncjis73aihrh0`; `/health` and `/ready` return HTTP 200 with database
  and queue `ok`. This UI-only change needs no backend deployment, schema or
  environment change. The later billing-security API batch retains its separate
  rollout prerequisites; it was not deployed or accepted by this task.
- The final receipt updates only README, ROADMAP, ARCHITECTURE and this plan,
  using the established `[skip ci] [skip render]` suffixes. The tested Mobile
  runtime is unchanged. Remaining limits are full native four-target interaction,
  real handsets, live AI/provider behavior and signed iOS/store delivery.
