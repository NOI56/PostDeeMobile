# Post/caption add-on, 2026-10-21

Historical implementation record: the monthly-expiry/Android-only policy below
was superseded by the user's explicit approval of non-expiring purchased
credits, monthly quota first, on Android and iPhone. See
[the replacement design and verification record](2026-10-21-nonexpiring-post-caption-credits.md).
This original implementation was not merged, deployed or sold; its verification
results describe APK12032 and do not verify the replacement design.

Status: implementation and local verification complete; real store acceptance
and rollout remain pending. No live product, payment, environment, hosted
database, deployment or installed app has been changed. APK12032 is built and
verified, but is not installed. No merge, push or deploy was performed.

## Baseline and requested behavior

- Freshly fetched `origin/main` and clean feature baseline:
  `f1ce4a7a3351c69545662df3ce84ab28173e3659`.
- Work branch: `codex/post-caption-addon-49`; existing unrelated D: checkout and
  generated Windows files in the integration worktree are preserved.
- User confirmed Starter/Pro members only and expiry with monthly quotas.
  Existing quotas reset on the UTC calendar month, not billing renewal.
- Target price 49 THB once; one purchase adds 100 post units and 50 real-clip AI
  caption generations. A two-destination post consumes two units. Repeat
  purchases in the same month accumulate. No carryover, plan upgrade or new
  scheduling/analytics/AI-frame rights.
- Initial checkout is Android only. During verification, Apple's
  [In-App Purchase rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)
  were checked and found to prohibit expiry of purchased credits. The user was
  informed that the chosen monthly expiry therefore keeps iPhone checkout and
  App Store purchase grants disabled. Existing iOS subscriptions are unchanged;
  do not create an App Store consumable SKU for this expiring-credit offer.

## Safety and compatibility

- Existing RevenueCat subscription, owner/session, post idempotency and exact
  caption reservation-release behavior must remain working.
- The app reads the actual localized store price, queries a non-subscription
  product, and requires backend readiness before opening checkout.
- The backend owns grant quantities and verifies transactions. Global
  store/environment/transaction identity prevents duplicate fulfillment.
- Refunds revoke the grant, including when refund delivery precedes purchase.
  Usage is retained; subsequent quota checks use the reduced limit.
- Server and mobile account fences prevent crediting another account. Deleted
  owners must not be recreated by late webhooks. Ledger replay protection must
  survive account deletion without retaining the deleted user's profile data.
- Subscription Restore must not mint consumable credits. Interrupted checkout
  and confirmation must never be presented as a confirmed grant or prompt a
  second purchase while the original transaction is unresolved.

## Rollout order

1. Review and apply the additive purchase-ledger migration, then deploy the API
   with `BILLING_ADDONS_ENABLED=false`.
2. Configure the matching Android consumable SKU in Google Play and
   RevenueCat, target Thai price 49 THB; do not attach it to Starter/Pro
   subscription entitlements. Use separate sandbox/production environments.
   `REVENUECAT_ADDON_PRODUCT_ID` defaults to `postdee_post100_caption50` and
   must differ from all subscription SKUs; `REVENUECAT_ADDON_ENVIRONMENT`
   defaults to `PRODUCTION` (set `SANDBOX` only in an isolated test deployment).
3. Configure RevenueCat platform server notifications for consumable refunds.
4. Verify sandbox purchase, late confirmation, webhook replay, refund and month
   reset against the exact API/mobile build; never use a real payment to smoke
   test without explicit authorization.
5. Enable the server gate only for the verified environment, then distribute
   Mobile. A disabled or unsupported API must block checkout.

