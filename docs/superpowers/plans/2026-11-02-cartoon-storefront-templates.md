# Cartoon storefront category — 2026-11-02

## Scope and baseline

The owner asked for a new store-link category, **การ์ตูน / Cartoon**, with an
explicit copyright requirement. Ten concepts were proposed in Thai and approved
by the owner before any building started. Package rights stay unchanged; there
is no paid-only theme gate and published pages remain public.

Work is on `claude/store-cartoon-themes` in the worktree
`.worktrees/store-cartoon-themes`, based on PR #51
(`claude/store-3d-themes-ten-more`, `99e945b4`), which itself contains
`origin/main` `f658f908`. PR #51 was chosen over plain `main` because it adds
the per-release catalog negotiation (`since` markers and an exact release
header) that a new category needs; basing on `main` would have duplicated and
conflicted with that work. **This branch must merge after PR #51.** A separate
"by store type" category is being built in parallel; whichever of the two
merges second renumbers its catalog release (for example 4 to 5).

## Designs

Ten templates on five cartoon layouts. Every page shows the seller's real
name, description, logo, links and colours as native content; a custom cover
replaces the drawing. Artwork contains no text.

| Template ID | Thai / English name | Layout | Drawing and links |
| --- | --- | --- | --- |
| `cartoon-doodle-shop` | ร้านวาดมือ / Doodle shop | `banner` | ink doodles and highlighter on cream paper; hand-drawn (elliptical-corner) links with an offset sketch line |
| `cartoon-comic-panels` | ช่องการ์ตูน / Comic panels | `panels` | three slanted halftone panels with a wordless burst; avatar panel and caption box; panel links with fills that take turns |
| `cartoon-tag-buddy` | เจ้าป้ายจิ๋ว / Little tag buddy | `beside` | the one mascot, a waving hang tag designed here; soft links with a colour stripe |
| `cartoon-sticker-sheet` | แผ่นสติกเกอร์ / Sticker sheet | `banner` | die-cut stickers with white edges; white-edged links with a still alternating tilt |
| `cartoon-chalkboard` | กระดานชอล์ก / Chalkboard | `banner` | chalk flourishes, blank ribbon and ray burst in a wooden frame; dashed chalk outlines (dark) |
| `cartoon-street-front` | หน้าร้านริมทาง / Street shopfront | `signboard` | striped awning, window and door; the seller's logo hangs as the shop sign; awning-striped links |
| `cartoon-chat-bubbles` | บับเบิลคุยกัน / Chat bubbles | `chat` | empty speech bubbles; the name in a bubble; links as alternating bubbles with tails |
| `cartoon-signposts` | ป้ายบอกทาง / Signposts | `beside` | blank wooden signposts on grass; arrow-shaped wooden links |
| `cartoon-crayon-sky` | สีเทียนท้องฟ้า / Crayon sky | `banner` | crayon sun (no face), clouds, hills and kite; outlines in rotating crayon colours |
| `cartoon-rocket-night` | จรวดการ์ตูน / Cartoon rocket | `banner` | rounded rocket, ringed planet and stars (dark); capsule links with a double ring |

The chalkboard has no menu or prices and the shopfront names no kind of shop,
so neither overlaps the "by store type" category.

## Originality and licences

The owner's rules: original work or commercially licensed sources only; no
existing or recognizable characters, franchises, studios, mascots or
brand-imitating styles; generic names.

- **Source:** all ten drawings are SVG written as code in
  `scripts/cartoon-storefront-art/` (`draw.mjs` helpers, `scenes.mjs` scenes)
  and rendered to PNG locally by `render.mjs` with headless Edge. No stock art,
  photos, traced images, icon packs, AI-generated images or downloaded assets
  are used. Licence: original PostDee work in this repository.
- **No text or fonts in art.** No new fonts were added; pages use the existing
  bundled Anuphan and Prompt. `scenes.test.mjs` fails if a scene contains
  `<text>`, fonts, `<image>`, `<use>`, scripts, external URLs or `href`, and
  checks the PNGs are byte-identical in both apps.
- **Avoided on purpose:** animal mascots (cats, bears, rabbits, dogs and similar
  read as known characters); a shopping-bag mascot (Shopee's logo is an orange
  bag), a parcel with a smile (a known retailer's mark) and a paper plane (a
  chat app's logo); faces on the sun, clouds or stickers (a children's TV sun,
  smiley trademarks); a red-and-white checked rocket (a famous comic rocket);
  halftone faces in the style of a named pop artist; convenience-store awning
  colours (orange/green/red or green/blue stripes) and chat-app greens. The
  mascot is a plain hang tag with dot eyes, designed here.
