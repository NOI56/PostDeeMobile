# Store Subscription Billing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace Stripe as the main mobile Pro payment flow with Apple App Store and Google Play subscription scaffolding.

**Architecture:** Keep the existing Basic/Pro entitlement store and feature gates. Mobile starts a Store Subscription flow and backend verifies a store purchase payload before activating Pro. This first pass is a safe scaffold: Apple/Google real receipt verification is represented by strict request validation and a mock provider until real product IDs and service credentials are available.

**Tech Stack:** Flutter, Express, TypeScript, Prisma schema, Vitest, Flutter widget/unit tests.

---

### Task 1: Backend Store Purchase Verification

**Files:**
- Modify: `apps/api/src/modules/billing/billingRoutes.test.ts`
- Modify: `apps/api/src/modules/billing/billingRoutes.ts`
- Create: `apps/api/src/modules/billing/storePurchaseService.ts`
- Modify: `apps/api/src/config/env.ts`

- [x] **Step 1: Write failing tests**

Add tests that `POST /billing/store/verify` activates Pro for an authenticated user when given `platform: IOS|ANDROID`, `productId: postdee_pro_monthly`, and a non-empty purchase token or transaction id. Add a test that unsupported platforms return `400`.

- [x] **Step 2: Run backend billing tests and confirm RED**

Run: `npm.cmd run test -- src/modules/billing/billingRoutes.test.ts`

Expected: tests fail because `/billing/store/verify` does not exist yet.

- [x] **Step 3: Implement minimal backend scaffold**

Add a parser for store purchase payloads, register `POST /billing/store/verify`, ensure the user exists, activate Pro through the existing subscription store, and return the subscription plus purchase metadata.

- [x] **Step 4: Run backend billing tests and confirm GREEN**

Run: `npm.cmd run test -- src/modules/billing/billingRoutes.test.ts`

Expected: billing route tests pass.

### Task 2: Mobile Store Subscription UI

**Files:**
- Modify: `apps/mobile/test/home_screen_test.dart`
- Modify: `apps/mobile/test/postdee_api_client_test.dart`
- Modify: `apps/mobile/lib/core/network/postdee_api_client.dart`
- Modify: `apps/mobile/lib/features/home/home_screen.dart`

- [x] **Step 1: Write failing mobile tests**

Change Home tests to expect a Store Subscription action instead of `Create Pro checkout`. Add API-client tests for Store purchase payload serialization.

- [x] **Step 2: Run targeted Flutter tests and confirm RED**

Run: `..\..\.tools\flutter\bin\flutter.bat test test\home_screen_test.dart test\postdee_api_client_test.dart`

Expected: tests fail because the old checkout flow is still wired.

- [x] **Step 3: Implement minimal mobile scaffold**

Replace checkout types/method names with store subscription names. In this scaffold, the Home action sends a mock store verification payload to the backend and refreshes the Pro status afterward.

- [x] **Step 4: Run targeted Flutter tests and confirm GREEN**

Run: `..\..\.tools\flutter\bin\flutter.bat test test\home_screen_test.dart test\postdee_api_client_test.dart`

Expected: targeted mobile tests pass.

### Task 3: Remove Stripe From Active Config and Docs

**Files:**
- Modify: `README.md`
- Modify: `API.md`
- Modify: `ARCHITECTURE.md`
- Modify: `apps/api/.env.example`
- Modify: `apps/mobile/README.md`

- [x] **Step 1: Update docs**

Replace Stripe-as-main-flow language with Store Subscription language. Keep a short note that real Apple/Google receipt verification still needs credentials and app-store products.

- [x] **Step 2: Run full verification**

Run backend tests/build, Prisma validation, Flutter analyze, and Flutter tests.

Expected: all commands complete without failures.

