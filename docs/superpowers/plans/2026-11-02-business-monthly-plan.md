# Additional monthly main subscription

## Integration authorization — 2026-11-03

The owner approved merging the pending UX and Business work into `main`, pushing
and deploying Staging in this chat. The combined candidate starts from verified
remote main `6c7ff068eeabc8e21a7e159a89c71a30a20c9fca`, preserving catalog 4,
twenty Cartoon designs and the second set of 3D templates. The earlier exclusions
below describe the original isolated implementation, before this approval.

Staging delivery includes the additive grant-snapshot migration before the
Business enum migration. New Business and multi-size add-on sales remain off;
Store setup, native billing acceptance, offer activation and Business trials are
not part of this deployment. Existing installed clients keep their legacy plan,
quota and receipt paths. The old Gemini Files transport experiment is excluded
because it needs cancellation and grounding tests against the current pipeline.

The combined candidate passed local API/Mobile suites, affected PostgreSQL
tests and exact-source CI. Staging is Live at `bd096ea3` after the Business
migration (30 total); matching APK 12096 was installed in place on Pixel_8.
Native startup reached the Staging store editor after a slow emulator startup.
No environment values were changed and actual Dashboard sales-switch values
could not be read. Store setup, native billing and sales activation remain
pending. See `docs/STAGING.md` for the deployment and verification record.

## Authorization and isolation

The owner confirmed a main subscription at THB 399/month with 400 post units,
50 links on the profile Link-in-Bio page, and 220 AI caption credits. **Business**
and `BUSINESS` are provisional labels chosen for implementation, not approved
branding. The dedicated local `codex/business-monthly-plan` worktree starts at
verified merged main `5fa8965075899e84ef2b063833e9ae038bd570d9`.
Remote submission, merge, hosted deployment/migration, Store setup, purchases
and activation are excluded. The separate Staging approval bundle remains
pinned to that baseline and must not silently include this new plan.

## Entitlements and preserved rules

| Plan | Post units / UTC month | AI credits / UTC month | Profile link capacity |
| --- | ---: | ---: | ---: |
| Basic | 3 after existing verification | 0 | 2 |
| Starter | 120 | 50 | 7 |
| Pro | 250 | 120 | 20 |
| Business | 400 | 220 | 50 |

One post sent to N channels uses N units. Caption generation preserves current
shared/per-channel charging, including existing reservation/refund behavior.
Monthly limits reset on the first day at 00:00 UTC, not the billing renewal.
Links are the persistent rows/buttons of the account's single Link-in-Bio page;
they do not reset. Mobile Add counts all draft rows, including disabled rows;
Publish sends and validates enabled rows. Downgrades retain stored profiles but
enforce lower limits on the next publish. Other Business capabilities inherit
Pro, including scheduling up to 30 days and real-clip visual captions; retired
features remain retired.

Basic/Starter/Pro limits, prices and checkout remain unchanged. All approved
40/25, 90/50 and 190/100 consumables and historical immutable 100/50 grants,
pending claims, owner/receipt namespaces, refund tombstones, monthly-first
consumption and non-expiry remain intact. Business can use the existing paid
plan top-up banks. No reinterpretation of historical purchases is permitted.

## Contract, migration and rollout

- Add `BUSINESS` to Prisma `SubscriptionPlan` through
  `20261102020000_business_subscription_plan`, without row rewrites or deletion.
  Extend `AdminTrialAccess_paid_plan` to allow Business, retaining rejection of
  Basic trials. Compare the check through text so the enum addition and check
  replacement are valid together before PostgreSQL commits the new value.
- Extend authoritative entitlements, memory/Prisma persistence, admin/trial/auth
  schemas and provider mappings. Lower trials do not override purchased Business.
- Add `subscription.businessPlanAvailable` to `GET /billing/subscription`; missing
  means false. `BILLING_BUSINESS_ENABLED` defaults false; real offers/readiness
  require the RevenueCat provider. Business checkout must
  request and receive exact `plan: BUSINESS` on purchase readiness. Restore and
  RevenueCat receipt fulfillment remain available when new sale visibility is off.
  Mobile must use the RevenueCat SDK (Play/App Store through RevenueCat is
  included) and cannot fall back to direct Store dispatch. The real direct
  `/billing/store/verify` bypass refuses Business; local mock fixtures are not
  real purchase support. Its authoritative native current-status/grace/refund
  contract needs separate work before it can support this unpublished product.
- Business wins over active Pro/Starter entitlements in RevenueCat subscriber
  snapshots. That reconciliation preserves still-active lower rights. Existing
  Starter/Pro direct Store paths retain their behavior. Never infer an upgrade
  from a mismatched
  receipt/SKU; retain account, environment and pending-state guards.
