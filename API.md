# API.md

PostDee backend API reference.

## Dot, the AI support helper (2026-10-28, phase 3 local candidate)

Dot answers most support chat messages (the team may be one person) when
both switches are on: the
server's `SUPPORT_BOT_PROVIDER` (`off` default, `mock` for local only and
refused in production, or `openai`, which reuses `OPENAI_API_KEY` and
`OPENAI_SUPPORT_BOT_MODEL`, default `gpt-4o-mini`) and an owner's global
switch in the admin console (no saved setting = off).

- `GET /support/chat` adds `bot: { available }`, `thread.botEnabled` and
  `thread.teamRequested`. Messages may now have `sender: "BOT"`; clients
  must accept it.
- `POST /support/chat/messages` is unchanged; Dot's reply is written after
  the response and arrives through polling. Dot answers only the newest
  member message and sets `WAITING_MEMBER`. When Dot needs a person it sets
  `teamRequested`, and the thread then stays `WAITING_TEAM` through Dot's
  later replies; Dot keeps answering.
- `POST /support/chat/handoff` (signed-in member, no body) asks the team to
  look: `200 { status, thread: { status: "WAITING_TEAM", botEnabled: true,
  teamRequested: true } }`, `404 SUPPORT_THREAD_NOT_FOUND` before the first
  message. Dot keeps helping meanwhile.
- A team reply clears `teamRequested` and leaves Dot on; only the admin
  per-thread switch turns Dot off. Closing clears the flag and turns Dot on.
- Sentry signals (optional): with `SENTRY_SIGNALS_TOKEN` (a Sentry auth token
  with `event:read`) next to the existing `SENTRY_DSN`/`SENTRY_ENVIRONMENT`,
  the API runs one `GET /api/0/organizations/{org}/issues/` search per area
  (TikTok/YouTube/Instagram/Facebook publishing, scheduler, uploads, AI
  captions, general 5xx) for unresolved issues seen in the last
  `SENTRY_SIGNALS_WINDOW_MINUTES` (default 30), cached for 2 minutes. The
  organization, region and project come from the DSN;
  `SENTRY_SIGNALS_PROJECT_IDS` can add projects. Dot gets only the fixed
  Thai area label and last-seen time, never issue titles. `view:
  "incidents"` adds `signals: { configured, checkedAt, failed, signals[] }`
  with titles and links for administrators.
- Admin: `view: "support"` adds `bot: { provider, enabled, updatedAt }`;
  `POST /admin/api/support/bot-settings {enabled}` is owner-only (`409
  ADMIN_SUPPORT_BOT_UNCONFIGURED` when the provider is `off`);
  `POST /admin/api/support/thread-bot {userId, enabled}` is for owners and
  viewers.
- Limits: 20 Dot replies per member per 24 hours, 500 output tokens, 20 s
  timeout; any failure becomes a fixed handoff message, and reaching the
  daily limit posts one fixed message. Dot receives only open notices,
  Sentry area labels, plan facts, the plan and the last five posts' statuses with
  translated failure reasons, plus the last 20 messages with emails, phone
  numbers and long digit runs removed.

Deployment: migration `20261028030000_support_bot` (additive). Update the
privacy policy before an owner turns Dot on. See the [Dot plan](docs/superpowers/plans/2026-10-28-support-bot-dot.md).

## Support chat (2026-10-28, phase 2 local candidate)

One continuous conversation per member, answered by administrators in the
admin console. The optional Dot helper is described above.

### `GET /support/chat`

Signed-in member only, `Cache-Control: private, no-store`. Without `after` it
returns the latest 100 messages; with `after=<cursor>` only newer ones (up to
100), which is what Mobile polls every 5 seconds while the chat is open.

```json
{
  "status": "ok",
  "thread": { "status": "WAITING_MEMBER", "lastMessageAt": "2026-10-28T09:20:00.000Z" },
  "messages": [
    { "id": "7d1f9c3a-2b4e-4c8a-9f10-000000000001", "sender": "MEMBER", "body": "โพสต์ไม่ขึ้น", "createdAt": "2026-10-28T09:12:00.000Z" },
    { "id": "7d1f9c3a-2b4e-4c8a-9f10-000000000002", "sender": "TEAM", "body": "ทีมงานกำลังดูให้", "createdAt": "2026-10-28T09:20:00.000Z" }
  ],
  "cursor": "opaque"
}
```

`thread` is `null` before the first message. `cursor` echoes the request when
nothing is new. Team replies never carry the administrator's identity.
`400 SUPPORT_CURSOR_INVALID` for a malformed cursor.

### `POST /support/chat/messages`

Body `{ "id": "<UUID>", "body": "..." }`; returns `201 { status, message }`.
The app makes the UUID once per message and reuses it on retry, so a retry
after a lost response returns the stored message instead of a duplicate.
`body` is 1–1000 characters after trimming; newlines are kept, other control
characters are rejected. The thread becomes `WAITING_TEAM` (a closed thread
reopens). Errors: `400 SUPPORT_MESSAGE_INVALID`, `409
SUPPORT_MESSAGE_CONFLICT` (id reused with other content), `429
SUPPORT_MESSAGE_LIMIT` (100 member messages per rolling 24 hours), the global
and a per-client limit of 20 sends per minute, and the usual account-deletion
`409 ACCOUNT_DELETION_IN_PROGRESS`.

The 2026-10-29 admin alert candidate preserves this response contract. A
best-effort administrator push is sent after the response only when a newly
stored member message moves the conversation into `WAITING_TEAM` (a new
conversation, or one that was `WAITING_MEMBER` or `CLOSED`). Follow-ups while it
already waits, retries with the same message id, and messages the in-app bot
will answer (bot available and on for that thread) send no push.
Recipients are the deduplicated configured owner and viewer UIDs with
registered Mobile devices. The generic payload has
`{ userId: "<recipient administrator UID>", type: "support_new_message" }`
and contains no member identity or message text. It uses the existing
`PUSH_SENDER=firebase` configuration. A handoff request without a new member
message updates the pending count but sends no additional push.

### `GET /admin/api/support/pending-count` (2026-10-29 candidate)

Owners and viewers only, with the existing Firebase admin authentication and
rate limit. Returns `{ "count": 3, "checkedAt": "2026-10-29T00:00:00.000Z" }`
with `Cache-Control: private, no-store` and no member data. `count` is the
number of conversations whose status is `WAITING_TEAM`, across all pages and
inbox filters. It is not an unread-message count: opening a conversation does
not clear it; replies, closes and Dot's existing status transitions determine
whether the conversation remains counted. This read-only GET does not need
the write-only Origin/header checks.

The admin navigation badge reads this endpoint on login/resume and every 30
seconds while visible, pauses when hidden and retains the last count with a
stale indicator if a read fails. It displays `99+` above 99 and does not reload
the open conversation or a reply draft. No new environment key or migration.

### Administrator commands (owners and viewers)

