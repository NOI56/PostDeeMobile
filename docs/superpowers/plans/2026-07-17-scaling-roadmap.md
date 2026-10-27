# PostDee Scaling Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve PostDee safely from the first paid customers to approximately 100, 1,000, 10,000, and 100,000 active users without rewriting the Flutter app or adding expensive infrastructure before it is needed.

**Architecture:** Keep the current Flutter + Express modular monolith + PostgreSQL foundation. Scale stateless APIs horizontally, move durable and expensive work to Redis/BullMQ workers, keep media direct-to-R2, and optimize PostgreSQL queries before considering service splits. Treat each usage tier as a measured capacity gate, not an automatic migration based on registered-user count.

**Tech Stack:** Flutter, Node.js, Express, TypeScript, Prisma, Render, Render PostgreSQL, Cloudflare R2, Upstash Redis, BullMQ, Firebase, RevenueCat, Gemini, Groq, PostPeer, and Sentry.

---

## Global Constraints

- Distinguish registered accounts, monthly active users, peak concurrent users, and queued jobs. These are not interchangeable.
- Do not upgrade infrastructure from registered-user count alone. Use CPU, RAM, p95/p99 latency, database connections and slow queries, queue delay/failures, provider limits, and recovery evidence.
- Keep Render while measurements and support requirements fit it. Re-evaluate vendors only when there is evidence of a limit or a contractual requirement.
- Keep video bytes out of PostgreSQL and normal API bodies. Upload/download media directly through signed Cloudflare R2 flows.
- Preserve user scoping, idempotency, and safe handling of uncertain PostPeer publishing outcomes.
- Keep mobile clients backward compatible during API changes. Support an overlap window before removing old contracts.
- Add a failing test before each behavior change, then implement the smallest safe change.
- Do not introduce Kubernetes, database sharding, active-active writes, or broad microservice decomposition before the 100,000-user decision gate proves they are needed.
- This is an umbrella plan. Create a narrower plan before a large subsystem such as async AI jobs, analytics rollups, or disaster recovery.

## Capacity Definitions

| Measurement | Meaning | Why it matters |
| --- | --- | --- |
| Registered accounts | Everyone who has ever signed up | Useful for business reporting, weak for capacity planning |
| Monthly active users | Users who open the app or perform a real action in 30 days | The tiers below refer primarily to this number |
| Peak concurrent users | Users sending requests at the same time | Drives API replicas, DB connections, and rate limits |
| Queue delay | Time a scheduled/AI job waits before processing | Drives worker count and isolation |
| Provider pressure | PostPeer, AI, push, R2, and billing quotas/errors | May become the limit before Render or PostgreSQL |

## Current Baseline

Useful foundations already exist: Prisma-backed stores, persisted managed multipart uploads with retries, BullMQ adapters and a separate worker runner, scheduled-job claim/reschedule protections, user-scoped routes, and relevant PostgreSQL indexes.

The main blockers to safe growth are:

- Production still selects an in-memory publish queue, so a restart can lose scheduled work.
- Rate-limit counters are process-local, so multiple API instances will not share one limit.
- Post and template list routes do not yet use bounded pagination.
- Analytics can load all platform-publish rows and aggregate/filter them in Node.js.
- AI media handling can buffer a full clip in memory, and expensive AI work is synchronous.
- API and worker processes do not yet complete graceful shutdown handling.
- Real push/Sentry evidence and repeatable load/soak tests are still missing.
- AI model names and fallbacks require an explicit lifecycle and upgrade process.

## Milestone Summary

| Active-user planning tier | What must be true before calling it ready |
| ---: | --- |
| Up to 100 | Durable scheduling, paid DB recovery, real push, bounded AI media, provider E2E evidence, and monitoring |
| Up to 1,000 | Safe multiple API instances, shared rate limits, pagination, bounded DB connections, graceful shutdown, and load/soak evidence |
| Up to 10,000 | Durable async AI jobs, isolated worker pools, database-side analytics/usage rollups, retention, and metric-based scaling |
| Up to 100,000 | Fresh enterprise review from at least 30 days of real 10,000-user metrics, plus HA/DR, API lifecycle, security, staffing, and support decisions |

## Task 1: Make Publishing Durable Before 100 Active Users

