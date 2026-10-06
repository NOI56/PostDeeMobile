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
| `shopee.png` | [Shopee Thailand](https://shopee.co.th/) links to the [official 96px favicon](https://deo.shopeemobile.com/shopee/shopee-pcmall-live-sg/assets/icon_favicon_1_96.1ce0e05fc18a86e5.png) | Original 96×96px PNG bytes, unchanged. |
| `line.png` | [LINE logo guidelines](https://www.line.me/en/logo), [official iOS app icon PNG archive](https://www.line.me/static/logo/top/LINE_APP_iOS.zip), file `LINE_APP_iOS.png` | Original 1001×1000px PNG bytes, unchanged. |
| `lazada.png` | [Lazada Thailand](https://www.lazada.co.th/), [official favicon](https://www.lazada.co.th/favicon.ico) | Original 128×128px ICO frame decoded losslessly to PNG. Same pixels and dimensions. |
| `youtube.png`, `instagram.png`, `facebook.png`, `tiktok.png` | Existing, visually verified mobile assets | Copied unchanged. Original retrieval provenance is not recorded by this task. |

Brand and trademark rights remain with their respective owners. Retain the
original aspect ratio and colors. The LINE guidelines specify a minimum height
of 40px for mobile use and 20px for PC use; its mark must not be recolored or
decorated.

## Byte parity

SHA-256 values for both the API copy and the mobile file:

| File | SHA-256 |
| --- | --- |
| `youtube.png` | `999C4D52F380D1C1DE8E29C32269A465D933121D3F3675BC660D5A34AEAB2A6C` |
| `instagram.png` | `2604BD33F5E75ECD2CA39599D4AEF92ED0F5072A5BC39A7CF79635DDA74B9FFF` |
| `facebook.png` | `7ED849718CC5C019FA76AE2CA29ED0119E6BA7BFA92727C768C5CE36388BFEE1` |
| `tiktok.png` | `D08E3ACC4B31BFCCA4C67031EBFC6C78E22B27DB3E6601F261D905AF6A8DF568` |
| `shopee.png` | `26B67120CBDF3123FE70F747D42BA6ADEEDC59CDF9C66085AFA0343930EF0897` |
| `line.png` | `5E93437EB5EC0DCDECE92D1562FCD435D1D521CCA5C013D2D9E15B544A1D8A39` |
| `lazada.png` | `9B2AF701CB4F10425AEAECF9175CCE3E74D7655FFDEAD15149A9A2ECC81B3CB2` |

Serve these local copies. Do not hotlink vendor assets at request time or fetch
arbitrary user URL favicons; the latter would introduce server-side fetching and
tracking risks unrelated to displaying these known platform marks.
