# Compact AI caption quota strip — 2026-10-25

This records the original quota-strip implementation. The later
[credit-per-channel contract](2026-10-25-caption-credit-per-channel.md) retains
the strip but supersedes its zero-only generation gating: known combined
availability must cover the complete selected-channel cost. The original tests
below do not establish acceptance or deployment of that accounting change.

## Request and baseline

The user approved a small strip above the caption-generation action, showing
the plan, monthly remainder/limit, used count and a thin remaining bar, then
authorized implementation and a `main/push` delivery.

Port from the earlier local implementation onto verified `origin/main`
`816f58c9` in a clean worktree, then refresh through `d7719cff` onto `f57531dc`
to retain the concurrent bottom-navigation updates. Preserve the original dirty workspace and all
main capabilities, including the pushed four-step wizard, selected-platform
caption generation, style learning, preview/apply/undo, account guards,
effective trial plans, fallback/refund behavior and nonexpiring add-on credits.
Do not copy complete stale uploader, shell or API-client files over main.

## Contract and presentation

- Add authenticated, read-only `GET /captions/quota` with `Cache-Control:
  no-store`, returning `status`, effective `plan` and `quota` containing
  `limit`, `usedThisMonth`, `remainingThisMonth`, `addonRemaining` and
  `availableGenerations`.
- Reuse the shared usage ledger and existing server clock/current UTC month.
  Monthly limits remain Basic 0, Starter 50 and Pro 120; clamp monthly remainder
  at zero without discarding use recorded before a downgrade.
- Paid availability combines monthly remainder and the nonexpiring purchased
  bank, including while new purchases are disabled. Basic can retain a bank but
  cannot generate until it has paid access. Reading never reserves or spends.
- Keep the approved small monthly strip; show `+ เครดิตเติม N ครั้ง` only when
  the bank is nonempty. Disable generation only when total paid availability
  is zero, while keeping manual caption editing and posting independent.
- Load on composer entry and app resume, with owner/request guards. Update
  returned quota before caption edit checks and advanced-preview acceptance:
  a generated result can spend a use even if it is not applied to the form.
- Retry unavailable reads without fabricating zero. Reread after a failed
  generation or a pending refund recount so the strip follows committed usage.

## Verification and delivery boundary

Run test-first API/client/widget/uploader regressions for authenticated scope,
monthly/add-on availability, exhausted-month use of the bank, fallback/refund,
late owner/request responses, text edits and canceled advanced preview. Check
real-font light/dark, narrow-width and enlarged-text rendering. Run current
main's required full suites, analysis/typecheck, build and schema validation,
then review the exact baseline diff before the authorized main push.

Deploy the additive API before distributing Mobile. A still-old API's `404`
must show unavailable/retry, not a false zero. No migration, package-rule,
provider, credential or environment-flag change is required. A code push is not
an API deployment, installed-device acceptance or a live AI/provider check.
Record actual validation/delivery results separately when available; earlier
dirty-branch tests are not verification of this refreshed-main port.

## Verified candidate

- Node 22.23.3: API full suite passed 2,701 tests with 31 skipped using
  `--maxWorkers=2`; the default-worker run hit two resource-contention timeouts,
  and both affected files also passed separately (24 tests).
- API typecheck, build, Prisma generate/validate and helper TypeScript checks
  passed. The production dependency audit reported zero vulnerabilities.
- Profile-template parity check and its 22 tests passed; the Staging
  configuration guard suite passed all 21 tests.
- Full Flutter analysis passed with no issues. Against the initial `816f58c9`
  baseline, the complete Mobile suite passed 2,933 tests with 6 skipped using
  `--concurrency=2`, including the quota,
  nonexpiring-credit, owner/session, refund and preview-cancellation regressions.
- After rebasing onto `d7719cff`, reran the caption widget/client/uploader and
  complete shell/navigation suites: all 104 tests passed, including the newer
  320–411 dp and enlarged-label navigation cases.
- The final integration base `f57531dc` adds only a Calendar icon-size change;
  its bottom-navigation suite was rerun and all 25 selected tests passed.
- The final candidate built a Staging debug APK with
  `--target lib/main.dart --dart-define-from-file=staging.local.example.json`.
  Android package inspection confirmed `com.postdee.postdee_mobile.staging`;
  this uses the tracked Staging API/Firebase configuration with billing disabled.
- The source diff is limited to this feature and its tests/documentation;
  the earlier dirty checkout remains untouched.
