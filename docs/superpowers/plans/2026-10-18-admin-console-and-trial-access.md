# PostDee administrator console and trial access

Latest delivery: admin UX source `50fba5e` is Live on Staging at 12:32 Bangkok,
18 October 2026 (`dep-dba5im61egvs739eoteg`). API and Flutter CI `39100690775`
passed. See the final release receipt for exact verification and remaining limits.

The subsequent local user/usage accuracy work is tracked separately in
[the usage accuracy plan](2026-10-18-admin-usage-accuracy.md). It adds all-account
reporting, explicit quota/delivery definitions, consistent read snapshots, batching
and safe refresh without changing trial commands or paid-access rules. The release
receipt below remains evidence for the earlier deployed source, not this follow-up.

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

### Initial credential-delivery blocker (resolved by replacement below)

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

## Authorized credential replacement and activation (2026-10-18)

The user approved a locally generated replacement key, upload of its public
certificate only, a temporary Staging-only key-upload exception, immediate policy/
role restoration, Render Staging secret delivery and deletion of the unavailable
original key. No internal browser download page or blocked browser workaround
was used. Private key contents were never printed or committed.

- Generated an RSA-2048 private key and matching X.509 certificate in a dedicated
  local directory whose ACL grants access only to the current Windows user and
  SYSTEM. The public certificate expires `2027-10-18T04:37:46Z`.
- The temporary Organization Policy Administrator role had the condition
  `request.time < timestamp('2026-10-18T05:30:00Z')`, less than one hour after
  authorization. Only Staging's `iam.disableServiceAccountKeyUpload` was temporarily
  overridden. The organization-level policy was not disabled.
- Uploaded the public certificate after policy propagation. Immediately restored
  inherited enforced upload policy and removed the temporary role, preserving
  the owner's seven original roles. Firebase Authentication Viewer remains the
  verifier's only application-data role. A read-only Firebase `getUser` succeeded
  and matched the verified owner. Deleted the unavailable original key and
  refreshed the list to confirm only the replacement user-managed key remained.
- Installed `FIREBASE_SERVICE_ACCOUNT_JSON` in Render Staging, enabled both admin/
  trial flags, and preserved deletion-off/mock-push and unrelated service values.
  Existing-build deployment `dep-dba4t5jbc2fs73a2set0` (source `5ebf8a0`) became
  Live at `2026-10-18T04:45:30Z`. All 20 migrations were already applied; the
  empty publishing-backlog guard passed and the memory scheduler started normally.
- Live Google sign-in exposed a missing CSP script origin in both IAB and Chrome:
  Firebase's popup resolver loads `https://apis.google.com/js/api.js` before opening
  its window. Added the failing regression first, then allowed only the required
  Google script origin while continuing to reject wildcard, unsafe-inline and
  unsafe-eval script execution. Reference:
  https://github.com/firebase/firebase-js-sdk/blob/main/packages/auth/src/platform_browser/index.ts
- The 28 focused admin routes/config/integration tests, API typecheck and build pass.
  Exact-source CI `39098358206` passed both Backend API and Flutter Mobile jobs.
  Fix `349e6c3bb72e0e7f930fb43a6d2284d0c8eb81ec` was pushed to main; deployment
  `dep-dba4v57btjjs73dqde2g` became Live at `2026-10-18T04:50:20Z`. Live CSP includes
  the helper origin. Health/readiness, admin HTML/JS/CSS/config return 200 with the
  expected admin no-store/CSP headers. Public config has only environment and
  Firebase Web settings; unauthenticated session access returns 401.
- Chrome opens Google's account chooser for the intended Firebase project. Input
  and screenshot commands on that popup timed out; the user reported selecting the
  owner, but the observed popup/main page had not completed sign-in. No successful
  owner data-view session or live ordinary-user denial is claimed yet. A subsequent
  IAB attempt loaded the auth helper iframe but still awaited completion. Closed
  the agent-created stalled Chrome popup and reloaded the two admin tabs; the
  enabled Google sign-in button is ready for normal manual sign-in.
- Automatic command approval rejected deletion of the two task-generated local
  private-key files as blocked by policy. They remain in the restricted-ACL directory;
  no alternate deletion method was attempted. Render holds the active credential.

No real customer trial, store purchase, provider publication, Production setting
or emulator installation was changed. Finish real owner sign-in and read-only
view acceptance; install the compatible Mobile build before customer trial grants.

## Live owner read-only acceptance (2026-10-18, Bangkok)

The user opened a new Chrome tab and completed Google sign-in manually, then
asked to inspect the views. The existing session showed the Owner role; it was
not reloaded or replaced during desktop checks. The environment badge remained
STAGING and the runtime source remained `349e6c3`.

