# Shop-link limits by plan — 2026-10-26

Status: source pushed to `main`; API deployed to Staging. Mobile build 12060
is installed on the test Emulator, with no app-store or Production release.
The receipts below distinguish local checks from post-deploy smoke checks.
Work starts from verified `origin/main`
`c56b4431bd0b8e0aba50777704ca5f198d1b4a48` on
`codex/shop-link-plan-limits`. Preserve the recent account-deletion acceptance
and restored read-only verifier-role records on that baseline.

## Package rules

| Effective plan | Price | Shop pages | Link limit |
| --- | --- | --- | ---: |
| Basic/free | Free | 1 | 2 |
| Starter | 199 THB/month | 1 | 7 |
| Pro | 299 THB/month | 1 | 20 |

Use the existing effective-plan resolver, including active valid admin trials
and their expiry/revocation rules. Expired paid access falls back to Basic
unless another valid entitlement applies. Do not introduce a production
client/header override, new trial path or purchase/provider integration.
Prices, monthly social-post/AI-caption quotas and customization rights are
unchanged. Twenty template choices in the minimal decoration category are
independent of the number of stored/published shop links.

## Existing content and counting

- A new draft link counts against **all stored links**, including disabled
  links. Add only when the total is below the current 2/7/20 limit; confirming
  an addition must recheck the latest entitlement and current stored count.
- Keep the existing 20-link hard storage/input ceiling for compatibility.
  Do not delete or truncate persisted drafts when a plan limit is lower.
- Legacy over-limit drafts remain available for viewing, editing, reordering,
  deleting and disabling existing links. An enabled subset within the current
  plan limit can still be published. Additions remain blocked until the total
  stored count is below that limit, even if fewer links are enabled.
- A new publish/update counts only the enabled links sent in the request,
  retaining their selected order. All existing structural validation still
  applies, including at least one enabled link and the maximum input of 20.
- A previously published over-limit page remains publicly unchanged after
  downgrade or expiry. The owner's **next explicit publish/update** must use a
  subset within the current limit. Do not automatically hide the page, trim
  links or rewrite its saved appearance, slug or media.
- Example: a former Pro owner now on Basic keeps a published 12-link page and
  its 12-link draft. The owner can edit/disable those links and next publish
  two enabled links while retaining all 12 in the local draft. Adding a new
  draft link remains blocked until fewer than two stored links remain.

## API boundary

- Add numeric `subscription.maxProfileLinks` to `GET /billing/subscription`:
  2, 7 or 20 from the current authenticated owner's effective plan.
- Enforce the current effective limit independently in
  `POST /link-in-bio/publish`, including updates to an existing public page.
  Return HTTP 403 with standard error code
  `LINK_IN_BIO_LINK_LIMIT_EXCEEDED` before changing the published snapshot when
  the valid enabled payload exceeds the plan limit. Include top-level `plan`
  (`BASIC|STARTER|PRO`), numeric `maxProfileLinks` and numeric `requestedLinks`
  for the enabled request count in the error envelope.
- If the server cannot resolve the owner's current entitlement, return HTTP
  503 `LINK_IN_BIO_ENTITLEMENTS_UNAVAILABLE` without changing the public
  snapshot. Unavailable entitlement does not grant a permissive default.
- Retain the 20-link structural input cap and existing owner/image/slug,
  appearance normalization, publication uncertainty and cleanup boundaries.
  A request outside structural validation still uses its existing validation
  error; the entitlement field is not a client-granted permission.
- `GET` of an existing page and explicit unpublish remain available. A
  downgrade does not mutate the public read or stored profile automatically.

## Mobile boundary

- Fetch fresh session-bound subscription data before opening Add, recheck
  before accepting the completed new-link form, and refresh before publishing.
  Recheck counts at confirmation rather than relying on the state when the
  editor opened. Existing session/owner guards reject stale async results.
