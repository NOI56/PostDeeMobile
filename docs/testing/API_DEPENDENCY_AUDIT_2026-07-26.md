# API dependency audit — 2026-07-26

Scope: production dependencies under `apps/api`.

## Result

`npm audit --omit=dev --audit-level=moderate` reports:

- 0 critical
- 5 high
- 6 moderate
- 11 total

The five high entries are one transitive chain:

`firebase-admin` → optional Firestore → `google-gax` → `rimraf` → `glob` →
`minimatch` → `brace-expansion`

PostDee does not import `glob`, `minimatch`, `rimraf`, `brace-expansion`, or
`uuid` directly, and no user-controlled glob pattern is passed by application
code. This lowers current reachability but does not remove the upstream issue.

## Safe-fix checks

- `npm audit fix --dry-run` proposed no non-breaking package changes.
- The reported full fix is a major downgrade from `firebase-admin` 14.2.0 to
  10.3.0. It was rejected because it would move the direct dependency
  backwards and risks Firebase compatibility.
- Adding `@google-cloud/firestore` 8.7.0 directly did not reduce the 11
  production findings.
- Overriding `brace-expansion` to the fixed 5.0.8 reduced the audit to six
  moderate findings, but the runtime compatibility smoke test failed:
  `minimatch` 9 imports a default export that `brace-expansion` 5 does not
  provide. That override must not be shipped.
- Latest checked upstream versions still expose the affected transitive
  ranges, so the remaining fix must come from compatible upstream releases.

## Decision

Do not change `package.json` or `package-lock.json` for this audit. Keep
`firebase-admin` current, monitor compatible releases, and rerun the production
audit before release. Do not use `npm audit fix --force`.
