# Global profile-link platform logos — 2026-10-07

## User request and outcome

The user asked to find popular app logos from other countries and expand the
profile-link catalogue to 100 logos. The intended result is **100 brand logos
in total**, counting the ten existing brands and 90 new destination identities.
The automatic, generic link, website, email and telephone values do not count
as brands. This is a curated selection across regions, not a statistical world
popularity ranking.

Mobile uses a searchable logo picker for platform names, aliases and country
associations. Recognized URLs suggest the platform display name only if the user
has left the title empty. Public pages and Mobile use identical bundled marks
and audited 40 x 40 visible-bound slots. Original proportions, colors, app-icon
backgrounds and visible white artwork remain intact; no extra white badge is
added by the product.

## Verified starting baseline

- Canonical checkout: `D:/PostDeeMobile/.worktrees/recover-main-systems`.
- Working branch: `codex/pinterest-mobile-ui`.
- Starting HEAD: `355ed52d780b46b27bef0151539ad6f8a3e84e56`.
- Verified integration reference: `origin/main` at
  `bcd7153f196cd381a786b333b9b61a67dbe95ca3`.
- Merge base: the same `bcd7153f196cd381a786b333b9b61a67dbe95ca3`.
- Starting comparison: 0 commits behind, 10 commits ahead.
- Preserve the unrelated root checkout and pre-existing untracked `artifacts/`;
  do not reset, overwrite or stage them as part of this feature.

## Scope and preserved contracts

- Keep the original ten IDs and PNG bytes: YouTube, Shopee, Lazada, LINE,
  TikTok, Instagram, Facebook, Messenger, WhatsApp and Google Maps.
- Add 90 brand IDs and PNGs; accept 105 total icon values including the five
  existing generic/automatic values.
- Serve exactly 100 fixed PNG filenames at `/profile-platforms/:file`, with
  the existing image content type, nosniff, one-day cache and self-only CSP.
- Keep explicit manual brand/generic overrides, website fallback and custom
  user-entered titles. No destination URL is fetched to suggest a name/icon.
- Retain HTTP(S) credential rejection, safe mailto/tel rules, raw contact input
  normalization, owner-scoped drafts/publication and the 20-link draft limit.
- Retain the link manager, appearance/preview/review, all package rights,
  uploaded images and existing publishing/caption/analytics flows.
- Add no third-party publishing/chat/payment/analytics API, paid logo API,
  dependency, environment flag, schema or database migration.

## Single catalogue and generation

`shared/profile-platforms.json` owns the 100 platform records: IDs/names,
categories, aliases, country associations, strict domains/path matches and
asset provenance/hash/canvas/visible bounds. Generated runtime files are:

- `apps/api/src/modules/linkInBio/profilePlatformCatalog.generated.ts`.
- `apps/mobile/lib/core/models/profile_platform_catalog.generated.dart`.

`scripts/generate-profile-platforms.mjs` generates both catalogues and checks
IDs and asset metadata. `node scripts/generate-profile-platforms.mjs --check`
verifies exact 100-ID coverage, preservation of original IDs, generated output,
SHA-256/byte parity of API/Mobile PNGs and bounds measured from PNG transparency.
The generator uses existing runtimes and does not install a new dependency.
Runtime code uses generated local data rather than external vendor-logo calls.

## Source curation and identity corrections

Use source records in the shared catalogue for exact asset URLs and preparation
methods; existing asset provenance remains in the platform asset README.
Supporting primary evidence includes:

