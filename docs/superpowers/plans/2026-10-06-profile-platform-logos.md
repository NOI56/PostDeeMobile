# Profile platform logos

The initial implementation, verification and deployment sections below record
the first release with white badge surfaces. The background correction at the
end records the subsequent change separately; earlier evidence is preserved.

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
were not exercised in this follow-up. Live Staging public browser checking
and Production acceptance remain unverified. Staging delivery is recorded below.
No migration is required. Earlier live R2 lifecycle checks remain deferred.

## Authorized push and Staging deployment

On 6 October 2026 the user authorized push and deploy to Staging. A fresh fetch
still confirmed `origin/main = bcd7153` and feature baseline `cc07128`; only the
26 logo/source/test/doc files were committed. Existing untracked `artifacts/`
and the unrelated dirty root checkout were excluded.

- Pushed implementation commit `fec5763a8bc5b143448e9af864ec08a9174acbf0`
  to `origin/codex/pinterest-mobile-ui`. No merge into `main` was performed.
- Manually dispatched [CI run 37456579263](https://github.com/NOI56/PostDeeMobile/actions/runs/37456579263)
  on that exact SHA, because feature-branch pushes do not automatically run the
  workflow. Both Flutter Mobile and Backend API completed successfully. API
  CI reports 1,187 passing tests across 97 files and includes build, Prisma
  validation and production dependency audit; mobile analysis and tests pass.
- Render service `srv-d9bb72ojs32c739osa5g` deployed the specific commit through
  its Dashboard. [Deploy `dep-db2do6ei0phs73eagveg`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db2do6ei0phs73eagveg)
  displays `Deploy succeeded | Live`, source `fec5763`, duration 1m49s. Logs
  show checkout of the full target SHA, build success and service Live at
  18:33:27 Asia/Bangkok. Database startup reports 14 existing migrations and
  `No pending migrations to apply`; API listens on port 10000, starts its
  memory scheduler and retains `mode=disabled; publisher=disabled`.
- Render's Dashboard-specific-commit action disables Auto-Deploy. The Settings
  banner confirms this state. The linked branch remains `main`; integrate this
  release there before reenabling Auto-Deploy to avoid replacing it with older
  linked-branch code. No service plan, secret/env values or Production deployment
  was changed.
- Browser access to `postdee-api-staging.onrender.com` was rejected by the saved
  user permission policy. No alternate browser/HTTP route was used to work
  around it. Render Live/startup evidence is verified, but the public page and
  seven public PNGs were not checked live; the earlier local rendered/compiled
  asset checks remain the evidence for those behaviors.

Evidence in the same visualization folder: `platform-logo-github-ci.json`,
`platform-logo-staging-deploy-snapshot.txt` and
`platform-logo-staging-deploy-live.png`. The final image shows Live status,
target source SHA and successful startup logs.

## Follow-up: remove added white logo backgrounds

After the first Staging release, the user reported unwanted white logo
backgrounds. Baseline for this corrective follow-up is `552c156` on the same
canonical worktree and feature branch. The cause has two parts: the UI added
a white fill behind every known mark, and the original YouTube asset itself had
an opaque white canvas. Shopee's original PNG already has transparency, so its
visible white background came from the wrapper rather than altered artwork.

The correction changes known-mark wrappers to transparent on the public page,
mobile manager and preview while retaining 40 x 40 sizing, contain fitting and
original colors. Generic fallback styling is retained. Replace only the two
API/mobile `youtube.png` copies with original transparent official source bytes:
[YouTube icon guidelines](https://brand.youtube/youtube-icon/),
[official icon archive](https://www.gstatic.com/marketing-cms/89/d9/cf95c4f345709f4998dc581221b0/youtube-icon.zip),
member `YouTube_Icon/Digital/01 Red/yt_icon_red_digital.png`, 1255 x 1075 pixels.
SHA-256 for both copies is
`1027B1B0517727ADB9697155A270744381C3CE9B047B1C8BD8A9389DC7D07A83`.
The white play triangle is part of the original YouTube mark and stays intact;
the other six PNGs, including transparent Shopee, are unchanged. All seven
API/mobile copies remain byte-identical. Exact provenance is recorded in
`apps/api/assets/profile-platforms/README.md`.

Use `/profile-platforms/youtube.png?v=2` in the renderer to bypass the previously
cached opaque asset. The route still accepts only the same seven filenames and
retains its one-day PNG cache, nosniff headers and self-only page CSP. No schema,
package, architecture, dependency, environment, owner scope or publish-contract
change is required; published profiles need no republishing after API/assets
deployment.

The user's push/deploy-to-Staging authorization covers this correction in the
same scope. The corrective checks below verify the changed artwork and wrapper
separately from the earlier release. Corrective push and Staging deployment are
complete as recorded below. Live Staging browser access remains blocked by
saved permissions and is not bypassed. Production is outside this follow-up.

### Corrective verification and exact APK

API targeted suites pass 126/126; the complete API suite passes 1,189/1,189
across 97 files. API build, Prisma validation, helper type-check and strict
logo-suite type-check pass. Flutter targeted checks pass 21/21; the final full
suite passes 1,152/1,152, and analyze reports no issues.

The first targeted/full Flutter runs caught stale bundled YouTube bytes even
though the source PNG was replaced correctly. The official archive preserved
its original 2017 modification timestamp, so incremental Flutter asset bundling
reused the previous cached image. Refreshing only the source file's modification
time leaves its original bytes intact and invalidates that cache. The targeted
and full suites were rerun successfully, and the bundled PNG SHA-256 now matches
the transparent source hash recorded above. No unrelated implementation was
changed to resolve the failed checks.

The exact Staging debug APK builds successfully and was installed with
`adb install -r`. API origin, Firebase project, package and feature flags match
the earlier verified delivery environment. Local and installed APK SHA-256:

`C035675D5F95C38C90DD169512EA090D3704477DA28ACE7F830CB6641E109BB8`.

Native manager-to-`ดูตัวอย่าง` navigation succeeds on the same API 34 emulator.
The actual two-link YouTube/Shopee manager and preview were visually inspected
with transparent wrappers and original colors. No draft saving, publication or
unpublication was performed. SharedPreferences before and after these checks
retain SHA-256
`17ce723edcece60378f0769ef76d7e895aa55945bdf21ae52fcf7d727bd62cc9`.
The current process log contains zero relevant Flutter/runtime/asset errors.
Native coverage remains these two actual links; full seven-platform coverage
is provided by widgets and the local browser rather than a native fixture.

Local compiled browser checks pass at desktop 700 x 650 and mobile 393 x 852.
Five checks cover the two-link and seven-platform fixtures, generic/spoofed-domain
fallbacks and manual overrides, source parity for all seven assets, transparent
wrappers, original colors and contain fitting. Clicking the YouTube image opens
the expected destination in a locally fulfilled popup with a null opener;
3px keyboard focus outline, hover colors, accessible titles and self-only CSP
remain correct. No overflow, console errors or HTTP issues were found.

Logs and inspected screenshots use the `platform-logo-transparent-*` prefix in
the same visualization folder:

| Evidence | Result |
| --- | --- |
| `platform-logo-transparent-api-full.log`, `platform-logo-transparent-api-build.log`, `platform-logo-transparent-api-prisma.log` | Final full API suite, build and schema validation pass. |
| `platform-logo-transparent-mobile-targeted-final.log`, `platform-logo-transparent-mobile-full-final.log`, `platform-logo-transparent-mobile-analyze.log` | Final targeted/full Flutter suites and analysis pass after cache invalidation. |
| `platform-logo-transparent-mobile-build.log` | Exact Staging APK build passes. |
| `platform-logo-transparent-browser-result.json`, `platform-logo-transparent-web-desktop.png`, `platform-logo-transparent-web-mobile.png`, `platform-logo-transparent-web-all-mobile.png`, `platform-logo-transparent-web-focus.png` | Compiled local browser checks and inspected transparent-logo rendering. |
| `platform-logo-transparent-native-manager.png`, `platform-logo-transparent-native-preview.png`, `platform-logo-transparent-native-logcat.log` | Inspected actual manager/preview and current process scan. |

These results establish the correction locally and on the installed emulator.
They do not claim live public-page verification, physical-device/iOS/API 36
testing or Production acceptance.

### Corrective release

- Fresh remote fetch before commit confirmed `origin/main = bcd7153` unchanged;
  the feature was 0 commits behind and 3 ahead. Only the 12 corrective files
  were committed; untracked `artifacts/` and the dirty root checkout were preserved.
- Pushed `55d2c8eaf29f5261e5651d8cf62304e7cce6eb99` to
  `origin/codex/pinterest-mobile-ui`. No merge into `main` was performed.
- [CI run 37490488828](https://github.com/NOI56/PostDeeMobile/actions/runs/37490488828)
  completed successfully on this exact SHA, both Backend API and Flutter Mobile.
  It includes the full suites, API build/schema/audit and mobile analysis.
- [Render deploy `dep-db2hgs0ae00c73acmvpg`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db2hgs0ae00c73acmvpg)
  shows `Deploy succeeded | Live`, source `55d2c8e`, duration 1m59s. Logs confirm
  checkout of the full target SHA and service Live at 22:51:03 Asia/Bangkok on
  6 October 2026. Database `postdee_staging` has 14 existing migrations and no
  pending migration; startup listens on port 10000 and retains memory scheduling
  and disabled social publisher settings. There is no schema change.
- Auto-Deploy remains disabled from the earlier specific-commit deployment;
  linked branch is still `main`. No plan, secrets/env, Production release or
  customer profile data was changed.
- Public Staging browser access remains blocked by saved permissions. No browser,
  HTTP or other alternate path was used to bypass it; Live status/startup are
  verified in Render, while page/logo rendering evidence comes from the compiled
  local renderer and the installed native app.

Corrective release evidence in the same visualization folder:
`platform-logo-transparent-github-ci.json`,
`platform-logo-transparent-staging-deploy-snapshot.txt` and
`platform-logo-transparent-staging-deploy-live.png`.

## Follow-up: balance the visible size of all seven marks

The user requested balanced logo sizes for every known platform on the public
page and in the mobile app. Equal 40 x 40 image widgets fit each entire source
canvas, including transparent margins. That makes YouTube's visible mark about
26px wide while several app-icon canvases occupy the full 40px slot. The earlier
transparent-background correction and its release evidence above remain intact.

Fresh baseline for this follow-up is `965c7ef` on the same canonical worktree and
`codex/pinterest-mobile-ui`; freshly verified `origin/main` remains `bcd7153`,
with zero commits behind and five ahead. Existing untracked `artifacts/` and the
unrelated dirty root checkout are preserved. This is display geometry, with no
product/package/API payload, schema, migration, environment or dependency change.

Keep a transparent 40 x 40 slot for every known mark. Use explicit, trusted source
bounds to fit the visible artwork's longest side to 40 and center it with one
uniform scale. Do not stretch axes independently, tint artwork, add a white
badge, alter PNG bytes or crop visible colored/white content. A larger source
image element can extend outside its slot only through transparent canvas
margins. Full-canvas app icons retain their original appearance. Generic-link
fallback styling and the accessible link title remain unchanged.

| Mark | Source canvas | Visible source bounds `(x, y, width, height)` | Visible extent in the 40-slot |
| --- | --- | --- | --- |
| YouTube | 1255 x 1075 | `(214, 248, 827, 579)` | 40 x 28.00484 |
| Shopee | 96 x 96 | `(5, 0, 86, 96)` | 35.83333 x 40 |
| Lazada | 128 x 128 | Full canvas | 40 x 40 |
| LINE | 1001 x 1000 | Full canvas | Approximately 40 x 40, preserving the source aspect ratio |
| TikTok | 240 x 240 | Full canvas | 40 x 40 |
| Instagram | 240 x 240 | Full canvas | 40 x 40 |
| Facebook | 240 x 240 | Full canvas | 40 x 40 |

YouTube's source image renders at approximately 60.7013 x 51.9952, with offset
`left: -10.350665`, `top: -5.99758`, so its actual mark fills the width without
discarding any artwork. Shopee remains a centered 40-square source image, because
its longest visible side already fills the height. LINE remains in the 40px
display slot without deliberately reducing its size or modifying its artwork;
its official mobile minimum-size guidance remains in the asset README. The
filled backgrounds inside Lazada/LINE/TikTok/Instagram/Facebook are original
artwork and are retained. All seven API/mobile assets and their SHA-256 values
are unchanged.

Use equivalent bounds/centering rules in the public renderer and the shared
Flutter logo widget so manager cards and previews match. The filename allowlist,
same-origin CSP, one-day image cache, existing YouTube `?v=2` URL and all other
public asset URLs remain unchanged. Published profiles need no republishing
after the API rendering update.

### Size-normalization verification

Regression tests were added before the geometry change. The old YouTube display
failed the visible-size expectation at 26.5 rather than 40. Pixel checks now
cover all seven marks: the longest visible dimension is 40, the artwork is
centered, its original aspect ratio is preserved and no visible content is
cropped. All seven original PNG files and their API/mobile parity remain intact.

- API targeted suites pass 133/133; the complete suite passes 1,196/1,196 across
  97 files. Build, Prisma validation, helper type-check and logo-test type-check
  pass.
- Mobile targeted suites pass 28/28; the complete suite passes 1,159/1,159.
  Flutter analyze reports no issues, and the exact Staging debug APK builds
  successfully with the existing verified environment/package configuration.
- Seven compiled local-browser QA checks pass at both desktop and mobile sizes.
  Rendering of all seven marks was visually inspected. These checks establish
  the updated visible-size geometry locally, separately from the prior releases.

The exact APK was installed on the same simulator with `adb install -r`,
retaining app data and the account. Installed APK SHA-256:

`71D445BA5692FC09CC0608A4178E6A863EE7BEB68051CF7F51335BD84B4303F6`.

Native manager and preview checks use the existing two-link YouTube/Shopee
profile; no seven-link fixture was added to customer data. SharedPreferences
before and after retain SHA-256
`17ce723edcece60378f0769ef76d7e895aa55945bdf21ae52fcf7d727bd62cc9`.
Coverage of every known mark comes from pixel/widget and local-browser checks,
while the native check confirms the actual two-link account flow.

Evidence uses the `platform-logo-balanced-*` prefix in the same visualization
folder:

| Evidence | Result |
| --- | --- |
| `platform-logo-balanced-api-red.log`, `platform-logo-balanced-mobile-red.log` | Before-fix regression evidence. |
| `platform-logo-balanced-api-full.log`, `platform-logo-balanced-api-build.log`, `platform-logo-balanced-api-prisma.log` | Complete API suite, build and schema validation pass. |
| `platform-logo-balanced-mobile-targeted.log`, `platform-logo-balanced-mobile-full.log`, `platform-logo-balanced-mobile-analyze.log`, `platform-logo-balanced-mobile-build.log` | Targeted/full Flutter suites, analysis and exact Staging build pass. |
| `platform-logo-balanced-browser-result.json`, `platform-logo-balanced-web-all-desktop.png`, `platform-logo-balanced-web-all-mobile.png` | Seven browser QA checks and inspected full-platform rendering. |
| `platform-logo-balanced-native-manager.png`, `platform-logo-balanced-native-preview.png` | Existing two-link native manager and preview evidence. |

Push, CI and Staging deployment for this size-normalization follow-up are
completed as recorded below. Public Staging browser access is still blocked by saved permissions;
the live public page and assets have not been confirmed, and no alternate access
path was used. Release status/startup were verified through Render Dashboard.
Physical devices, iOS, API 36 and Production remain outside these checks.

### Size-normalization release

- Pushed implementation commit
  `b40bd74ddb08698efd78b60a585a408d8f6f6c01` to
  `origin/codex/pinterest-mobile-ui`. No merge into `main` was performed.
- [CI run 37493802956](https://github.com/NOI56/PostDeeMobile/actions/runs/37493802956)
  completed successfully for both Backend API and Flutter Mobile on that exact
  head SHA.
- [Render deploy `dep-db2hs0qd0e5s738bgd50`](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db2hs0qd0e5s738bgd50)
  on service `srv-d9bb72ojs32c739osa5g` shows `Deploy succeeded | Live` for the
  full implementation SHA above. It started at 23:12:51 and became Live at
  23:14:44 Asia/Bangkok on 6 October 2026, duration 1m53s. Startup confirms
  `postdee_staging` has 14 existing migrations and no pending migration, listens
  on port 10000, and retains the memory scheduler with
  `mode=disabled; publisher=disabled`.
- Auto-Deploy remains Off, with `main` still linked. No new migration,
  dependency, environment value or customer profile data was changed.
- Public Staging page/asset access remains blocked by saved browser permissions.
  Render Live and startup evidence confirm deployment; rendering and asset
  behavior remain verified locally and in the installed app, not through a live
  public-page browser check. No alternate access path was used to bypass the
  block.

Release evidence in the same visualization folder:
`platform-logo-balanced-github-ci.json`,
`platform-logo-balanced-staging-deploy-snapshot.txt` and
`platform-logo-balanced-staging-deploy-live.png`.