- Extend actual profile validation and Mobile parsers from 20 to 50, as well as
  plan labels, paid-bank checks, scheduling and visual-caption gates.
- Required proposed identifiers: native subscription product
  `postdee_business_monthly`, RevenueCat product same, entitlement `business`.
  Server config uses `STORE_BUSINESS_MONTHLY_PRODUCT_ID`,
  `REVENUECAT_BUSINESS_PRODUCT_ID`, `REVENUECAT_BUSINESS_ENTITLEMENT_ID`.
  Store setup must represent a monthly THB 399 reference price; actual payable
  amount comes from verified platform metadata. Do not create active products
  or imply that these identifiers are already configured.

Business uses a separate optional gateway capability for every checkout.
Current SDK user binding and purchased ownership must agree with the bound
API snapshot: fresh Basic requires no active SDK membership; upgrading from
Starter/Pro requires one matching subscription in the current Store. Family
sharing, unknown/multiple products, cross-store membership and stale Basic
state fail before payment and guide restore/original-Store management.
There is no fallback to a generic new purchase. Android uses the pinned SDK's
`StoreProductChangeInfo` and `StoreReplacementMode.chargeProratedPrice` so
benefits change immediately, the billing date stays, and Google computes and
confirms the difference. A Store rejection does not become a second purchase.
On iOS, all main plans must be configured in the same App Store subscription
group; code ownership checks do not prove that external setup. Existing
Starter/Pro purchase adapters remain unchanged. Active purchased Business
cannot start a lower-plan checkout in-app. Manage/cancel the original membership
and wait for verified expiry/reconciliation before buying a lower plan; this
does not implement an immediate in-app downgrade. These checks require native
Sandbox validation before sales.

The custom-paywall replacement requirement is documented by
[RevenueCat](https://www.revenuecat.com/docs/subscription-guidance/managing-subscriptions#google-play);
[Google Billing](https://developer.android.com/google/play/billing/subscriptions)
defines the replacement modes. This implementation uses the existing pinned
`purchases_flutter` 10.3.0 API without changing dependencies. Unit tests prove
argument/ownership guards, not real Store replacement or billed amounts.

Deployment order is the enum migration, all Business-aware API/worker readers,
compatible Mobile, then separately approved store setup/native sandbox checks
and offer activation. Old clients cannot fully represent Business: some map an
unknown plan to Basic, reject >20 links, or omit capabilities. Default-off
visibility protects initial rollout, but does not retrofit old binaries; users
must use a compatible build before this product is offered or a Business trial
is granted.

Once Business rows exist, rollback must retain readers supporting that value.
Keep the enum/data; do not down-migrate, clear test purchases or delete pending
claims. Closing sale visibility does not undo prior charges or disable recovery.

## Verification record

Final local Mobile suite: **4,852 passed / 9 optional skips**, with full Flutter
analysis clean. Final API suite: **3,343 passed / 75 optional skips** using two
workers; typecheck and build pass. Prisma generation/validation/helper checks,
shared template catalog generation and its 24 tests, and 21 Staging CI guard
tests pass. No dependency versions changed. The production dependency audit
passes the repository's high-severity threshold, reporting four moderate issues
in the unchanged Sentry/glob dependency chain; no forced update is included.

Six explicit real-PostgreSQL suites pass **22 tests** after all 30 migrations are
applied to fresh disposable loopback schemas. They cover populated legacy enum
and trial constraints, Business persistence/trial precedence, historical 100/50
defaults, immutable grants, duplicate/refund delivery and separate quota banks.
Other opt-in database suites remain skipped; the default API pass is not proof
of those unrelated database paths. The local fixture is stopped and its data
retained. No hosted database was used.

The Business-specific SDK/service regression group passes 212 tests, including
28 SDK ownership/replacement cases and nine additional service cases. Two
Thai/English reconciliation widget tests prove useful recovery guidance without
success callbacks or leaked product identifiers. Independent source review has
no unresolved finding in the bounded RevenueCat path. The legacy direct Store
verifier/notification paths and consumable grant logic retain baseline behavior.

Source fingerprints, exact commands/logs, final commit and guarded Staging APK
delivery evidence are recorded in the task's `.tmp/business/verification.json`.
The Thai widget fixture uses mocked THB 199/299/399 Store metadata; it is not a
native device screenshot or purchase proof. No app install is included. Native
Play/App Store Sandbox must still prove exact products/prices, replacement and
proration, iOS subscription-group setup, cancellation, restore and refunds before
activation. The separate Staging preflight for `5fa8965` is still prepared only
and requires an existing authorized internal Shell to obtain actual pending
migrations; it is not authorization to deploy this Business branch.
