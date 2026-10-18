# Admin usage accuracy and refresh

Baseline: verified `origin/main` `a9037823901324149ae9695cb5ecce1981853481`.
Implementation branch: `codex/admin-usage-accuracy`, isolated managed worktree.
The user approved implementation of the six admin improvements on 18 October 2026.
Merge, push and Staging deployment are not part of that approval.

## Scope and preserved capabilities

1. Explain registered accounts, UTC usage windows, reserved/consumed quota and
   recorded publishing results without describing them as online users or invoices.
2. Read related projections in bounded, read-only repeatable-read transactions.
3. Replace per-trial/per-member usage queries with set-based aggregates.
4. Report all accounts, including Basic and accounts without trials. Retain an
   explicit latest-trial scope; add UTC date filters and whole-cohort summaries.
5. Manual refresh plus 60-second visible-page refresh; preserve old readings and
   their timestamp on errors. Pause refresh during member dialogs, trial commands,
   search editing and CSV downloads. Never retry mutations automatically.
6. Verify actual PostgreSQL projections, boundary cases, concurrent writes and
   local fixture load. Check desktop and mobile rendering and interaction.

Preserve Firebase owner/viewer authorization, same-origin JSON headers, no-store/CSP,
recent owner authentication, reviewed identity/version, trial command idempotency,
trial/purchased-plan separation, safe channel outcome labels, CSV formula escaping,
feature flags, existing quota rules and provider publication behavior.
No real customer writes, trial grants, platform posting or Staging load tests.

## Contract

`POST /admin/api/view` adds `reportScope: ALL_ACCOUNTS | LATEST_TRIAL` for reports;
the new console explicitly starts with all accounts. Existing clients that omit
scope retain latest-trial reports and the legacy CSV filename. `from`/`through` are inclusive UTC calendar dates;
internally `until` is exclusive and capped at the observation time. Without a
lower bound reports include all retained history. The UI initially selects the
current UTC month. Latest-trial usage intersects the chosen range with the latest
trial's start and expiry/revocation/observation time; it is not historical attribution.

Responses add `asOf`, `window` and report `summary`. Summary/total cover all search
matches before pagination, while rows/CSV remain bounded to 50 accounts per page.
`checkedAt` remains the response completion time. Each request uses a fresh DB
snapshot; separate refreshes/pages are not a permanently frozen export.

Report `postUnits` retains its existing meaning: recorded PlatformPublish rows.
`quotaPostUnits` separately sums selected platforms on Post rows created in the
range, matching the existing quota-counting rule. Member `postUnits` retains its
monthly quota meaning. Caption requests and edit minutes include usage records
reserved/consumed by existing workflows, not a count of successful AI results.
Live, draft, other delivery, failed and pending results are separate. Missing
configured cost rates remain null; estimates are not provider charges.

## Validation and delivery

- Tests first for route validation, projection semantics, batching and refresh.
- Actual DB tests accept only the dedicated loopback fixture
  `127.0.0.1:55439/postdee_admin_fixture`, with owned fixture cleanup.
- Full relevant API tests, typecheck/build, Prisma validation/helper typecheck.
- Browser plugin not available (the Browser plugin/skill is not listed); use
  regular Playwright against local preview with fixture authentication only.
- Target flow: `/admin` -> open local fixture -> reports -> scope/date/search/
  refresh -> matching totals and rows; errors retain the last confirmed reading.
- Desktop and 390x844 mobile; inspect identity, nonblank content, no overlay,
  console, screenshots and actual interactions. QA artifacts stay outside the repo.
- Record measured local load and limits here before completion; local timings do
  not establish Staging capacity. No schema migration expected until measurements
  demonstrate a directly related need.