- If entitlement cannot be verified, fail closed for new additions and
  publishing, show a retry path, and keep existing local drafts editable.
  Do not substitute a cached paid plan, a missing snapshot or an unknown limit
  for permission. Existing local edits and content remain intact.
- New Mobile reads `maxProfileLinks`. When a successful fresh older API
  response omits that additive field, map the effective plan to 2/7/20.
  This fallback does not replace the server's authoritative publish check.
- Preserve enabled-link filtering, disabled links, stable IDs/order, appearance
  and media. Show consistent Basic/Starter/Pro copy and the current link limit.
  Do not describe twenty links as a benefit of every plan.

## Compatibility and deployment order

1. Deliver the API's additive subscription field and publish gate first.
   Existing Mobile ignores the new field and can safely receive the 403;
   rejected updates must leave the previous public snapshot intact.
2. Distribute Mobile with fresh entitlement checks and the missing-field
   compatibility mapping. API deployment alone does not update installed app
   code, and older API deployments do not supply the new authoritative gate.
3. Verify the exact delivered API/app and account/entitlement state before
   claiming acceptance. No schema migration, new dependency, provider,
   appearance version, shared-catalog change or new configuration flag is
   required by this rule change.

## Acceptance checklist

- API regression tests for Basic 2/3, Starter 7/8 and Pro 20/21 boundaries;
  distinguish the plan error from the existing structural maximum.
- Effective active trials, expired paid access and production header-override
  rejection use the existing resolver semantics.
- A rejected update does not mutate an existing published over-limit page;
  permitted enabled subsets publish without trimming the local disabled links.
- The 403 includes effective-plan/count metadata, and unavailable server-side
  entitlement produces the 503 code without changing an existing page.
- Mobile opening Add, confirming after downgrade and publishing all refresh
  entitlement; failed reads block only the new gated operation.
- Existing over-limit drafts retain text, IDs, order, styles, media and disabled
  entries through edit/delete/disable/save/reload, with additions blocked until
  the stored count is below the current limit.
- Older subscription responses without the new field, stale account responses,
  current-plan copy, targeted/full tests, analysis/build and relevant API/schema
  checks. Record real commands/results separately when run; this checklist is
  not a verification receipt.

## Local verification receipt — 2026-10-26

- Final remote refresh: `origin/main` remains
  `c56b4431bd0b8e0aba50777704ca5f198d1b4a48`; branch HEAD is at that base,
  ahead/behind 0/0, with the intended implementation as local changes. No
  unrelated source changes, deleted files, schema/dependency changes or feature
  flag changes were included. Existing account-deletion records remain intact.
- API on Node **22.23.3**: full `npm test -- --maxWorkers=2
  --no-file-parallelism` passed **2,858 tests**, with **54 skipped** (178 passed
  files / 9 skipped files). `npm run typecheck`, `npm run build`,
  `npm run prisma:validate` and the Prisma seed/config helper `tsc` check passed.
  Schema validation used a local placeholder URL and did not connect to a real
  database. Test-first coverage includes effective trials/expiry/revocation,
  trusted owner scope, resolver failure, rejected-update preservation and
  2/7/20 boundaries; Pro's 21st input remains a structural 400.
- Mobile full `flutter test --no-pub --reporter expanded`: **3,147 passed /
  6 skipped**. A separately added race-test file then passed **4/4** covering
  a wrong subscription owner, synchronous failure and retry, concurrent enable
  with one slot left, and duplicate Add/Save taps. This later file was not part
  of the earlier full-suite discovery. Targeted screen coverage also confirms
  downgrade during form entry retains typed text, enabled subsets retain all
  stored links, and the known pre-write entitlement 503 allows retry without
  falsely reporting an uncertain publication.
- Final `flutter analyze --no-pub` and Staging Android x64 debug build passed.
  Build command: `tool/postdee-staging.ps1 -Command build-apk --no-pub
  --target-platform android-x64 --build-number 12060`.
