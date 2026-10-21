# Non-expiring purchased post/caption credits, 2026-10-21

Status: implementation and local verification complete. Native store purchase,
refund and missing-canonical-ID recovery acceptance remain release gates; new
sales stay default-off. No hosted database, store product, payment, deployment
or installed app has been changed. APK12033 is built and inspected, not installed.
No main merge, push or deploy was performed.

## Approved behavior and baseline

- User explicitly replaced monthly expiry with non-expiring purchased credits,
  consuming included monthly quota first, using the same rules on Android and
  iPhone. Price/quantities remain target 49 THB once for 100 platform post units
  and 50 real-clip AI captions; repeat purchases accumulate.
- Only effective Starter/Pro can buy/use purchased credits. Basic retains the
  balance until paid membership resumes. Existing tier features, included
  monthly limits, subscription pricing and monthly reset dates are unchanged.
- Fresh `origin/main`: `f1ce4a7a3351c69545662df3ce84ab28173e3659`.
  Feature starts from the unshipped monthly prototype
  `8db1b43ad967686dfa8e3c29432fa12ebc13a1f6`, which contains that main baseline.
  Branch: `codex/nonexpiring-post-caption-credits`. Preserve unrelated D: work
  and the three existing EOL-only Windows generated-file changes.
- No live add-on migration/configuration or purchases were performed for the
  monthly prototype; its server gate remains default-off. If another target
  environment has historical add-on usage, do not infer allocations from
  zero defaults: reconcile that history explicitly before migration.

## Accounting and compatibility

- Preserve the canonical transaction ledger and sticky refund/owner tombstones.
  Its valid grant total is now lifetime, without a purchase-month filter.
- Persist `Post.addonPostUnits` and `RealClipCaptionUsage.usesAddonCredit` with
  zero/false defaults. Included monthly usage excludes purchased allocations.
  Purchased balance equals lifetime valid grants minus lifetime purchased usage.
  Multi-platform posts may split between both sources.
- Quota checks and allocation writes remain atomic under the active-owner
  Serializable transaction fence. Memory adapters recheck idempotency after
  asynchronous grant reads and do not await between final quota check/write.
- Exact post rollback or caption release restores the original source even
  across monthly resets. A plan change never retroactively reallocates usage.
  A refund revokes its grant while preserving any spent credit deficit; only
  displayed availability is clamped to zero. Included quota still works during
  a purchased-credit deficit.
- `BILLING_ADDONS_ENABLED` controls new purchases only. Existing balances remain
  visible and usable by effective paid members when new sales are off.
- Catalog/confirmation identify `policyVersion: 2`, `creditsExpire: false`,
  `expiresAt: null`. The app rejects older expiring policies before any SDK
  payment; incompatible confirmation retains the pending receipt for retry.
- Keep owner-bound durable purchase intent, baseline/receipt recovery, canonical
  transaction confirmation, shared SDK queue and account-deletion fences.
  Subscription Restore never grants consumable credits or substitutes a paid
  entitlement for proof of the exact add-on transaction.
- Independent SDK review found that immediate purchase results and recovered
  Customer Info history can use store IDs and RevenueCat internal IDs
  respectively. Persist explicit `STORE`/`REVENUECAT` receipt namespaces and
  resolve only that namespace through authenticated provider data. An exact
  canonical mapping remains the ledger identity. Never mint a grant under a
  RevenueCat internal ID or infer fulfillment from timestamps or balances.
  A proposed unique-metadata fallback was rejected during review: two different
  purchases can share a timestamp while REST/webhook histories arrive in a
  different order. Missing canonical mapping stays pending, even when a webhook
  has independently granted credits. Exact mapped refunds stay revoked. The
  response echoes the original selector.

## Rollout order and remaining external acceptance

1. Confirm no historical monthly add-on usage; otherwise reconcile allocations.
2. Apply both additive migrations (original ledger, then usage allocation) and
   deploy the version-2 API with new sales disabled.
3. Configure matching repeatable consumables in Google Play, App Store and
   RevenueCat. Use target Thai price 49 THB and keep the SKU separate from
   Starter/Pro entitlements. Keep sandbox and production environments separate.
4. Verify native Android/iPhone purchase, restart recovery, late confirmation,
   webhook replay and refund on the exact source/environment. In particular,
   prove authoritative internal-history-ID to canonical-store-ID recovery;
   RevenueCat v1 may omit that mapping and the safe result is pending. Do not
   enable sales while that native recovery case is unresolved. Test month reset,
   downgrade/renewal and credit-source restoration without a real charge.
5. Enable new sales only for the verified environment and distribute the
   compatible app. No main merge/push/deploy or installation is authorized by
   this implementation request alone.

