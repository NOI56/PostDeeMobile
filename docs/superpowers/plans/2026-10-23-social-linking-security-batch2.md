# Security Batch 2: social account linking

## Scope and baseline

The user authorized merging PR #18 using a merge commit without force-push,
then a new Batch 2 branch and one PR only. PR #18 is MERGED at
`5313f262a25dd30e64bc7a77b7eb7fe7b865c71b`, including its original head
`1eddc7579158bab0979eb9e8a40f733742838095`. The merge message includes
`[skip render]`. The new `codex/security-batch2-social-linking` branch starts at
that exact main; the older primary checkout was not modified.

Before opening the PR, main advanced to
`4a1c0f9c1d77d622460bc9eb0d3d82eaf81f52cf`. The unpublished Batch 2 branch
was rebased onto it without force-push. Three documentation header conflicts
were resolved by preserving the new security sections and main's delivered
compact-caption release notes. Main's Mobile outline-only selector change and
tests remain intact; full validation is repeated on the rebased branch.
Main subsequently added documentation-only release notes at
`4f2242000d0b49bae9bdbfaa04a27be107474991`; those were also rebased before
the first feature push. Runtime, schema and test files are byte-for-byte
unchanged by that final documentation-only rebase.

Implement only Social account linking from `CODEX-FIX-BRIEF.md` and the trace
`apps/api/socialConnections/connect-url-completion-not-bound-to-initiating-user`
in the user's `run-2/NEEDS-VALIDATION.md`. No other security batch is included.
No Batch 2 merge, deploy, dashboard change, real OAuth, publication, account
reassignment or app installation is authorized.

## Reproduced failures before implementation

On unchanged main `5313f26`, real Express route tests with synthetic auth/provider
fixtures failed for:

- `does not import a newly listed integration when the user has no connect attempt`
  (unexpected connection saved).
- `rejects a new integration whose externalAccountId belongs to another user`
  (200 instead of 409).
- `rejects a new integration whose postPeerAccountId belongs to another user`
  (200 instead of 409).

The normal same-user connect/refresh test passed before the fix. Three memory
tests also failed: `rejects claiming another owner external social account`,
`rejects claiming another owner PostPeer integration even with a different external id`
and `allows exactly one owner when two users race to claim a social account`.
The last admitted two owners. Both Prisma P2002 mapping tests failed by exposing
the raw error instead of the domain conflict. These were assertion failures,
not missing imports or unavailable dependencies.

Before Mobile edits, both widget tests failed to find Thai recovery guidance:
`social account ownership conflict on connect explains recovery in Thai` and
`social account ownership conflict on refresh explains recovery in Thai`.

After the initial fix, four additional concurrency regressions were written
and observed failing before their respective fixes:

- `does not let a stale ordinary refresh overwrite a newer completed connection`
- `does not let a stale ordinary refresh disconnect a newer completed connection`
- `does not apply an old provider snapshot to a connection completed while polling`
- `does not let a delayed explicit disconnect remove a newer connection or its next attempt`

## Implementation

- `socialConnectionRoutes.ts`: pre-URL baseline snapshot, 32-byte random nonce,
  SHA-256 hash, 15-minute expiry and authenticated owner/platform/profile scope.
  New attempts replace the same user's same-platform attempt; failed URL
  creation only cancels the matching hash. Return a no-store
  `{status, connectUrl, nonce, expiresAt}` response.
- Refresh admits one fresh integration only with the correct valid attempt.
  Zero candidates remains pending, multiple candidates fail closed, and replay,
  expiry, profile mismatch or another user's nonce is rejected. The response
  adds `connectAttemptConsumed` when a nonce is supplied. Legacy refresh only
  maintains exact existing identities and cannot recover/import unbound ones.
- Memory and Prisma stores enforce uniqueness. Prisma uses active-owner-fenced
  serializable transactions for nonce consumption plus write; an ownership
  conflict rolls back consumption. Conditional maintenance protects newer links
  from old provider snapshots and leaves pending attempts intact. Explicit
  disconnect snapshots both connection and pending nonce before the provider
  call, then conditionally cleans up only those captured identities on success.
- Mobile validates the new contract before browser launch, retains pending
  attempts across a transient network failure, clears them on terminal events
  or owner switch, and maps safe 409 codes to Thai recovery text. Browser and
  deep-link parameters never supply ownership evidence.
- Shared typed repository fixtures include the new Prisma delegate. Regression
  tests cover existing routes, memory/Prisma contracts, real PostgreSQL
  concurrency, nonce rollback, stale maintenance and account deletion fences.
- API.md, ARCHITECTURE.md, README.md and ROADMAP.md describe the new contract,
  compatibility, migration and provider limitations.

## Migration and duplicate evidence

`20261023010000_bind_social_connect_attempts` adds `SocialConnectAttempt` with
User cascade deletion, `(userId, platform)` primary key and unique `nonceHash`;
it also adds unique `(platform, externalAccountId)` (null allowed) and globally
unique `postPeerAccountId`. Attempts are bounded to one per user/platform.

`apps/api/prisma/social-linking-preflight.sql` is read-only and reports both
duplicate key groups, their connection IDs and owner counts. Both result sets
must be empty. The migration locks SocialConnection and repeats those checks
inside its transaction before creating any object. It never deletes, transfers
or rewrites customer connections.

