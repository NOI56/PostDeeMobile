# Replacement post/caption credit packs (2026-11-02, local candidate)

This is the historical standalone billing record for `e488a4f1` / PR #53.
The later scoped category-and-billing draft is documented in
[the consolidation record](2026-11-02-packages-consolidated.md). Its current
scope and verification take precedence over the standalone isolation notes below.

## Approved scope and isolation

- Baseline: verified `main` `f658f9089b14f0d66d900d89fbc1c8bbfddff437`.
- Local branch `codex/multi-sku-topups`, separate from PR #50, #51 and category-only
  PR #52. No code from those pending PRs is merged into this billing branch.
- Approved replacement tiers supersede the earlier quantity/price proposals:

| Tier | Product ID | Post units | Caption credits | THB reference |
| --- | --- | ---: | ---: | ---: |
| Small | `postdee_post40_caption25` | 40 | 25 | 49 |
| Medium | `postdee_post90_caption50` | 90 | 50 | 99 |
| Large | `postdee_post190_caption100` | 190 | 100 | 199 |

Reference amounts do not replace verified native-store checkout quotes. Repeat
purchases are allowed, with distinct receipts granting independently. Two Medium
packs give 180/100 at a THB reference total of 198; one Large gives 190/100 at
199, adding ten post units for one extra baht. Preserve the chosen amounts and
do not claim Large is best value overall or discounted. Verified provider
variable costs/margins are unavailable.

## Preserved contracts

The canonical legacy SKU `postdee_post100_caption50` and existing configured
legacy aliases retain 100 post / 50 caption credits. Do not repurpose that SKU,
change old store products, reinterpret old purchases, reset usage or remove
refund deficits. Starter/Pro eligibility, non-expiry and monthly-first spending
remain. One video sent to N channels uses N post units; caption generation costs
one credit per selected channel, while a shared-caption request costs one.

Catalog v3 adds a per-product array while keeping all old scalar fields and
non-expiring policy v2. Old Mobile builds can read the legacy catalog; new
Mobile falls back when the product list is absent. Confirmation retains the
request shape and echoes the exact product, receipt ID/namespace and frozen
quantities. Verification derives quantities from trusted server definitions and
stored transactions, never client-submitted quantities or a currently selected
card. Recovery remains available with sales disabled or expired membership.

Mobile pending v2 records freeze the expected grant pair under the same
account/API-scoped storage key. Historical v1 receipts remain readable,
including retired configured aliases with their original 100/50 contract. A
new checkout still requires an approved current SKU; recovery of an existing
receipt is not permission to buy an unknown product. Old app builds cannot
read v2 records and fail closed. Preserve the modern pending reader during a
Mobile rollback and never clear a pending record to force another payment.

## Storage and migration

`20261102010000_addon_grant_snapshots` adds non-null
`MonthlyAddonPurchase.postUnitsGranted` and `aiCaptionsGranted`, defaulting to
100/50 for the historical contract and late legacy writers. Constraints reject
invalid grants; a database trigger prevents editing frozen quantities. Refunds
and owner-deletion tombstones change only their existing fields. Both memory
and Prisma readers sum snapshots and count valid transactions independently of
quantity. Existing post and caption consumption stay separate and lifetime.

## Store setup and delivery gates

1. Review this local code before any remote submission for the expanded billing
   scope. Keep category-only PR #52 separate and resolve its eventual UI overlap
   deliberately; do not copy over the pending visibility/category safeguards.
2. Apply the additive migration and deliver the compatible API to every instance,
   leaving `BILLING_ADDON_TIERS_ENABLED=false`. The existing global sale gate
   also remains required. Audit historical configured product aliases.
3. Under separate authorization, configure the exact three IDs as consumable
   one-time products in Google Play/App Store and RevenueCat. Set the chosen
   Thai reference prices and review each store/country's actual quote. Retain
   legacy product history and receipt lookup; do not repurpose its identity.
   The old-client scalar offer retains its existing gate. Decide separately
   whether/when to retire new legacy checkouts; preserve old fulfillment and
   balances even if its store product stops accepting new purchases.
