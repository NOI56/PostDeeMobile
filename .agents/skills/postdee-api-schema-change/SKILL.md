---
name: postdee-api-schema-change
description: Change a PostDee API route, request or response shape, Prisma model, or migration while keeping installed Mobile builds and existing data working. Use for backend contract or database changes in apps/api; not for UI-only work.
---

# PostDee API and schema changes

Installed Mobile builds keep calling the API after a deploy, and the Staging and Production databases hold real rows. Every change must work for old clients and existing data first.

## Before editing

- Find every caller: the Mobile client (`apps/mobile/lib/core/network/postdee_api_client.dart` and feature services), the admin console (`apps/api/src/modules/admin/web/admin.js`), workers in `apps/api/src/workers/`, and tests.
- Find the newest section in `API.md` that describes the route. `API.md` is a newest-first history log; older sections can be stale.
- For a persisted feature, locate both the memory store and the Prisma repository and the factory that picks between them by `*_STORE`.

## Compatibility rules

- Add fields as optional, and keep accepting the old request shape until the owner retires the old builds. Do not rename or remove a response field that a shipped Mobile build reads.
- Deploy order is API first, then Mobile. State it in the change summary and in `API.md`.
- Keep user scope on every query: a user-owned route reads and writes only the authenticated user's rows.
- Error responses use a stable `code` (for example `IDEMPOTENCY_KEY_REUSED`, `AI_EDITING_RETIRED`). Mobile branches on codes, so do not change an existing one.

## Prisma changes

- Edit `apps/api/prisma/schema.prisma`, then add a migration folder `apps/api/prisma/migrations/<YYYYMMDDHHMMSS>_<snake_case_name>/migration.sql`, following the existing folders. Generate it with `npm.cmd run prisma:migrate:dev` only against a disposable local database, never Staging or Production.
- Migrations must be safe on populated tables: add nullable columns or columns with defaults, backfill in SQL when needed, and never drop or rewrite user data without an approved plan.
- A new user-owned model must relate to `User` with `onDelete: Cascade`, or be cleared explicitly by account deletion (`apps/api/src/modules/account/`), with a test. Account deletion relies on the cascade.
- Run `npm.cmd run prisma:generate` and `prisma:validate` (needs a `DATABASE_URL`; the local value is in `AGENTS.md`), plus the `tsc` check for `prisma/seed.ts` and `prisma.config.ts` from `AGENTS.md`.
- On Render, `preDeployCommand` runs `prisma migrate deploy` before the new code starts.

## Database tests are opt-in

The default `npm.cmd run test` skips real-PostgreSQL tests (`describe.skipIf`). A green default run says nothing about SQL, transactions, or migrations. Run the affected suites with their variable set. Most suites refuse any URL except their dedicated loopback fixture, so the host, port, and database name must match exactly:

| Variable | Required fixture | Suites |
| --- | --- | --- |
| `ADMIN_TEST_DATABASE_URL` | `127.0.0.1:55439/postdee_admin_fixture` | admin, admin usage, admin account deletion, service incidents, support chat |
| `POSTDEE_TEST_DATABASE_URL` | `127.0.0.1:55441/postdee_addon_test` | monthly add-on, store-link slug reservation, post claim |
| `POSTDEE_SOCIAL_LINKING_TEST_DATABASE_URL` | `127.0.0.1:55482/postdee_batch2_test` | social connection linking |
| `POSTDEE_ADDON_DB_TEST_URL` | no guard; use a disposable database | non-expiring add-on quota concurrency |
| `POSTDEE_CAPTION_BATCH_DB_TEST_URL` | no guard; use a disposable database | caption credit batches |

Re-check with `rg "skipIf" apps/api/src` before running; new suites appear over time. Never point any of them at the everyday dev database on 5432 or a hosted database. A throwaway cluster for the admin fixture (repeat with the other port and name as needed):

```powershell
initdb -D <scratch>\pg55439 -U postdee_fixture --auth=trust --encoding=UTF8 --locale=C
pg_ctl -D <scratch>\pg55439 -o "-p 55439 -h 127.0.0.1" start   # run in the background; it keeps the shell attached
psql -h 127.0.0.1 -p 55439 -U postdee_fixture -d postgres -c "CREATE DATABASE postdee_admin_fixture"
$env:DATABASE_URL='postgresql://postdee_fixture@127.0.0.1:55439/postdee_admin_fixture'; npx.cmd prisma migrate deploy
```

Then set the test variable to the same URL and run the affected suites. Stop the cluster and delete only the scratch folder you created afterwards.

## Docs and summary

- Add a dated section at the top of `API.md` in the existing style, `## <Feature> (<YYYY-MM-DD>, <status>)` with a status such as "local candidate", covering the contract, compatibility, migration, and deploy order. Sync `ARCHITECTURE.md` when the structure changes.
- The completion summary names the migration (or "no migration"), the deploy order, which database suites ran, and which were skipped.
