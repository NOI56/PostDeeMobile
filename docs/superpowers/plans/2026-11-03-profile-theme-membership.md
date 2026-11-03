# Store-link theme membership

## Scope and isolation

The owner requested Simple (เรียบง่าย) for free accounts and every other theme
category for subscribers. The local `codex/link-theme-membership` branch starts
at freshly verified main `181f312645618f15211905d87f13d15f439b3c80` in its own
worktree. The dirty Claude checkout and other worktrees are untouched. No
interaction with Claude, pending shutdown, deployment, APK installation, live
migration, merge or publication is authorized in this implementation.

## Chosen behavior

- Membership means an active **purchased** Starter, Pro or Business plan, using
  the existing purchased-plan contract. Admin trial elevation and consumable
  credit balances are not purchased subscriptions. Their existing other benefits
  remain unchanged.
- Only category `minimal` is free. Every other raw catalog category and legacy
  non-minimal theme is premium; the existing picker layout/categories are kept.
  New categories default to premium rather than requiring a new allowlist.
- An additive `subscription.canUsePremiumProfileThemes` is authoritative.
  Missing/error proof fails closed in Mobile; API must be delivered first.
- Preserve authored appearance in storage and drafts. On expiry/error, display
  a separate canonical Simple projection, retaining text, links and owned images.
  Never persist the projection merely because membership changed.
- Permit content-only updates retaining existing premium styling, including
  omitted-appearance and exact legacy catalog replay. Reject new/changed premium
  styling with `403 LINK_IN_BIO_PREMIUM_THEME_REQUIRED`. Explicitly choosing a
  different free style remains an intentional owner edit.
- Public pages use the profile owner's purchased entitlement, not the viewer's
  headers. Keep public static assets available, but do not cache rendered page
  entitlement decisions. Restoring membership re-enables the retained design on
  the next refresh unless the owner intentionally selected a replacement.
- Preserve existing image ownership/pruning, catalog conflict guards, link
  limits, account/session protection, subscription checkout and credit banks.

## Data and rollout

No schema migration or data rewrite is expected. Both memory and Prisma stores
must support internal owner/profile rendering lookup without exposing owner ID
in profile JSON. API/readers precede compatible Mobile; old apps cannot bypass
server publication/render enforcement even if their local picker lacks locks.
No hosted changes are performed. Native visual/purchase verification is separate
from unit/widget fixtures and any uninstalled local build.

## Verification

Implementation and local verification are complete. Tests cover
free, all paid plans, expired, restored, trial-only, top-up-only, absent/error
proof, public visitor spoofing, retained style/content, legacy catalog replay,
account changes and accessible Thai/English layouts.

Completed checks on the frozen source:

- `npm test -- --maxWorkers=2`: 3,604 passed, 77 optional tests skipped.
- `npm run typecheck`, `npm run build`, `npm run prisma:validate`, Prisma seed/
  config helper TypeScript check: passed. Fresh Prisma client generation passed.
- Template generator parity check: all seven categories / 140 templates; its
  28 tests and the 61 cartoon-art source tests passed.
- `npm audit --omit=dev --omit=optional --audit-level=high`: passed the required
  threshold. Four existing moderate Sentry/glob/minimatch findings remain;
  dependencies and lockfiles are unchanged by this task.
- All 30 existing migrations applied to a new disposable PostgreSQL 18 fixture
  on loopback port 55441, database `postdee_addon_test`, schema `theme_access`.
  Both new real-Prisma tests passed: paid expiry/restoration and a Serializable
  cross-transaction stale-style conflict, with saved appearance preserved. All
  three existing real-Prisma slug-reservation tests also passed. The task's own
  cluster was stopped after the checks; fixture files are retained as evidence.
- `flutter analyze --no-pub`: no issues. `flutter test --no-pub --concurrency=2
  --reporter expanded`: 5,046 passed, 10 optional preview/test cases skipped.
- Staging CI configuration guard tests: 21 passed.
- Tests-first evidence includes policy/flag denial, open-preview entitlement
  refresh and inactive-background-image removal failing before their fixes.
  Scoped Mobile checks passed 247 tests plus two copy regressions.
- Two independent final source reviews found no unresolved issue after fixes
  for live full-screen preview refresh, saved-versus-temporary theme wording,
  inactive image removal and atomic concurrent-style validation.
- SHA-256 comparison of 1,362 API/Mobile/shared source files confirms the frozen
  source remained unchanged during the final suites. No dependency, product,
  schema, billing-provider or runtime configuration changes are present.

The guarded `postdee-staging.ps1 -Command build-apk --no-pub
--target-platform=android-arm64` build passed (Gradle 191.6 seconds), without
installation. It validated the existing Staging API,
Firebase configuration and RevenueCat Test Store overlay without copying or
printing keys. Generated APK outputs use a new task-only D: artifact directory
through this worktree's `build` junction; completed widget-test output is kept
in `.tmp/theme-access/widget-build`. Other checkouts, installed APK 12096 and prior artifacts
are untouched.

APK identity is `com.postdee.postdee_mobile.staging`, version `0.1.0-staging+1`,
SHA-256 `72b960662f390080ba76c35299f0da72cfb85b3e41f404cbaeaae4d441702a92`.
This is an uninstalled build artifact, not an update package for installed build
12096. A future authorized device update needs the correct target architecture,
an appropriate build number and the existing volume-preserving updater.
The build used `https://postdee-api-staging.onrender.com`, Firebase project
`project-798caf7e-85b8-45e3-af7`, Firebase auth with local mock auth disabled,
and RevenueCat Test Store. It did not call a paid checkout or prove the new
API capability is deployed. Existing Kotlin/deprecation warnings do not block
this build; no SDK or plugin dependency was changed here.

The Thai preview `.tmp/theme-access/preview/member-theme-locked-th.png` is a
376x900@2x widget fixture, visually checked with real fonts. It is not evidence
of a native-device installation, Store sandbox purchase or live public page.
Native interaction and screen-reader behavior are not verified. API must precede
Mobile: a previous API without the additive capability keeps premium access
locked in the new client until compatible API delivery.

This request authorizes a reviewable local commit, not a new remote PR. No
hosted data, provider setup, production flags or current device is changed.
