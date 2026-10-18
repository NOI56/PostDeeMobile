# Unified publishing settings — 2026-10-18

## Scope and baseline

The user approved the four-platform settings plan with **เริ่มไล่แก้ไขเลย**.
This covers a consistent settings UI, TikTok lazy Direct options, optional Meta
AI-media declarations, end-to-end data plumbing and regression verification.
It does not include real publication, OAuth grants, purchases, data repair,
merge/push/deploy or installation on the user's logged-in emulator.

Canonical `grouped-account-ui` main and remote were freshly fetched and verified
at **c813eef72d1bc98e958b86ae2928e80a20939f8a**, 0 ahead/0 behind. The already
attached `tiktok-native-session-results/PostDeeMobile` worktree was reused with
branch **codex/platform-settings-unified** starting at that exact main. Three
pre-existing generated Windows plugin changes remain untouched/excluded; the
stale dirty `D:/PostDeeMobile` checkout and canonical untracked artifacts remain.

## User-visible changes

- One `PlatformSettingsScaffold` supplies platform logo, account identity,
  Cancel/Save actions, validation and a scrollable body bounded to available
  height (maximum 86% of the screen). Short Inbox forms shrink to their content.
  The footer stays above the keyboard; labels wrap with larger system text.
  An actual short-phone/keyboard test also exposed overflow in the underlying
  composer header. Its toolbar/progress now shrink within a scrollable header
  capped at 45% of available height; main content and sticky actions are retained.
- TikTok Inbox explains the handoff, real quota use and final TikTok action.
  It does not load Direct capabilities. Direct loads on entry, clears consent
  and binds the fresh response to the current owner/account/generation. Leaving
  Direct clears the options and invalidates any late completion; reentry reads
  fresh options. Existing creator restrictions and manual music/branded consent
  remain enforced. Grouped controls retain privacy, interactions, commercial and
  AI settings; no default privacy or invented permission is introduced.
- YouTube groups title/visibility and audience/content choices. Existing
  blank-only title suggestions, required kids/synthetic-media answers and manual
  certification are preserved, with a visible reason when Save is disabled.
- Instagram retains feed sharing; Facebook retains explicit publish/Page-draft
  selection. Both show the selected cover context and optional AI-media answers.
  Cover selection remains in the clip step. Facebook is Page Video, with no
  unsupported Reels claim. Page drafts still upload/use quota; local drafts do not.
- Review includes explicit Meta AI answers and all TikTok Direct interactions,
  commercial/AI/music/branded declarations, alongside existing destination,
  schedule, YouTube answers and cover context.

## Additive contract and compatibility

IG and FB platform settings accept optional **isAiGenerated: boolean**. Mobile
uses nullable `instagramIsAiGenerated` / `facebookIsAiGenerated`; null means
unanswered and is omitted from draft/API/recovery serialization. It is never
silently defaulted to false. Explicit true/false can be saved or cleared and
participate in equality/hash and immutable post-intent comparison.

The strict backend parser accepts the existing exact old shape or the exact
shape with a boolean declaration. Null, strings, numbers and unknown fields are
rejected. Persistence, BullMQ, accepted replay and owner-scoped recovery preserve
the original shape. A changed declaration conflicts with an already accepted
request ID. Provider mapping emits explicit true/false only when present.
Captions written by AI do not determine media disclosure.

No database/schema/migration, dependency, environment, plan, quota or destination
change is needed. **Deploy the API and every publishing worker before Mobile**:
the previously deployed parser rejects new fields, and old workers must not read
new declaration snapshots. Existing old clients remain accepted by the new API.
The owner barriers, media/upload receipts, original request IDs and no-resend
recovery protections remain intact.

## Verification

- Regression-first backend tests reproduced 13 failures for unsupported flags;
  the corrected targeted run passed 299 tests. Final full API suite passes
  **127 files / 2,207 tests**, using `--maxWorkers=2` (47.15 seconds).
  An initial default-parallel run timed out two unrelated catalog checks under
  concurrent work; the complete rerun passes without changing timeouts or skips.
- API typecheck/build, Prisma schema validation with a local dummy URL and
  Prisma seed/config helper compilation pass. No live database mutation was used.
  Logs: `C:/Users/stopp/AppData/Local/Temp/postdee-meta-ai-full-test-retry.log`
  and sibling `postdee-meta-ai-{typecheck-final,build,prisma,prisma-helper}.log`.
- Independent backend review finds no actionable issue in optional-field
  parsing, equality, replay/recovery, persistence, queue or provider mapping.
- Compiled `dist/app.js` smoke with injected dummy Prisma rows passes `/health`
  and owner-scoped `/posts` reads: missing/false/true disclosures survive DTO
  normalization, private/no-store is retained, with one injected read and zero
  external fetches/writes. Log:
  `C:/Users/stopp/AppData/Local/Temp/postdee-meta-ai-compiled-smoke.log`.
