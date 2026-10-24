# Scheduler and plan-check fixes from the Codex review

Baseline: `origin/main` at `f29c701e` (2026-10-25). Branch:
`claude/fix-scheduler-plan-review`. Source: a Codex review of PRs #24 and #29
on 2026-10-25. All three findings below were confirmed against the code before
fixing.

## Findings and fixes

1. **The due-post batch could starve every other owner (from #24).**
   - Problem: `listDue` returned the same 50 oldest due posts every poll. If
     all 50 belonged to an owner the scheduler cannot start (for example an
     account whose deletion failed half-way), `runWithActiveOwner` rejected
     them, they stayed `QUEUED`, and no later post was ever read.
   - Fix: `listDue({ excludeIds })` (Prisma `id NOT IN`). The scheduler reads up
     to `maxDueBatchesPerPoll = 10` batches per poll, each excluding the posts
     already tried in that poll, and stops at a short batch.
2. **A failed plan read could block a later account deletion (from #29).**
   - Problem: the plan was read inside the nested owner-operation lifetime. Any
     nested rejection marks the outer operation as retained (the safety net for
     uncertain provider work), so a transient database error kept the durable
     ticket. That held even when the retry then published, and the owner's
     account deletion then failed with `ACCOUNT_WRITE_DRAIN_FAILED`.
   - Fix: `processPublishJobForPost` reads the plan before entering
     `runWithActiveOwner`. The error reaches the scheduler's pre-publish retry
     without touching the lifetime.
3. **Publish now during the plan read was failed (from #29).**
   - Problem: the job snapshot said `SCHEDULED`. If the owner pressed Publish
     now while the plan was read, the claim (which accepts a null schedule)
     succeeded and the post was failed with `PAID_PLAN_REQUIRED`, although
     post-now posts are not re-checked.
   - Fix: after the claim, the worker fails the post only if `findOwned` still
     shows a schedule. Otherwise it publishes normally.

## Reproduction before the fix

`apps/api/src/workers/schedulerReviewFixes.test.ts` ran against `f29c701e`.
All 4 cases failed:

| Case | Before-fix result |
| --- | --- |
| 50 stuck posts from a deleting owner, then 1 healthy post | Healthy post stayed `QUEUED` |
| 550 stuck posts | Batch limit constant did not exist (1 read) |
| Plan read fails once, then `PRO`; then account deletion | Post published, but deletion threw `OwnerOperationBusyError` (`ACCOUNT_WRITE_DRAIN_FAILED`) |
| Publish now during the plan read, plan `BASIC` | Publisher called 0 times; post not published |

`duePostRead.test.ts` gains a Prisma `excludeIds` case.

## Docs

- `ARCHITECTURE.md`: the scheduler batch rule and the plan-check rules.
- `README.md`: the scheduler bullet.
- `API.md` is unchanged because no HTTP contract changed.

## Round 2 after the Codex re-review (2026-10-25)

The re-review rated this PR "partly fixed". Two problems remained, both
reproduced:

- **500 or more stuck posts still starved later owners.** The skip list reset
  every poll, so each poll retried the same 500. Fix: replace `excludeIds` with
  a cursor kept across polls. `listDue({ afterId })` uses Prisma
  `id > afterId ORDER BY id`, and the memory store uses insertion order. The
  scheduler resumes after the last post it tried and wraps to the start at the
  end of the due list.
- **The post-claim `findOwned` could retain the operation ticket.** It ran
  inside the nested owner lifetime. Fix: no extra read. With an ended plan,
  `claimForPublish({ requireSchedule: true })` claims only a row still
  scheduled at its run time (Prisma `scheduledAt = runAt`). A row switched to
  Publish now is left `QUEUED`, and the next poll publishes it as post-now.

Before fix, against the round-1 head `57e97ef1`:
- "Reaches posts behind a full poll of 500 stuck posts on a later poll": the
  healthy post stayed `QUEUED`.
- "Fails an expired-plan post without extra reads" (`findOwned` failing):
  account deletion threw `ACCOUNT_WRITE_DRAIN_FAILED`.

The Publish-now test now checks the post is not failed on the first poll and
is published on the second. `duePostRead.test.ts` now expects `id` order,
`afterId` and the schedule-only claim.

## Known limitation (not changed)

In BullMQ mode (not deployed), a plan read that fails on every attempt leaves
the post `QUEUED` with no failure push, like other pre-claim errors there.

## Verification

See the pull request: targeted tests, the full API suite, typecheck and build.
