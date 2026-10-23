import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import { createOwnerMutationLock } from '../account/ownerMutationLock.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createUserStore } from '../users/userStore.js';
import type { RevenueCatSubscriberSnapshot } from './revenueCatSubscriberClient.js';
import { registerRevenueCatWebhookRoutes } from './revenueCatWebhookRoutes.js';

const webhookToken = 'transfer-regression-webhook-token';
const initialTimestampMs = 1_784_044_800_000;
const transferTimestampMs = initialTimestampMs + 1;
const observedAtMs = initialTimestampMs + 2;

const productionPro = {
  id: 'pro',
  productId: 'postdee_pro_monthly',
  expiresAt: '2100-01-01T00:00:00.000Z',
  isSandbox: false,
  store: 'play_store'
};

const transferConfig = () => readServerConfig({
  BILLING_PROVIDER: 'revenuecat',
  REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken,
  REVENUECAT_REST_API_V1_KEY: 'fixture-key-not-used-for-network',
  REVENUECAT_SUBSCRIPTION_ENVIRONMENT: 'PRODUCTION'
});

const planFor = async (app: ReturnType<typeof createApp>, userId: string) => {
  const response = await request(app)
    .get('/billing/subscription')
    .set('x-postdee-user-id', userId)
    .expect(200);
  return response.body.subscription.plan;
};

const activateSource = (app: ReturnType<typeof createApp>, timestampMs = initialTimestampMs) =>
  request(app)
    .post('/billing/revenuecat/webhooks')
    .set('Authorization', `Bearer ${webhookToken}`)
    .send({ event: {
      id: `source-purchase-${timestampMs}`,
      type: 'INITIAL_PURCHASE',
      app_user_id: 'transfer-source',
      event_timestamp_ms: timestampMs,
      entitlement_ids: ['pro'],
      product_id: productionPro.productId,
      environment: 'PRODUCTION',
      store: 'PLAY_STORE',
      expiration_at_ms: Date.parse(productionPro.expiresAt)
    } })
    .expect(200);

const postTransfer = (app: ReturnType<typeof createApp>, event: Record<string, unknown> = {}) =>
  request(app)
    .post('/billing/revenuecat/webhooks')
    .set('Authorization', `Bearer ${webhookToken}`)
    .send({ event: {
      id: 'transfer-event',
      type: 'TRANSFER',
      event_timestamp_ms: transferTimestampMs,
      transferred_from: ['transfer-source'],
      transferred_to: ['transfer-destination'],
      ...event
    } });

