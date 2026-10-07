# Profile template categories — 2026-10-07

## Current composition revision — 2026-10-07

**Status: integrated source pushed, exact-source CI passed, Staging API Live;
matching Android update in progress.** The receipt immediately below verifies
this revision. The older CI/Render/emulator receipt later in this document
belongs to `fc087c4119cd46503c569879e61cddf99e402fb2` only.

### Current integrated delivery receipt

- Initial composition snapshot: `a659bf571800ec278944aff51406b84fab397072`,
  containing only the forty-two reviewed composition files. The three unrelated
  CRLF-only files and untracked artifacts were excluded.
- Release preparation found Live Staging `550f73a` ahead of the earlier source,
  and `main` subsequently advanced to `ebc9c47a2eb5d1a48f4124927a8dce0aec1ac572`.
  A clean checkout from that latest verified `main` ports the live four-step
  composer, its receipt (`1859978`) and the composition snapshot. The final
  source is `9c7fa74cc6910063fc88a66568860ac64609f02f` on
  `codex/profile-compositions-integrated-staging`, checkout
  `D:/PostDeeMobile/.worktrees/profile-compositions-integrated-staging`.
- Blob/delta audit preserves Account, composer and composition code/tests;
  merged documents retain all three contracts. No source/config/schema/provider
  or entitlement change is introduced by the integration. Latest verified
  `main` is an ancestor; no merge to `main` or Production release is performed.
