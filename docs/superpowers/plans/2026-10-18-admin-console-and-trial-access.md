# PostDee administrator console and trial access

## Authorization and baseline

The user approved implementation of the seven Thai administrator views and the
recommended roles, environment labeling, usage reports and time-limited trial
grants. Initial canonical main was `c813eef72d1bc98e958b86ae2928e80a20939f8a`.
During implementation main advanced to `f4e899fda1017d86132ca9550c3d8137a11a8bf6`.
The private feature branch was rebased onto that freshly fetched main, preserving
all unified channel settings and optional Meta disclosure behavior. Documentation
conflicts were resolved by retaining both feature sections. No integration into
main, remote push or deployment was performed.
Implementation uses the clean `codex/admin-trial-console` worktree. Existing
generated Windows modifications and unrelated artifacts remain in their worktrees.
This scope does not authorize deployment, changing actual account privileges,
granting real customer access, sending social posts, refunds or paid purchases.

## Chosen boundary

The console uses the existing Express deployment, Firebase identity, PostgreSQL
and paid subscription rules. A separate, expiring PostDee trial ledger augments
effective access without editing store purchases or RevenueCat subscriptions.
This avoids replacing a paid Starter/Pro record with a temporary promotion.
All API and worker entitlement checks use the higher active paid/trial plan;
expiration/revocation preserves existing paid access and never resets usage.
No recurring charge or store subscription is created by a trial grant.

The administrator surface is disabled by default. Owner/viewer Firebase UIDs are
configured server-side, never selected by email or supplied in browser claims.
Only owners with a recent authenticated session can change trial access. The
browser never receives a service account key, database URL or provider secret.
Writes require a same-origin JSON request, explicit review, a reason, immutable
request identity, optimistic version and a durable audit in the same transaction.
Target-account deletion barriers and cascading data removal must remain intact.

## Views and limits

- Overview: observed member, trial and publication counts.
- Members: bounded search, purchased plan, separate trial and channel details.
- Posts: bounded status/platform/date search with redacted failure summaries;
  no publication/retry/delete action.
- Trials: registered-account grant, extension and revocation. Presets 7/14/30
  days; extension is bounded to 90 days ahead. No lifetime grant.
- Channels: stored connection identities/status; no delegated OAuth or raw tokens.
- Reports: trial/usage cohorts and CSV export. Estimated costs require explicitly
  configured unit rates and are labeled estimates, not invoices. A paid plan
  observed after a trial is not automatically attributed as a conversion.
- Audit: actor, target, reason, immutable intent and before/after trial state.

Static client assets follow the existing Express HTML delivery convention to
avoid adding a separate hosting service or frontend dependency/build pipeline.
Layout follows the ImageGen member-table/trial-drawer concept with semantic HTML,
responsive navigation, shared tokens/components and reduced-motion support.

## Preservation and verification gates

Preserve Firebase session ownership, all paid-package rules and quotas, RevenueCat
ordering/restore behavior, scheduled publishing, AI gates, account deletion,
retained owner operations, R2 uploads, mobile and public shop pages.
Add regression tests before implementation; verify owner/viewer isolation,
disabled-by-default behavior, forged roles, expired sessions, stale/double writes,
trial expiry, paid/trial overlap and CSV safety with dummy identities. Run API
tests/typecheck/build/schema validation and browser workflows against a local
fixture server. No live account grant or external provider call belongs to QA.

The additive migration must precede enabling trial access or the admin console.
Actual administrator UID, public Firebase web configuration and HTTPS origin are
deployment configuration; no user is granted administrator access by this source.

## Local verification record (2026-10-18)

The disabled-by-default client/server implementation and both SQL migrations are
committed on the private `codex/admin-trial-console` branch. The test cluster is a
new loopback-only PostgreSQL 18 cluster on port 55439, database
`postdee_admin_fixture`; no Render connection credentials were used in local QA.
The opt-in database test suite refuses other hosts/ports/database names.

- Applied all 20 migrations to the isolated database. A schema diff initially
  exposed missing Shopee/Lazada enum values in migration history already present
  in the original baseline schema. Added a separate idempotent reconciliation
  migration; the final Prisma schema diff reports **no difference**.
- Eight actual PostgreSQL checks cover schema values, grant/audit atomicity,
  exact replay/conflicting intent, simultaneous grants, rollback after audit
  failure, reviewed-email changes, missing members, deletion tombstones/cascades,
  usage/plan projections, optional estimates and stable 50-row pagination.
- Application-route tests cover grant/revoke/expiry, member scope, effective
  billing/AI capability, RevenueCat resync without paid access, worker factory
  behavior and preservation of purchased Starter/Pro access.
- Purchase confirmation has its own paid-plan projection. A Pro trial must not
  satisfy a Pro store confirmation before paid access arrives, and paid Starter
  can be bought/restored beneath an effective Pro trial. Mobile checks
  `purchasedPlan`, paid resync is separate from AI capability recovery, and
  readiness gates legacy confirmation clients while a trial upgrades access.
  Regression tests first reproduced early Pro confirmation and a failed Starter
  restore, then verified waiting for paid access, retained Pro capabilities,
  old-API fallback, invalid metadata rejection and original account binding.
  Release API/worker support first, then compatible Mobile, before customer grants.
