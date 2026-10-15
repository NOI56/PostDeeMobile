# TikTok Inbox delivery result mapping

## Report and verified baseline

- The user reports a TikTok-only post as FAILED in PostDee, created on October
  15 at 12:43 UTC. This is a stored publishing result, separate from the earlier
  local video-preparation timeout.
- At the verified pre-change baseline, freshly fetched `origin/main` was
  `9189e7b`. Work continued on
  `codex/tiktok-native-session-results`, retaining local native-preparation
  commit `656b2bd` and verification receipt `744ebf0`. The API files for this
  correction are unchanged from main before the patch. Preserve unrelated
  generated Windows line-ending changes.
- At diagnosis, Staging API runtime was `0f2941b` and the installed app was
  12021. Subsequent authorized main/Staging delivery is recorded below; the
  installed APK remains 12021.

## Read-only evidence

- Render worker logs at 12:44:09.598 UTC report TIKTOK / PLATFORM_PUBLISH_FAILED
  with a generic Error. Logs deliberately omit provider error text and IDs.
- Using the existing configured PostPeer credential only against its configured
  `https://api.postpeer.dev` origin, a GET-only lookup filters TikTok posts to
  12:42–12:46 UTC and matches the caption prefix visible in the user's app.
  Exactly one record matches, created at 12:43:51.805 UTC and finalized at
  12:44:09.411 UTC. A single-record GET confirms:
  - The request selected TikTok with `platformSpecificData.draft: true`.
  - The provider reports post and selected-platform status `published`.
  - The selected TikTok result has a `v_inbox_url~v2.<digits>` receipt and a
    TikTok messages URL, with no provider error or warning.
- The old mapper accepts a TikTok draft only when the provider literally says
  `draft`. It therefore rejects this completed Inbox result and the worker
  persists the generic FAILED message. A successful provider job here means
  draft handoff; it does not establish public publication on TikTok.
