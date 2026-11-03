# Second 3D storefront set — 2026-11-02

## Scope and baseline

The owner asked for ten more 3D store-link designs that do not look like the
first ten (clay, layered paper and frosted glass on centered podium art). Work
starts from freshly fetched `origin/main` `353cb011` on
`claude/store-3d-themes-ten-more` in an isolated worktree, and was rebased
onto `f658f908` (caption quality work) before review; only the dated top
sections of the four root docs overlapped, and both were kept. The root
checkout's uncommitted work was not touched. Package rights stay unchanged; published
pages remain public.

## Designs

| Template ID | Thai / English name | Layout | Material, light, colour |
| --- | --- | --- | --- |
| `dimensional-chrome-night` | โครมยามค่ำ / Night chrome | `showcase`, left | mirror chrome, twisted column, navy studio softboxes |
| `dimensional-lowpoly-dawn` | ภูเขาโลว์โพลี / Low-poly dawn | `showcase`, centered | faceted peaks and pines, still lake, peach-lilac dawn |
| `dimensional-zen-garden` | สวนหินเซน / Zen garden | `showcase`, left | raked sand rings, basalt stones, moss, low morning sun |
| `dimensional-wood-blocks` | บล็อกไม้ของเล่น / Wooden toy blocks | `split-art` | maple grain and painted blocks, warm sun |
| `dimensional-parcel-stack` | กองกล่องพัสดุ / Parcel stack | `split-art` | kraft boxes, paper tape, blank label, cool daylight |
| `dimensional-ceramic-tiles` | กระเบื้องเคลือบ / Glazed tiles | `tile-grid` | glossy cobalt/white glaze, isometric |
| `dimensional-pop-shapes` | ทรงป๊อปสีสด / Pop shapes | `tile-grid` | glossy toy plastic in candy colours |
| `dimensional-neon-sign` | นีออนยามค่ำ / Neon night | `neon` | emissive tubes on dark brick, polished floor |
| `dimensional-concrete-slab` | คอนกรีตเปลือย / Raw concrete | `slab` | cast slabs with tie holes, hard sun, signal orange |
| `dimensional-terrazzo-steps` | บันไดเทอราซโซ / Terrazzo steps | `slab` | terrazzo chips, terracotta and olive, warm low sun |

Layouts: `showcase` is a full-bleed cropped banner with the avatar overlapping
its edge; `neon` is an inset glowing banner; `split-art` puts transparent
object art beside the avatar; `tile-grid` puts art above a side-by-side avatar
and name and pairs links as tiles (a lone last tile fills its row); `slab`
puts the name first and the art as a shelf above the links. Each scene has its
own link material (chrome edge, soft card, outline, block extrusion, label,
glazed ledge, pop outline, neon glow, slab, terrazzo ledge). The seller's real
name, logo, description, links and colours are always native content; a custom
cover replaces the art.

Artwork is rendered from code in `scripts/3d-storefront-art/` (WebGL ray
marching with procedural materials; no AI images, photos or third-party
assets). The ten PNGs (7.7 MB total) are byte-identical in API
`assets/profile-decorations/` and Mobile `assets/images/profile_decorations/`.
Opaque banners are 1600×800; transparent art is 1200×960, 1600×900 or
1600×800.

## Catalog and compatibility

`shared/profile-templates.json` is version 3. The new entries carry
`"since": 3`; the first 110 entries are byte-identical (hash asserted by the
generator test). The API maps each template to its release (classic 1, first
3D set 2, marked entries their marker) and reads `X-PostDee-Profile-Catalog`
as an exact release number. Clients only see template IDs from their release
or earlier; other IDs serialize as `templateId: null` with the same editable
appearance. Storage and the public page keep the real design. A
null-template `minimal` snapshot from a client that cannot see the saved
template is an exact replay (styling preserved) or
`409 LINK_IN_BIO_APPEARANCE_CONFLICT`. Catalog 2 apps can still switch to a
first-set design or a classic one explicitly.

**Delivery order: API before Mobile.** The current Staging API compares the
header with `2` exactly, so a catalog 3 app talking to it is treated as a
legacy client and cannot save the new IDs. No Prisma change, migration,
entitlement or environment flag. A rollback must keep a catalog 3 reader once
a new design has been saved; never clear stored designs.

## Verification

- [x] Generator: 26 tests and `--check` pass; both generated catalogs match.
- [x] API link-in-bio suites pass, including tiered GET/POST/DELETE
  compatibility, exact replay, conflict, explicit first-set selection, scene
  layout CSS, tile pairing, outline fills, cover/colour overrides and PNG
  parity for all 20 3D images. API build passes.
- [x] Mobile: `flutter analyze` reports no issues; targeted 3D/catalog/picker/
  readability/API-client tests (291) pass, including the new layouts at 320px
  with text scale 1.6, long Thai names, light/dark app themes, cover
  replacement and owner colours.
- [x] Local public pages for all ten scenes at 320px and desktop: art loads,
  no horizontal overflow, readable long Thai name and links.
- [x] Full API suite: 3,305 passed / 67 opt-in skipped; five cases in four
  unrelated files timed out while the Mobile suite ran alongside, and all four
  files pass when rerun alone (881 cases with the link-in-bio suites).
- [x] Full Mobile suite: 4,622 passed / 7 skipped; its one failure was a stale
  `110` catalog-size assertion, updated to 120 and passing on rerun.
- [x] Native preview widgets for all ten scenes were exported with bundled
  fonts and artwork and match the public pages.
- [x] Android x64 Staging debug APK 12093 built with the guarded helper
  (SHA-256 `be16102f29f6035927eb2436a1a9a1ea6b54e9b4caf0c3f3a4a0de12c5c6c789`)
  and installed on `emulator-5554` with the shared updater; installed hash
  matches, package UID 10197 and app data preserved, previous build was 12090
  (`d9a60b83…`). The app starts natively with the STAGING strip.
- [ ] Signed-in device walkthrough: the app opened on the sign-in screen
  (no session restore after a cold start) and two Google accounts exist on the
  emulator, so no account was chosen. The owner signs in, then the 3D picker
  and previews can be captured on device.
- [ ] Saving or publishing a new design against Staging needs this API
  deployed first (owner authorization). Production untouched.
