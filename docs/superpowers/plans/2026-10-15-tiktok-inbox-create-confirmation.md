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
  publication. The later PostDee row remains FAILED at this diagnostic stage;
  no historical mutation or provider resend is performed for this record.

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
- This locally verified correction is not yet committed, merged, pushed or
  deployed to Staging. Installed APK12021 and Mobile source remain unchanged;
  no new Mobile/native runtime verification is claimed for this backend fix.
- The later historical row has not been repaired. Any separate correction must
  re-prove its owner, immutable intent, provider record and current row version;
  deployment alone cannot rewrite an already FAILED row. Do not reuse the earlier
  record's operator artifact, timestamps or row guards for this later record.
- No provider POST/retry/requeue, billing action, phone verification, account
  reconnection, environment change or Production delivery is included.
- User-side TikTok Inbox confirmation and final public publication remain
  unverified and require the user's own action.
