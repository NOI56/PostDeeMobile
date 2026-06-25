# Production Foundation RevenueCat Design

## Goal

Make the backend and deployment configuration ready for the first production billing path by using RevenueCat as the subscription source of truth, while keeping existing local mock billing and legacy Apple/Google verifier scaffolds available for development only.

## Scope

Phase 1 covers backend production configuration, RevenueCat webhook ingestion, and documentation sync. It does not add real RevenueCat mobile purchases yet, does not add secrets to the repository, and does not remove the existing Apple/Google verifier code.

## Architecture

The backend will accept `BILLING_PROVIDER=revenuecat` in production. RevenueCat will send subscription lifecycle events to `POST /billing/revenuecat/webhooks`; the API will verify a shared authorization token, map RevenueCat product or entitlement identifiers to PostDee plans, and update the existing subscription store. Existing entitlement checks in posts, captions, analytics, and AI editing will continue to read from `SubscriptionStore`, so downstream product behavior does not need a rewrite.

RevenueCat `app_user_id` must match the authenticated app user id used by PostDee, which will be the Firebase user id for production. For paid subscriptions, the backend will store a provider-neutral billing id using the RevenueCat subscriber id, such as `revenuecat:<app_user_id>`, so later events update the same subscription.

## Components

- `apps/api/src/config/env.ts`: add `revenuecat` to `BILLING_PROVIDER`, read RevenueCat webhook token and mapping env vars, and keep production rejecting only `BILLING_PROVIDER=mock`.
- `apps/api/src/modules/billing/revenueCatWebhookRoutes.ts`: parse RevenueCat events, verify webhook authorization, map plan/status, and update subscriptions.
- `apps/api/src/modules/billing/revenueCatWebhookRoutes.test.ts`: cover webhook auth, Starter/Pro activation, cancellation, ignored events, and unsupported products.
- Existing subscription stores: no interface change in Phase 1. RevenueCat uses a deterministic billing id, `revenuecat:<app_user_id>`, so inactive events can reuse the existing `updateStatusByBillingSubscriptionId` method after an activation event has bound the user.
- `render.yaml`: switch production away from mock auth/billing and document secret-backed env vars with `sync: false`.
- `.env.example`, `README.md`, `API.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `docs/GO_LIVE.md`: sync production billing direction to RevenueCat.

## Data Flow

1. Mobile production signs the user in with Firebase.
2. Mobile RevenueCat setup uses Firebase uid as RevenueCat app user id.
3. User buys Starter or Pro through Apple/Google via RevenueCat.
4. RevenueCat sends a webhook to `POST /billing/revenuecat/webhooks`.
5. Backend checks `Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>`.
6. Backend maps product/entitlement to `STARTER` or `PRO`.
7. Backend ensures the user exists and activates the mapped plan in `SubscriptionStore`.
8. App features continue using `GET /billing/subscription`.

## Error Handling

Missing or invalid webhook authorization returns `401`. Unsupported product or entitlement events return `202` with `ignored: true` so RevenueCat does not retry forever. Malformed payloads return `400`. Cancellation, expiration, refund, and billing issue events set the existing subscription to an inactive state through `billingSubscriptionId` when a prior activation has bound the user.

## Testing

Backend tests will be written first and must fail before implementation. Verification commands are `npm.cmd run test`, `npm.cmd run build`, and Prisma validation. Mobile RevenueCat SDK migration is intentionally outside Phase 1 and will be a separate task.