- Environment: package `com.postdee.postdee_mobile.staging`, version
  `0.1.0-staging` / **12060**, API
  `https://postdee-api-staging.onrender.com`, Firebase project
  `project-798caf7e-85b8-45e3-af7`, Firebase auth enabled and local mock auth
  disabled. The helper validated the existing ignored RevenueCat Test Store
  overlay; no SDK key or credential was added to Git.
- APK SHA-256:
  `1FF955F2E3B43550776C837F49208EA8B214E28A46264147B55AAFAAABA0BD40`.
  Existing debug signer SHA-256:
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
  The safe APK update preserved Emulator package UID **10197** and internal
  volume while updating 12059 to 12060; there was no uninstall or data clear.
- Native Emulator smoke: the existing signed-in Free account, saved clip draft,
  connected-channel count and published shop remained available. Shop manager
  showed **2/2** links; Add displayed the two-link limit message and did not
  open a new-link form. No public page update, link deletion, purchase or
  account/entitlement change was performed during this smoke test.
- `git diff --check` passed. Local logs are in the user's Temp directory under
  `postdee-shop-link-plan-limits-api-20261026-*` and
  `postdee-shop-link-plan-limits-mobile-*-20261026.log`.

Pre-release status at local verification: no push, merge or API deployment had
yet been performed. The Emulator used the existing Staging API, so this is Mobile
compatibility/smoke evidence, not evidence that the new server gate is live.
Deploy API first, then release Mobile, and verify the delivered versions.
No database migration is required. Optional real-database/provider tests and
real paid-account purchase/downgrade acceptance remain outside these local
results; production was not changed.

## Staging deployment receipt — 2026-10-26

- The user authorized pushing `main` and deploying the API. Fresh remote check
  still matched baseline `c56b4431`; a separate release review found no
  unrelated changes, deleted files, schema/dependency/configuration changes or
  feature-flag changes. The source commit is
  `f4f39922a52dd8681f4582d4056da8edb062c902`, pushed to `origin/main` by a normal
  fast-forward push. All full-test/build evidence above applies to this source.
- Render workspace `tea-d45nsamuk2gs73cmhol0`, existing service
  `postdee-api-staging` / `srv-d9bb72ojs32c739osa5g`, branch `main`, API
  `https://postdee-api-staging.onrender.com`. Auto-deploy was and remains off;
  no environment variables, infrastructure or Production service were changed.
- Manual deploy `dep-dbfh91ijnfac73ccsa8g` resolved the exact source commit
  above and became **live at 15:52:45 Asia/Bangkok** (08:52:45 UTC).
  The previous live deploy was `dep-dbfg74o473hc73d2mjsg` at `d1138796`.
- Startup reported **25 migrations found / no pending migrations**, API
  listening on port 10000 and the existing PostPeer empty-backlog guard
  enforced. This feature introduced no new migration.
- Post-live checks: `/health` returned **200** with `status: ok`; the existing
  `/p/postdee-demo-20261005` returned **200**, retained shop `noikub` and its two
  published links. Repeated page responses differed only in the expected
  per-request CSP style nonce. Normalized-content SHA-256 was stable at
  `E1BF7EDDD330C7902646AC195FAC70EDC7EE0111D6F75F2CADA7D8FA1DB8D0D5`.
  This is a repeated post-live check, not a pre/post byte-equality claim.
- Unauthenticated `/billing/subscription` returned **401** as expected, and a
  bounded error-level runtime-log query after go-live returned no entries.
  No publish/update, purchase, account/trial change or content deletion was
  performed by these post-deploy checks.
- Live authenticated `subscription.maxProfileLinks` and paid-account downgrade
  were not directly exercised: no ready approved auth-token smoke fixture was
  available. The 2/7/20 gate is covered by local API/Mobile regressions and the
  exact deployed commit; the earlier native Free 2/2 smoke can also use the
  Mobile fallback, so it is not proof of the additive live API response.
- The follow-up documentation commit records this receipt only and uses
  `[skip render]`; it does not require another API deployment. Mobile store
  distribution and Production acceptance remain separate release steps.
