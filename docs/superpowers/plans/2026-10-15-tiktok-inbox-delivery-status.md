# TikTok Inbox delivery result mapping

## Report and verified baseline

- The user reports a TikTok-only post as FAILED in PostDee, created on October
  15 at 12:43 UTC. This is a stored publishing result, separate from the earlier
  local video-preparation timeout.
- Freshly fetched `origin/main` remains `9189e7b`. Work continues on
  `codex/tiktok-native-session-results`, retaining local native-preparation
  commit `656b2bd` and verification receipt `744ebf0`. The API files for this
  correction are unchanged from main before the patch. Preserve unrelated
  generated Windows line-ending changes.
- Staging API runtime is `0f2941b`; the installed app is 12021. Neither has been
  deployed or replaced again during this diagnosis.

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
- A separate controlled repair would first prove the immutable PostDee owner,
  target, media/settings and exact provider record, then conditionally update
  only the matching stored delivery receipt and parent aggregate. That repair
  has not been performed or enabled here. No external database access is opened.
- Until that separate repair, the historical app screen can remain FAILED even
  though the provider reports an Inbox handoff. The user's TikTok Inbox and
  final public publication still require user-side confirmation.
- Code verification and delivery status will be recorded below. No merge,
  push, Staging deployment or live social publication is claimed yet.

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
  remain in place. No mobile or physical-device retest is claimed for this
  backend-only correction.
- No merge, push, deployment, migration, historical-record update, TikTok Inbox
  user action or public social publication is performed. The existing FAILED
  app history therefore still requires the separate guarded receipt repair.

## Historical repair preview (not executed)

- Read-only comparison identifies one eligible TikTok-only parent/receipt pair.
  Proposed effect: mark that existing receipt completed with DRAFT semantics,
  retain the already existing PostPeer ID, clear the generic error/live
  reference, and set its handoff timestamp from the verified provider result.
  Recompute only its parent's aggregate delivery status.
- Before any write, revalidate the active owner, exact row/version, caption,
  media key, immutable target/settings, failed receipt and provider result in
  the same guarded owner-operation/transaction boundary. Abort on any mismatch
  or affected-row count other than one parent and one selected receipt.
- Preserve caption/media/settings, original request ID, quota/subscription,
  every other post/platform and all queue state. Never call provider POST/retry,
  create another post, open the external database allowlist or describe the
  Inbox handoff as public publication to repair the historical status.
- This preview is not authorization to change the user's data; no repair
  command or automatic historical-reconciliation feature is enabled here.
