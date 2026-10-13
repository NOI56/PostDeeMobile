# Account deletion retry authorization

Date: 2026-10-14 (Asia/Bangkok).

Status: MAIN PUSH + STAGING DELIVERY COMPLETE. Verified delivery source
`3481f3fcff4c78d11b954a45906341a784d7654c` is Live on Staging; migration 17
is applied. Account deletion remains disabled. This is not Production acceptance.

## Baseline and scope

- Integration branch: `codex/account-deletion-retry-authorization`.
- Baseline: main `1bf125c27ed22fa1eb61bb6e2da1a9016af2b0e6`.
- Isolated checkout:
  `D:/PostDeeMobile/.tmp/security-followup-validation/route-fixture-check`.
- Preserve the original audit report and historical delivery receipts. The
  2026-10-13 security delivery and logo delivery remain separate evidence.
- Change only account deletion authorization, related owner persistence,
  regression tests and these contract/architecture notes. Retain current
  lifecycle fences, queue draining, provider/media cleanup ordering, mobile
  response fields and feature flags.

## Cause and reproduction limit

The account-only verifier can mark an authenticated token as
`identityAlreadyDeleted` when Firebase Admin reports the UID missing. The old
route skipped recent authentication solely because of that marker. A regression
fixture with an old token and no previous deletion request therefore proceeded
to PostDee cleanup. Missing identity is a provider observation, not evidence
that the user authorized deletion.

The reproduction used a Firebase SDK fixture. It is not a confirmed live
Firebase exploit, and this patch must not be described as a full audit or
Production launch acceptance.

## Intended authorization contract

1. Keep proof on the UID-keyed `ManagedUploadOwner` row, separate from `User`,
   in nullable `deletionAuthorizedAt`. The owner proof must survive user-data
   cascading deletion.
2. `getOwnerDeletionAuthorization` reads the same UID's status and proof.
   `authorizeOwnerDeletion` atomically marks `DELETING` and persists server time;
   retries retain the original valid authorization.
3. Only the account route with an extant Firebase identity and finite token
   `auth_time` within five minutes may create proof. Permit at most 60 seconds
   of future clock skew. An absent, non-finite, too-old or too-far-future claim
   cannot grant initial permission.
4. Valid stored proof with owner status `DELETING` or `DELETED` allows an
   authorized retry for the same UID, even with an older still-valid signed
   token or an already-missing Firebase identity. Reject revoked/invalid tokens.
5. `beginOwnerDeletion`, `finishOwnerDeletion` and mock deletion do not create
   Firebase authorization. Status alone, another UID's proof, missing identity
   alone, and legacy `NULL` tombstones are insufficient.
6. Recheck authorization under the owner lock before proof persistence and
   cleanup. Missing repository methods or proof read/write failures return
   `503 ACCOUNT_DELETION_AUTHORIZATION_UNAVAILABLE` before a local deleting
   mark or any queue, provider, media, database or identity cleanup. A busy
   write/drain operation keeps `503 ACCOUNT_WRITE_DRAIN_FAILED`.
7. An ordinary extant-identity readiness request returns
   `{ "status": "ok", "identityAlreadyDeleted": false }` before mobile
   reauthentication. A missing identity returns `200`/`true` only with proof,
   otherwise `403 ACCOUNT_REAUTHENTICATION_REQUIRED`. Readiness creates no
   proof and performs no cleanup.

## Migration and rollout order

Migration `20261014003000_authorize_account_deletion` adds nullable
`ManagedUploadOwner.deletionAuthorizedAt` without a default or backfill.

1. Review and validate the additive migration against a disposable database.
2. Apply migrations to the intended environment and generate the matching
   Prisma client before deploying the API that reads/writes the new field.
3. Verify migration state and exact API source in that environment. Keep
   `FIREBASE_AUTH_DELETE_ENABLED=false` in Production.
4. Exercise authorized retry and rejected first-request cases with disposable
   accounts under controlled conditions before considering enablement.

Old owner rows remain `NULL`. If a legacy account has already lost its Firebase
identity and lacks authorization proof, fail closed. Recovery requires separate
operator verification of the account and original deletion request; do not
backfill, accept the token alone or automatically stamp old tombstones.

