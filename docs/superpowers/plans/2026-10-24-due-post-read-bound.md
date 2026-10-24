# Bounded due-post read for the publish scheduler

Baseline: latest verified `origin/main` at
`6afe4d6b07fe53032467031b4575aa62c9751912` (2026-10-24), ahead/behind 0/0.
Branch: `claude/security-due-post-read`. Source: audit run-2,
"Investigate, then fix" item "Global `listDue` full-row read". Independent of
the open security Batch 2-6 pull requests.

## Problem

Every five seconds the in-process scheduler called `PostStore.listDue`. The
Prisma implementation ran one `findMany` over every owner's `QUEUED` due posts
with no `take` and no `select`, so a large backlog loaded all of those full rows
(caption, settings JSON, media fingerprint, add-on allocation) into the single
shared API process at once.

## Reproduction before the fix

`apps/api/src/modules/posts/duePostRead.test.ts` was run against the baseline
source (constant inlined as 50, since it did not exist yet). All three cases
failed:

| Case | Expected | Before-fix result |
| --- | --- | --- |
| Prisma `listDue` | `take: 50` and a publish-field `select` | `findMany` called with neither |
| Prisma `listDue` with `limit: 5` | `take: 5` | No `take` |
| Memory store, 53 due posts | 50 returned | 53 returned |

## Change

- `maxDuePostsPerPoll = 50` and `DuePost` (a `QueuedPost` without
  `mediaContentFingerprint` and `addonPostUnits`) in `postStore.ts`.
- `listDue({ now, limit? })` returns at most `limit` (default 50) posts in both
  stores. Prisma adds `take` and selects only the 13 columns the mapper and
  scheduler use. Ordering is unchanged (`scheduledAt` ascending, so post-now rows
  with a null schedule still follow overdue scheduled rows in Postgres).
- The scheduler is unchanged: posts beyond the batch stay `QUEUED` and are read
  by the next poll.

No API contract, schema, migration, environment variable or mobile change, so
`API.md` is unchanged. `ARCHITECTURE.md` and `README.md` record the bound.

## Verification

- Targeted: `duePostRead.test.ts` 3/3 and `src/workers` pass.
- Full: `npm run test`, `npm run typecheck`, `npm run build` in `apps/api`
  (results in the pull request).

## Residual risk

- At 50 posts per poll the scheduler still processes them one at a time, so a
  very large backlog drains at the publisher's pace, as before.
- Rows that stay `QUEUED` because their owner is busy (account deletion in
  progress) are re-read each poll. Fifty of them with the earliest schedule could
  delay later posts until deletion finishes; deletion removes those rows.