| View | Observed live result |
| --- | --- |
| Overview | 3 members, 0 active paid subscriptions, 0 active trials; 2 failed, 1 partial and 7 successful post records |
| Members | 3 rows; owner email search returns one, an absent query returns zero, clearing restores the list; owner detail loads paid/trial access and monthly usage |
| Posts | 10 rows; FAILED filter returns 2; combined partial status + TikTok + 2026-10-14 UTC bounds returns the one matching post |
| Trials | 0 rows, consistent with overview and no grant being confirmed |
| Channels | 3 recorded connections; owner search returns 2; UI accurately states latest publishing permission is not verified live |
| Reports | 0 rows; current-page CSV is disabled without report rows; report limitations are visible |
| Audit | 0 rows after clearing search, consistent with no trial writes during inspection |

Trial-form inspection rejected a blank reason with Thai validation. Selecting
Starter/14 days and entering a review-only reason produced the correct review
summary; Back retained the reason and Cancel closed it. The final Confirm button
was never pressed. A later fresh member opening reset the form to its defaults.

Responsive checks temporarily set Chrome to 390x844: the compact menu navigated,
overview and member drawer fit the width, and Escape from the focused close
button dismissed the drawer. The posts table's content is wider than its own
container but does not expand the page; physical mobile swipes and keyboard
horizontal movement were not established by this run. The viewport override was
reset and the signed-in tab was returned to Overview for the user.

No relevant application console error or framework error overlay was observed.
The warnings returned by the browser came from an unrelated Chrome extension.
Screenshots are saved outside the repository in the task's Windows temporary
folder: `postdee-admin-review-overview.png`,
`postdee-admin-review-mobile-overview.png`,
`postdee-admin-review-mobile-drawer.png`, and
`postdee-admin-review-trial-confirmation.png`.

UX findings for a follow-up (no runtime edits in this inspection):

1. Overview labels and per-channel results expose technical enum values. Translate
   them and distinguish delivery to a draft/inbox from public publication, rather
   than requiring an operator to interpret `PUBLISHED (DRAFT)` or `LIVE`.
2. Opening a member as Owner immediately opens a default Pro trial form. A neutral
   member-details view with a separate explicit grant action would better separate
   inspection from changing access; existing review/identity guards still apply.
3. Empty Trials/Reports/Audit show the generic search-empty message even with no
   search. Explain each page's empty state and why CSV is disabled when appropriate.

Live grant/extend/revoke, a nonempty report/CSV, Viewer/ordinary-user denial,
pagination beyond the current small dataset and Mobile trial refresh were not
exercised. Existing fixture/automated checks do not replace that live acceptance.
No account/paid access/trial/audit record, provider publication, migration,
environment setting or runtime source was changed. Only these documentation
receipts were updated locally; no new push/deploy or test-suite rerun was needed.

## Admin UX follow-up implementation (2026-10-18, local only)

User authorized the three findings above. Verified `origin/main` after fetch:
`790cb224211e44fc0754c182cea5547e960d9f1f`, identical HEAD/merge base and 0/0
ahead/behind, on `codex/admin-trial-console` in the managed admin worktree.
Preserved the six uncommitted documentation receipts from the preceding review.

Changes:

- `apps/api/src/modules/admin/adminDataSource.ts`: Thai overview and channel
  presentation, separate TikTok Inbox draft/live/private/unlisted outcomes,
  explicit unknown-outcome text for legacy records, and safe Thai platform names
  in failure summaries. Non-success statuses take precedence over stale outcome
  values. Raw post status/filter enums, field shapes, queries and paging stay intact.
- `apps/api/src/modules/admin/web/admin.js` and `admin.css`: Owner and Viewer
  open neutral member details; only Owner has explicit grant/extend/revoke actions.
  Keep reason/review/final confirmation, pending-request recovery, recent-auth,
  identity/version/idempotency and paid-plan safeguards. Add view-specific empty
  states, search/filter clearing, CSV help, and a return-to-member-details action.
- `apps/api/scripts/admin-preview.ts`: realistic draft/live/failure examples,
  monthly fixture usage and loopback-only `--empty-trials` mode on 4176 (4177
  with Viewer). The existing preview-auth deployment prohibition is unchanged.
- `adminDataSource.test.ts`: regression coverage for Thai overview, delivery
  outcomes, legacy missing data, stale failed outcomes and safe failure summaries.
  All three tests failed first against the previous source and passed after patch.
  Before patch, browser inspection also reproduced Owner opening directly into
  a default Pro trial form rather than neutral details.

Verification:

- Focused datasource/routes: 13 passed. Full API: **2,245 passed, 8 optional
  isolated-database tests skipped**, 133 passing files and one skipped DB file.
- `npm run typecheck`, `npm run build`, `node --check .../web/admin.js`, separate
  `tsc --noEmit` for the fixture preview and `npm run prisma:validate` passed.
- Built assets include the modified JS/CSS. No schema, migration, dependency,
  feature flag, runtime environment or Mobile change is required; delivery only
  needs the normal API source deployment.
- Rendered QA uses the available CUA browser surface (no external Playwright
  fallback), owner `http://127.0.0.1:4176/admin` and viewer `:4175/admin`.
  Desktop 1280x720 and mobile 390x844 were exercised; temporary overrides reset.
