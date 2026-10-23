# Billing security remediation: Batch 1

Original reproduction baseline: `6b06c63fba5504437b7f3577f1d3c7cf1a5ac467`.
Current integration baseline after rebase: latest verified `origin/main` at
`eee9e6ae1bdcbb4d465b9a243ee2aed7a93ca83c` (2026-10-23), including requested
runtime main `a391bc47cc8158a38e14041ee9723ba0ebf97ef9` and its subsequent
documentation-only release record. The owner-transaction retry/backoff and
startup fixes from a391bc4 are preserved.
Implementation branch: `codex/security-batch1-billing`, in its own clean worktree.
Only audit run-2 Batch 1 is in scope. Existing API request/response contracts,
mobile purchase readiness, trials, add-on quantities and non-expiry policy remain.

## Reproduction before implementation

Five local regression cases failed against the baseline on 2026-10-23, using
mock authentication, memory stores and injected subscriber responses:

- Sandbox Test Store Starter and Pro resync granted paid access in production.
- A sandbox subscription webhook was applied instead of acknowledged/ignored.
- The memory add-on ledger granted a production Test Store transaction.
- After destination Restore and a TRANSFER, both source and destination kept Pro.

These are local development reproductions, not deployed/provider acceptance
tests. No live customers, purchases, credentials or dashboards were used.

Independent RED confirmation repeated the regression test files from original
implementation commit `9717e7a` on
both original main `6b06c63` and latest pre-fix runtime main `a391bc4`, with
unchanged Git blob hashes. Both runs exited 1 with five behavioral assertion
failures (50 other cases filtered out), with no import/setup failure:

| Exact failing test title | Expected | Before-fix result |
| --- | --- | --- |
| `does not restore a sandbox Test Store starter subscription into production` | BASIC | STARTER |
| `does not restore a sandbox Test Store pro subscription into production` | BASIC | PRO |
| `acknowledges a sandbox subscription webhook without activating a production plan` | HTTP 202 | HTTP 200 |
| `does not grant production add-on credits from the Test Store` | Purchase rejected | Granted with `applied: true` |
| `revokes the source after restore transfers its subscription to another existing account` | Source BASIC, destination PRO | Both PRO |

Reproduce by adding the two committed regression files to an isolated worktree
at either pre-fix baseline and running:

```powershell
npm.cmd run test -- --maxWorkers=1 --no-file-parallelism src/modules/billing/revenueCatSubscriptionEnvironment.test.ts src/modules/billing/revenueCatTransferRoutes.test.ts -t '(does not restore a sandbox Test Store (starter|pro) subscription into production|acknowledges a sandbox subscription webhook without activating a production plan|does not grant production add-on credits from the Test Store|revokes the source after restore transfers its subscription to another existing account)$'
```

Local evidence is retained in the separate detached
`security-batch1-red-confirmation` worktree: `red-evidence.log`,
`red-evidence-a391bc4.log` and `RED-CONFIRMATION.md` in its parent folder.

## Change boundaries

- `REVENUECAT_SUBSCRIPTION_ENVIRONMENT` accepts `PRODUCTION` (default) or
  `SANDBOX`. Production Blueprint pins PRODUCTION; isolated Staging pins SANDBOX.
- Subscriber entitlement proof includes subscription `is_sandbox` and store,
  including lifetime purchases. Filter eligibility before choosing the paid plan.
- Production accepts App Store/Play Store only. Test Store requires SANDBOX for
  both subscription and add-on purchases. Missing proof fails closed.
- RevenueCat promotional entitlements without purchase provenance cannot grant
  paid access. A fresh promotional-only resync cancels an existing matching
  RevenueCat subscription; use the audited PostDee admin-console trial flow
  instead. Separately valid admin trials remain independent.
- Subscription lifecycle mismatch is ignored without advancing the cursor.
- TRANSFER uses source/destination arrays, re-reads existing active owners and
  reconciles through the shared owner barrier and durable per-user cursor.
  It never creates unknown users or grants from the transfer payload alone.
  Provider failures, stale snapshots and eligible unmapped access cannot trigger
  a guessed cancellation. Retry after resolving the provider/configuration issue.
- No schema migration or client update is required. No historical bulk revocation
  or credit backfill is performed. Existing subscription rows do not retain
  purchase provenance; add-on ledger rows already retain store/environment and
  can support the owner's separate historical review.

