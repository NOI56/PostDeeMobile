# Expired upload session sweeper

Baseline: latest verified `origin/main` at
`6afe4d6b07fe53032467031b4575aa62c9751912` (2026-10-24), ahead/behind 0/0.
Branch: `claude/security-upload-session-sweeper`. Source: audit run-2 finding
`uploads/managedUploadService:create-unretired-active-owner-state`, the
"sweeper" part that Batch 5 (PR #22) left open. Batch 5 caps file names at 255
characters and open sessions at 10 per owner. This change does not depend on it.

## Problem

`sessionExpiresAt` only blocked later part/complete calls. Nothing read the
`(expiresAt, status)` index: expired `UPLOADING` rows stayed forever and their
R2 multipart uploads were never aborted. Only account deletion
(`prepareOwnerDeletion` / `finishOwnerDeletion`) cleaned them up.

## Reproduction before the fix

The new tests were run against the baseline source before any implementation.
All 9 failed:

| Test | Before-fix result |
| --- | --- |
| Sweep aborts R2 and retires expired sessions (memory store) | `service.sweepExpiredSessions is not a function`: no retirement path exists |
| Unexpired, grace, completing and completed sessions untouched | Same |
| At most `limit` per sweep | Same |
| Failed R2 abort keeps the session for the next sweep | Same |
| Prisma bounded oldest-first expired list | `repository.listExpiredUploading is not a function` |
| Prisma compare-and-set retire | `retireExpired is not a function` |
| Scheduler sweeps on its own interval after `start()` | Sweeper called 0 times: the scheduler had no cleanup work |
| Sweep failure keeps readiness | `scheduler.sweepUploadsOnce is not a function` |
| No overlapping sweeps; drain waits | Same |

The app-wiring test (`createApp` passes the managed upload service's sweep to
the scheduler) was added after the implementation.

## Change

- `UploadSessionStore`:
  - `listExpiredUploading({ expiredBefore, limit })` returns `UPLOADING` rows
    of any owner, oldest expiry first. In Prisma it is `findMany` with `take`
    on the existing index.
  - `retireExpired({ id, expiredBefore })` moves `UPLOADING` to `ABORTED` with
    a compare-and-set (Prisma `updateMany` with a count check).
- `ManagedUploadService.sweepExpiredSessions({ limit = 25 })`:
  - Uses `expiredBefore = now - 5 minutes`.
  - For each session it aborts the R2 multipart upload first. The R2 client
    already treats `NoSuchUpload` as success. Then it retires the row.
  - Returns `{ retired, failed }`. A failed session stays `UPLOADING` and the
    next sweep retries it.
- `createPublishScheduler({ sweepExpiredUploads, uploadSweepIntervalMs = 10 min })`:
  - A second timer starts and stops with the scheduler.
  - Sweeps run one at a time, and `drain()` waits for the active one.
  - Counts are logged. Errors are reported as monitoring operation
    `scheduler.uploadSweep` (added to the allowlist) and never change `/ready`.
- `app.ts` passes `managedUploadService.sweepExpiredSessions` when a managed
  upload service exists. Production and Staging use `PUBLISH_QUEUE=memory`, so
  the sweep runs in the single API instance. In BullMQ mode no in-process
  scheduler exists, so this sweep does not run.

Why this is safe against live uploads: after `expiresAt`,
`getUploadableForOwner` and `beginCompletion` reject the session, so an expired
`UPLOADING` row can only become `ABORTED`. The 5-minute grace period covers a
completion request that passed the expiry check just before the deadline
(transactions time out after 10 seconds). Account deletion and the sweep can
both abort the same upload, and that is harmless because both abort paths are
idempotent.

Rows are retired, not deleted. `findForOwnerKey` keeps returning a
non-`COMPLETED` session for that key, so post creation keeps answering
`UPLOAD_NOT_READY` instead of falling through to the legacy path. After Batch 5
caps `fileName` at 255 characters, each retained row is small.

No schema change, migration, new environment variable, or mobile change.
Mobile treats every status other than `COMPLETED`/`COMPLETING` as not completed,
and `ABORTED` was already a documented status.

## Docs

`API.md` (`DELETE /uploads/:uploadId` section), `ARCHITECTURE.md` (upload
rules list), `README.md` (interrupted-upload paragraph). When this merges after
Batch 5, remove Batch 5's sentences "No sweeper retires expired session rows or
aborts their R2 uploads yet" (`API.md`) and "Still open: a sweeper ..."
(`ARCHITECTURE.md`).

## Verification

- Targeted: `uploadSessionSweeper.test.ts` 6/6 and
  `publishSchedulerUploadSweep.test.ts` 4/4 pass.
- Full: `npm run test`, `npm run typecheck`, `npm run build` in `apps/api`
  (results in the pull request).
- Not verified: a real R2 abort on Staging, and deployed row counts.

## Residual risk and owner checks

- Throughput is at most 150 sessions per hour. Batch 5's 10-per-owner cap and
  the 60/hour uploads limiter keep creation near that rate per client. A
  backlog of old rows from before this change drains over several hours after
  deploy.
- R2 multipart uploads with no session row (for example, a crash between
  `CreateMultipartUpload` and the database insert) are not swept. Owner check:
  confirm in the Cloudflare dashboard that the bucket has a rule that aborts
  incomplete multipart uploads (Cloudflare documents a 7-day default).
- Rows stuck in `COMPLETING` after a crash are not reconciled by the sweep.
  They still reconcile on `GET /uploads/:id` or account deletion.
- A session whose R2 abort fails permanently takes one batch slot on every
  sweep. Twenty-five such rows would block the queue. The
  `UPLOAD_SWEEP_INCOMPLETE` log line makes this visible.
