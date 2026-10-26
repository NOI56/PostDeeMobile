# Account deletion: PostPeer profile cleanup and activation gates

Date: 2026-10-25 (Asia/Bangkok)

Status: source change on branch `claude/beautiful-feynman-spud2a`, based on
verified main `629c97f`. Not deployed. `FIREBASE_AUTH_DELETE_ENABLED` stays
`false` in Production and Staging.

## Context

The user asked to make account deletion safe enough to enable in Production.
Review of the current source found that the blocker described in several docs
("the owner coordinator is process-local") is already resolved: the durable
PostgreSQL drain from
[the shared owner operation drain](2026-10-14-shared-owner-operation-drain.md)
and [deletion authorization](2026-10-14-account-deletion-authorization.md) are
on main and Live on Staging since 2026-10-14. The remaining activation gates
are mostly real-service acceptance, not code.

One code gap remained from the drain plan's gate 4 ("pending OAuth flows that
can finish outside an API handler"): deletion disconnected every PostPeer
integration but left the PostPeer profile in place. A connect URL opened in a
browser before deletion could still finish OAuth afterwards and attach a new
social account to that orphaned profile, where PostDee could no longer see or
remove it.

## Change

- `PostPeerConnectClient.deleteProfile` calls `DELETE /v1/profiles/{id}` with
  the existing `x-access-key` request helper. `404` counts as already deleted;
  other failures raise `PostPeerConnectProviderError`. PostPeer documents this
  endpoint as a soft delete that blocks new connections and keeps existing
  integrations, so the saga disconnects integrations first.
- `DELETE /account` deletes the profile only after every integration
  disconnect succeeds. A failed profile deletion returns the existing
  `503 ACCOUNT_SOCIAL_CLEANUP_FAILED` before media, database or identity
  cleanup, keeping the local profile mapping for retry.
- After a successful profile deletion the local social records are dropped
  immediately, so a retry after a later failure (for example R2 cleanup) does
  not list integrations of the deleted profile again.
- No API response field, schema, migration, dependency, flag or Mobile change.

A small race remains: an OAuth that completes between the final integration
listing and the profile deletion call can leave one integration on the
soft-deleted profile. The window shrinks from the lifetime of an open connect
page to the duration of one provider request.

## Verification

- New tests were added first and observed failing (6 failures) before the
  implementation: three client tests (endpoint/encoding, 404 idempotency,
  non-404 error) and account route tests for call order, profile-deletion
  failure retaining data/profile, no profile deletion after a failed
  disconnect, and a media-failure retry that does not revisit PostPeer.
- Targeted: 79/79 in `accountRoutes.test.ts` and `postPeerConnectClient.test.ts`.
- Full API suite (Node 22.22.0, `--maxWorkers=2`): 175 files passed, 8 skipped;
  2,829 tests passed, 50 skipped (database fixtures need
  `ADMIN_TEST_DATABASE_URL`/a local PostgreSQL, unavailable here).
- `npm run typecheck`, `npm run build` and `prisma validate` pass;
  `src/config` tests (63) pass after the `render.yaml` comment update.
- Flutter is not installed in this environment; Mobile source is unchanged.
- The PostPeer endpoint was confirmed from PostPeer's documentation through a
  search summary only (the docs host is blocked by this environment's network
  policy). It has not been called against the real provider.

## Remaining gates before `FIREBASE_AUTH_DELETE_ENABLED=true`

