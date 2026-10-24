# Scheduled posts after a paid plan ends

Baseline: latest verified `origin/main` at `fc1ddd38` (2026-10-24).
Branch: `claude/security-scheduled-post-plan-check`. Source: audit run-2,
"Investigate, then fix" → "Queued posts after a paid plan ends". The owner
approved the recommended rule on 2026-10-24.

## Problem

`POST /posts` requires Starter or Pro to schedule (14 or 30 days ahead), but
`publishScheduler.ts`, `publishWorker.ts` and the BullMQ runner never re-read the
plan. After the subscription expired, was refunded, or a trial ended, every
remaining scheduled post was still sent.

## Rule (approved)

When a **scheduled** post comes due, the worker reads the owner's current plan
with the same `subscriptionStore.getPlan` used by `POST /posts`. That includes
admin trials and the RevenueCat-maintained status and period end.

- Plan is `BASIC`:
  - Nothing is sent to PostPeer.
  - Each selected platform is recorded `FAILED` with
    `errorMessage: "PAID_PLAN_REQUIRED"`.
  - The post becomes `FAILED`, and the usual failure push is sent.
  - The units charged at creation are **not refunded**: monthly counting
    ignores status, so the row still counts.
- Starter or Pro (including a downgrade from Pro to Starter): publishes as
  before. Accepted schedules keep their time.
- Post-now posts are not re-checked.
- The plan is read **before** the post is claimed. A read failure throws
  before any state change, and the scheduler's existing pre-publish retry
  policy applies (retry, then `FAILED` after 3 attempts).
- Local mock development (`AUTH_PROVIDER=mock`, non-production) takes the plan
  from a per-request header that cannot be re-read, so no check applies there.
  The condition is shared with the post routes' override switch
  (`allowsSubscriptionPlanOverride`).

## Reproduction before the fix

`scheduledPublishPlan.test.ts` ran with only the plan-reader module present,
before the worker used it. 3 of 9 failed:

| Case | Before-fix result |
| --- | --- |
| Due scheduled post, owner now `BASIC` (scheduler) | Plan never read; the post was published |
| Plan read fails once, then `PRO` | Plan never read |
| Shared worker (BullMQ path), owner `BASIC` | Worker returned `PUBLISHED` instead of `FAILED` |

These guards passed before and after:
- Starter and Pro still publish.
- Post-now posts are not checked.
- A failed post still counts its 2 units.
- The reader is off in mock mode and reads by owner id under Firebase auth.

## Change

- `apps/api/src/workers/scheduledPublishPlan.ts`:
  - `paidPlanRequiredPublishError`, the `ReadOwnerPlan` type and
    `allowsSubscriptionPlanOverride(config)`.
  - `createScheduledPublishPlanReader({ config, subscriptionStore })` returns
    nothing in mock mode, and otherwise `getPlan({ id, provider })`.
- `processPublishJobForPost({ readOwnerPlan })`:
  - Before the claim, it reads the plan for `status: 'SCHEDULED'` jobs.
  - After the claim, when the plan is `BASIC`, it records the platform
    failures, marks the post `FAILED`, notifies, and returns a `FAILED` result
    with cleanup `SKIPPED`.
- `createPublishScheduler({ readOwnerPlan })` passes the reader through.
- `app.ts` passes `createScheduledPublishPlanReader({ config, subscriptionStore })`
  to the memory scheduler and uses `allowsSubscriptionPlanOverride` for the
  post routes (same behavior as before).
- `publishWorkerRunner.ts` (BullMQ, not deployed) builds a subscription store
  and passes the reader. It now also creates Prisma when the subscription store
  or trials need it.

No schema change, migration, environment variable or API request change. The
app already treats `FAILED` as a failure. Its post detail screen shows each
platform's `errorMessage` as `สาเหตุ: …`, so an app build without the companion
mobile change shows the raw code `PAID_PLAN_REQUIRED` there. The companion app
PR maps it to a Thai explanation.

## Docs

`API.md` (platform results), `ARCHITECTURE.md` (plan rules),
`README.md` (Cloud Scheduling paragraph).

## Verification

- Targeted: `scheduledPublishPlan.test.ts` 9/9.
- Full: `npm run typecheck` and `npm run build` pass, and
  `npm run test -- --maxWorkers=3` gives 2,637 passed, 0 failed. That includes
  the mock-mode flow tests that schedule posts with the plan header.
- Not verified: Staging, with a real expired subscription.

## Residual risk

- A user who renews after the scheduled time does not get the failed post back;
  they must create it again.
- Subscription rows that RevenueCat has not yet expired (grace or billing
  retry) still count as paid, which is the intended behavior.