The non-expiring design aligns with Apple's purchased-credit expiry clause;
it does not claim overall App Review approval. References:
[Apple In-App Purchase rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase),
[RevenueCat non-subscriptions](https://www.revenuecat.com/docs/platform-resources/non-subscriptions),
[RevenueCat Customer Info](https://www.revenuecat.com/docs/api-v1/customer-info-model).
The SDK history-ID distinction is also visible in RevenueCat's
[Android transaction parser](https://github.com/RevenueCat/purchases-android/blob/main/purchases/src/main/kotlin/com/revenuecat/purchases/models/Transaction.kt)
and the checked local `purchases_flutter` 10.3.0 `StoreTransaction` model.

## Changed surfaces

- API: purchase ledger/repository, catalog/confirmation and webhook handlers;
  post/caption stores, Prisma repositories, routes and subscription snapshot;
  app factory wiring and strict repository test fixtures.
- Database: additive `20261021120000_nonexpiring_addon_usage`, preserving the
  original ledger migration, with bounded per-post purchased allocation and
  caption credit-source columns plus owner/allocation indexes.
- Mobile: API DTOs, consumable service/gateway, paywall and Home/Profile credit
  summaries; existing durable pending intent/receipt and session fences stay.
- Documentation: README, ROADMAP, API, ARCHITECTURE, Mobile README, subscription
  package plan and superseded prototype record. Regression tests cover both
  runtime adapters and mobile purchase/recovery/display behavior.

## Verification record

- Tests-first runs reproduced the old expiring contract, allocation/owner
  fencing gaps, old-policy checkout rejection and receipt-namespace mismatch
  before the corresponding fixes. A real concurrent grant run exposed `P2034`
  contention. The ledger now retries only `P2002`/`P2034` at a bounded outer
  boundary with 20/40 ms pauses; the shared owner helper is unchanged.
  Deterministic exhaustion tests retain a hard retry limit and create no grant
  on persistent failure. PostgreSQL contenders are fully drained even when a
  regression fails an assertion. Five focused 13-test concurrency/ledger runs
  passed before the final full rerun; persistent contention still requires
  retrying the same receipt, never starting another purchase.
- Full API suite, Node 22.23.3: **2,388 passed, 18 optional admin database cases
  skipped**, 143 passing suites and 2 optional suites skipped, 90.91 seconds.
  Both add-on PostgreSQL suites ran against the owned loopback fixture, covering
  7 real database cases, including cross-month allocation, final-unit races,
  mixed platform allocation, refunds/debt, replay, exact release and owner fences.
- API TypeScript, production build, Prisma schema validation, seed/config helper
  typecheck and migration status all passed. All 22 migrations are applied in
  the disposable local database. User, Post, RealClipCaptionUsage,
  MonthlyAddonPurchase and ManagedUploadOwner fixture counts are zero afterward;
  the owned PostgreSQL listener was stopped. No hosted database was used.
- Full Mobile suite, Flutter 3.44.1 / Dart 3.12.1: **2,586 passed, 6 optional
  preview cases skipped**, 196.9 seconds. Final `flutter analyze` reports no
  issues (8.6 seconds; wrapper 10.4 seconds). Coverage includes native iOS
  gateway eligibility, retained Basic balances, old policy rejection before
  payment, changed pack terms after readiness, durable pending namespaces,
  process restart with distinct RC/store IDs and no second SDK purchase.
- The explicit final paywall preview suite passed **9 tests**, wrapper 17.7
  seconds. Real-font PNGs were inspected at 376 px, text scales 1 and 1.35.
  The new add-on card has no overflow and states non-expiry, monthly quota
  first, actual localized checkout price and retained balances after downgrade.
  The normal fixture's unrelated subscription button retains its existing
  test-font rendering artifact; this is not a native screenshot.
- Exact source Android x86_64 debug **APK12033** built successfully: Gradle 84.5
  seconds, wrapper 88.6 seconds. Inspected package
  `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`, known debug
  signer, 16 KiB alignment, staging API and expected Firebase app/client.
  Compiled kernel checks include non-expiring credit handling, availability,
  durable pending and existing consent/defaults/Home feedback/profile dot/
  publishing-progress capabilities. APK is **197,099,326 bytes**, SHA256
  `4e0549816a1e2bc3e6496d2e384f4a84890b108bc97838c8941bed60cf2940fa`.
- All **450 API/shared** and **661 Mobile/shared/document** candidate hashes
  matched their verified sources/snapshot during checks and APK inspection.
  Only this verification record and the API namespace documentation were
  updated afterward; runtime/test/schema files must remain byte-identical.
  `git diff --check` passed; unrelated generated Windows EOL changes are excluded.

Evidence and APK: `D:\PostDeeMobile\artifacts\nonexpiring-post-caption-20261021`.
The original APK12032 and pre-recovery/failed-run evidence are preserved.

## Remaining release limits

- No signed iOS build, physical-device/store checkout, refund notification or
  live provider recovery was performed. Unit/widget/fixture results do not
  prove native store acceptance or App Review approval.
- In particular, SDK history can contain an RC internal ID while RevenueCat v1
  omits its canonical store ID. The implementation correctly keeps that exact
  receipt pending, without duplicate credit or another payment. This case is
  unresolved for release until authoritative mapping is proven in the target
  store/environment; do not enable new sales on the strength of these mocks.
- Deploy the database migrations and API first, then the compatible app. Store
  consumables, pricing, sandbox/production routing and native recovery/refund
  acceptance still need configuration/verification. No real payment was made.