1. Run the prepared
   [disposable Staging account procedure](2026-10-14-staging-regression-and-typecheck.md#prepare-a-disposable-staging-account)
   with a Staging-only `FIREBASE_SERVICE_ACCOUNT_JSON`, temporarily enabling
   deletion on Staging: confirm Firebase identity, R2 owner prefix, PostPeer
   integrations and profile, database rows and an isolation-control account.
2. ~~Cover late legacy signed-PUT uploads.~~ Done in the Production Blueprint;
   see [strict multipart follow-up](#strict-multipart-follow-up-2026-10-25).
   Staging keeps `dual`; set its Dashboard value to `multipart` before the
   disposable-account test so the test matches Production.
3. Confirm `FIREBASE_SERVICE_ACCOUNT_JSON` in the Production Dashboard; with
   the flag `true` and no key the API refuses to start.
4. ~~Publish a public account-deletion request page.~~ Added in source; see
   [public deletion page](#public-deletion-page-and-support-address-2026-10-26).
   The admin action for email requests followed; see
   [admin console deletion](#admin-console-deletion-for-email-requests-2026-10-26).
5. Physical-device check of the in-app flow, including reauthentication.

Deployment order for this change: API only. Any environment receives it with a
normal API deploy; no migration is involved.

## Strict multipart follow-up (2026-10-25)

The user confirmed that nobody besides the owner has installed any build
against Production. Legacy signed PUT URLs (5 minutes) are bearer URLs that
account deletion cannot revoke, so an upload started just before deletion
could land under the deleted owner's R2 prefix afterwards. Managed multipart
sessions do not have this gap: the saga aborts them and late part PUTs fail.

- `render.yaml` sets `UPLOAD_PROTOCOL_MODE=multipart` (was `dual`); the
  render config test now requires it. `/uploads` is the only route that hands
  upload URLs to clients; the Link in Bio image upload is server-side.
- Current Mobile always requests `multipart-v1`, so current builds are
  unaffected. A build without the opt-in gets
  `426 UPLOAD_CLIENT_UPGRADE_REQUIRED`. Rebuild the earlier prepared Play AAB
  from current source and confirm it sends `multipart-v1` before uploading it.
- With strict mode, posts referencing a video uploaded through the legacy
  path are rejected by `assertUploadReady`. Production has no external users;
  any old owner-only test post in the suspended Production database may need
  recreating.
- `render.staging.yaml` and the live Staging Dashboard keep `dual`; the
  Blueprint is not auto-synced. Change Staging in the Dashboard before the
  deletion test.
- The Blueprint change applies to Production only when the Blueprint is synced
  or the value is set in the Dashboard; Production is currently suspended.

Verification: `src/config` and `src/modules/uploads` tests pass (191), with
the updated expectation observed failing first.

## Public deletion page and support address (2026-10-26)

The user could not confirm that `support@postdee.app` exists (no evidence of
the domain was found), so they created `postdee.support@gmail.com`.

- Base refreshed by merging main `d89ea80` (Mobile analytics/OTP/draft fixes,
  no overlap with this branch).
- `GET /account-deletion` (`accountDeletionPage.ts`, registered in
  `accountRoutes.ts`) serves a static, unauthenticated page meeting Google
  Play's web-resource requirement: app name, in-app steps matching current
  labels (Account tab → ลบบัญชี → ลบบัญชีถาวร), an email request path that does
  not need the app, and the data deleted/kept. Thai primary with an English
  summary. No script; per-response style nonce in CSP; `form-action 'none'`;
  five-minute public cache. Production URL:
  `https://postdee-api.onrender.com/account-deletion`, reachable only while
  the Production API runs.
- The 30-day response time for email requests is an assumption chosen for a
  solo operator; change the page and `docs/PRIVACY_POLICY.md` together if a
  different commitment is wanted.
- Mobile replaces `support@postdee.app` with `postdee.support@gmail.com` in the
  security and help sheets, both in-app legal documents and the add-on
  purchase help dialog. A Mobile test now fails if any `lib/` file shows the
  old address. Privacy policy, terms and Play listing drafts use the new
  address; their unrelated placeholders remain.

Retained data listed on the page is taken from the current saga: the
`ManagedUploadOwner` tombstone (UID, status, deletion proof time) has no TTL,
add-on transaction IDs stay unlinked for replay protection, released Link in
Bio slugs stay reserved for 30 days, and RevenueCat/store records, published
social posts, on-device drafts and provider backups/logs are outside the saga.
Provider backup retention periods are not stated because they were not
verified.

Verification: page tests (3) were observed failing first, then the account
module passes 128 tests; a Chromium render at 390 px has no horizontal
overflow in light or dark mode. Mobile contact tests (3) were observed failing
first and pass after the change. Full-suite results are recorded in the
commit summary for this change.

## Admin console deletion for email requests (2026-10-26)

The public page promises email requests are handled within 30 days, and the
admin console had no way to delete an account. The owner asked for a delete
button there.

- `registerAccountRoutes` now wraps the unchanged `DELETE /account` body in an
  internal `runAccountDeletion(authUser, responder, operatorAuthorized)` and
  returns `deleteAccountAsOperator(uid)`. Operator mode only skips the owner's
  recent sign-in requirement; proof recording, owner lock, durable drain,
  provider/media/database cleanup, Firebase identity deletion and the
  `FIREBASE_AUTH_DELETE_ENABLED` gate are the same code path.
- `POST /admin/api/account-deletions`: owner only, admin sign-in within 15
  minutes, same-origin JSON header, UUID request id, `expectedEmail` binding
  (UID confirmation in the UI when a member has no email), reason 3–500
  characters without `@`, Owner/Viewer UIDs protected. The route does not run
  inside the target's owner lifetime, otherwise the saga's drain would wait on
  its own ticket.
- `AdminAccountDeletion` (additive migration
  `20261026010000_admin_account_deletions`, no User foreign key, status and
  completion CHECK constraints) keeps request id, actor UID, target UID,
  reason, intent hash, status, last error code and times. A retry with the
  same request id continues after the member row is gone; a completed request
  replays without cleanup; a different intent returns `ADMIN_REQUEST_CONFLICT`.
- Admin UI: **ลบบัญชีนี้** in the owner member drawer, typed confirmation,
  review step, **ลบบัญชีถาวร**, retained request id with **ลองอีกครั้งด้วยคำขอเดิม**,
  Thai messages for every saga error code, and a new **ประวัติการลบบัญชี** page
  (search by exact UID). The local preview fixture supports the flow.
- The public page and privacy draft now disclose the operator record.

Verification:

- New tests were observed failing first: 8 route/integration tests (including
  the real saga through `createApp`: data removed, identity deleted, member's
  own stale session still refused; and closed while the flag is off), 1 data
  source view test, 4 browser-script UI tests and 4 PostgreSQL tests.
- Full API suite: 177 files, 2,845 passed, 50 skipped; typecheck, build,
  `prisma validate` and Prisma helper typechecks pass.
- A throwaway local PostgreSQL 16.x cluster on `127.0.0.1:55439` applied all
  migrations with no schema drift (`prisma migrate diff --exit-code`); the 4 new
  and 18 existing admin database tests pass, and the DB-enabled full suite
  passes 2,867 with 32 skipped (other DB suites use separate variables). The
  cluster was stopped and deleted. Production runs PostgreSQL 18; this check
  used 16.
- Chromium against `npm run admin:preview` (fixture data only): confirmation
  disabled until the email matches and the reason has no address, deletion
  removes the sample member, history shows the completed record, no page
  errors, no horizontal overflow at 390 px.
- Not verified: Staging/Production deployment, the migration on hosted
  databases, real Firebase/R2/PostPeer cleanup through the admin action.
