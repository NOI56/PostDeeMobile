# Selected profile themes and motion — 2026-10-07

The user selected Pinterest options 2, 3 and 6: pink pastel, cottage garden,
and lavender storefront cards. Add these alongside the four existing themes.
Interpret the pending motion preference as optional automatic animation for
this implementation; free-position dragging and animated media uploads are
not part of the selected theme work.

## Verified baseline

Use `D:/PostDeeMobile/.worktrees/recover-main-systems`, branch
`codex/pinterest-mobile-ui`, starting HEAD
`86e55c7dc6ca832b62b6bce2c9fc552cfa758766`. Fresh `git fetch origin`
confirmed `origin/main` at `bcd7153f196cd381a786b333b9b61a67dbe95ca3`,
the same merge base, 0 behind and 12 ahead. Preserve the unrelated dirty root
checkout and pre-existing untracked `artifacts/` in the canonical checkout.

## Design and scope

- Pinterest references: [pink](https://in.pinterest.com/pin/1010847078900174633/),
  [garden](https://in.pinterest.com/pin/39617671719718376/),
  [cards](https://in.pinterest.com/pin/1010847078900260937/).
- Built-in Image Gen produced three full portrait visual concepts in
  `C:/Users/stopp/.codex/generated_images/01a1153f-2c52-7c43-9fb7-ba3a4366835d`:
  pink `exec-130f7ecd-ca7b-4d57-a55e-211279cafdd8.png`, garden
  `exec-09facf24-91a6-4fe4-9d69-455dc589df9c.png`, cards
  `exec-640394d8-8281-4c9d-b370-5ec1e5d3e41c.png`.
- Keep UI text, monogram, vectors, real platform artwork and controls native
  to HTML/CSS/Flutter. No generated concept is used as a runtime screenshot.
- Tokens: pink `#fff1f6/#fde6ee/#b94f78/#67364d`, garden
  `#fffaf0/#fffef8/#718852/#35472c`, cards
  `#eee8f7/#f7f3fc/#ffffff/#40364e/#8b67b5`.
- Existing Thai Anuphan/Prompt fonts, centered header and monogram, 12px link
  spacing, pill pink links, 16px garden links, taller white storefront cards
  with `เปิดลิงก์`. Only existing profile/link fields are used; no product
  inventory, fake prices, statistics, people or photographs are introduced.
- Intentional corrections to generated artwork preserve prior user requests:
  use the 100 real bundled logos at their audited 40px visible geometry with
  no added white badge; retain the existing PostDee footer rather than the
  invented heart brand mark; retain actual editable promotion copy.
- Add optional validated `effects` to appearance version 1: background,
  entrance and featured booleans, stickers `none/hearts/flowers/sparkles`.
  Legacy defaults are all off. New theme presets may opt into gentle effects.
- Implement CSS-only public motion under existing nonce/CSP (no JavaScript),
  a visitor pause control, reduced-motion handling, and equivalent Flutter
  preview behavior. Decorative shapes are inaccessible/non-interactive.
- Extend theme thumbnail choices and a collapsed `ลูกเล่น` group; preserve
  existing advanced groups, colors/fonts, images, custom titles, overrides,
  safe contacts, order, 20-link limit, owner scope, account and plan rights.
- No provider/API key, dependency, configuration flag, schema or migration
  changes. API needs the new enum/optional fields before Mobile publishes them.

## Validation and delivery

Regression tests were added before runtime changes. API's 101 files / 1,344 tests,
build, Prisma validation and Prisma helper type-check pass. The complete API
test-inclusive type-check has 129 existing diagnostics; an archive of exact
starting HEAD with the same dependencies produced byte-identical diagnostics.
No new type error is introduced; do not describe this broad check as clean.
One full run hit the existing 100-image test's 15s timeout during emulator boot;
the complete suite passed with two workers, without changing its timeout/code.
The final Flutter suite has 1,300 passing tests and `flutter analyze` reports
no issues. Earlier concurrent verification runs were invalidated by ongoing
source edits and do not serve as final acceptance evidence.

Local browser flow: actual compiled `/p/theme-*` routes -> view links -> pause ->
resume with keyboard -> reduced motion -> all link content remains reachable.
Browser plugin is not available. CUA/IAB verified actual pages, text, URL/title
and pause. Its portrait viewport screenshot was scaled into a larger canvas;
full-page screenshots worked. Existing Playwright Chromium 1223 provided
repeatable breakpoint/media checks and correctly sized screenshots, with no
dependency installation or remote navigation. At 320/393/1440 x 852, all 14
cases pass: seven presets plus a customized square-card 20-link page; page
identity/content, no framework overlay, zero relevant console/HTTP errors,
responsive layout, loaded 40px logos, safe contacts, CSS-only CSP, pause, actual
distinct motion frames, keyboard resume and reduced-motion visibility. The
initial local fixture omitted the existing font-route registration; this was
fixed in the fixture, not product routes. No customer profile was published.

Design fidelity was inspected with `view_image` on each generated concept and
the actual 393px browser screenshot, plus native emulator screenshots. Compare
the selected Pinterest directions and the repository-constrained design spec;
the generated artwork is inspiration, not an approved pixel-exact replacement.

| Inspected point | Rendered evidence / decision |
| --- | --- |
| Palettes and hierarchy | Pink blush/berry, garden cream/olive, lavender/white cards retain the specified palette and centered store header. |
| Header/avatar | 112px monogram or owned uploaded logo, centered name and description; reuse bundled Thai fonts, not generated font shapes. |
| Link anatomy | Pink pills, rounded garden links/divider, taller white cards with purple `เปิดลิงก์`; 12px spacing and real link content. |
| Platform marks | All 100 byte-identical assets remain at audited 40px visible geometry; generated white badge wrappers deliberately omitted per the user's prior request. |
| Promotion | Actual editable promotion text retained; card preset uses its lavender pill. Existing button shapes/colors/fonts and per-link overrides still apply. |
| Motion/decoration | Fixed, gentle heart/flower/sparkle shapes, pause/resume and reduced motion; lower decoration density preserves readability and tap areas. |
| Copy/footer | Existing Thai store/description/category/link text wins over rewritten generated link titles; original plain PostDee footer replaces invented heart branding. No fake products/prices. |
| Mobile chrome | Collapsed effects section; the bounded preview now starts at readable store content with a visible scrollbar, instead of showing only the large avatar. Full avatar/cover remain reachable above it. |

The above-fold copy diff preserves real user content. Fixture-only store and
description copy match the design brief; LINE/YouTube titles use actual fixture
link values rather than the generated artwork's rewrites. Intentional deviations
are recorded above; this is verification of the chosen theme directions and
editable product UI, not a claim of 10/10 pixel matching an unapproved image.
Material defects fixed: overflowing theme thumbnails, preview avatar cropping,
ignored custom button shape on new public themes, hidden focus control under
reduced motion, and static native image backgrounds when motion was enabled.
Both old/new native image previews now move and freeze correctly when paused.
README, ROADMAP, API and ARCHITECTURE describe the additive contract and order.

This new theme feature has not been pushed or deployed. Any release must use
specific session authorization, the exact tested SHA and API-before-Mobile
order. The previously blocked public Staging browser is not bypassed by local
rendering checks; record live rendering separately if it becomes available.

### Final Android evidence

The final runtime source built successfully with the existing Staging dart
defines. This project uses the debug application suffix, not a named Staging
flavor. Installed package: `com.postdee.postdee_mobile.staging`, version
`0.1.0-staging`; API base: `https://postdee-api-staging.onrender.com`; Firebase
project: `project-798caf7e-85b8-45e3-af7`. Firebase authentication is enabled,
mock authentication, RevenueCat, BeatSync and AI Hook flags are disabled.
The existing appearance JSON column requires no new migration for this change.

The Android API 34 PostDee_Pixel emulator retained its Google account and the
existing noikub store/free entitlement (0 of 3). Installation used `adb install
-r`. Installed APK SHA-256 matches the final built APK:
`cba85615a3e161942a0812172f079f98f9670ab58c06638d87c015406b4cafe2`.
Preferences SHA-256 before installation and after the final smoke is unchanged:
`3a3c91d727b12ad8a14b0ce7cbb6425264083e38b586bc69827f7705a6546235`.

Six native smoke steps pass: home entitlement, existing profile manager, all
three selected new theme previews, and the expanded effects controls. No draft
save or publish was invoked. The app was force-stopped to discard the temporary
in-memory theme choices and then reopened with the existing stored profile.
The web checks used local owned fixture data; no live Staging public web or iOS
rendering was verified. New themes must be enabled on the API before shipping
the Mobile release; installing the test APK alone does not update shared pages.

Retained evidence root:
`C:/Users/stopp/.codex/visualizations/2026/10/07/01a1153f-2c52-7c43-9fb7-ba3a4366835d`.
Public screenshots: `profile-themes-{pink,garden,cards}-393.png`;
native screenshots: `profile-themes-native-final-{pink,garden,cards,effects}.png`.
Machine-readable records: `profile-themes-browser-qa.json`,
`profile-themes-native-smoke.json` and `profile-themes-native-after.json`.
Final test/build logs are retained alongside these files.

Removal of temporary QA artifacts was rejected by the execution policy before
the command ran. No cleanup took place; the temporary baseline, scripts and
superseded screenshots remain outside the repository. The baseline contains a
node_modules junction and must not be recursively removed through that junction.
Pre-existing checkout artifacts and user work were not removed.