Prisma v6 transaction behavior was checked against its
[versioned documentation](https://www.prisma.io/docs/orm/v6/prisma-client/queries/transactions),
and snapshot semantics against
[PostgreSQL isolation documentation](https://www.postgresql.org/docs/current/transaction-iso.html).

## Results

Implementation complete locally; merge/push/deployment remain pending. A final
remote fetch still resolves `origin/main` to the same `a903782` baseline. No tracked
file was deleted; no lockfile/dependency/schema/flag change was retained. Existing
worktrees and their dirty files were not modified. Mobile source was unchanged.

Changed files: API `adminDataSource.ts`/test, `adminUsageReport.ts`/test,
`adminRoutes.ts`/test, `adminRefresh.test.ts`, `adminUsageDatabase.test.ts`,
`web/admin.js`, `web/admin.css`, `scripts/admin-preview.ts`; documentation
`README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`, `apps/mobile/README.md`,
`docs/ADMIN_CONSOLE.md`, the prior admin-console plan and this work record.

- `adminDataSource.ts` wraps reads in read-only RepeatableRead transactions with
  a 5-second acquisition wait, 10-second statement limit and 15-second transaction
  limit. Member monthly quota retains the application's existing month-key/full
  UTC-month rules; the report separately clips its selected window at observation.
- `adminUsageReport.ts` runs one parameterized set-based SELECT for each report,
  including all-match summary/total and at most 50 rows. Search percent/underscore/
  backslash characters are literal in both Prisma member search and report SQL.
- Actual PostgreSQL tests caught two UTC defects before fixes: JSONB naive
  timestamp strings were interpreted as local time, and raw Date parameters were
  converted through the DB's Asia/Bangkok session timezone. Explicit UTC binding
  and serialization fix both; UTC boundary and trial-intersection assertions pass.
- A future trial now reports `NOT_STARTED` and “ยังไม่เริ่ม” consistently with
  access evaluation. It is neither active nor expired. The console does not offer
  extension before it starts. This adds only an admin presentation status.
- Route tests first reproduced missing scope validation. UI tests first reproduced
  absent refresh, stale/error handling and all-account reports. Backend's initial
  new-test run was blocked by missing optional native test dependencies; its later
  monthly/literal-search/timezone regressions were observed failing before fixes.
- Actual DB suite: **10/10 pass**, including all plans/no trial/zero usage,
  125-account pagination and whole-cohort totals, dates/intersections, literal
  search, monthly quota preservation, disjoint delivery outcomes and two barriers
  that pause a snapshot while another connection commits a matching account.
- Synthetic load: **1,000 accounts, 10,000 posts, 20,000 platform-result rows**, plus
  1,000 caption and 1,000 edit records. **15 concurrent reports**, **0 errors**,
  **1 SELECT per report**, each response matching the known fixture totals and
  DB counts. The dedicated run measured p50 **136.49 ms**, p95 **212.23 ms**. These
  are loopback measurements, not a promise of Render capacity or network latency.
- Full API suite with the dedicated PostgreSQL URL enabled: **137 files / 2,290
  tests pass, no skips**. UI fake-clock/deferred-response suite: **18/18 pass**,
  covering visible-only/single-flight refresh, paused workflows, plain-text 429,
  old responses after logout/navigation, retained timestamps, CSV binding and
  future-trial presentation. A browser-found false selected-row highlight was
  reproduced by an added assertion and fixed; unknown cost uses readable text.
- API typecheck/build, Prisma schema validation, seed/config helper typecheck and
  preview helper typecheck pass. All 20 existing fixture migrations are applied;
  no new migration is needed. Fixture cleanup leaves no test accounts; the local
  PostgreSQL server was stopped after verifying no other client connections.
- Compiled smoke verifies source-matching JS/CSS, actual Firebase revoked-check
  wiring through a fake verifier, Owner/Viewer/ordinary-user boundaries, seven
  Prisma read views, report scopes, CSV and unchanged member monthly quota.
  It creates/deletes only its owned local fixture and never calls a provider.

### Browser QA

Environment: `http://127.0.0.1:4184/admin`, local in-memory fixture only, Chrome
via bundled Playwright 1.62.1. Browser plugin not available; no Browser plugin or
browser skill is listed. The bundled import needed CommonJS `createRequire`, and
Chrome uses its existing Program Files executable; no browser dependency or new
project package was installed. Preview accepts a validated `--port=4184` to avoid
unrelated existing preview servers; it binds only 127.0.0.1 and reports port errors.

| Required check | Result |
| --- | --- |
| Identity | `/admin`, title `PostDee · ผู้ดูแลระบบ` |
| Meaningful render | All seven views, 1440x1000 and 390x844 |
| Overlay | No framework error overlay |
| Console | No page errors or warning/error messages during the seven-view smoke |
| Layout/screenshots | Document width equals viewport at both sizes; tables scroll within their containers |
| Interaction | Scope, search, dates, manual/automatic refresh, member details, CSV, failure/retry and logout verified |

Exact interaction evidence: ALL_ACCOUNTS -> LATEST_TRIAL gives one fixture account;
back to ALL_ACCOUNTS gives three; search `narin` gives one row; changing `from` sends
the exact UTC calendar date. CSV download contains the same applied scope/date/
search and retains the legacy trial filename. CSV deliberately reads a fresh
snapshot, explained in the UI, so changes since the screen load may alter values.
A one-shot mocked HTTP 503 retains the prior row/timestamp, marks it stale and
offers retry; retry restores the normal state. Playwright clock installed before
navigation confirms one automatic read at 60 seconds, none during an open drawer
or focused search editing, resumed reads after closing, and none after logout.
The drawer remains unchanged across three simulated minutes.

QA evidence remains outside the repository in the user's Temp folder:
`postdee-admin-usage-desktop.png`, `postdee-admin-usage-mobile.png`,
`postdee-admin-usage-mobile-summary.png`, `postdee-admin-usage-refresh-error.png`,
`postdee-admin-usage-mobile-drawer.png`, `postdee-admin-usage-qa.csv`,
`postdee-admin-usage-api-release-check.log`, `postdee-admin-usage-database-final.log`
and `postdee-admin-usage-compiled-smoke.mjs`.

### Delivery limits

Only local data and the intended new worktree were used. Staging has not received
this update, and no real trial, account, entitlement, purchase or post was changed.
No new Firebase sign-in or connected-provider publication check was necessary for
these read-only changes. Flutter tests were not rerun because no Dart/native file
changed. The real Firebase login and Staging throughput of this new source remain
unverified. Existing admin auth/flag setup is reused; release the API/admin assets
then reload `/admin`. No Mobile reinstall is needed. Reload old browser clients
to receive the new all-account UI; omitted API scope, CSV filename and old report
field meanings remain compatible, and the all/trial distinction is explicit.