- Compiled `dist` smoke checks HTML/JS/CSS/Thai fonts, actual Firebase Admin
  revocation-check wiring through a dummy verifier, Owner/Viewer/customer
  boundaries, actual Prisma grant/replay, billing capabilities and all seven views.
  This smoke uses a fake identity verifier and no external provider calls.
- Browser QA uses the in-app browser (CUA), local fixture URLs on 4174/4175,
  desktop 1536×1024 and mobile 390×844. All seven views load meaningfully with
  correct title/URL, no blank page/framework overlay or app console errors.
  Tested empty search, failed-post filtering, required reason, review, grant,
  extension, revocation, updated audit, Viewer read-only controls and actual CSV
  download. Mobile table horizontal scrolling is intentional; document width
  equals the 390-pixel viewport after the layout fix.
- Frontend fixes found during QA: align navigation icons, keep keyboard focus in
  modal dialogs, preserve immutable unknown requests, retain a route to history,
  render numerical zeroes correctly, and widen multi-column tables with readable
  mobile headings. Existing Anuphan font assets are reused.

### Concept fidelity ledger

Final verification on the branch rebased onto `f4e899f`:

| Check | Result |
| --- | --- |
| Full API suite, including actual isolated PostgreSQL | 133 files / 2,250 tests pass (`npm test -- --maxWorkers=2`) |
| Mobile full suite | 2,378 pass, two optional previews skipped (`flutter test --no-pub`) |
| API typecheck/build | Pass; static assets copied into dist |
| Flutter analysis | No issues |
| Prisma schema/helper/preview script | Validate and TypeScript checks pass; all 20 local migrations applied |
| Prisma migration → schema diff | No difference detected |
| Compiled app smoke | Pass with dummy Firebase verifier and real local Prisma, including paid/trial split and legacy readiness guard |
| Browser | All seven views, owner/viewer controls, grant/extend/revoke/history/CSV, desktop and mobile pass |
| Android Staging compile/package/signature | 12025 x86_64 debug build passes; not installed |

The first unbounded API run shared heavy CPU work with Flutter and timed out in
three pre-existing catalog/template checks; the new default-config expectation
also needed the two opt-in fields. After that fix, bounded full runs pass without
changing unrelated test timeouts or product code. Final integration-diff review
finds no removed files or changes to unified platform settings/publisher behavior.

Core files: `apps/api/src/modules/admin/`, Prisma schema/two additive migrations,
API config/app wiring, subscription factory and billing projections;
`apps/mobile/lib/core/network/postdee_api_client.dart` and
`apps/mobile/lib/features/billing/store_subscription_service.dart` plus regression
tests; `docs/ADMIN_CONSOLE.md`, root reference documents and Mobile README.

Android package proof uses the validated `postdee-staging.ps1` helper with
`--no-pub --split-per-abi --target-platform=android-x64 --build-number=8025`.
The resulting `app-x86_64-debug.apk` is 127,820,574 bytes, package
`com.postdee.postdee_mobile.staging`, versionCode **12025**, versionName
`0.1.0-staging`, min SDK 24 / target SDK 36. SHA-256:
`F31F72E0AADED996C5A4CDF44002D76F04CF011EE4906494828F701A055E7AC1`.
Signer SHA-256 matches the earlier data-preserving Staging builds:
`014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
The helper validates the Staging API, Firebase project/Web OAuth configuration,
Firebase auth enabled, local mock auth disabled, and the existing RevenueCat Test
Store overlay without printing its SDK key. No install or real login/purchase was
performed. Pre-existing Kotlin/Java deprecation warnings remain; dependencies
were not upgraded. The temporary PostgreSQL fixture server was stopped after QA;
the memory-only admin preview remains available for review.

The ImageGen reference and final saved browser screenshot were visually inspected
at native size. Screenshots are temporary local evidence, not shipped assets.

| Point | Reference → implementation |
| --- | --- |
| Navigation | 244px mint rail, seven outlined icons, emerald selected item retained |
| Header | 88px header, page title, environment badge and logout retained |
| Member table | Four columns and mint selected row retained; purchased plan stays separate from trial |
| Trial panel | 446px panel below desktop header; selected email, plan, 7/14/30 choices and reason retained |
| Actions | Cancel/review preserved; review is followed by explicit confirmation and real transaction result |
| Typography/color | Thai Anuphan from existing assets, white/mint/emerald system; no new font dependency |
| Mobile | Full-width panel and compact menu; wide data tables scroll internally |

Intentional functional differences: metadata is labeled “อัปเดตข้อมูลล่าสุด”
instead of claiming it is a login timestamp; added purchased-plan/current-trial
context and current-month usage; an active trial shows extend/revoke instead of
allowing another overlapping grant. The fixture badge is LOCAL rather than
pretending the screenshot is Staging. Form height follows its actual content.

### Release checks still outside this local delivery

The user supplied an owner email in chat; no personal identifier was hardcoded in
source. Its Firebase UID is not yet verified. A read-only query through the Render
connector was rejected because Staging's external database allowlist is empty;
the network protection was left unchanged. Verify identity through Firebase or an
authorized internal read before setting owner UIDs. Real Google popup/domain
configuration, Staging grants/mobile refresh and Production acceptance remain
unverified. Both feature flags remain off in default configuration.

`npm ci --ignore-scripts` reported 20 existing dependency audit findings (12
moderate, 8 high) on the locked dependencies; versions were not changed as part of
this feature. This work is not a comprehensive security audit.
