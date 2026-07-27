# API dependency audit — 2026-07-26

Scope: production dependencies under `apps/api`.

## Result

`npm audit --omit=dev --audit-level=high` now exits successfully and reports:

- 0 critical
- 0 high
- 6 moderate
- 6 total

The resolved high entries were one transitive chain:

`firebase-admin` → optional Firestore → `google-gax` → `rimraf` → `glob` →
`minimatch` → `brace-expansion`

The API now scopes an override to `rimraf` only under `google-gax`. The resolved
chain is `rimraf` 6.1.3 → `glob` 13.0.6 → `minimatch` 10.2.5 →
`brace-expansion` 5.0.8. `firebase-admin` remains at 14.2.0.

## Safe-fix checks

- `npm audit fix --dry-run` proposed no non-breaking package changes.
- The reported full fix is a major downgrade from `firebase-admin` 14.2.0 to
  10.3.0. It was rejected because it would move the direct dependency
  backwards and risks Firebase compatibility.
- Adding `@google-cloud/firestore` 8.7.0 directly did not reduce the 11
  production findings.
- Overriding only `brace-expansion` to 5.0.8 was rejected because the ESM smoke
  test proved it incompatible with `minimatch` 9.
- The scoped `google-gax` → `rimraf` 6.1.3 override upgrades the complete
  matching dependency chain instead. CommonJS and ESM minimatch smoke tests,
  `google-gax`, and `firebase-admin/firestore` imports all pass.
- A clean `npm ci` followed by Prisma generation, all 684 API tests, the
  TypeScript build, Prisma validation, and the production high-severity audit
  pass with the scoped override.

## Decision

Keep the scoped `google-gax` → `rimraf` override until `google-gax` accepts
`rimraf` 6 upstream, then remove the override after another audit and smoke
test. The six remaining findings are moderate `uuid` findings in the Google
storage chain; do not use `npm audit fix --force` because it proposes a
breaking Firebase downgrade.
