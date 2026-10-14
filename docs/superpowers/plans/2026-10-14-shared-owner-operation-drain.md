# Shared owner operation drain — implementation, verification and Staging delivery

Date: 2026-10-14 (Asia/Bangkok)

Status: Source `7576ee3` is pushed on main and Live on Staging with migration 18.
Feature and main CI pass; real deletion, social publishing and Production remain
disabled. [The later delivery receipt](#main-and-staging-delivery-2026-10-14)
records hosted evidence. The original sections below preserve the preceding
local implementation phase and its baseline; their local-only scope is historical.

## Local implementation scope and baseline

The user requested continuation of the remaining cross-process deletion drain
work. Continue from local `1b5a403` on
`codex/staging-regression-and-test-types`, whose verified remote-main baseline
is `f07ee30`. The earlier local typing/native/R2-part receipt is preserved in
[`2026-10-14-staging-regression-and-typecheck.md`](2026-10-14-staging-regression-and-typecheck.md).
The original security audit and prior delivery receipts are unchanged.

The local implementation phase did not merge main, push, deploy, apply a hosted
migration, change hosted flags, create an account or perform real account
deletion. The later separately authorized delivery is recorded below.
The user previously authorized normal project test/build
execution. Existing mobile source, credentials, dependencies and feature flags
are retained.

## Problem and resulting behavior

The durable owner marker rejected work admitted after sealing, but a callback
admitted in a different process could still finish after destructive cleanup.
The local FIFO queue could not represent that callback's lifetime in PostgreSQL.
Deletion therefore needs both a shared lifetime record and a shared exclusive
cleanup claim, not merely another marker check.

The candidate now:

1. Registers a private operation ticket in a short Serializable transaction
   before the callback starts. Admission locks the ACTIVE owner row; a competing
   seal uses the same owner row. Remote I/O stays outside SQL transactions.
2. Seals the owner and preserves first same-UID deletion authorization before
   shared drain. Already-admitted work remains visible in every upgraded process.
3. Waits for an empty ticket set and acquires one owner-exclusive cleanup claim
   before queue/provider/media/database/identity cleanup. Re-read provider profile
   scope and cleanup capabilities after drain so a previously admitted profile
   creation cannot be omitted from the cleanup snapshot.
4. Releases successful known work by exact owner/operation ID. Callback
   exceptions, ambiguous HTTP/provider outcomes and unconfirmed release retain
   tickets. A failed release does not replace a successful remote queue
   acknowledgement with a synthetic queue failure.
5. Releases a cleanup claim by exact owner/run ID after its cleanup callback
   settles. Process crash or failed release leaves the claim blocked. No timer
   expiry or automatic stale-claim takeover is implemented.
6. Requires a sealed owner and an empty operation set before final session
   deletion. Neither finish nor user-data cascade may erase unresolved blockers.

Memory stores implement matching admission/drain semantics only within their
process. Cross-process coordination requires all participants to use the same
Prisma-backed PostgreSQL database.

## Persistence and lifecycle wiring

Additive migration `20261014020000_track_owner_operations` creates:

| Table | Fields and boundary |
| --- | --- |
| `ManagedOwnerOperation` | Random private ID, owner ID and start time; owner index; restrictive FK to `ManagedUploadOwner` |
| `ManagedOwnerDeletionRun` | Owner primary key, unique random run ID and start time; restrictive FK to `ManagedUploadOwner` |

These records reference the durable marker, not `User`, so user-data cascade
cannot remove lifetimes or cleanup claims. No existing marker/proof is backfilled.
The start time is diagnostic only; even an old ticket remains a blocker.
No token, signed media URL, credential or provider payload is stored in a ticket.
No public endpoint exposes operation or cleanup-claim IDs.

The coordinator is in
`apps/api/src/modules/account/prismaOwnerOperationCoordinator.ts`, wired by the
Prisma upload-session repository and memory store. `runWithOwnerLifetime` admits
concurrent HTTP/worker callbacks; `runWithActiveOwner` preserves the separate
FIFO for explicit queue/store writes. This keeps concurrent AI quota validation
working instead of serializing whole provider requests. Nested calls within
each admission surface share an AsyncLocalStorage context instead of waiting
on their own FIFO entry; cross-surface calls obtain their own tracked ticket.
Started unawaited children retain the same ticket until their callbacks
settle; after the parent context closes, later descendants must re-admit and
cannot reuse a closed admission.

`ownerOperationRouter.ts` wraps the final registered authenticated mutation
handler promise through its `finally` work, not response `end`, `finish` or
client `close`. Known mutating reads include auth bootstrap, social refresh,
billing subscription and upload reconciliation. Account deletion/readiness use
their separate deletion path. Ambiguous server responses retain a blocker;
explicit configuration failures known to precede remote I/O may release normally.
Conservative retention can require reconciliation even when a failed operation
eventually proves harmless. This is an availability tradeoff, not permission to
expire a ticket.

Managed upload create/part/complete/reconcile/abort are awaited inside protected
HTTP handlers; new direct service callers must use shared admission too.
Queue admission has its separately ordered lifetime. Worker wiring covers post
claim, provider polling/results, post
status and notification; scheduler retry/failure work is included. Coordinated
ownerless jobs fail closed. An unknown provider outcome can fulfill the worker
promise as `FAILED` while its internal `requiresReconciliation` signal retains
the owner ticket and makes scheduler readiness unavailable. A terminal status
alone is not proof that the provider has stopped processing.

## Compatible API behavior

No new public response field or reconciliation endpoint is introduced. Existing
`503 ACCOUNT_WRITE_DRAIN_FAILED` also covers durable drain timeout and an occupied
cleanup claim. The default drain polling budget is five seconds, with normal
SQL wait/timeout limits still applying; it does not bound or cancel the admitted
remote callback itself.

When this error follows a committed seal, the same-UID proof and `DELETING`
marker remain, while queue/provider/media/database/identity cleanup has not
started. A retry can proceed after known work finishes. A crash, unknown outcome
or unconfirmed release remains blocked until verified reconciliation. A local
FIFO timeout before authorization enters its transaction still creates no proof.
Readiness never creates deletion authorization, and a legacy `NULL` tombstone
still cannot authorize deletion.

## Local verification

Regression checks were added before implementation and observed failing before
their related fixes. Current focused checks cover admission/drain, original
authorization semantics, exact-token release, nested/closed contexts, child
lifetimes, unknown fulfilled worker outcomes, ownerless worker denial, worker
notification and HTTP/finally work.

- Core targeted checks: 50/50, including concurrent same-owner lifetimes.
- Worker/scheduler targeted checks: 53/53.
- HTTP/deletion targeted checks: 17/17, including disconnect, chaining and
  preflight/uncertain error handling. AI/HTTP integration: 79/79.
- Full API tests: 1,909/1,909 in 119 files, using one worker (83.78 seconds).
- Full test-inclusive typecheck, production build, Prisma schema validation,
  Prisma seed/config helper typechecking and `git diff --check` pass.
- Independent reviews found no blocker in admission/drain/claim, awaited and
  detached children, HTTP/finally/disconnect, concurrent lifetimes and worker
  unknown-outcome retention. At this local phase, hosted CI and the full mobile
  suite were not rerun;
  mobile source is unchanged and no new APK was built or installed.
- The initial parallel verification exhausted host memory. A bounded full pass
  then exposed whole-request serialization breaking the existing concurrent
  transcription quota test. Separate concurrent lifetime/ordered-write runners
  repaired it; the final full pass above has no failures or unhandled errors.
- Logs are retained under `D:/PostDeeMobile/.tmp/staging-followup/`, including
  `shared-owner-full-tests-final.log`, `shared-owner-types-final.log`,
  `shared-owner-build-final.log`, `shared-owner-schema-final.log` and
  `shared-owner-prisma-helpers-final.log`.

These targeted counts describe the corresponding verification runs; they are
not a substitute for the final full-suite receipt.

### Actual PostgreSQL and two independent processes

An isolated PostgreSQL 18.1 instance on `127.0.0.1:55444` applied all 18 actual
migrations. Two independent Node processes/Prisma clients exercised a parent-
owned loopback HTTP synthetic provider. Final result: **PASS, 10/10 checks**:

1. Isolated database/migrations and both durable barrier tables exist.
2. Two independent Node processes and a separate loopback mock provider run.
3. Consent and `DELETING` commit while an admitted remote callback is in flight.
4. Late admission fails without running its callback; another owner stays usable.
5. Unfinished work returns `ACCOUNT_WRITE_DRAIN_FAILED` without cleanup, keeping
   proof, user data and ticket.
6. Remote completion precedes cleanup; retry succeeds with the original proof.
7. Concurrent deletion admits one cleanup run while the other process blocks.
8. A callback exception retains a ticket and prevents destructive cleanup.
9. Killing the requesting process does not erase its admission; the parent mock
   provider still finishes, and even a year-2000 ticket blocks cleanup.
10. Two same-owner callbacks in one process start concurrently and create two
    tickets. Completing only the first leaves one ticket and cleanup blocked;
    completing the second allows cleanup. The final run uses concurrent
    `runWithOwnerLifetime`, matching HTTP/worker wiring.

Receipt:
`D:/PostDeeMobile/.tmp/staging-followup/shared-owner-lifetime-20261014-final/lifetime-receipt.json`.

SHA256:
`6ECB1C45F980FDBB8359C55642E255516FD4555958D37B62985D7BF07C61B6F4`.

Node PIDs `36492`/`34256`, PostgreSQL PID `33220` and provider parent PID `24260`
were owned test processes and are stopped; port 55444 is free. Evidence and local
unresolved fixture tickets remain for inspection. No live data, real Redis,
Firebase or social provider was used. The crash test demonstrates the local
fail-closed boundary, not a live-provider exploit or complete provider cleanup.

The preceding 9-check run remains unchanged in `shared-owner-lifetime-20261014`
with receipt SHA256
`2A64786967BC58A16C92C270D9701676E10C089A1918272FA4D790AEC775835A`.

## Rollout order and activation gates

Keep `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled` and the
existing single-instance Staging memory queue. No hosted migration or runtime
activation occurred during the local implementation phase. The later Staging
delivery below applies migration 18 while leaving feature activation disabled.

1. For any target environment, commit the additive migration before new code
   handles authenticated work, generate Prisma, and upgrade **every** API and
   worker process.
   Quiesce and drain older binaries before activation: they do not register their
   already-running work. Schema compatibility alone cannot cover such work.
2. Exercise actual Redis/BullMQ with separate API/worker processes, delayed
   effects, process crashes, queue acknowledgements and cleanup retry. The local
   PostgreSQL/HTTP fixture is not an actual Redis/provider acceptance test.
3. Test real Firebase and provider cleanup with explicitly approved disposable
   identities only. The user has no empty account and requested preparation
   only; creation steps remain in the
   [earlier account setup plan](2026-10-14-staging-regression-and-typecheck.md#prepare-a-disposable-staging-account).
4. Verify complete-upload/abort races and R2 cleanup, pending OAuth flows that
   can finish outside an API handler, and existing legacy signed-PUT cancellation
   or expiry. A PostgreSQL callback ticket cannot revoke an external bearer URL
   or guarantee completion of an independent browser/provider workflow.
5. Pass physical-device, slow-network and provider-specific acceptance before
   Production or multi-instance/separate-worker activation. Preserve the
   unaffected isolation owner and retained current app drafts/session.

## Private reconciliation requirements

No automated reconciliation endpoint, repair command or destructive SQL recipe
is introduced. For a future explicitly authorized controlled recovery:

1. Inspect private operation/claim metadata and the exact owner/run scope; retain
   redacted evidence without exposing credentials or signed URLs.
2. Establish that the original process cannot resume and verify the actual
   provider/storage/queue terminal result or confirmed cancellation. Process
   death and ticket age alone do not prove that a remote effect stopped.
3. Resolve any accepted remote work or cleanup uncertainty with dedicated test
   identities and an unaffected isolation control. Stop if the outcome remains
   unknown; do not stamp missing authorization or revive the owner.
4. Only after evidence and explicit approval, perform a narrowly scoped repair
   for the exact owner/ticket or cleanup run, then retry the normal authorized
   saga and verify cleanup. Preserve original same-UID proof and tombstones.

## ขั้นตอนถัดไปสำหรับผู้ใช้

งานนี้ทำให้ระบบรองานที่เริ่มไปแล้วข้าม process ได้ในชุดทดสอบภายในเครื่อง
หากงานไม่ทราบผลหรือ process ปิด ระบบจะหยุดลบบัญชีไว้ก่อนและไม่ปลดล็อกตามเวลา
ยังไม่เปิดลบบัญชีจริงหรือโพสต์จริง และยังไม่ได้สร้างบัญชีทดสอบใหม่
ส่งมอบบน Staging พร้อม migration 18 แล้วตามบันทึกด้านล่าง ขั้นถัดไปยังต้องทดสอบ
บริการจริงด้วยบัญชีว่างตามขั้นตอนที่เตรียมไว้
ก่อนเปิดใช้ลบบัญชีหรือเปลี่ยนข้อมูลจริง

## Main and Staging delivery (2026-10-14)

The user authorized branch push and CI, then main/push and Staging migration/
deployment. Source `7576ee3f98ed17a00664200c7a6b442e31f75059` includes typing
commit `1b5a403` and the shared-operation implementation. It was fast-forwarded
from verified `f07ee30` onto canonical main and pushed normally. Existing dirty
generated/QA files remain excluded and their six original hashes are preserved.

- [Feature CI `38514367627`](https://github.com/NOI56/PostDeeMobile/actions/runs/38514367627)
  and [main CI `38514981824`](https://github.com/NOI56/PostDeeMobile/actions/runs/38514981824)
  both pass on exact source `7576ee3`: 1,909 API tests in 119 files, 2,189 Mobile
  tests, test-inclusive typecheck, API build, Flutter analyze and Prisma schema
  checks. Catalog parity validates 100 templates and generator tests pass 22/22.
  CI does not apply the hosted migration and the optional APK steps were skipped.
  Production-filtered audit has four moderate findings and no high/critical.
  Dependency and action deprecation warnings remain for later maintenance.
- Staging service `srv-d9bb72ojs32c739osa5g`, exact-source deployment
  `dep-db7gsd3bc2fs73f64600`, is Live at **12:09:57 Asia/Bangkok**.
  Migration `20261014020000_track_owner_operations` completed at 12:09:04.753,
  before the upgraded API listened at 12:09:52.389. Actual `postdee_staging`
  has 18 applied migrations and both new tables. The post-smoke snapshot has
  zero operation tickets/cleanup claims, three users unchanged and zero owners
  with deletion authorization.
- Actual Staging configuration retains `FIREBASE_AUTH_DELETE_ENABLED=false`,
  `SOCIAL_PUBLISHER=disabled`, `PUBLISH_QUEUE=memory`, one API instance and
  Firebase authentication. The generic Production Blueprint was not applied.
  Health and authenticated account checks pass; deletion and publishing readiness
  still fail closed as configured. No separate worker was created or activated.
- The authenticated synthetic R2 fixture transfers one 30,199-byte part, returns
  HTTP 200 with matching ETag, recovers `UPLOADING` and then reaches `ABORTED`.
  Re-signing its aborted session returns 409 and the old signed PUT returns 404.
  No upload completion, AI provider, social posting or real-account deletion ran.
- Existing Staging package `com.postdee.postdee_mobile.staging`, versionCode 12019,
  is retained without a new APK/install. Shop → Home → Account → Shop checks
  preserve the same owner hash, whole-draft value hash and two shop links.
  Credentials, signed URLs and user identity are excluded from tracked evidence.
- Production remains user-suspended with no deployment or configuration change.
  No disposable account was created; its prepared procedure remains unexecuted.

Private local delivery evidence is retained in
`D:/PostDeeMobile/.tmp/shared-owner-delivery/`, including
`ci-feature-verification.json` and `render-live.png`. Feature verification receipt
SHA256 is `BCE6D70B5E41A18E2A2D73AE576D69FF99E54950DCFFA50912E7DD80BA228638`.
The earlier 10/10 local PostgreSQL receipt and original audit are preserved.

This delivery installs the barrier on the existing disabled Staging path. It
does not pass actual Redis/BullMQ, real Firebase/provider cleanup, upload
completion/abort races, pending OAuth, legacy signed-PUT or physical-device/
slow-network acceptance. Upgrade and drain every target API/worker process and
complete those gates before activation; unresolved tickets/claims never expire
by time or process death.
