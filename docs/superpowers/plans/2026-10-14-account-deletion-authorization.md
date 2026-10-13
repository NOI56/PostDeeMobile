# Account deletion retry authorization

Date: 2026-10-14 (Asia/Bangkok).

Status: local implementation and verification complete. Main integration,
push, database migration and deployment are not part of this receipt.

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

No mobile runtime change, new response field, dependency, paid-provider
activation or feature-flag activation is required for this patch. Four mobile
regression cases cover the existing error/session behavior. Cross-process
database/Redis drain and already-admitted provider calls remain independent
Production gates.

## Verification record

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
  `TIMESTAMP(3)` column addition. This validates the generated DDL, not execution
  against a real PostgreSQL database; the migration has not been applied.
- Full test-inclusive TypeScript checking still reports 142 existing fixture
  errors, matching fresh main by file, error code and normalized message.
  No new error remains; this check is not claimed as passing.
- Mobile compatibility: 159/159 cases across API-client and shell test files
  passed, including four added 403/503 regression cases. Flutter analyze found
  no issues. Mobile runtime files are identical to main; no new APK was built
  or installed for this backend patch.
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

Live PostgreSQL/Redis cross-process behavior, real Firebase/provider cleanup,
mobile-device deletion acceptance and Staging delivery remain unverified for
this patch. Keep real deletion disabled until the separate rollout checks above
are complete. The original full-audit report and prior delivery receipts have
not been rewritten.