- **Names** are generic Thai/English descriptions and hint at no franchise.

## Catalog, API and app

- `shared/profile-templates.json` is version 4: category `cartoon` and ten
  `cartoon-*` entries with `"since": 4` are appended; the first 120 entries are
  byte-identical (hash asserted). The generator accepts five cartoon-only
  compositions (`banner`, `beside`, `signboard`, `panels`, `chat`), ten
  templates for the category and the release marker 4 for cartoon only.
- API: `linkInBioCartoonStyles.ts` holds the fixed geometry table, link edges,
  avatar rings and the five layouts; the renderer adds
  `data-template-category="cartoon"`, a `profile-cartoon-hero` with the
  catalog PNG (or the owner's cover) and, for the shopfront, a sign wrapper.
  Comic, sticker and chat fills take turns only while the design's default
  colours are kept and the default text stays readable. `/profile-decorations/`
  serves the ten PNGs from the catalog-derived allowlist.
- Compatibility: `X-PostDee-Profile-Catalog: 4` sees every template; `3`, `2`
  and older or unknown values receive `templateId: null` with the same editable
  appearance for cartoon designs. Storage and `/p/:slug` keep the real design;
  an old app's exact fallback replay is preserved and an edited one is
  `409 LINK_IN_BIO_APPEARANCE_CONFLICT`, as for earlier releases.
- Mobile: `link_in_bio_cartoon_scenes.dart` (`BioCartoonHeader`, link
  decoration and wrappers for tails, arrows, dashed chalk, tilt, stripe and
  awning) mirrors the public CSS. The picker shows a third chip, **การ์ตูน /
  Cartoon**, opens on the saved design's category, and thumbnails use no store
  name. Names are localized in Thai and English. Mobile sends catalog `4`.

**Delivery order: PR #51, then API before Mobile.** No Prisma change, migration,
entitlement or environment flag. Once a cartoon design is saved, a rollback
must keep a catalog-4 reader; never clear stored designs.

## Verification

- [x] Generator: 28 tests and `--check` pass; art guard: 31 tests pass.
- [x] API link-in-bio suites: 932 pass, including per-release GET/POST/DELETE
  compatibility (catalogs 1–5), exact replay and conflict, cover/colour
  overrides, layout CSS, fill turns and PNG parity for all 30 decoration files.
  Earlier tests that used `4` as an "unknown future" header now use `5`.
- [x] Full API: typecheck and build pass; 3,425 passed / 67 opt-in skipped,
  with 4 cases in 3 unrelated files (Sentry fatal process, owner-operation
  coordinator, platform-logo catalog) timing out while the Flutter suite ran
  alongside; all 3 files pass alone (39/39).
- [x] Mobile: `flutter analyze` reports no issues; full suite 4,680 passed /
  7 optional visual previews skipped (two workers). The 33 new cartoon widget
  tests cover 320px with text scale 1.6, long Thai names, light/dark app
  themes, English names, cover replacement and owner colours. Three existing
  assertions were updated for the third category chip and the cartoon
  compositions.
- [x] Native previews (widgets exported with bundled fonts and artwork) and the
  public pages at 360px match; public pages at 320px with a long Thai name and
  at 1280px have no horizontal overflow. Comic avatars shrink to 64px at 400px
  and below so long names keep room, on both renderers.
- [x] Android x64 Staging debug APK 12094 built with the guarded helper from
  commit `d7b61937` (SHA-256
  `0d5c3776bc6b9313529cc23d7adcb5ee93efa6c6518dca9c75c3b91f40979da3`,
  235,432,511 bytes, package `com.postdee.postdee_mobile.staging`, all ten
  cartoon PNGs bundled). Installed on `emulator-5554` (AVD `Pixel_8`) with the
  shared updater: previous build 12093 (`be16102f…`, the PR #51 build), package
  UID 10197 and internal storage kept, installed hash matches. The app starts
  natively with the STAGING strip and the signed-in session, saved draft and
  posts intact. Store link → Decorate shows three chips; การ์ตูน lists ten
  thumbnails with the neutral name; the Cartoon rocket preview opened and was
  closed without applying, so the draft stayed unsaved as before.
- [x] Emulator note: the cold boot under test load showed a system
  "isn't responding" dialog (Wait was chosen) and a stale USB-debugging prompt
  (Cancel); adb was already authorized after restarting the adb server.
- [ ] Saving or publishing a cartoon design against Staging needs PR #51 and this
  API deployed first (owner authorization). Production untouched.
