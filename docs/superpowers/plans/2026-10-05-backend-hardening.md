# Backend hardening — historical baseline and current port

## Original isolated work (2026-10-05)

This record was originally written in the isolated `codex/backend-hardening`
worktree, based on main `1451dd26627f3d85f35d24fc5dcbe5a32430847c`. Its baseline
was 1,106 API tests in 92 files. It was not pushed or deployed then. These
historical results must not be presented as verification of current main.

The original local work covered trusted-proxy/IPv6 rate-limit keys, compatible
dependency refresh, bounded read-only `/ready`, graceful shutdown and startup
recovery from complete terminal publish records. It preserved profile links,
caption/upload contracts, quota/idempotency, target settings, managed uploads,
account deletion and the PostPeer activation guard. No migration, provider
activation, Mobile change or Render change was part of that old scope.

The original recorded final API suite was 1,137 tests in 95 files, with build,
Prisma/helper checks and an audit of zero vulnerabilities on that old lockfile.
A Windows mock-safe entry-point smoke checked health/readiness, anonymous 401s
and orderly SIGTERM. Linux CI, live credentials/database/provider failure
recovery and physical devices were still unverified. Those numbers and audit
are historical only.

## Port into the current integration (2026-10-08)

The genuine runtime findings are ported onto `b1f793c`, which already includes
the current profile layouts, full-screen composer, running-dot navigation and
mobile cleanup. The old dependency refresh and `deepmerge-ts` override are
**not ported**: package files/lock stay on the current baseline. No current
zero-vulnerability claim follows from the old audit.

- Use trusted-proxy `req.ip` and the existing IPv6 `/56` helper for per-route
  limits. Counters remain process-local; this is not shared rate limiting.
- Add `/ready` with constant read-only DB/queue probes, two-second response
  deadline, single-flight underlying work, no caching and redacted failures.
  `/health` and config-only publishing readiness preserve their contracts.
- Stop scheduler claims/HTTP intake, mark unavailable, drain publishing and
  requests, then close queue/Prisma with a 30-second shutdown deadline.
- Inspect interrupted `PUBLISHING` rows before the memory scheduler starts.
  Finalize only when every platform has a saved terminal result; a successful
  result requires a provider/external id, delivery outcome and valid published
  timestamp. Unknown/missing evidence leaves the row untouched, never requeues
  or calls the provider, and keeps readiness unavailable for reconciliation.
- A provider call followed by a receipt/status persistence error also makes
  the scheduler unavailable. Complete durable receipts can be recovered later;
  missing evidence requires operator confirmation, not a second publish.
- Existing owner barriers and activation guards remain in place. Separate
  mutating-read owner-guard and Home-preview additions are recorded in the current
  integration plan, not attributed to the old isolated branch.

Current ownership/files: `app.ts`/`server.ts`, `readiness.ts`, `shutdown.ts`,
post stores, queue adapters, rate limiter, scheduler/worker and
`interruptedPublishRecovery.ts`, with their focused regression tests. Current
targeted hardening evidence is 110 tests in 14 files plus build; root wiring has
its own 49-test owner-guard run. The completed current full suite is 1,609 tests
in 107 files, with build/schema/helper checks; source `36dbacc` is pushed/on
main. Exact-source CI `37754460435` passed API/Mobile jobs; its main-push APK
step was intentionally skipped. Current locally built APK/native/delivery
receipts are recorded in `2026-10-08-integrate-pending-main-work.md`.
No live API deployment is asserted here.

## Remaining release/scale work

1. At a separately authorized API release, retain the existing one-instance
   topology/flags and verify target SHA, `/health`, `/ready`, auth/adapters and
   unchanged migration state. This port needs no new schema migration.
2. Use dedicated accounts for controlled upload/caption/profile/publishing and
   orderly shutdown/restart checks. Confirm destination results around provider
   acceptance; local mocks cannot prove no duplicate external publication.
3. Reconcile unknown outcomes under maintenance using provider/destination
   evidence. Restore readiness after a verified resolution and restart. An
   automatic reconciler would need durable per-attempt receipts and proven
   provider lookup/idempotency before it could be added safely.
4. Before multiple API instances or a real independent worker, provide shared
   mutation/deletion coordination, rate counters and worker health/lease/drain
   behavior. Current local locks and evidence-only startup recovery are not
   those cross-process guarantees. Real PostgreSQL/Redis outage and worker
   stalled-job/drain evidence remains a release gate.