- [Exact-source CI 37623591224](https://github.com/NOI56/PostDeeMobile/actions/runs/37623591224)
  passes Backend API (104 files / 1,555 tests, generator/catalog, build, Prisma,
  dependency audit) and Flutter Mobile (analyze, 1,556 tests).
- [Render deployment dep-db342ek9v7es73astung](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db342ek9v7es73astung)
  is **Deploy succeeded | Live**. Source and running instance `bsf55` report the
  exact full `9c7fa74` SHA. Dispatch was 19:55:22 and Live log 19:57:18
  Asia/Bangkok, duration 1m56s. Staging database has fourteen migrations with
  none pending; listener is 10000, social publisher remains disabled and the
  existing memory scheduler starts. Service plan/secrets/Auto-Deploy stay as-is.
- Read-only compiled-module fixtures succeed: 100 retained IDs (sorted-ID
  SHA256 `937c28fa35a33d431739e92176c31fe365d485134b3986d33fded2f9b5e9ea2f`),
  five categories of twenty distinct compositions, eight PNG signatures, seven
  legacy themes, appearance-version/unknown-ID validation, all 100 renderers,
  omitted-appearance retention and synthetic public-route headers. They use
  memory fixtures only; no live owner profile/database/provider is touched.
- Release evidence is in the original checkout's
  `artifacts/profile-composition-release`: `ci-final.log`, `render-live.png`,
  `runtime-smoke.json/png` and privacy-safe device preparation. Private backups
  and keys remain outside Git. Public Staging/browser/owned-image checks remain
  unverified under the earlier saved browser restriction.
- The pre-integration local APK hash `a12249…eaab` below is historical and is
  **not** installed for this release. Windows Flutter-tool snapshot and source
  startup hang; a local analyze crash is not reported as a pass. An opt-in
  manual CI APK build is being prepared using the tracked example config;
  local comparison verifies all nine values match the private build config.
  Downloaded runner-debug APKs require local re-signing before in-place update.
  Installed APK and the existing local debug keystore certificate both have
  SHA256 `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  No private JSON/signing key is uploaded or new credentials created.

After seeing the first hundred choices, the user said the templates within a
category looked too similar. Clarification confirmed that all choices must
remain short link pages, not multi-section store websites. On 2026-10-07 the
user explicitly accepted **all fifteen A1–E3 sample directions** and requested
new structures across the full hundred choices.

### Initial local baseline and preservation (historical)

- Canonical checkout remains `.worktrees/recover-main-systems`, branch
  `codex/pinterest-mobile-ui`; local-revision starting HEAD is
  `630e20a097b3929f7749b6684d927b62d6ba5532`.
- Observed `origin/main`/merge base remains
  `bcd7153f196cd381a786b333b9b61a67dbe95ca3`, zero behind / sixteen ahead at
  revision start. Existing unrelated artifacts and account/draft data remain.
- Retain every one of the hundred previously published template IDs, appearance
  version 1 and all seven legacy theme IDs. The `templateId` fallback,
  mismatch validation and explicit publication contracts do not change.
- Retain existing store name, description, categories, links/order/visibility,
  safe contacts, logo/cover/background ownership, featured link, custom
  colors/fonts/radius and per-link overrides. Reuse these fields in every short
  composition; do not add product inventory, prices, multi-section copy,
  analytics, free-position dragging or a paid design provider.
- The hundred platform-brand assets and their normalized 40px geometry are
  unchanged. The new decorative artwork is a separate asset set.
- No database schema/migration, credentials, package rights, external provider,
  feature flags or dependencies are added.

### Accepted fifteen bases

These are layout directions adapted into short link pages. They are not static
screenshots replacing the owner's content or externally hosted runtime images.

| Sample | Category / composition | Accepted direction | Retained template ID |
| --- | --- | --- | --- |
| A1 | Minimal / `editorial` | Open white typography, numbered line-separated links | `minimal-white-editorial` |
| A2 | Minimal / `bicolor` | Lavender-gray upper area, white link area and four outlined tiles | `minimal-mono-pair` |
| A3 | Minimal / `portrait` | Portrait-led off-white page with dark-green lead link | `minimal-clean-cover` |
| B1 | Cute / `scallop` | Pink scalloped stationery with fine outlined/hairline links | `cute-cherry-cream` |
| B2 | Cute / `collage` | Scrapbook layers, tilted photo/card and tape details | `cute-sticker-layers` |
| B3 | Cute / `window` | Lilac browser-window panel over mint gingham | `cute-candy-box` |
| C1 | Nature / `botanical` | Cream page with a leafy frame and fine link rows | `nature-olive-garden` |
| C2 | Nature / `glass` | Forest photograph, direct white identity copy and translucent links | `nature-greenhouse` |
| C3 | Nature / `torn` | Meadow photograph and torn-paper content | `nature-paper-fibers` |
| D1 | Luxury / `seal` | Black/gold crest and fine outlined links | `luxury-gold-seal` |
| D2 | Luxury / `tag` | Ivory hanging tag with black filled buttons | `luxury-silver-signature` |
| D3 | Luxury / `gallery` | Open white/black gallery and two-column link tiles | `luxury-black-gallery` |
| E1 | Creative / `poster` | Yellow/black poster type and strong shadowed links | `creative-yellow-pop` |
| E2 | Creative / `window-grid` | Purple window frame/titlebar, cream header and lime modular link area | `creative-play-blocks` |
| E3 | Creative / `ticket` | Coral retro ticket over blue, cream rounded buttons and dark copy | `creative-retro-cover` |

The first three items of each category resolve these bases in A/B/C/D/E order.
The remaining seventeen use different compositions with category-specific
palettes and details. An ID such as `luxury-black-gallery` remains stable even
though its accepted new appearance is the white **แกลเลอรีขาวดำ** direction.

Review corrections retain outlined/hairline links for bicolor and scallop.
Poster/collage defaults use the category wash with its readable name color so
approved pastel link cycles can display instead of falling back to one dark
fill; E1's lead fill is `#ff6a48` with `#242522` text on its yellow page.
C2 uses `#182a16` background/gradient/surface, white page copy and footer,
`#edf3e9` links with `#203522` text, Anuphan and background motion off.
Its white heading sits directly on the forest with a small light monogram;
there is no separate white header/footer card. Custom owner colors/media
remain authoritative, and actual image contrast remains part of visual QA.
A2/A3 and B2 default to square buttons. B2 retains a fine paper border and
hard pastel shadow; owner-selected round/pill corners remain supported.
B3 retains a mint outside background, white
window surface, lilac titlebar wash and pink lead button; the following default
link cycle uses cream/lilac/mint. Owner backgrounds take precedence over the
built-in gingham treatment.
E2 retains a cream outside/header, purple frame/titlebar and lime body with
dark copy and lilac lead tile. E3 uses blue outside, a coral ticket sheet,
cream rounded buttons and dark copy. These are default changes to the two
creative bases only; owner colors and per-link overrides remain authoritative.

Pinterest references were visually inspected during research; pin titles alone
are not evidence of layout. Reference IDs supplied by that inspection:

| Category | Pinterest references |
| --- | --- |
| Minimal | [Two-tone stationery reference](https://www.pinterest.com/pin/442056519670825729/) |
| Cute / pastel | [Cute page reference](https://www.pinterest.com/pin/505036545733369337/) |
| Nature / warm | [Nature reference 1](https://www.pinterest.com/pin/4594797619946422656/), [Nature reference 2](https://www.pinterest.com/pin/4608519518301550976/), [Nature reference 3](https://www.pinterest.com/pin/677299231479887912/) |
| Luxury / premium | [Black embossed stationery](https://www.pinterest.com/pin/167196204905531483/), [Luxury reference](https://www.pinterest.com/pin/351984527143288543/) |
| Creative / colorful | [Graphic reference](https://www.pinterest.com/pin/414471971968806036/) |

Accepted local boards (three labeled samples in each file) are under
`C:/Users/stopp/.codex/generated_images/01a1153f-2c52-7c43-9fb7-ba3a4366835d/`:

| Samples | Accepted board file |
| --- | --- |
| A1–A3 / Minimal | `exec-3bcb72f0-0468-47f7-8032-c76cfa7c59ae.png` |
| B1–B3 / Cute, final board | `exec-4acdec89-4ec3-4e25-b19c-2860435b8f20.png` |
| C1–C3 / Nature | `exec-0c006afd-7676-426a-9a9d-161ae8beb041.png` |
| D1–D3 / Luxury | `exec-7652c4aa-2513-42d6-97fa-8b8a0ed27029.png` |
| E1–E3 / Creative | `exec-dd60877d-5f4d-45f0-9fa4-2792ca99fc25.png` |

Current native/public comparison screenshots are recorded under
`artifacts/profile-composition-qa`. The six earlier generated category concepts
below document the initial release, not these fifteen bases.

### Twenty composition families

`layout.composition` is required in the authored catalog and generated TS/Dart
layout definitions. It is trusted internal metadata, never CSS or a new field
accepted from a publish request. Each category contains all twenty allowlisted
compositions exactly once. The earlier five-header/four-button model remains
historical release design; it is no longer the uniqueness criterion.

| Composition | Distinct short-page structure |
| --- | --- |
| `editorial` | Open typography and numbered ruled link rows |
| `bicolor` | Two-tone page areas and outlined two-column link tiles |
| `portrait` | Prominent portrait/cover and a lead link followed by smaller rows |
| `scallop` | Scalloped stationery sheet with delicate link separators |
| `collage` | Layered/tilted paper or portrait pieces and mixed link rhythm |
| `window` | Browser-window frame, title rail and list links |
| `botanical` | Leaf-framed open page with centered identity and fine rows |
| `glass` | Photograph-backed translucent floating panel |
| `torn` | Landscape/cover leading into a torn-paper sheet |
| `seal` | Crest/badge identity over a framed link list |
| `tag` | Hanging clipped-corner tag and solid link buttons |
| `gallery` | Open image-led gallery and two-column link tiles |
| `poster` | Large poster identity and bold shadowed link rows |
| `window-grid` | Graphic window border and a modular link grid |
| `ticket` | Ticket cutouts/perforations around compact link content |
| `rail` | Side rail/timeline markers alongside link rows |
| `ribbon` | Ribbon/band header and staggered link bands |
| `notebook` | Ruled notebook sheet, margin rail and list rows |
| `arch` | Arched portrait/cover opening and rounded sheet |
| `staircase` | Alternating stepped offsets through the link list |

The existing header/link/button/decoration/avatar fields remain as secondary
metadata. Metadata and default button/text colors are aligned: outline families
use readable surface text, soft families use readable wash colors, and filled
families use contrast-checked text. User-authored colors and fonts remain
authoritative. Persisted appearances from the previous hundred-template release
must be included in QA, especially when an old filled button becomes a
transparent row or the gallery default changes from dark to white.

### Shared rendering and built-in artwork

- `shared/profile-templates.json` generates both clients. Public HTML and
  Flutter render the same twenty composition families with real escaped/native
  copy, links, platform marks and owner media. Actual geometry needs visual QA;
  a matching enum alone does not establish visual parity.
- Chooser thumbnails reuse the actual native composition renderer with
  deterministic sample links, disabled tickers and scaled page geometry.
  Shared decoded-image caching avoids separate downloads or parallel animation.
  Selected previews reuse the owner's draft; category/filter/cancel do not
  mutate it. Applying a preset remains distinct from saving/publishing.
- Eight built-in ImageGen raster decorations are bundled under
  `apps/api/assets/profile-decorations` and
  `apps/mobile/assets/images/profile_decorations`. They supply photograph,
  paper/tape, leaf, crest and cord details; they do not flatten real copy,
  platform artwork or links into a screenshot.
  Filenames: `botanical-frame.png`, `forest.png`, `meadow.png`, `paper.png`,
  `letter-frame.png`, `collage-tape.png`, `gold-seal.png`, `tag-cord.png`.
- A new public read-only `GET /profile-decorations/:file` uses a fixed eight-PNG
  filename allowlist. Successful responses are `image/png`,
  `Cache-Control: public, max-age=86400` and
  `X-Content-Type-Options: nosniff`; unknown filenames return 404. No arbitrary
  path/URL fetching, uploaded-image ownership access, Pinterest runtime call,
  external image source or script/CSP expansion is permitted.
- Ship the API renderer and bundled decorative assets before the matching
  Mobile build. No database migration or new credential/provider is required.
  This revision has not been represented as pushed, CI-approved or deployed.

### Current-revision verification and remaining delivery

Tests were added before catalog changes. Initial new-composition tests failed
on missing/unknown/repeated compositions, then passed after implementation.

| Check | Current-revision status |
| --- | --- |
| Generator validation | 22 tests passed; missing/unknown/duplicate compositions rejected, twenty per category and hundred published IDs retained; hairline/pastel-cycle/C2/B3/A2/A3/B2/E2/E3 defaults covered |
| Generated TS/Dart parity | `node scripts/generate-profile-templates.mjs --check` passed |
| API catalog contract | 11 tests passed, including appearance/custom-style round trips |
| Flutter catalog contract | 5 tests passed, including legacy themes and appearance round trips |
| Default palette contrast | Generator verifies at least 4.5:1 on intended default text backgrounds |
| Full API suite | 104 files / 1,555 tests passed on final source; `npm.cmd run test -- --maxWorkers=2 --testTimeout=20000` |
| API renderer/routes and build | 179 focused tests passed; final `npm.cmd run build` passed |
| API schema/helpers | `prisma:validate` passed with local validation URL; Prisma seed/config NodeNext type-check passed; no schema change or migration |
| Full Flutter suite/analyze | 1,499 tests passed; `flutter analyze` reports no issues |
| Exact Staging APK | Main entry/debug build with `--dart-define-from-file=D:/PostDeeMobile/apps/mobile/staging.local.json` passed; package, flags, fonts and all eight decoration assets verified |
| Native picker/preview and persisted-appearance regression | Full suite includes apply/cancel/draft isolation, real thumbnails, heading reveal, old appearance/custom styles, long Thai names/20 links and missing owner images; four custom-panel-paper regressions passed |
| Native visual capture | 1 capture test passed; all twenty actual Flutter compositions at 393dp, ratio 2, bundled fonts; no device/account preferences accessed |
| Public responsive/visual matrix | All 100 final pages at 320×800: four links, no horizontal overflow or missing images, minimum link target ≥44px. All twenty families with twenty long Thai links: no overflow or arrow/text collisions. All twenty families honor global/per-link colors and pill corners; desktop collage checked at 1280×900 |
| Eight raster assets | 14 asset-route tests passed within full suite; exact API/Mobile PNG byte parity, PNG/nosniff/cache headers, unknown/traversal 404; assets included in APK |
| Exact-commit remote CI | Subsequent integrated `9c7fa74` CI passes; see current delivery receipt above |
| Staging deploy/runtime/public-image checks | Integrated API is Live and compiled fixtures pass; public browser/owned-image checks remain unverified |
| Data-preserving emulator update | Matching integrated APK update is in progress; this earlier local APK is not installed |

Final local evidence is in `artifacts/profile-composition-qa`: API/mobile suite,
analysis and APK build logs; native capture receipt; responsive/custom-style
JSON; comparison PNGs; and `staging-apk-receipt.json`. The final APK SHA-256 is
`a12249ef091afc6576b5e2aa2b352d1864f194a458aa9649163c4bc874ecbaab`,
package `com.postdee.postdee_mobile.staging`, version `0.1.0-staging` (code 1),
min/target SDK 24/36. It targets `https://postdee-api-staging.onrender.com`,
Firebase project `project-798caf7e-85b8-45e3-af7`, Firebase auth on/local mock
auth off, RevenueCat off, experimental beat/AI hook off. This is a local APK
build receipt, not a claim that Staging has this source or that the APK is
installed. An initial `--flavor staging` attempt failed because this project
uses a debug build-type suffix rather than product flavors; the correct exact
build command above passed. No build configuration was changed to mask it.

An earlier default-worker API run hit the generator child-process test's 5s
deadline under CPU load. The direct generator check passed; the final full
suite limits workers to two and gives tests 20s. No assertion or product/API
request deadline was relaxed. The earlier API suite receipts of 1,544/1,547/
1,553 and Flutter 1,495 predate the last regressions; final counts are above.
The appearance editor image test now scopes its finder to the owner's actual
`MemoryImage` and verifies byte identity, because built-in template art makes a
global `find.byType(Image)` assertion unrelated to that behavior.

Reduced-motion and visitor-pause-removal regressions pass in the full suites.
The public renderer remains script-free, and a fresh actual 393px page had no
warn/error logs. The local acceptance phase had no remote runtime SHA; the
subsequent integrated runtime SHA is recorded in the current receipt above.
Final diff/parity audit confirms retained IDs, twenty strategies per category,
no deleted tracked files, no dependency-version/environment/entitlement/schema changes
and no unrelated profile/auth screen content rewrite. Local verification
precedes any authorized delivery. Preserve the receipt below as historical
evidence rather than substituting this revision's hashes/counts into it.

### Current-revision visual QA and comparison ledger

Accepted concept PNGs in the table above and actual rendered PNGs were read with
`view_image` in the same QA pass. Public pages were inspected using the Codex
Browser/IAB plugin, not a terminal-controlled browser. The fixture server uses
the real compiled renderer, catalog and allowlisted asset routes with in-memory
sample content only; it does not access account preferences, publish a profile,
change a database or call a provider. Public screenshots use 393×760 native-size
page frames; the narrow checks use 320×800. Desktop collage was checked at
1280×900, retaining the centered 520px page maximum.

Native captures use the actual Flutter `RenderRepaintBoundary` at 393 logical
pixels, pixel ratio 2, bundled Anuphan/Prompt and SDK MaterialIcons fonts. These
are native renders of the twenty compositions, not drawings of proposed UI or
emulator screenshots. Animation is disabled for stable comparison captures.
Public fixture effects including stickers are off; native static captures
retain the preset's sticker art while disabling animation. Actual owner effect
settings remain supported.

| Inspected comparison | Result and corrections | Actual evidence |
| --- | --- | --- |
| A1–A3 hierarchy and geometry | Open large editorial heading, divider before description, numbered rows; lavender double identity frame and outlined 2×2 tiles; portrait left, real copy right and dark-green lead link. Corrected initial boxes and avatar shapes. | `flutter-native/native-A.png`, `web-minimal.png` |
| B1–B3 stationery and window anatomy | Scalloped pink/ivory sheet with bow; tilted paper/tape collage and wide/pair/wide link rhythm; mint gingham outside, lilac three-dot rail and white window. Corrected opaque frames, flat backgrounds, pastel cycles and B2 corner/shadow defaults; final window dots are filled pink/yellow/mint and logo corners follow the catalog in both renderers. | `flutter-native/native-B.png`, `web-cute.png` |
| C1–C3 artwork and content separation | Leaf border around editable content; forest behind direct white copy and transparent links; meadow leading into torn-paper content. Corrected C2 white identity/footer cards and compressed C3 spacing. | `flutter-native/native-C.png`, `web-nature.png` |
| D1–D3 identity and link density | Gold seal on black invitation, cord/clipped ivory tag with black buttons, open white/black gallery with 2×2 outlined tiles. Corrected unwanted monogram boxes and circle clipping. | `flutter-native/native-D.png`, `web-luxury.png` |
| E1–E3 colors and button anatomy | Yellow poster/shadow links; purple frame/cream header/lime modular body; coral perforated ticket on blue with numbered cream rows. Corrected window framing, contrasting tile cycle and ticket palette. | `flutter-native/native-E.png`, `web-creative.png` |
| Additional five structural families | Rail has a small left identity, divider and numbered hairline rows; ribbon identity band/staggered links; notebook ruled sheet with right logo; arch contains media only, copy below; staircase has right logo and stepped links. Corrected public/native header placements, arch enclosure and default rail boxes/dots. | `flutter-native/native-F.png`, `web-minimal-20.png` |
| Brand marks, typography and live content | Reuse the existing normalized 40px platform slots, real Thai fonts, editable text and real safe destinations. Chooser thumbnails scale the real native renderer. No rasterized store copy or fake clickable controls. | Native PNGs, public 393px/320px pages, picker/composition tests |
| Owner customization and readable surfaces | Filled hairline rows and torn rows honor owner corner radius; old white-text snapshots keep readable fill. Owner background images retain the surface panel. Custom glass surfaces stay opaque; native paper does not cover custom surface colors. Defaults still retain stock art and hairline geometry. | Focused API/native regressions and public custom-style checks |

Above-the-fold copy check: the fixture identity is `noikub`, description is
`เลือกช่องทางที่ต้องการได้เลย`, and the four sample links are YouTube, Shopee,
TikTok and LINE. The renderer keeps those fields and destinations; it does not
add a store section, product claims, pricing or dashboard copy. Actual owners'
names, descriptions, categories and labels remain editable fields. Numbering,
title rails, paper and decorative frames are presentation only.

Intentional adaptations and limits: these fifteen concepts were accepted as
**bases for short link pages**, not flattened screenshot replacements. Keep
the supported Thai Anuphan/Prompt/system font families instead of adding the
luxury mockups' serif font to the API contract. Native preview footer remains
`PostDee`; public footer remains `สร้างหน้าเว็บร้านค้าด้วย PostDee`. Existing
authentic platform PNGs retain their artwork (including the TikTok asset's
black tile). Native preview card corners/scrolling and browser page chrome are
different containers. Long copy and twenty links extend the short page by
scrolling; they do not create new sections. Minor paper-edge details and the
window footer position are adaptations of the bases. These differences are
recorded, not described as pixel-identical output. Twenty structure families
are reused with category styling; there are one hundred choices, not one
hundred wholly unrelated structure engines.

Final evidence retained for review includes the five `web-*-20.png` category
boards, `web-100-default-320.json`,
`web-20-compositions-long-320.json`, `web-20-compositions-custom.json`,
`flutter-native/capture_manifest.json`, the six native boards, final suite/build
logs and `staging-apk-receipt.json`. Temporary fixture processes/tabs are closed
after verification. No current-revision remote CI, Staging runtime, public
owned-image integration or data-preserving device update is represented as
verified by these local results.

The accepted fifteen bases and latest browser output were directly inspected
for hierarchy, color, frame geometry, artwork, button anatomy, typography and
editable copy. Material mismatches discovered in that review and the owner
style audit were corrected; none remains unresolved within the accepted
short-page-base scope. The core category → twenty choices → draft preview →
cancel/apply → explicit save/publish boundaries are verified by the native/API
test suites; live account publication and owned R2 image checks remain delivery
checks. The implementation is faithfully verified against those fifteen bases
with the explicit adaptations above; it is not claimed to be pixel-identical.

### Current-revision changed files

- Catalog: `shared/profile-templates.json`,
  `scripts/generate-profile-templates.mjs` and its tests; generated TS/Dart
  catalog files and their catalog tests.
- Public rendering: `linkInBioRenderer.ts`, `linkInBioTemplateStyles.ts`, new
  `linkInBioCompositionStyles.ts`, `linkInBioRoutes.ts`, rendering tests and new
  `linkInBioDecorationAssets.test.ts`; eight API decoration PNGs.
- Mobile rendering: `link_in_bio_template_preview.dart`, new
  `link_in_bio_composition_art.dart`, `link_in_bio_theme_picker.dart`,
  `link_in_bio_preview.dart`, new `link_in_bio_composition_test.dart`, picker and
  appearance-editor regression tests; eight Mobile decoration PNGs and one
  asset-folder entry in `pubspec.yaml`.
- Documentation: this plan, `README.md`, `ROADMAP.md`, `API.md` and
  `ARCHITECTURE.md`. No profile/auth/home screen behavior, dependency version,
  environment flag, billing entitlement or schema file is changed.
- Final default `git diff` reports no content change in `profile_screen.dart`,
  `profile_screen_test.dart` or `app_test.dart`; their working-tree CRLF status
  is preserved without overwriting them.

## Initial category release — confirmed scope

The user explicitly chose five categories, twenty templates per category, and
differences in both layout and visual style. Categories: เรียบง่าย (minimal),
น่ารัก/พาสเทล (cute), ธรรมชาติ/อบอุ่น (nature), หรูหรา/พรีเมียม (luxury), and
สดใส/ครีเอทีฟ (creative). Remove the visitor pause control from public pages
and both mobile preview renderers. Retain the owner's effects settings and OS
reduced-motion support. Clarification answers were received before implementation.

## Baseline and preserved capabilities

- Canonical checkout: `.worktrees/recover-main-systems`, branch
  `codex/pinterest-mobile-ui`, starting commit `4132fc8`.
- Fresh `origin/main`: `bcd7153f196cd381a786b333b9b61a67dbe95ca3`, also the merge
  base; zero behind, fourteen ahead. Existing untracked `artifacts/` is excluded.
- Preserve the seven legacy theme IDs, all section and per-link colors/fonts,
  button shapes, description, owned avatar/cover/background images, categories,
  link ordering/visibility, featured promotion, safe contacts, and all 100
  byte-identical platform marks with their normalized 40px geometry.
- Preserve owner-scoped private drafts, explicit publication/update/unpublish,
  image ownership validation, the twenty-link limit, nonce CSP, and script-free
  public rendering. No product inventory, prices, video widgets, new provider,
  package rules, flags, dependencies, or database migration.

## Initial category release — design and implementation contract

- One authored `shared/profile-templates.json` catalog generates TypeScript and
  Dart definitions. IDs and layout fields are fixed allowlists, never CSS input.
- Optional nullable `appearance.templateId` extends version 1. Omitted/null
  means a legacy theme. Known IDs resolve a legacy `themeId` fallback; an
  explicitly mismatched theme is invalid. Existing records need no conversion.
- Twenty distinct structural combinations per category: five header placements
  (`centered`, `left`, `split`, `cover`, `badge`) with four link treatments
  (list/solid, list/outline, grid/soft, grid/raised). Each has an authored Thai
  name, palette, font, button shape, avatar shape and restrained decoration.
- Decoration enum: `none|line|dots|frame|stripe`; avatar enum:
  `circle|rounded|square`. Category changes filter the picker, not the draft.
- Flow: category → twenty template thumbnails → real draft preview → ใช้แบบนี้.
  Cancelling a preview leaves the draft unchanged. A collapsed legacy section
  retains the seven earlier choices. Publishing remains a separate review action.
- Selecting a preset changes style defaults but retains content and image keys;
  per-link colors/fonts remain editable and authoritative.
- Removing pause controls does not remove owner effects controls. Public CSS
  and Flutter MediaQuery/TickerMode continue to disable motion when requested.

## Initial category release — concept direction

ImageGen produced six preview-only concepts in the calling task's generated
image directory (not runtime assets):

| Surface | Concept file |
| --- | --- |
| Category picker | `exec-48241da9-193e-4c42-a026-b880f02b479d.png` |
| Minimal | `exec-c98dc972-513a-4bc8-acd9-4094e7fc1044.png` |
| Cute | `exec-ca83f4b8-6bd4-480a-847d-16f4c21454a5.png` |
| Nature | `exec-5542948e-df26-4829-8727-4db8f1bfce54.png` |
| Luxury | `exec-aea76f95-4705-40af-968e-eb4991bd57ba.png` |
| Creative | `exec-7191039b-819c-495c-8a07-cbb683e0e5d7.png` |

These were inspected with `view_image` as category directions; they were not
approved pixel-exact screenshots. Implementation keeps the user's real copy,
existing local fonts, exact bundled platform marks and code-native vectors.
Generated slogans, invented leaf branding, fake status bars, and rasterized
platform artwork are excluded. Native viewport scale, editable images and
long-text wrapping take precedence over generated typography/spacing.

Design system: white app chrome, near-black text, PostDee green selected chips
and strokes; horizontal category rail, two-column readable thumbnails, explicit
preview/apply. Public palettes: neutral white; blush/berry; cream/olive;
near-black/muted gold; yellow/black pop. Typography stays Anuphan/Prompt/system,
with 26–28px headings, 15–16px body, 12px footer and readable controls. Links
retain 40px icon slots and safe northeast vectors. No pause pill appears.

## Initial category release — validation and release order

Tests first: catalog count/uniqueness/parity, all 100 appearance round trips,
invalid-ID/mismatched-theme rejection, atomic legacy retention, safe rendering,
customization preservation, absence of pause controls, owner effects and OS
reduced motion, picker filter/cancel/apply, and narrow native/browser layouts.
Run relevant full API and Flutter suites, API build/Prisma validation, Flutter
analysis, exact Staging APK build, local rendered browser checks and native QA.
Results and the visual mismatch ledger are recorded below.

The user authorized push, Staging deployment and emulator update on 2026-10-07.
Deploy the API/catalog before
distributing mobile templates: the current Staging runtime understands the
seven earlier themes and can accept their base colors but silently discards the
new `templateId`, losing its layout. On the new API, omission of the entire
appearance preserves a saved selection, but an old client sending a complete
appearance without that field can clear it. Update clients before editing new
templates and avoid an API rollback after use. Do not publish or change the
customer's private draft for verification. Public Staging browser access is
still blocked by the saved browser permission; local QA is allowed.

## Initial category release — completed local verification

Evidence directory (outside the checkout):
`C:/Users/stopp/.codex/visualizations/2026/10/07/01a1153f-2c52-7c43-9fb7-ba3a4366835d`.

| Verification | Result |
| --- | --- |
| Shared generator tests and generated-file check | 12 tests passed; `--check` passed |
| Full API suite | 103 files / 1,469 tests passed |
| Final API catalog/render regressions after palette correction | 157 tests passed |
| API build, Prisma schema validation and helper typecheck | Passed; schema/migrations unchanged |
| Full final Flutter suite | 1,422 tests passed; `profile-100-templates-flutter-delivery-final.log` |
| Flutter analyze | No issues; `profile-100-templates-flutter-delivery-analyze.log` |
| Local rendered public-page matrix | 310 cases passed; `profile-template-browser-qa.json` |
| Stable final public screenshots | Six captures passed; `profile-template-browser-screenshots.json` |
| Real Staging main-entry APK | Debug build passed; `profile-template-staging-apk-build.log` |
| Native picker and full raised-grid preview | Inspected on Android API 34, emulator-5554; no pause control |
| Native restoration | Original APK and preferences hashes matched; `profile-template-native-restored.json` |

The browser matrix covers all 100 templates at 320/393/768px, seven legacy
themes at 320px, and a twenty-link custom/contact/long-Thai profile at three
widths. It checks absence of horizontal overflow, readable content, 40px loaded
logo geometry, touch targets, safe contact links, no pause/script markup, CSP,
reduced motion, and the actual in-memory route publish/read/invalid/unpublish
lifecycle. IAB was used first for a meaningful rendered page, keyboard focus
and empty error logs. The formal Browser plugin is not listed in this session;
Playwright provided the repeatable responsive matrix. No customer data or live
draft was used. Browser external requests were blocked by the local test harness.

The broader TypeScript check including every test has 129 existing diagnostics;
none concern the affected link-in-bio modules or added tests. The production
API build passed. At local acceptance, remote CI had not yet run; the authorized
exact-commit CI and Staging delivery are recorded below. Live customer
publication/public-browser image reload, iOS, and physical-device checks remain
unverified. The earlier release's remote CI does not verify this new work.

## Initial category release — visual fidelity and corrections

These checks compare category direction and implemented shared primitives,
not pixel-perfect fidelity to unapproved generated concepts.

| Surface / concern | Final observation |
| --- | --- |
| Picker | White chrome, green active category/stroke/check, two-column schematic layout thumbnails; preview then explicit apply. Short chip labels keep the rail readable. |
| Minimal | Neutral white, dark readable text, restrained line decoration and outlined list links. |
| Cute | Blush/berry palette, rounded buttons and delicate framing; content and bundled marks stay real. |
| Nature | Cream/olive palette, calm spacing and outlined links. |
| Luxury | Near-black/gold palette, badge/avatar framing and clear contrast. |
| Creative | Bright palette, outlined raised links and grid/list variants. The first template is a grid instead of the concept's list as part of the requested structural variety. |
| Cross-surface geometry | 40px platform marks; 26px narrow / 28px larger titles; 16px link text; outline override borders, pill radius 999 and raised 2px border / opaque 4px shadow agree. |
| Motion | Public and native pause controls absent; editor effects toggles and OS reduced motion remain. |

Corrections made from review: outline colors originally blended into white
backgrounds; all authored default text palettes now meet 4.5:1 contrast on their
intended backgrounds. Bounded 120px previews now show the store title for every
header, including small width, large text and an owned cover. Loading an owned
cover reserves its space. Grid pill radius and custom outline borders now match
the web. Raised-grid arrows moved to the bottom right, shadow opacity/border
width and heading/link spacing were aligned. Fifteen added native regressions
cover these review findings. Early screenshot capture caught running entrance
transitions; the screenshot harness now waits for opaque content and removes
hover before capture. No product animation was removed to fix that test artifact.

Intentional limits: schematic thumbnails avoid dozens of simultaneous animated
previews; the selected modal renders the actual store content. Native Wrap keeps
natural card heights while CSS grid stretches cards in a row; long-copy tests
show no ordering/content loss or overflow. Generated slogans, fake status bars,
invented leaf logos and rasterized brands were excluded. All 100 original
platform assets, fonts, config, dependencies and schema remain unchanged.

## Initial category release — exact environment and handoff

- Final main-entry APK package: `com.postdee.postdee_mobile.staging`, version
  `0.1.0-staging`, target/compile SDK 36. SHA-256:
  `1686590fc2f3d9373d64304e205b5fca629e7e9db8191246d8be26939515c4d1`.
- Defines from `D:/PostDeeMobile/apps/mobile/staging.local.json`: API
  `https://postdee-api-staging.onrender.com`; Firebase auth true, local mock
  auth false, RevenueCat billing false, beat sync false, AI hook false.
- Debug Firebase project: `project-798caf7e-85b8-45e3-af7`. No account,
  entitlement or package rules were changed. The restored app opens the signed-in
  Home screen and shows its existing Free entitlement.
- Native visual fixture imported the real picker/preview with isolated Mali
  Studio sample data and no Firebase/network/preferences/save calls. It was
  removed by restoring the original installed APK. APK/preferences hashes both
  matched their recorded baseline before reopening the original app.
- At local acceptance, the final main-entry APK was built but not installed on
  the old API. The subsequent release followed exact-commit CI, API Live, then
  data-preserving installation. No new migration is needed. During deployment,
  the service reported fourteen existing migrations and none pending.
- At local acceptance, no commit, push, merge, PR or deployment had occurred for
  this scope. The subsequent authorized delivery is recorded below. The
  existing untracked `artifacts/` remains excluded and untouched. Changes are
  limited to the catalog, appearance contract, public/native rendering/picker,
  their regressions, generator CI check and these related documents.

## Authorized Staging delivery — 2026-10-07

- The user explicitly authorized push, Staging deployment and emulator update
  by replying “ต่อเลย” to the release question. No additional confirmation was
  required. A fresh fetch kept origin/main at `bcd7153f196cd381a786b333b9b61a67dbe95ca3`;
  before commit this checkout was zero behind / fourteen ahead of main and
  matched its remote feature branch.
- Feature commit `fc087c4119cd46503c569879e61cddf99e402fb2`, **Add 100 profile
  templates and simplify motion controls**, includes only the 32 related
  files and was pushed to `codex/pinterest-mobile-ui`. No merge into main or
  Production deployment was performed; existing untracked artifacts were excluded.
- [CI run 37599020895](https://github.com/NOI56/PostDeeMobile/actions/runs/37599020895)
  succeeded on that exact SHA: API 103 files / 1,469 tests, generator 12 tests,
  generated-catalog parity, API build, Prisma schema and production audit;
  Flutter analysis and 1,422 tests. Evidence: `profile-template-release-ci-summary.json`,
  `profile-template-release-ci-run.json`, `profile-template-release-ci.log`.
- [Render deploy dep-db30rph42hec7386vvrg](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db30rph42hec7386vvrg)
  used **Deploy a specific commit** on the existing `postdee-api-staging`
  service `srv-d9bb72ojs32c739osa5g`. Source and checkout logs identify the
  feature SHA. The configured main-branch label does not indicate a merge.
  Service plan, Auto-Deploy, environment and health-check settings were unchanged.
- Started at 16:16:22 GMT+7; **Deploy succeeded | Live** at 16:18:19, duration
  1m56s. Startup confirms PostgreSQL `postdee_staging`, fourteen migrations and
  **No pending migrations to apply**, port 10000, existing disabled social
  publisher and in-process memory scheduler. Pruning reports the same four
  moderate production advisories; this scope changes no dependencies.
- A read-only command in the running instance `dm5pl` imported the actual
  compiled catalog, validator and renderer. It confirmed
  `RENDER_GIT_COMMIT=fc087c4119cd46503c569879e61cddf99e402fb2`, five categories
  of twenty, all 100 appearance round trips and HTML renders, and no pause
  markup. Only an in-memory sample was rendered; no database/storage/user
  write or HTTP publication occurred. Evidence: `profile-template-release-runtime-check.txt`
  and `.png`. This does not bypass the saved public-site browser restriction.
- Render evidence: `profile-template-release-staging-deploy.txt` and
  `profile-template-release-staging-live.png`. The temporary Shell tab was
  closed; the deployment result remains open as the delivery evidence.
- After API Live, `adb install -r` installed the final **main-entry** APK on
  emulator-5554. Installed bytes match
  `1686590fc2f3d9373d64304e205b5fca629e7e9db8191246d8be26939515c4d1`.
  A fresh baseline immediately before installation and the final smoke agree:
  preferences SHA-256 `d531f37d6410fb954b4a8cc28c111d32f02786ff21cee1801c0399536dec5769`,
  account snapshot unchanged, owned draft unchanged. The existing pink draft
  still has two enabled links, the signed-in account remains present and Home
  shows its existing Free entitlement (0/3). API/Firebase/feature flags match
  the exact environment recorded above.
- Native smoke opened the real store manager, all five category headings
  (twenty templates each), and the Yellow Pop grid modal with the owner's name,
  logo, YouTube/Shopee marks and footer. No pause control appears. Cancelling
  the preview retains the pink appearance. No apply, save, publish, billing or
  account change was invoked. The final app remains open on the Creative chooser.
  Android UIAutomator returned a null root once; no stale accessibility tree
  was used. Subsequent SDK actions were based on fresh emulator screenshots.
- Native evidence: `profile-template-release-installed.json`,
  `profile-template-release-after.json`, `profile-template-release-smoke.json`,
  `profile-template-release-real-category-{cute,nature,luxury,creative}.png`,
  `profile-template-release-real-picker.png`,
  `profile-template-release-real-grid-preview.png`, and
  `profile-template-release-final-picker.png`. Final audit confirms
  `apkMatches`, `preferencesUnchanged`, `accountUnchanged`, `draftsUnchanged`
  and `noSaveOrPublish` all true.
- Shared pages now use the updated renderer, including pause-button removal.
  Applying a new template to a customer's published page remains an explicit
  owner Update action. No live customer publication was performed for QA, and
  no public Staging browser/image, iOS or physical-device rendering is claimed.
- README, ROADMAP, API and ARCHITECTURE record this exact release. The delivery
  receipt changes only these documents and this plan; it does not change the
  runtime source tested by CI, deployed by Render or built into the installed APK.