Provider shape references: [RevenueCat webhook event fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)
and [webhook reconciliation guidance](https://www.revenuecat.com/docs/integrations/webhooks).
TRANSFER environment/store are optional; subscriber readback supplies proof.

## Delivery and owner actions

Deliver as one reviewable PR; do not merge/push main, deploy, or change dashboards.
When separately authorized to release:

1. **Before deploying**, set `REVENUECAT_SUBSCRIPTION_ENVIRONMENT=SANDBOX` in
   the **Render dashboard for Staging**. The Blueprint declaration alone is not
   evidence that a live service has the value. Production must use PRODUCTION.
   Verify the separate add-on environment and server-only REST v1 key too.
2. Enable the **TRANSFER event** in the **RevenueCat webhook** that delivers
   to the target API. Confirm its URL/authentication, project/environment/app
   filters, matching product/entitlement IDs and restore/transfer behavior.
3. Deploy the API first, with no schema/mobile migration. Verify Staging sandbox
   purchase/restore, transfer source loss/destination access, independent source
   purchases, duplicate/out-of-order delivery and provider-failure retry behavior.
4. Review historical subscription/add-on grants for sandbox contamination before
   production acceptance; use separately authorized reconciliation, not a blanket
   revoke. This change does not retrospectively prove historical purchases.

Owner decisions recorded from the brief, intentionally not changed here:

- Enabling production account deletion requires the Firebase service account.
- Confirm RevenueCat project topology, webhook filters and restore behavior.
- Confirm the actual Render proxy hop count.
- Set a production database `ipAllowList` and decide the `npm ci` build switch.

Other batches and queued-post expiry, slug recycling and `listDue` investigation
remain separate work. Final command results belong in this batch's PR.

## Initial verification receipt before follow-up, 2026-10-23

- Initial regression run against the unmodified baseline: five expected
  assertion failures across environment isolation and transfer source revocation.
- Final targeted environment/transfer suites: 55 tests passed.
- Full API suite under pinned Node 22.23.3: 151 files passed, four opt-in
  database files skipped; 2,548 tests passed and 25 skipped. Dependencies were
  installed from the unchanged lockfile in this worktree; Prisma Client was
  regenerated from the current schema.
- API typecheck/build, Prisma schema validation and standalone seed/config
  TypeScript checks passed. No schema or migration change is included.
- Compiled API loopback smoke passed: health, real-store-shaped production
  grant, sandbox expiration isolation, transfer source BASIC/destination PRO.
  Authentication/storage/provider responses were local mocks, not live services.
- Production dependency audit returned zero reported vulnerabilities.
- Flutter analyze passed; full Flutter suite passed 2,767 tests, with six
  pre-existing opt-in cases skipped. No mobile source changes are included.
- Independent code review completed; a discovered owner-admission cleanup leak
  was fixed and covered before the final full run. `git diff --check` passed.

PostgreSQL integration tests require `POSTDEE_TEST_DATABASE_URL` and were not
run. Live RevenueCat/store behavior, project topology, dashboard settings and
Staging/production acceptance remain unverified. No deployment, dashboard
mutation, live purchase, main push or merge was performed.

## Follow-up verification after rebase, 2026-10-23

- Rebased onto requested runtime main `a391bc4`, preserving its owner-transaction
  retry/backoff and startup changes. Full API tests, typecheck, build and compiled
  loopback smoke passed again.
- Included the subsequent documentation-only main `eee9e6a`, then repeated all
  three requested API commands on that final baseline:
  `npm run test -- --maxWorkers=2 --no-file-parallelism`, `npm run typecheck`,
  and `npm run build` all passed under Node 22.23.3. Final full suite: 152 files
  passed / four opt-in database files skipped; 2,562 tests passed / 25 skipped.
- Added three explicit promotional-only resync cases: missing both provenance
  fields, missing `is_sandbox`, and missing `store`. Each verifies prior PRO,
  then a fresh lifetime promotional snapshot causing the matching subscription
  to become CANCELED and the purchased/effective plan to become BASIC. The
  environment/transfer regression files now cover 58 cases in total.
- Compiled API smoke passed after the final rebase. Independent review confirmed
  the tests, API policy, preserved main behavior and explicit rollout order.
- Updated API.md and related docs: RevenueCat promotional grants do not unlock
  paid access; grant trials through the audited PostDee admin console instead.
- PR description lists all five exact RED titles and before-fix assertions on
  both pre-fix baselines. It requires Render Staging dashboard SANDBOX first,
  then RevenueCat webhook TRANSFER enablement, before an authorized API deploy.
- Mobile source, Prisma schema and helpers, and dependency lockfile are unchanged
  by this follow-up. The earlier Flutter/Prisma/dependency-audit results above
  are retained as earlier checks, not described as new runs.

No dashboard values, deployments, production purchases, main push or merge were
performed. PostgreSQL opt-in and live provider/store acceptance remain unverified.
