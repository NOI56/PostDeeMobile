# Separate 3D storefront templates — 2026-11-01

## Scope and baseline

The owner approved ten 3D website designs as a separate category after reviewing
clay, layered-paper and frosted-glass concepts. Package rights stay unchanged;
any visitor should be able to open a published website without login or the app.
This is a **local candidate**, not a hosted deployment or installed-build receipt.

Work starts from freshly verified `origin/main`
`e7fd926ef06791f7a3c6cd984b3742558258c91e`, on
`codex/3d-storefront-templates`, in the isolated delivery checkout. The final
candidate branch is `codex/3d-storefront-templates-ready`, based on freshly
fetched main `3eee7a71a79917b6dcc6d842e5d28cb0b053010e`. That intervening
commit changes only the previous Staging deployment receipt in `docs/STAGING.md`;
all feature code bytes are unchanged by the baseline update. The original
dirty checkout and unrelated Store-link/dark-mode work remain preserved. The
owner subsequently approved integrating feature commit `859d2a86` into main,
pushing it and deploying only Staging. The delivery is recorded below.

## Catalog and presentation

`shared/profile-templates.json` version 2 generates both API and Dart catalogs,
including `profileTemplateCatalogVersion = 2`. Category ID `dimensional` displays
as **3D**. The picker exposes only Minimal (20) and 3D (10), and preserves all
100 original catalog entries, values and order for saved pages. Seven legacy
theme IDs and appearance JSON version 1 remain unchanged.

| Template ID | Display name | Material/composition |
| --- | --- | --- |
| `dimensional-clay-mint` | ดินปั้นมิ้นต์ | `clay` |
| `dimensional-clay-peach` | ดินปั้นพีช | `clay` |
| `dimensional-clay-cloud` | ก้อนเมฆนุ่ม | `clay` |
| `dimensional-clay-sand` | ดินปั้นทราย | `clay` |
| `dimensional-paper-fold` | กระดาษพับ | `paper-stack` |
| `dimensional-paper-stage` | เวทีกระดาษ | `paper-stack` |
| `dimensional-paper-ribbon` | ริบบิ้นกระดาษ | `paper-stack` |
| `dimensional-glass-lavender` | กระจกลาเวนเดอร์ | `frosted` |
| `dimensional-glass-mist` | กระจกหมอก | `frosted` |
| `dimensional-glass-sage` | กระจกเขียวหม่น | `frosted` |

Native widgets and public CSS provide depth, material surfaces and readable link
rows. Each template's decorative header PNG uses its exact ID as filename and
is bundled identically under API `assets/profile-decorations/` and Mobile
`assets/images/profile_decorations/`. Artwork contains no owner identity or
clickable text; the real store name, description, logo, links and platform icons
remain native/HTML content. An uploaded cover replaces header artwork only.
Custom colors, fonts, button shape, featured links and draft confirmation remain
editable. Motion retains existing reduced-motion behavior.

No WebGL, third-party script, third-party font or arbitrary asset URL is added.
The public page keeps its existing same-origin asset allowlist and script-free
CSP. New PNG filenames are derived from the fixed dimensional catalog IDs.

## Access and compatibility

Basic keeps two active links, Starter seven and Pro twenty. There is no
paid-only theme gate. Published `/p/:slug` pages remain unauthenticated; the
catalog header does not grant owner access. Private management and image-owner
validation remain unchanged.

New Mobile sends exactly `X-PostDee-Profile-Catalog: 2` on authenticated
`GET /link-in-bio`, `POST /link-in-bio/publish` and
`DELETE /link-in-bio/publish`. These responses retain dimensional template IDs.
Missing, older or unknown header values receive the same appearance fields
with `templateId: null` and its existing fallback theme. Responses retain
`Cache-Control: no-store` and vary on the catalog header. Classic responses
remain unchanged.

This fallback is response serialization only: reads never change storage, and
the public page always uses the saved 3D selection. An older client's exact
fallback replay omits appearance from the atomic update, preserving the stored
3D choice and a concurrent styling update after that compatibility read. If a
legacy/unrecognized-catalog client sends a minimal/null-template appearance
that differs from the current saved 3D fallback, the API returns
`409 LINK_IN_BIO_APPEARANCE_CONFLICT`. An edited fallback and a stale snapshot
captured before a newer theme was saved are ambiguous, so neither may silently
replace the design. No profile/name write, image validation or publication/image
cleanup runs on this conflict. Reload page data or update the app before retrying.
Known classic template IDs and distinct legacy theme IDs remain deliberate
replacements. A catalog 2 client can explicitly clear its template using null.
Omitted appearance keeps its existing atomic preservation behavior.

**Delivery order: API before Mobile.** The old API rejects unknown template IDs.
No Prisma schema change, migration, entitlement, environment flag or destructive
data cleanup is required. Delivery needs separate owner authorization and the
normal exact-main CI and Staging workflow.

Once a 3D selection has been saved, a rollback must keep catalog 2 readers and
the legacy-response adapter. An older API cannot validate the new template
IDs. Keep stored appearances intact; do not clear user designs as a rollback.

## Final verification to record

- [x] Shared generator: 24 tests and `--check` pass; original 100 entries keep
  their values/order and both generated catalogs match.
- [x] API compatibility/owner/plan cases pass, including legacy GET/POST/DELETE,
  exact fallback replay, concurrent updates and explicit classic/null changes.
  The stale-before-handler/edited-fallback correction failed five cases first;
  its four affected suites then passed 267 cases, including conflict preservation
  of the name, saved theme and publication/image hooks.
