# AI caption credits per selected channel — 2026-10-25

## Request and baseline

The user wants selecting all four AI caption channels to cost four credits.
Keep the compact selector and quota strip, showing the cost only on the
existing `สร้างแคปชั่น · N เครดิต` action. Implement from verified fresh
`origin/main` `b7fb8533` on `codex/caption-credit-per-channel` in the clean
`caption-quota-main` worktree; preserve the unrelated dirty original checkout.

## Contract and accounting

- Advanced requests cost one credit for each distinct supported `platforms`
  value: 1/2/3/4 channels cost 1/2/3/4 credits. Empty/duplicate/unsupported
  supplied lists remain invalid. Shared-caption requests without `platforms`
  and the legacy keyword endpoint cost one credit.
- The server derives the price. New Mobile always sends `expectedCredits`
  equal to the displayed cost. A multi-channel request without matching
  confirmation returns `409 AI_CAPTION_COST_CONFIRMATION_REQUIRED` with
  `quota.requiredCredits` and `quota.chargedCredits: 0` before reservation/provider
  work. Legacy shared/one-channel requests may omit it;
  older multi-channel apps must update instead of silently spending more.
- Atomically reserve the full cost, monthly credits first and then retained
  nonexpiring add-on credits. Insufficient total balance returns `429
  AI_CAPTION_QUOTA_REACHED` with actual remaining quota and `quota.requiredCredits`,
  without partial debit or a provider call. Keep one usage row per credit and
  protect the same balance from concurrent overspend.
- A set still uses one provider generation operation with its existing retry
  policy. Failed/fallback/incomplete output releases that request's entire
  batch atomically without removing another request's credits. Preserve failed
  refund visibility. `quota.requestedCredits` records cost;
  `quota.chargedCredits` is the full cost or zero after full release, alongside
  the existing `charged` boolean. Successful generation is charged even if the
  preview is dismissed or a stale-result guard prevents applying its text.
- Mobile compares the cost to combined monthly/add-on availability, blocks
  known insufficient requests before upload and lets users deselect channels.
  Keep unavailable reads distinct from zero, and refresh committed quota after
  failure/refund using the existing owner/request guards.

Starter/Pro monthly allowances remain 50/120. No plan price, add-on pack,
credit lifetime, provider, environment flag, schema or migration change.
Preserve shared/manual captions, writing style, selected-only preview/apply/
undo, draft targets, owner/session/clip guards, upload cleanup and publishing.

## Verification and release boundary

Test costs 1–4, shared/legacy compatibility and confirmation failures; exact
success/refund metadata; monthly/add-on mixed allocation; insufficient positive
balances and concurrent reservation; full-batch refund and failure visibility;
and Mobile cost/balance/preview/session behavior. Run required complete API and
Mobile suites, static/build/schema checks and exact-environment smoke, then
review the baseline diff. Record actual results separately; this plan is not
test or deployment evidence.

Coordinate API and new Mobile delivery. Backend first safely rejects older
multi-channel requests with an update/cost-confirmation error; new Mobile on
the older API can quote more credits than its one-credit meter charges until
the API is updated. Do not describe this policy as deployed based on the prior
quota-strip Staging release. No push or deployment belongs to this document
change without the relevant user authorization.

## Verified result — 2026-10-25

Implementation completed on `codex/caption-credit-per-channel` from `b7fb8533`.
A final fetch confirmed `origin/main` still equals that baseline. The unrelated
dirty `D:\PostDeeMobile` checkout was preserved; the implementation is in
`C:\Users\stopp\.codex\worktrees\caption-quota-main\PostDeeMobile`.

Changed API files: `captionRoutes.ts`, `captionUsageStore.ts`,
`prismaRealClipCaptionUsageRepository.ts`, their existing affected tests,
`platformCaptionGeneration.test.ts`, and new `captionPerPlatformCredits.test.ts`,
`captionUsageBatch.test.ts`, `captionUsageBatch.database.test.ts`.
Mobile changes are the request DTO, uploader cost/affordability guard, quota
strip credit units, and matching AI credit wording in paywall/home/profile,
with their contract, quota, platform, visual and screen regressions. The four
main docs and six relevant older plans are synchronized alongside this plan.

- Full API suite on Node **22.23.3**: **2,747 passed, 38 skipped**. Seven skips
  are the new explicitly opted-in local database suite; the other 31 were
  pre-existing optional tests. The final caption-focused run passed **227**
  tests. New HTTP cost tests passed **19/19**.
- Disposable PostgreSQL **18** with all **23 existing migrations**: **7/7**
  passed, including genuine Prisma `P2034` conflict/retry, mixed monthly/bank
  allocation, insert/delete rollback, exact refund and account-deletion guards.
  The generated Prisma client also typechecks directly against the repository.
- Full Flutter suite: **2,941 passed, 6 skipped**. Full `flutter analyze
  --no-pub` reports no issues. Real-font light and dark/narrow/large-text visual
  checks passed **2/2**; current screenshots were saved under
  `D:\PostDeeMobile\output\playwright\caption-credit-per-channel`.
- API typecheck/build, Prisma schema validation and helper-file TypeScript
  checks passed. `git diff --check` passed; no schema/migration, provider,
  environment flag, dependency, publishing route or Android configuration
  change and no deleted baseline files.
- Exact-source Staging debug APK build passed. APK metadata confirms
  `com.postdee.postdee_mobile.staging`, label `PostDee Staging`, version
  `0.1.0-staging` (code 1). Build used `staging.local.example.json`: Staging API
  URL, Firebase auth enabled, mock auth disabled, RevenueCat billing disabled;
  debug Firebase config maps that package to
  `project-798caf7e-85b8-45e3-af7`. The APK was **not installed** and no
  authenticated hosted-provider/account billing flow was exercised.

The disposable database/schema were removed, fixture rows verified absent,
and its server stopped with no listener remaining. Automatic approval review
blocked recursive deletion of its inactive TEMP cluster directory with reason
`blocked by policy`; no bypass was attempted. Only stopped temporary files
remain at
`C:\Users\stopp\AppData\Local\Temp\postdee-caption-batch-0f2b1c473ef94875b754f11bcf586984`.

The verification above was completed before main delivery. On 2026-10-25 the
user authorized `main/push` for this change and the post-quota strip. Main
delivery does not deploy Render or install the APK. The previous quota-strip
Staging deploy does not contain this pricing change. Release API and updated
Mobile together using the compatibility order above; do not claim live
per-channel charging until that release and authenticated verification.
