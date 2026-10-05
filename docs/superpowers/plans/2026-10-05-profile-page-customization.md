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
Staging profile deployment does not imply this customization migration is live.
Real R2 upload and deployed-domain QA remain required for rollout. Retain current
AI captions, uploader, publishing, login, calendar, billing and analytics behavior.

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
This does not verify the pending migration, real R2 transport or deployed-domain
customization. Obtain release authorization before push/merge/deploy; deploy the
API and migration before installing the candidate Staging APK.
