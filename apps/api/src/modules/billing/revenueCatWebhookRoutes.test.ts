import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';

const revenueCatToken = 'revenuecat-webhook-token';

const createRevenueCatApp = () =>
  createApp({
    config: readServerConfig({
      BILLING_PROVIDER: 'revenuecat',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: revenueCatToken,
      REVENUECAT_STARTER_ENTITLEMENT_ID: 'starter',
      REVENUECAT_PRO_ENTITLEMENT_ID: 'pro',
      REVENUECAT_STARTER_PRODUCT_ID: 'postdee_starter_monthly',
      REVENUECAT_PRO_PRODUCT_ID: 'postdee_pro_monthly'
    })
  });

const postRevenueCatWebhook = (app: ReturnType<typeof createRevenueCatApp>, body: unknown) =>
  request(app)
    .post('/billing/revenuecat/webhooks')
    .set('Authorization', `Bearer ${revenueCatToken}`)
    .send(body);

describe('RevenueCat webhooks', () => {
  it('rejects webhook requests without the configured bearer token', async () => {
    const app = createRevenueCatApp();

    const response = await request(app)
      .post('/billing/revenuecat/webhooks')
      .send({
        event: {
          type: 'INITIAL_PURCHASE',
          app_user_id: 'seller-revenuecat-auth',
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      })
      .expect(401);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_WEBHOOK_UNAUTHORIZED'
    });
  });

  it('activates Starter for a RevenueCat Starter entitlement event', async () => {
    const app = createRevenueCatApp();

    const activationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-starter',
        entitlement_ids: ['starter'],
        product_id: 'postdee_starter_monthly',
        expiration_at_ms: 4102444800000
      }
    }).expect(200);

    expect(activationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-starter',
      plan: 'STARTER',
      status: 'ACTIVE',
      billingSubscriptionId: 'revenuecat:seller-revenuecat-starter'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-revenuecat-starter')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-starter',
      plan: 'STARTER',
      status: 'ACTIVE',
      canSchedule: true,
      canUseAiCaptions: true,
      canUseAnalytics: false
    });
  });

  it('activates Pro for a RevenueCat Pro product event', async () => {
    const app = createRevenueCatApp();

    const activationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'RENEWAL',
        app_user_id: 'seller-revenuecat-pro',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly',
        expiration_at_ms: 4102444800000
      }
    }).expect(200);

    expect(activationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-pro',
      plan: 'PRO',
      status: 'ACTIVE',
      currentPeriodEnd: '2100-01-01T00:00:00.000Z'
    });
  });

  it('marks an existing RevenueCat subscription as canceled after expiration', async () => {
    const app = createRevenueCatApp();

    await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-expired',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(200);

    const expirationResponse = await postRevenueCatWebhook(app, {
      event: {
        type: 'EXPIRATION',
        app_user_id: 'seller-revenuecat-expired',
        entitlement_ids: ['pro'],
        product_id: 'postdee_pro_monthly'
      }
    }).expect(200);

    expect(expirationResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-expired',
      plan: 'PRO',
      status: 'CANCELED'
    });

    const subscriptionResponse = await request(app)
      .get('/billing/subscription')
      .set('x-postdee-user-id', 'seller-revenuecat-expired')
      .expect(200);

    expect(subscriptionResponse.body.subscription).toMatchObject({
      userId: 'seller-revenuecat-expired',
      plan: 'BASIC',
      status: 'INACTIVE'
    });
  });

  it('does not revoke entitlements for non-expiring RevenueCat lifecycle events', async () => {
    const app = createRevenueCatApp();

    for (const eventType of ['CANCELLATION', 'SUBSCRIPTION_PAUSED', 'BILLING_ISSUE']) {
      const userId = `seller-revenuecat-${eventType.toLowerCase().replace(/_/g, '-')}`;

      await postRevenueCatWebhook(app, {
        event: {
          type: 'INITIAL_PURCHASE',
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      }).expect(200);

      const lifecycleResponse = await postRevenueCatWebhook(app, {
        event: {
          type: eventType,
          app_user_id: userId,
          entitlement_ids: ['pro'],
          product_id: 'postdee_pro_monthly'
        }
      }).expect(202);

      expect(lifecycleResponse.body).toMatchObject({
        status: 'ok',
        ignored: true,
        code: 'REVENUECAT_EVENT_NOT_ACTIONABLE'
      });

      const subscriptionResponse = await request(app)
        .get('/billing/subscription')
        .set('x-postdee-user-id', userId)
        .expect(200);

      expect(subscriptionResponse.body.subscription).toMatchObject({
        userId,
        plan: 'PRO',
        status: 'ACTIVE'
      });
    }
  });

  it('acknowledges unsupported RevenueCat products without changing entitlements', async () => {
    const app = createRevenueCatApp();

    const response = await postRevenueCatWebhook(app, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'seller-revenuecat-unknown',
        entitlement_ids: ['unknown'],
        product_id: 'unknown_product'
      }
    }).expect(202);

    expect(response.body).toMatchObject({
      status: 'ok',
      ignored: true,
      code: 'REVENUECAT_PRODUCT_NOT_MAPPED'
    });
  });

  it('rejects malformed RevenueCat webhook payloads', async () => {
    const app = createRevenueCatApp();

    const response = await postRevenueCatWebhook(app, {}).expect(400);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'REVENUECAT_WEBHOOK_INVALID'
    });
  });
});