- [Tencent Weixin/WeChat](https://www.tencent.com/products/weixin-wechat/) and
  [consumer products](https://www.tencent.com/what-we-create/for-consumers/).
  Its Q1 2026 product page reports over 1.4 billion combined Weixin/WeChat MAU.
- [NAVER service catalogue](https://www.navercorp.com/service/all).
- [Mercari's introduction](https://about.in.mercari.com/what-we-do/) and
  [Japanese marketplace](https://jp.mercari.com/).
- [Carousell Group](https://press.carousell.com/carousell-group/), which
  documents its regional services and tens of millions of users.
- [ByteDance](https://www.bytedance.com/?lang=en) and its
  [official service centre](https://kefu-lf.bytedance.com/) for Douyin.
- [Kuaishou material library](https://www.kuaishou.com/official/material-lib).
- [Alibaba business descriptions](https://www.alibabagroup.com/en-US/about-alibaba-businesses-1894256634985709568)
  for Ele.me's December 2025 rebrand to Taobao Instant Commerce.
- [Gojek logo announcement](https://www.gojek.com/blog/gojek/logo-baru-Gojek-simbol-evolusi)
  and [Trip.com's app page](https://www.trip.com/pages/appdownload).

For inaccessible vendor CDNs or misleading favicons, use exact-publisher
primary app-store artwork and record the verified title/seller/bundle/source.
Do not choose a similarly named third-party application. Source originals retain
their legitimate app-icon background; source conversion does not add a white
badge or erase brand details.

Corrections made during research avoid false identities:

- WeChat uses its two-bubble app mark, not a one-bubble site favicon.
- Bilibili uses its product mark, not a WEB-badged website icon.
- Mercari uses the product app icon, not a corporate black `m` favicon.
- Flipkart uses the main app mark, not a LITE icon.
- Taobao Instant Commerce uses current official artwork with stable ID `eleme`
  and Ele.me/local-language search aliases.
- Trip.com uses new ID `trip_com` and `trip.com` recognition; the distinct
  `ctrip.com` service is excluded from that identity.
- BAND uses only `band.us`; unrelated `band.com` is excluded.
- QQ uses `im.qq.com` and `qm.qq.com`, not Qzone or every Tencent `qq.com` host.
- Meituan excludes the distinct Dianping identity; unverified `alipay.me` and
  `dingtalk.jp` domains are omitted.

Brand and trademark rights remain with their owners. Source publication is
provenance, not a claim of CC0 rights or platform partnership. Retain original
colors/geometry/content and follow source terms/attribution requirements.
These marks identify outbound destinations only.

## Files in scope

Implementation includes the shared catalogue/generator, generated TS/Dart,
API appearance/destination/logo handling, Mobile appearance/defaults/logo
widget/picker/screen and their regression tests, and the 90 PNG additions in
each of `apps/api/assets/profile-platforms` and
`apps/mobile/assets/images/platforms`.

Synchronize `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`, the platform
asset README and this plan. Dated tests/releases in earlier plans remain
historical evidence and do not verify the new 100-logo expansion.

## Validation status

Local integration checks passed on the implementation below. The 43 Asia assets
and search metadata were reviewed separately during source preparation; the
runtime checks cover all 100 brands, including the 47 other additions and ten
preserved originals. Remote delivery and CI remain separate pending checks.

| Check | Status / evidence |
| --- | --- |
| Regression tests first | Ten API expansion regressions failed before implementation; final targeted/full suites pass (`global-logo-api-red.log`) |
| Catalogue generation and `--check` | Passed: 100 brands, both generated catalogues, PNG bounds and API/Mobile parity |
| All 100 PNG copies/hashes/bounds and original ten byte preservation | Independent audit passed: 100 local assets, 2,436,434 bytes per collection, hashes/bounds/sample recognition match, original ten bytes unchanged |
| API targeted/full tests, build, type checks and Prisma validation | Passed: 241 catalog/contact targeted tests, then 28 generator tests and 1,328 final full tests; build, test/helper TypeScript checks and Prisma schema validation |
| Flutter targeted/full tests and analysis | Passed: 161 targeted and 1,283 full tests; analyzer reports no issues |
| Local public-page desktop/mobile visual and interaction QA | Passed: actual compiled API, 100 loaded PNGs, 18 rendered pages at 700/393/320 px; geometry, URLs, manual overrides, contact/spoof rules, keyboard and isolated logo click; no console/page/HTTP errors or outgoing vendor requests |
| Exact Staging APK build, package/environment checks | Passed: Staging debug APK built and installed with matching SHA-256; exact package, Firebase debug project and environment recorded below |
| Native Android emulator picker/autotitle/preview smoke and data preservation | Passed: Zalo URL suggests title, searchable picker and preview show real new mark alongside existing Shopee; existing authenticated account and preference hash unchanged |
| Baseline diff/no unexpected deletion or lost wiring | Parent review passed for related changes; refreshed main comparison remains 0 behind / 10 ahead before delivery |
| Remote CI on delivered source SHA | Pending |
| Push and Staging API release | Pending |

Evidence is saved outside the checkout under
`C:/Users/stopp/.codex/visualizations/2026/10/04/01a105f6-2943-7ae3-9df1-447070022cb2`:

- API logs: `global-logo-api-{red,targeted,full,build,test-types,helper-types,prisma}.log`;
  generation/audit: `global-logo-generator-check.log`, `global-logo-100-audit.json`.
- Mobile logs: `global-logo-mobile-{targeted,full,analyze,build}.log`.
- Browser: `global-logo-browser-result.json`, fixture data and screenshots
  `global-logo-web-global-logos-{1..5}-{desktop,mobile-393,mobile-320}.png`,
  `global-logo-web-global-safety-*` and `global-logo-web-keyboard-focus.png`.
- Native: `global-logo-native-{before,installed,after}.json`,
  `global-logo-native-picker-search.png` and `global-logo-native-preview.png`.

Browser QA used existing bundled Playwright 1.62.1/Chromium 1223 because the
Browser plugin was unavailable. A local-only memory fixture on port 4797
published five profiles through the real compiled publication route, twenty
brands each, plus one contact/override/spoof profile. A 21-link request was
rejected without altering the saved fixture. All 100 image responses matched
the API and Mobile copies; visible bounds occupy the centered 40 px slots with
original proportions/colors and no product-added white wrapper. CSS geometry
assertions allow 0.025 px for Chromium's fractional layout rounding. All five
brand groups and the safety page were also visually inspected from screenshots.
The Messenger logo click opened the exact href with null `window.opener`; its
response was fulfilled locally, with no request to Messenger. Email/telephone
were tested for hit targets without launching a mail or call handler.

Native verification used package `com.postdee.postdee_mobile.staging`. Debug
Firebase configuration is `project-798caf7e-85b8-45e3-af7` from
`android/app/src/debug/google-services.json`; the root Production Firebase file
was not used by that build. Flags: Staging API origin, Firebase auth true,
mock auth false, RevenueCat false and both experimental feature flags false.
Installed/build APK SHA-256:
`c260c3f290075434d2933e68afb11958939883e56fa7ea50ea87f681320790df`.
Shared preferences SHA-256 before install, after install and after discarding
the unsaved smoke draft remained
`3a3c91d727b12ad8a14b0ce7cbb6425264083e38b586bc69827f7705a6546235`.
The existing authenticated account and connected-account count stayed intact;
the test did not publish or persist a remote customer profile.

## Delivery order and remaining limits

No database migration is required by this expansion. Deploy the API/generated
catalogue and 100 local assets before distributing the new Mobile build;
otherwise older APIs reject new icon IDs during publication. Existing clients,
profiles, safe contacts and original icon values remain compatible. Existing
published pages use the updated bundled marks without republishing.

The intended Mobile test environment is the existing Staging build with its
configured Staging API origin and Firebase project. Preserve account/profile
data; do not uninstall or clear preferences for verification. Record actual
build flags, package, APK hash and preserved data evidence after checks run.
Do not treat in-memory local fixtures as remote Staging or Production evidence.

The earlier saved browser restriction on the public Staging domain remains a
separate limit unless actually changed. Do not substitute another network path
to bypass it or claim live public-page appearance from local fixture evidence.
Record deployment state separately from live-browser rendering. Physical iOS
and Android acceptance and app-specific login/region restrictions are not
proven by an Android emulator or by seeing a logo.

No push, merge or deploy has been performed by this documentation subtask.
The parent task must record actual authorized delivery and validation evidence
before declaring this expansion complete.
