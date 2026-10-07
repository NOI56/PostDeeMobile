# Profile template categories — 2026-10-07

## Confirmed scope

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

## Design and implementation contract

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

## Concept direction

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

## Validation and release order

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

## Completed local verification

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
API build passed. Remote CI, live Staging publication/image reload, iOS, and
physical-device checks have not run for this revision. The earlier release's
remote CI does not verify this new work.

## Visual fidelity and corrections

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

## Exact environment and handoff

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
- The final new main-entry APK is built but not installed on the old API.
  Ship API and pass exact-commit CI first, then update the emulator/app with
  data-preserving installation. No new migration is needed; the existing
  deployment's migration state was not re-queried in this local task.
- At local acceptance, no commit, push, merge, PR or deployment had occurred for
  this scope. The subsequent authorized delivery is recorded below. The
  existing untracked `artifacts/` remains excluded and untouched. Changes are
  limited to the catalog, appearance contract, public/native rendering/picker,
  their regressions, generator CI check and these related documents.