- Primary references:
  [PostPeer GET post listing](https://www.postpeer.dev/docs/api/posts/listPosts),
  [PostPeer GET single post](https://www.postpeer.dev/docs/api/posts/getPost),
  and [TikTok upload-to-Inbox guide](https://developers.tiktok.com/docs/en/content-posting-api-get-started-upload-content).
  TikTok's guide documents both Inbox receipt prefixes and requires the user to
  continue editing/posting from the Inbox notification.
- No provider publish, retry, account connection, billing action, signed-media
  download, or record update is performed. Credentials, raw request bodies,
  caption text, account IDs, and media URLs are not retained in this report.
- The Render read-only database connector cannot reach the Staging database
  because external connections are blocked. The network allowlist is retained.
- A subsequent authorized internal Render Shell query runs in an explicit
  PostgreSQL READ ONLY transaction, scoped to the current account's verified
  email and the 12:42–12:46 UTC window. It finds exactly one PostDee record,
  created at 12:43:49.643 UTC and updated at 12:44:09.607 UTC, with both parent
  and selected TikTok receipt FAILED and no retained provider ID. Comparison
  against the existing PostPeer record confirms matching caption, target
  account, media storage path, selected TikTok-only platform and INBOX_DRAFT
  intent. Only match booleans and safe record metadata are emitted; no network
  policy, data or queue state is changed.

## Minimal correction

1. Add regression tests before changing the mapper, covering the observed
   published Inbox receipt through both immediate create results and polling.
2. Accept that result only for requested TikTok INBOX_DRAFT when the selected
   platform explicitly reports published, has a strict URL/file Inbox receipt,
   and a genuine PostPeer post ID is available. Persist the existing DRAFT
   delivery outcome and provider ID. Do not expose a messages URL as a live-post
   reference.
3. Retain failure and pending checks, explicit draft compatibility, Facebook
   draft handling, owner/target validation, and duplicate-publication guards.
   A messages URL alone, ordinary video ID, malformed or missing receipt, or
   receipt on another platform cannot confirm Inbox delivery. A Direct Post
   request receiving an Inbox receipt cannot be confirmed as PRIVATE or LIVE.
4. Keep existing API shapes, database schema, modes, flags, quotas, native media
   preparation, and dependencies. No migration or mobile rebuild is required.
   Run the affected publisher/worker/route tests and relevant full API checks.

## Historical record and delivery boundary

- The already FAILED PostDee record will not repair itself when this mapper is
  deployed: existing interrupted-job reconciliation scans PUBLISHING records.
  Never requeue or publish again to repair a status mismatch.
- A separate controlled repair must first prove the immutable PostDee owner,
  target, media/settings and exact provider record, then conditionally update
  only the matching stored delivery receipt and parent aggregate. That separate
  repair is now completed and verified below. No automatic historical-repair
  feature or external database access is enabled.
- The historical screen previously remained FAILED despite the Inbox handoff.
  After the guarded repair, Calendar and post detail show `ส่งเป็นร่างแล้ว`
  without error. The user's TikTok Inbox and final public publication still
  require user-side confirmation.
- Code verification and completed main/Staging delivery are recorded below.
  Neither that deployment nor a stored-receipt repair proves public TikTok
  publication.

## Verification receipt

- Regression-first tests add 33 cases. Before the production change, the
  publisher suite reports 10 failures / 58 passes: completed Inbox jobs are
  rejected, Direct Post incorrectly accepts Inbox results as private, and a
  missing PostPeer ID can incorrectly poll using TikTok's receipt. RED log:
  `D:/Temp/tiktok-inbox-publisher-red-20261015.log`.
- The production correction is confined to `postPeerPublisher.ts`: classify
  strict selected TikTok Inbox receipts, keep PostPeer IDs separate from TikTok
  receipts, accept completed requested draft handoff without a live reference,
  and reject that receipt as proof of a non-draft request. No provider call,
  retry or queue mutation path is added.
- Publisher, publish worker and post route regressions pass all 174 cases.
- The first default-concurrency full API run reports 1,945 passes and two
  failures in unchanged timing-sensitive account-coordinator/catalog tests,
  including one associated unhandled rejection. Both affected files pass all
  38 cases when run alone. No assertion, timeout, fixture or production policy
  is weakened to address those unrelated timing failures.
- The complete final API suite passes **119 files / 1,947 tests** with
  `npm test -- --maxWorkers=1`, exit 0, in 93.90s. Log:
  `D:/Temp/tiktok-inbox-api-full-serial-20261015.log`. The initial parallel run
  is retained at `D:/Temp/tiktok-inbox-api-full-20261015.log`.
- `npm run typecheck`, `npm run build`, `npm run prisma:validate`, and the
  standalone Prisma seed/config TypeScript check all pass. Validation uses a
  dummy local URL and does not connect to or migrate a real database.
- The exact compiled `dist` publisher/worker smoke consumes an injected fake
  transport with the observed response structure. It produces DRAFT, retains
  the provider ID, omits a live reference and performs one injected create call
  with no retry. No live provider publish is performed by this smoke.
- Independent read-only code review finds no blocking issue in mode/receipt
  boundaries or duplicate-publication guards. Mobile source, package rules,
  storage, owner guards, native helper, schema, dependencies and flags are
  unchanged; the previously installed 12021 app and its verified native fix
  remain in place. No native-codec or physical-device retest is claimed for
  this backend-only correction; the later app status check is recorded below.
- Local code verification above does not perform a provider publish or repair.
  The subsequent authorized historical repair is recorded below; no TikTok
  Inbox user action or public social publication is claimed.

## Authorized main and Staging delivery receipt

- The user authorizes main integration, push, Staging deployment and a separate
  single-record historical repair. Integration/deployment is confirmed in this
  section; the completed repair has its own live receipt below.
- Main is fast-forwarded and pushed from `9189e7b` to
  `7a55fe8a0b4152ee4ad4d9a5238c918656b67a61`, retaining native source `656b2bd`,
  its verification docs `744ebf0`, and the Inbox mapper correction `7a55fe8`.
  At source delivery, local main, origin/main and the implementation head agree.
  A later documentation-only receipt commit can advance main without changing
  the verified Staging runtime `7a55fe8`; no second deployment is needed.
- Exact-head [CI run `38741265826`](https://github.com/NOI56/PostDeeMobile/actions/runs/38741265826)
  passes both jobs. The Backend test suite passes 119 files / 1,947 tests in
  24.66s; typecheck, build, Prisma validation and the production-dependency audit
  gate also pass.
  Mobile passes 2,252 tests and analysis with no issues (13.5s). The push
  workflow skips APK building/uploading; it does not rebuild or replace the
  separately verified installed APK12021.
- Render Staging deploy `dep-db8d6gss728c7391ajp0` is Live at
  `2026-10-15T13:23:04.671572Z`, running exact source `7a55fe8a...b67a61`.
  All 18 existing migrations are applied, none pending; the empty-backlog
  activation guard passes. No new migration is introduced.
- Public `/health` and `/ready` return HTTP200 in both checks at approximately
  13:23:51 and 13:25:33 UTC. A bounded 13:23:04–13:25:13 UTC log query finds no
  errors or 5xx entries; its request coverage is incomplete, so it is not proof
  that every request succeeded.
- No environment/provider configuration, flags, Production delivery, new APK,
  queue replay or provider publish/retry is included. The separately completed
  historical repair is recorded below.

## Historical repair guards and completed live receipt

- Read-only comparison identifies one eligible TikTok-only parent/receipt pair.
  The authorized effect is to mark that existing receipt with DRAFT semantics,
  retain the already existing PostPeer ID, clear the generic error/live
  reference, and set its handoff timestamp from the verified provider result.
  Recompute only its parent's aggregate delivery status.
- The original operator artifact `DBCEF713...` stops its live READ ONLY dry-run
  at `OWNER_NOT_IDLE_ACTIVE`, with no writes: five durable operation markers
  remain. Their age is not treated as completion, expiry or reconciliation.
- The separate v2 operator artifact has SHA-256
  `F565CD416346A8C0155343C45EC9080C180C9F0C53DDEAA52FCA2540CD22F7E8`.
  Nine local guard tests and independent code review pass. It permits only the
  exact five-row operation snapshot, whose sorted ID/start-time SHA-256 is
  `230bb6a22ce95721866413c9262ca27b6af045ad2b0e5d33ccba95195d334784`.
  This is not a general drain bypass, and no operation marker is resolved.
- Apply uses Serializable isolation and locks the ACTIVE owner, its exact
  operation rows (`FOR SHARE`), the post and single receipt in that order.
  Immutable owner/target/settings/media/provider evidence and failed-row versions
  must match; conditional updates must affect exactly one parent and one receipt.
  Full before/after snapshots preserve the operations and other immutable data.
  Dry-run/check use explicit READ ONLY transactions without locking selects.
- The v2 live READ ONLY preview succeeds with `wouldWriteRows: 2` and
  `writtenRows: 0`. The single authorized apply executes around 13:36 UTC on
  October 15, returning `ok: true`, `writtenRows: 2`, `quotaPreserved: true`,
  `immutableProofVerified: true`, `operationSnapshotVerified: true`,
  `durableBlockersPreserved: true` and `independentReadbackVerified: true`.
- A subsequent independent `--check` succeeds with `alreadyRepaired: true`,
  `wouldWriteRows: 0`, `writtenRows: 0`. The existing parent is PUBLISHED and
  selected TikTok receipt is PUBLISHED with `deliveryOutcome: DRAFT`; the genuine
  provider ID is retained, live reference/error are null, and the original
  provider handoff timestamp stays `2026-10-15T12:44:09.409Z`.
- All five exact operation rows remain unchanged with the snapshot hash above.
  The owner remains ACTIVE, without deletion authorization or a deletion run.
  Caption/media/settings, request ID, quota/subscription, every other post and
  platform, and queue state are preserved. No provider POST/retry, requeue,
  replacement post, marker cleanup, external database opening or unrelated
  manual row change is performed.
- On installed APK12021, Calendar and the reopened post detail both show
  `ส่งเป็นร่างแล้ว` without the error at approximately 13:37 UTC. Proofs are
  `user12021-inbox-repaired.png` and `user12021-inbox-repaired-calendar.png`
  under `D:/PostDeeMobile/.tmp/tiktok-fps-native-probe-20261015/session-results/`.
  These checks verify the repaired PostDee history. The user must still open
  TikTok's Inbox notification and finish editing/posting; user-side Inbox
  confirmation and final public publication remain unverified.
- No automatic historical-reconciliation feature is added to the application.
  Customer email, PostDee/provider post IDs, captions and media URLs are omitted
  from this committed receipt.
