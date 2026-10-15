# TikTok Inbox CREATE confirmation through canonical GET

## Verified baseline and preserved delivery

- Main, origin/main and the implementation worktree start at
  `2efac1a8ab9ddaf9f6f51d110b8174bed8b49dd6`, the documentation receipt after
  runtime `7a55fe8`. Work continues on `codex/tiktok-native-session-results`.
  Preserve unrelated generated Windows changes and the existing publisher tests.
- Staging's active worker build and actual compiled source are confirmed as
  `7a55fe8`. Its injected canonical GET-style Inbox result already produces
  DRAFT. This is not an old runtime or missing prior patch.
- The 12:43 incident's one-time repair, readback and Calendar/detail verification
  remain complete in `2026-10-15-tiktok-inbox-delivery-status.md`. This follow-up
  concerns a separate, later user-created post. Do not merge their repair receipts.
- Installed APK12021, native helper and media validation, owner/target boundaries,
  phone-gate UX, modes, quota, schema, dependencies, flags and Production remain
  outside this correction. No new mobile build or migration is proposed.

## Observed evidence for the later incident

- All timestamps below are UTC on October 15, 2026. The later local post is
  created at `13:48:05.979` and records FAILED at `13:48:30.199`.
- A scoped read-only provider lookup identifies the matching post created at
  `13:48:10.391`, updated at `13:48:29.431`, with original selected TikTok handoff
  timestamp `13:48:29.430`.
- Canonical GET confirms matching owner/account, caption, media and immutable
  INBOX_DRAFT intent. The raw requested platform data has `draft: true`; the
  provider parent and selected TikTok statuses are published, with a strict
  `v_inbox_url~v2.<digits>` receipt and null error/warning fields. Only match
  booleans and safe timestamps are recorded here, without customer identifiers,
  caption text, media URLs or credentials.
- That final provider evidence proves an Inbox handoff, not public TikTok
  publication. At this diagnostic stage the later PostDee row was FAILED;
  the separately authorized correction and verification are recorded below.

## Reproduced contract gap and inference boundary

