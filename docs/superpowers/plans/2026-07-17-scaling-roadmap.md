# PostDee future capacity roadmap

Original proposal: 2026-07-17. Reconciled against the active product and source
integration `36dbacc` on main on 2026-10-08. **Future plan only:** this document enables no worker,
API replica, service subscription, provider, feature flag or database migration.
No customer-count capacity claim has been verified by this plan.
The source integration's exact API/Mobile CI `37754460435` passed; those results
verify source behavior, not any capacity tier or activated scaling infrastructure.

## Product and runtime baseline

Keep Flutter and the Express modular monolith, Prisma/PostgreSQL, direct signed
R2 media access, Firebase, RevenueCat, Gemini captions and guarded PostPeer
publishing. The active product is upload/caption/publish/schedule plus profile
links; AI video editing/Subtitle Studio are inactive compatibility modules.
Groq is rejected by runtime configuration. New cross-platform statistics
ingestion and paid analytics providers are deferred, not scaling prerequisites.

Useful foundations include persisted scheduled posts, managed uploads,
idempotency and target snapshots, owner-scoped routes, a BullMQ adapter and
worker runner, Firebase analytics/crash reporting, and current local lifecycle
hardening. Backend Sentry is still a proposal. See
`2026-10-08-integrate-pending-main-work.md` for implementation/test/delivery facts.

The deployed memory scheduler polls durable Prisma records, so a restart does
not inherently lose the scheduled post rows. Execution and owner/rate-limit
coordination are still local to one API process. Bounded `/ready`, shutdown and
complete-receipt recovery reduce failure ambiguity; they do not provide a
distributed owner barrier, worker heartbeat or proven provider crash recovery.
Keep the one-instance topology until those guarantees are implemented/tested.

Home media previews now opt in to a bounded latest-post list; that is not full
cursor pagination of post/template history. Existing expensive queries, media
buffering and provider limits must be measured before deciding what to optimize.

## Capacity gates

Distinguish registered accounts, monthly active users, peak concurrency, queued
jobs and provider pressure. Tier numbers below organize future work; they are
not automatic infrastructure triggers or supported-user promises.

| Planning tier | Evidence required before expanding |
| ---: | --- |
| Around 100 active users | Real auth/upload/caption/billing/publishing evidence, recovery drills, measured memory/latency/provider budgets and tested backup restore |
| Around 1,000 | Shared owner coordination/rate counters, bounded DB pool and history queries, worker drain/lease health, representative load/failure evidence |
| Around 10,000 | Measured need for isolated durable jobs, rollups/retention and autoscaling; safe retries/deletion across every active worker |
| Around 100,000 | Fresh architecture/operations review using sustained traffic, failure and cost evidence, staffed incident response and tested HA/DR |

## Future tasks — not activated

- [ ] Measure CPU/RAM, p95/p99 latency, DB connections/slow queries, queue delay,
  provider limits/errors and recovery evidence. Define pass budgets from those
  results rather than from registered-user counts.
- [ ] Before enabling separate BullMQ workers or multiple APIs, implement a
  durable shared owner mutation/deletion barrier or equivalent outbox/claim and
  drain boundary spanning API writes, provider calls and deletion. Verify stale
  leases, in-flight account deletion, reschedule/idempotency and uncertain
  provider acceptance with no duplicate destination posts.
- [ ] Add shared production rate counters, bounded Prisma connections and
  worker heartbeat/health. Select Redis/worker settings only after observed
  backlog and provider concurrency justify them. Preserve local test adapters.
- [ ] Add stable owner-filtered cursor pagination and mobile backpressure where
  full history is still unbounded. Keep overlap compatibility for old clients;
  retries of safe reads must never silently repeat an uncertain publish.
- [ ] Bound caption media downloads and benchmark memory on small Android
  devices/server instances. Use a supported-model lifecycle process for active
  Gemini captions; do not restore Groq or the removed AI editor from this plan.
- [ ] Create load/soak/failure scenarios with synthetic accounts and mock/sandbox
  providers. Include authenticated reads, upload sessions, scheduling,
  cancel/reschedule, quota checks and webhook bursts. Record exact source,
  configuration and results without touching customer posts or generating real
  provider charges by default.
- [ ] Test backups/restore and define RTO/RPO, retention/account deletion and
  incident ownership. Add backend observability with sensitive-media/token
  redaction only through a separately scoped implementation.
- [ ] If measured caption load requires async jobs, write a narrower plan for
  persisted state, quota reservation/refund, cancellation, cleanup and restart
  recovery before adding schemas/workers. Active publishing takes priority;
  inactive editing workflows are not reintroduced.
- [ ] If analytics becomes a separately approved product feature, design
  provider access/cost, timestamp freshness and bounded SQL aggregation then.
  Do not buy metrics APIs or implement analytics workers under this capacity
  plan alone.
- [ ] Review managed service cost/operational support from actual workload
  evidence. Preserve the modular monolith unless profiling justifies isolation;
  Kubernetes, sharding and broad microservices require their own demonstrated
  need and decision record.
- [ ] At each completed gate, synchronize README, ROADMAP, API, ARCHITECTURE,
  GO_LIVE and STAGING with exact test/live limitations. Refresh this proposal
  instead of treating an unchecked historical task as missing product behavior.

## Release boundaries

Source tests do not replace live PostgreSQL/Redis/provider/device checks. API
readiness is narrower than provider readiness and does not prove an independent
worker is running. Do not horizontally scale the memory scheduler or infer safe
account deletion across processes from local owner locks. Do not automatically
resend unknown provider outcomes. Service prices, provider capability and model
availability must be rechecked when a concrete implementation is approved;
this proposal assumes no current price or free unlimited quota.
