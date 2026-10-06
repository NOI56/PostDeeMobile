# Profile platform logos

## Scope and verified baseline

The user confirmed replacing platform symbols with correct logos on both the
public profile page and mobile app. The reported YouTube play symbol and Shopee
`S` were generated placeholders rather than the corresponding platform artwork.
This change covers YouTube, Shopee, Lazada, LINE, TikTok, Instagram and Facebook
in the internal link manager, mobile preview and public renderer.

Freshly fetched baseline: `HEAD = origin/codex/pinterest-mobile-ui`,
`cc071281181db03f0e72bc42d1e947084ff5f591`, on `codex/pinterest-mobile-ui`
in the canonical recovery worktree. `origin/main` is
`bcd7153f196cd381a786b333b9b61a67dbe95ca3`; the feature branch is one commit
ahead and zero behind main. Tracked files were clean before this change;
pre-existing untracked `artifacts/` are retained. No merge, push or deployment
had been performed at the end of local verification. On 6 October 2026 the
user authorized pushing this change and deploying it to Staging. Delivery uses
the verified feature commit directly; Production is outside this request.

## Implementation and preservation

- Reuse the four existing YouTube, Instagram, Facebook and TikTok mobile PNGs
  without changes. Add Shopee and LINE original official PNGs and the original
  Lazada favicon frame decoded losslessly to PNG. Copy all seven byte-identically
  into `apps/api/assets/profile-platforms`. Preserve original artwork, aspect
  ratios and colors. Sources, dimensions and SHA-256 parity are recorded in the
  asset directory's README.
- Use white 40 x 40 badges and contain sizing on all three surfaces. Keep link
  titles as accessible names and brand images decorative. Do not tint, crop,
  invent replacement brand artwork or dim the logo on hover.
- Share the Flutter `BioPlatformLogo` widget between preview and manager cards.
  Asset loading has a generic fallback. Known asset paths are fixed; arbitrary
  icon values do not become local image paths.
- Serve public `GET /profile-platforms/:file` before authenticated owner routes.
  Allow only seven known filenames, returning `image/png`, nosniff and a one-day
  public cache; unknown files return 404. Keep the page's `img-src 'self'` CSP.
  Do not hotlink vendor images, fetch user URLs or depend on private R2 storage.
- Preserve automatic hostname recognition, exact/subdomain matching, explicit
  brand and generic icon overrides, URL escaping, title suggestions, custom
  colors/fonts, ordering, enabled-only publication and owner isolation.
  Draft saving/publication stays explicit. No social publishing destination or
  platform partnership is added by displaying a mark.

No dependency, feature flag, credential, entitlement, database schema,
environment configuration or publish request/response contract changes are
needed. The public static-asset route is additive. Deploy API plus bundled
assets to update existing published pages without republishing; ship the mobile
build to update its locally rendered cards/previews. There is no new migration.
The earlier customization migration and deferred live browser/R2 checks remain
historical release requirements, not results of this logo refinement.

## Verification

Tests were written before implementation. The API logo suite initially had
17 failures and 10 passes against the old behavior. The mobile regression failed
because a YouTube AssetImage was absent from the old preview. Verification logs
use `platform-logo-*` and `platform-logos-api-*` prefixes in
`C:\Users\stopp\.codex\visualizations\2026\10\04\01a105f6-2943-7ae3-9df1-447070022cb2`.

- API targeted link-in-bio suites: 124/124 pass, including 27 logo-route/renderer
  regressions. Coverage includes original-asset parity, all seven marks,
  overrides, unknown/spoofed domains, route authentication independence,
  filename rejection, response headers and unchanged self-only CSP.
- Complete API suite: 1,187/1,187 pass across 97 files. Production build,
  Prisma validation, explicit seed/config helper type-check and isolated new
  logo-suite type-check pass. No database migration or data mutation was run.
- A broader TypeScript check including historical test fixtures fails in
  unchanged files. Current and isolated `cc07128` baseline each emit the same
  360 diagnostic lines with zero comparison differences. This is confirmed
  pre-existing test-fixture typing debt; production compilation passes.
