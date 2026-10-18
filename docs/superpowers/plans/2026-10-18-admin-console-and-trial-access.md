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
The initial implementation scope did not authorize deployment, changing actual account privileges,
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

## Authorized Staging delivery follow-up (2026-10-18)

The user subsequently authorized main integration/push, Staging deployment,
Firebase Web sign-in setup and owner access, with no grants to other customers.
Firebase Console verified the intended owner email/UID in the Staging project;
personal owner identifiers remain in an ignored local preparation file, not source.

Main advanced to `caf1e5029f3d18bef7d1436dd08e5572e590cc92` during release.
The feature commits were rebased again, preserving the Android app-storage update
and its delivery evidence. The only conflict was the Mobile README header; both
trial documentation and the newer Android-delivered status were retained.
API, Mobile application and test code are identical to the previously verified
feature code. The resulting source is `5ebf8a0db260198a8df78925d4c56b5b12bd59fc`,
pushed to remote main without overwriting the other main checkout's work.

- Local release API run: 132 files / 2,242 tests passed; the eight opt-in database
  tests were skipped in this run and previously passed against the isolated cluster.
  Build, typecheck, Prisma/helper checks and prepared Staging configuration passed.
- Exact-source Backend and Flutter CI `39095519413` passed; unsigned iOS build
  `39095519418` also passed. Runtime dependency audit has four moderate findings,
  no high finding under the deployed `--omit=dev --omit=optional` policy.
- Render database export `2026-10-18T04:01Z.dir.tar.gz` is ready in the existing
  Staging Recovery page; no download link/token or database credentials are recorded.
- Source deployment `dep-dba4cdajnfac73eaidg0` became Live at
  `2026-10-18T04:10:19Z`. Both new migrations applied successfully to
  `postdee_staging`; `/health` returned HTTP 200.
- Firebase Web app `PostDee Admin Staging` was registered with no Firebase Hosting.
  Existing Google sign-in remains enabled; the exact Staging Render hostname was
  added to Authorized domains. A dedicated verifier has only Firebase Authentication
  Viewer access. Firebase user deletion remains off and push remains mock.
- The user separately approved a temporary owner Organization Policy Administrator
  grant, expiring at `2026-10-18T05:00:00Z`, and a temporary key-creation exception
  for the Staging project only. After one user-managed verifier key was created,
  the project returned to inherited enforced key-creation policy and the added
  owner role was removed, preserving all seven original roles. The organization
  policy itself was never disabled.

### Remaining activation blocker

Google Console reports the private key file was saved, but the browser download
event timed out and the named file was not found in the Windows Downloads folder
or scoped task/app temporary locations. The browser security policy rejected
opening its internal downloads page; no alternative browser surface, raw CDP,
hidden page state or network workaround was used. The user must provide the saved
file location or complete the local save before credential delivery can continue.
No private key has been printed, committed or installed on Render.

Seven admin-only configuration keys are prepared on Staging with
`ADMIN_CONSOLE_ENABLED=false` and `TRIAL_ACCESS_ENABLED=false`. No administrator
session or customer trial mutation has been performed. Complete credential
delivery, enable flags consistently, verify real owner sign-in/read-only views,
and install compatible Mobile before customer trial acceptance. Production,
store purchases and provider publication were not changed by this delivery.