describe('RevenueCat subscription transfers', () => {
  it('revokes the source after restore transfers its subscription to another existing account', async () => {
    const source = 'transfer-source';
    const destination = 'transfer-destination';
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === destination ? [productionPro] : []
    }));
    const app = createApp({
      config: transferConfig(),
      revenueCatSubscriberClient: { loadSubscriber }
    });

    await planFor(app, source);
    await planFor(app, destination);
    await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', `Bearer ${webhookToken}`)
      .send({ event: {
        id: 'original-source-purchase',
        type: 'INITIAL_PURCHASE',
        app_user_id: source,
        event_timestamp_ms: initialTimestampMs,
        entitlement_ids: ['pro'],
        product_id: productionPro.productId,
        environment: 'PRODUCTION',
        store: 'PLAY_STORE',
        expiration_at_ms: Date.parse(productionPro.expiresAt)
      } })
      .expect(200);
    expect(await planFor(app, source)).toBe('PRO');

    await request(app)
      .post('/billing/revenuecat/resync')
      .set('x-postdee-user-id', destination)
      .send({})
      .expect(200);
    expect(await planFor(app, destination)).toBe('PRO');
    loadSubscriber.mockClear();

    const response = await request(app)
      .post('/billing/revenuecat/webhooks')
      .set('Authorization', `Bearer ${webhookToken}`)
      .send({ event: {
        id: 'restored-subscription-transfer',
        type: 'TRANSFER',
        app_user_id: destination,
        event_timestamp_ms: transferTimestampMs,
        transferred_from: [source],
        transferred_to: [destination],
        entitlement_ids: ['pro'],
        product_id: productionPro.productId,
        environment: 'PRODUCTION',
        store: 'PLAY_STORE'
      } });

    expect(await planFor(app, destination)).toBe('PRO');
    expect(await planFor(app, source)).toBe('BASIC');
    expect(response.status).toBe(200);
    expect(loadSubscriber).toHaveBeenCalledWith(source);
    expect(loadSubscriber).toHaveBeenCalledWith(destination);
  });

  it('reconciles both accounts when TRANSFER has no app user, product, environment, or store fields', async () => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(200);

    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
    expect(loadSubscriber).toHaveBeenCalledTimes(2);
  });

  it('preserves an independent eligible subscription remaining on the source', async () => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-source' ? [{
        ...productionPro, id: 'starter', productId: 'postdee_starter_monthly'
      }] : [productionPro]
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(200);

    expect(await planFor(app, 'transfer-source')).toBe('STARTER');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it.each([
    { isSandbox: true, store: 'PLAY_STORE' },
    { isSandbox: false, store: 'TEST_STORE' },
    { isSandbox: undefined, store: 'PLAY_STORE' },
    { isSandbox: false, store: undefined }
  ])('does not grant production access from an ineligible destination snapshot: %j', async (proof) => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-destination' ? [{ ...productionPro, ...proof }] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(200);

    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');
  });

  it('keeps a newer source renewal when a transfer readback has an older cursor', async () => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app, observedAtMs + 1);

    await postTransfer(app).expect(200);

    expect(await planFor(app, 'transfer-source')).toBe('PRO');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it('does not reactivate the source from a renewal older than the transfer readback', async () => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(200);
    await activateSource(app, transferTimestampMs);

    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it('retries stale provider readbacks without advancing their cursor to the event time', async () => {
    let providerTime = transferTimestampMs - 1;
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs: providerTime,
      activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(502);
    expect(await planFor(app, 'transfer-source')).toBe('PRO');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');

    providerTime = observedAtMs;
    await postTransfer(app).expect(200);
    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it.each(['transfer-source', 'transfer-destination'])(
    'reads both snapshots before any write and safely retries a lookup failure for %s', async (unavailableOwner) => {
    let providerUnavailable = true;
    const loadSubscriber = vi.fn(async (userId: string) => {
      if (userId === unavailableOwner && providerUnavailable) {
        throw new Error('private-upstream-detail');
      }
      return {
        observedAtMs,
        activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
      };
    });
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    const failure = await postTransfer(app).expect(502);
    expect(JSON.stringify(failure.body)).not.toContain('private-upstream-detail');
    expect(await planFor(app, 'transfer-source')).toBe('PRO');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');

    providerUnavailable = false;
    await postTransfer(app).expect(200);
    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it('deduplicates aliases appearing on either side and ignores replayed writes', async () => {
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === 'transfer-destination' ? [productionPro] : []
    }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);
    const aliases = {
      transferred_from: ['transfer-source', 'transfer-source'],
      transferred_to: ['transfer-destination', 'transfer-source', 'transfer-destination']
    };

    await postTransfer(app, aliases).expect(200);
    expect(loadSubscriber).toHaveBeenCalledTimes(2);
    await postTransfer(app, aliases).expect(200).expect(({ body }) => {
      expect(body.ignored).toBe(true);
    });
    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('PRO');
  });

  it('does not create or look up unknown owners named in a transfer', async () => {
    const loadSubscriber = vi.fn(async () => ({ observedAtMs, activeEntitlements: [productionPro] }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });

    await postTransfer(app).expect(202);

    expect(loadSubscriber).not.toHaveBeenCalled();
    expect(await planFor(app, 'transfer-source')).toBe('BASIC');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');
  });

  it.each([
    { id: undefined },
    { event_timestamp_ms: undefined },
    { event_timestamp_ms: '123' },
    { transferred_from: undefined },
    { transferred_from: [] },
    { transferred_from: ['transfer-source', 42] },
    { transferred_to: [''] }
  ])('rejects malformed transfer ordering or owner metadata without subscriber work: %j', async (event) => {
    const loadSubscriber = vi.fn(async () => ({ observedAtMs, activeEntitlements: [] }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });

    await postTransfer(app, event).expect(400);

    expect(loadSubscriber).not.toHaveBeenCalled();
  });

  it('preserves access and asks for retry when an eligible entitlement is unmapped', async () => {
    const loadSubscriber = vi.fn(async () => ({ observedAtMs, activeEntitlements: [{
      ...productionPro, id: 'unmapped-entitlement', productId: 'unmapped-product'
    }] }));
    const app = createApp({ config: transferConfig(), revenueCatSubscriberClient: { loadSubscriber } });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(502);

    expect(await planFor(app, 'transfer-source')).toBe('PRO');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');
  });

  it('asks for retry without changing access when the subscriber lookup is not configured', async () => {
    const app = createApp({ config: readServerConfig({
      BILLING_PROVIDER: 'revenuecat',
      REVENUECAT_WEBHOOK_AUTH_TOKEN: webhookToken,
      REVENUECAT_REST_API_V1_KEY: '',
      REVENUECAT_SUBSCRIPTION_ENVIRONMENT: 'PRODUCTION'
    }) });
    await planFor(app, 'transfer-source');
    await planFor(app, 'transfer-destination');
    await activateSource(app);

    await postTransfer(app).expect(502);

    expect(await planFor(app, 'transfer-source')).toBe('PRO');
    expect(await planFor(app, 'transfer-destination')).toBe('BASIC');
  });

  it('releases every owner admission when checking user existence fails', async () => {
    const app = express();
    const router = express.Router();
    const ownerMutationLock = createOwnerMutationLock();
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore();
    const loadSubscriber = vi.fn(async () => ({ observedAtMs, activeEntitlements: [] }));
    const exists = vi.fn().mockRejectedValue(new Error('private-database-detail'));
    app.use(express.json());
    registerRevenueCatWebhookRoutes({
      router,
      config: transferConfig(),
      ownerMutationLock,
      userStore: { ...userStore, exists },
      subscriptionStore,
      subscriberClient: { loadSubscriber }
    });
    app.use(router);
    app.use((_error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
      response.status(500).json({ status: 'error' });
    });

    await postTransfer(app).expect(500);

    expect(loadSubscriber).not.toHaveBeenCalled();
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });

  it('does not mutate a source sealed for deletion while the subscriber lookup is running', async () => {
    const app = express();
    const router = express.Router();
    const ownerMutationLock = createOwnerMutationLock();
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore();
    const source = { id: 'transfer-source', provider: 'firebase' as const };
    const destination = { id: 'transfer-destination', provider: 'firebase' as const };
    await userStore.ensure(source);
    await userStore.ensure(destination);
    await subscriptionStore.activatePro(source, { billingSubscriptionId: `revenuecat:${source.id}` });
    let beginLookup!: () => void;
    let releaseLookup!: () => void;
    const lookupStarted = new Promise<void>((resolve) => { beginLookup = resolve; });
    const lookupGate = new Promise<void>((resolve) => { releaseLookup = resolve; });
    const loadSubscriber = vi.fn(async (userId: string): Promise<RevenueCatSubscriberSnapshot> => {
      if (userId === source.id) {
        beginLookup();
        await lookupGate;
      }
      return { observedAtMs, activeEntitlements: userId === destination.id ? [productionPro] : [] };
    });
    app.use(express.json());
    registerRevenueCatWebhookRoutes({
      router, config: transferConfig(), userStore, subscriptionStore,
      ownerMutationLock, subscriberClient: { loadSubscriber }
    });
    app.use(router);

    const transferRequest = postTransfer(app).then((response) => response);
    await lookupStarted;
    ownerMutationLock.markDeleting(source.id);
    releaseLookup();

    expect((await transferRequest).status).toBe(200);
    expect(await subscriptionStore.getPlan(source)).toBe('PRO');
    expect(await subscriptionStore.getPlan(destination)).toBe('PRO');
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });

  it('honors a durable owner tombstone even if the process still sees an active source', async () => {
    const app = express();
    const router = express.Router();
    const owners = createInMemoryUploadSessionStore();
    const ownerMutationLock = createOwnerMutationLock();
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore({ runWithActiveOwner: owners.runWithActiveOwner });
    const source = { id: 'transfer-source', provider: 'firebase' as const };
    const destination = { id: 'transfer-destination', provider: 'firebase' as const };
    await userStore.ensure(source);
    await userStore.ensure(destination);
    await subscriptionStore.activatePro(source, { billingSubscriptionId: `revenuecat:${source.id}` });
    await owners.beginOwnerDeletion(source.id);
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === destination.id ? [productionPro] : []
    }));
    app.use(express.json());
    registerRevenueCatWebhookRoutes({
      router, config: transferConfig(), userStore, subscriptionStore,
      ownerMutationLock, subscriberClient: { loadSubscriber }
    });
    app.use(router);

    await postTransfer(app).expect(200);

    expect(await subscriptionStore.getPlan(source)).toBe('PRO');
    expect(await subscriptionStore.getPlan(destination)).toBe('PRO');
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });

  it('does not grant the destination before a failed source subscription write can be retried', async () => {
    const app = express();
    const router = express.Router();
    const ownerMutationLock = createOwnerMutationLock();
    const userStore = createUserStore();
    const subscriptionStore = createSubscriptionStore();
    const source = { id: 'transfer-source', provider: 'firebase' as const };
    const destination = { id: 'transfer-destination', provider: 'firebase' as const };
    await userStore.ensure(source);
    await userStore.ensure(destination);
    await subscriptionStore.activatePro(source, { billingSubscriptionId: `revenuecat:${source.id}` });
    const applyRevenueCatEvent = vi.fn(async (
      input: Parameters<typeof subscriptionStore.applyRevenueCatEvent>[0]
    ) => {
      if (input.authUser.id === source.id) throw new Error('private-write-error');
      return subscriptionStore.applyRevenueCatEvent(input);
    });
    const loadSubscriber = vi.fn(async (userId: string) => ({
      observedAtMs,
      activeEntitlements: userId === destination.id ? [productionPro] : []
    }));
    app.use(express.json());
    registerRevenueCatWebhookRoutes({
      router, config: transferConfig(), userStore,
      subscriptionStore: { ...subscriptionStore, applyRevenueCatEvent },
      ownerMutationLock, subscriberClient: { loadSubscriber }
    });
    app.use(router);
    app.use((_error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
      response.status(500).json({ status: 'error' });
    });

    await postTransfer(app).expect(500);

    expect(await subscriptionStore.getPlan(source)).toBe('PRO');
    expect(await subscriptionStore.getPlan(destination)).toBe('BASIC');
    expect(applyRevenueCatEvent).toHaveBeenCalledTimes(1);
    expect(ownerMutationLock.debugStateSize()).toBe(0);
  });
});