4. Deliver Mobile only after the compatible API, and verify sandbox checkout,
   canonical receipt recovery, refunds and old/new app compatibility. Enabling
   products or the sale gate requires separate authorization.
5. Once a different-sized SKU has a ledger row, the former count × 100/50 reader
   is not a safe API rollback, even though old Mobile remains supported. Retain
   a snapshot-aware reader and verification path.

No live products, production billing/environment changes, hosted migration,
PR approval/merge or deployment are included in this implementation.

## Verification record

Tests are run on the isolated branch with pinned Node 22.23.3 and workspace
Flutter 3.44.1 / Dart 3.12.1. Real database suites use only a disposable loopback
PostgreSQL 18 cluster created under this worktree on port 55441, with separate
add-on and caption fixture databases/schemas. No hosted database is used.

Final checks on the approved 190/100 Large definition and historical v1 fix:

- API `npm.cmd run test -- --maxWorkers=4`: 3,297 passed / 72 opt-in skipped
  across 194 passed / 12 skipped files. Final backend typecheck passed.
- Affected real PostgreSQL suites: `monthlyAddonDatabase.test.ts`,
  `monthlyAddonGrantMigration.database.test.ts`,
  `monthlyAddonQuota.database.test.ts` and `captionUsageBatch.database.test.ts`:
  19 passed. They exercised production migration SQL on populated legacy/alias/
  revoked rows, late legacy writer defaults, immutable quantities, mixed-SKU
  duplicate/refund behavior and separate monthly-first post/caption consumption.
- API build, `prisma:generate`, `prisma:validate`, and the NodeNext TypeScript
  check of `prisma/seed.ts` / `prisma.config.ts` passed. Profile catalog generator
  check and 24 generator tests passed. The production dependency audit met the
  configured high-severity threshold; four pre-existing moderate advisories
  remain, with dependency files unchanged.
- Mobile `flutter test --no-pub --concurrency=2 --reporter expanded`:
  4,668 passed / 8 optional skipped, after the final v1 receipt fix. A previous
  partial run was intentionally stopped for that fix and is not a passing run.
- Focused mobile billing tests: 142 passed; custom configured legacy alias
  run: 3 passed. The 12 v1 alias-collision regressions failed before the fix and
  passed afterward, covering all replacement SKU names, both namespaces, old
  responses without product echo, matching echoes and rejected proof mismatches.
- Paywall checks after the 190 amendment: 107 passed / 1 legacy optional preview
  skipped, including the offline screenshot fixture. Thai/English 320dp at 2x
  text in light/dark passed; reviewed images show all three 40/25, 90/50 and
  190/100 tiers with fixture quotes. Images are not live store configuration proof.
- Full `flutter analyze --no-pub` passed. Staging configuration guards: 21
  passed. Guarded `postdee-staging.ps1 -Command build-apk --no-pub` passed using
  the existing Staging/Test Store overlay without copying or logging its key.
  APK SHA-256: `56327f8e96057ff2e40aff327f5d6cb54b9429a71fdc0641461a564d2dc8c122`.
  The APK was not installed. An earlier build hit disk capacity; only this task's
  old reproducible build intermediates/duplicate APK outputs were removed, while
  both previously verified APKs and their hashes were preserved. The final build
  succeeded after cleanup and after the receipt fix.

The disposable PostgreSQL cluster was stopped after the real database suites.
No hosted migration, product creation, real purchase, device startup, remote
submission, PR merge or deployment was performed. Native store products and
end-to-end purchase/restore/refund flows remain unverified until the separately
authorized store setup. Future integration with pending PR #50/#52 must retain
their category/visibility/unit-explanation behavior and rerun combined tests.
