# Link in Bio reservation delete race fix

Baseline: `origin/main` at `f29c701e` (2026-10-25). Branch:
`claude/fix-slug-reservation-race`. Source: a Codex review of PR #27 on
2026-10-25. The finding was confirmed against the code.

## Problem

`assertSlugClaimable` read the reservation for slug X and, when it was expired
(or the claimant's own), deleted it with `deleteMany({ where: { slug } })`. The
following sequence was possible:

1. Owner B's claim reads X's reservation as expired.
2. In the meantime, owner A reclaims X and renames back to Y, which writes a
   fresh 30-day reservation for X.
3. B's unconditional delete then removed A's fresh reservation, and B claimed
   X.

The `ARCHITECTURE.md` wording promised more protection than the code gave.

## Fix

- The delete is conditional:
  `deleteMany({ where: { slug, OR: [{ reservedUntil: { lte: now } }, { ownerId: claimant }] } })`.
- When it deletes nothing, the row changed after the read, and the claim fails
  with `409 LINK_IN_BIO_SLUG_TAKEN`.
- The memory store has no await between its check and its write, so it is
  unchanged.

## Reproduction before the fix

`linkInBioSlugReservationRace.test.ts` ran against `f29c701e`. Both cases
failed:

| Case | Before-fix result |
| --- | --- |
| Delete is conditional on still expired or own | Called with `{ where: { slug } }` only |
| Reservation replaced after the read (conditional delete removes 0 rows) | Claim succeeded (profile upserted) |

The existing #27 unit test was updated to expect the conditional delete.

## Verification

- `src/modules/linkInBio`: 524 passed, 3 skipped. Typecheck passes.
- Real PostgreSQL: on a throwaway 18.1 fixture cluster on loopback 55441,
  `linkInBioSlugReservation.database.test.ts` passed 3/3 with the fix,
  including the expired-reservation claim and the 15-round rename/claim race.
  No rows were left, and the cluster was stopped and deleted.
- Full API suite, build: see the pull request.