**Files:** `render.yaml`, `apps/api/src/config/env.ts`, `apps/api/src/config/env.test.ts`, `apps/api/src/server.ts`, `apps/api/src/workers/publishWorkerRunner.ts`, and existing BullMQ/Render tests.

- [ ] Add failing tests that reject production using the memory queue and verify the worker receives Redis configuration.
- [ ] Set production to `PUBLISH_QUEUE=bullmq`, provide `REDIS_URL`, and enable a separate publish worker. Keep memory mode for local/tests only.
- [ ] Handle `SIGTERM`/`SIGINT`: stop accepting work, close BullMQ/Redis/HTTP/Prisma, and allow an in-flight job to finish within a deadline.
- [ ] In Staging, schedule a post, restart API and worker separately, and confirm exactly one publish attempt at the correct time.
- [ ] Run focused tests, `npm.cmd run test`, `npm.cmd run build`, and Prisma validation.

## Task 2: Bound AI Memory and Model Risk Before 100 Active Users

**Files:** mobile upload/AI client flow; `apps/api/src/modules/ai/captionRoutes.ts`; media helpers; Gemini/Groq factories; environment validation; tests.

- [ ] Test maximum audio size, MIME type, ownership, timeout, and provider failure mapping.
- [ ] Extract/compress audio on the phone where practical and upload the small artifact through managed R2 instead of loading a full video into the API.
- [ ] Stream or strictly bound any server download that remains. Do not hold a 200 MiB clip in memory.
- [ ] Replace unsupported model fallbacks with configurable supported models and document a deprecation/upgrade check.
- [ ] Verify on low-memory Android, normal Android, iOS if available, and real Gemini/Groq test credentials without logging media or secrets.

## Task 3: Complete Push, Monitoring, and Provider Evidence Before 100 Active Users

**Files:** `render.yaml`, API startup/worker files, Firebase push wiring, mobile startup, `docs/GO_LIVE.md`, and `docs/STAGING_CHECKLIST.md`.

- [ ] Wire real Firebase push for production and retain the mock adapter for local tests.
- [ ] Add Sentry (or equivalent) to API, worker, and mobile with secret, token, caption, and media URL redaction.
- [ ] Record controlled E2E evidence for R2, PostPeer, RevenueCat, Firebase, Gemini, and Groq.
- [ ] Alert on elevated 5xx, publish failures, queue delay, worker death, DB saturation, provider quota errors, and billing webhook failures.

## Task 4: Make Multiple API Instances Safe Before 1,000 Active Users

**Files:** `apps/api/src/modules/security/rateLimit.ts`; Prisma configuration; environment schema/tests; server/worker lifecycle; `render.yaml`.

- [ ] Replace process-local production rate limits with Redis-backed counters while keeping an in-memory test adapter.
- [ ] Add bounded Prisma connection settings appropriate to the DB plan and number of API/worker instances.
- [ ] Make publish-worker concurrency configurable, defaulting conservatively until provider limits are measured.
- [ ] Prove two API instances share rate limits and do not duplicate scheduled jobs during deploy/restart.
- [ ] Dashboard CPU/RAM, DB connections/slow queries, Redis errors, queue depth/delay, and provider latency/errors.

## Task 5: Add Pagination and Mobile Backpressure Before 1,000 Active Users

**Files:** post/template stores, repositories, routes, mobile API client/screens, tests, and `API.md`.

- [ ] Add cursor pagination with default 20, maximum 100, and stable ordering by `createdAt` plus `id`.
- [ ] Preserve an overlap window for older mobile clients and document the final response contract before removing compatibility code.
- [ ] Add incremental loading so mobile does not request or render an unbounded history.
- [ ] Add jittered backoff for safe idempotent reads on `429`/`503`. Never automatically repeat a publish with an uncertain outcome.
- [ ] Test next-page, empty-page, deleted-row, duplicate-boundary, offline, and retry behavior.

## Task 6: Create a Repeatable 1,000-User Load and Soak Gate

**Files:** new scripts under `apps/api/scripts/load/`, `apps/api/package.json`, and `docs/GO_LIVE.md`.