The account-deletion patch requires no mobile runtime change, new response
field, dependency, paid-provider activation or feature-flag activation. Four mobile
regression cases cover the existing error/session behavior. Cross-process
database/Redis drain and already-admitted provider calls remain independent
Production gates.

## Initial local verification at `5ebb0ac`

Checks ran in the isolated checkout with the user's existing permission for
normal project tests/builds. Credentials and providers were dummy fixtures;
no live account was deleted. API dependencies and the generated Prisma client
were isolated on drive D before generation; the shared checkout's generated
client was unchanged. No dependency or lockfile change is included.

- TDD: the old implementation failed the unauthorized missing-identity
  regression. The final account route/lifecycle selection passes 55/55;
  memory/Prisma owner authorization and fixture selection passes 37/37.
- Negative cases cover old/future/non-finite authentication claims, missing
  identity without proof, legacy `NULL` tombstones, wrong UID/status, invalid
  proof time, forged request fields, and absent/failing proof-store methods.
  No denied case starts cleanup or creates authorization.
- Positive cases cover proof before cleanup, media/identity partial failures,
  stale/missing-identity retries, app recreation with the same store, and
  preservation of the first proof. Revoked/expired credentials remain rejected.
- Repository cases cover owner FIFO admission, timeout without a late proof,
  Serializable retry exhaustion, and generic lifecycle calls that preserve
  an existing proof without creating one.
- Full API suite: 1,871/1,871 cases in 116 files passed. After a typing-only
  delivery fixture update, its five cases passed again.
- Production API build, Prisma generation, schema validation and the
  `prisma/seed.ts` / `prisma.config.ts` TypeScript helper check passed.
- Offline Prisma schema-to-schema migration diff matches the single nullable
  `TIMESTAMP(3)` column addition. At this initial stage it validated generated
  DDL only; later real-database execution is recorded separately below.
- Full test-inclusive TypeScript checking still reports 142 existing fixture
  errors, matching fresh main by file, error code and normalized message.
  No new error remains; this check is not claimed as passing.
- Mobile compatibility: 159/159 cases across API-client and shell test files
  passed, including four added 403/503 regression cases. Flutter analyze found
  no issues. Mobile runtime files at `5ebb0ac` are identical to baseline main;
  no new APK was built or installed for this backend patch.
- Compiled API smoke passed using `dist`: first unauthorized deletion returns
  403 with retained data and zero media cleanup; an authorized partial failure
  returns 503 and a later stale/missing-identity retry returns 200, retaining
  the original proof. No external service was used.
- Independent source review found no blocking issue in the authorization
  change. This is a focused remediation review, not a new complete audit.

Local verification logs are under
`D:/PostDeeMobile/.tmp/account-deletion-authorization/` (including
`api-full.log`, `mobile-compat-final.log`, `mobile-analyze.log`,
`types-all-final.log`, `types-baseline.log`, `migration-sql.log`, and
`compiled-api-smoke.log`). The earlier failing regression evidence remains
under `D:/PostDeeMobile/.tmp/security-followup-validation/`.

## Disposable PostgreSQL execution validation

Before Staging deployment, an isolated PostgreSQL 18.1 instance on
`127.0.0.1:55442` applied the 16 baseline migrations, then exactly the new
authorization migration as number 17. A further `prisma migrate deploy` reported
no pending migrations. Seeded dummy ACTIVE/DELETING/DELETED owners retained
NULL proof, with no column default or backfill.

The built repository and actual generated Prisma client passed 16 checks:
Serializable status/proof persistence, fresh-client durable reads, UID isolation,
first timestamp preservation, invalid-date rejection, User/Template cascade
independence, generic lifecycle calls without authorization, DELETED preservation
and simultaneous authorization through two clients. These two clients do not
establish multi-process SQL/Redis atomicity. The test accessed no remote database.
Its own server was stopped, the port is free, and data/logs were retained.

Receipt:
`D:/PostDeeMobile/.tmp/account-deletion-authorization/pg18-a1d61bcc-7d69-4646-a13a-78d8b2194f16/real-prisma-receipt.json`.
SHA256: `65031AD6DD857411524DE1D25488CE74D051294A4AD0F5BE51344C9F1CC89496`.

## Main and Staging delivery receipt

- The user subsequently requested main/push/deploy. Scope is the existing
  Staging service used by the test app. Production is not resumed or deployed.
