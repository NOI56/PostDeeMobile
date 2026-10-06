# Profile platform marks

These local PNGs are the same bytes as the corresponding files in
`apps/mobile/assets/images/platforms/`. The public profile page and the mobile
profile manager use the same full-color marks instead of generic letters or
play/shop/chat symbols. They are identification marks for outbound destinations;
they do not indicate a platform partnership or a publishing integration.

## Sources

Retrieved and visually checked on 2026-10-06:

| Asset | Original source | Preparation |
| --- | --- | --- |
| `youtube.png` | [YouTube icon guidelines](https://brand.youtube/youtube-icon/), [official icon archive](https://www.gstatic.com/marketing-cms/89/d9/cf95c4f345709f4998dc581221b0/youtube-icon.zip), file `YouTube_Icon/Digital/01 Red/yt_icon_red_digital.png` | Original 1255×1075px transparent PNG bytes, unchanged. The white play triangle is part of the original mark. |
| `shopee.png` | [Shopee Thailand](https://shopee.co.th/) links to the [official 96px favicon](https://deo.shopeemobile.com/shopee/shopee-pcmall-live-sg/assets/icon_favicon_1_96.1ce0e05fc18a86e5.png) | Original 96×96px PNG bytes, unchanged. |
| `line.png` | [LINE logo guidelines](https://www.line.me/en/logo), [official iOS app icon PNG archive](https://www.line.me/static/logo/top/LINE_APP_iOS.zip), file `LINE_APP_iOS.png` | Original 1001×1000px PNG bytes, unchanged. |
| `lazada.png` | [Lazada Thailand](https://www.lazada.co.th/), [official favicon](https://www.lazada.co.th/favicon.ico) | Original 128×128px ICO frame decoded losslessly to PNG. Same pixels and dimensions. |
| `messenger.png` | [Messenger](https://www.messenger.com/) declares the [official favicon](https://static.xx.fbcdn.net/rsrc.php/yO/r/qa11ER6rke_.ico) in its HTML | Original highest-resolution 128×128px RGBA ICO frame decoded losslessly to PNG. Same pixels and dimensions. |
| `whatsapp.png` | [WhatsApp](https://www.whatsapp.com/) declares the [official SVG favicon](https://static.whatsapp.net/rsrc.php/y1/r/FJbTMJqMap7.svg) in its HTML | Official SVG rendered to 240×240px PNG with the existing bundled Sharp runtime. Paths, proportions and original colors retained. |
| `google_maps.png` | [Google products](https://about.google/intl/ALL/products/), [official Google Maps mark](https://www.gstatic.com/marketing-cms/assets/images/55/0e/c70d6751460a973c06968f0b64e0/logo-maps-2025-color-2x-web-96dp.webp) | Original 192×192px RGBA WebP decoded losslessly to PNG. Same pixels and dimensions. |
| `instagram.png`, `facebook.png`, `tiktok.png` | Existing, visually verified mobile assets | Copied unchanged. Original retrieval provenance is not recorded by this task. |

Brand and trademark rights remain with their respective owners. Retain the
original aspect ratio and colors. The LINE guidelines specify a minimum height
of 40px for mobile use and 20px for PC use; its mark must not be recolored or
decorated.

The transparent YouTube source replaces the former opaque white-square mobile
asset. Shopee already has a transparent background (including the letter-shaped
cutout); it does not require background removal. Display these originals without
an added white badge. White elements that belong to a brand mark remain intact.

## Byte parity

SHA-256 values for both the API copy and the mobile file:

| File | SHA-256 |
| --- | --- |
| `youtube.png` | `1027B1B0517727ADB9697155A270744381C3CE9B047B1C8BD8A9389DC7D07A83` |
| `instagram.png` | `2604BD33F5E75ECD2CA39599D4AEF92ED0F5072A5BC39A7CF79635DDA74B9FFF` |
| `facebook.png` | `7ED849718CC5C019FA76AE2CA29ED0119E6BA7BFA92727C768C5CE36388BFEE1` |
| `tiktok.png` | `D08E3ACC4B31BFCCA4C67031EBFC6C78E22B27DB3E6601F261D905AF6A8DF568` |
| `shopee.png` | `26B67120CBDF3123FE70F747D42BA6ADEEDC59CDF9C66085AFA0343930EF0897` |
| `line.png` | `5E93437EB5EC0DCDECE92D1562FCD435D1D521CCA5C013D2D9E15B544A1D8A39` |
| `lazada.png` | `9B2AF701CB4F10425AEAECF9175CCE3E74D7655FFDEAD15149A9A2ECC81B3CB2` |
| `messenger.png` | `3CDA2D1EA91B6C87BAA3B43B2ED28C9C57E434014D649F4AAA06E8A0C8B7D98E` |
| `whatsapp.png` | `1103B5DFE5420B191202C3F31B8E03EFAAF954F9E4AB117B089587ED910442DC` |
| `google_maps.png` | `ABFEF074006DEC3C9808EB9CF87EA1145107A263F71377AA17E791032A5C85C4` |

Serve these local copies. Do not hotlink vendor assets at request time or fetch
arbitrary user URL favicons; the latter would introduce server-side fetching and
tracking risks unrelated to displaying these known platform marks.

The contact expansion brings the allowlist to ten brand PNGs. The seven earlier
assets retain their exact bytes. All known marks share transparent 40×40 display
slots, with a uniform scale based on audited nontransparent bounds. For the
added assets, source bounds `(x, y, width, height)` are Messenger
`(5, 7, 117, 116)`, WhatsApp `(0, 0, 240, 240)`, and Google Maps
`(27, 8, 138, 176)`. Center visible artwork without stretching, recoloring,
adding a white badge or clipping its original colored/white content.
Website, email and phone are code-native vector icons; they require no brand
PNG and are not files served by this route. These assets identify outbound
destinations, without adding provider/API integration or connection permission.

## Global catalogue expansion — 2026-10-07

The current catalogue contains **100 brand PNGs**, comprising the ten original
marks above and 90 additions. Generic automatic/link/website/email/telephone
values are not brand images. All ten original files retain their exact bytes;
the hashes above describe those originals, not only the first seven.

The complete source record lives in `shared/profile-platforms.json` at the
repository root: each platform includes its ID, display name, aliases, country
associations, strict destination rules and asset source/preparation information,
SHA-256, canvas size and visible alpha bounds. Source and brand/terms references
document provenance; they do not declare the marks CC0 or grant a partnership.
Both API and Mobile bundle the same `<id>.png` bytes. Run
`node scripts/generate-profile-platforms.mjs --check` from the repository root
to validate the 100 IDs, generated catalogues, PNG hashes, identical copies and
source bounds. Do not manually edit generated TypeScript/Dart lists.

This is a curated regional/global selection, not the world's 100 largest apps
in rank order. Regional context uses primary company/service evidence, including
[Tencent](https://www.tencent.com/products/weixin-wechat/),
[NAVER](https://www.navercorp.com/service/all),
[Carousell](https://press.carousell.com/carousell-group/),
[Mercari](https://about.in.mercari.com/what-we-do/) and
[Alibaba](https://www.alibabagroup.com/en-US/about-alibaba-businesses-1894256634985709568).
Alibaba documents Ele.me's December 2025 rebrand; ID `eleme` uses the current
Taobao Instant Commerce mark, with Ele.me aliases retained for searching.
Trip.com uses ID `trip_com` and only `trip.com` recognition because `ctrip.com`
has a distinct mark. BAND uses `band.us`, not the unrelated `band.com`.

New sources are declared official website/service images or exact-publisher
app-store icons. ICO frames are decoded losslessly; SVGs are rasterized with
the recorded original geometry and colors; other source formats are converted
without repainting artwork. Store-supplied icons retain their original colored
or white backgrounds. For example a product app icon can intentionally contain
an opaque white field; removing it would alter the published source. No
additional white badge is placed around these originals by the renderer.

All source artwork shares the normalized transparent 40 x 40 display slots.
The source bounds fit and center the visible artwork without stretching or
cropping colored/white content. Respect each brand's terms and attribution
requirements, preserve proportions and colors, and do not imply endorsement.
Current source/preparation records for the 90 additions are in the shared
catalogue rather than a second hand-maintained source table here.
The fixed local route allowlists all 100 PNGs under the existing same-origin
CSP/cache/nosniff rules; it fetches no vendor/user URL at request time.
No paid logo API, provider integration, dependency or database migration is
required. Deploy API/catalogue/assets before distributing the new Mobile
build because older APIs reject the new icon IDs. Verification and release
status are tracked in
`docs/superpowers/plans/2026-10-07-global-profile-platform-logos.md`.
