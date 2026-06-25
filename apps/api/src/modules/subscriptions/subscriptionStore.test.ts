import { describe, expect, it } from 'vitest';

import { createSubscriptionStore } from './subscriptionStore.js';

describe('createSubscriptionStore', () => {
  it('persists mock Pro activation for a user', async () => {
    const store = createSubscriptionStore();

    await expect(store.getPlan({ id: 'seller-pro', provider: 'mock' })).resolves.toBe('BASIC');

    await expect(store.activatePro({ id: 'seller-pro', provider: 'mock' })).resolves.toMatchObject({
      userId: 'seller-pro',
      plan: 'PRO',
      status: 'ACTIVE'
    });
    await expect(store.getPlan({ id: 'seller-pro', provider: 'mock' })).resolves.toBe('PRO');
  });

  it('drops an ACTIVE subscription to BASIC once its paid period has ended', async () => {
    const store = createSubscriptionStore({
      now: () => '2026-07-10T00:00:00.000Z'
    });

    await store.activatePro(
      { id: 'seller-expired', provider: 'mock' },
      { currentPeriodEnd: '2026-07-01T00:00:00.000Z' }
    );

    // Status is still ACTIVE in storage, but the period ended -> safety net.
    await expect(store.getPlan({ id: 'seller-expired', provider: 'mock' })).resolves.toBe(
      'BASIC'
    );
  });

  it('keeps the plan while the paid period is still current', async () => {
    const store = createSubscriptionStore({
      now: () => '2026-07-10T00:00:00.000Z'
    });

    await store.activatePro(
      { id: 'seller-active', provider: 'mock' },
      { currentPeriodEnd: '2026-08-01T00:00:00.000Z' }
    );

    await expect(store.getPlan({ id: 'seller-active', provider: 'mock' })).resolves.toBe('PRO');
  });

  it('persists mock Starter activation for a user', async () => {
    const store = createSubscriptionStore();

    await expect(
      store.activatePlan({ id: 'seller-starter', provider: 'mock' }, 'STARTER')
    ).resolves.toMatchObject({
      userId: 'seller-starter',
      plan: 'STARTER',
      status: 'ACTIVE'
    });
    await expect(store.getPlan({ id: 'seller-starter', provider: 'mock' })).resolves.toBe(
      'STARTER'
    );
  });

  it('updates a subscription status by billing subscription id', async () => {
    const store = createSubscriptionStore({
      now: () => '2026-06-04T00:00:00.000Z'
    });

    await store.activatePro(
      { id: 'seller-store', provider: 'mock' },
      {
        billingSubscriptionId: 'google-play:android-purchase-token'
      }
    );

    await expect(
      store.updateStatusByBillingSubscriptionId({
        billingSubscriptionId: 'google-play:android-purchase-token',
        status: 'CANCELED'
      })
    ).resolves.toMatchObject({
      userId: 'seller-store',
      plan: 'PRO',
      status: 'CANCELED'
    });
    await expect(store.getPlan({ id: 'seller-store', provider: 'mock' })).resolves.toBe('BASIC');
  });
});