- Remote main was freshly verified at `1bf125c`; branch protection was absent
  and applicable branch rules empty. The canonical main checkout fast-forwarded
  to `5ebb0ac` and later `3481f3f`; both the review branch and main were pushed
  normally and verified exact. Six existing generated/QA files retained their
  original SHA256 hashes, and the original dirty checkout was preserved.
- Initial CI `38451840383` passed Backend but failed Mobile analyze on a new
  Flutter 3.47.7 warning: a Future returned inside the logo crop's try/finally
  lacked `await`. Follow-up `3481f3f` adds only that await before resource disposal.
  Its eight existing logo tests and local analyze passed. API tree
  `a24e74b604c5e3359dbca4905bf480123e1aadba` is identical to `5ebb0ac`.
- [CI 38452410378](https://github.com/NOI56/PostDeeMobile/actions/runs/38452410378)
  passed on exact `3481f3f`: API 1,871/1,871 in 116 files, generator 22/22,
  catalog 100 templates/5 categories, build and Prisma generate/validate;
  Flutter 3.47.7 analyze and full Mobile 2,189/2,189. Node 22.23.3 and Prisma
  6.19.3 ran on CI. The production dependency audit passed its high threshold
  with four moderate advisories; it is not a zero-advisory claim. APK build/upload
  was skipped deliberately; no APK was built or installed in this delivery.
- Commits contain `[skip ci] [skip render]`; CI was explicitly dispatched.
  Staging auto-deploy was verified off, and its existing build/start commands
  were retained. A single API-triggered deploy selected the tested current main
  SHA; the returned deployment metadata confirmed exact `3481f3f`.
- [Staging dep-db785nvavr4c73a1cm80](https://dashboard.render.com/web/srv-d9bb72ojs32c739osa5g/deploys/dep-db785nvavr4c73a1cm80)
  started **02:13:35 GMT+7 on 2026-10-14** and became Live **02:15:41 GMT+7**
  (2m06s). Build/client generation succeeded on Render Node 26.11.1.
  Start ran migration before pruning dependencies and serving the new API.
  Logs show migration `20261014003000_authorize_account_deletion` applied and
  all 17 migrations successfully applied.
- Read-only checks through the new instance's internal Web Shell confirmed
  source `3481f3f`, database `postdee_staging`, 17 completed migration records,
  exactly one completed authorization migration, nullable timestamp without
  default, and zero non-NULL authorization records through the actual new
  Prisma client. Database external access remains blocked; no IP rule changed.
- Runtime remains one instance, Firebase auth, the existing Staging Firebase
  project, `FIREBASE_AUTH_DELETE_ENABLED=false`, `SOCIAL_PUBLISHER=disabled`,
  and `PUBLISH_QUEUE=memory`. No feature flag, secret, service plan or provider
  activation changed.
- `/health` and `/ready` return HTTP 200 with database/queue ok. Unauthenticated
  account deletion readiness, publishing readiness and POST billing purchase
  readiness return HTTP 401. This verifies the auth gate, not an authenticated
  real-Firebase deletion flow.
- The existing public shop returns HTTP 200 with the same displayed shop name
  and two visible links. Raw HTML hashes vary because every response has a fresh
  CSP nonce; nonce-normalized hashes match across two post-deploy requests.
  This is public-page acceptance, not native signed-in session acceptance.
- No error-level application logs were returned for new instance `xsgdd` from
  Live through **02:18:49 GMT+7**. Production API remains user-suspended;
  its last deployment is unchanged. No Production database mutation occurred.

Delivery logs and generated records stay under
`D:/PostDeeMobile/.tmp/account-deletion-authorization/`; they are excluded from
Git. The documentation-only receipt follow-up needs no duplicate deployment.
API/ARCHITECTURE contracts remain the implementation contracts above.

## Remaining gates

Live PostgreSQL/Redis cross-process draining, real Firebase/provider cleanup
and mobile-device deletion acceptance remain unverified. The migration and
disabled-feature deployment do not satisfy those enablement gates. Keep real
deletion disabled until the separate rollout checks are complete. Full
test-inclusive TypeScript fixture debt remains as recorded above. The original
full-audit report and prior delivery receipts have not been rewritten.
