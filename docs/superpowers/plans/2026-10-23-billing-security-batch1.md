# Billing security remediation: Batch 1

Baseline: latest `origin/main` at `6b06c63fba5504437b7f3577f1d3c7cf1a5ac467`.
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

## Change boundaries

- `REVENUECAT_SUBSCRIPTION_ENVIRONMENT` accepts `PRODUCTION` (default) or
  `SANDBOX`. Production Blueprint pins PRODUCTION; isolated Staging pins SANDBOX.
- Subscriber entitlement proof includes subscription `is_sandbox` and store,
  including lifetime purchases. Filter eligibility before choosing the paid plan.
- Production accepts App Store/Play Store only. Test Store requires SANDBOX for
  both subscription and add-on purchases. Missing proof fails closed.
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

1. Confirm separate production/test project and webhook configuration, matching
   product/entitlement IDs and restore/transfer behavior in RevenueCat.
2. Set subscription environment explicitly before the API rollout: SANDBOX for
   isolated Staging, PRODUCTION for production. Verify the separate add-on
   environment too. Keep the REST v1 key server-only and available for TRANSFER.
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

## Local verification receipt, 2026-10-23

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
