# Link in Bio slug reservation

Baseline: latest verified `origin/main` at
`6afe4d6b07fe53032467031b4575aa62c9751912` (2026-10-24), ahead/behind 0/0.
Branch: `claude/security-link-in-bio-slug-reservation`. Source: audit run-2,
"Investigate, then fix" → "Link-in-bio slug recycling". Independent of the open
security Batch 2-6 pull requests.

## Problem

`LinkInBioProfile.slug` is the only claim on a public `/p/<slug>` URL. A rename
updated the row and an account deletion removed it, so another owner could claim
the old slug immediately. Followers using a shared link would then land on a
stranger's page, which makes impersonation easy. Brand and system names such as
`postdee-official` or `admin` were also claimable.

## Reproduction before the fix

`linkInBioSlugReservation.test.ts` ran against the baseline stores, with only
the policy constants module present. 11 of 13 failed:

| Case | Expected | Before-fix result |
| --- | --- | --- |
| Another owner claims a renamed slug | 409 for 30 days | Claimed at once |
| Previous owner reclaims; new slug then held | Reclaim OK, other owner 409 | Other owner claimed the left slug |
| Slug of a deleted account | 409 for everyone for 30 days | Claimed at once |
| Five renames | Only the 3 newest held | Nothing held |
| `admin`, `support`, `postdee`, `postdee-official`, `official-postdee-th` | 409 | Accepted |
| Prisma: reserved by another owner | 409, no upsert | Upserted |
| Prisma: holder read before reservation read | Ordered reads | No reads |
| Prisma: expired reservation | Deleted in the same transaction | No transaction |
| Prisma: rename reserves the old slug and trims | Reservation upsert + trim | None |
| Prisma: reserved name | 409 before writes | Upserted |
| Prisma: account deletion | Ownerless reservation, owner id nulled | Profile delete only |

Two guards passed before and still pass: an unpublished page keeps its slug,
and republishing the same slug does no reservation work.

Two existing route tests that asserted immediate release were changed to the
new rule (409 for another owner, then success after 30 days).

## Change

- New `linkInBioSlugPolicy.ts`:
  - 30-day reservation.
  - At most 3 reservations per owner.
  - A reserved-name set (system words) plus any slug containing `postdee`.
- New Prisma model and additive migration `LinkInBioSlugReservation`:
  - Columns: `slug` primary key, nullable `ownerId` with no User relation,
    `releasedAt`, `reservedUntil`.
  - Index on `(ownerId, releasedAt)`.
- Prisma repository: `publish` runs one interactive transaction.
  - Reads the owner's current profile.
  - When the slug is new for this owner:
    1. Rejects reserved names.
    2. Reads any profile holding the slug, then the reservation. This order
       closes the race with a concurrent rename under Read Committed: the
       rename commits the profile change and the reservation together.
    3. Rejects an active reservation held by someone else, and deletes an
       expired or own reservation.
  - Upserts the profile as before.
  - On a rename, reserves the old slug for the owner and deletes that owner's
    reservations beyond the newest three.
  - A `P2002` still maps to `LINK_IN_BIO_SLUG_TAKEN`.
- Prisma `deleteAllForUser` runs in one transaction. It nulls the owner's
  existing reservations, reserves the profile's slug for nobody, then deletes
  the profile.
- The memory store mirrors the same rules.
- The factory selects the Prisma repository only when the reservation delegate
  and `$transaction` exist. Otherwise it fails closed with the existing 503
  `LINK_IN_BIO_UNAVAILABLE`, never silently skipping reservations.
- Every refusal reuses `409 LINK_IN_BIO_SLUG_TAKEN`. Mobile already shows
  "ชื่อ URL นี้มีคนใช้แล้ว กรุณาเลือกชื่อใหม่", so no app change is needed.

## Deploy order

The migration is additive and must run before the new API code serves traffic.
Production runs `prisma migrate deploy` as `preDeployCommand`, and Staging runs
it in `startCommand`, so a normal deploy does this. Rollback leaves an unused
table. No new environment variable.

## Docs

`API.md` (Link in Bio errors), `ARCHITECTURE.md` (Link in Bio paragraph),
`README.md` (profile page paragraph).

## Verification

- Targeted: `linkInBioSlugReservation.test.ts` 13/13. All `src/modules/linkInBio`
  and `src/modules/account` tests pass (645).
- `prisma validate` and `prisma generate` pass. The migration SQL is the output
  of `prisma migrate diff` from the baseline schema.
- Full: `npm run test`, `npm run typecheck`, `npm run build` (results in the
  pull request).
- Real PostgreSQL, checked after merge (2026-10-25):
  - Setup: a throwaway PostgreSQL 18.1 fixture cluster on loopback port 55441
    (`postdee_addon_test`), created in a temporary folder. The local
    development database was not touched.
  - Migrations: all 23, including `20261024120000_link_in_bio_slug_reservations`,
    applied from main `7fca508e` with no drift (`prisma migrate diff
    --exit-code`). The add-on real-database suites passed (7 tests).
  - New `linkInBioSlugReservation.database.test.ts`, 3 tests:
    - A rename reserves the old slug, which is released after 30 days.
    - Account deletion keeps an ownerless reservation.
    - Over 15 rounds of one owner renaming while another claims the old slug at
      the same time, the claim never succeeds.
  - Mutation check: with the "current holder" read removed, the race test fails
    because the other owner took the slug mid-rename. The holder-first read is
    therefore needed, and the test detects its loss. With the shipped code
    restored, 3/3 pass.
  - Clean-up: no fixture rows were left, and the cluster was stopped and
    deleted.
  - The test is skipped unless `POSTDEE_TEST_DATABASE_URL` points at that exact
    fixture.

## Residual risk and owner decisions

- Slugs released before this deploy are not backfilled. Whoever holds one now
  keeps it.
- After account deletion the slug text stays for 30 days, but no owner id is
  kept. Confirm this retention fits the privacy policy.
- The reserved-name list is a starting set. Review it, especially whether
  generic words such as `shop` should be reserved. Any current holder of a
  listed name is grandfathered.
- Reservations owned by nobody (deleted accounts) remain as rows after expiry
  until someone claims the slug. That is one small row per deleted account
  with a profile.