- [ ] Create Staging-only load scripts using synthetic users and mock/sandbox providers so tests cannot publish to customer accounts.
- [ ] Cover authenticated reads, upload-session creation, post creation, scheduling, cancel/reschedule, quota checks, and webhook bursts.
- [ ] Run a 60-minute soak with at least two API instances and one worker.
- [ ] Initial pass budget: p95 below 1,000 ms, 5xx below 1%, no duplicate publish, DB connections below 70%, memory below 80%, and queue delay below 60 seconds.
- [ ] Store the dated scenario, commit, configuration, and result; tune from evidence rather than treating these initial thresholds as permanent promises.

## Task 7: Move Expensive AI Work to Durable Jobs Before 10,000 Active Users

**Files:** new AI-job module/worker, Prisma schema/migration, AI routes, mobile job-status UI, `render.yaml`, tests, and `API.md`.

- [ ] First write a narrower AI-job plan covering the data model, quotas, cancellation, privacy, retention, and failure UX.
- [ ] Persist `QUEUED`, `RUNNING`, `SUCCEEDED`, `FAILED`, and `CANCELED` with user scope and idempotency keys.
- [ ] Return a job ID quickly; let mobile poll with backoff or receive push completion instead of keeping a long HTTP request open.
- [ ] Separate publish, AI, notification, and analytics workers so AI bursts cannot delay scheduled posts.
- [ ] Add bounded retries, dead-letter handling, artifact cleanup, quota reservation/refund, and restart recovery tests.

## Task 8: Move Analytics and Usage Aggregation Into PostgreSQL Before 10,000 Active Users

**Files:** analytics/usage repositories, Prisma schema/migrations, rollup worker, tests, and retention/account-deletion docs.

- [ ] Filter ranges and aggregate views/likes/posts in SQL instead of loading an entire user history into Node.js.
- [ ] Add daily/monthly rollups for analytics and AI/post usage where query evidence shows they are needed.
- [ ] Build bounded resumable backfills and verify query plans with realistic volumes before adding indexes.
- [ ] Define retention/deletion for raw media, derived audio, AI artifacts, job logs, analytics events, and account deletion.
- [ ] Load-test queries and keep PostgreSQL as source of truth before considering a separate analytics database.

## Task 9: Make the 100,000-User Enterprise Decision From Evidence

**Files:** create a fresh dated architecture decision and narrower subsystem plans when this gate is triggered.

- [ ] Collect at least 30 days of real 10,000-user traffic: concurrency, latency, egress, slow queries, DB/Redis saturation, queues, provider limits, incidents, and support workload.
- [ ] Compare current Render, an appropriate managed/enterprise option, and one credible alternative by total cost, migration risk, staffing, support, and Thai-user latency.
- [ ] Keep the modular monolith unless profiling proves a domain needs independent scaling or failure isolation.
- [ ] Add DB HA/read replicas, partitioning, or service extraction only when measured query/write/recovery evidence justifies it.
- [ ] Define tested backup/restore, RTO/RPO, incident ownership/on-call, API version support, feature flags, security, data residency, and provider contracts.
- [ ] Do not promise 100,000-user readiness until representative peak, failure, and disaster-recovery tests pass.

## Task 10: Synchronize Documentation at Every Completed Gate

**Files:** `ROADMAP.md`, `ARCHITECTURE.md`, `README.md`, `API.md` when contracts change, `docs/GO_LIVE.md`, `docs/STAGING_CHECKLIST.md`, and `LAUNCH_CHECKLIST.md` when operational truth changes.

- [ ] Record the achieved gate, dated measurements, and infrastructure configuration that passed.
- [ ] Update API docs only when a real contract is implemented; do not describe planned pagination or job endpoints as live.
- [ ] Keep public claims limited to features and capacity with end-to-end evidence.
- [ ] Run full API test/build/Prisma checks and Flutter analyze/test before marking an implemented gate complete.

## Self-Review Result

- The plan scales the existing architecture first and delays expensive complexity.
- The first mandatory change is durable BullMQ scheduling; adding API replicas before that would make production behavior less predictable.
- The biggest code risks are full-media AI buffering, process-local coordination, unbounded list/analytics queries, and long synchronous jobs.
- Exact server sizes and monthly costs are intentionally not promises because prices and capacity change. Select upgrades from measured usage and current vendor pricing.
- No application or infrastructure change is made merely by adding this document.