- Mobile settings/draft/review regression checks pass **81 tests**; separate
  recovery-client checks pass **8 tests**. New UI tests reproduced eager Inbox
  reads and missing declaration controls before production edits. Scaffold checks
  cover compact content, sticky actions, large text and keyboard constraints.
- Source-final `flutter analyze --no-pub` passes with no issues (16.0 seconds).
  Full Mobile suite passes **2,371 tests / 2 optional preview skips** in 3m29s,
  using `--no-pub --concurrency=4 --reporter=expanded`. The new opt-in five-sheet
  preview was executed separately and passes. Final logs:
  `C:/Users/stopp/AppData/Local/Temp/postdee-unified-settings-mobile-full-final.log`
  and `postdee-unified-settings-analyze-final.log` in the same directory.
- The initial whole Mobile run found 24 failures: 23 old global-first-scroll
  selectors targeted the new header instead of the composer, plus one existing
  Instagram copy assertion. Selectors now explicitly target main/header/modal
  according to the interaction; existing assertions and skips were preserved.
  The familiar Instagram wording is retained. The affected 183 checks pass
  (182 together plus the isolated wording case) before the final whole-suite run.
  No tests were removed or disabled to obtain a green result.
- Independent UI/data review verifies Cancel discards local edits, current
  owner/binding checks remain, stale Direct results cannot restore consent, and
  all YouTube/TikTok required declarations remain enforced. Whitespace-normalized
  review confirms underlying composer content and sticky actions are preserved
  around the new responsive header wrapper.
- No connected-account publication, store purchase, login grant, user draft
  modification, emulator installation or Production change was performed.

## Android build and visual checks

- Exact local Staging APK builds using the validated helper and base build
  number 8024 / versionCode **12024**, x86_64, min SDK 24/target SDK 36,
  package **com.postdee.postdee_mobile.staging**, version **0.1.0-staging**.
  Source-final build time 24.3 seconds. Artifact size **127,815,906 bytes**, SHA-256
  **FF67B6268B1CE92FA3ED2D6E623BF38890E21871E191D564378DDDED88A31A6C**.
  Signer SHA-256 matches delivered 12023:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  Build log: `C:/Users/stopp/AppData/Local/Temp/postdee-unified-settings-apk-12024-final.log`.
- Helper inputs verify Staging API, Firebase auth enabled, local mock auth
  disabled, RevenueCat enabled with the existing Test Store overlay, and both
  experimental AI Hook/Beat Sync disabled. AAPT verifies the package/version and
  packaged Firebase project matches the Staging Google-services file. Only
  matching booleans are printed; credential values are not exposed. These are
  build/configuration checks, not a new authenticated emulator session.
- Actual Flutter widget previews use bundled Anuphan fonts and platform assets,
  with fixture accounts and no real publishing. Inspected all five: compact
  TikTok Inbox, grouped Direct, YouTube, Instagram and Facebook Page Video.
  Short-phone tests use 360×640 with a 220-pixel keyboard and 1.5× text.
  Dropdowns expand to available width; the last real controls and fixed actions
  remain reachable. The preview-only run passes separately.
- Preview files are outside product source at
  `C:/Users/stopp/.codex/visualizations/2026/10/18/01a14cae-8651-76f3-814e-ae06034fa8e8/platform-settings-unified/`:
  `tiktok-inbox.png`, `tiktok-direct.png`, `youtube_shorts.png`,
  `instagram_reels.png`, `facebook_reels.png`. A few background toolbar glyphs
  use a test-font fallback; the real sheet text and bundled logos render correctly.
- APK12024 is **not installed on the user's emulator**. Current Staging API must
  be updated before enabling the new Mobile declaration fields. No connected
  Instagram/Facebook publish, provider label, physical-device or iOS build/device
  verification is claimed for this local implementation.

## Primary changed files

| Area | Files |
| --- | --- |
| Shared sheet, layout and controls | `apps/mobile/lib/features/uploader/platform_settings_scaffold.dart`, `uploader_screen.dart`, `tiktok_publishing_settings_sheet.dart` |
| Draft/request model and review | `apps/mobile/lib/features/uploader/platform_publish_settings.dart`, `publish_review_screen.dart` |
| API parser/immutable intent and provider mapping | `apps/api/src/modules/posts/platformSettings.ts`, `apps/api/src/workers/postPeerPublisher.ts` |
| Regression evidence | Associated API tests, Mobile model/draft/review tests, `platform_settings_scaffold_test.dart`, `unified_platform_settings_test.dart`, existing uploader interaction/scroll helpers |
| Documentation | `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `apps/mobile/README.md`, this record |

## Primary provider evidence

- [Instagram AI-media declaration, feed and cover](https://www.postpeer.dev/docs/platforms/instagram)
- [Facebook Page Video declaration, drafts and cover](https://www.postpeer.dev/docs/platforms/facebook)

These optional fields are provider-supported according to current docs. Mocked
mapper/route tests do not prove a real connected account's publication or label.
