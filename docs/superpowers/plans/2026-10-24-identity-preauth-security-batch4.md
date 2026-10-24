# Identity and pre-auth hardening: security Batch 4

Baseline: latest verified `origin/main` at
`a4efd650d7a74b26fc81e11ccb8bf59d2eeaa79a` (2026-10-24), ahead/behind 0/0.
Implementation branch: `claude/security-batch4-identity`, in its own clean
worktree. Only audit run-2 Batch 4 is in scope; it does not depend on the open
Batch 2 or Batch 3 pull requests.

## Reproduction before implementation

Eight regression cases failed against the baseline on 2026-10-24 with injected
fakes only (18 cases in the four touched test files, 10 passed):

| Item | Test | Expected | Before-fix result |
| --- | --- | --- | --- |
| 4a | Token with `email` but no or false `email_verified` | No email stored | Email copied (both verifiers) |
| 4a | Upsert hits P2002 on `email` | Fallback address, 2 upserts | Error rethrown (500 in routes) |
| 4b | 5 concurrent cold verifications | 1 certificate fetch | 5 fetches |
| 4b | Two failed refreshes within 5 s | 1 fetch | 2 fetches |
| 4b | Default fetch | `AbortSignal` passed | No signal |
| 4c | 50 requests after 50 clients are tracked | At most 1 sweep | 50 full sweeps |
| 4c | Third client with a cap of 2 | Oldest client evicted | No cap |

Guard cases that pass both before and after: a verified email is kept, a
non-email P2002 is still rethrown, and an expired bucket that has not been
swept yet starts a fresh window. These are local reproductions, not deployed or
Firebase acceptance tests.

## Change boundaries

- 4a: `firebaseTokenVerifier` and `firebaseAdminTokenVerifier` map `email`
  only when `email_verified === true`. `createPrismaUserRepository.ensure`
  retries once with `buildFallbackEmail` when the upsert fails with P2002 whose
  target includes `email` (or has no target). The other row is not changed.
  A non-email P2002, or a conflict on the fallback address itself, still throws.
- 4b: the built-in verifier keeps one in-flight refresh promise, caches a
  failed refresh for 5 seconds and passes `AbortSignal.timeout(5000)` to the
  default `fetch`. The Firebase Admin verifier keeps the SDK's own caching.
- 4c: `createRateLimitMiddleware` sweeps expired buckets at most once per
  window, treats a stored but expired bucket as a new window, and evicts the
  oldest client when `maxTrackedClients` (default 10,000) is reached.

## Compatibility and deployment notes

- Existing users whose Firebase email is unverified will have their stored
  email rewritten to `firebase-<uid>@postdee.local` on their next request. The
  admin console shows that address for them, and member trial confirmation must
  use it. Verified Google and email accounts are unchanged.
- No schema change, migration, env var or `render.yaml` change.
- Owner check: confirm in the Firebase console whether email/password sign-up
  and email enumeration protection are enabled in Production; this change does
  not depend on it.

## Verification

- `npm.cmd run test`: 154 files passed, 4 skipped; 2577 tests passed, 25 skipped.
- `npm.cmd run typecheck` and `npm.cmd run build`: passed.
- Mobile code is unchanged, so Flutter was not run.
- Not verified on a deployed environment or against a real Postgres unique
  index; the P2002 path uses a Prisma-shaped fake error.