RevenueCat API v1 can omit a canonical store transaction ID for consumables.
The backend never substitutes RevenueCat's internal transaction ID. Such a
purchase remains pending until its authenticated webhook records the canonical
transaction; confirmation then reads that ledger entry without granting again.
REST first-grants also require the original RevenueCat owner to match the
authenticated UID; aliased customers wait for the authoritative webhook.
Reference: [RevenueCat non-subscription purchases](https://www.revenuecat.com/docs/platform-resources/non-subscriptions)
and [Customer Info model](https://www.revenuecat.com/docs/api-v1/customer-info-model).

## Verification record

- Tests-first coverage includes ledger duplicate/refund/owner checks, monthly
  post/caption quota exhaustion, idempotent post replay, exact caption release
  and account cleanup. The account cleanup regression failed with retained
  credits before the cleanup dependency was wired, then all 22 account tests
  passed.
- Final Android-only backend suite on Node 22.23.3: **2,368 passed, 18 skipped**
  across 143 passed and two skipped files (75.39 seconds). The 18 existing optional admin
  database cases were not enabled; both new add-on database suites were enabled.
- TypeScript source/test checking, production API build, Prisma schema
  validation and seed/config TypeScript checks all passed.
- Dedicated local PostgreSQL 18 fixture: all 21 migrations applied, including
  `20261021110000_monthly_post_caption_addon`. Real database tests cover
  simultaneous transaction claims, refund-before-purchase, deletion fencing,
  retained null-owner replay protection, concurrent final post/caption units,
  post replay and exact caption release. Quota tests passed in UTC and
  Asia/Bangkok.
- After the full suite, User, Post, RealClipCaptionUsage, MonthlyAddonPurchase
  and ManagedUploadOwner each had zero fixture rows. Only the 21 completed
  migration records remain. The new fixture cluster was stopped and its
  loopback port 55441 is closed. No hosted database was read or changed.
- API log: `D:/PostDeeMobile/artifacts/post-caption-addon-20261021/api-full-android-final.log`.
  Quota database logs: `quota-db-utc.log`, `quota-db-bangkok.log` in the same
  evidence directory. Dependencies were installed from the unchanged current
  `main` lockfile into an isolated D: directory; other worktree dependencies
  and the installed Android app were preserved.
- Final Mobile suite: **2,571 passed, six optional preview skips** (192.3
  seconds). Explicitly enabling the add-on preview then passed all eight
  paywall/add-on cases, including the preview. Final Flutter analysis reports
  **No issues** (12.2 seconds; wrapper 13.9 seconds).
- Final preview uses real Flutter widgets and local fake store data at 376px,
  with text scale 1 and 1.35. The complete add-on card, Thai copy, 49 THB button
  and local expiry date fit with no overflow. The final large-text PNG hash is
  identical to the image already visually inspected. The standard-size fixture
  has an unrelated old button using the test fallback font; that fixture does
  not establish a native-app font defect.
- Mobile tests cover exact receipt confirmation, failed/pending purchases,
  timeout/late SDK results, no second checkout, typed cancellation and refunds,
  API/account-scoped durable intent/baseline/receipt recovery after service
  recreation, corrupt state blocking, account changes and account deletion.
  The deletion regression retains the replacement user's pending purchase when
  the account changes during earlier local cleanup. SDK calls stay serialized
  under the existing global RevenueCat identity queue. Apple add-on gates are
  checked before any SDK purchase; existing iOS subscription tests still pass.
- The pending baseline/receipt is local device data, not a transferable wallet.
  Recovery accepts only a unique new transaction of the original SKU and owner
  before server confirmation. A missing baseline or multiple possible new
  transactions remains pending and requires investigation; it never guesses
  a purchase or opens another checkout. No authentication token is stored.
- Staging x86_64 debug APK12032 built successfully (Gradle 154.6 seconds;
  wrapper 159.1 seconds). All 660 source/snapshot hashes matched for final
  full tests, preview, analysis and build. Signature, 16KiB alignment, package
  `com.postdee.postdee_mobile.staging`, version `0.1.0-staging`, existing
  Firebase project/app/client, Staging API and existing public Test Store SDK
  key were verified without printing the key. Prior consent/defaults, Home
  sending feedback, profile dots and publish progress remain in the kernel.
- APK: `D:/PostDeeMobile/artifacts/post-caption-addon-20261021/app-staging-12032-x86_64-debug.apk`,
  197,096,726 bytes, SHA256
  `4ae99ae976be0f5a35c1e48d3f39c1bba5546f44d82d925306d0449e167a546f`.
  Signature SHA256 remains
  `014e1d98cb4c6161015f33be988d9a9bc43575c3adcf9226f9f8ee6948380cdb`.
- Preview: `D:/PostDeeMobile/artifacts/post-caption-addon-20261021/preview-final/addon-card-large-text.png`.
  Verification receipts and logs are in the parent evidence folder. Only this
  verification record was updated after Mobile checks. A later API `.env.example`
  edit corrects the word "signed" to "authenticated" in a comment; API runtime,
  tests, schema and migration inputs did not change after the final API suite.
- No store product setup, live purchase/refund, deployed API migration, enabled
  gate, native payment attempt, ARM/iOS build or physical-device acceptance is
  claimed from these local checks. The installed emulator app is preserved.

## Changed areas

- Mobile: `paywall_screen.dart`, `store_addon_service.dart`,
  `addon_pending_store.dart`, shared `store_subscription_service.dart`,
  `app_config.dart`, `postdee_api_client.dart`, Home/Profile quota displays,
  Uploader quota guidance and Shell account cleanup, with regression tests.
- API: `addonRoutes.ts`, `monthlyAddonStore.ts`,
  `prismaMonthlyAddonRepository.ts`, `revenueCatAddonPurchaseClient.ts`,
  `revenueCatWebhookRoutes.ts`, billing snapshots, post/caption stores,
  repositories, routes and factories, account cleanup, app/config wiring,
  schema and additive migration, with memory/route/real-database tests.
- Documentation: README, API, ARCHITECTURE, ROADMAP, mobile README, the package
  source-of-truth plan and this record. No dependency, existing tier price,
  social-publishing destination or unrelated feature was removed.
- Three generated Windows Flutter files have line-ending-only changes from
  tool setup; they are unrelated and are excluded from the feature commit.