- Correct URL/title, meaningful rendering, no error overlay, screenshots and
  interaction state checks passed. Owner/Viewer/mobile console warnings/errors
  were empty in the captured logs.
- Opening a member shows identity, paid/trial state, signup, post/channel counts
  and monthly usage before any trial form. Viewer has no trial-action controls.
  Blank reason is blocked; Starter/14-day review is correct; Back retains reason;
  returning to details/closing does not save. Mobile menu and Escape work.
- Empty Trials/Reports/Audit have distinct explanations. Search-empty states
  differ from an empty dataset; clearing combined post filters restores rows.
  CSV is disabled and explained for zero rows. Draft/live/failure channel labels
  were visible in the fixture posts table.
- On memory fixture Narin only, grant Starter 14 days, extend 7 days (plan select
  locked), then revoke all completed through final confirmation. Three audit
  entries appeared; purchased Starter remained unchanged. A nonempty fixture
  report enabled CSV and downloaded successfully. This is not a live-data write
  or a live CSV acceptance result.
- Screenshots outside Git: `postdee-admin-ux-member-details.png`,
  `postdee-admin-ux-empty-report.png`, `postdee-admin-ux-post-results.png`,
  `postdee-admin-ux-mobile-member.png` in the Windows temporary folder.

This source is not merged/pushed/deployed. Staging remains `349e6c3` /
`dep-dba4v57btjjs73dqde2g`; no live customer trial, subscription, post, audit,
credential, IAM policy or environment was changed. Live grant/extend/revoke,
nonempty CSV, ordinary-user denial and Mobile trial refresh still require their
separate acceptance checks. Flutter was not rerun because no Mobile file changed.

## Admin UX push and Staging delivery (2026-10-18, 12:32 Bangkok)

The user explicitly requested push/deploy. Fetched main was still `790cb22`,
identical to the implementation baseline. Committed the reviewed 11-file change
as `50fba5e81f2bb4fad966d1aa64f78e26e7025e7b`, pushed the feature branch and
fast-forwarded remote main without force or touching other dirty worktrees.

Verified the user-confirmed My Workspace (`tea-d45nsamuk2gs73cmhol0`), service
`postdee-api-staging` / `srv-d9bb72ojs32c739osa5g`, repo/branch/root and existing
build/start commands. Auto-deploy was off, so triggered one manual deploy of
main through Render MCP after Backend API CI passed. Returned commit matched
`50fba5e`. No service setting, env var, credential or database allowlist changed.
Pre-deploy owner overview had no QUEUED/PUBLISHING posts. Production was untouched.

Deployment `dep-dba5im61egvs739eoteg` became **live** at
`2026-10-18T05:32:00Z` (12:32 Bangkok). Logs confirm no pending migrations, empty
publishing backlog, API listening on 10000 and the existing in-process memory
publish scheduler started. Runtime public configuration still identifies STAGING
and Firebase `project-798caf7e-85b8-45e3-af7`, with no preview token.

Post-live checks:

- `/health`, `/ready`, `/admin`, `/admin/config` and both admin assets returned 200;
  readiness reported database/queue OK. Unauthenticated `/admin/api/session`
  remained 401. Admin no-store and Google popup helper CSP allowance remain intact.
- Runtime JS/CSS bytes match the Git release commit exactly (Unix line endings):
  JS SHA256 `3e9189874e57224a4f06197e5db3b4c095acdd37fae364f5209c7838791ddfd4`;
  CSS SHA256 `901674b2bad724e424a53a263fd054ec705686f8558d5f759fb56a0d821c090b`.
- Existing authenticated owner session loaded Thai overview with members 3,
  paid-active 0, trial-active 0, FAILED 2, PARTIAL 1, delivered 7. Posts loaded 10
  rows, including 2 explicit TikTok Inbox draft results and 5 legacy missing-
  outcome results. Returned the existing owner tab to Overview. Screenshot:
  Windows Temp `postdee-admin-ux-staging-overview.png` (outside Git).
- CI https://github.com/NOI56/PostDeeMobile/actions/runs/39100690775 completed
  success for Backend API and Flutter Mobile. APK build/upload were correctly
  skipped on this push; no Mobile source changed and no app install was needed.
- A separate fresh Chrome login opened Google's account chooser, but automated
  account selection did not finish before cancellation. Closed only those two
  new test tabs and preserved the existing owner session. Do not count this as
  successful fresh login or live verification of the new member/empty-state UI;
  those interactions were verified with local fixtures and release assets match.

No real trial/subscription/post/audit mutation was made. Remaining acceptance:
fresh owner login and new member/empty-state UI on live data, authorized real
grant/extend/revoke, nonempty live CSV, live ordinary-user denial and Mobile trial
refresh. The subsequent documentation-only receipt commit does not change the
runtime and does not require a second deploy or another test-suite run.
