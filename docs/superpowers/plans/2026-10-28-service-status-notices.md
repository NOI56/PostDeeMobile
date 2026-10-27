# Service status notices — 2026-10-28

Status: review candidate on branch `claude/service-status`, cut from verified
`origin/main` `e562b842` and opened as a pull request. Not merged or
deployed. Phase 1 of the
support chat plan (`ROADMAP.md`, "Support chat with an AI helper").

## Goal

When the app has a problem, owners tell every customer what is happening from
the admin console, and the Mobile Home shows it. Later phases (support chat,
AI support bot) answer from these same notices, so they must be the single
source of "what is wrong right now".

## Decisions

- Owners create, update and close notices; viewers only read them. Replying to
  support chats (phase 2) will be open to owners and viewers.
- No recent-login requirement for notices (unlike trials and deletions), so an
  owner can post during an outage without signing in again.
- `GET /support/status` is public so the banner still works when sign-in is
  the thing that is broken. It returns only what administrators wrote, never
  administrator ids or member data.
- At most five open notices; closing (`RESOLVED`) is final, a recurrence gets
  a new notice.
- Create is idempotent by a browser-made UUID; update uses an optimistic
  `version` and replays when the same update already landed.
- Mobile never shows an error for this banner: a failed read keeps the last
  known notices and does not count as a failed Home refresh.

## Changes

- API: `apps/api/src/modules/serviceStatus` (types, validation, memory and
  Prisma stores, public route), admin `incidents` view and
  `POST /admin/api/incidents`, wiring in `app.ts`, local admin preview fixture.
- Database: `ServiceIncident` table, migration
  `20261028010000_service_incidents` (additive; checked stage and
  resolution consistency).
- Admin console: "สถานะระบบ" tab with list, create/update drawer, preview
  review step, Thai error messages.
- Mobile: `ServiceIncidentResult`, `PostDeeApiClient.loadServiceStatus`,
  `HomeServiceStatusBanner` under the Home header.

## Verification

- API unit/route tests, plus Prisma store tests on a throwaway PostgreSQL 18
  fixture cluster (`ADMIN_TEST_DATABASE_URL` on 127.0.0.1:55439) with all
  migrations applied: concurrent create replay, open-notice cap under
  concurrency, racing updates, database CHECK constraints.
- Admin console exercised in the local preview: create, review, publish,
  update to closed, list.
- Mobile widget tests for the banner and Home placement/refresh, API client
  parsing test, and real-font light / dark large-text captures.

## Deployment order

1. Deploy the API with migration `20261028010000_service_incidents`.
2. Smoke-test on Staging: `GET /support/status` returns `incidents: []`; an
   owner creates and closes a test notice in `/admin`.
3. Ship a Mobile build for the Home banner. Older apps ignore the route.

## Not verified yet

- Staging deploy, the real Staging admin sign-in, and the banner on a device
  against Staging.
