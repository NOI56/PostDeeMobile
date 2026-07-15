# Production Foundation RevenueCat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first production-safe RevenueCat subscription foundation for PostDee backend and deployment configuration.

**Architecture:** Add RevenueCat as a production billing provider while leaving local mock billing and legacy Apple/Google verifier scaffolds intact. RevenueCat webhooks update the existing `SubscriptionStore`, so current feature gates keep working without changing posts, captions, analytics, or AI editing modules.

**Tech Stack:** Express, TypeScript, Vitest, Prisma, Render Blueprint, RevenueCat webhooks.

> **Status addendum — 2026-07-15:** RevenueCat Test Store purchase E2E now
> passes on the Android Emulator with a Firebase uid and test price. Restore
> UI/SDK passed before server reconciliation was added. The code now performs
> SDK restore followed by authenticated `POST /billing/revenuecat/resync`, which
> reads the subscriber with a server-only `REVENUECAT_REST_API_V1_KEY` and
> reconciles the subscription store. That true resync still needs Staging deploy,
> secret configuration, and E2E verification. Google Play purchase and physical
> Android testing remain unverified.

---

### Task 1: Billing Config Accepts RevenueCat

**Files:**
- Modify: `apps/api/src/config/env.ts`
- Test: `apps/api/src/config/env.test.ts`

- [x] **Step 1: Write failing config tests**

Add tests that `BILLING_PROVIDER=revenuecat` is accepted and that production allows it while still rejecting `mock`.

- [x] **Step 2: Run config tests and verify RED**

Run: `npm.cmd run test -- src/config/env.test.ts`

Expected: fail with `BILLING_PROVIDER must be mock or store`.

- [x] **Step 3: Implement config support**

Add `revenuecat` to `BillingProviderKind`, `readBillingProvider`, and server config fields for RevenueCat webhook token and product/entitlement mappings.

- [x] **Step 4: Run config tests and verify GREEN**

Run: `npm.cmd run test -- src/config/env.test.ts`

Expected: pass.

### Task 2: RevenueCat Webhook Route

**Files:**
- Create: `apps/api/src/modules/billing/revenueCatWebhookRoutes.ts`
- Create: `apps/api/src/modules/billing/revenueCatWebhookRoutes.test.ts`
- Modify: `apps/api/src/app.ts`

- [x] **Step 1: Write failing webhook tests**

Cover missing auth returning `401`, Starter activation, Pro activation, cancellation status updates, ignored unknown products returning `202`, and malformed payload returning `400`.

- [x] **Step 2: Run webhook tests and verify RED**

Run: `npm.cmd run test -- src/modules/billing/revenueCatWebhookRoutes.test.ts`

Expected: fail because the route module does not exist.

- [x] **Step 3: Implement webhook parser and route**

Create a focused route module that verifies `Authorization: Bearer <token>`, reads `event.app_user_id`, maps product ids to Starter/Pro, activates the subscription, and updates status for inactive events.

- [x] **Step 4: Register route in app**

Register the RevenueCat webhook route when billing routes are registered so the endpoint exists for production.

- [x] **Step 5: Run webhook tests and verify GREEN**

Run: `npm.cmd run test -- src/modules/billing/revenueCatWebhookRoutes.test.ts`

Expected: pass.

### Task 3: Production Deployment Defaults

**Files:**
- Modify: `render.yaml`
- Modify: `apps/api/.env.example`

- [x] **Step 1: Update deployment config**

Set production to `AUTH_PROVIDER=firebase`, `BILLING_PROVIDER=revenuecat`, `VIDEO_STORAGE=r2`, and add secret placeholders using Render `sync: false` for Firebase, RevenueCat, R2, and provider keys.

- [x] **Step 2: Validate config by tests**

Run: `npm.cmd run test -- src/config/env.test.ts`

Expected: pass.

### Task 4: Documentation Sync

**Files:**
- Modify: `README.md`
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `ROADMAP.md`
- Modify: `docs/GO_LIVE.md`

- [x] **Step 1: Sync RevenueCat docs**

Document RevenueCat as the production billing path, describe webhook setup, and mark Apple/Google verifier as legacy/scaffold.

- [x] **Step 2: Run verification**

Run:

```powershell
npm.cmd run test
npm.cmd run build
$env:DATABASE_URL='postgresql://postdee:postdee_password@localhost:5432/postdee?schema=public'
npm.cmd run prisma:validate
```

Expected: tests pass, build passes, Prisma schema valid.

### Task 5: Restore And Server Reconciliation Addendum

**Files:**
- Create: `apps/api/src/modules/billing/revenueCatSubscriberClient.ts`
- Create: `apps/api/src/modules/billing/revenueCatRestoreRoutes.ts`
- Modify: `apps/api/src/modules/subscriptions/subscriptionStore.ts`
- Modify: `apps/api/src/modules/subscriptions/prismaSubscriptionRepository.ts`
- Modify: `apps/mobile/lib/features/billing/store_subscription_service.dart`
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `render.yaml`
- Modify: `render.staging.yaml`
- Modify: `apps/api/.env.example`

- [x] Add authenticated subscriber lookup and plan reconciliation tests.
- [x] Add mobile SDK restore → backend resync flow and tests.
- [x] Keep the RevenueCat REST secret on the API only; derive app user id from
      the authenticated Firebase user rather than request data.
- [ ] Deploy the current backend to Staging and set
      `REVENUECAT_REST_API_V1_KEY` in Render without exposing its value.
- [ ] Rerun Restore E2E against Test Store and verify Starter/Pro/Basic results.
- [ ] Verify real Google Play sandbox purchase/restore on a physical Android
      device before claiming production billing readiness.
