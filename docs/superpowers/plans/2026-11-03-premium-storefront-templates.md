# Premium storefront category — 2026-11-03

## Scope and baseline

The owner asked for twenty Luxury / Premium store-link designs. A first local
candidate (Codex, same day) only exposed the catalog's existing classic
`luxury-*` set: those twenty reuse the generic page compositions with dark
colours, have no artwork of their own and one is plain white. The owner judged
them not beautiful and asked for the category to be redone.

Work continues on `codex/store-premium-themes` in the root checkout, based on
freshly fetched `origin/main` `9c05fa8e`. The first candidate's uncommitted diff
was backed up before it was replaced. Unrelated dirty files (Windows generated
plugin files, scratch folders) are left untouched.

## Decision

Add a new category, `premium`, with twenty new `premium-*` designs drawn and
laid out like the 3D and Cartoon releases, instead of restyling the classic
`luxury` entries. The classic entries stay byte-identical so saved pages and
older apps keep working; the picker shows the new set under the same label,
**หรูหรา / พรีเมียม (Luxury / Premium)**, and no longer lists the classic one.
A store that saved a classic luxury design keeps it; the picker opens on Simple
for it, as it already does for the hidden Cute, Nature and Creative designs.

## Designs

Five premium layouts: `crest` (full-width picture fading into the page, avatar
on its lower edge, diamond ornament under the name), `cameo` (avatar in the
middle of the picture), `portal` (picture seen through an arched window, avatar
on the sill), `atelier` (full-width picture, avatar and name on the left, short
rule) and `vitrine` (framed picture, avatar beside the name like a label).
Link finishes: polished plate with a sheen, gilded double rule, cut Art Deco
corners, open rows over a fine rule, stitched thread, and soft pearl glow.

| Template ID | Thai / English name | Layout | Picture and links |
| --- | --- | --- | --- |
| `premium-gold-leaf` | ทองคำเปลว / Gold leaf | crest | beaten-gold flakes drifting across black lacquer; gold plates |
| `premium-white-marble` | หินอ่อนขาว / White marble | portal | grey-veined white marble with one gold vein; charcoal gilded links |
| `premium-thai-gold` | ลายไทยทอง / Thai gold pattern | crest | prajam yam lattice between kranok borders on deep red; gilded links |
| `premium-art-deco` | อาร์ตเดโค / Art Deco | cameo | sunburst halo, stepped fans and fluted lines; notched gold plates |
| `premium-emerald-facet` | มรกตเจียระไน / Cut emerald | vitrine | step-cut emerald in a gold setting; gilded emerald links |
| `premium-pearl-strand` | สร้อยไข่มุก / Pearl strands | portal | pearl strands over blush satin; pearl-white pill links |
| `premium-velvet-wine` | กำมะหยี่ไวน์ / Wine velvet | atelier | velvet folds and a twisted gold cord; stitched links |
| `premium-champagne` | ฟองแชมเปญ / Champagne bubbles | cameo | rising bubbles and bokeh round a gold halo; champagne plates |
| `premium-guilloche` | ลายเส้นกิโยเช / Guilloche engraving | cameo | engraved silver rosette and wave bands; silver gilded outlines |
| `premium-rose-gold` | โรสโกลด์ / Rose gold | vitrine | brushed rose-gold half disc and fine rings; rose plates |
| `premium-midnight-stars` | ราตรีประดับดาว / Midnight stars | cameo | orbit rings, crescent moon, invented constellations; open rows |
| `premium-black-onyx` | นิลดำสายทอง / Gold-veined onyx | atelier | dark stone with gold-filled seams; open rows |
| `premium-silk-ribbon` | ริบบิ้นผ้าไหม / Silk ribbon | portal | two satin ribbons turning as they fall; champagne plates |
| `premium-crystal` | คริสตัล / Crystal | vitrine | clear quartz points and a thin rainbow; pearl links |
| `premium-damask` | ลายดามัสก์ / Damask | crest | ogee lattice with tone-on-tone fleurons on navy; champagne plates |
| `premium-golden-palms` | ใบปาล์มทอง / Golden palms | atelier | gold line palm fronds on deep green; gilded pill outlines |
| `premium-spotlight` | แสงสปอตไลต์ / Spotlight | cameo | warm beams on an empty pedestal, gold dust; gilded links |
| `premium-colonnade` | ทางเดินซุ้มโค้ง / Colonnade | portal | receding arches over a chequered floor; open rows |
| `premium-leather-stitch` | หนังเย็บมือ / Hand-stitched leather | atelier | pebbled cognac leather, saddle stitches, gold buckle; stitched links |
| `premium-sapphire-wave` | คลื่นไพลิน / Sapphire waves | vitrine | overlapping silver-lined wave scales; notched silver plates |