| Route | Contract |
| --- | --- |
| `POST /admin/api/view` | `view: "support"`; optional `status` (`WAITING_TEAM`/`WAITING_MEMBER`/`CLOSED`), `query` (email or name), opaque `cursor`; newest conversation first, 50 per page, no CSV |
| `POST /admin/api/support/thread` | `{userId}`; thread, latest 200 messages (`byYou` marks the caller's own replies), `hasEarlier`, member email/name/purchased plan |
| `POST /admin/api/support/reply` | `{userId, id (UUID), body}`; runs inside the member's owner lifetime, sets `WAITING_MEMBER`, and sends one push (`type: support_reply`, generic text) the first time the reply is stored |
| `POST /admin/api/support/close` | `{userId, lastMessageId}`; closes only if no newer message arrived (`409 ADMIN_SUPPORT_THREAD_CHANGED` otherwise) |

Other errors: `404 ADMIN_SUPPORT_THREAD_NOT_FOUND`, `409
ADMIN_SUPPORT_MEMBER_DELETING`, `503 ADMIN_SUPPORT_UNAVAILABLE`.

Deployment: migration `20261028020000_support_chat` adds `SupportThread` and
`SupportMessage` (additive, cascade from `User`, so account deletion removes the
conversation). No environment flag. Replies notify through the existing
`PUSH_SENDER`; with the mock sender they are saved but no push is sent. The
Mobile entry ("แชทกับทีมงาน" under Account help) needs a new build. See the
[support chat plan](docs/superpowers/plans/2026-10-28-support-chat-room.md).

## Service status notices (2026-10-28, local candidate)

Administrators publish customer-facing notices while the app has a problem;
the Mobile Home shows open ones as a banner. This is phase 1 of the support
chat plan; the chat room and AI support bot are later phases.

### `GET /support/status`

Public on purpose (no sign-in), so the notice still reaches people while login
itself is failing; it is covered by the global rate limit and sent with
`Cache-Control: public, max-age=30`.

```json
{
  "status": "ok",
  "incidents": [
    {
      "id": "0f7c2a51-3b8d-4e7a-9c1f-5d2e6b8a9c01",
      "title": "TikTok ส่งคลิปช้ากว่าปกติ",
      "message": "โพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ ไม่ต้องส่งซ้ำ",
      "platforms": ["TIKTOK"],
      "stage": "IDENTIFIED",
      "startedAt": "2026-10-28T07:00:00.000Z",
      "updatedAt": "2026-10-28T07:30:00.000Z"
    }
  ],
  "checkedAt": "2026-10-28T08:00:00.000Z"
}
```

Only open notices are listed (newest first, at most 5 can be open). `stage` is
`INVESTIGATING`, `IDENTIFIED` or `MONITORING`; an empty `platforms` list means
the whole app. Administrator ids are never included. A store failure returns
`503 SERVICE_STATUS_UNAVAILABLE` with `no-store`; Mobile then keeps its last
known notices and shows no error.

### Administrator commands

`POST /admin/api/view` with `view: "incidents"` lists every notice (open and
closed, newest first, opaque `cursor`, no CSV) for owners and viewers.
`POST /admin/api/incidents` is owner-only and needs no recent re-login, so an
owner can post during an outage:

| Field | Rule |
| --- | --- |
| `action` | `CREATE` or `UPDATE` |
| `id` | UUID; for `CREATE` the browser makes it once and reuses it on retry |
| `expectedVersion` | `UPDATE` only; the version the owner reviewed (optimistic lock) |
| `title` | 3–80 characters, one line |
| `message` | 3–500 characters, newlines allowed |
| `platforms` | Subset of TikTok/YouTube Shorts/Instagram Reels/Facebook Reels |
| `stage` | `CREATE`: an open stage; `UPDATE` may also send `RESOLVED`, which closes it for good |

A retried `CREATE` or `UPDATE` that already landed returns the stored notice.
Errors: `400 ADMIN_INCIDENT_INVALID`, `409 ADMIN_REQUEST_CONFLICT` (id reused
with other content), `409 ADMIN_INCIDENT_LIMIT` (5 open), `409
ADMIN_INCIDENT_CHANGED` (someone else updated it), `409
ADMIN_INCIDENT_RESOLVED`, `404 ADMIN_INCIDENT_NOT_FOUND`, `503
ADMIN_INCIDENT_UNAVAILABLE`.

Deployment order: apply migration `20261028010000_service_incidents` (one new
table, additive) with the API deploy; no environment flag is needed. The admin
tab ships with the API. The Home banner needs a new Mobile build; older apps
simply never call the route. See the
[service status plan](docs/superpowers/plans/2026-10-28-service-status-notices.md).

## Caption cost confirmation (2026-10-25, implementation candidate)

`POST /captions/generate-from-clip` derives its cost from validated `platforms`:
1–4 distinct destinations cost 1–4 credits. Omitting `platforms` costs one
credit for shared-caption generation; `POST /captions/generate` also remains
one credit. Starter/Pro monthly limits (50/120), add-on packs and prices are
unchanged. One provider generation operation still produces the selected set.

The new Mobile sends `expectedCredits` equal to its displayed cost. When
supplied it must match the server-derived cost; multi-platform requests must
include it. Missing/mismatched confirmation returns `409` with code
`AI_CAPTION_COST_CONFIRMATION_REQUIRED` before quota reservation or provider
work. Its error `quota` contains `requiredCredits` and `chargedCredits: 0`.
Legacy shared/one-platform requests may omit it. Invalid platform values remain
`400`; the API never accepts a client price as authoritative.

The complete cost is reserved atomically, included monthly quota first and then
the nonexpiring add-on bank. Insufficient combined balance returns `429
AI_CAPTION_QUOTA_REACHED` with actual remaining quota and `quota.requiredCredits`,
without partial debit or provider work. A failed/fallback/incomplete result
releases the entire batch. Quota metadata adds `requestedCredits` and
`chargedCredits`; the latter equals the cost when charged or zero after a
successful full refund. The existing `charged` boolean remains optional: it is
reported for fallback results, and omission on normal success means `true`.
Rejecting a successfully generated preview does not refund the generation.

Coordinate API and Mobile rollout. Older multi-platform clients must update
instead of silently being charged more than their fixed one-credit display.
New Mobile against the older API can quote multiple credits while that API
still charges one. No schema, migration, provider or environment flag change is
required. This is not a deployment receipt; see the
[credit-per-channel plan](docs/superpowers/plans/2026-10-25-caption-credit-per-channel.md).

## Caption quota read (2026-10-25, implementation candidate)

### `GET /captions/quota`

Returns the authenticated user's effective plan and current AI caption quota
with `Cache-Control: no-store`. This read does not generate captions, upload
media, reserve usage, consume purchased credits or accept caller-selected
user/plan/month overrides. Missing authentication returns `401`.

```json
{
  "status": "ok",
  "plan": "STARTER",
  "quota": {
    "limit": 50,
    "usedThisMonth": 12,
    "remainingThisMonth": 38,
    "addonRemaining": 20,
    "availableGenerations": 58
  }
}
```

Monthly limits remain Basic `0`, Starter `50` and Pro `120`. The usage ledger
and current UTC month are the same as caption generation; the route uses the
existing server clock. `remainingThisMonth` is `max(limit - usedThisMonth, 0)`,
retaining recorded use after a downgrade. `addonRemaining` is the existing
nonexpiring purchased bank after add-on usage. Paid `availableGenerations`
combines monthly remainder and that bank even when new add-on purchases are
disabled. Basic can read a retained bank but has `availableGenerations: 0`;
the read does not unlock paid AI access.

The Mobile visibility follow-up renders this validated snapshot for all plans
in both shared and advanced caption modes. Basic shows its actual `0` monthly
limit/remainder and any retained `usedThisMonth`, plus a small paid-eligibility
hint; its purchased bank must not be shown as spendable. Display units are
credits. This is a Mobile presentation change using the existing response;
Basic still cannot generate AI captions. Loading/failed reads remain retryable
unknown states rather than fabricated zero balances. An updated Mobile build
must be installed to see the follow-up; no API/schema or pricing change is needed.

Deploy this additive API before distributing the quota-strip Mobile build.
An older API returning `404` leaves the strip unavailable with a retry action,
not an invented zero balance. The quota-read addition itself does not alter
generation/fallback/refund, trial or selection rules; current credit spending
follows the cost-confirmation contract above. No schema, migration,
environment flag or provider change is required. This record does not claim a
deployment; scope and verification are tracked in the
[quota-strip plan](docs/superpowers/plans/2026-10-25-caption-quota-strip.md).
## Mobile per-channel duration checks (2026-10-25, local candidate)

This Mobile-only candidate adds early duration warnings after video pick,
prefill and draft restoration. Connected channel rows report incompatibility;
unselected incompatible rows cannot be added, selected ones remain removable,
and Next/final confirmation stay blocked until selected errors are resolved.
Select all adds only compatible channels without deleting existing selections.

Local limits are Facebook Page Reels 3–90 seconds, YouTube Shorts at most 180,
Instagram Reels 3–900, TikTok Inbox at most 600, and TikTok Direct at most
min(600 seconds, the fresh connected creator limit). These are client checks,
not new trusted server media validation or a guarantee of provider acceptance.
Unknown source hints do not establish compatibility. Actual outgoing-file
validation and TikTok preparation/Direct guards remain required.

No request field, backend route, schema, migration, quota or feature flag changes.
Accepted idempotent recovery remains before new submission guards; cached receipts
and original request IDs are retained. No already queued schedule is rewritten.
Mobile tests, analysis and Staging APK12052 build/package/signature checks pass;
installation and native runtime are still unverified.
Primary source review on 2026-10-25 is recorded in the [preflight plan](docs/superpowers/plans/2026-10-15-platform-publish-preflight.md#per-channel-duration-alerts--2026-10-25-local-candidate);
real-account PostPeer publication remains unverified.
## Social linking security Batch 2 (2026-10-23, review candidate)

New links require an authenticated, single-use connect attempt. The updated
connect and refresh contracts below supersede the earlier profile-only polling
flow. Existing saved connections can still be listed and reconciled, but a
legacy refresh without a nonce cannot import or replace an account.

This candidate adds one Prisma migration. Run the read-only
[`social-linking-preflight.sql`](apps/api/prisma/social-linking-preflight.sql)
against each target database before rollout; both result sets must be empty.
The migration also locks/checks the table and aborts on duplicates without
deleting or reassigning connections. Apply the migration and API before updated
Mobile. Old Mobile cannot finish a new connection after this API change until
it is updated; saved connections and publishing retain their existing contracts.
Hosted duplicate counts and real PostPeer completion are **not verified**.
Staging external database access is blocked and Production is suspended; no
access settings were changed. See the
[Batch 2 validation and rollout record](docs/superpowers/plans/2026-10-23-social-linking-security-batch2.md).

## Mobile AI caption selection (2026-10-23, Staging Live)

The advanced composer can request captions for an explicitly chosen subset of
the four supported channels. The initial AI selection is empty; requesting
generation requires 1–4 selections. These are generation targets, independent
of destinations selected for publishing. The client sends only their existing
API enum values in `POST /captions/generate-from-clip`'s optional `platforms`
array. The then-deployed contract already supported this subset; the original
Mobile selection follow-up required no backend runtime or deployment change.

The original release used one credit per set; that rule is superseded by the
2026-10-25 cost-confirmation contract above. Missing/malformed output retains
whole-request fallback and refunds the entire reserved batch;
`quota.charged` reflects whether release succeeded.
The client previews/applies/undoes only the requested captions and preserves all
unselected text. The four manual editors remain available regardless of the
generation selection.

`aiCaptionPlatforms` is optional local-draft metadata, defaults to an empty set
for historical drafts, and is never added to post creation/recovery requests
or reusable account/channel defaults. This work changes no publish settings
contract, database schema, migration or environment variable. Checks
pass 2,504 API tests, typecheck/build, Prisma validation/helper typecheck and
the Mobile checks recorded below. Feature `dab94fb` is merged/pushed and its
Backend/Mobile CI passes. The user-authorized Staging synchronization deploy
is Live on that exact source, with unchanged runtime settings, 22 migrations
and none pending. Health/readiness and unauthenticated-route barriers pass.
APK **12043** is installed; emulator selector/draft smoke passes without any
AI request, quota spend or post. iOS no-codesign CI also passes; actual
provider acceptance remains unverified. Track results in the
[selection work record](docs/superpowers/plans/2026-10-23-caption-target-selection.md).

## Per-platform caption contract (2026-10-23, Staging Live)

The optional `caption` string in each `platformSettings.<platform>` object
overrides the shared post caption for that destination. TikTok, Instagram and
Facebook overrides must be nonempty after trimming. YouTube accepts `""` or
whitespace, normalized to an explicit empty description; it does not fall back
to shared text. All required settings for that destination remain required,
including YouTube's title; a caption-only object does not replace those
settings. Absence means use the shared `caption`, preserving existing clients
and historical posts.
The top-level post `caption` remains part of the existing request and immutable
intent. Mobile supplies a compatibility summary from the selected effective
captions in advanced mode, while retaining the original shared text locally.

New-post validation, TikTok Direct validation, immutable replay/recovery,
JSON persistence, queued execution and provider mapping retain and use the
effective per-destination text. A changed override conflicts with the original
accepted submission intent. The optional field does not change visibility,
disclosures, destination ownership, scheduling, quotas or posting modes.
`FACEBOOK_REELS` retains its existing key; the 2026-10-24 contract below routes
it to Facebook Page Reels only. Real-account E2E remains pending.

The existing `POST /captions/generate-from-clip` additionally accepts optional
`platforms` and can return `platformCaptions`; its detailed contract is below.
Both additions use existing JSON/storage paths and require no database
migration. Deploy the updated API before Mobile sends these fields; old API
parsers can reject the new settings. Staging serves the contract at `a391bc4`,
with APK 12042 installed after API deployment. Final CI, health/readiness,
authentication barriers and three authenticated installed-client subscription
reads passed. This does not establish actual multi-caption provider quality or
real destination publication. See the
[feature work record](docs/superpowers/plans/2026-10-23-platform-captions.md).

## Opt-in Sentry reporting (2026-10-23, Staging Live)

The candidate adds internal error monitoring without changing public routes,
request/response shapes, authentication, status codes, provider retry rules,
quotas or database schema. `@sentry/node` is pinned to `11.8.0`. The API and
its in-process publisher use the reporter; the optional BullMQ worker initializes
the same boundary when run separately.

| Environment variable | Default / requirement |
| --- | --- |
| `SENTRY_DSN` | Empty disables reporting. Use the API project's HTTPS ingest DSN only in the target environment's untracked configuration. |
| `SENTRY_ENVIRONMENT` | Set explicitly when a DSN is enabled: `development`, `staging` or `production`. Do not derive Staging from `NODE_ENV=production`. |
| `SENTRY_RELEASE` | Optional safe build identifier, for example `postdee-api@<commit-sha>`; no customer details, URL/query or credentials. |

Malformed enabled server configuration is rejected at startup. SDK/transport
failure is contained and does not change API responses or publishing safeguards;
shutdown flush is bounded. Expected 4xx responses are not reported. Unexpected
5xx responses and unhandled request errors use safe method/route-template/status
labels, and handled provider, publisher, scheduler and worker failures use
allowlisted operation/platform labels. These reports do not retry or resend a
post, repair its history or consume quota.

The only automatic fatal integration is the SDK's
`onUncaughtExceptionIntegration`. Node's default unhandled-rejection path is
preserved, including fatal exit for rejected named errors; a separate Sentry
rejection handler is not installed. Real child-process regressions cover this
fatal behavior. That targeted result does not replace final full-suite checks.

The final outbound sanitizer and transport rebuild error events/envelopes using
allowlisted error types, repository-relative stack frames and bounded labels.
They remove raw exception
messages, provider payloads, request bodies/headers/cookies/URLs, customer
captions/media keys, user/account identifiers and credentials. No tracing,
performance spans, breadcrumbs, logs, Replay or attachments are enabled. There
is no public test-error endpoint, DSN discovery route or Sentry authentication
token in the repository. Default-off configuration preserves existing deployments.

No Prisma migration or API-first compatibility rollout is needed for this
internal reporter. Each cloud API/worker still needs an explicitly authorized
deployment and its own runtime DSN/environment. The final local API checks pass
on Node `22.23.3`: 2,422 tests pass with 25 skips, plus typecheck/build and Prisma
validation/helper compilation. A synthetic local Express 500 reached
`POSTDEE-API-1` in Staging without real social publication or purchases. Sentry's
inferred coarse geography prompted project-level IP storage prevention and
an advanced removal rule using source `$user.**` on both projects; the initial
source `user` did not provide the intended result. A subsequent API event was
accepted and the latest API/Mobile dashboard events show no geography. Outbound
allowlist tests cover the absence of customer URL/body/user fields. The cloud API
release is authorized by the user's 2026-10-23 `main/push/deploy` request.
Feature `b486ca3` and lockfile-only fix `35512aa` are on `main`/GitHub. Merging
only the three Sentry environment keys into `My Workspace`'s
`postdee-api-staging` triggered an initial build despite auto-deploy being off;
it failed `npm ci` with lockfile `EUSAGE`, leaving live source `8c957ab` running.
The Node 22/npm 10 lockfile compatibility fix changes no runtime package manifest
or API source. That repair deployed `35512aa`; later cloud inspection exposed
an empty-stack processing warning. The minimal sanitizer correction
`12e05895755b16d21f7eabb90a75d1824dac0b1e` is on `main`/GitHub and was Live in
`dep-dbdcvlmi0phs739c9m20`, finished 2026-10-23 10:10:35 Thailand time.
Post-Live `/health` and `/ready` return HTTP 200 with database/queue healthy.
Startup confirms 22 migrations found/none pending and no monitoring-init or
fatal startup failure. For that `12e0589` deployment, only the Sentry release key
changed; its value was
`postdee-api@12e05895755b16d21f7eabb90a75d1824dac0b1e` in `staging`.
Prior-source CI `39890752750` passes Backend/Mobile; new-source CI `39893356044`
also passes Backend and Flutter Mobile. The repeated cloud test accepts a
generic deployed-module event as `POSTDEE-API-2` / `7807957893`,
event `1d062ef96a624d039d6f87ccdfa0dc0f`,
matching the deployed source, Staging environment and full release above. An
isolated Node process in the authenticated Render Web Shell imports only the
deployed monitoring config/reporter and SDK event/close accessors; flush/close
succeed, and health/readiness remain 200. It does not load the app/server/worker,
use the database or force an HTTP failure, so this proves deployed
module/configuration/network ingestion rather than an Express-main-process error
path. The earlier SSH probe stopped at host trust without changes; this Web Shell
check requires no SSH key/trust change. Full status is tracked in the
[work record](docs/superpowers/plans/2026-10-22-sentry-monitoring.md).
The initial `35512aa` event `08fa034ea34e49ffa5afb5a8c7bcd090` was accepted
with `Discarded invalid value` at `exception.values.0.stacktrace.frames`.
The fix omits the stacktrace when no safe frames remain, retaining nonempty safe
stacks and the privacy allowlist. Targeted 30 tests and the full API/static
checks pass. The latest `12e0589` event has no `Processing Error` or
`Discarded invalid value` in the dashboard's full accessibility tree and visual
inspection; its generic message/release/environment match and geography is absent.
The API source/results are unchanged by the later Mobile-only native Crashlytics
preservation fix. Final-3 Mobile tests/analysis and APK12041 build/source checks
pass. Exact APK12041 startup, enabled native Crashlytics collection and a generic
production-reporter Sentry event are verified; no actual native crash was forced.
The APK12040 event remains intermediate evidence, superseded by APK12041.

The user's later main-process drill runs source
`a0540a3589bd8760343191993140c92e607af67f`, whose API tree is identical to
CI-tested `12e0589`. A temporary Staging-only preload and private OS signal
request call the actual main process's existing SIGTERM drain, then cause one
uncaught `RangeError` after shutdown completes. Main PID `146` emits matching
Sentry event `fc21ccb5e45c4c32924a15473b098931` as Fatal/Unhandled and exits 1;
Render restarts it as PID `128`. The captured event is generic and has no
geography or processing error. Gateway health samples observe roughly 33
seconds of 502s before recovery. All queued/publishing/platform counts are zero.

Cleanup removes only temporary `NODE_OPTIONS`, restores the original 57-key
set and retains release
`postdee-api@a0540a3589bd8760343191993140c92e607af67f`. Normal deploy
`dep-dbdddq3rjlhs73ct61hg` is Live on exact `a0540a3`; final health/readiness
are 200 with database/queue healthy, and clean runtime confirms no
`NODE_OPTIONS`, no armed marker, matching source/release and zero publish
counts. No repository runtime code, endpoint, inspector, port, database write
or real post/purchase is added by the drill. This proves a real main-process
fatal after drain and restart, not a crash during active publishing or a forced
HTTP-500 middleware error. Full chronology/evidence is in the work record.

## Local remembered settings boundary (2026-10-20, YouTube native restart verified)

Remembered channel settings are Mobile-only local preferences. No new endpoint,
request field or migration is introduced. Mobile resolves editable reusable
choices into the existing per-post `platformSettings` contract; clip-specific
declarations, TikTok creator capabilities and fresh confirmation retain their
existing server validation. There is no server-side or cross-device preference
sync. Mobile tests, analysis and the local Staging build pass. Native YouTube
Save and restart restore reusable choices while preserving fresh clip
declarations; Cancel/reopen also passes. Meta coverage remains automated
fixtures. Source is integrated into `main` on 2026-10-20 with smooth progress;
no API deployment is required or performed for these Mobile-only changes.
See the [work record](docs/superpowers/plans/2026-10-18-remember-platform-defaults.md).

The local same-sheet TikTok consent follow-up changes only Mobile editing state:
viewer/interaction/AI edits retain the user's explicit checkmark until Save,
while commercial context changes invalidate it. The final settings, creator
revision and confirmations use the same API payload and validation. No backend
deployment or database migration is needed; see the
[consent work record](docs/superpowers/plans/2026-10-20-platform-settings-consent.md).

## Optional Meta media disclosure (2026-10-18, Staging delivered)

`platformSettings.INSTAGRAM_REELS` accepts `{shareToFeed: boolean,
isAiGenerated?: boolean}`; `FACEBOOK_REELS` accepts `{publishMode:
"PUBLISH" | "PAGE_DRAFT", isAiGenerated?: boolean}`. The Facebook internal key
now targets Page Reels using `contentType: 'reel'`; these existing delivery and
disclosure choices are preserved. A present disclosure must be a boolean; null,
strings, numbers and unknown fields are rejected. Absence preserves the old exact shape,
including persisted snapshots, queue messages, accepted request replay and
read-only submission recovery. Absent, false and true are distinct immutable
intents; changing a declaration cannot reuse an accepted request ID.

The worker forwards `platformSpecificData.isAiGenerated` only when explicitly
present, including false. No inferred value comes from AI-written captions.
Backend regression tests pass 127 files / 2,207 tests, plus typecheck/build and
Prisma checks. Source `866f0e3` is merged/pushed to main and Live on Staging
`dep-dba2oieq1p3s73a3g6qg`; exact-source Backend/Flutter CI `39089186176` passes.
Health/readiness return HTTP 200. A read-only probe of the deployed compiled
parser preserves missing/false/true for both Meta platforms, rejects invalid
types and distinguishes immutable intents, without writes or provider calls.
Staging's publisher runs in the API process with a memory queue and no separate
worker. Other environments must deploy the
API and every publishing worker before the new Mobile controls. No schema
migration, dependency or environment change is needed. Android **12024** is now
installed after the separate emulator storage recovery; the API remains on
source `866f0e3` and does not need another deployment for this installer/tool
follow-up. The later administrator API deployment described below supersedes
that server source without changing the unified publishing contracts.
Native Home/account/drafts/video reads pass after the update and cold boot;
this is not a new publishing HTTP POST or provider publication test.
Connected-account Meta publication and platform labeling remain unverified.
Evidence:
[implementation record](docs/superpowers/plans/2026-10-18-unified-platform-settings.md).

## Private administrator API (2026-10-18, disabled by default)

Source `50fba5e` is Live on Staging in `dep-dba5im61egvs739eoteg`. Both additive
migrations applied earlier; health/readiness, `/admin`, assets and public config
return HTTP 200. The read-only Firebase credential is installed and administrator/
trial flags are enabled. Unauthenticated `/admin/api/session` returns 401.
Manual Google owner sign-in and all seven authenticated read-only views pass.
Member search/detail, post status/platform/UTC-date filters and the unsaved trial
review flow were exercised against live data. Real trial mutations, nonempty
CSV and live ordinary-user denial remain unverified; no member trial was granted.
Post-deploy API/Flutter CI `39100690775` passed. Health/readiness and exact admin
JS/CSS release hashes pass; the existing owner session verified Thai overview and
draft/legacy-unknown channel results. Fresh owner login into the new UI remains
unverified in this deploy receipt; member actions/empty states passed local QA.

`ADMIN_CONSOLE_ENABLED=true` registers `/admin`, its static assets and public
Firebase Web configuration. No data endpoint is public: `/admin/api/*` requires
revocation-checked Firebase authentication and an explicit Owner/Viewer UID.
All responses use private/no-store. Every POST requires exact configured `Origin`,
`Content-Type: application/json` and `X-PostDee-Admin: 1`.

| Route | Contract |
| --- | --- |
| `GET /admin/api/session` | Role, email, environment; owner lists are never exposed |
| `GET /admin/api/support/pending-count` | Owners and viewers; `{count, checkedAt}` for all `WAITING_TEAM` conversations, independent of inbox filters/pages (2026-10-29 candidate) |
| `POST /admin/api/view` | `view`: overview/members/posts/trials/channels/reports/audit/deletions, and since 2026-10-28 incidents and support (`deletions` searches by exact Firebase UID); optional `query`, opaque `cursor`; posts accept `status`, `platform`; posts/reports accept `from`, `through` (inclusive UTC dates); reports accept `reportScope: ALL_ACCOUNTS` or `LATEST_TRIAL` (legacy API default); the new console explicitly starts with all accounts |
| `POST /admin/api/member` | `userId`; existing member details, purchased plan, separate trial, current UTC-month usage |
| `POST /admin/api/trials` | Owner only, auth_time within 15 minutes; command below |
| `POST /admin/api/account-deletions` | Owner only, auth_time within 15 minutes; deletes a member on their verified request (see below) |
| `POST /admin/api/incidents` | Owner only; creates/updates customer-facing service notices (2026-10-28, see Service status notices) |
| `POST /admin/api/support/thread`, `/support/reply`, `/support/close` | Owners and viewers; support chat (2026-10-28, see Support chat) |

`POST /admin/api/account-deletions` takes `{requestId (UUID), userId,
expectedEmail, reason}`. `expectedEmail` must match the member's current email
(empty for phone-only members); `reason` is 3–500 characters with no control
characters and no `@`, because the record is retained after deletion and must
not hold the member's address. Owner/Viewer UIDs return `409
ADMIN_DELETE_PROTECTED`. The first call stores a PENDING `AdminAccountDeletion`
row (request id, actor UID, target UID, reason, intent hash; no User foreign
key, no email) and then runs the exact `DELETE /account` saga for that UID
without the member's recent sign-in requirement; every other gate, drain,
provider/media/database cleanup and Firebase identity deletion is unchanged,
including `FIREBASE_AUTH_DELETE_ENABLED`. Saga errors return the saga's status
and `code` (for example `503 ACCOUNT_DELETION_UNAVAILABLE` while disabled) and
are stored as `lastErrorCode`; retrying the same request id continues even if
the member row is already gone. A completed request replays `200` without
running cleanup again, and a reused id with another intent returns `409
ADMIN_REQUEST_CONFLICT`. Success returns `{status: "ok", deletion}`. The route
does not run inside the target's owner lifetime, so the saga's drain cannot
wait on its own request. Apply migration `20261026010000_admin_account_deletions`
before deploying this API.

View responses contain `rows`, optional `total`, `nextCursor`, `note`, and `checkedAt`.
The usage-accuracy update adds `asOf` (one observation time per read snapshot),
report `window: {from: string|null, until: string, timezone: "UTC"}`, `reportScope`
and `summary`. `checkedAt` is response completion, not a provider verification.
Trial rows may also return `trialStatus: NOT_STARTED` when their start is in the
future; the console displays “ยังไม่เริ่ม” rather than active/expired.
Member details add an explicit `quotaPostUnits` alias for legacy monthly `postUnits`
and a UTC `window`; existing fields keep their meanings. Related database reads
share one bounded, read-only RepeatableRead transaction per request. Separate
requests/page loads may observe later writes; pagination is not a frozen export.
Pages contain at most 50 rows. Posts/audit sort newest first with stable tie-breaks.
`view=reports,csv=true` exports the current page only with spreadsheet-formula-safe
CSV. Search text stays in POST bodies rather than URLs. The new console starts by
explicitly requesting all registered accounts, including accounts with no trial
or usage. Existing clients that omit `reportScope` retain latest-trial reports
and the legacy CSV filename. Latest-trial
scope intersects the requested range with each latest trial's start and earliest
expiry/revocation/observation time. Missing `from` includes all retained history;
`until` is exclusive and capped at `asOf`. The UI initially chooses the current
UTC month. Results for empty/intersected-out ranges are zero, not omitted accounts.

Report `summary` covers all search-matching accounts before the cursor, with
`memberCount`, `captionRequests`, `editMinutes`, `quotaPostUnits`, `postUnits`,
`livePostUnits`, `draftPostUnits`, `otherDeliveredPostUnits`, `failedPostUnits`,
`pendingPostUnits`, and nullable `estimatedUsd`. Rows contain the same usage fields
plus `userId`, `email`, `purchasedPlanNow`, nullable latest-trial fields and
`usageFrom`/`usageUntil`. Report `postUnits` remains the number of recorded
PlatformPublish rows by their creation date. `quotaPostUnits` sums selected
platforms on Post rows by Post creation date, preserving current quota rules.
Live/draft/other count only successful deliveries; other includes private,
unlisted and unknown visibility. Failed and pending/publishing remain separate.
These are current stored outcomes for records created in the selected range,
not counts of state-transition events during the range. AI usage includes
reserved/consumed records, not only successful results. Costs use recorded
delivery rows and configured rates, remain null without rates, and are not
invoices or proof of paid conversion. CSV still exports only the displayed page;
CSV reads a fresh snapshot using the displayed page's applied filters/cursor;
its numbers can change after the screen was loaded. The all-account filename is `postdee-usage-report.csv`, latest-trial filename stays
`postdee-trial-report.csv`. Source `fc457b2` is merged/pushed to main and Live on
Staging deploy `dep-dba64iqjnfac73egt8i0` at 13:10:11 Bangkok on 18 October 2026.
Health/readiness, exact source assets, fresh Firebase owner login and real
all-account/empty-trial report reads pass. Omitted-scope/legacy CSV compatibility
is covered by local route/compiled checks; it is not yet claimed as a separate
live legacy-client request. No schema, flag, worker contract or Mobile change
is required. Exact verification and limits are in the
[usage accuracy receipt](docs/superpowers/plans/2026-10-18-admin-usage-accuracy.md).

Staging admin UX follow-up (`50fba5e`): overview `label`, post `channels` and
`failureReason` are Thai presentation strings. Post `status` and status/platform
filter enum values retain their existing contract. Successful delivery may be a
draft: `DRAFT` explicitly means not yet published; `PRIVATE`/`UNLISTED` keep their
visibility labels; missing delivery outcome does not imply publication. These
strings describe stored results, not a fresh provider visibility check. Member
inspection uses the existing read endpoint; only explicit final confirmation
submits the unchanged owner-only trial command.

Trial commands contain a UUID `requestId`, `userId`, reviewed `expectedEmail`,
`action` (`GRANT`/`EXTEND`/`REVOKE`), `plan` (`STARTER`/`PRO`), `days` (7/14/30),
`expectedVersion` (0 for no prior trial) and a 3–500-character `reason`. The server
sets actor UID, validates the target identity again inside the transaction, locks
the active target owner, and commits trial plus audit together. Exact request replay
returns the original result; altered intent or stale version returns 409. Extensions
preserve the trial plan and are limited to 90 days ahead. Success returns
`{status:"ok",trial:{userId,plan,startsAt,expiresAt,revokedAt,version}}`.
Errors expose a safe `code`, including `ADMIN_OWNER_REQUIRED` (403),
`ADMIN_REAUTH_REQUIRED` (401), `ADMIN_TRIAL_CHANGED` (409),
`ADMIN_MEMBER_NOT_FOUND` (404), and `ADMIN_TRIAL_UNAVAILABLE` (503, retry same UUID).

When `TRIAL_ACCESS_ENABLED=true`, normal billing/subscription and capability gates
return the higher valid paid/trial `plan`, with a separate `purchasedPlan` for
purchase confirmation. RevenueCat resync retains its legacy paid `plan`, adds
`effectivePlan` for access and `purchasedPlan` when trials are enabled; its
`subscription` remains the purchased RevenueCat result. Mobile AI recovery reloads
current access, while billing confirmation polls the purchased plan. A trial is
never accepted as evidence of a store purchase. Purchase readiness retains its
`preparationProtocol:1` acknowledgement; clients must send
`purchaseConfirmationProtocol:2` before buying when effective access exceeds paid
access. Older clients receive `PURCHASE_READINESS_UNSUPPORTED` (409) before payment.
Paid receipts and usage counters are not rewritten by trial grants. See
[deployment and data boundaries](docs/ADMIN_CONSOLE.md).

## Channel publishing preflight (2026-10-15, Staging delivered)

`GET /social-connections/publishing-readiness` requires authentication and returns
`Cache-Control: private, no-store`. It reads only the caller's existing local
connections and stored PostPeer profile ID, then lists that profile's integrations.
It never creates/finds a profile remotely, synchronizes accounts, repairs stored
connections or sends a provider POST. Query parameters cannot select another
owner/profile/account. Owner activity, profile binding and connection revisions
are checked around the bounded provider GET; a read-only failure completes the
owner lifetime normally so it cannot retain an ambiguous-write deletion blocker.

```json
{
  "status": "ok",
  "checkedAt": "2026-10-15T10:00:00.000Z",
  "connections": [
    {
      "platform": "INSTAGRAM_REELS",
      "connectionId": "<local connection id>",
      "connectionRevision": "<opaque 64-character SHA-256 revision>",
      "state": "ready"
    }
  ]
}
```

All four supported platforms are returned. `connectionId`/`connectionRevision`
are optional for disconnected entries; revisions cover every platform and never
expose provider IDs. States are `ready`, `connected`, `reconnect_required`,
`permission_missing`, `not_connected`, or `unavailable`. Only explicit boolean
`platformMetadata.capabilities.publish: true` can produce `ready`, provided no
explicit `tokenStatus.reconnectRequired: true` is present. Explicit false publish
capability produces `permission_missing`; a reconnect flag or missing stored
integration produces `reconnect_required`. Unknown capability metadata remains
`connected` with `PUBLISH_CAPABILITY_UNCONFIRMED`, not an invented permission.
Other safe reason codes are `NOT_CONNECTED`, `PROVIDER_PROFILE_MISSING`,
`PROVIDER_INTEGRATION_MISSING`, `PROVIDER_RECONNECT_REQUIRED`, and
`PUBLISH_PERMISSION_MISSING`. Provider reasons, credentials and external IDs are
never returned. Unconfigured/failed provider lookup returns safe HTTP 503
`PUBLISHING_READINESS_UNAVAILABLE`; a connection/profile replacement during the
lookup returns HTTP 409 `SOCIAL_CONNECTIONS_CHANGED`.
Ordinary `GET /social-connections` listings now include that same opaque
`connectionRevision` for YouTube, Instagram and Facebook as well as TikTok, so
clients can compare identities across separate list/readiness requests. No
provider integration ID is added to the public connection DTO.

This response is a snapshot at `checkedAt`, not a guarantee of future provider
permissions or actual publication. Existing APIs without the route produce 404;
new Mobile uses only that absence as its compatibility fallback. A 503 is an
error and blocks a new submission. Unknown, successfully read capabilities remain
usable with an unverified label; this check does not add provider lookups to old
accepted requests or scheduled worker jobs.

New post captions are checked before upload-readiness/provider lookup, plan/quota
work or post creation: YouTube descriptions allow at most 5,000 UTF-8 bytes and no
`<`/`>`; Instagram uses a conservative 2,200 UTF-16-unit cap; Facebook uses a
conservative 63,206 UTF-16-unit cap, matching Mobile. No user text is truncated.
HTTP 400 `PLATFORM_CAPTION_INVALID` contains a safe `platform`, `reason`, `message`
and optional `maxLength`/`unit` (`utf8_bytes` or `utf16_units`). Reasons are
`YOUTUBE_DESCRIPTION_TOO_LONG`, `YOUTUBE_DESCRIPTION_INVALID_CHARACTERS`,
`INSTAGRAM_CAPTION_TOO_LONG`, or `FACEBOOK_CAPTION_TOO_LONG`. The publisher repeats
the guard before account/media/provider work. Matching already accepted
idempotent requests recover the original intent before new-request validation;
TikTok's existing Direct-only caption rule and Inbox behavior are unchanged.
Since 2026-10-24 (security Batch 5) new posts also reject any shared or
per-platform caption longer than 63,206 UTF-16 units, the largest supported
platform cap, with reason `CAPTION_TOO_LONG`. This bounds TikTok Inbox captions,
which had no ceiling below the 1 MiB body limit. The check runs only when a post
is created; already queued posts are not re-checked by the publisher.

`POST /posts/submissions/recover` is an authenticated, strictly read-only lookup;
POST keeps the private caption and original intent out of URLs/access logs. Send
the original `clientRequestId`, `caption`, `videoS3Key`, `platforms` and any original
`platformSettings`, `scheduledAt`, `coverImageS3Key`, `coverFrameTimeMs`, or
`mediaContentFingerprint`. Stored legacy settings are accepted for comparison.
Only this recovery route may fill an omitted Facebook entry with the known
historical `PUBLISH` default when the other selected platform entries are present
and valid. It never infers a current choice or matches an accepted `PAGE_DRAFT`;
malformed/other missing entries remain invalid and new `POST /posts` stays strict.
The server resolves only the authenticated owner's request and verifies the same
immutable intent comparison used by creation. Owner activity is checked before
and after lookup under the durable owner lifetime. Errors are caught inside that
lifetime; the outer router exempts only this exact read-only POST path from
500-response remote-write uncertainty retention, without weakening other routes.

A match returns HTTP 200 `{status: "ok", post, idempotentReplay: true, recovered:
true}` with the ordinary public post shape and no internal target/fingerprint.
The stored status is unchanged, including `FAILED`; recovery never means a failed
post was published. Missing owner-scoped requests return HTTP 404
`POST_SUBMISSION_NOT_FOUND`; changed intent returns HTTP 409
`IDEMPOTENCY_KEY_REUSED`; malformed input returns HTTP 400
`INVALID_POST_SUBMISSION_RECOVERY`; unavailable lookup returns safe HTTP 503
`POST_SUBMISSION_RECOVERY_UNAVAILABLE`. There is no create, plan/quota/media/provider
check, queue enqueue or queue repair. Mobile can recover a previously accepted
receipt before applying new submission guards, retaining failed/unverified drafts
and unknown request IDs rather than uploading or publishing them again.

Media/codec/duration preflight is performed by Mobile on the actual outgoing file.
It is not a new server-verified media assertion or API field. No database/schema,
dependency or environment change is required. Source `2e86634` is on main and
Live on Staging deploy `dep-db8focbrjlhs73bs5s90`, followed by the data-preserving
Android **12023** update. Exact-source Backend/Flutter CI `38766556966` and unsigned
iOS build `38766556987` pass. Public health returns HTTP 200; unauthenticated
readiness and recovery requests return HTTP 401. The logged-in real Mobile
client against Staging reads connections/readiness with matching TikTok/YouTube
revisions and unknown capabilities labeled `connected`, not `ready`.
Instagram/Facebook remain disconnected; no real publication was attempted.
Local suites, native diagnostic results and delivery evidence are recorded in
[the implementation record](docs/superpowers/plans/2026-10-15-platform-publish-preflight.md).

## TikTok Direct Post contract (2026-10-15, Staging delivered)

`GET /social-connections/TIKTOK/publishing-options` is authenticated and returns
`Cache-Control: private, no-store`. The server resolves only the caller's stored
TikTok connection; callers cannot select a provider account ID. It checks the
owner's active state and account revision around the bounded provider request.
The response is `{ status: "ok", connectionId, creatorInfoRevision, creatorInfo }`.
`creatorInfo` contains `creatorAvatarUrl`, `creatorUsername`, `creatorNickname`,
`privacyLevelOptions`, `commentDisabled`, `duetDisabled`, `stitchDisabled`, and
`maxVideoPostDurationSec`. An unavailable/malformed response disables Direct
instead of supplying default permissions. Connection listings expose an optional
local `connectionId` and opaque `connectionRevision`, never the provider ID.

New explicit TikTok Direct settings contain all of these fields:

```json
{
  "publishMode": "DIRECT_POST",
  "creatorInfoRevision": "<64 lowercase hexadecimal characters from publishing-options>",
  "privacyLevel": "PUBLIC_TO_EVERYONE",
  "disableComment": true,
  "disableDuet": true,
  "disableStitch": true,
  "brandContentToggle": false,
  "brandOrganicToggle": false,
  "isAigc": false,
  "videoDurationSeconds": 30,
  "musicUsageConfirmed": true,
  "brandedContentPolicyConfirmed": false
}
```

This example is not a default selection. Privacy must be explicitly chosen from
the latest creator response: `PUBLIC_TO_EVERYONE`, `MUTUAL_FOLLOW_FRIENDS`,
`FOLLOWER_OF_CREATOR`, or `SELF_ONLY`. Interactions cannot override account
restrictions. Branded third-party content requires policy confirmation and cannot
use `SELF_ONLY`. The clip duration must fit both the creator's current limit and
the API upload limit of 600 seconds; Mobile uses prepared media metadata.
Direct video captions are limited to 2,200 UTF-16 code units. An oversized caption
returns `400 TIKTOK_CAPTION_TOO_LONG` before creator lookup, quota or enqueue;
Mobile stops before draft save/upload and the worker repeats the same guard.

The API rechecks current options and the account revision before any new post,
quota reservation or enqueue, and the worker checks again before CREATE,
including scheduled posts. It never changes the requested privacy or converts
Direct to Inbox automatically. Complete settings participate in idempotent intent
comparison. Consent/revision data stays in the internal settings snapshot; only
documented TikTok flags are forwarded to PostPeer.

Inbox retains `{ "publishMode": "INBOX_DRAFT" }`. Legacy missing settings and
persisted two-field `DIRECT_POST`/`SELF_ONLY` remain compatible. New Direct
publication requires final selected TikTok status and a valid Direct video
reference/receipt; a messages URL or Inbox receipt cannot prove it. Ambiguous
accepted responses use bounded GET reconciliation and never replay CREATE.
Final Direct receipts support the documented `v_pub_file~v2-1.<digits>` form as
well as the observed v2 receipt family; neither is fabricated into a public URL.
`PRIVATE` means `SELF_ONLY`; `LIVE` means published to the selected audience,
including friends/followers, and does not by itself mean public visibility.

No database migration or historical post repair is added. Source `5681602` is
Live on Staging deploy `dep-db8ep7brjlhs73e46qc0`, with health/readiness HTTP 200
and unauthenticated publishing-options HTTP 401. Installed Android Staging 12022
successfully fetched account-bound options through the new route without an
upload or publication. Other environments must deploy API first; older APIs
without publishing-options leave Direct unavailable in new Mobile. Provider
audit/public approval and real Direct publication remain unverified.
Validation/release evidence is maintained in
[the feature record](docs/superpowers/plans/2026-10-15-tiktok-direct-post.md).

## TikTok Inbox CREATE confirmation (2026-10-15, Staging delivered)

No client request/response shape changes. PostPeer's documented CREATE
example lacks the selected-platform status and Inbox ID available from canonical
GET. A later local failure reproduces with that injected shape; its original raw
CREATE response is unavailable, so the incident explanation remains an inference.
The adapter follow-up uses only a genuine CREATE PostPeer ID for bounded GET
confirmation of requested INBOX_DRAFT when the successful selected summary lacks
status/ID. DRAFT still requires the strict selected
TikTok receipt; parent/URL success alone, another platform's result or a mismatched
GET post ID cannot confirm it. No POST retry, quota/mode/schema change or automatic
historical repair is introduced. After 21 regression-first failures, all 102
publisher tests and all 1,981 API tests pass, with typecheck/build, Prisma checks,
two compiled smokes and no blocking review finding. Source `e191ed7` is on main
and Live on Staging deploy `dep-db8dr449v7es738gr9vg`; CI `38747979249` passes
Backend/Mobile. Health/readiness, 18 migrations/no pending and the empty-backlog
guard pass. A separate guarded repair corrects only the matched parent/receipt
to PUBLISHED/DRAFT with its original handoff time and no live URL/error.
Independent readback and APK12021 Calendar/detail confirm `ส่งเป็นร่างแล้ว`.
The five unresolved operation markers remain untouched; no resend or new APK is
included. User-side Inbox/public publication is unverified. The earlier repair
stays separate. Receipt:
`docs/superpowers/plans/2026-10-15-tiktok-inbox-create-confirmation.md`.

## TikTok Inbox completion mapping (2026-10-15, Staging delivered)

No request/response shape changes. For requested TikTok INBOX_DRAFT, a completed
selected-platform result with a strict `v_inbox_url~v2.<digits>` or
`v_inbox_file~v2.<digits>` receipt and a genuine PostPeer post ID confirms the
existing `PUBLISHED` platform status with `deliveryOutcome: DRAFT`. It does not
confirm a public TikTok video. The messages URL is not exposed as a live-post
reference. Failure/pending checks and explicit draft compatibility remain.
Inbox receipts cannot confirm Direct Post/private/live delivery. A messages URL
alone, ordinary video ID or missing provider ID is insufficient. Historical
FAILED records are not rewritten by deploying this mapper. All 1,947 API tests,
typecheck/build, Prisma checks and compiled worker smoke pass. Source `7a55fe8`
is on main and Live on Staging deploy `dep-db8d6gss728c7391ajp0` after exact-head
CI `38741265826` passes Backend API (119 files / 1,947 tests) and Mobile
(2,252 tests/analysis). Health/readiness return HTTP200; all 18 existing
migrations are applied and the empty-backlog guard passes. No request/schema,
environment/configuration, Production or APK12021 change is included. A separate
guarded repair corrects only the matched historical parent/receipt to
`PUBLISHED` with DRAFT delivery, retaining its provider ID and original handoff
time, with no live reference/error or provider resend. Independent readback and
Calendar/detail confirm `ส่งเป็นร่างแล้ว`; all five unresolved operation markers
remain untouched. This does not confirm user-side Inbox completion or public
publication. Evidence:
`docs/superpowers/plans/2026-10-15-tiktok-inbox-delivery-status.md`.

## TikTok native completion correction (2026-10-15, local Mobile app updated)

The mobile correction for lost FFprobe/FFmpeg completion events changes neither
requests nor response contracts. Native preparation still completes and validates
media before any remote upload, including normalized 360–4096-pixel dimensions.
The client-local v2 preparation receipt prevents reuse of older unvalidated media;
the existing explicit-new-attempt guard preserves legacy receipts and IDs.
Existing request IDs, owner guards, platform results, and Calendar `GET /posts`
remain intact. This mobile correction requires no migration or provider
configuration; its source is included in the combined main/Staging delivery
above. Mobile analysis and all 2,252 tests pass;
APK 12021 is installed locally with the account/draft retained. These native
checks do not prove provider delivery; the later user-created Inbox result and
repaired history are recorded above. The earlier account check showed Free 0/3
and an unverified phone, which blocks the free allowance under existing rules.
Verification and APK status:
`docs/superpowers/plans/2026-10-15-tiktok-native-session-completion.md`.

## Calendar activity and TikTok validation (2026-10-15, Staging delivered)

Calendar uses the existing authenticated `GET /posts` without `scheduled=true`,
`includeMedia`, or a preview limit. This returns the owner's complete post list,
including immediate activity with a missing/null `scheduledAt`. The new Mobile
Calendar DTO permits that optional schedule; `GET /posts?scheduled=true`, the
strict scheduled DTO, and scheduled mutation routes remain unchanged. Calendar
shows finished activity at `publishedAt`, falling back to its real schedule or
creation time; queued activity uses its real schedule or creation time. Queue
mutations still require `QUEUED` plus an actual schedule.

No response field or migration is added for TikTok media validation. For the
allowlisted TikTok `frame_rate_check_failed` terminal provider rejection, the
existing platform-result `errorMessage` now carries a fixed safe explanation.
Other errors retain the existing generic message and secret-free logging. Old
historical generic errors are not relabelled. New Mobile builds localize the
fixed message and prepare/validate TikTok media before calling upload routes.
An older Mobile build can display the fixed English string safely. Prefer API
delivery before the updated APK; Calendar's unfiltered route already exists.
Source `0f2941b` is on main and Live on Staging deployment
`dep-db8bdj2vcj2c738t2ke0`, after exact-head CI `38725833299` passes Backend and
Mobile. Health/readiness return HTTP200; all 18 existing migrations are applied.
The retained postpeer/memory configuration passes its empty-backlog startup
guard. Historical posts are neither rewritten nor retried during delivery.
See `docs/superpowers/plans/2026-10-14-tiktok-media-and-calendar-activity.md` for
verification and delivery status; older dated scheduled-only UI notes below
describe their original releases.

## Main integration boundary (2026-10-13, completed)

Verified main is fast-forwarded and pushed to feature head
`be7732f6a14f9f91e6eda4a39179b30c385427ab` after exact-head CI `38386971185`
passed Backend and Mobile. Integration adds no API/schema/config/dependency
patch beyond that verified branch. Runtime matches Staging Live `7b0c51d`;
post-push health/readiness return HTTP200 with database/queueok. No new migration
run or Production deployment; Production API/database remain user-suspended and
Staging auto-deploy disabled. Preserve prior8016 and Oct12 delivery receipts;
“no main merge” was true at those historical deliveries. Plan:
`docs/superpowers/plans/2026-10-13-main-motion-audit-integration.md`.

## Mobile motion audit boundary (2026-10-12, Staging delivered)

The cross-screen audit changes presentation guards and thumbnail lifecycle only.
Keep API requests/owner scope, AI/save/publish triggers, entitlement/scheduling,
billing and persistence contracts unchanged. Public-preview entrance settles
when interrupted without replay; requested ambient effects may resume. No new
endpoint, quota rule, provider/configuration/dependency, schema or migration.
Final source passes 2,058 Flutter tests and analysis (No issues, 8.6 s); exact
Staging x64 4016/8016 build/install and safe native navigation preserve data.
Native AI, Save, OAuth, purchase and publication were not invoked; positive
business paths use fixtures. Diagnostic debug frames do not certify production
FPS or prove a before/after speedup. Combined source
`7b0c51d71090e5c080182daa8630d5b90e6d3d49` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38249605630` passed Backend
and Mobile/2,058 tests/analysis14.2 s. CI APK build/upload was skipped; local8016
remains installed. Render `dep-db6d96vavr4c73b21o2g` is Live at 19:39:44 GMT+7
with 16 existing migrations/no pending and health/readiness HTTP200. Publishing
stays disabled/queue memory; post-Live safe navigation retains account/shop data.
No new API/schema/config/dependency or migration, no main merge and no second
source deployment for the docs-only receipt. Keep initial8015 proof separate. Plan:
`docs/superpowers/plans/2026-10-12-mobile-motion-smoothness-audit.md`.

## Bottom navigation presentation boundary (2026-10-12, Staging delivered)

Dock icon selection/press feedback changes presentation only. Existing tab
callbacks, guarded `/create-post` navigation, owner/request scope and all API/
billing/publishing contracts retain their triggers. No new request, persistence,
quota, provider, schema/config/dependency or migration. Initial dock-only source
passed 1,979 Flutter tests and analysis, including 13 new cases; APK4015/8015 was
installed then with native navigation/composer open-close preserving data.
Guard/accessibility paths use fixtures, with no real mutations. Combined source
`7b0c51d` passed CI `38249605630` and is Live through
`dep-db6d96vavr4c73b21o2g`; current installed8016 has the separate 2,058-test audit
receipt. API contracts remain unchanged; no new migration or main merge.
Plan:
`docs/superpowers/plans/2026-10-12-bottom-nav-ui-motion.md`.

## Account mobile motion boundary (2026-10-12, Staging delivered)

The approved Account-only presentation follow-up adds finite entrance/press
feedback, without a new request, persistence trigger, quota, price or entitlement
rule. Profile/request ownership, existing subscription refresh, phone/email
verification and account/billing callbacks retain their contracts and guards.
Native QA browsed and dismissed only; positive mutations use controlled
fixtures. Final source passes 1,966 Flutter tests and analysis, including 29 new
Account cases. Exact Staging x64 APK 4014/8014 is built/installed with the retained
account. Native read/browse/dismiss/tab-return checks retain account/settings/
scroll; no verification, OAuth, purchase, delete or sign-out action was performed.
No API/schema/config/dependency change or new migration. Combined source
`904a3f89c3601a1fac28eedfaf8781434b19bd49` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38205149761` passed both jobs
with 1,966 Mobile tests. Render `dep-db66eh8473hc73dabfcg` is Live at 11:53:11
GMT+7; 16 existing migrations/no pending and health/readiness HTTP 200 with
database/queue ready. Publishing stays disabled/queue memory; installed 8014
and post-Live account/shop data are retained. No main merge. Plan:
`docs/superpowers/plans/2026-10-12-account-ui-motion.md`.

## Shop-link mobile motion boundary (2026-10-12, Staging delivered)

The approved manager/theme motion follow-up changes presentation only. Existing
owner-scoped local autosave/image protection and explicit publish/update/
unpublish/confirmed-URL requests retain their triggers and contracts. Section,
category, press and drag feedback add no request, persistence trigger, quota,
provider mapping, schema/config/dependency change or migration. Public page
motion and the 100-template catalog remain unchanged. The earlier Shop-only source passed
1,937 Flutter tests and analysis, including 22 new motion cases; exact Staging
x64 APK 4013/8013 was installed at that Shop release with the account/shop data retained. Native read/
browse/cancel/navigation checks pass; mutation/Save/Apply/publication paths use
controlled fixtures. No new backend suite or migration execution was required by
local UI verification. Combined source `904a3f8` passed CI `38205149761` and is
Live via `dep-db66eh8473hc73dabfcg`; installed 8014 is retained. Post-Live Shop
remains published/saved clean with its two original links/confirmed URL. Plan:
`docs/superpowers/plans/2026-10-12-shop-link-ui-motion.md`.

## Calendar compact composition (2026-10-12, Staging delivered)

The implemented Calendar UI keeps `GET /posts?scheduled=true` and the existing
owner-scoped post mutation/detail routes. Week/month/day counts and platform
filters are mobile projections; each matching post counts once, even with
multiple destinations. Selected-date handoff is local composer input, not a
new API field or automatic post. Existing future-only RFC 3339 conversion,
Starter 14-day/Pro 30-day limits, subscription checks, publishing kill switch and
queue-only reschedule/cancel rules remain authoritative. No backend contract,
schema or migration is required by this revision. Composer relative-date labels
share its injected local clock; the default remains `DateTime.now`.
Authorized SHA `3368f4d` is pushed. Exact-source CI `38187776818` passes 1,883
Flutter tests and 1,781 Backend tests/109 files, generator checks, build, Prisma
validation and the high-severity production audit threshold (four moderate,
zero high findings). API source is unchanged. Local APK 4007/8007 installs with
retained data/session and a post-deploy Home cold-launch smoke; full native Calendar/composer
checks belong to the preceding 8006 revision. Positive queue/partial/mutations
remain fixtures for the empty real account. Render deploy
`dep-db62jdvlot8c738l37q0` is Live with this exact source at 07:30:34 GMT+7 on
2026-10-12; 16 existing migrations have none pending and `/health` plus `/ready`
return HTTP 200. No new migration is added; Staging social publishing remains
disabled. Source identity is verified in Render checkout/UI, not the health
response. Evidence:
`docs/superpowers/plans/2026-10-11-calendar-ux.md`.

### Calendar motion follow-up (2026-10-12, Staging delivered)

The press, selection, week/month-size, current-day entrance and initial-loading
skeleton effects are mobile-only presentation. They add no request, endpoint,
response field, entitlement change, dependency, environment setting or database
migration. Silent refresh retains confirmed content; current owner/mutation
guards, selected-date handoff and scheduling validation remain authoritative.
Reduced motion, inactive tabs and background state stop effects. Authorized
source `df8df1d` is pushed; exact-source CI `38189859822` rechecks the unchanged
API with 1,781 tests/109 files, 22 generator checks, build, Prisma validation and
the high-severity production audit threshold (four moderate findings remain).
Flutter checks pass 1,891 tests and analysis. Render deploy
`dep-db6327ajnfac73c7vr90` is Live at 08:02:20 GMT+7; 16 existing migrations
have none pending and health/readiness return HTTP 200. Source identity comes
from checkout/Render UI, not the health response. At that Calendar release,
local Staging APK 4008/8008 was installed; post-Live native refresh preserved
the selected date/filter and account state. The later guided revision updates
the local APK. These checks are a separate receipt in the Calendar plan;
the preceding Staging/health receipt does not verify this follow-up.

## Home read composition (2026-10-11, Staging delivered)

The Home revision composes existing authenticated subscription, social
connection, scheduled-post and profile-link reads. Recent previews retain
`GET /posts?includeMedia=true&limit=3`; saved publish drafts come from the
current stable UID's device-local draft store rather than an API endpoint.
Mobile selects the earliest future `QUEUED` scheduled post and does not derive
an all-post count from the recent-three response. A failed connection lookup
is unknown, not zero connections; a connected flag is not token-health or
publishing-readiness evidence. The profile shortcut requires the server's
`isPublished` and confirmed `publicUrl` to report a published page.
Existing subscription entitlement/quota behavior and partial/unknown delivery
outcomes remain authoritative. No route, response field, schema, provider,
analytics call or package contract is added; `apps/api` source remains unchanged.
Local API regression checks pass: 1,781 tests across 109 files, build, Prisma
validation against a dummy local connection string and helper type-check on
the unchanged API source. The base Staging mobile version 8003 reads the existing subscription,
connections and published-profile state and opens the empty native Calendar.
Positive future-queue and partial/unknown outcomes are covered by automated
fixtures; no real post was created for this check. No database migration or
API contract change is required. These are pre-delivery local receipts.
Feature source `ce89a0e464517f87f5902dd8ab32c764f2e67a72` is pushed, passes
exact-source CI `38125004499` and is Live on Staging through Render deploy
`dep-db5kk4h42hec739a7gg0`. CI rechecks the unchanged API: 1,781 tests/109 files,
22/22 generator checks, build, Prisma and high-severity production audit pass.
Render reports all 16 existing migrations applied with none pending;
post-Live `/health` and `/ready` return 200, with database/queue ready and
readiness marked `no-store`. Detailed
mobile build/native evidence:
`docs/superpowers/plans/2026-10-11-home-ux.md`.

The subsequent cover/motion/pull-to-refresh follow-up is mobile-only and passes
the final 1,863-test Flutter suite. Its step hint is computed from existing saved-draft
fields, not a new persisted current-step field or API response. Cover fallback
reads a muted paused local first video frame with a five-second initialization
limit and a compact 120 logical-pixel cropped presentation; it creates no upload,
thumbnail file or FFmpeg job. Refresh awaits the
same authenticated plan/posts/connections/queue/profile reads plus owner-local
drafts, coalesces same-owner requests and preserves previously loaded content,
including known empty results. No new endpoint, statistics request or API schema
is needed. A failed section retains its error/retry state
rather than an all-sections success claim; owner changes invalidate late results.
Intermediate native version 8004 reads the existing live plan/connection/profile
state. Frozen-source version 8005 is built/installed; analysis and native
notification/pull-refresh/create-and-close checks pass without saving. The
final local full mobile suite passed in 2m54s; exact-source CI also passes all
1,863 Mobile tests and analysis. This rollout changes no API contract or
provider mode. Post-Live native version 8005 refreshes the same Free 0/3 and
connections 0/4 without writes; positive draft/cover cases remain fixture-only.
CI intentionally skips APK build/upload; the verified local Staging debug/Test
Store APK remains installed. Main and Production remain unchanged.

## Audit-fix rollout (2026-10-09, Staging)

- `POST /posts` accepts optional `mediaContentFingerprint`, a lowercase 64-digit
  SHA-256 identity computed from source clip, watermark mode and rendered cover.
  Matching identities permit the same draft request to replay across upload-key
  changes; differing identities return `409 IDEMPOTENCY_KEY_REUSED`.
  If either side lacks an identity, video and cover keys must match exactly.
- `DELETE /devices` accepts JSON `{ "token": "..." }`, requires authentication
  and removes that token only when it still belongs to the caller. It is
  idempotent. Push payload data now includes owner `userId` and `postId`.
- `PUT /link-in-bio/draft-images` accepts `{ "draftId": "...", "keys": [],
  "mode": "add" }` or `mode: "replace"`. At most three owned image keys are
  accepted. New mobile clients send a 32-hex device base plus `_revision` as
  `draftId`, persisting its increasing safe-integer revision before requests.
  Delayed `replace` only removes that base's references at the request revision
  or earlier; it cannot release newer or other-device references. Add new
  protections before committing a local draft, then replace its old references.
  `POST /link-in-bio/images` accepts that optional `draftId`; older clients that
  omit it upload retained legacy images. Claimed/deleted images cannot be pinned.
- Provider failures on either caption endpoint return an explicit
  `isFallback: true` with `quota.charged: false` after releasing the exact usage
  reservation. If release fails or a custom adapter lacks release support,
  `charged: true` reports the remaining charge rather than promising a refund.
  If recount fails after a committed refund, `quota.usageRefreshPending: true`
  accompanies the last known conservative count; the next subscription refresh
  reads the authoritative ledger. Legacy transcription errors also release
  their exact reservation while preserving the existing error response.
  Successful provider/local-scaffold paths retain their prior quota behavior.

Staging API `9f0b729` is Live on 2026-10-09 with all 16 migrations applied and none
pending, including both additive audit migrations. For other environments,
apply migrations and regenerate Prisma before API and then mobile.
No provider or billing configuration is activated by this patch. Direct live
route/readiness checks remain unverified because browser access is blocked.
See `docs/superpowers/plans/2026-10-09-system-audit-fixes.md` for legacy recovery
and delivery limits.

This document describes the current Express + TypeScript API in `apps/api`.
Implemented adapters remain mock-safe for local development, while production
readiness for social publishing, live analytics, Cloudflare R2, real-clip AI
captioning, Firebase, Apple App Store, and
Google Play still depends on the provider/device release gates listed below.

The 2026-10-08 pending-work integration adds `/ready`, optional bounded media
URLs on `GET /posts`, and guard coverage for mutating reads within the existing
account mutation barrier. Main already prepares relational users in its routes
after their validation/quota gates; this integration does not add a generic
duplicate preparation step. No migration or provider activation is required.
Source `36dbaccb1d23ee46f9c970f2fdd8fff3d32b01d0` is pushed/on main; exact-source
CI `37754460435` passed both API/Mobile jobs. Staging deploy
`dep-db3m2g59fdbs73ecbib0` became Live on 2026-10-08 at source
`9baa18c3483b2abd9b6f0ac619e74c00e15cbec6`, with the same API/runtime code.
Current source verification and delivery are recorded in
`docs/superpowers/plans/2026-10-08-integrate-pending-main-work.md`.

Health/readiness, authenticated empty-owner contracts and separate R2 fixture
delivery/range/cleanup pass. The owner has zero posts, so actual nonempty
Home media and two-authorized-owner isolation remain unverified; full results
and unchanged publishing/Production limits are in the integration plan above.

## Base URL

Local default:

```text
http://localhost:4000
```

Backend path:

```text
apps/api
```

## Profile Links (2026-10-05)

Profile links replace AI video editing in the active mobile product. Since
2026-10-24 the AI editing routes documented later answer `410
AI_EDITING_RETIRED` unless `AI_EDITING_ENABLED=true`; they are not package
benefits.
One profile page per authenticated account is available on every package.
Production persistence follows `POST_STORE=prisma` and requires the new
LinkInBioProfile migration; memory mode is development-only scaffolding.

| Route | Authentication | Behavior |
| --- | --- | --- |
| `GET /link-in-bio` | Required | Return only the current account's profile, or `profile: null` |
| `POST /link-in-bio/publish` | Required | Atomically create/update and publish the current account's page |
| `DELETE /link-in-bio/publish` | Required | Hide the page while retaining its saved links and reserved slug |
| `GET /p/:slug` | Public | Serve responsive HTML only for a published page; missing/hidden pages return 404 |
| `POST /link-in-bio/images` | Required | Validate/store a draft PNG and return its owned storage key |
| `GET /link-in-bio/image?key=...` | Required | Preview an image belonging to the current account |
| `GET /p/:slug/images/:slot` | Public | Serve only the current published logo, cover, or background image |
| `GET /profile-fonts/:file` | Public | Serve a whitelisted bundled font |
| `GET /profile-platforms/:file` | Public | Serve one of 100 allowlisted bundled platform PNGs |
| `GET /profile-decorations/:file` | Public | Serve one of eight allowlisted bundled decorative PNGs |

Publish body:

```json
{
  "storeName": "ร้านตัวอย่าง",
  "slug": "example-shop",
  "links": [{ "id": "shop", "title": "เลือกซื้อสินค้า", "url": "https://example.com/shop" }]
}
```

`storeName` and each link title are trimmed, 1–80 characters. The slug is
trimmed/lowercased ASCII, 3–40 characters, using letters/numbers and internal
hyphens. The structural publish input accepts 1–20 links, each with a unique
nonempty id up to 80 characters. Destinations are up to 2048 characters:
absolute HTTP(S) without
embedded credentials, a safe plain `mailto:` address, or a safe `tel:` number.
`mailto:` accepts one ASCII email address, without query, fragment, percent
encoding or multiple recipients; malformed address/domain syntax is rejected.
The address is at most 254 characters. Its local part is 1–64 letters, digits,
periods, underscores, pluses or hyphens, without leading/trailing/consecutive
periods; domain labels are 1–63 letters/digits with internal hyphens, and a
2–63-letter final suffix is required.
`tel:` accepts only an optional leading `+` and 7–15 digits; spaces, separators,
extensions, percent encoding and dial-control characters are rejected. Empty
contacts and other schemes, including javascript/data/file/sms, are rejected
before changing the published snapshot. The server does not fetch linked sites.
The mobile destination field normalizes a plain email address or a phone number
to `mailto:` or `tel:` before saving/publishing; the API itself accepts the
explicit schemes, not raw email/telephone strings. Only enabled custom links
are sent by the app. HTTP(S) opens with
noopener/noreferrer; email/phone links invoke the visitor's installed handler
without opening a new browser tab.

Shop-link plan limits (2026-10-26, API on Staging at `f4f39922`): every new
`POST /link-in-bio/publish`, including an update of an existing page, is limited
to Basic/free 2, Starter 7, or Pro 20 links. The request array is the enabled
subset selected by Mobile; the API does not count disabled local draft links.
The server resolves the authenticated owner's current effective plan through
the existing paid/trial rules, including active valid trials. Expired paid
access falls back to Basic unless another valid entitlement applies. Requests
within the 20-link structural ceiling but above the plan limit return HTTP 403
with the standard error `code: LINK_IN_BIO_LINK_LIMIT_EXCEEDED`, before changing
the published snapshot. The error envelope includes top-level `plan`
(`BASIC|STARTER|PRO`), numeric `maxProfileLinks`, and numeric `requestedLinks`
for the enabled payload count. If the server cannot verify the owner's
entitlement, publish returns HTTP 503 with
`code: LINK_IN_BIO_ENTITLEMENTS_UNAVAILABLE` and leaves the previous snapshot
unchanged. Production does not accept a client/header plan override.

A downgrade does not trim, hide or rewrite an already published page. Its next
explicit publish/update must use an enabled subset within the new limit.
Existing local drafts retain their links, including disabled links, for
view/edit/reorder/delete/disable. New additions count all stored links and are
blocked while that total is at or above the current 2/7/20 limit. The hard
compatibility storage/input ceiling remains 20; this does not migrate or delete
stored content. Deploy this API enforcement before the corresponding Mobile
build. Older Mobile receives the 403 safely; updated Mobile can map a missing
`maxProfileLinks` field from an older API only after a successful fresh
subscription read. This change adds no endpoint, schema migration,
dependency or provider. Exact deployment, checks and live-auth acceptance limits
are recorded in the
[implementation and compatibility plan](docs/superpowers/plans/2026-10-26-shop-link-plan-limits.md).

Success uses `{ "status": "ok", "profile": ... }`. Profile contains
`storeName`, `slug`, `links`, `isPublished`, nullable `publishedAt`, `updatedAt`,
and `publicPath` (`/p/<slug>` only when published, otherwise null). It does not
include the owner's email or tokens. The client resolves `publicPath` against
its configured API origin. A changed slug makes the old URL unavailable.

Slug conflicts return HTTP 409 with `LINK_IN_BIO_SLUG_TAKEN`. Since 2026-10-24
the same response also covers:
- A slug another owner released less than 30 days ago, by renaming or deleting
  their account. The previous owner may take back a slug they renamed away
  from; after account deletion nobody may claim it until the 30 days end. Each
  owner keeps at most their 3 most recent released slugs reserved.
- A reserved name for a new claim: `admin`, `support`, `help`, `api`,
  `official`, `www` and similar, or any slug containing `postdee`. An owner who
  already holds such a slug may keep republishing it.

Unpublishing still keeps the slug held by its owner. Invalid payloads
return 400. An unavailable durable repository returns 503 with
`LINK_IN_BIO_UNAVAILABLE`; it never silently falls back to in-memory publication.
Owner/public responses disable caching. Unpublishing or deleting an account
makes its public page unavailable. Mobile request timeouts do not prove a
publication was canceled: the app preserves the local draft and reloads server
state before subsequent publication actions.

### Customization (all packages)

Each link optionally adds `category` (0–60 characters), `icon`
(`auto|link|website|email|phone` or one of the 100 brand IDs in
`shared/profile-platforms.json`), `font`,
`textColor` and `buttonColor`. The array remains the display order; only enabled
links are published. Optional per-link styles override the corresponding page
style. Fonts are `anuphan|prompt|system`; colors are exact `#RRGGBB` values.

Publish optionally includes an `appearance` object; profile responses return
its normalized version. Omission of the entire appearance object retains previous settings.
Null/absent appearance on old rows maps to the original theme. A partial
appearance request starts from the specified preset; the current mobile client
sends the complete object:

```json
{
  "version": 1,
  "themeId": "minimal",
  "description": "สินค้าพร้อมส่ง ติดต่อได้ทุกวัน",
  "logoKey": null,
  "coverKey": null,
  "background": {
    "mode": "solid", "color": "#fff8ef", "gradientColor": "#f4e3c7",
    "imageKey": null, "overlay": 30
  },
  "surfaceColor": "#ffffff",
  "buttonColor": "#305d36",
  "buttonRadius": "rounded",
  "nameStyle": { "color": "#253529", "font": "anuphan" },
  "descriptionStyle": { "color": "#687065", "font": "anuphan" },
  "categoryStyle": { "color": "#537844", "font": "anuphan" },
  "buttonStyle": { "color": "#ffffff", "font": "anuphan" },
  "brandStyle": { "color": "#687065", "font": "anuphan" },
  "featuredLinkId": null,
  "featuredLabel": "โปรวันนี้",
  "effects": {
    "background": false, "entrance": false, "featured": false,
    "stickers": "none"
  }
}
```

Themes: `minimal|shop|pastel|dark|pink|garden|cards`; backgrounds: `solid|gradient|image`; overlay:
integer 0–80 percent black; button shape: `rounded|pill|square`. Description is
0–280 characters, featured label 0–40. A non-null featured ID must name an enabled
link in the publish request. Images are registered owned keys, never URLs.
Unknown/other-owner/missing image references fail with HTTP 400 before publication.
Malformed appearance returns 400 `LINK_IN_BIO_INVALID_INPUT`.

Optional version-1 `effects` accepts only boolean `background`, `entrance`, and
`featured`, and `stickers: none|hearts|flowers|sparkles`. Invalid types/null
objects/unsupported values fail before publication. Partial appearance requests
start from the selected preset. Earlier presets default all effects off; pink
and cards enable background/entrance with hearts/sparkles, garden enables
entrance/flowers. Featured movement defaults off. Normalized responses include
all four fields. Omission of the entire appearance retains the saved snapshot,
including effects, for legacy-client publication. Public motion uses CSS under
the nonce CSP with `prefers-reduced-motion`; no script
or third-party media fetch is introduced. Deploy API before Mobile. No schema
migration is needed; old mobile clients must update to understand new theme IDs.

The template-category revision adds optional nullable `appearance.templateId`
to version 1. Within a supplied appearance object, omitted/null `templateId`
selects the legacy theme; a non-null ID must exist in
the shared 100-template catalog (five categories, twenty each). Omitted
`themeId` defaults to that template's legacy base; an explicitly mismatched
theme/unknown ID fails with HTTP 400 before writing. Layout fields are trusted
catalog values, not client-supplied CSS. All existing appearance overrides and
owned images remain supported. Omitting the entire appearance atomically
retains the saved template and customization. Public/native pause controls are
removed; owner effects controls and OS reduced motion remain. No migration is
required. Deploy this API/catalog revision before distributing the new Mobile
build. The earlier seven-theme API can accept the legacy base theme but silently
discard `templateId`, losing the selected layout. An older mobile client that
reads a new template and sends a complete appearance without `templateId` can
also clear that selection on the new API. Only omission of the entire appearance
preserves it; update clients before editing new-template profiles and avoid an
API rollback after they are used. See
`docs/superpowers/plans/2026-10-07-profile-template-categories.md`.

Mobile picker visibility (2026-10-26 candidate) is limited to the twenty
minimal (`เรียบง่าย`) templates. The other category controls and legacy-theme
chooser are hidden in Mobile; the API still accepts all 100 known template IDs
and seven legacy theme IDs under the same validation and appearance-version
rules. Existing saved appearances and drafts are not automatically converted.
This presentation change adds no endpoint, schema, migration or configuration.

Staging deploy `dep-db302kqd0e5s73elbv9g` became Live on 2026-10-07 at
15:24:38 GMT+7 using `8d96ea66d8086c66bf800920871ac5d71c65b209`, with no pending
database migrations. This resolves the prior theme-contract mismatch: the
previous deployed code rejected `pink|garden|cards` with the generic 400 input
message. Existing failed-request messages in an open app clear on a new attempt;
deployment does not automatically publish a user's private draft.

The subsequent 100-template revision became Live at 16:18:19 GMT+7 on
2026-10-07: deploy `dep-db30rph42hec7386vvrg`, source
`fc087c4119cd46503c569879e61cddf99e402fb2`. Exact-commit CI passed and the
running Staging service normalized/rendered all 100 templates in five groups
of twenty, with no pause markup. This read-only check did not publish a test
page or change customer data. Startup reported fourteen migrations and no
pending migrations; public Staging browser/image checks remain unverified.

### Composition revision — 2026-10-07 (corrected Staging delivery)

The user accepted all fifteen A1–E3 short-page directions and their expansion
to one hundred choices. The authored catalog now assigns each category twenty
distinct allowlisted `layout.composition` values instead of the previous
five-header/four-link-treatment combinations. Composition is internal catalog
metadata, not a new publish-request field, CSS input or schema column. Existing
published template IDs are retained. The `appearance.version: 1`,
`templateId`, legacy-theme fallback and mismatch-rejection contracts above
remain unchanged. Public HTML, generated Mobile definitions, chooser thumbnails
and draft previews resolve the same catalog.

The new read-only public `GET /profile-decorations/:file` is limited to the
eight bundled PNG filenames in `apps/api/assets/profile-decorations`. Allowed
filenames are `botanical-frame.png`, `forest.png`, `meadow.png`, `paper.png`,
`letter-frame.png`, `collage-tape.png`, `gold-seal.png` and `tag-cord.png`.
Successful responses use `Content-Type: image/png`,
`Cache-Control: public, max-age=86400` and
`X-Content-Type-Options: nosniff`; unknown filenames return 404. It serves no
arbitrary path, remote URL, user upload or Pinterest image. Matching decoration
bytes are bundled in `apps/mobile/assets/images/profile_decorations`; text,
platform marks, links and page structure remain real HTML/native elements.
The existing self-only image CSP and private ownership checks for uploaded
profile images remain separate from these public built-in decorations.

There is no new database migration, credential, external provider or dependency,
and the hundred existing brand-logo files are unchanged. These are short link
pages using the existing content fields, not multi-section store websites.
Ship the revised API renderer and its bundled assets before the matching Mobile
build. Local QA passes: 1,555 API tests (104 files), 179 focused renderer/routes
tests, API build and schema/helper checks, plus the actual hundred-page 320px
browser matrix. Asset tests verify PNG headers, byte parity and filename/path
rejections. Pre-integration native tests/analysis and the local Staging APK
build also passed; that APK is not the combined release artifact. The prior
`fc087c4` CI/deploy receipt does not verify these new compositions or asset
responses. Initial integrated source `9c7fa74` passed exact-source CI `37623591224`
(1,555 API / 1,556 Flutter tests) and became Live on Staging deployment
`dep-db342ek9v7es73astung`. Read-only fixtures against compiled modules in that
instance verify all 100 templates, retained IDs, five groups of twenty distinct
compositions, eight bundled PNGs, seven legacy themes, omitted-appearance
preservation and safe route headers. Header checks use synthetic responses;
public browser/proxy and owned-image checks remain unverified under the existing
browser restriction. No live user profile is modified by these fixtures.
Manual APK CI `37627939566` also passed and built the same `9c7fa74` Mobile
source. After local re-signing, its verified APK is installed on emulator-5556
with account/draft/Flutter preferences unchanged. Native QA passes all fifteen
base previews but exposes cropped shop logos in tall frames. The follow-up
composition CSS fits uploaded `img.logo` with centered `contain` across all
100 templates; cover/background-photo cropping, initials, legacy themes and
frame geometry remain unchanged. Local API regression/full suite (1,556 tests)
and build pass. Corrected source `ae65b9d5eacddf6f9cf000bdb4efb44b4e82b3e0`
passes exact-source CI `37633935019` (104 API files / 1,556 tests, Flutter
analyze / 1,559 tests and Staging APK build) and is Live on
`dep-db35c71srm7s73e5sf1g`. Read-only compiled fixtures in the running instance
confirm all 100 owned-logo contain rules, preserved cover cropping, retained
IDs and eight PNGs; they do not make public HTTP or user-profile requests.
The matching verified/re-signed APK is installed in place on emulator-5556
with account/draft/preferences unchanged immediately after installation.
The preceding `9c7fa74` APK receipt is historical; public browser/owned-image,
iOS and physical-device checks remain unverified.
Evidence is in
`docs/superpowers/plans/2026-10-07-profile-template-categories.md`.

### Profile images

`POST /link-in-bio/images` accepts `{ "slot": "logo", "imageBase64": "..." }`,
where slot is `logo|cover|background`. The mobile gallery picker normalizes PNG
bytes before this request. Strict base64, PNG chunk structure, maximum 512 KiB
and 1280 pixels on either side are validated. SVG and arbitrary URLs are rejected.
Success is HTTP 201 `{ "status": "ok", "image": { "key": "uploads/<owner>/<uuid>/profile-logo.png" } }`.
The mobile logo-positioning follow-up crops the confirmed preview to a square
PNG of at most 512 pixels per side before applying the existing normalization.
Cancel sends no upload. This adds no server field or endpoint and leaves cover
and background selection unchanged. Delivery:
`docs/superpowers/plans/2026-10-13-shop-logo-position-main.md`.
The key can be used in any image slot owned by that account. Uploading it alone
does not publish it. Owner previews return `image/png`, and another owner gets 404.
Public image routes exist only while that slug is published and that slot has a
saved key. Page/image/owner responses are no-store; images have nosniff.

Image bytes use private R2/S3 storage in durable deployments. The API never
returns bucket URLs. Missing image repositories fail closed with 503
`LINK_IN_BIO_IMAGES_UNAVAILABLE`. Invalid bytes/keys return 400
`LINK_IN_BIO_IMAGE_INVALID`; unknown owner images return 404
`LINK_IN_BIO_IMAGE_NOT_FOUND`; reaching 20 managed images or 20 retained legacy
images returns 429 `LINK_IN_BIO_IMAGE_LIMIT` for that upload class. Total retained
metadata is bounded at 40 during transition. Existing upload rate limits apply.
On subsequent upload/publication, only managed images older than 24 hours without
saved profile, pinned-device-draft or newest-slot references can be pruned.
Legacy images stay because an offline old-client draft can still use them.
Inactive accounts are not periodically swept. Account deletion clears all images
and metadata. Explicit legacy-image cleanup remains future work.

Apply migration `20261005193000_customize_link_in_bio_profile`, regenerate Prisma,
deploy API plus bundled font assets, and only then distribute the new mobile build.
Fonts/images are served from the page origin under the existing nonce CSP.
There is no arbitrary CSS, script, custom font upload, product-card pricing,
or new paid provider in this contract.

### Bundled platform marks (2026-10-07)

`GET /profile-platforms/:file` requires no authentication and accepts only the
100 `<id>.png` filenames in `shared/profile-platforms.json`. This catalogue
retains the earlier `youtube.png`, `shopee.png`, `lazada.png`, `line.png`,
`tiktok.png`, `instagram.png`, `facebook.png`, `messenger.png`, `whatsapp.png`
and `google_maps.png` bytes and adds 90 regional/global destination marks.
The five values `auto|link|website|email|phone` have no PNG route entries;
the link `icon` contract therefore has 105 accepted values. Unknown IDs are
rejected before updating the published snapshot. Successful asset responses
use `image/png`,
`X-Content-Type-Options: nosniff` and `Cache-Control: public, max-age=86400`;
unknown filenames return 404. These files are fixed bundled assets, independent
of owner-uploaded profile images and their private storage provider. The route
does not fetch destination URLs or third-party favicons.

The renderer selects a known mark using an explicit `icon` value or
recognized destination-domain rules. Automatic HTTP(S) destinations outside
those rules use the website vector icon; `mailto:` and `tel:` use email and phone
vectors. Explicit `icon: "link"` retains the generic icon, and manual brand
overrides remain available. Brand images are decorative beside the existing link
title and use a transparent 40 x 40 slot without recoloring. Explicit trusted
source bounds for all 100 marks fit the visible artwork's longest side to 40
and center it while preserving its original aspect ratio. Larger image elements
may extend beyond the slot to omit transparent canvas margins; visible artwork
is never clipped. Full-canvas app icons retain contain sizing.
The page's `img-src 'self'` CSP remains unchanged. Existing appearance fields,
owner scope and publication semantics are retained; the contact expansion adds
the icon values and safe destination schemes documented above.

Automatic contact-brand detection uses strict host/path matching, not substring
matching: Messenger accepts `m.me`, `messenger.com` and their subdomains, plus
Facebook's `/messages` path family; WhatsApp accepts `wa.me`, `whatsapp.com` and
their subdomains. Google Maps accepts the `/maps` path family on exact hosts
`google.com`, `www.google.com`, `google.co.th` and `www.google.co.th`, plus
`maps.google.com`, `maps.google.co.th`, `maps.app.goo.gl`, and the `/maps` path
family on `goo.gl`. Arbitrary Google subdomains, non-map Google paths and
lookalike hosts do not select brand
artwork. These are local destination rules; no third-party metadata is fetched.
The mobile empty-title suggestions use recognized platform names from the
shared catalogue, plus `ส่งอีเมล` and `โทรหาร้าน`, retaining custom titles and
hostname fallback. A searchable logo picker finds names, aliases and countries;
an explicit brand or generic override remains separate from automatic matching.
Every host rule uses an exact match or a dot-delimited hostname suffix, with the
existing explicit Messenger/Maps path rules retained. For example `band.us` is
BAND while `band.com` is excluded; QQ matches `im.qq.com`/`qm.qq.com`, not all
`qq.com`; Trip.com recognizes `trip.com`, not the distinct `ctrip.com` brand.
`eleme` displays Taobao Instant Commerce, retaining searchable Ele.me aliases
after that service's December 2025 rebrand.

The earlier seven-mark background correction uses the original transparent official YouTube PNG.
Its renderer URL is `/profile-platforms/youtube.png?v=2`, bypassing the prior
one-day image cache without changing that release's seven-filename allowlist.
The other six files were unchanged. Only the added white frame fill is removed; white artwork
that belongs to a platform mark is retained.
The earlier size-normalization follow-up changed rendering geometry only,
preserving all seven PNG bytes, asset URLs, filename allowlist and response/cache
headers. The 2026-10-06 contact expansion added three filenames for its
ten-file allowlist. The 2026-10-07 expansion adds 90 more for the current
100-file allowlist; all ten earlier asset bytes and all cache headers remain.

Deploy the updated API with `apps/api/assets/profile-platforms` before expecting
new marks on the public site. Existing published profiles need no republish;
these follow-ups require no schema change or migration. Deploy the global
expansion's API/assets before distributing Mobile: older APIs reject its new
icon IDs. The earlier contact expansion also required API-first delivery for
`mailto:`/`tel:` URLs. Existing HTTP(S) payloads and icon
values remain accepted. Mobile uses byte-identical local assets, with provenance
and parity recorded in that asset folder's README. No chat/maps/email/telephone
provider integration or paid API is added. The source catalogue generates the
TypeScript/Dart definitions; `node scripts/generate-profile-platforms.mjs --check`
validates 100 unique brand IDs, generated output, PNG hashes/byte parity and
source bounds. It never fetches external assets at runtime. The curated 100
marks are not a statistical world popularity ranking. Verification and release
status are recorded in
`docs/superpowers/plans/2026-10-07-global-profile-platform-logos.md`.

## Mobile Request Deadlines

The Flutter client bounds ordinary JSON requests to 20 seconds end to end,
including authentication refresh, connection, and response-body completion.
`POST /ai-edits/transcribe`, `/ai-edits/prepare`, `/ai-edits/plan`, and caption
generation POSTs allow 120 seconds. Legacy upload PUTs and each multipart PUT
allow 180 seconds. Timeout aborts a pending request or cancels the body
subscription and raises client-local `API_REQUEST_TIMEOUT` with `ApiException`
status `408`; this is not a new server response or a guarantee that an accepted
mutation was canceled. `POST /posts` is not automatically retried, and the draft
retains its original `clientRequestId` for explicit recovery. Multipart
completion status reconciliation and signed-URL expiry retry remain unchanged.
The existing request-deadline behavior itself needs no server/schema migration
or package change. Profile-page publication separately requires its migration.

## Current Status

The backend currently supports:

- Health checks
- Mock or Firebase authentication
- Upload metadata validation, legacy mock/R2/S3 signed upload, managed R2
  multipart sessions, and signed read access scaffolding
- Authenticated config-only publishing preflight, post creation, and queue handoff
- Caption generation through mock, Gemini, or legacy OpenAI providers. The
  product direction is real-clip captioning after a video is selected. Remote
  providers retry transient failures (e.g. a Gemini 503) with backoff. Gemini
  uses the configured primary `gemini-2.5-flash-lite`, then
  `POST /captions/generate` degrades directly to the local template caption;
  no secondary Gemini model is attempted.
- Real-clip caption flow at `POST /captions/generate-from-clip`, with
  Starter/Pro mode selection, authenticated media-key ownership checks,
  optional temporary AI media cleanup, and monthly quota reservation through
  memory or Prisma-backed usage storage.
- Saved templates
- Pro-only analytics summary
- Store subscription verification scaffold for Apple App Store and Google Play
- Store server notification routes for renewal, cancel, refund, and grace-period handoff

The backend must not publish through shared PostPeer account ids in production
(startup rejects them). Production publishing resolves per-user social
connections. The existing `FACEBOOK_REELS` value requests Facebook Page Reels
through PostPeer `platform: 'facebook'` with
`platformSpecificData.contentType: 'reel'`; there is no Page feed fallback.
Provider-level approval is still blocked on broader per-user platform,
scheduling, failure-recovery, and
Production tests. One controlled Staging YouTube Shorts Private immediate E2E
passed on 2026-08-10 with a real non-mock external reference; this is not launch
approval for other paths. The repository's Production Blueprint nevertheless
selects `SOCIAL_PUBLISHER=postpeer`; treat that mismatch as a configuration risk,
not evidence that the deployed environment is ready. This change does not alter
the Production Blueprint.

## Authentication

### Mock Auth

Default local mode:

```env
AUTH_PROVIDER="mock"
MOCK_USER_ID="local-dev-user"
```

`AUTH_PROVIDER=mock` is rejected at startup when `NODE_ENV=production`.

Development headers:

| Header | Purpose |
| --- | --- |
| `x-postdee-user-id` | Override the mock user id |
| `x-postdee-email` | Optional mock email |
| `x-postdee-display-name` | Optional mock display name |
| `x-postdee-subscription-plan` | Simulate `BASIC`, `STARTER`, or `PRO` in memory mode |
| `x-postdee-phone-verified` | Use `true` to simulate phone verification |
| `x-postdee-phone-number` | Optional mock phone number |

### Firebase Auth

Production direction:

```env
AUTH_PROVIDER="firebase"
FIREBASE_PROJECT_ID="your-firebase-project-id"
```

Authenticated requests must include:

```http
Authorization: Bearer <firebase-id-token>
```

The backend reads `phone_number` from the verified Firebase ID token and treats it as phone verification for the Basic free quota.

Since 2026-10-24 (security Batch 4) the backend stores the token's `email` only
when the token also carries `email_verified: true`. Otherwise the account keeps
the fallback address `firebase-<uid>@postdee.local`, so an unverified sign-up
cannot occupy another person's address in the unique `User.email` column. If a
verified address is still held by a different PostDee row (for example a
deleted Firebase identity whose PostDee data remains), the new account also
gets the fallback address instead of a `500`. Admin search and member trial
confirmation therefore show the fallback address for unverified accounts.

The built-in verifier (used when no Firebase service account is configured)
shares one certificate refresh between concurrent requests, aborts the Google
certificate fetch after 5 seconds, and reuses a failed refresh for 5 seconds.
Per-IP rate limiters sweep expired entries at most once per window and remember
at most 10,000 client addresses each, evicting the oldest first.

## Plans And Entitlements

This table records the intended package contract, not a claim that every listed
benefit is production-ready. The active paywall must advertise only features
whose complete provider/device flow has passed its release gate.

| Feature | Basic | Starter | Pro |
| --- | --- | --- | --- |
| Price | Free | 199 THB/month | 299 THB/month |
| Phone verification | Required for free quota | Not required for quota | Not required for quota |
| Monthly post units | 3 after phone verification | 120 | 250 |
| Real-time posting | Yes | Yes | Yes |
| Cloud scheduling | No | Yes | Yes |
| Calendar for scheduled posts | No | Yes | Yes |
| AI caption from real clip | No | Audio-only, 50 credits/month; shared requests cost 1, advanced requests cost 1 per selected channel; production provider/device verification remains | Audio + selected frames, 120 credits/month; same per-channel rule; production provider/device verification remains |
| Public profile link page | One page, up to 2 links | One page, up to 7 links | One page, up to 20 links |
| AI audio review as a separate feature | No | No | No |
| Unified Analytics | No | No | Yes |
| Hashtag radar and AI comment center | No | No | Yes |
| Team and editor access | No | No | Yes |

Important rules:

- Basic users must verify a phone number before using the 3-post free quota.
- Basic users can only post in real time.
- Post units count by platform. One video posted to four platforms uses four
  units.
- Starter users can post immediately, schedule posts, use the calendar, and use
  real-clip AI captioning from audio after a selected clip.
- All packages can save, publish, update, and unpublish one profile link page.
  The 2026-10-26 candidate sets link limits to Basic 2 / Starter 7 / Pro 20;
  draft additions count all stored links, publication only the enabled payload.
  Existing over-limit published pages remain until the next explicit update;
  existing drafts are retained rather than trimmed.
  AI video editing is retired from the active product; its internal legacy APIs
  do not grant an advertised package benefit.
- Pro users currently unlock implemented analytics and visual-frame AI
  captioning subject to their listed release gates. Hashtag radar, AI comment
  center, and team/editor access remain planned
  package benefits and must not appear as active paywall promises yet.
- Prompt-only caption generation may still exist in the API while the app
  transitions, but it should not be the main paid package promise.
- Secret provider keys must stay on the backend, never inside the Flutter app.

## Standard Error Shape

Most errors follow this format:

```json
{
  "status": "error",
  "code": "PAID_PLAN_REQUIRED",
  "message": "Cloud Scheduling requires the Starter or Pro plan"
}
```

Some validation errors include only `status` and `message`.

## Endpoints

### `GET /health`

Checks whether the API process is running.

Response:

```json
{
  "status": "ok",
  "service": "postdee-api"
}
```

### `GET /ready`

Public operational readiness with `Cache-Control: no-store`. The server probes
the configured database and queue in parallel, with a two-second response
deadline and one underlying in-flight probe per dependency. Prisma uses a
read-only constant query; BullMQ checks Redis metadata, while memory mode
checks the in-process scheduler. A healthy response is `200`:

```json
{
  "status": "ok",
  "service": "postdee-api",
  "checks": { "database": "ok", "queue": "ok" }
}
```

An unavailable dependency or shutdown returns `503`, `status: "unavailable"`
and `"unavailable"` for affected checks. Internal errors/connection details are
not returned. Uncertain interrupted publishes also keep the memory scheduler
unavailable until reconciliation and restart. The existing global request
limit still applies. This route does not check PostPeer, Gemini, storage,
connected accounts or a separate worker's heartbeat. `/health` remains the
unchanged process-liveness endpoint and `/publishing/readiness` remains the
configuration gate below.

### `GET /publishing/readiness`

Authenticated, side-effect-free configuration gate used before a client starts
new social-post media work.

When the API process is accepting new posts:

```json
{
  "status": "ok",
  "acceptingPosts": true,
  "platformSettingsVersion": 1
}
```

This `200` response means only that `SOCIAL_PUBLISHER` is not `disabled` for
this API process. `platformSettingsVersion: 1` advertises support for the exact
per-platform request shapes documented under `POST /posts`; it is not a provider
capability version. It does not call or verify PostPeer, R2/S3, the publish queue,
a separate BullMQ worker, or the authenticated user's platform connections. It
must not be used as provider-level or launch-readiness evidence.

Deployment order is API-first: apply migration
`20260811130000_add_platform_publish_configuration`, deploy the API, verify this
field is `1`, and only then release a Mobile build that sends the new settings.
Current Mobile checks both `acceptingPosts` and an integer version of at least
`1`; a missing, malformed, or older value fails closed before upload.

When `SOCIAL_PUBLISHER=disabled`, the response is:

```json
{
  "status": "error",
  "code": "SOCIAL_PUBLISHING_UNAVAILABLE",
  "message": "Social publishing is temporarily unavailable. Please try again later."
}
```

The status is `503`. Current mobile clients call this route before watermarking
or `POST /uploads`, but `POST /posts`, `PATCH /posts/:id`, and
`POST /posts/:id/publish-now` repeat the same authoritative check to close the
race between preflight and mutation.

Both the accepting `200` response and disabled `503` response include:

```http
Cache-Control: private, no-store
```

This prevents readiness responses from being stored for reuse. It is defensive
and does not identify caching as the cause of any earlier result.

### `GET /auth/me`

Returns the current authenticated user.

Response:

```json
{
  "status": "ok",
  "user": {
    "id": "local-dev-user",
    "provider": "mock",
    "email": "seller@example.com",
    "displayName": "PostDee Seller",
    "phoneVerified": true
  }
}
```

## Uploads

### `POST /uploads`

Creates either a legacy signed-`PUT` upload or a managed multipart session.
Requires authentication. Uploads are scoped to the current authenticated user;
unauthenticated Firebase-mode requests return `401`.

Request:

```json
{
  "fileName": "demo-video.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 12345678,
  "width": 1080,
  "height": 1920,
  "uploadProtocol": "multipart-v1"
}
```

Validation:

- `fileName` is required and at most 255 characters (2026-10-24).
- `contentType` must be exactly `video/mp4`, `video/quicktime`, `image/jpeg`,
  `image/png` or `image/webp` (2026-10-24; previously any `video/` or `image/`
  prefix). The purpose-specific uploads below keep their own exact types.
- A managed multipart session is refused with `409` and
  `code: "UPLOAD_SESSION_LIMIT_REACHED"` when the owner already holds 10
  unexpired `UPLOADING` sessions; the provider upload created for that request
  is aborted. Expired sessions do not count, and the scheduler's expired-session
  sweep (see `DELETE /uploads/:uploadId`) aborts their R2 uploads and retires
  them to `ABORTED`.
- `sizeBytes` must be positive and no larger than `UPLOAD_MAX_SIZE_BYTES` (default `524288000`, or 500 MiB).
- For generic uploads, provided `width` and `height` must describe vertical
  9:16 media within a 2 percent tolerance.
- `purpose: "ai-caption-video"` accepts an `.mp4` file with `video/mp4` at any
  aspect ratio, within the same `UPLOAD_MAX_SIZE_BYTES` limit. Preserve known
  source dimensions, including `1080x2400` (9:20). Omit both dimensions when
  unknown; if either is supplied, both must be positive finite integers.
  Invalid metadata for this purpose returns `400` with code
  `UPLOAD_AI_CAPTION_VIDEO_INVALID`.
- `uploadProtocol`, when present, must be `multipart-v1`.

The AI caption purpose is Live in Staging API `9f0b729`; other environments need
API-first rollout. This purpose requires no migration. Older APIs ignore the
unfamiliar purpose and still reject known non-9:16 dimensions. Generic upload
and mobile posting validation retain the existing 9:16 policy.

Legacy responses retain the supplied dimensions; `aspectRatio` is optional and
does not provide a computed label for every ratio. Use actual dimensions when
present. Managed responses retain their existing shape without a new ratio field.

Mock response:

```json
{
  "status": "ok",
  "upload": {
    "id": "upload-id",
    "fileName": "demo-video.mp4",
    "contentType": "video/mp4",
    "sizeBytes": 12345678,
    "width": 1080,
    "height": 1920,
    "aspectRatio": "9:16",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "storageProvider": "private",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

The legacy R2 or S3 response may also include:

```json
{
  "uploadUrl": "https://signed-upload-url.example",
  "uploadMethod": "PUT",
  "uploadHeaders": {
    "Content-Type": "video/mp4"
  },
  "uploadExpiresAt": "2026-06-05T08:15:00.000Z"
}
```

The legacy R2 signed `PUT` URL signs `Content-Type` and `Content-Length` so the
uploaded object must match the declared metadata. Clients should upload the
same file whose byte length was sent as `sizeBytes`.

When `UPLOAD_PROTOCOL_MODE=dual|multipart` and the client requests
`multipart-v1`, the response instead contains a managed session:

```json
{
  "status": "ok",
  "upload": {
    "id": "opaque-session-id",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "fileName": "demo-video.mp4",
    "contentType": "video/mp4",
    "sizeBytes": 12345678,
    "uploadProtocol": "multipart-v1",
    "partSizeBytes": 16777216,
    "partCount": 1,
    "sessionExpiresAt": "2026-06-05T09:00:00.000Z",
    "storageProvider": "private"
  }
}
```

`UPLOAD_PROTOCOL_MODE` defaults to `legacy`. In `dual` mode (Staging), opted-in
clients receive managed multipart sessions while old clients keep receiving
the legacy response. Since 2026-10-25 the Production Blueprint uses strict
`multipart` (no legacy build was distributed for Production), so account
deletion can abort every client upload; a request without the opt-in returns
`426 UPLOAD_CLIENT_UPGRADE_REQUIRED`.

### `POST /uploads/:uploadId/parts/:partNumber`

Returns a short-lived signed `PUT` URL for one part of an owned, unexpired
managed session. The server calculates the exact byte length; the response
includes `partNumber`, `sizeBytes`, `uploadUrl`, `uploadMethod`,
`uploadHeaders`, and `uploadExpiresAt`. The client must upload that exact byte
range and retain the storage ETag.

### `POST /uploads/:uploadId/complete`

Completes the managed upload. Every part must be present once, using consecutive
part numbers and the lowercase API field `etag`:

```json
{
  "parts": [
    { "partNumber": 1, "etag": "\"part-etag\"" }
  ]
}
```

Successful completion changes the session to `COMPLETED` and returns the upload
metadata. Only then may its `videoS3Key` be used to create a post.

### `GET /uploads/:uploadId`

Returns the authenticated owner's managed upload metadata and `sessionStatus`
(`UPLOADING`, `COMPLETING`, `COMPLETED`, or `ABORTED`). Clients use this to
resolve an ambiguous completion response without starting a second session. If
R2 completed the object but the database acknowledgement failed, the API checks
the object's exact byte size and safely reconciles the session to `COMPLETED`.

### `DELETE /uploads/:uploadId`

Aborts an owned unfinished multipart session. Account deletion also blocks new
sessions, returns `409 ACCOUNT_UPLOADS_DRAINING` while a fresh completion gets
its drain window, and aborts persisted and R2 orphan multipart uploads before
sweeping the owner's stored objects. Completion and abort state changes use
compare-and-set rules so neither terminal result can overwrite the other.

Since 2026-10-24 the in-process scheduler also retires abandoned sessions. Every
10 minutes it takes up to 25 `UPLOADING` sessions (any owner, oldest first)
whose `sessionExpiresAt` passed more than five minutes ago, aborts each R2
multipart upload, and then moves the session to `ABORTED` with a compare-and-set
update. `GET /uploads/:uploadId` then reports `sessionStatus: "ABORTED"`. Part
and complete calls already returned `410 UPLOAD_SESSION_EXPIRED` after expiry, so
no live upload changes behavior. A failed R2 abort leaves the session
`UPLOADING` for the next sweep. Session rows are kept, not deleted, so
`videoS3Key` lookups keep their meaning.

Legacy signed `PUT` remains available during `legacy`/`dual` rollout and still
has a replay window until strict `multipart` mode is enabled for all clients.

## Posts

### Mobile creation presentation (2026-10-07)

The approved 2026-10-12 guided presentation and feedback follow-up are locally
verified and installed. They keep
these four steps and makes AI controls, verified account names, known clip
metadata and the step/channel-count confirmation summary easier to read.
Date/time remains in the shared review and schedule panel.
Opening optional controls and presentation motion do not generate captions,
learn examples, save drafts or submit posts. Optional writing controls remain
reachable and keep their existing explicit triggers, including learning an
edited accepted non-fallback AI caption on Caption Next. There is no new endpoint, request field,
quota, provider mapping or migration. Latest feedback ties required-caption
focus/error, AI wait/full-response presentation and a temporary saved check to
the existing validation/request/explicit-local-save results; it adds no request
or persistence trigger. The final rapid-save guard rejects busy callbacks before
clearing feedback generation. Final feedback includes 10 new tests; save/guard
tests pass 86/86, the full Flutter suite passes 1,915/1,915 and analysis passes.
At that composer release, APK 4012/8012 was installed; native blank-caption inline error/focus/keyboard
is verified without writing data or invoking AI/upload/post/Save.
187/187, 1,914/1,914 and native 8011 validation are pre-guard history. AI/save
results use fixtures, without native AI/upload/post requests or Save.
The preceding connector source passed
1,905 Flutter tests and analysis; Staging APK 4010/8010 was installed with its
existing session and native checks verified selection without invented completion.
Prior 8009 four-step/zero-destination checks are a separate receipt from positive
identity/metadata/schedule/AI and narrow/large-text widget fixtures. No real AI/upload/post request was
performed for native UI QA. Authorized source
`430f82ad1c493b5a8bcf1f51b007e2a7604dae1e` is pushed to
`origin/codex/audit-system-fixes`; exact-source CI `38200231563` passed Backend
and Mobile. No remote APK build was requested; local 8012 was unchanged in that delivery. Render
specific-commit deploy `dep-db65d08473hc73d6fp50` is Live at 10:41:35 GMT+7;
16 existing migrations have none pending and health/readiness return HTTP 200
with database/queue ready. This adds no API/schema/config/dependency change;
social publishing stays disabled and the memory queue is unchanged. Source
identity comes from Render/CI checkout, not health responses. Details:
`docs/superpowers/plans/2026-10-12-create-post-guided-ux.md`.
The existing connection lookup gains owner/request generation guards so late
responses cannot restore another account's identity or finish a newer load.
Identity labels are withheld while loading, on error or on owner mismatch;
neither lifecycle motion handling nor this guard adds a network request.

The full-screen Mobile composer has four UI steps: clip, caption, connected
destinations, and inline review/time/send with one explicit confirmation.
Local poster/full-screen playback, navigation between steps and editing the
summary do not create uploads/posts or use post quota. AI caption generation
still requires an explicit user action and uses the existing caption endpoint
and paid-plan gates. Local draft Save and the changed-form exit prompt remain
separate from posting.

This presentation revision changes no endpoint, request/response field, supported
platform, provider mapping, package price/rule, schema or environment flag, and
requires no database migration. Mobile still validates the actual target
account and complete `platformSettings`, persists the owned submission before
publishing side effects, and retries with the same `clientRequestId`. Existing
readiness, upload, post, scheduling and truthful delivery-result contracts below
remain authoritative.

Mobile publish drafts are local files, not API resources. The app copies the
draft video, optional cover, and manifest to app-owned Application Support
storage under a stable authenticated user ID (the Firebase UID with real
authentication). Saving a draft does not call this API,
R2, PostPeer/social providers, the publish queue, or post-quota accounting. The
backend therefore has no `PostStatus.DRAFT`; `GET /posts` exposes only server-side
post lifecycle records. Local drafts do not sync between devices and may be
included in an operating-system backup according to device settings.

Do not confuse that local draft with a provider draft. TikTok
`INBOX_DRAFT` and Facebook `PAGE_DRAFT` are delivery choices executed only after
the user presses Post. They perform readiness/upload/post/queue/provider work and
consume a post unit, then leave the resulting media as a draft at that provider.

Migration `20260811130000_add_platform_publish_configuration` adds nullable
`Post.platformSettings` and internal `Post.platformTargets` JSONB snapshots,
plus nullable `PlatformPublish.deliveryOutcome` and internal
`PlatformPublish.providerPostId`. Nullable columns keep existing rows readable;
their compatibility rules are described below.

Supported platform values:

```text
TIKTOK
YOUTUBE_SHORTS
INSTAGRAM_REELS
FACEBOOK_REELS
```

`FACEBOOK_REELS` is retained for mobile/API compatibility. From the 2026-10-24
contract update, the server always sets PostPeer `platform: 'facebook'` with
`platformSpecificData.contentType: 'reel'`. It requires a video and never falls
back to a Page feed video. Existing `publishMode: PUBLISH|PAGE_DRAFT` and
explicit optional `isAiGenerated` remain unchanged; `PAGE_DRAFT` still sends
`published: false` and requires provider-confirmed draft delivery. Real-account
E2E must verify Page Reel delivery before production claims.

No new client fields, environment variables, or database migrations are needed.
After deploying the updated publisher, existing queued/scheduled
`FACEBOOK_REELS` jobs also request Page Reels while retaining their accepted
settings and immutable target snapshots. Page Video duration/width limits must
not be treated as Reel limits; the provider validates the actual media.

### `GET /posts`

Returns posts for the authenticated user, with `Cache-Control: private,
no-store`. Plain `GET /posts` retains its existing full payload/order and does
not sign media URLs. Optional query parameters:

| Parameter | Behavior |
| --- | --- |
| `scheduled=true` | Retain the existing scheduled-post filter |
| `includeMedia=true` | Add available signed preview URLs for this owner's objects only |
| `limit=<positive integer>` | Return newest-created posts first, capped at 50; invalid, zero, fractional, duplicate or unsafe-integer values return `400 INVALID_POST_LIMIT` |
| `pageSize=<1-100>` | Since 2026-10-24: return one cursor page, newest created first (`createdAt` desc, then `id` desc), and add `nextCursor` |
| `cursor=<nextCursor>` | Continue after the page that returned this cursor; `pageSize` defaults to 50 when omitted |
| `activeSince=<RFC 3339 time>` | Since 2026-10-25, paging only: keep posts created, scheduled or published at or after this time. Calendar passes the start of the oldest period it shows; pass the same value on every page |

Cursor pages (2026-10-24) let Calendar read history in bounded requests. A
paged response adds `"nextCursor": "<opaque string>"`, or `null` on the last
page. Clients pass the value back unchanged and must not parse it. Each page is
one owner-scoped keyset query of at most `pageSize + 1` rows on the
`(userId, createdAt)` index, so a forged cursor can only move within the
caller's own posts. Posts created after the first page do not shift later
pages. `scheduled=true` combines with paging. A `pageSize` outside 1-100, a
malformed cursor or `activeSince`, `activeSince` without paging, or paging
combined with `limit` or `includeMedia` returns `400 INVALID_POST_PAGE`. The API
does not sign cursors: a hand-built cursor in the right format is accepted, but
it only moves the position within the caller's own posts.

Plain `GET /posts` without `pageSize`/`cursor` is unchanged: it still returns
the complete history with no `nextCursor`, so installed apps keep working. A new
app talking to an older API gets the complete list (the old API ignores the
unknown parameters and returns no `nextCursor`), which the app treats as the
last page. The legacy unbounded list can be capped once every supported app
version pages.

Media opt-in without a limit defaults to 50 posts. Home requests
`includeMedia=true&limit=3`. A valid owned cover produces optional
`coverImageUrl`; otherwise an available owned clip produces optional `videoUrl`.
The API uses the existing storage adapter's signed download access, accepts
safe HTTP(S) URLs, and bounds each signing attempt to 1.5 seconds. A missing,
unsafe or failed URL is omitted while retaining the post. A successful cover
does not also sign the clip. Neither query grants access to another owner's
keys. These previews do not add cursor pagination; use `pageSize`/`cursor`.
Since 2026-10-24 (security Batch 5) limited and media requests ask the store for
only that many newest posts (`take` in Postgres) instead of reading the whole
history first. Plain `GET /posts` still returns the full history for installed
apps; Calendar in new app builds uses the cursor pages above. The Prisma post
store refuses a list without a `userId`.

Response:

```json
{
  "status": "ok",
  "posts": [
    {
      "id": "post-1",
      "platformResults": [
        {
          "postId": "post-1",
          "platform": "TIKTOK",
          "status": "PUBLISHED",
          "externalPostId": "https://www.tiktok.com/@seller/video/123",
          "deliveryOutcome": "PRIVATE",
          "publishedAt": "2026-07-15T04:00:00.000Z",
          "views": 0,
          "likes": 0
        }
      ]
    }
  ]
}
```

`platformResults` is assembled only from results belonging to the authenticated
user's returned post ids. A failed platform result can contain `errorMessage`;
the response does not expose another user's publish records.

Since 2026-10-24 a scheduled post whose owner's plan is `BASIC` when it comes
due (for example a subscription expired, was refunded, or a trial ended) is not
sent. The post becomes `FAILED`, and each selected platform gets a `FAILED`
result with `errorMessage: "PAID_PLAN_REQUIRED"`. The post units charged when it
was accepted are not refunded. Post-now posts and downgrades between paid plans
are unaffected.

The 2026-10-18 Mobile publishing-activity follow-up uses these existing reads
and result fields. Home refreshes recent posts every 30 seconds only while a
loaded post is `PUBLISHING` and its owner, foreground, active-tab and current-route
guards allow it. Calendar retains its existing visible `QUEUED`/`PUBLISHING`
polling. Post detail was a navigation snapshot at that release; the separate
2026-10-21 candidate below adds a single-post GET. No response field, schema, flag, dependency,
entitlement or migration is added. Mobile targeted tests pass 145/145, full
Flutter passes 2,437 with two optional previews skipped, and analysis has no
issues. Release CI builds APK 12026 with the existing Test Store settings; APK
inspection, guarded native update and read-only screen smoke checks pass.
Staging deploy `dep-dba83jqjnfac73enqm40` is Live at `1cf755e`, whose API tree is
identical to release candidate `5c83b3a`; it also delivers main's earlier
backward-compatible YouTube-title route fix. No new migrations are required;
startup reports 20 migrations and none pending, and health/readiness return 200.
New provider publication and native active-sending/FPS are not claimed. See the
[publishing-motion plan](docs/superpowers/plans/2026-10-18-publishing-motion.md).

### `GET /posts/:id` (2026-10-21 usability follow-up)

Requires the existing Bearer authentication. Returns only the exact post owned
by that authenticated user, with `Cache-Control: private, no-store`:

```json
{ "status": "ok", "post": { "id": "post-1", "status": "PUBLISHING", "platformResults": [] } }
```

The actual `post` retains the existing public post fields. Optional
`includeMedia=true` adds safe signed `videoUrl` and `coverImageUrl` independently
when their objects belong to this owner. Signing is best-effort and bounded by
the same preview helper as the list endpoint. Missing, failed or unsafe preview
URLs are omitted; the owned post still returns successfully. No provider refresh,
post creation, queue change or quota consumption occurs.

Missing and foreign IDs both return `404` with
`{ "status": "error", "code": "POST_NOT_FOUND", "message": "Post not found" }`.
Mobile treats only that explicit code as an unavailable record. A generic 404
from an older deployment remains an error, preserving the visible snapshot.
The existing `GET /posts` contract is unchanged. Deploy this API before the
updated Mobile detail/recovery/notification navigation. No migration is needed.

The 2026-10-21 Calendar-cover follow-up reuses this already implemented endpoint
without a contract change. Calendar keeps metadata-only `GET /posts` with no
preview limit and retains existing `coverImageS3Key` and `coverFrameTimeMs`.
Selected-day rows with a stored image or video key may request
`GET /posts/:id?includeMedia=true`. Mobile prefers `coverImageUrl`; only an older
post without an image key may use that owned read's signed `videoUrl` for
bounded, static extraction of the saved frame, defaulting to frame time zero
when the selection is absent. List metadata cannot supply an arbitrary fallback
video URL. Mobile's bounded loopback proxy fetches HTTPS ranges through Dart
with normal TLS verification, then streams them to the existing native extractor
over local HTTP. This is not a new backend route or public video proxy. There is
no video player, though extraction can fetch remote video data. Missing/failed previews leave the
post visible with a placeholder.

New Mobile submissions use the existing optional cover upload/post fields to
retain chosen images on all four supported destinations. Historical non-Meta
upload receipts without an image key keep their original retry identity. This
adds no provider thumbnail capability, endpoint, quota charge, public storage,
migration or backend deployment. The user authorized main integration and
GitHub push on 2026-10-21; this Mobile release requires no manual API deployment.
See the
[work record](docs/superpowers/plans/2026-10-21-calendar-post-covers.md).

### Account mutation boundary for stateful reads

Authenticated writes retain the existing owner mutation/deletion barrier and
active-owner checks. The same guard covers `GET`/`HEAD` `/social-connections`,
`/billing/subscription` and `/uploads/:uploadId`, because these reads can
reconcile durable state. Guard matching normalizes case and trailing slashes
to match Express's existing route behavior; alternate spellings cannot bypass
the deletion boundary. The barrier drains through handler response completion,
including an upload-status read in progress when account deletion starts.
Ordinary reads and unauthenticated requests remain outside this guard path.

Main's individual Prisma-backed routes already ensure User rows after their
own validation/quota gates. That preparation is preserved without a duplicate
generic middleware upsert, new public user endpoint or new preparation error
contract. Managed uploads retain their separate owner transaction.

### `POST /posts`

Creates a queued post and hands it to the publish queue.

Request:

```json
{
  "caption": "Try this product today. #PostDee",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
  "coverFrameTimeMs": 4200,
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "scheduledAt": "2026-06-06T10:00:00.000Z"
}
```

Rules:

- When `SOCIAL_PUBLISHER=disabled`, the route returns `503` with
  `SOCIAL_PUBLISHING_UNAVAILABLE` before managed-upload readiness checks,
  subscription/quota reads, user/post persistence, or queue enqueue.
- `caption` must be a string; `videoS3Key` and at least one valid platform are
  required. A trimmed empty caption is accepted only when the sole destination
  is `YOUTUBE_SHORTS` and `platformSettings.YOUTUBE_SHORTS` contains a valid
  explicit title and all required visibility, audience, synthetic-media and
  certification settings. Other destinations still require a nonempty caption.
  The same exception applies to accepted replay and read-only submission
  recovery; changed immutable intent still conflicts with the original request.
- YouTube title auto-fill is a Mobile behavior, not a new API field: an empty
  local `youtubeTitle` is resolved before review/submission into the existing
  `platformSettings.YOUTUBE_SHORTS.title`. The automatic title uses the first
  sentence of the first nonempty caption line, removes `<`/`>`, and is limited
  to 100 Unicode code points. An explicit custom title is preserved across
  caption edits and must pass the existing title validation. The full caption
  remains the description, with its existing length/character guards unchanged.
  In the 2026-10-23 advanced-caption mode, automatic title derivation and
  description validation use YouTube's effective override when present.
  No database migration or top-level `youtubeTitle` request field is added.
  Local automated verification passes; [results and delivery limits](docs/superpowers/plans/2026-10-18-unified-platform-settings.md#youtube-title-follow-up-2026-10-18-local-implementation)
  include APK12025 build/install and basic Home launch. Entitlement loading,
  exact updated API deployment and real publication remain unverified; the
  blank-caption exception requires the updated API.
- `videoS3Key` must be an upload key owned by the authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape returned by `POST /uploads`.
- `coverImageS3Key` is optional. When present, it must be an owner-scoped
  completed JPEG or PNG managed upload no larger than 2 MiB.
- `coverFrameTimeMs` is optional and must be a non-negative 32-bit integer. It
  records the selected source-video frame in milliseconds.
- A managed multipart upload must have status `COMPLETED` before its
  `videoS3Key` or `coverImageS3Key` can be used. Legacy owner-scoped video keys
  remain accepted only while the server is in `legacy` or `dual` rollout mode.
- If `scheduledAt` is present, it must use the RFC 3339 shape
  `YYYY-MM-DDTHH:mm:ss(.fraction)?(Z|±HH:mm)` with a valid calendar date and
  timezone. The API normalizes it to UTC. It must be strictly after the server's
  current time, cannot be more than 14 days ahead for Starter or 30 days for
  Pro, and the user must have one of those paid plans. The window is a rolling
  number of 24-hour days, inclusive at its upper boundary.
- Basic users must have a verified phone number before using the free quota.
- Basic is limited to 3 post units per month after phone verification.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Repeated platform values are collapsed before quota accounting, persistence,
  and queueing. Post units count unique selected platforms, not post rows.
- The monthly-unit check and post insert are one atomic store operation; Prisma
  uses a serializable transaction and retries write conflicts before rechecking.

Worker behavior:

- The publish worker claims a post by moving it from `QUEUED` to `PUBLISHING`
  before calling the platform publisher.
- PostPeer `202 pending/publishing` is not treated as success. The adapter polls
  `GET /v1/posts/{postId}` for roughly two minutes and records `PUBLISHED` only
  when the selected platform has a real `platformPostUrl` or `platformPostId`.
  It never fabricates an external id. Each PostPeer request times out after 60
  seconds (2026-10-27): a timed-out create is an unknown outcome (never
  resubmitted), and a timed-out status check counts as one unanswered poll.
- The in-process scheduler publishes up to 4 posts of a due batch at once, so
  one slow provider publish does not hold back the rest. Polls still never
  overlap, `drain` waits for in-flight publishes and claims nothing new, and a
  post that reaches a final status has its in-memory queue job removed.
- A provider call is retried only for an explicitly safe error proving that no
  external post was accepted. A network/timeout or uncertain PostPeer outcome is
  not submitted again; clients must check the platform before a manual retry.
- Retry or duplicate jobs are skipped when the post is already `PUBLISHING`,
  `PUBLISHED`, `PARTIAL_PUBLISHED`, or `FAILED`.
- Stale scheduled jobs are skipped when the job `runAt` no longer matches the
  post's current `scheduledAt`, such as after a reschedule.
- Optional R2/S3 cleanup after a fully successful publish is best-effort. A
  cleanup failure is returned in the worker result, but the post stays
  `PUBLISHED`.
- Cover delivery follows platform capability: Instagram receives the signed
  cover image or frame offset. Facebook Page Reels optionally receives the
  signed image as `videoThumbnailUrl` alongside `contentType: 'reel'` on a
  best-effort basis; display on a Reel still needs real-account verification,
  and the provider may choose the cover. TikTok Direct Post receives the selected
  frame time, and YouTube Shorts does not receive a custom thumbnail.
- Create is database-first. The API commits one deterministic, owner-scoped
  `QUEUED` post for a supplied `clientRequestId`, then enqueues it. If enqueue
  fails, the API returns `503 PUBLISH_QUEUE_UNAVAILABLE` but deliberately keeps
  that durable post row. A later request with the same key and matching intent
  finds the row and calls `ensureEnqueued` to repair a missing/unhealthy job.
  It does not create or charge a second post.
- Reschedule and publish-now also update the owned `QUEUED` row first with a
  compare-and-set guard, then replace the queue job. A queue failure attempts a
  conditional rollback only while the persisted schedule still equals the
  transition made by that request; it never overwrites a state that has already
  advanced.
- The mobile readiness preflight normally prevents a new upload while social
  publishing is disabled. An old client or a configuration race can still have
  uploaded media before this route returns `503`; the route does not delete that
  pre-existing object, so the temporary-media cleanup policy must remove it.

Local-only request override:

```json
{
  "subscriptionPlan": "PRO"
}
```

This override is accepted only in local mock development. In `NODE_ENV=production`,
the backend rejects request-body plan overrides with
`SUBSCRIPTION_PLAN_OVERRIDE_DISABLED`.

Production should use the subscription store, not request-body overrides.

Success response:

```json
{
  "status": "ok",
  "post": {
    "id": "post-id",
    "userId": "local-dev-user",
    "caption": "Try this product today. #PostDee",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
    "coverFrameTimeMs": 4200,
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "platformSettings": {
      "TIKTOK": { "publishMode": "INBOX_DRAFT" },
      "YOUTUBE_SHORTS": {
        "title": "Launch walkthrough",
        "visibility": "private",
        "madeForKids": false,
        "containsSyntheticMedia": false,
        "communityGuidelinesCertified": true
      }
    },
    "scheduledAt": "2026-06-06T10:00:00.000Z",
    "status": "QUEUED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  },
  "publishJob": {
    "id": "job-id",
    "queueName": "publish-posts",
    "postId": "post-id",
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "runAt": "2026-06-06T10:00:00.000Z",
    "status": "SCHEDULED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

The first successful request returns HTTP `201`. A retry with the same supplied
`clientRequestId` and matching publishing intent returns HTTP `200`, includes
`"idempotentReplay": true`, and returns the already-persisted post (plus a
repaired/current job when the post is still `QUEUED`). Reusing a committed key
for a different recognized publishing intent, including changed platform
settings, returns HTTP `409` with
`IDEMPOTENCY_KEY_REUSED`. Replaying a post that has already reached terminal
`FAILED` returns HTTP `409` with `IDEMPOTENT_POST_FAILED` and its `postId`; it is not
reported as newly queued. The social-publishing kill switch remains
authoritative and returns `503` without repairing a replay while disabled.

This protects the post row and quota count, not uploaded objects. The local
draft currently persists the request ID but not completed remote video/cover
keys. After a lost response, Mobile can upload replacement objects before the
API returns the existing post; those unused objects require an explicit
temporary-media cleanup/lifecycle policy before production.

Legacy Post rows whose new JSON columns are null normalize to the historical
settings above. Legacy queued rows with no target snapshot still resolve the
current connected account at execution time, so inspect or drain that backlog
before activating Phase 2/PostPeer; they do not gain immutable-target safety
retroactively. Existing platform results with null `deliveryOutcome` remain
readable but cannot prove whether the old delivery was live, private, unlisted,
or a provider draft.

Basic user without phone verification:

```json
{
  "status": "error",
  "code": "PHONE_VERIFICATION_REQUIRED",
  "message": "Phone verification is required to use the Basic free post quota"
}
```

Post limit reached:

```json
{
  "status": "error",
  "code": "POST_LIMIT_REACHED",
  "message": "Basic plan is limited to 3 post units per month"
}
```

### `PATCH /posts/:id`

Reschedules an authenticated user's queued post. Body:
`{ "scheduledAt": "<ISO-8601 date>" }`. Since 2026-10-24 this route and
`POST /posts/:id/publish-now` read only the one owned post, not the owner's
history. The route returns the updated `post`,
returns `404` for a missing/non-queued user-owned post, and returns `503` when
the publish queue cannot be rescheduled. The timestamp uses the same strict RFC
3339 contract as post creation, must be in the future, and must be no more than
14 days ahead for the current Starter plan or 30 days for Pro; Basic cannot
create a new schedule or reschedule a queued post. Existing accepted
schedules retain their original time after a policy change or plan downgrade;
only a new scheduling request applies the current limit. `SCHEDULE_LIMIT_EXCEEDED`
keeps its existing error shape, with a message naming the plan's 14- or 30-day
limit. When social publishing is disabled it
returns `503 SOCIAL_PUBLISHING_UNAVAILABLE` before reading or changing the post
or queue schedule.

### `DELETE /posts/:id`

Deletes an authenticated user's scheduled/queued post and removes its publish
job. Returns `{ "status": "ok" }` or `404` when no user-owned post is found.
This cancellation route remains available while social publishing is disabled,
so queued or scheduled records can be removed safely.

## Devices And Social Connections

### `POST /devices`

Registers the authenticated user's FCM token. Body:
`{ "token": "...", "platform": "IOS|ANDROID|WEB" }`; `platform` is optional.

Since 2026-10-24 (security Batch 5) `token` must be at most 4096 characters of
`A-Z a-z 0-9 : _ . -`, otherwise `400` with `code: "DEVICE_TOKEN_INVALID"`.
Each owner keeps the 10 most recently registered tokens; registering an
eleventh removes the oldest, and the publish notifier reads at most those 10.
Tokens FCM reports as unregistered or invalid after a send are unregistered
for that owner (2026-10-27); transient FCM errors keep the token.

Publish-result pushes include `data: { postId, type: "publish_result", userId }`,
using the same owner as device-token selection. Mobile clears its in-app list
on session transitions and accepts only exact matching recipient UIDs. Old
recipientless messages are ignored. Existing token rotation, authenticated
`DELETE /devices` unregistration and cold-start tap handling are retained.
Recipient filtering alone cannot establish backend cleanup or control OS
background notifications; that lifecycle still needs runtime verification.

### `GET /social-connections`

Lists the authenticated user's saved PostPeer connections.

Mobile treats a failed lookup as unknown status, not an empty connected-account
list or proof of disconnect, and disables connection actions until refresh
succeeds.

### `POST /social-connections/:platform/connect`

Creates/loads the user's PostPeer profile and returns
`{ status: "ok", connectUrl, nonce, expiresAt }` for the requested supported
platform. `nonce` is a cryptographically random 32-byte base64url value (43
characters); `expiresAt` is an ISO timestamp 10 minutes after attempt creation, matching
PostPeer's single-use connect URL lifetime.
Before taking the baseline, the API deletes this platform's leftover PostPeer
integrations in the user's profile, meaning any not saved as the user's
connection, unless an explicit disconnect in this API instance is already
deleting them. PostPeer saves an integration before redirecting and reuses its
id when the same account reconnects, so a leftover would otherwise block that
account from ever being admitted again. If that delete fails, the route
returns `502 SOCIAL_CONNECTION_FAILED` and creates no attempt.
The API stores only its SHA-256 hash, bound to the authenticated user, platform,
claimed profile and the integration IDs listed before issuing the URL. There
is at most one pending attempt per user/platform; a new attempt replaces the
previous one. Failed URL creation cancels only its own attempt. Responses are
`Cache-Control: private, no-store`; do not log or persist the raw nonce or URL.
The provider adapter validates the returned URL
as absolute HTTPS against the requested platform's trusted OAuth domains, and
Mobile repeats that check before opening it. Android uses a dedicated native
Custom Tab bridge that returns failure to Dart instead of substituting a
WebView; iOS and unsupported Android devices use the external system browser.

The optional JSON body accepts `returnTarget: "android"` or
`returnTarget: "android-staging"`. The API maps these to fixed provider
`redirectUri` values:

| `returnTarget` | PostPeer `redirectUri` |
| --- | --- |
| `android` | `postdee://social-connect/return` |
| `android-staging` | `postdee-staging://social-connect/return` |

Omitting the target preserves the legacy request without `redirectUri`.
Unsupported targets return `400 SOCIAL_CONNECTION_RETURN_TARGET_INVALID`
before the provider call. Caller-supplied `redirectUri`, `returnUrl`, `profileId`
and `userId` are ignored; redirect and ownership come from the fixed mapping
and authenticated user. PostPeer documents this optional redirect after successful
connection in its [Connect guide](https://www.postpeer.dev/docs/social-accounts/connect).
The deep link only signals an authenticated refresh; its parameters cannot
prove connection success or replace provider integration state. The fixed-target
API is Live on Staging at `9f0b729`; other environments must deploy API before
mobile. The target affects newly generated links only; previously open links
retain the X/manual-refresh fallback. An injected VIEW URI verified warm return
to the original Connections screen on the installed Staging APK. Real
provider/browser handoff, browser Open App confirmation and cold callback remain
unverified; the injected URI does not verify provider connection or refresh.
The original fixed-return-target feature added no schema or environment setting.
The Batch 2 attempt table and account uniqueness indexes described above are
required for the current nonce contract.

For a new Firebase identity, the API ensures the local `User` row before saving
the foreign-keyed PostPeer profile. Profile creation sends PostPeer a required,
stable HMAC-derived pseudonymous name and does not send the Firebase UID, email,
phone, or display name. Concurrent same-user profile creations are coalesced
inside one API instance. New profiles use a versioned 128-bit HMAC name. A
single legacy 40-bit profile can be repaired only with the temporary,
operator-supplied fingerprint and exact profile id described below; legacy
profiles are never selected by the short name alone. The database exclusively
claims each PostPeer profile id for one user. A conflicting claim returns
`409 SOCIAL_CONNECTION_CONFLICT` without exposing either user's identity or
the provider profile id. If competing requests create different provider
profiles for the same user, the previously claimed database mapping remains
authoritative.

### `POST /social-connections/refresh`

Accepts optional JSON `{ "nonce": "<value returned by connect>" }`. The API
verifies its authenticated owner, profile, platform and expiry, then admits
exactly one integration of that platform whose ID was absent from the attempt's
baseline. Zero candidates leaves the attempt pending; multiple candidates fail
closed. Successful account write and nonce consumption share one transaction.
It returns `{ status: "ok", connections, connectAttemptConsumed }` for requests
with a nonce; `connectAttemptConsumed` is false while pending and true only
after successful atomic completion. Retrying a consumed nonce is rejected.

With `{}` or no nonce, the API only updates metadata/removes already-saved
exact provider/external identities. It never imports new integrations, including
ones found through profile recovery, or silently rotates an account identity.
Provider snapshots are applied conditionally so a slow refresh cannot overwrite
or remove a newer completed link or cancel its pending attempt.

| HTTP / code | Meaning |
| --- | --- |
| 400 `SOCIAL_CONNECTION_ATTEMPT_INVALID` | Nonce is malformed. |
| 409 `SOCIAL_CONNECTION_ATTEMPT_EXPIRED` | Unknown, wrong-owner/profile, expired, replaced or consumed attempt; restart after checking current status. |
| 409 `SOCIAL_CONNECTION_COMPLETION_AMBIGUOUS` | More than one new integration matches; reconnect one account at a time. |
| 409 `SOCIAL_ACCOUNT_ALREADY_LINKED` | `(platform, externalAccountId)` or global `postPeerAccountId` is already claimed by another connection; no owner identifiers are exposed. |

Mobile holds the nonce only in the initiating screen's memory, clears it on
completion/owner switch/disconnect/terminal attempt errors, and retains it for
pending responses or transient network failure until expiry. A lost completion
response can yield an expired/replayed error even though linking succeeded;
use the ordinary status refresh before reconnecting. A process restart loses
the nonce. Pre-existing unbound integrations cannot be adopted by starting
another attempt; an unbound integration with a reused provider ID requires operator/provider
resolution rather than bypassing the baseline check. Thai conflict guidance
asks the user to disconnect from the original PostDee account or choose another
social account. New Mobile rejects a missing/invalid nonce contract before
opening the browser.

The nonce proves possession by the initiating authenticated app request, **not
which human consented in PostPeer OAuth**. Forwarding an attacker's live connect
URL to a different human with an otherwise unbound social account remains a
provider-dependent risk. Signed/echoed completion state, short-lived URL and
browser/profile binding, stable `platformUserId` and reconnect ID behavior need
PostPeer owner validation; no live provider flow was tested in this change.

Mobile calls refresh once when returning to PostDee; the manual refresh remains
available. This is an explicit reconciliation request, not an OAuth completion
callback, and it must not be polled aggressively. PostPeer documents an
optional `redirectUri`; Android requests use the fixed targets above. A warm
native return preserves the original screen. A cold start follows the normal
authentication gate, where the previous in-memory screen may no longer exist.
iOS retains its legacy external-browser/resume and manual-refresh behavior;
automatic iOS return is not claimed.

### `DELETE /social-connections/:platform`

Disconnects the authenticated user's platform using the stored, user-scoped
PostPeer integration id. The provider integration is removed first and the
local record is deleted only after provider success; provider `404` and a
repeated request with no local record are treated as successful idempotent
cleanup. The API captures the connection and pending nonce in one snapshot;
after provider success it removes only that same account identity and cancels
only that captured nonce. A delayed DELETE cannot remove a newer link or a
newer pending attempt. If provider cleanup is unavailable or fails, the route returns
`503 SOCIAL_CONNECTION_UNAVAILABLE` or `502 SOCIAL_CONNECTION_FAILED` and
keeps the local record so a refresh cannot silently recreate a connection the
user believed was removed.

## Account

### `GET /account/deletion-readiness`

Checks that Firebase identity deletion, owner-prefix media cleanup, and any
stored PostPeer profile cleanup are configured before the mobile app starts
Apple reauthentication. Returns
`{ "status": "ok", "identityAlreadyDeleted": false }` or a retryable `503`
without changing account data. For an extant identity the ordinary `200`/`false`
preflight remains available before recent mobile reauthentication. For an
already-missing Firebase identity, `200`/`identityAlreadyDeleted=true` requires
valid stored deletion authorization for the same UID with owner status
`DELETING` or `DELETED`; this lets the mobile app finish an authorized retry
without repeating Apple reauthentication. A missing identity without that
proof returns `403 ACCOUNT_REAUTHENTICATION_REQUIRED`; neither a legacy
tombstone nor `auth/user-not-found` alone grants permission. Missing proof-store
methods or a proof read failure returns
`503 ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE` before cleanup.
If a stored PostPeer profile exists but provider cleanup is not configured,
the endpoint returns `503 ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE`.

### `GET /account-deletion`

Public, unauthenticated HTML page for the Google Play "Account deletion URL"
(Production: `https://postdee-api.onrender.com/account-deletion`). It names
PostDee, shows the in-app steps (Account tab → ลบบัญชี → ลบบัญชีถาวร), offers an
email request to `postdee.support@gmail.com` answered within 30 days, and lists
the data deleted and the data kept (deletion proof, including the operator
record for email requests handled through `POST /admin/api/account-deletions`, unlinked add-on
transaction IDs, the 30-day store-link reservation, store purchase records,
already published social posts, on-device drafts, provider backups/logs).
Thai is primary, with an English summary. The response carries no script,
a per-response style nonce in `Content-Security-Policy` and
`Cache-Control: public, max-age=300`. Keep its labels and data list in sync
with the Mobile flow and the deletion saga below.

### `DELETE /account`

Permanently deletes the authenticated user's account, owned upload objects,
Firebase identity, and user-scoped application data. This backs the App Store /
Google Play required "Delete Account" flow in the profile screen.

Production currently keeps `FIREBASE_AUTH_DELETE_ENABLED=false`; the endpoint
therefore fails closed before cleanup. The behavior below documents the
controlled/test path and shared-drain implementation delivered to Staging at
`7576ee3`, with migration 18 applied. Production launch readiness still requires
its own migration/all-process rollout and real external-service acceptance. See
[the delivery receipt](docs/superpowers/plans/2026-10-14-shared-owner-operation-drain.md#main-and-staging-delivery-2026-10-14).

Behavior:

- Initial Firebase deletion requires an extant identity and a finite ID-token
  `auth_time` no more than five minutes old, allowing at most 60 seconds of
  future clock skew. The API atomically records its server timestamp in
  `ManagedUploadOwner.deletionAuthorizedAt` and marks that UID `DELETING`
  before cleanup. This record is independent of `User`, so cascading user-data
  deletion cannot remove the retry proof. An existing valid proof on a
  `DELETING`/`DELETED` owner allows the same UID's authorized retry even when its
  signed token is older or Firebase confirms its identity is missing.
  Otherwise return `403 ACCOUNT_REAUTHENTICATION_REQUIRED`. Revoked or invalid
  tokens remain rejected. Generic lifecycle begin/finish operations and mock
  deletion must not create Firebase deletion authorization.
- Missing proof-store methods or proof read/write failures return a retryable
  `503 ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE` before a local deleting mark
  or queue, provider, media, database or identity cleanup. Authorization is
  rechecked under the owner lock before proof persistence and cleanup.
  A busy owner-write drain retains `503 ACCOUNT_WRITE_DRAIN_FAILED`. Apply
  migration `20261014003000_authorize_account_deletion` and regenerate Prisma
  before deploying this API. The new timestamp is nullable, with no backfill;
  existing `NULL` tombstones are not permission to retry. A legacy account with
  missing identity and no proof needs separately verified operator recovery,
  not an automatic authorization stamp.
- Marks the owner as deleting before cleanup starts, including legacy upload
  mode. Prisma supplies a durable marker whenever active; otherwise it is
  process-local. User ensure, Post create/quota/reschedule/publish-now and
  Subscription activation/RevenueCat event writes additionally lock an ACTIVE
  owner in the same Serializable transaction as the final mutation. The
  implementation delivered to Staging also admits HTTP handler/finally,
  managed-upload, queue and worker
  lifetimes through `ManagedOwnerOperation`, locking that same owner row before
  recording admission. Remote I/O remains outside SQL transactions.
- After sealing, waits for durable operation tickets to drain, then acquires an
  owner-exclusive `ManagedOwnerDeletionRun` before any cleanup snapshot. Profile
  scope and cleanup capabilities are re-read after drain. A drain timeout or
  another cleanup claim returns `503 ACCOUNT_WRITE_DRAIN_FAILED` before queue,
  provider, media, database or identity cleanup. The durable `DELETING` marker
  and prior authorization may already be committed; user data stays intact.
  Retry succeeds when known work finishes, but crashes, callback exceptions,
  ambiguous outcomes and unconfirmed releases remain blocked until verified
  reconciliation. Tickets/claims have no TTL and no public API exposes them.
- Removes owned queued/scheduled jobs, including jobs whose post row is absent
  after rollback. Failed queue cleanup returns
  `503 ACCOUNT_PUBLISH_CLEANUP_FAILED`. Apply additive migration
  `20261014020000_track_owner_operations`, regenerate Prisma, upgrade every
  API/worker process and drain older binaries before later activation. Local
  two-process synthetic tests do not replace actual Redis/provider acceptance.
- Lists every paginated integration in the user's PostPeer profile and
  disconnects each one through the provider before deleting local records.
  This includes integration ids for platforms PostDee does not yet recognize.
  After every disconnect succeeds, the API deletes the emptied PostPeer profile
  (`DELETE /v1/profiles/{id}`, `404` counts as already deleted) so a connect
  flow still open in a browser cannot attach a new account to it, then drops
  the local profile mapping so a later retry does not query that profile again.
  Provider cleanup failure returns `503 ACCOUNT_SOCIAL_CLEANUP_FAILED` so the
  request can retry without losing local account data; the profile is kept
  while any integration could not be disconnected.
- A fresh multipart completion gets a short drain window and returns
  `409 ACCOUNT_UPLOADS_DRAINING` so the caller can retry. A stale completion is
  reconciled against the R2 object's exact size before persisted and orphan
  multipart sessions are aborted.
  Another upload cleanup failure returns `503 ACCOUNT_MEDIA_CLEANUP_FAILED`.
- Deletes every object under the exact owner prefix
  `uploads/<encoded-firebase-uid>/` before deleting database records. A storage
  cleanup failure returns `503 ACCOUNT_MEDIA_CLEANUP_FAILED`, leaving the
  account records available for retry. Cleanup attempts every listed object;
  because external object deletion is not transactional, some objects may
  already be gone when a retryable error is returned.
- With Prisma stores, deletes the `User` row; `onDelete: Cascade` removes every
  related row in one step.
- With in-memory stores, each store drops the user's records.
- When Firebase auth is used in a controlled environment,
  `FIREBASE_AUTH_DELETE_ENABLED=true` and `FIREBASE_SERVICE_ACCOUNT_JSON` are
  required. Firebase identity is deleted last, after deletion authorization
  and user-scoped cleanup.
- After authorization, `auth/user-not-found` during identity cleanup is treated
  as an idempotent success. Other Firebase
  failures return `503 ACCOUNT_IDENTITY_DELETE_FAILED`; retrying the same
  request completes identity deletion after the already-idempotent data cleanup.
  The account-only verifier can recognize a still-valid signed token whose UID
  Firebase Admin confirms is already missing, but the account routes require
  persisted authorization before readiness or deletion treats it as a retry.
  Revoked tokens remain rejected.
- If Firebase identity deletion is not enabled, the endpoint returns
  `503 ACCOUNT_DELETION_UNAVAILABLE` before changing any data.
- On iOS/macOS, the mobile flow calls the readiness endpoint, reauthenticates
  Apple-linked users, and calls Firebase `revokeTokenWithAuthorizationCode`
  before deletion. Apple Sign-In must remain unavailable on Android/web until a
  server-side Apple token revocation flow is implemented there.
- Late active RevenueCat webhooks are acknowledged and ignored when the
  PostDee user row no longer exists, so a renewal cannot recreate a deleted
  account.

Success response:

```json
{
  "status": "ok"
}
```

## Captions

### `POST /captions/generate`

Generates a Thai affiliate-style caption from 1 or 2 keywords.

Requires Starter or Pro. Each keyword must be 80 characters or fewer. Successful
generations reserve one monthly AI caption generation from the Starter/Pro
quota; quota exhaustion returns `429` with code `AI_CAPTION_QUOTA_REACHED`.

Current note: this endpoint is still the legacy prompt/keyword caption
scaffold. New UI should prefer `POST /captions/generate-from-clip` after a
clip is selected. Optional user text should become extra guidance after clip
selection, not the main sold workflow.

Request:

```json
{
  "keywords": ["skincare", "sensitive skin"]
}
```

Response:

```json
{
  "status": "ok",
  "caption": "Generated caption text",
  "hashtags": ["#PostDee", "#Affiliate"],
  "affiliateLinkPlaceholder": "[Affiliate link placeholder]",
  "model": "gemini-2.5-flash-lite",
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49
  }
}
```

Current providers:

```env
CAPTION_PROVIDER="mock"
CAPTION_PROVIDER="gemini"
CAPTION_PROVIDER="openai"
```

Gemini production direction:

```env
CAPTION_PROVIDER="gemini"
GEMINI_API_KEY="..."
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
```

### `POST /captions/generate-from-clip`

Generates a mock-safe AI caption package from a selected clip key.

Requires Starter or Pro.

- Starter retains `AUDIO_ONLY` mode and includes 50 caption credits/month.
- Pro retains `AUDIO_WITH_FRAMES` mode and includes 120 caption credits/month.
  These historical enum values are unchanged. Both Gemini modes receive the
  whole MP4 when it fits the clip budget below; `AUDIO_ONLY` does not describe
  an isolated audio transport. Only a clip too large to send whole is sent as
  extracted audio. Pro
  additionally supplies up to three selected frames under the existing rules.
- Shared-caption generate/change requests cost one credit. Requests with
  `platforms` cost one credit for each of their 1–4 selected channels.
- Local development can keep quota usage in memory with
  `CAPTION_USAGE_STORE=memory`. Production should use
  `CAPTION_USAGE_STORE=prisma` so monthly usage survives API restarts.
- It uses `videoS3Key`, optional `guidance`, optional `writingStyle`, optional
  `selectedFrameKeys`, optional `deleteAfterUse`, optional `platforms`, and
  `expectedCredits` for confirmation of the displayed cost. Multi-platform
  requests require matching confirmation; shared/one-platform legacy requests
  may omit it.
- Mobile creates the clip upload with `purpose: "ai-caption-video"`; its source
  aspect ratio does not change Starter/Pro access, media ownership, generation
  quota or existing server media-processing limits.
- `videoS3Key` and any `selectedFrameKeys` must be upload keys owned by the
  authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape
  returned by `POST /uploads`.
- When the mobile app uploads media only for AI captioning, it sends
  `"deleteAfterUse": true`; the backend then attempts to delete the clip and
  selected frames after the request. Cleanup failures are logged but do not
  block a successful caption response.
- The full request cost is reserved atomically before the AI provider is called,
  using monthly quota before retained add-on credits. Insufficient combined
  capacity creates no partial usage and makes no provider call; simultaneous
  requests cannot overspend the configured usage store.
- Media downloaded for AI processing is capped to protect API memory.
- This flow transfers the clip and optional Pro frames to configured
  storage/providers and may consume mobile data. The aspect-ratio fix has not
  performed real remote user uploads, provider generation or paid state
  changes, and does not certify production generation.
- When `CAPTION_PROVIDER=gemini`, this endpoint sends the whole MP4 to Gemini;
  Pro's `AUDIO_WITH_FRAMES` also sends the `selectedFrameKeys` images. Gemini
  retries transient failures on configured-primary `gemini-2.5-flash-lite`,
  then falls back directly to the local template caption, so a caption is
  always returned. No secondary Gemini model is attempted.
- When no Gemini caption provider is configured, it falls back to the legacy path:
  the configured `TRANSCRIPTION_PROVIDER` (ElevenLabs or legacy OpenAI) transcribes the clip
  and a local template builds the caption.
- The auto-editing/subtitle flow uses ElevenLabs because it needs accurate
  timestamps; the caption path prefers Gemini.
- Frame sampling itself (extracting `selectedFrameKeys` from the video) is done
  by the mobile app via FFmpeg, which uploads the frames as images before
  calling this endpoint. Pending real-device verification.
- Media limits (2026-10-24): `selectedFrameKeys` are deduplicated before the
  first three are used, and each must end in `.jpg`, `.jpeg`, `.png` or `.webp`;
  otherwise the request returns `400` with `code: "AI_CAPTION_FRAME_INVALID"`
  before any download. Each frame download must have an `image/*` content type
  (`415 AI_CAPTION_FRAME_INVALID`) and at most 5 MiB. Limits are enforced
  while streaming, so a missing or wrong `Content-Length` cannot make the API
  buffer more (`413 AI_MEDIA_TOO_LARGE`).
- Clip budget (2026-10-27): Gemini takes media inline (base64) and rejects
  requests over 20 MB, so a clip over 15,000,000 bytes can never be captioned
  whole. The clip download is capped there. A legacy `videoS3Key` clip above it
  (up to the 200 MiB AI media limit) skips the download and returns the same
  local template caption Gemini's rejection produced before; above 200 MiB it
  stays `413 AI_MEDIA_TOO_LARGE`.
- `audioS3Key` (2026-10-27) is accepted instead of `videoS3Key` (exactly one;
  both or neither is `400`). It must end in `.m4a`, be stored as `audio/mp4`
  (`415 AI_CAPTION_MEDIA_TYPE_INVALID` otherwise) and fit the clip budget
  (`413 AI_MEDIA_TOO_LARGE`). The mobile app still uploads the whole MP4 when it
  fits the budget, so Gemini also sees the video; only a larger clip has its
  audio extracted on device and uploaded with `"purpose": "ai-edit-audio"`, so
  it gets a real AI caption instead of the template. Transcription fallback
  treats it as audio. Deploy order: release this API before the mobile build
  that sends `audioS3Key`; older APIs reject it with `400`. Older mobile builds
  keep working against this API unchanged.
  At most two clip-caption requests per API instance hold media at once; extra
  requests get `503` with `code: "AI_MEDIA_BUSY"` and `Retry-After: 1`, after
  the quota pre-check but before any download or quota reservation.
- Admission follow-up (2026-10-30, local implementation): the same two-slot
  budget covers the legacy transcription fallback as well as Gemini. Once
  admitted, Gemini atomically reserves the existing caption-credit cost before
  downloading media, so a request that loses a quota race returns `429` without
  downloading. Existing media-error refunds and local-template fallback remain
  unchanged; refunds still depend on the usage store being available.
  `AI_MEDIA_BUSY` releases the owner-operation ticket because no provider work
  was admitted; unknown/provider `5xx` outcomes keep their existing blocker.
- The active customer flow should not require manual language or market
  selection. Spoken language is inferred from the clip, while `guidance`
  remains the simple override path when a seller wants a specific language,
  market, or style.

Optional platform-caption generation (2026-10-23; accounting revised 2026-10-25):

- Omit `platforms` to retain the existing request/result behavior. When supplied,
  it must contain 1–4 unique values from `TIKTOK`, `YOUTUBE_SHORTS`,
  `INSTAGRAM_REELS`, `FACEBOOK_REELS`; invalid/empty/duplicate values return
  `400` before media download or quota reservation.
- The response adds `platformCaptions`, a map containing every requested key,
  with `{ "caption": string, "hashtags": string[] }` for each. Existing shared
  `caption`, `hashtags`, context and quota fields remain present. Unrequested
  channels are not returned as generated variants.
- One requested set invokes the provider's generation operation once and
  atomically reserves one credit per channel: 1/2/3/4 channels cost 1/2/3/4.
  Mobile's selection starts empty and the user chooses channels independently
  of publish destinations. It sends matching `expectedCredits` with the
  displayed cost. Missing/mismatched confirmation for multiple channels returns
  `409 AI_CAPTION_COST_CONFIRMATION_REQUIRED` before reservation/provider work.
  Existing transient HTTP retries remain possible inside the single operation.
- Gemini is instructed to adapt wording for each platform from the same clip
  evidence and writing style, without inventing prices, products, claims or
  promotions. YouTube's variant is its description, not its separate title.
- Missing/malformed variants fail the whole generated set into the transparent
  local fallback. It returns editable placeholders for every requested channel,
  `isFallback: true`, `quota.charged: false` and `quota.chargedCredits: 0` when
  the complete reservation is released. Failed refunds retain `charged: true`
  and the full `chargedCredits`; no-provider/legacy-template selected sets are
  also labeled fallback. `quota.requestedCredits` always records the derived
  cost. Successful generation remains charged if the preview is dismissed.
- Paid-plan, owner/media checks, monthly/add-on quota, media limits and requested
  cleanup continue to apply. Opening advanced settings does not call AI.

Example additional request fields (alongside the existing clip fields):

```json
{
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS", "INSTAGRAM_REELS", "FACEBOOK_REELS"],
  "expectedCredits": 4
}
```

Illustrative additional response field, not evidence of a live generation:

```json
{
  "platformCaptions": {
    "TIKTOK": { "caption": "เมนูนี้มีอะไรให้ดูบ้าง?", "hashtags": ["#เมนูร้าน"] },
    "YOUTUBE_SHORTS": { "caption": "พาดูข้อมูลในหน้าเมนูร้านแบบสั้น ๆ", "hashtags": [] },
    "INSTAGRAM_REELS": { "caption": "เก็บบรรยากาศหน้าเมนูร้านมาฝาก", "hashtags": ["#เมนูร้าน"] },
    "FACEBOOK_REELS": { "caption": "วันนี้พาดูหน้าเมนูร้าน มีตรงไหนที่อยากรู้เพิ่มบ้าง?", "hashtags": [] }
  }
}
```

Caption-quality behavior keeps the existing request/response fields. The prompt
asks for an evidence-specific natural opening hook in the primary caption, using
speech, visible actions and legible text without inventing claims or tutorial
steps. For silent clips the prompt requests visible evidence and
`detectedSpokenLanguage: "und"`. Thai is the prompt default unless actual speech
or dominant meaningful text across the clip clearly establishes another
language; brands, account names, dates and numbers do not override it. Captions
use the creator's voice for viewers, not an analysis summary, in one or two
short sentences. Silent menu navigation only previews visible menus/data;
store creation, business setup or promotional benefits must not be inferred.
This evidence boundary applies to options, hooks and metadata too. Visible
buttons, plan or link labels alone do not prove
setup, editing, purchase, scheduling or integrations. Real-clip generation
temperature changes from 0.8 to 0.4 to reduce speculative claims. This is a prompt rule,
not a guarantee of factual accuracy. `hooks` stays separate: the parser does not
prepend it or rewrite the primary caption.

Gemini `hashtags` and `seoKeywords` contain up to five normalized unique valid
items. Missing, empty or invalid metadata remains `[]`, without generic default
tags or keywords. Hashtags use one `#` prefix and Unicode letters, marks, digits
or `_`; normalization uses NFC and case-insensitive deduplication. SEO keywords
also collapse whitespace. The caption uses topical wording naturally; SEO
metadata is separate, and Mobile does not append a literal `SEO:` list to the
publish text. Models, retries, paid rules, ownership and quota stay unchanged.
Limited direct-provider probes improved one final primary caption, while Gemini
still returned `detectedSpokenLanguage: "th"` for a clip with no audio stream.
The `und` request is not guaranteed silent detection; this context metadata does
not drive Mobile caption selection, routing or entitlements. These probes do not
verify deployed Staging routes or quota. General quality and authenticated
caption-screen smoke remain pending; this patch is not pushed/deployed.

#### Caption writing style follow-up (2026-10-09, final verification pending)

`writingStyle` is an optional object. Omitting it preserves legacy request
behavior; omitted fields within a supplied object use these defaults:

| Field | Accepted values | Default |
| --- | --- | --- |
| `tone` | `auto`, `friendly`, `playful`, `direct_review`, `soft_sell` | `auto` |
| `length` | `auto`, `short`, `medium` | `auto` |
| `emoji` | `auto`, `none`, `light` | `auto` |
| `examples` | Up to three strings, trimmed nonempty, each at most 500 UTF-16 code units | `[]` |

For an eligible paid request, null/array/non-object styles, invalid enum values,
non-array examples, invalid elements or exceeded bounds return `400` rather
than silently dropping/truncating the style. Unknown extra fields are ignored.
The existing paid gate, ownership and quota checks remain unchanged.

The real-provider prompt requests 1–2 sentences for auto/short and 3–4 for
medium, without fact padding. Emoji none requests no emoji in `caption`,
`captionOptions` or `hooks`; light allows 0–2 appropriate emoji per text. Presets outrank
examples, which are JSON style data, never instructions or facts about the
current clip. They do not override clip-language rules or supply products,
discounts, URLs or account details. Real-provider `context.selectedTone`
reflects the chosen enum; labeled local fallback remains unchanged. Prompt
compliance is not guaranteed; no training or additional model call is added.

Mobile persists this profile per account on the device and sends its selected
style/eligible examples only with a manually requested generation. Deploy API
support before installing/shipping Mobile; an older API ignores this field.
Automated checks and the local `089dcb52` APK build pass. Staging API source
`7d568458` is Live; the new APK remains uninstalled to preserve the open form.
Native, real paid AI/style-quality and live HTTP verification remain pending;
the audit follow-up records exact-source CI and deployment evidence. No new
route, schema, environment, provider/model configuration or package/quota rule
is introduced.

Request:

```json
{
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "guidance": "focus on the opening hook",
  "writingStyle": {
    "tone": "friendly",
    "length": "short",
    "emoji": "light",
    "examples": ["แวะมาดูของชิ้นนี้ด้วยกันนะ"]
  },
  "selectedFrameKeys": [
    "uploads/local-dev-user/frame-upload-1/demo-1.jpg",
    "uploads/local-dev-user/frame-upload-2/demo-2.jpg"
  ],
  "deleteAfterUse": true,
  "expectedCredits": 1
}
```

Starter response shape (illustrative Gemini output):

```json
{
  "status": "ok",
  "model": "gemini-2.5-flash-lite",
  "caption": "Caption option A",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"],
  "hooks": ["Hook A", "Hook B", "Hook C"],
  "hashtags": ["#หัวข้อในคลิป"],
  "seoKeywords": ["หัวข้อในคลิป"],
  "searchTitle": "หัวข้อจากคลิป",
  "context": {
    "selectedCaptionLanguage": "Thai",
    "selectedTargetMarket": "Thailand",
    "selectedTone": "auto",
    "detectedSpokenLanguage": "th",
    "suggestedCaptionLanguage": "Thai",
    "suggestedTargetMarket": "Thailand"
  },
  "source": {
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "mode": "AUDIO_ONLY",
    "selectedFrameCount": 0
  },
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49,
    "requestedCredits": 1,
    "chargedCredits": 1
  }
}
```

Quota reached (`429`; the response retains actual remaining quota and includes
the required request cost, including when the balance is positive but too small):

```json
{
  "status": "error",
  "code": "AI_CAPTION_QUOTA_REACHED",
  "message": "Not enough AI caption credits for the selected channels",
  "quota": {
    "limit": 120,
    "usedThisMonth": 119,
    "remainingThisMonth": 1,
    "addonRemaining": 2,
    "availableGenerations": 3,
    "requiredCredits": 4
  }
}
```

Cost confirmation required (`409`; no reservation or provider call):

```json
{
  "status": "error",
  "code": "AI_CAPTION_COST_CONFIRMATION_REQUIRED",
  "message": "Confirm the current AI caption cost before generating",
  "quota": {
    "requiredCredits": 4,
    "chargedCredits": 0
  }
}
```

Error messages above are illustrative; clients should use the code and quota
fields. The 429 example reports the three credits actually available rather
than fabricating an exhausted balance for a four-credit request.

Production direction:

The paid caption flow should return SEO fields in the same AI call where
possible:

```json
{
  "seoKeywords": ["keyword 1", "keyword 2", "keyword 3"],
  "searchTitle": "Search-friendly short video title",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"]
}
```

These SEO fields are returned by the new mock-safe real-clip scaffold, but the
AI provider still needs real clip audio/frame inputs before production launch.

## Removed Legacy AI Clip Review Endpoint

`POST /clip-reviews` is no longer mounted in the app.

Reason:

- It overlapped with AI caption from the real clip.
- It exposed confusing package flags such as AI audio review and AI video review.
- The current product plan sells real-clip captioning and Pro ElevenLabs + Gemini
  auto editing instead.

Current behavior:

- Requests to `/clip-reviews` return `404`.
- `canUseAiAudioReview` and `canUseAiVideoReview` are kept as compatibility
  fields in subscription responses, but they are always `false`.
- The old route, UI, config, and internal mock/provider files have been
  removed.

Future SEO direction: Starter real-clip captioning should be based on audio
understanding. Pro real-clip captioning should combine audio and selected visual
frames where useful.

## AI Auto Editing

**Retired (2026-10-24).** AI video editing has no mobile entry point, so the
API no longer serves it by default. Every `/ai-edits/*` request returns `410`
with `{ "status": "error", "code": "AI_EDITING_RETIRED", "message": "AI video
editing is no longer available." }` and never reaches the transcription,
edit-plan, sound-effect or visual-plan providers. Setting
`AI_EDITING_ENABLED=true` restores the legacy contract below for a controlled
rollback only. Historical `AiEditUsage` rows are kept and are still removed by
account deletion. `/captions/generate` and `/captions/generate-from-clip` are
unaffected.

The legacy contract, when re-enabled: all `/ai-edits/*` endpoints require auth. `POST /ai-edits/transcribe`,
`POST /ai-edits/prepare`, and `POST /ai-edits/plan` require the `PRO` plan
(otherwise `402` with `code: "PRO_REQUIRED"`); `GET /ai-edits/quota` is
available to any authenticated user.

### `POST /ai-edits/transcribe`

Transcribes uploaded analysis audio (Thai). Meters usage against a monthly minute quota
(`200` min); returns `402` `AI_EDIT_QUOTA_EXCEEDED` when exhausted. The client
`durationSeconds` is the client-probed media duration used for pre-check and
timeline recovery. Before returning success, the backend reserves minutes from
the longer valid value between media and provider-transcript duration, so an
early provider endpoint cannot reduce usage and concurrent requests cannot push
usage past the configured store limit. The response still reports the raw
provider transcript duration. Current clients send ordered
`audioChunks`; legacy clients may send one `audioS3Key` or `videoS3Key`.
Exactly one of those three media forms is required. Response includes
`transcript` (text, language, durationSeconds, segments[], words[]) and `quota`.
The ElevenLabs adapter requests word-level timing plus non-speech audio-event
tags and sends no free-form spelling prompt. Segment responses retain optional `avgLogprob`,
`noSpeechProbability`, and `compressionRatio` quality signals when the provider
returns them.
Provider timing is audited as one complete timeline before AI editing may use it.
The API can retain a valid display subset for diagnostics, but one malformed,
missing, overlapping, backwards, or out-of-range timed event marks the complete
timeline untrusted. Partial evidence must not authorize subtitles, highlight
planning, repeated-speech cleanup, or silence removal.

If the configured transcription provider is unavailable, both this endpoint and
`POST /ai-edits/prepare` return `502` JSON without reserving quota:

```json
{
  "status": "error",
  "code": "AI_TRANSCRIPTION_PROVIDER_FAILED",
  "message": "AI transcription is temporarily unavailable"
}
```

Provider response details and credentials are never included in the client
response. A temporary uploaded analysis-audio object is still cleaned up by the
route's normal `finally` path.

### `GET /ai-edits/quota`

Reports `{ limitMinutes, usedMinutes, remainingMinutes }` for the current month.

### `POST /ai-edits/prepare`

Builds the UI-facing mobile render recipe for the AI editing screen. This is the
backend contract for the Claude Design flow: the app sends the selected clip,
chosen style/prompt, and capability toggles such as `subtitle`, `silence`,
`filler`, `hook`, `zoom`, `color`, `cta`, `pricetag`, and `watermark`.
Current mobile clients start every optional capability off and explicitly send
`false` for capabilities the user did not enable. A request with every optional
capability disabled remains valid when the user wants only target-length
shortening; recipe consumers must not infer subtitle, silence, repeated-speech,
or colour work from provider data when its matching toggle is false.

This endpoint is Pro-gated and minute-metered like `/ai-edits/transcribe`: the
client `durationSeconds` is the media timeline estimate, the backend transcribes
the stored clip and builds the requested edit plan/recipe. It atomically reserves
minutes from the longer valid media/transcript duration only when at least one
requested analysis outcome is usable. Repeat-only, subtitle-only, or
silence-only requests whose timing evidence is unavailable return a diagnostic
recipe without consuming minutes. A safe silence analysis is successful even
when it finds no candidate. Failed planners and invalid recipes do not consume
quota; the final conditional reservation still prevents concurrent requests
from exceeding the monthly limit. That same longer duration is used by the
planner and `recipe.transcript.durationSeconds`, while word/segment endpoints
retain their provider timestamps. It does **not** render video on the server;
mobile still renders/export with FFmpeg.

Current mobile clients split source audio into balanced chunks no longer than
30 seconds. Every chunk is created through `POST /uploads` with `.m4a`,
`audio/mp4`, `purpose=ai-edit-audio`, no dimensions, and a maximum size of
25 MiB. The client sends ordered `audioChunks` with the source-relative start
time of every chunk. The first start must be zero; keys must be unique,
user-owned, ordered, and limited to 40 chunks. The backend transcribes chunks
sequentially and shifts their local word/segment timestamps onto the source
timeline. If shifting would clip or drop any timing at a chunk boundary, the
merged timeline is marked untrusted instead of treating the clipped subset as
safe editing evidence. The route still cleans every temporary chunk, and any
successful metered prepare reserves usage at most once for the combined request.
`durationSeconds` must describe the source clip for the quota
pre-check, not the requested output length. It is currently supplied by the
official client and combined with the provider timeline; server-side media
probing and an API-side 600-second ceiling remain required before public
tamper-resistant billing. All owned chunks are deleted in the cleanup path even if a later
provider call fails. Legacy clients may send exactly one `audioS3Key` or one
`videoS3Key`; legacy video objects are not auto-deleted. Sending multiple media
forms or no media form is rejected.

`targetDurationSeconds` is an optional positive desired result length. It is
separate from `durationSeconds`, which is the source-duration/quota estimate.
Current mobile clients accept sources up to 10 minutes and use one slider from
5 seconds to at most 3 minutes (or from 1 second when the source is shorter than
5 seconds), capped by the source length. They omit the target at the rightmost
“keep original” position. When a target is present, the edit planner selects
one strongest continuous story window from reliable transcript segments and
returns the complementary ranges to remove. Provider prompt leakage and segments
that cross the configured provider/segment quality thresholds are
excluded from highlight scoring and from rendered subtitle lines. Their timing
still remains available to silence detection so uncertain speech is not mistaken
for a silent gap. Thai-first transcripts containing clearly unexpected scripts
(for example Cyrillic/Hangul/Han replacement noise) are rejected by the same gate,
while ordinary Latin product or place names remain allowed.

Request:

```json
{
  "audioChunks": [
    {
      "audioS3Key": "uploads/local-dev-user/upload-id/postdee-ai-edit-audio-000.m4a",
      "startSeconds": 0
    },
    {
      "audioS3Key": "uploads/local-dev-user/upload-id/postdee-ai-edit-audio-001.m4a",
      "startSeconds": 25
    }
  ],
  "durationSeconds": 65,
  "targetDurationSeconds": 30,
  "styleId": "flash_sale",
  "prompt": "เหลือ 45 วิ เน้นตอนพูดราคา",
  "capabilities": {
    "subtitle": true,
    "silence": true,
    "filler": true,
    "hook": false,
    "beatsync": false,
    "reframe": false,
    "zoom": false,
    "color": true,
    "sfx": false,
    "audio": false,
    "translate": false,
    "pricetag": false,
    "cta": false,
    "watermark": false
  },
  "settings": {
    "silencePreset": "balanced",
    "speechReductionMode": "auto",
    "subtitleWordsPerLine": 3,
    "subtitleColor": "#FFFFFF",
    "subtitleOutlineColor": "#000000",
    "subtitleNormalizedX": 0.5,
    "subtitleNormalizedY": 0.88,
    "ctaText": "กดตะกร้าเลย",
    "priceText": "99 บาท",
    "watermarkText": "Meena Shop",
    "toneFilter": "warm",
    "zoomLevel": "medium",
    "music": {
      "source": "original",
      "beatIntensity": "balanced",
      "volume": 0.25,
      "ducking": {
        "enabled": true,
        "musicVolumeDuringSpeech": 0.12
      }
    }
  }
}
```

If a client loses the prepare response after uploading analysis audio, it may
call `POST /ai-edits/audio/cleanup` with `{ "audioS3Key": "..." }`. Cleanup is
authenticated, owner-scoped, and idempotent. Chunked clients call it once for
each orphaned chunk.

When a client explicitly supplies capabilities but selects neither planning,
subtitles, silence analysis, nor repeated-speech analysis, the endpoint stops
before transcription and returns `400`:

```json
{
  "status": "error",
  "code": "AI_EDIT_NO_ANALYSIS_REQUESTED",
  "message": "เลือกงาน AI ที่ต้องการก่อนเริ่มวิเคราะห์"
}
```

This includes explicit empty and colour-only requests. Color-only edits at
original duration render locally for Pro users and do not consume AI editing
minutes. After checking the local Pro entitlement, the official mobile client
routes only that colour adjustment to `localRenderOnly`. It builds a cut-free,
full-duration recipe and renders the original source without extracting audio,
uploading media, calling `/ai-edits/prepare`, or changing the minute balance.
Colour plus a shortened target, subtitles, silence cleanup, or repeated-speech
cleanup stays on the normal audio/API route. Any unknown enabled capability
fails closed before these side effects. A local retry repeats only rendering,
and accepted source A remains active if a source B render fails. The output name
uses `_subtitled.mp4` only when real subtitle content exists; otherwise it uses
`_edited.mp4`. Temporary owned audio is still cleaned on the API rejection path.
A legacy request that omits the entire `capabilities` field remains metered for
backward compatibility. Output codec, FPS, file size, audio peak, and A/V sync
are phone-renderer acceptance evidence and remain pending device-matrix checks;
the API response does not claim those measurements are complete.

When a style, prompt, or target length needs transcript timing but that timing
cannot be verified, the endpoint stops before planning, recipe creation, or
quota reservation and returns `422`:

```json
{
  "status": "error",
  "code": "AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE",
  "message": "Transcript timing evidence is unavailable"
}
```

`settings.subtitleWordsPerLine` accepts an explicit integer from 1 through 5;
the current setup presets use 1, 3, and 5. Text and outline colours must be
`#RRGGBB`. `subtitleNormalizedX` and `subtitleNormalizedY` are optional but must
be sent together as finite values from 0 through 1. The normalized position is
the canonical subtitle centre and takes precedence over legacy
`subtitlePosition`. Invalid explicit subtitle settings return HTTP `400` with
`code: "INVALID_AI_EDIT_SETTINGS"` before transcription or quota reservation.

Response includes:

- `recipe.renderMode: "mobile-ffmpeg"`
- `recipe.transcript` with text, language, duration, raw `segments`, `words`,
  repaired `boundarySegments`, and model. Current responses always include the
  boundary array; it is built only from the complete strict/reliable transcript
  timeline and stays empty when that evidence cannot be proven.
- `recipe.subtitles` for mobile subtitle burn-in. When subtitles are enabled,
  current responses may also include optional `variants` keyed by `"1"`,
  `"3"`, and `"5"`. All three variants are built from the same validated
  transcript in one prepare request; `segments` remains the selected variant
  for backward compatibility.
- `recipe.cutRanges` with executable planner/repeated-speech cuts,
  `silenceRanges` as internal transcript-gap candidates, and legacy-compatible
  `fillerRanges`. Transcript gaps are silence candidates only. The Android/iOS
  client confirms each candidate against the source waveform before rendering;
  failed or ambiguous verification keeps the original audio. Candidates are
  never folded into `cutRanges` by the API. The client intersects them with
  FFmpeg waveform silence, applies safety padding, rejects source edges and
  protected speech, and sends only verified intersections to its local renderer.
- optional `recipe.speechReduction` with stable repeated-word groups,
  occurrences, recommendations, and `defaultCutRanges`
- `recipe.analysisOutcomes`, with `plan`, `subtitle`, `silence`, and
  `speechReduction` set to `not-requested`, `succeeded`, or `unavailable` from
  the actual result. The API uses this field for its quota decision; clients
  must not infer billing from enabled toggles alone. The legacy fixed-filler
  path counts as succeeded only when it produces a real safe filler range.
- `recipe.plan`, including transcript-selected cuts, a short summary, and the
  planner model identifier
- `recipe.overlays` for future CTA, price tag, and watermark processors; the
  current production mobile renderer does not apply these hints.
- `recipe.renderHints` for tone and future zoom settings. Hook removal is not
  emitted by the current recipe builder yet.
- `recipe.music` with the validated source (`auto`, `library`, `device`, or
  `original`), optional genre/library track reference, beat intensity, volume,
  and voice-ducking preferences
- `recipe.capabilities`, where each requested UI capability is marked
  `applied`, `hinted`, `planned`, or `skipped`
- `quota` with `{ limitMinutes, usedMinutes, remainingMinutes }`

`recipe.transcript.boundarySegments` is independent of
`recipe.subtitles.segments`: it provides source-timeline sentence boundaries
for cut alignment and does not enable or render subtitles. Mobile can therefore
align a shortened result while the subtitle capability is off. Older payloads
without this field are parsed as an empty boundary list, never as raw
`transcript.segments`. When boundaries are missing or rejected, mobile preserves
the planner cut unchanged and shows a warning instead of inventing a new cut.
Valid raw segments, global words, and validated segment words remain separate
conservative protected-speech evidence.

Each `recipe.subtitles.segments[]` keeps the compatibility fields `text`,
`start`, and `end`, and may also contain authoritative `words[]`. Every word is
`{ word, start, end }` on the source timeline. An absent `words` field means a
legacy response; a present empty array means the server deliberately rejected
word timing; a non-empty array is used only after every item and the complete
cue reconstruction pass validation. Reconstruction is exact and case-sensitive
after removing only untimed whitespace, punctuation, and symbols; canonically
different Unicode text fails closed to `words: []`. Clients must not invent
active-word timing when the authoritative array is empty or malformed.
For Thai recipes, provider tokens are expanded at semantic word boundaries and
each multi-token final server cue is limited to at most five semantic words and
20 graphemes. One indivisible brand name, URL, or other token may exceed 20
graphemes rather than being split mid-token; it is emitted as its own cue and is
never merged with neighboring tokens. Minimum-readable-duration and tail merges
may keep a short cue rather than exceed either multi-token limit.

Current mobile builds convert `recipe.subtitles`, transcript metadata, and cut
ranges into a local versioned `SubtitleProject` for Subtitle Studio. Editing,
autosave, live preview, local preview render, reopen, and export reuse this
prepare response; they require no additional API endpoint and consume no extra
AI-edit minutes. Mobile renders and opens result review first; Subtitle Studio
opens only from the explicit review action. Validated cue words drive active-word
preview/export. The response style can carry `outlineColor` and paired
`normalizedX`/`normalizedY`; older responses without them use the legacy
white/black and top/middle/bottom mapping. Edited or unsafe cues use a static
one-line fallback.

Production mobile lets sellers select `subtitle`, `silence`, `filler` (shown as
repeated-speech cleanup), and `sfx`. Every optional switch starts `false`;
target-only shortening remains valid with all optional capabilities off. The
seller-facing `color` and `audio` cards are hidden while their API and
legacy-render compatibility remain intact. `sfx=true` requests a dedicated AI
sound-design analysis in `/ai-edits/prepare`; it is not a manual/local-only
capability.

An executable recipe may contain
`soundEffects: [{"soundId": "coin_ping", "sourceSeconds": 4.0}]`.
`soundId` must be one of the ten bundled PostDee procedural assets and
`sourceSeconds` must exactly match an allowlisted boundary from trusted source
timing. The provider receives only catalog metadata and transcript anchors—no
WAV, asset path, URL, or volume. The complete response is validated atomically,
sorted, and capped at eight; any unknown field, asset, timestamp, duplicate,
malformed JSON, provider failure, or unsafe timing makes the SFX
analysis unavailable with an empty executable list. A valid empty list is a
completed analysis. Mobile assigns the fixed 25% volume and maps source anchors
through the final accepted cuts before local FFmpeg rendering. There is no
seller-facing manual sound picker or placement editor.

Capabilities that need future analysis or rendering, including beat sync, the
opening hook/highlight, auto-reframe, zoom, music choice, audio cleanup,
subtitle translation, price tag, CTA, and the AI-page watermark, are accepted
from older/internal clients but marked `planned` so the UI can stay honest.

`settings.silencePreset` accepts three values and changes the minimum internal
gap between validated word timings that becomes a silence candidate. A complete
reliable segment timeline is used only when safe word evidence is unavailable.
Leading and trailing gaps are excluded. The mobile verifier is the final
authority: successful verification, including an empty result, is cached for
the exact source and timing evidence; failures are not cached. Its retry action
runs only the local waveform probe and local render, without extracting audio,
uploading media, calling this endpoint, or reserving more minutes:

- `natural`: 1.0 second
- `balanced`: 0.6 second (also used when the field is missing or invalid)
- `compact`: 0.4 second

Current mobile has local `AI เลือกให้` and `เลือกเอง` selection modes. Both send
`settings.speechReductionMode: "auto"` and no fixed word list, allowing the same
analysis to be reused without another metered transcription. For a validated
Thai word timeline, the response adds:

- `speechReduction.status`: `ready` or `unavailable`; unavailable timing is
  fail-closed and creates no automatic cuts.
- `groups[]`: the repeated word/phrase and all stable occurrence IDs.
- `occurrences[]`: source start/end, context, repetition kind, recommendation,
  and whether the occurrence is safe to remove.
- `defaultCutRanges[]`: only safe adjacent repeats selected by default.

For Thai repeated-speech detection, character fragments are reconstructed only
when their text matches exact NFC-normalized semantic words in raw provider
order, every fragment stays inside the same reliable segment, and each internal
fragment gap is at most 0.15 seconds. The reconstructed timing is private to
repeat detection and never replaces subtitle word timing. The detector does not
sort damaged evidence, cross an unreliable segment, or bridge a timed audio
event. If any boundary cannot be proven, `speechReduction.status` is
`unavailable`, `unavailableReason` is `fragmented-word-timing` or
`unsafe-word-timing`, and `defaultCutRanges` is empty.

The automatic detector checks repeated one-to-three-word phrases whose two
occurrences are no more than 0.35 seconds apart, removes earlier occurrences,
and preserves the final occurrence. A word found at least three times but
spread through separate sentences is reported as `frequent-only` and kept by
default. Negation, `ๆ`, numbers/prices, sentence boundaries, Thai fragments that
cannot be reconstructed exactly, and incomplete timing are never cut
automatically. AI mode initially
selects `defaultCutRanges`; manual mode initially selects no occurrence. The
mobile review can keep or remove each safe occurrence; unknown or non-removable
IDs are discarded fail-closed. Manual mode also ignores legacy-only
`fillerRanges` so it cannot remove speech before the user chooses.
The mobile build-time repeat rollback keeps these detection groups visible but
read-only, sends no selected occurrence IDs through initial render, review,
subtitle re-render, or export, and applies no legacy or structured repeat cut.
This rollback does not change the API request/response contract.

`settings.fillerWords` is the legacy-client exact allowlist. Supported values are `เอ่อ`,
`อ่า`, `อาฮะ`, `แบบว่า`, `คือว่า`, and `ประมาณว่า`. The backend normalizes NFC and
removes surrounding whitespace, punctuation, and symbols before comparing a
normal transcript word; `เออ` and `อะฮะ` are exact transcription aliases for
`เอ่อ` and `อาฮะ`, but a
longer token such as `เออแล้ว` does not match. When a provider returns a validated Thai
character-token stream, the backend may conservatively reassemble adjacent
fragments that equal an allowlisted filler. Reassembly cannot cross a timing
gap and requires a real gap or verified Thai word/text boundaries; short
prefixes remain stricter. Omitting `speechReductionMode` preserves legacy
behavior and checks the original five words when `fillerWords` is also absent.
Sending `[]`, a non-array value, or
an array that sanitizes to no supported values fails closed and produces no
filler ranges; it does not fall back to the legacy list.
Mobile fits and aligns `recipe.plan.cuts` to the requested story duration first
and only then unions silence and selected repeated-speech cleanup without
shrinking it. The rendered
clip can therefore be slightly shorter than `targetDurationSeconds`, but a
selected cleanup occurrence is never restored merely to fill the requested
duration. When subtitles are enabled, mobile removes the same validated timed
word from subtitle cues before burn-in. If a selected range cannot map to a
complete subtitle word, both the subtitle change and media cut are rejected.
The setup source is pending state, separate from the accepted source/recipe used
by review and export. Mobile commits the active source, duration, recipe,
verified-silence result, subtitle project, capabilities, repeat selection, and
rendered result together only after a successful render. A failed new-source
render therefore cannot pair an old recipe or project with the new file.

Production mobile builds send `hook: false` because
`ENABLE_EXPERIMENTAL_AI_HOOK` defaults to `false`. If an internal or legacy
client sends `hook: true`, the response still marks it `planned`, emits no hook
render hint, and mobile does not reorder the first three seconds. The compile-time
flag exposes setup UI only; it does not enable a renderer.

`settings.music` is additive and optional. Requests that omit it default to
`source: "original"`. A library track is referenced only by an opaque `trackId`.
The current API validates and passes this reference through; a production
catalog resolver with ownership/licensing checks is still required before a
library track can be rendered.
Clients must never send a storage key or absolute device file path to this API.
Receiving music settings does not mean the current renderer has mixed music or
cut on detected beats.

The response is an editable review recipe, not a final server-rendered video.
Mobile may disable recipe capabilities and re-render locally from the original
clip before the user accepts the result. That review loop must reuse the
successful recipe instead of calling this minute-metered endpoint again.
Capabilities marked `planned`, `hinted`, or `skipped` must not be presented as
already applied to the preview.

Mobile derives the review's repeated-speech count from `speechReduction.groups`
and the user's selected occurrence IDs, then merges selected/clamped cleanup
ranges before displaying the detected time.
That summary describes pre-render detections and must not be presented as the
exact duration removed from the exported clip.

After one successful metered prepare, mobile keeps the transcript in memory for
the selected source and settings. Changing only the duration slider calls the
non-metered `/ai-edits/plan` endpoint with that transcript and does not upload
or transcribe the audio again. Changing analysis settings or selecting another
source still requires a new metered prepare.

When the target is shorter than the transcript, current mobile builds create a
whole-duration 360 px MP4 proxy at 1 fps with mono 16 kHz AAC. The upload
must use `purpose=ai-edit-visual-proxy`, `video/mp4`, an `.mp4` name, no client
dimensions, and at most 50 MiB. This is a low-bandwidth representation of the
entire timeline, not a small set of selected still frames. The original source
remains on the device for rendering.

### `POST /ai-edits/plan`

Returns a structured cut plan for an auto-edit style or a free-form prompt,
computed from an already-transcribed clip. Pro-gated but **not** minute-metered.

Local mode uses the rule-based mock (`model: "mock-rule"`). Staging/production
uses `gemini-3.5-flash-lite` for transcript planning and falls back to the
PostDee rules on provider failure. Both transcript and visual GenerateContent
requests require structured JSON and use provider-default sampling without an
explicit `generationConfig.temperature`.

If `visualProxyS3Key` is present, owned by the authenticated user, and a Gemini
key is configured, the API downloads the proxy, uploads it to Gemini Files API,
waits until it is active, and asks Gemini to watch the complete proxy together
with the timestamped transcript. The returned cuts are still clamped to the
requested duration. Any visual download/upload/processing/generation failure
falls back to the configured audio/transcript planner so an otherwise valid edit
does not fail. The R2 proxy and Gemini file are temporary and cleaned
best-effort. Upload, processing-state polling, and deletion use Google's
official `@google/genai` Files client; the edit request still uses the validated
file URI only after Gemini reports the proxy as active.

Request (one of `styleId`, `prompt`, or `targetDurationSeconds` is required):

```json
{
  "styleId": "flash_sale",
  "prompt": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธเธญเธญเธเนเธฅเนเธงเน€เธซเธฅเธทเธญ 15 เธงเธด",
  "durationSeconds": 30,
  "targetDurationSeconds": 15,
  "visualProxyS3Key": "uploads/local-dev-user/upload-id/postdee-visual-proxy.mp4",
  "segments": [{ "text": "เธฃเธฒเธเธฒ 99 เธเธฒเธ—", "start": 3, "end": 6 }]
}
```

- `styleId` โ€” a mobile edit-style id (e.g. `flash_sale`, `qa`, `before_after`,
  `tutorial`, `comedy`); keeps keyword-relevant segments, cuts the rest.
- `prompt` โ€” free-form Thai instruction. The mock understands a target length
  ("เน€เธซเธฅเธทเธญ 45 เธงเธด") and profanity removal ("เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ").

Response:

```json
{
  "status": "ok",
  "plan": {
    "cuts": [{ "start": 10, "end": 12 }, { "start": 17, "end": 30 }],
    "summary": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ ยท เธขเนเธญเน€เธซเธฅเธทเธญ ~15 เธงเธด",
    "model": "mock-rule"
  }
}
```

`visualProxyS3Key` is optional for old clients and audio-only fallback. A key
outside the authenticated user's upload namespace returns `403`; a non-MP4 key
returns `400`. If upload succeeds but the planning request cannot be sent, the
client may call `POST /ai-edits/visual-proxy/cleanup` with
`{ "visualProxyS3Key": "..." }`.

Visual planning converts Gemini suggestions into one continuous target-length
window and uses timestamped transcript boundaries to avoid opening on common
Thai continuation fragments when a nearby complete sentence has comparable
editorial value. This is a soft ranking rule, not a forbidden-word filter.

`cuts` are absolute-second ranges to remove; the client feeds them into the same
on-device render pipeline used by silence/segment cuts. Returns `400` when
`durationSeconds` is missing or none of `styleId`, `prompt`, or
`targetDurationSeconds` is provided.

## Templates

### `GET /templates`

Returns saved text templates for the authenticated user, newest first. Since
2026-10-24 (security Batch 5) the list returns at most 200 templates.

Response:

```json
{
  "status": "ok",
  "templates": []
}
```

### `POST /templates`

Creates a saved text template for the authenticated user.

Limits (2026-10-24): `title` up to 120 characters and `body` up to 5000 after
trimming, otherwise `400` with `code: "TEMPLATE_FIELD_TOO_LONG"`. One owner
can keep up to 200 templates; the next create returns `409` with
`code: "TEMPLATE_LIMIT_REACHED"`. The count check is not transactional, so a
burst of concurrent creates can end slightly above 200.

Request:

```json
{
  "title": "Affiliate disclaimer",
  "body": "This post may contain an affiliate link."
}
```

Response:

```json
{
  "status": "ok",
  "template": {
    "id": "template-id",
    "title": "Affiliate disclaimer",
    "body": "This post may contain an affiliate link.",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

### `DELETE /templates/:id`

Deletes one of the authenticated user's templates (2026-10-27), freeing its
slot. Returns `{ "status": "ok" }`, or `404` when the template does not exist or
belongs to another user. The mobile Templates screen asks for confirmation
before calling it. This endpoint takes no request body.

## Analytics

### `GET /analytics/summary?range=30d`

Returns a unified analytics summary for the authenticated user.

Requires Pro.

Supported `range` values are `today`, `7d`, `30d`, `90d`, and `year`.
The default is `30d`. Platform publish metrics are filtered by their publish
time (falling back to record creation time) and grouped into UTC date buckets.
The `daily` series therefore attributes the current synchronized totals to the
day each platform publish was created/published; it is not a provider-level
hourly history or a synthetic trend.

Response:

```json
{
  "status": "ok",
  "summary": {
    "range": "30d",
    "totalViews": 0,
    "totalLikes": 0,
    "platforms": [
      {
        "platform": "TIKTOK",
        "label": "TikTok",
        "views": 0,
        "likes": 0
      }
    ],
    "daily": [
      {
        "date": "2026-07-10",
        "views": 0,
        "likes": 0
      }
    ]
  }
}
```

If the user is not Pro:

```json
{
  "status": "error",
  "code": "PRO_REQUIRED",
  "message": "Unified Analytics requires the Pro plan"
}
```

An unsupported range returns `400 INVALID_ANALYTICS_RANGE`.

## Billing And Subscriptions

### Non-expiring post/caption credits

The catalog product `postdee_post100_caption50` represents one repeatable
consumable purchase at a target price of 49 THB: 100 post units and 50 real-clip
caption credits. Quantities come from the server catalog, never the client.
Only effective Starter/Pro members can buy/use it; no subscription or tier
feature is changed. Purchased credits never expire. Included monthly quota is
consumed first; only the excess is allocated to purchased credits. One video
sent to two destinations uses two units and may split its allocation between
monthly quota and purchased credits. AI captions likewise cost one credit per
selected generation channel under the 2026-10-25 contract; a shared-caption
request costs one. Basic retains purchased balances but
cannot spend them until Starter/Pro becomes effective again. Refunds revoke
that transaction's grant without removing existing posts or usage records.
Previously spent purchased credits remain charged internally after a refund;
future purchases cover any resulting deficit before more purchased credits
become available. Monthly included quota remains usable during that deficit.

Native Android and iPhone use the same policy. Purchase grants accept Play
Store and App Store, restricted to `REVENUECAT_ADDON_ENVIRONMENT`. RevenueCat
Test Store is accepted only with `SANDBOX`, including ledger writes and trusted
purchase confirmation. Starter/Pro separately enforce
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT`.

Authenticated `GET /billing/addons` returns the catalog and readiness fields:
`enabled`, `eligible`, `productId`, `postUnits`, `aiCaptions`, `priceThb`,
`policyVersion: 2`, `creditsExpire: false`, `expiresAt: null`, `purchasedPacks`,
`addonPostUnits` and `addonAiCaptions`. Pack quantities remain 100/50;
`purchasedPacks` counts valid lifetime grants, while the two `addon*` fields
report unspent purchased balances, clamped to zero for display. There is no
purchase-month binding. Mobile requires policy version 2, explicit non-expiry,
canonical purchase readiness and a matching non-subscription store product
before checkout. `BILLING_ADDONS_ENABLED` defaults to false and controls new
sales only; balances remain available to effective paid members when it is off.

Authenticated `POST /billing/addons/confirm` accepts only the intended
`productId` and `transactionId` as purchase selectors. The server derives the
owner from authentication, verifies the exact transaction using RevenueCat,
and grants idempotently. HTTP 200 with `confirmed: true` confirms fulfillment;
HTTP 202 with `confirmed: false` remains pending. Both responses identify
`policyVersion: 2`, `creditsExpire: false` and `expiresAt: null`. A pending response is not a
new purchase instruction. Webhook retries and confirmation cannot double grant.
Consumable purchase/refund events are handled separately from Starter/Pro
subscription lifecycle events.

The optional request `transactionIdKind` is `STORE` (default for legacy callers)
or `REVENUECAT`. The immediate SDK purchase result uses `STORE`; SDK Customer
Info history uses `REVENUECAT`, and mobile persists that namespace with a
recovered receipt. The server resolves only the selected namespace through
authenticated RevenueCat data. A grant always uses the canonical
store/environment/transaction ledger identity. `STORE` can read an existing
canonical ledger confirmation directly; an internal history selector never
uses that shortcut, even if its text collides with a canonical ID.
When RevenueCat omits the canonical store ID for a history selector, return
`202 pending` without creating a grant or guessing a ledger match. Purchase
timestamps, quantities and balances cannot prove transaction identity; even a
unique metadata match is unsafe while provider histories are eventually
consistent. Exact mapped refunds remain revoked. The response echoes the
requested selector and namespace. Mobile requires both to match the durable
receipt before clearing it; a legacy missing namespace means `STORE`, so a
recovered `REVENUECAT` receipt requires an explicit matching acknowledgement.
The intent can settle when authoritative proof exists, without another checkout. Native history recovery with
missing canonical IDs is an explicit release gate; keep new sales disabled
until the exact store/environment supplies and passes this mapping path.

Subscription snapshots keep `monthlyPostLimit`, `usedPostsThisMonth` and
`remainingPostsThisMonth` scoped to included monthly quota. They also return
`baseMonthlyPostLimit`, remaining purchased `addonPostUnits`/`addonAiCaptions`,
`addonExpiresAt: null`, `addonCreditsExpire: false`, and `availablePostUnits`.
The latter is included monthly remaining plus usable purchased post credits;
Basic receives only its included remaining in that total. Stored purchased
balances are reported even for Basic or when new sales are disabled.
Caption `quota.limit`, `usedThisMonth` and `remainingThisMonth` likewise describe
included monthly usage; `addonRemaining` and `availableGenerations` expose the
separate purchased balance and usable total. Atomic reservations persist the
allocation source so release/rollback restores the correct balance even after
a monthly reset. Plan changes do not retroactively move earlier allocations.

The former monthly add-on was never released. Its older client rejects the new
null expiry before checkout; the new client rejects the old monthly policy
before checkout and retains any pending receipt when confirmation is not
compatible. Deploy both additive database migrations and the version-2 API
before distributing Mobile or enabling purchases. See
`2026-10-21-nonexpiring-post-caption-credits.md` for release limits and historical
allocation/backfill prerequisites.

### `POST /billing/purchase-readiness`

Authenticated preparation before a new RevenueCat SDK purchase. Send `{}`;
body owner selectors cannot choose another principal. Success:
`{ "status": "ok", "purchaseReady": true, "preparationProtocol": 1 }`.
The route ensures the canonical User only for an active owner. Authentication
errors remain 401 and a deleting/deleted owner returns
`409 ACCOUNT_DELETION_IN_PROGRESS`. It does not activate entitlement or call a
payment/subscriber provider.

Current Mobile requires this explicit acknowledgement before a new SDK buy.
404/501 or unsupported/missing readiness shows a Thai compatibility message
and prevents purchase. Existing pending-confirmation/retry and Restore flows
remain separate from a new payment. Install the additive API first, then the
preparation-aware app; read-only GET is a separate later rollout step.

### `GET /billing/subscription`

Shop-link limits (2026-10-26 candidate) add numeric
`subscription.maxProfileLinks`: 2 for Basic/free, 7 for Starter and 20 for Pro,
derived from the same current effective plan as other capabilities. Valid
active trials keep their existing effective rights; expired paid access falls
back to Basic unless another entitlement applies. The field is additive:
older clients can ignore it, and new Mobile can map a missing field from a
successful fresh legacy snapshot using those same plan limits. A failed
subscription read grants no new-add or publish permission. Mobile verifies
again before confirming an addition and publishing; the server's publish check
remains authoritative. Existing local content remains editable offline.
Deploy API before Mobile; no schema migration or new provider is required.

Uploader post-quota display (2026-10-25, follow-up candidate) reuses this
existing authenticated response. Its strip appears on entry to the
clip-selection step, including when no clip is selected. It reads
`subscription.plan`, `monthlyPostLimit`,
`usedPostsThisMonth` and `remainingPostsThisMonth` for the included monthly
balance; `addonPostUnits` is the retained purchased bank and
`availablePostUnits` is the usable combined total. Paid users can spend that
bank; Basic retains it without adding it to usable availability. The strip uses
`requiresPhoneVerification` to explain Basic's existing phone gate;
`canUseFreePostQuota` remains the existing eligibility field. A missing/failed
snapshot, or absent monthly limit/used/remaining
fields, is unavailable with retry, not a zero balance. This adds no endpoint,
response field or accounting rule. Opening the composer or selecting a clip
does not submit a post, reserve quota, start AI or initiate payment. This UI
requires an updated Mobile build; an API deployment does not update installed
Mobile code.
See the [post-quota strip plan](docs/superpowers/plans/2026-10-25-post-quota-strip.md).

The 2026-10-21 usability follow-up adds optional ISO-8601
`subscription.monthlyQuotaResetsAt`, the start of the next UTC calendar month
using the same observation time as monthly usage. For example, an observation
on 2026-10-21 returns `2026-11-01T00:00:00.000Z`. Mobile displays device-local
time and leaves it unknown when an older API omits the field. This does not
change subscription renewal, allowance limits or the nonexpiring purchased bank.

Returns the current user's plan and feature flags.

During the additive security rollout this route retains legacy canonical-user
preparation so existing buying builds continue to work. That User ensure uses
the active-owner final-write fence. This delivery stage does not switch GET to
read-only; retire/disable any incompatible buying builds before a later cutover.

Basic response example:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "BASIC",
    "maxProfileLinks": 2,
    "status": "INACTIVE",
    "monthlyPostLimit": 3,
    "usedPostsThisMonth": 0,
    "remainingPostsThisMonth": 0,
    "phoneVerified": false,
    "requiresPhoneVerification": true,
    "canUseFreePostQuota": false,
    "canSchedule": false,
    "canUseAiCaptions": false,
    "canUseAnalytics": false,
    "canUseAiAudioReview": false,
    "canUseAiVideoReview": false
  }
}
```

After Basic phone verification:

```json
{
  "phoneVerified": true,
  "requiresPhoneVerification": false,
  "canUseFreePostQuota": true,
  "monthlyPostLimit": 3,
  "remainingPostsThisMonth": 3
}
```

Starter response sets:

```json
{
  "plan": "STARTER",
  "maxProfileLinks": 7,
  "status": "ACTIVE",
  "monthlyPostLimit": 120,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 120,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": false,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

Pro response sets:

```json
{
  "plan": "PRO",
  "maxProfileLinks": 20,
  "status": "ACTIVE",
  "monthlyPostLimit": 250,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 250,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": true,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

`canUseAiAudioReview` and `canUseAiVideoReview` are legacy compatibility flags
for older clients, but the active API keeps them false. Package copy should use
"AI caption from real clip" instead.

### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when
`BILLING_PROVIDER=revenuecat`.

This endpoint requires:

```http
Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>
```

The token (and the Google Play notification token) is compared in constant
time over SHA-256 digests (2026-10-27), so response timing reveals neither its
length nor a matching prefix.

RevenueCat `app_user_id` must match the PostDee user id. In production this
should be the Firebase uid used by the mobile app. The backend maps RevenueCat
entitlement ids or product ids to PostDee plans, stores the billing id as
`revenuecat:<app_user_id>`, and keeps `GET /billing/subscription` as the single
app-facing entitlement endpoint.

Example request:

```json
{
  "event": {
    "id": "event-id-from-revenuecat",
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "environment": "PRODUCTION",
    "store": "PLAY_STORE",
    "event_timestamp_ms": 1780444800000,
    "expiration_at_ms": 1780531200000
  }
}
```

Success response:

```json
{
  "status": "ok",
  "ignored": false,
  "eventType": "INITIAL_PURCHASE",
  "subscription": {
    "userId": "firebase-user-id",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

Supported active event types include `INITIAL_PURCHASE`, `RENEWAL`,
`PRODUCT_CHANGE`, `UNCANCELLATION`, and `NON_RENEWING_PURCHASE`. `EXPIRATION`
cancels the existing RevenueCat-bound subscription and removes paid access.
Actionable events must include a non-empty event `id` and positive integer
`event_timestamp_ms`. The subscription update and per-user ordering cursor are
committed atomically. A retried event id or a timestamp that is not newer is
acknowledged with `ignored: true` and cannot overwrite newer entitlement state.
`CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE` are acknowledged
without revoking access immediately because the subscription can still be active
until the paid period actually expires. Unknown product or entitlement ids return
`202` with `ignored: true`.

Actionable subscription events must match
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT` (default `PRODUCTION`) and a supported
store (`APP_STORE` or `PLAY_STORE`; `TEST_STORE` only with `SANDBOX`). Missing
or mismatched environment/store proof returns 202 with `ignored: true`, without
changing the subscription or cursor. This also applies to `EXPIRATION`, so a
sandbox expiration cannot cancel a production plan.

`TRANSFER` uses its own payload shape: `id`, `event_timestamp_ms`, and non-empty
`transferred_from` / `transferred_to` arrays. It does not require `app_user_id`
or `product_id`. Environment/store on this payload are optional; trusted
subscriber readback supplies purchase proof instead. The handler queries each
distinct existing active PostDee user in both arrays before applying changes.
An eligible remaining paid entitlement is retained; otherwise only that user's
matching RevenueCat subscription is canceled. Unknown or deleting users are
skipped, never created. Each write uses the existing owner mutation barrier
and atomic per-user cursor with the subscriber observation timestamp.
There is no cross-user transaction; retry delivery safely reconciles a partial
application. The destination receives access only when its readback proves it.
Lookup/configuration failures and snapshots older than the transfer are
retryable errors and do not fabricate a cancellation. Eligible but unmapped
entitlements remain a configuration error rather than a reason to revoke.

### `POST /billing/revenuecat/resync`

Reconciles RevenueCat rights with PostDee's subscription store when
`BILLING_PROVIDER=revenuecat`. This authenticated endpoint accepts an
empty JSON body and always uses the authenticated PostDee/Firebase uid as
RevenueCat `app_user_id`; any user id
in the request body is ignored. Explicit mobile Restore calls RevenueCat
`restorePurchases` first, then this endpoint; SDK Restore is not a prerequisite
for the server lookup.

The implemented AI preflight uses this unchanged endpoint once per Generate
action only after a successful subscription GET denies AI access and RevenueCat is
enabled. It then performs a fresh GET and ignores the resync response's plan;
the fresh `canUseAiCaptions` value controls the unchanged paid gate and Pro frame
selection. Paid users, disabled RevenueCat and failed initial GETs skip resync.
Resync/fresh-GET failure keeps access closed with a Thai verification error and
manual retry. There is no purchase, SDK Restore, free grant or automatic retry
loop. Owner/generation/source guards and quotas remain. Automated checks pass;
the exact-source Staging APK is built and installed. Native Free/denied gating
and button usability pass; live HTTP sequencing and active-paid
reconciliation/generation remain unverified.

Subsequent Staging delivery (2026-10-09): exact-source CI `37918977276` passed
at `c8e463d`, and Render deploy `dep-db4ccku0tbcc73dtlasg` is Live. The installed
`24266aa` APK has the same runtime; no API contract, schema or environment
change accompanies this delivery. Live HTTP sequencing and active-paid AI
remain unverified; see the chronological audit receipt.

This preflight does not reconcile a later caption `402` after upload or retry
the AI provider.
The existing server subscriber lookup is bounded to 8 seconds; these ordinary
JSON calls keep the client deadline of 20 seconds per request.

Mobile does not report a completed store purchase as failed solely because
PostDee confirmation is unavailable. It shows pending confirmation and retries
receipt verification or subscription reads without a new purchase; backend
confirmation remains required to grant paid benefits. Failure to load the
initial current plan disables new purchases but leaves retry and Restore
available. These client states do not change this endpoint's response contract.
Pending confirmation survives paywall reopening only in a memory cache scoped
to the stable signed-in UID. Sign-out/account changes clear it and reject old
results; app restart requires Restore rather than a locally persisted receipt.

The backend requests the subscriber from RevenueCat API v1 using the server-only
`REVENUECAT_REST_API_V1_KEY`. It first filters purchase provenance from
`subscriptions[productId].is_sandbox` and `.store` against
`REVENUECAT_SUBSCRIPTION_ENVIRONMENT`. Missing/invalid proof is ineligible,
including for lifetime entitlements; production never accepts Test Store.
It maps eligible active Starter/Pro entitlements or products,
prefers Pro if both are eligible, preserves a lifetime entitlement, and respects
entitlement/subscription grace-period expiry. When RevenueCat returns no active
entitlement, only the matching `revenuecat:<uid>` subscription is deactivated;
paid access from another provider is left unchanged. A result containing only
ineligible purchases is treated as no eligible paid access. An eligible active but unmapped
entitlement is treated as configuration drift and never downgrades the user.

RevenueCat promotional grants do **not** grant Starter/Pro access in PostDee.
They are not a substitute for a verified store purchase: an entitlement lacking
boolean `is_sandbox` or a supported `store` is ineligible, even when its ID maps
to Pro/Starter or it has no expiry. If a fresh subscriber snapshot contains only
such promotional entitlements and no eligible purchase, resync applies
`CANCELED` to the existing matching `revenuecat:<uid>` subscription and returns
`plan: BASIC`; this is a cancellation, not an unmapped-entitlement 409. Existing
ordering protection still ignores stale/equal observations. Other-provider
subscriptions and separately granted admin trials are not canceled by this path.
Grant trial access through the PostDee admin console instead, using the existing
trial-access configuration and audited owner-only trial command; do not grant
trials as promotional entitlements in the RevenueCat dashboard. `effectivePlan`
continues to report any valid admin trial separately from purchased access.

The subscriber response's positive integer `request_date_ms` advances the same
per-user ordering cursor used by webhooks, in the same serializable transaction
as the subscription change. A snapshot older than, or equal to, the stored
cursor is ignored and the response reports the effective stored plan instead of
claiming that stale snapshot was applied.
For an empty RevenueCat result, top-level `plan` is `BASIC` so the client does
not report a successful Restore; `effectivePlan` separately reports any access
that remains active from another provider. If an empty snapshot is stale,
top-level `plan` also reports that effective stored plan.

If RevenueCat omits `request_date_ms`, the client records the local API receipt
time as the observation timestamp. This fallback requires synchronized server
clocks: clock skew can temporarily make a legitimate webhook appear older.
Distinct observations with the same millisecond timestamp are deliberately
treated as equal, so the later arrival does not overwrite the committed state.

Request:

```http
POST /billing/revenuecat/resync
Authorization: Bearer <Firebase ID token>
Content-Type: application/json

{}
```

Paid response example:

```json
{
  "status": "ok",
  "plan": "PRO",
  "subscription": {
    "userId": "firebase-user-id",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

The route has a fixed per-IP limit of 10 requests per 10 minutes per API
instance. Errors are:

- `401` when the user is not authenticated.
- `409 REVENUECAT_ENTITLEMENT_NOT_MAPPED` when RevenueCat reports active access
  that does not match the configured Starter/Pro ids; the existing plan is kept.
- `429` when the restore/resync limit is exceeded.
- `501 REVENUECAT_RESYNC_NOT_CONFIGURED` when the server REST key is absent.
- `502 REVENUECAT_RESYNC_FAILED` when RevenueCat cannot be queried or returns an
  invalid response. A provider failure leaves the existing local plan unchanged.

This route is distinct from the webhook: the webhook handles provider lifecycle
events, while resync repairs or confirms state after an explicit user Restore.

### `POST /billing/store/verify`

Legacy direct Apple/Google store verifier. It verifies a mobile store purchase
and activates Starter or Pro when `BILLING_PROVIDER=store` or in local mock
mode. Production should use RevenueCat webhooks instead of this custom verifier.

Default product ids:

```env
STORE_STARTER_MONTHLY_PRODUCT_ID="postdee_starter_monthly"
STORE_PRO_MONTHLY_PRODUCT_ID="postdee_pro_monthly"
```

Android request:

```json
{
  "platform": "ANDROID",
  "productId": "postdee_starter_monthly",
  "purchaseToken": "google-play-purchase-token"
}
```

iOS request:

```json
{
  "platform": "IOS",
  "productId": "postdee_pro_monthly",
  "transactionId": "app-store-transaction-id"
}
```

Response:

```json
{
  "status": "ok",
  "purchase": {
    "provider": "mock-store",
    "platform": "ANDROID",
    "productId": "postdee_starter_monthly",
    "purchaseToken": "google-play-purchase-token",
    "verifiedAt": "2026-06-05T08:00:00.000Z"
  },
  "subscription": {
    "userId": "local-dev-user",
    "plan": "STARTER",
    "status": "ACTIVE"
  }
}
```

The backend stores a provider-neutral billing id:

- Android: `google-play:<purchaseToken>`
- iOS: `apple-app-store:<originalTransactionId>` when available, otherwise `apple-app-store:<transactionId>`

### `POST /billing/mock-success`

Activates Starter or Pro for local scaffold testing.
This endpoint is disabled in `NODE_ENV=production` and when `BILLING_PROVIDER`
is not `mock`.
`BILLING_PROVIDER=mock` is also rejected at startup when `NODE_ENV=production`.

Request:

```json
{
  "plan": "PRO"
}
```

Response:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

This endpoint is for local development only.

## Store Server Notifications

These endpoints support the legacy direct Apple/Google verifier path. The
preferred production billing path is RevenueCat.

### `POST /billing/google-play/notifications`

Receives Google Play Real-time Developer Notifications through a Pub/Sub push payload.

Requires `Authorization: Bearer <GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN>`.

Supported scaffold event types:

- `subscriptionNotification`
- `testNotification`
- `voidedPurchaseNotification`

The scaffold maps clear subscription events to entitlement state only when the purchase token was previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "google-play",
    "eventType": "SUBSCRIPTION_NOTIFICATION",
    "notificationId": "message-id",
    "notificationType": "4",
    "productId": "postdee_pro_monthly",
    "purchaseToken": "purchase-token"
  }
}
```

### `POST /billing/apple/notifications`

Receives App Store Server Notification V2 payloads.

Request:

```json
{
  "signedPayload": "apple-signed-notification-payload"
}
```

The scaffold verifies the signed payload when Apple root certificates and app config are present, extracts transaction ids, and updates subscriptions that were previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "apple-app-store",
    "eventType": "DID_RENEW",
    "notificationId": "notification-uuid",
    "notificationType": "DID_RENEW",
    "subtype": null,
    "transactionId": "transaction-id",
    "originalTransactionId": "original-transaction-id"
  }
}
```

Current notification mapping highlights:

- Apple `DID_RENEW` activates the subscription.
- Apple `EXPIRED` expires the subscription.
- Apple `REFUND` expires the subscription.
- Apple `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD` keeps the subscription active.
- Apple `DID_FAIL_TO_RENEW` without grace period marks the subscription as past due.
- Google Play cancellation, expiration, revocation, and voided purchase events can downgrade or expire known subscriptions.

## Queue

### `GET /queue/jobs`

Returns queued publish jobs for the authenticated user in local memory mode.
Canceling or rescheduling a queued post also removes or replaces the matching
publish queue job.

Response:

```json
{
  "status": "ok",
  "jobs": []
}
```

Production direction:

```env
PUBLISH_QUEUE="bullmq"
POST_STORE="prisma"
DATABASE_URL="postgresql://..."
REDIS_URL="redis://localhost:6379"
```

`PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` because
the API and worker run in separate processes and must share post state through
PostgreSQL.

## Environment Variables

| Variable | Example | Purpose |
| --- | --- | --- |
| `NODE_ENV` | `production` | Runtime environment; production disables local mock shortcuts |
| `PORT` | `4000` | API port |
| `DATABASE_URL` | `postgresql://...` | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis connection string for BullMQ |
| `AUTH_PROVIDER` | `mock`, `firebase` | Auth adapter |
| `FIREBASE_PROJECT_ID` | `postdee-prod` | Firebase project id |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `{...}` | Firebase Admin service account JSON; when Firebase auth is selected, enables revoked-token checks even with deletion off and must match `FIREBASE_PROJECT_ID`. Also used for account deletion; keep secret |
| `FIREBASE_AUTH_DELETE_ENABLED` | `false`, `true` | Enables Firebase identity/account cleanup; requires the service account. Keep disabled until the shared-drain migration/all-process rollout and real Redis/provider/Firebase, legacy upload/OAuth and device cleanup acceptance pass |
| `PUSH_SENDER` | `mock`, `firebase` | Push sender adapter; keep `mock` until the Firebase sender is verified with the installed Admin SDK |
| `VIDEO_STORAGE` | `mock`, `r2`, `s3` | Temporary video storage adapter |
| `CLOUDFLARE_R2_BUCKET` | `postdee-video-temp` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | `...` | Cloudflare account id |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | `...` | R2 S3-compatible access key id |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | `...` | R2 S3-compatible secret access key |
| `CLOUDFLARE_R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` | Optional custom R2 endpoint |
| `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS` | `300` | Signed upload URL lifetime; legacy retries request one fresh URL after explicit expiry, while multipart retries refresh only the affected part URL |
| `UPLOAD_PROTOCOL_MODE` | `legacy`, `dual`, `multipart` | Upload rollout mode; defaults to `legacy`, Staging uses `dual`, and Production uses strict `multipart`, which rejects old clients without the opt-in |
| `MULTIPART_UPLOAD_PART_SIZE_BYTES` | `16777216` | Server-selected managed multipart part size in bytes (16 MiB default) |
| `MULTIPART_UPLOAD_SESSION_EXPIRES_SECONDS` | `3600` | Managed multipart session lifetime in seconds |
| `UPLOAD_MAX_SIZE_BYTES` | `524288000` | Maximum declared upload size accepted by `POST /uploads` |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Per-IP rate limit window in milliseconds |
| `RATE_LIMIT_MAX_REQUESTS` | `300` | Max requests per IP per window; exceeding returns `429` with code `RATE_LIMITED` (`GET /health` is exempt). Tighter fixed per-IP buckets also cover `/auth` (30/10min), `/uploads` (60/hr), `/captions` + `/ai-edits` (60/hr), and `/social-connections` (20/10min) |
| `AWS_REGION` | `ap-southeast-1` | Legacy S3 region |
| `AWS_S3_BUCKET` | `postdee-video-temp` | Legacy S3 bucket |
| `AWS_S3_UPLOAD_EXPIRES_SECONDS` | `900` | Legacy S3 signed upload URL lifetime |
| `CAPTION_PROVIDER` | `mock`, `gemini`, `openai` | Caption provider |
| `GEMINI_API_KEY` | `...` | Gemini API key |
| `GEMINI_CAPTION_MODEL` | `gemini-2.5-flash-lite` | Gemini caption model |
| `GEMINI_EDIT_PLAN_MODEL` | `gemini-3.5-flash-lite` | Gemini visual/transcript edit-planning model |
| `OPENAI_API_KEY` | `...` | Legacy OpenAI API key |
| `OPENAI_CAPTION_MODEL` | `gpt-4o-mini` | Legacy OpenAI caption model |
| `TRANSCRIPTION_PROVIDER` | `mock`, `openai`, `elevenlabs` | AI caption language detection and AI edit transcription provider |
| `ELEVENLABS_API_KEY` | `...` | Server-only ElevenLabs Speech-to-Text API key |
| `ELEVENLABS_TRANSCRIPTION_MODEL` | `scribe_v2` | ElevenLabs batch transcription model |
| `ELEVENLABS_TRANSCRIPTION_KEYTERMS` | empty | Optional comma/newline-separated brand terms; blank avoids the provider keyterm surcharge |
| `WHISPER_MODEL` | `whisper-1` | Legacy OpenAI transcription model |
| `EDIT_PLAN_PROVIDER` | `mock`, `openai`, `gemini` | Brain for `POST /ai-edits/plan`; `mock` is rule-based, the others call an LLM and fall back to mock on failure |
| `OPENAI_EDIT_PLAN_MODEL` | `gpt-4o-mini` | OpenAI chat model for edit planning |
| `BILLING_PROVIDER` | `mock`, `store`, `revenuecat` | Billing verifier adapter |
| `REVENUECAT_WEBHOOK_AUTH_TOKEN` | `...` | Bearer token required by the RevenueCat webhook endpoint |
| `REVENUECAT_REST_API_V1_KEY` | `...` | Server-only secret used to read a subscriber during authenticated restore/resync |
| `REVENUECAT_SUBSCRIPTION_ENVIRONMENT` | `PRODUCTION` | Starter/Pro purchase environment, `PRODUCTION` or isolated `SANDBOX`; Test Store is never accepted in production |
| `REVENUECAT_STARTER_ENTITLEMENT_ID` | `starter` | RevenueCat entitlement mapped to Starter |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | `pro` | RevenueCat entitlement mapped to Pro |
| `REVENUECAT_STARTER_PRODUCT_ID` | `postdee_starter_monthly` | RevenueCat product mapped to Starter |
| `REVENUECAT_PRO_PRODUCT_ID` | `postdee_pro_monthly` | RevenueCat product mapped to Pro |
| `BILLING_ADDONS_ENABLED` | `false` | Enables new post/caption consumable sales after rollout verification; existing purchased balances remain usable by paid members |
| `REVENUECAT_ADDON_PRODUCT_ID` | `postdee_post100_caption50` | Consumable SKU, distinct from all Starter/Pro product identifiers |
| `REVENUECAT_ADDON_ENVIRONMENT` | `PRODUCTION` | Accept only the configured `PRODUCTION` or isolated `SANDBOX` purchase environment |
| `STORE_STARTER_MONTHLY_PRODUCT_ID` | `postdee_starter_monthly` | Starter store product id |
| `STORE_PRO_MONTHLY_PRODUCT_ID` | `postdee_pro_monthly` | Pro store product id |
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.postdee.postdee_mobile` | Android package name |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON` | `{...}` | Google Play verifier service account JSON |
| `GOOGLE_PLAY_ACCESS_TOKEN` | `...` | Optional Google Play access token |
| `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` | `...` | Bearer token required by the Google Play RTDN endpoint |
| `APPLE_APP_BUNDLE_ID` | `com.postdee.postdeeMobile` | iOS bundle id |
| `APPLE_APP_STORE_ISSUER_ID` | `...` | App Store Server API issuer id |
| `APPLE_APP_STORE_KEY_ID` | `...` | App Store Server API key id |
| `APPLE_APP_STORE_PRIVATE_KEY` | `...` | App Store Server API private key |
| `APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64` | `...` | Root certificates for notification verification |
| `APPLE_APP_APPLE_ID` | `1234567890` | Apple app id |
| `APPLE_APP_STORE_ENVIRONMENT` | `sandbox`, `production` | App Store environment |
| `TEMPLATE_STORE` | `memory`, `prisma` | Template persistence |
| `POST_STORE` | `memory`, `prisma` | Post persistence |
| `SUBSCRIPTION_STORE` | `memory`, `prisma` | Subscription persistence |
| `ANALYTICS_STORE` | `memory`, `prisma` | Analytics persistence |
| `CAPTION_USAGE_STORE` | `memory`, `prisma` | Real-clip AI caption monthly usage persistence |
| `AI_EDIT_USAGE_STORE` | `memory`, `prisma` | AI editing monthly minute usage persistence |
| `AI_EDITING_ENABLED` | `false` (default), `true` | Rollback switch for the retired `/ai-edits/*` routes. Leave unset in production and staging; when unset every `/ai-edits/*` request returns `410 AI_EDITING_RETIRED` without provider work |
| `PUBLISH_QUEUE` | `memory`, `bullmq` | Publish queue adapter; `bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` |
| `SOCIAL_PUBLISHER` | `mock`, `disabled`, `postpeer` | Local fake success, explicit fail-closed staging/maintenance mode, or real PostPeer publishing. `disabled` makes readiness, post create, post reschedule, and publish-now return `503 SOCIAL_PUBLISHING_UNAVAILABLE`; cancel remains available |
| `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG` | `false`, `true` | Optional `PUBLISH_QUEUE=memory` activation guard. With `postpeer`, startup runs one atomic global aggregate count with status in `QUEUED` or `PUBLISHING` (including future schedules) before starting the scheduler or listening; a non-zero total or inspection failure blocks startup. Defaults to `false`; Staging sets `true` and Production is unchanged |
| `POSTPEER_API_KEY` | `...` | PostPeer API key for real social publishing |
| `POSTPEER_API_BASE_URL` | `https://api.postpeer.dev` | Optional PostPeer API host override |
| `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` | 64 hex characters | Temporary one-user repair proof: `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`; must be paired with the exact profile id and removed after refresh succeeds |
| `POSTPEER_LEGACY_RECOVERY_PROFILE_ID` | `...` | Exact PostPeer profile id allowed for the temporary legacy repair; must be paired with the fingerprint |
| `POSTPEER_TIKTOK_ACCOUNT_ID` | `abc123` | Operator PostPeer TikTok integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_YOUTUBE_ACCOUNT_ID` | `abc123` | Operator PostPeer YouTube Shorts integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_INSTAGRAM_ACCOUNT_ID` | `abc123` | Operator PostPeer Instagram Reels integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_FACEBOOK_ACCOUNT_ID` | `abc123` | Operator PostPeer Facebook Page integration id for `FACEBOOK_REELS` (Page Reels only via `contentType: 'reel'`) used only when no per-user connection resolver is wired; forbidden in production |
| `MOCK_USER_ID` | `local-dev-user` | Default mock user id |

## Production Gaps

The following work is still required before production launch:

- Verify the per-user PostPeer connect/refresh and full publish-result flow with
  connected test accounts before enabling production user publishing; do not
  use shared `POSTPEER_*_ACCOUNT_ID` values in production. Apply the Phase 2
  migration/API first, verify `platformSettingsVersion: 1`, and inspect or drain
  queued legacy-null rows before releasing Mobile.
- Verify the new TikTok creator-info/privacy/consent/revision flow and the
  provider's TikTok audit approval before production/public Direct enablement.
  The successful read-only creator-info request alone is not audit evidence. Run controlled
  provider E2E for TikTok `INBOX_DRAFT` and Facebook `PAGE_DRAFT`; confirm the
  provider id/final state without exposing internal ids to clients.
- Complete YouTube compliance/provider verification for title, made-for-kids,
  synthetic-media disclosure, certification, and Private/Unlisted/Public. The
  platform may keep non-private uploads Private until its API audit allows the
  requested visibility.
- Prove immutable target snapshots on immediate and scheduled posts: connection
  replacement/disconnect between review, commit, and worker execution must fail
  closed, while public APIs/logs must redact provider account/post ids.
- Store social access tokens securely only if direct platform APIs replace the
  PostPeer provider later.
- Complete provider-level R2 upload and cleanup testing.
- Close the completed-upload orphan path: a lost create-post response can make
  Mobile upload a new video/cover before an idempotent replay returns the old
  post. Persist/reuse completed remote keys or delete superseded objects, and
  verify the lifecycle rule against real R2 before launch.
- Account deletion is not production-safe. The implementation delivered to
  Staging implements
  durable operation tickets and an exclusive cleanup claim, with synthetic
  separate-process verification. For any other target environment, deliver the
  additive migration and every API/
  worker upgrade, quiesce/drain older binaries, and verify actual Redis/BullMQ,
  provider/Firebase cleanup and delayed OAuth/legacy signed-PUT effects before
  activation. Unknown outcomes and crashed claims require verified private
  reconciliation; elapsed time never authorizes destructive cleanup. No
  reconciliation endpoint or automatic ticket repair is implemented.
- Run the local-draft, stable-request replay, explicit destination, truthful
  status, future/14-day Starter and 30-day Pro limits, preservation of accepted
  queues after downgrades, and publish-now matrix on physical Android and iPhone
  release candidates and through controlled Staging provider E2E.
- Replace the in-app Privacy Policy and Terms working drafts with finalized,
  hosted legal text, and make Android/iOS backup plus Data Safety/App Privacy
  disclosures match app-owned draft video/cover storage.
- Test real-clip caption/transcription with real R2 videos, Gemini, and ElevenLabs before
  production launch. Mobile frame extraction/upload (up to 3 frames) is
  implemented and still needs real-device/provider verification.
- Apply and verify the Prisma `RealClipCaptionUsage` migration in production
  before selling paid AI caption quotas.
- Keep legacy AI review compatibility flags false while validating real-clip AI
  captioning and Pro ElevenLabs + Gemini editing.
- Validate Pro AI auto editing with ElevenLabs transcription, Gemini planning,
  minute quotas, top-up handling, mobile FFmpeg export, retries, and failure handling.
- Complete Firebase Google Sign-In and Phone Auth device testing.
- RevenueCat Test Store purchase and true Restore/resync E2E pass on the Android
  Emulator after the current backend was deployed and
  `REVENUECAT_REST_API_V1_KEY` was configured in Render Staging.
- The RevenueCat dashboard now has a Play Store app, Starter/Pro products,
  entitlements, the default offering, and a production Android public SDK key;
  a signed AAB is also ready. Still create the Play Console app/subscriptions,
  configure Google service credentials, open an internal-testing track, and run
  a real Google Play purchase/restore. Those steps are blocked until Play Console
  access is verified with a physical Android device; an Emulator is not accepted.
- Add full RevenueCat renewal, cancel, refund, billing-issue, and notification
  replay coverage.
- Replace mock analytics with real platform analytics fetchers.
- Verify and activate the opt-in Sentry error reporter separately for each
  authorized API/worker environment. Audit logging and production monitoring
  beyond errors remain separate work (per-IP rate limiting is live via
  `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX_REQUESTS`).
