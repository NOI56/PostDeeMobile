import { describe, expect, it, vi } from 'vitest';

import {
  RevenueCatSubscriberProviderError,
  RevenueCatSubscriberUnavailableError,
  createRevenueCatSubscriberClient
} from './revenueCatSubscriberClient.js';

describe('createRevenueCatSubscriberClient', () => {
  it('requires a server-side RevenueCat REST API key', async () => {
    const client = createRevenueCatSubscriberClient({
      now: () => new Date('2026-07-15T00:00:00.000Z')
    });

    await expect(client.loadSubscriber('seller-1')).rejects.toBeInstanceOf(
      RevenueCatSubscriberUnavailableError
    );
  });

  it('loads only active entitlements while honoring lifetime and grace access', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        request_date_ms: Date.parse('2026-07-15T00:00:00.000Z'),
        subscriber: {
          entitlements: {
            pro: {
              product_identifier: 'postdee_pro_monthly',
              expires_date: '2026-08-15T00:00:00.000Z'
            },
            expired: {
              product_identifier: 'expired_product',
              expires_date: '2026-06-15T00:00:00.000Z'
            },
            lifetime: {
              product_identifier: 'lifetime_product',
              expires_date: null
            },
            starter: {
              product_identifier: 'postdee_starter_monthly',
              expires_date: '2026-07-14T00:00:00.000Z'
            }
          },
          subscriptions: {
            postdee_starter_monthly: {
              grace_period_expires_date: '2026-07-20T00:00:00.000Z'
            }
          }
        }
      })
    });
    const client = createRevenueCatSubscriberClient({
      apiKey: 'rc-secret-key',
      baseUrl: 'https://api.revenuecat.test/v1/',
      fetchImpl,
      now: () => new Date('2026-07-15T00:00:00.000Z')
    });

    await expect(client.loadSubscriber('seller/one')).resolves.toEqual({
      activeEntitlements: [
        {
          id: 'pro',
          productId: 'postdee_pro_monthly',
          expiresAt: '2026-08-15T00:00:00.000Z'
        },
        {
          id: 'lifetime',
          productId: 'lifetime_product'
        },
        {
          id: 'starter',
          productId: 'postdee_starter_monthly',
          expiresAt: '2026-07-20T00:00:00.000Z'
        }
      ]
    });
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.revenuecat.test/v1/subscribers/seller%2Fone',
      {
        method: 'GET',
        headers: { Authorization: 'Bearer rc-secret-key' },
        signal: expect.any(AbortSignal)
      }
    );
  });

  it('fails closed when RevenueCat returns malformed customer data', async () => {
    const client = createRevenueCatSubscriberClient({
      apiKey: 'rc-secret-key',
      fetchImpl: vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({ subscriber: { entitlements: [] } })
      })
    });

    await expect(client.loadSubscriber('seller-1')).rejects.toBeInstanceOf(
      RevenueCatSubscriberProviderError
    );
  });

  it('does not expose RevenueCat upstream failures', async () => {
    const client = createRevenueCatSubscriberClient({
      apiKey: 'rc-secret-key',
      fetchImpl: vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        json: async () => ({ message: 'secret upstream detail' })
      })
    });

    await expect(client.loadSubscriber('seller-1')).rejects.toMatchObject({
      name: 'RevenueCatSubscriberProviderError',
      message: 'RevenueCat subscriber lookup failed'
    });
  });
});