Every page shows the seller's real name, description, logo, links and colours
as native content; a custom cover replaces the picture. Default text keeps at
least 4.5:1 contrast on the page, panel and links (generator and API tests).

## Originality and licences

- All twenty pictures are SVG written as code in `scripts/premium-storefront-art/`
  (`paint.mjs` materials, `scenes.mjs` pictures) and rendered to PNG locally by
  `render.mjs` with headless Edge. No stock art, photos, traced images, icon
  packs, AI-generated images or downloaded assets. Licence: original PostDee
  work in this repository. `scenes.test.mjs` fails on text, fonts, images,
  `<use>`, scripts, external URLs or `href`, and checks API/Mobile PNG parity.
- Patterns are public traditional forms drawn from geometry here: Thai prajam
  yam and kranok borders, guilloche rosettes, damask scrolls on an ogee
  lattice, Art Deco fans and overlapping wave scales.
- Avoided on purpose: repeated monogram canvases, quilted black-and-gold
  leather, robin's-egg blue boxes with white ribbon, signature orange, and any
  logo, crest or lettering. No new fonts; pages use the bundled Prompt.

## Catalog, API and app

- `shared/profile-templates.json` is version 5: category `premium` and twenty
  `premium-*` entries with `"since": 5` are appended; the first 140 entries are
  byte-identical to catalog 4 (hash asserted). The generator accepts five
  premium-only compositions and release marker 5 for premium only.
- API: `linkInBioPremiumStyles.ts` holds the geometry table and the five
  layouts; the renderer adds `data-template-category="premium"` and a
  `profile-premium-hero` with the catalog PNG (or the owner's cover), wrapped
  in an arch or a frame for portal and vitrine. `/profile-decorations/` serves
  the twenty PNGs from the catalog-derived allowlist.
- Compatibility: `X-PostDee-Profile-Catalog: 5` sees every template; `4`, `3`,
  `2` and older or unknown values (now including `6`) receive `templateId:
  null` with the same editable appearance for premium designs. Storage and
  `/p/:slug` keep the real design; an old app's exact fallback replay is kept
  and an edited one is `409 LINK_IN_BIO_APPEARANCE_CONFLICT`, as before.
- Membership: unchanged. Every non-Simple category, premium included, needs
  an active purchased Starter, Pro or Business plan to apply or publish.
- Mobile: `link_in_bio_premium_scenes.dart` (`BioPremiumHeader`, panel, frame,
  link finishes and the ornament) mirrors the public CSS. The picker shows
  Simple, 3D, Cartoon and หรูหรา / พรีเมียม; thumbnails use no invented store
  name. Mobile sends catalog `5`.

**Delivery order: API before Mobile.** An older API rejects the new IDs and
treats header `5` as a classic-only client. No Prisma change, migration,
entitlement or environment flag. Once a premium design is saved, a rollback
must keep a catalog-5 reader; never clear stored designs.

## Verification

- [x] Generator: 30 tests and `--check` pass (8 categories, 160 templates).
  Premium art guard: 61 tests pass; cartoon art guard still 61.
- [x] API link-in-bio suites, including the new premium rendering file and
  per-release compatibility for catalogs 1–6.
- [x] Mobile: `flutter analyze` reports no issues; targeted link-in-bio tests
  pass, including 46 new premium widget tests (320 px at text scale 1.6, long
  Thai names, cover replacement, owner colours, English names in light and
  dark) and the updated picker tests.
- [x] Visual QA: all twenty public pages rendered by the real renderer at
  390 px and all twenty native previews exported from the real widgets were
  compared side by side (local evidence only, not checked in).
- [x] Full Mobile suite (Flutter 3.44.1, two workers): 5,119 passed, 10
  optional screenshot-output fixtures skipped, no failures (13m 17s).
- [x] Full API: typecheck, build and `prisma validate` pass; 3,694 passed / 77
  opt-in skipped, with 5 cases in 2 unrelated files (Sentry fatal process,
  platform-logo catalog) timing out under full-suite load; both files pass
  alone (24/24) and are unchanged by this work.
- [ ] Staging API deploy, APK install and owner review on a device. No merge,
  push, deploy or Production change has been made.
