# Profile page customization

## Accepted scope

Every package keeps one page and up to 20 enabled links. Owners choose one of
four starting themes then edit section and individual-link colors/fonts, logo,
cover, solid/gradient/image background, description, button shape, category/order
and one featured promotion. Include reset-to-theme and preview before publishing.
No product cards/prices, analytics provider, custom domains or custom font uploads.

## Data and safety

- Add nullable versioned appearance JSON and LinkInBioImage metadata, with User
  cascade, retaining legacy page/link-only requests and existing account cleanup.
- Same presets/font identifiers in Flutter and HTML; self-host licensed fonts.
- Gallery images normalize to bounded PNG; authenticate owner previews and
  validate image ownership before writing the publication snapshot.
- Published media URLs depend on published slug/slot, not storage keys or signed URLs.
- Keep drafts/private uploads separate from the live appearance snapshot.
- Cap per-owner image metadata, prune unused older files on activity, and retain
  current saved/newest draft references. Current deployment is one API instance;
  durable locking and a scheduled reconciler are prerequisites for horizontal scaling.

## Verification and release

Add regression tests before implementation for legacy compatibility, malformed
styles, escaping/CSP, cross-owner images, draft/publication separation, appearance
roundtrip, theme reset, editor interactions and narrow screens. Run API full tests,
build, Prisma validate/generate/helpers, Flutter full analyze/tests, APK build,
responsive browser QA and emulator editing/publication smoke.

Deploy migration/generated client/API/fonts before the mobile client. Existing
profile deployment alone does not establish customization acceptance. Verify
real R2 transport and deployed-domain behavior separately; dated results below
record which checks passed or were deferred. Retain current AI captions,
uploader, publishing, login, calendar, billing and analytics behavior.

## Local verification on 2026-10-05

Baseline: verified `origin/main` at `1451dd26627f3d85f35d24fc5dcbe5a32430847c`.
API full suite: 1,158 passed; build, Prisma validation/generated client/helper
typechecks passed. Flutter full suite: 1,107 passed; analyze had no issues.
Android x64 debug APKs built for local QA and the existing Staging configuration.
Responsive local browser checks passed for all four themes and desktop/mobile.
Android emulator smoke passed for gallery logo upload, theme/font/color changes,
applying while the keyboard is open, featured promotion, publication and saving
a later draft without changing the published page. Original Staging APK and
Flutter preferences were restored afterward, retaining the Google account.
That local run did not verify the then-pending migration, real R2 transport or
deployed-domain customization. The authorized Staging deployment and its more
limited live acceptance are recorded separately below.

## Staging verification on 2026-10-05

The user authorized push and Staging deployment. PR #15 merged as
`9195211f16519fd58c9cc01d6949dd8486190d01`. Render service
`srv-d9bb72ojs32c739osa5g`, deploy `dep-db1qad6gekts73f0p8bg`, reached Live
in 2 minutes 1 second. Logs confirmed migration
`20261005193000_customize_link_in_bio_profile` applied, all migrations completed
successfully, and the API started listening. The generated client/API and
bundled font assets were deployed before installing the candidate mobile APK.

All PR CI passed (API 1,158 tests; Mobile 1,107 tests). Main CI run
`37316135653` and iOS build run `37316135541` also succeeded. The installed
Staging APK matched SHA-256
`A20F8BADF189AD4D753CA1C4AD64046E0959A9993A6941FB60CC669DB62C8EA8`.

On the real Staging Android emulator, gallery logo upload succeeded. A temporary
local draft was saved; after force-stop/restart, the logo loaded again from the
authenticated owner image API. This confirms the upload and private byte-read
path, not a published public image route. Original Flutter preferences were
restored and compared afterward; the new APK remains installed, and the
Firebase/Google account was preserved.

The user explicitly chose to defer live browser and R2 lifecycle checks. Public
page/image and customization publish/update/unpublish acceptance remain
unverified in this live Staging run; the existing published profile was preserved.
Saved browser permissions blocked both the Staging and Cloudflare
domains even after approval; no alternative HTTP or browser workaround was used
to bypass those blocks. Before the browser blocks, the direct R2
`GetBucketLifecycleConfiguration` read returned `403 AccessDenied`, so the actual lifecycle
configuration remains unverified. Existing local/automated publication tests
and the earlier profile-page Staging checks do not satisfy these new live gates.
Production was not deployed or accepted by this Staging run.