- [x] Final full API after the legacy-conflict guard: 3,063 passed / 67 opt-in
  PostgreSQL cases skipped, across 190 passed / 11 skipped files. Node 22.23.3
  uses one worker. Typecheck, build and generator `--check` pass after the fix.
  The compiled memory smoke returns the conflict without profile/name/image
  hook writes and keeps the public Peach design available. Prisma validate and
  helper typecheck passed; no schema change or migration ran.
- [x] Primary Mobile source: 4,480 passed / seven optional visual previews
  skipped; analysis reports no issues. The 197 targeted cases include the
  ten designs, Thai/English labels, draft confirmation, custom imagery/colors
  and narrow light/dark layouts. Two existing UI assertions were updated to
  account for the two category controls and a modal-scoped category label;
  the corrected full suite passes with unchanged deadlines.
- [x] Ten new PNG signatures and byte-for-byte API/Mobile parity pass; public
  asset/allowlist cases pass 24/24. Original generation prompts and SHA-256
  receipts are in local `artifacts/3d-theme-art/manifest.json`.
- [x] Actual native widgets were exported for all ten designs. Browser checks
  on all ten public routes at 320px confirm loaded artwork, two links, visible
  material shadows and no horizontal overflow. A 390px case and a 1920px
  desktop case also pass; keyboard Tab focuses the real YouTube link. Large
  Thai text, custom imagery, light/dark surroundings and reduced motion are
  covered by widget/API tests; browser OS reduced-motion emulation is not claimed.
- [x] Browser review caught a CSS specificity bug hidden by string assertions:
  the old composition reset overrode the first 3D material rules. A regression
  failed before the fix; the scoped selector now has three attributes and wins
  over the two-attribute reset. Forty-four 3D cases and 192 legacy rendering
  cases pass; actual computed shadows were rechecked for all ten designs.
- [x] Public pages need no login, external links keep their safe attributes,
  and CSP still forbids scripts and non-self image/font sources. Browser console
  warnings seen during QA come from the installed MetaMask extension; no local
  application error was found. Viewport overrides were reset. Browser screenshots
  use the existing CUA capture API after a CDP full-page capture timed out.
- [x] Combined APK source preserves the installed Store-link/readability and
  dark-mode work. Its final full suite passes 4,513 cases / seven optional
  visual previews skipped with two workers, and analysis reports no issues.
  An initial four-worker run stopped on Windows temporary-directory cleanup
  (`errno 32`) in the request-deadline test teardown; that unchanged file passes
  all eight cases alone, and the complete two-worker rerun passes. All 704
  frozen Mobile/shared source hashes still match after tests and the build.
- [x] Android x64 Staging debug APK 12091 builds successfully. Its package is
  `com.postdee.postdee_mobile.staging`, size 224,263,745 bytes and SHA-256 is
  `8f6d97f4f1e720777a59a424b577a372fa7e608fd46d369c035ea12e42b38ce1`.
  The guarded helper verifies the Staging API/Firebase environment, real
  Firebase auth, disabled mock auth, RevenueCat Test Store and Staging Sentry
  release `postdee-mobile@3d-storefront-templates-12091`. All ten bundled 3D PNG
  hashes match the frozen source. Local evidence is recorded in
  `artifacts/3d-mobile-apk-receipt.json` and
  `artifacts/3d-combined-build-source-manifest.json`. No secret values are
  included in these receipts. The APK has not been installed.
- [x] Feature commit `859d2a86beb4adbfa6f89ef1338d1cc399359378` was fast-forwarded
  into main and pushed with `[skip render]`. Its exact-SHA
  [CI run 41304004522](https://github.com/NOI56/PostDeeMobile/actions/runs/41304004522)
  passes Backend API (3,063 / 67 skipped), Flutter (4,480 / seven skipped),
  analyze and 21 Staging configuration guard cases. The separate
  [iOS no-codesign build 41304004516](https://github.com/NOI56/PostDeeMobile/actions/runs/41304004516)
  also succeeds. No artifact from that iOS workflow was distributed or installed.
- [x] Render Staging deploy `dep-dbjimstg1s2s73fs0q2g` is Live at that exact
  source SHA from 2026-11-01 12:08:36 UTC / 19:08:36 Asia/Bangkok. It replaces
  `e7fd926e` / `dep-dbjepsutlv9c73d139q0`. Startup finds 28 existing migrations
  with none pending, and the publishing activation guard passes with an empty
  backlog. No environment values were changed.
- [x] Live read-only smoke at 12:08:50 UTC confirms health 200, ready 200 with
  database/queue ok and no-store, posts 401 without a token, and private profile
  401 with/without catalog 2 plus no-store/Vary. All ten new public PNG routes
  return correct content/security/cache headers and exact approved source hashes
  without login; an unknown artwork filename returns 404. No app error/warn logs
  appear from 12:07:15 through 12:08:53 UTC. Local safe receipt:
  `artifacts/3d-staging-live-receipt.json`. Deployment details are in
  [STAGING.md](../../STAGING.md).
- [ ] Install the prepared APK and record retained device UID/data if later
  authorized. No APK/device installation, authenticated Staging profile mutation,
  real published 3D profile, social publishing or iOS device test was performed
  during this deployment. Production was not deployed, resumed or reconfigured.