Local PostgreSQL 18.1 on dedicated loopback port 55482 applied all 23 migrations
successfully to a fresh synthetic database. Two separate legacy-schema fixtures
each contained two conflicting connections: one duplicated platform/external ID,
the other duplicated provider integration ID across platforms. Preflight found
each correct group, and migration aborted with SQLSTATE 23505 in both cases.
Both rows remained and neither attempt table nor either index was created.

Actual hosted duplicate counts were not confirmed. The read-only Staging query
was blocked by its empty external IP allowlist; Production is suspended. No
allowlist, suspension, dashboard or customer data was changed. Those limitations
are a release gate, not evidence that duplicates are absent.

## Validation record

Final checks on the rebased runtime, using Node 22.23.3:

| Check | Observed result |
| --- | --- |
| API `npm run test -- --maxWorkers=2 --no-file-parallelism` | 2,652 passed / 25 skipped; 154 files passed / 4 legacy DB suites skipped. |
| Focused social linking suites | 141 passed, including 12 real PostgreSQL cases. |
| API `npm run typecheck`, `npm run build` | Passed. |
| Prisma schema validation, seed/config standalone TypeScript | Passed. |
| Fresh local migrations, migration status, schema diff | All 23 applied; up to date; no schema difference. |
| Compiled API loopback smoke | Health, no-attempt rejection, same-user completion, replay, ownership collision and provider-first disconnect passed. |
| Flutter `analyze --no-pub` | No issues. |
| Flutter `test --no-pub --concurrency=2` | 2,815 passed / 6 skipped. |
| Independent source review and `git diff --check` | Passed within the Batch 2 scope; known provider limitations remain below. |

Local tests use synthetic users and a dedicated guarded PostgreSQL database;
they do not contact PostPeer or consume purchases/publishing/AI quota. The
scratch PostgreSQL instance was stopped after verification; the host's existing
database service was not modified. No APK/native-device or live provider
verification is claimed.
The real database suite is opt-in using
`POSTDEE_SOCIAL_LINKING_TEST_DATABASE_URL` and guards the dedicated loopback
protocol, host, port and database path. The local fixture uses
`postgresql://postdee_test@127.0.0.1:55482/postdee_batch2_test?schema=public`.
The unrelated legacy opt-in DB suites remain skipped unless their own fixtures
are explicitly configured; they are not implied to have run.

## Required rollout order (owner action after separate authorization)

1. Run the read-only preflight internally against **each** intended database.
   Keep connection/account IDs private. If either result is nonempty, stop:
   verify ownership with affected users and PostPeer, and prepare an explicitly
   reviewed repair/reconnect plan. Do not auto-delete or reassign data.
2. After conflict resolution and backup/maintenance planning, apply the migration
   and updated API. The checked-in Render Blueprint uses a Prisma pre-deploy
   command; inspected Staging instead runs Prisma first in its start command.
   Both must complete migration before the new API starts; a guard failure must
   stop rollout. If Prisma records a failed
   migration, verify rollback and conflict resolution before any operator-led
   `migrate resolve`; do not mark an unapplied migration as applied.
3. Check API connectivity and owner-scoped synthetic linking behavior, then
   distribute updated Mobile. Existing saved connections remain readable, but
   old Mobile cannot complete new links without submitting its nonce. No new
   environment variable or provider dashboard setting is needed by this code.
4. Validate real disposable provider accounts only with separate authorization.
   If any gate fails, stop the rollout and investigate; preserve ownership
   constraints/attempt records rather than dropping them to restore imports.

Batch 1 prerequisites remain independent: Staging needs its explicitly chosen
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT=SANDBOX` before a future Batch 1 deployment,
and RevenueCat TRANSFER delivery must be enabled by the owner. They were not
changed by this task.

## PostPeer validation and residual limits

- Confirm connect URL lifetime/single use and browser/profile binding, consent
  identity presentation, signed/echoed completion state and profile isolation.
  The local nonce only gates admission by the initiating authenticated app;
  it cannot prove that a different human consenting through a forwarded URL is
  that same initiator. An otherwise-unbound social account remains exposed to
  that provider-dependent shared-link scenario. Do not claim complete phishing
  or initiating-human protection.
- Confirm every platform supplies a stable physical-account `platformUserId`,
  including Facebook Page Video. If missing, uniqueness only detects identical
  provider IDs and cannot recognize different integrations for the same account.
- Verify connecting one social account across PostPeer profiles and replacing
  or reconnecting an account. The baseline intentionally rejects pre-existing
  IDs. An unbound integration whose ID PostPeer reuses needs operator/provider resolution;
  do not disable the baseline check to make it pass. Already-saved exact
  identities remain maintainable without a new attempt.
- Closing/restarting the app loses its in-memory nonce. A provider integration
  completed before that loss is not imported by a new attempt's baseline. Real
  reconnect and cleanup guidance needs owner/provider validation.
- If completion succeeds but the response is lost, retry returns an expired or
  replayed attempt; ordinary refresh can read the already-saved connection.
  Check status before reconnecting. This patch adds no consumed-nonce ledger.
- No live PostPeer connect/refresh or cross-profile flow was executed. These
  external checks remain open, separate from passing local regression tests.

## Deployment monitoring

Read-only Render inspection after the PR #18 merge showed no new deployment:
Staging auto-deploy is off and its latest live source remains `dab94fb`;
Production is suspended. No build/deploy event was observed for the merge.
The merge's `[skip render]` follows Render's documented auto-deploy skip marker.
This task did not trigger a deployment or alter any dashboard.
Read-only service inspection also confirmed PR previews are disabled on both
services; opening this feature PR does not request a preview deployment.