- The current official [CREATE post documentation](https://www.postpeer.dev/docs/api/posts/createPost)
  shows platform summaries with platform, success, platform URL, error and warning
  fields, without a selected-platform status or Inbox publish ID. Canonical
  [GET post](https://www.postpeer.dev/docs/api/posts/getPost) supplies the final
  record used for strict Inbox evidence.
- Injecting the documented CREATE summary into the actual `7a55fe8` adapter
  reproduces generic rejection before any GET, while an injected canonical
  published Inbox record produces DRAFT. The mapper requires explicit selected
  published status plus a strict Inbox receipt and therefore rejects the summary
  before reaching its existing GET confirmation path.
- The historical real CREATE response was not captured or retained. The above
  establishes a reproducible contract gap and a plausible explanation of the
  incident; it does not prove the exact bytes or shape returned by that CREATE.
  Do not describe the injected payload as a captured live response.
- Current CREATE docs also document optional `idempotencyKey`. This adapter does
  not currently send a stable provider idempotency key. This fix does not add that
  feature: a create request may already have succeeded, so confirmation must use
  read-only GET rather than another POST.

## Implemented minimal correction and regression gates

1. Add tests first for requested TikTok INBOX_DRAFT with a published CREATE parent,
   explicit successful selected TikTok summary, missing selected status/ID and a
   genuine CREATE `postId`/`id` that is not a TikTok publish receipt. Request
   canonical GET using that ID; do not classify
   CREATE summary/parent/messages URL alone as successful DRAFT delivery.
2. Keep existing strict canonical GET proof: selected TikTok published status,
   valid URL/file Inbox receipt, genuine provider ID, no live-post reference and
   unchanged DRAFT semantics. A declared GET provider ID that differs from the
   CREATE ID cannot confirm the request; bounded polling remains on the original
   ID and becomes unknown if no matching proof arrives. Never poll using a TikTok
   receipt or another platform's ID as a fallback. The pre-existing rejection of
   an Inbox receipt without selected status remains intact.
3. Preserve explicit failure and pending precedence, explicit draft compatibility,
   non-TikTok behavior, immutable account targets and Direct Post boundaries.
   Parent-only success, messages URL alone, another platform's success or missing
   genuine provider ID must not activate the new confirmation shortcut.
4. Bound GET checks with the existing polling limits. Pending, incomplete or
   unconfirmed GET responses and transport/JSON failures must not manufacture
   DRAFT or resend POST. Confirm one injected create call even when GET retries.
5. Run affected publisher/worker/route regressions, full API tests, typecheck/build
   and Prisma checks. Review the exact compiled publisher with injected CREATE
   summary plus canonical GET proof. Keep live provider publication out of tests.

## Files changed

- `apps/api/src/workers/postPeerPublisher.ts`: bounded CREATE-summary confirmation
  and canonical provider-ID binding.
- `apps/api/src/workers/postPeerPublisher.test.ts`: 34 regression cases, including
  worker no-resend and unknown-outcome checks.
- `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`, and this plan: behavior,
  verification, Staging delivery and the separate repair receipt.

## Verification, delivery and historical state

- Thirty-four regression-first cases extend the publisher suite. Before the
  source correction, 21 cases fail at the documented-summary confirmation gap.
  After the minimal patch, all **102 publisher tests pass**. They cover wrapped
  CREATE payloads, the `id` alias, missing messages URLs, pending-to-complete GET,
  incomplete/mismatched/failed GET, bounded transport/JSON errors, strict receipt
  rejection and failure/mode guards. Worker integration cases verify one CREATE
  call for both confirmed DRAFT and unknown outcomes, with reconciliation retained
  for the latter.
- Frozen source SHA-256:
  `89A126DF8FE3BB923A3E0702C2995012DA442AEC5F550BA7B2A72AD7A3898C7E`.
  Frozen test SHA-256:
  `39843A70ED61281E7D2C7929C86CEF021E3DC9C53820AE7DEE501C30C878A392`.
  Independent source/matrix review finds no blocking issue in the confirmation,
  provider-ID binding, strict Inbox proof or no-resend boundaries.
- The complete API suite passes **119 files / 1,981 tests** with
  `npm test -- --maxWorkers=1`, exit 0, in 95.73s. Log:
  `D:/Temp/tiktok-inbox-create-api-full-20261015.log`.
- Typecheck, build, Prisma schema validation and the standalone Prisma seed/config
  TypeScript check all pass, exit 0. No migration or live database mutation is
  performed by these checks.
- Exact compiled `dist` smoke passes two injected scenarios: documented CREATE
  summary followed by canonical GET confirms DRAFT without a live reference
  (`POST, GET`); still-incomplete GET remains bounded and unknown
  (`POST, GET, GET`), with both GETs using the original provider ID. No actual
  remote POST is performed by either smoke.
- Source is committed, fast-forwarded into main and pushed as
  `e191ed7574aea58a11e48d452240d09420202ff7`. Installed APK12021 and Mobile source
  remain unchanged; no new native runtime verification is claimed for this
  backend fix. Exact delivery and the separate historical repair follow below.
- No provider POST/retry/requeue, billing action, phone verification, account
  reconnection, environment change or Production delivery is included.
- User-side TikTok Inbox confirmation and final public publication remain
  unverified and require the user's own action.

## Exact main, CI and Staging delivery

- Exact-head [CI `38747979249`](https://github.com/NOI56/PostDeeMobile/actions/runs/38747979249)
  succeeds. Backend passes 119 files / 1,981 tests plus 22 generator tests,
  typecheck, build, Prisma validation and the production-dependency audit gate
  at 14:04:11 UTC. Mobile passes 2,252 tests and analysis with no issues (14.0s)
  at 14:08:55 UTC. Push CI skips APK building/uploading.
- Staging deploy `dep-db8dr449v7es738gr9vg` is triggered once at
  `14:05:04.733433Z` and Live at `2026-10-15T14:07:09.942921Z` on exact source
  `e191ed7`. Startup confirms all 18 migrations with none pending and the
  enforced empty-backlog activation guard passes. No environment/configuration,
  flags, Production or new APK change is included.
- Public `/health` and `/ready` return HTTP200/status ok in two rounds at
  14:08:09 and 14:09:30 UTC. The bounded post-Live 14:07:09.942921–14:09:10 UTC
  queries return no error/5xx entries. Request logs in that window are empty,
  so coverage is incomplete and does not prove every request succeeded.
- Actual runtime comparison matches LF-normalized source SHA-256
  `61a73b30d66f0f791f42c653e05315a396862d9afdf48278374538f2b9d5f483`
  and compiled publisher SHA-256
  `627721bd34738d63fb726f7cb02179173594dba920b197e6a8c2b7da3c3a3b55`.
  Both injected runtime scenarios pass: CREATE-summary to canonical GET DRAFT,
  and incomplete GET to bounded UNKNOWN. Neither performs an actual remote POST.

## Separate later-record repair and app verification

- A new operator artifact is pinned to exact runtime `e191ed7`, with SHA-256
  `98EA1C8CCDEF60810D6021A1E7BE703D91E0DFCE3BD50BCAC0D7456EB5017213`.
  Its nine local tests pass in 122ms. Its transaction body is byte-identical to
  the earlier frozen v2 guard; only the separately verified target constants
  and exact deployment pin change. The earlier operator is not reused against
  this record, and the earlier 12:43 repair receipt remains intact.
- On the new runtime, the READ ONLY preview verifies the current owner, target,
  immutable intent/media, exact provider record/version and five-operation
  snapshot, returning `wouldWriteRows: 2`, `writtenRows: 0`.
- One authorized apply runs around 14:12 UTC. It returns `ok: true`,
  `writtenRows: 2`, quota/immutable/target/owner/operation proof true,
  `durableBlockersPreserved: true` and `independentReadbackVerified: true`.
  A subsequent explicit READ ONLY `--check` succeeds with `alreadyRepaired: true`,
  `wouldWriteRows: 0`, `writtenRows: 0`.
- Only the existing parent and selected TikTok receipt change: parent PUBLISHED,
  receipt PUBLISHED/DRAFT, genuine provider ID retained, no external live URL or
  error, original handoff timestamp `2026-10-15T13:48:29.430Z`. All five unresolved
  operation rows remain unchanged with snapshot SHA-256
  `230bb6a22ce95721866413c9262ca27b6af045ad2b0e5d33ccba95195d334784`;
  they are not deleted, expired or reconciled. No provider resend, requeue, quota,
  billing, authentication, environment, Production or new APK change is made.
- At 14:13 UTC, installed APK12021 Calendar and the reopened detail show
  `ส่งเป็นร่างแล้ว` for this later record; the earlier repaired record stays correct.
  Proofs `user12021-tese-inbox-repaired.png` and
  `user12021-tese-inbox-repaired-calendar.png` are under
  `D:/PostDeeMobile/.tmp/tiktok-fps-native-probe-20261015/session-results/`.
- These receipts verify PostDee history and canonical provider Inbox handoff.
  The original real CREATE payload remains uncaptured; its inferred explanation
  is not upgraded to a raw capture. User-side Inbox confirmation and final public
  publication remain unverified and require the user's action.
- A subsequent receipt-only commit will advance main with CI/Render skip markers;
  runtime remains `e191ed7` and no second deployment is required for these docs.