- Mobile targeted logo/preview/manager suites: 20/20 pass, including six new
  regressions. Checks cover bundled PNG decoding, original-color AssetImages,
  contain sizing, 40 x 40 badges, dark preview, overrides/spoofed domains and
  manager controls.
- Complete Flutter suite: 1,150/1,150 pass, and Flutter analyze reports no
  issues. The first full run exposed one existing customization test that
  counted every Image widget as the uploaded store logo; platform marks add
  AssetImages. Its assertion now scopes the uploaded MemoryImage, retaining
  that behavior check. The final full run is green.
- Original source artwork and API/mobile byte parity were visually/file checked.

Local browser QA uses the compiled API with an in-memory fixture at
`http://127.0.0.1:4793`, not a deployed service or customer data. Existing bundled
Playwright 1.62.1/Chromium 1223 was used because the Browser plugin is unavailable;
no dependency was installed. Desktop 700 x 650 and mobile 393 x 852 checks pass
for seven known marks plus unknown, spoofed-domain and explicit-override links.
Images load at 40 x 40 with contain sizing and white surfaces under the unchanged
self-only CSP; bundled font routes load too. An actual click on the YouTube-logo
anchor was intercepted locally and verified the destination popup URL and null
opener. Focus outline and hover behavior preserve visible keyboard focus and
original image colors. No horizontal overflow, console or page errors were seen;
desktop and mobile screenshots were visually inspected.

## Exact delivery build and native checks

The Staging debug APK build passes using the existing
`D:\PostDeeMobile\apps\mobile\staging.local.json`. Delivery configuration is
API `https://postdee-api-staging.onrender.com`, Firebase authentication enabled
with project `project-798caf7e-85b8-45e3-af7`, package
`com.postdee.postdee_mobile.staging`, and mock, RevenueCat and experimental
flags false. Installation used `adb install -r` to retain app/account data.
Local and installed APK SHA-256 match exactly:

`BB5CA11999E013729B1EA1BCAA7C78ED02D9E2BD8611277CFFAEACE5DE371FEE`.

Native QA on `emulator-5554`, Android API 34, 1080 x 2400 at density 420
(approximately 411 x 914 dp), shows the existing published `noikub` profile's
two YouTube/Shopee links with correct artwork in the manager and review preview.
The manager-to-preview tap succeeds; both screenshots were visually inspected
for original colors, contain sizing and consistent placement. No draft Save,
publish or unpublish was performed. The existing account and Free 0/3 state
remain, and SharedPreferences before installation and after QA have identical
SHA-256:

`17ce723edcece60378f0769ef76d7e895aa55945bdf21ae52fcf7d727bd62cc9`.

The current app-process log has no FATAL, Unhandled Exception, RenderFlex,
E/flutter or Unable to load asset matches. Evidence in the visualization folder:

| Evidence | Result |
| --- | --- |
| `platform-logo-mobile-full-final.log`, `platform-logo-mobile-analyze.log` | Final 1,150-test run and analysis pass. |
| `platform-logo-mobile-build.log` | Exact Staging debug APK build passes. |
| `platform-logo-browser-qa.log` | Local compiled browser interaction/layout checks pass. |
| `platform-logo-web-desktop.png`, `platform-logo-web-mobile.png`, `platform-logo-web-all-mobile.png`, `platform-logo-web-focus.png` | Inspected two-link and full-platform rendering plus focus state. |
| `platform-logo-native-manager.png`, `platform-logo-native-preview.png` | Inspected actual two-link manager and review preview on installed APK. |
| `platform-logo-native-logcat.log` | Current process scan contains no matching runtime/asset errors. |

Native coverage is the actual two-link profile on API 34; all seven marks are
covered by widgets and local browser QA, not by a seven-link native fixture.
Native full-screen preview, dark mode, physical devices, iOS and target API 36
were not exercised in this follow-up. Live Staging public browser checking,
API deployment and Production acceptance remain unverified. Deployment requires
the user's authorization; the web rendering fix and assets are ready locally.
No migration is required. Earlier live R2 lifecycle checks remain deferred.
