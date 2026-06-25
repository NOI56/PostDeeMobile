import { describe, expect, it } from 'vitest';

import { StorePurchaseVerificationError } from './storePurchaseService.js';
import { createGooglePlayPurchaseVerifier } from './googlePlayPurchaseVerifier.js';

describe('createGooglePlayPurchaseVerifier', () => {
  it('verifies an active Google Play subscription through subscriptionsv2.get', async () => {
    const requestedUrls: string[] = [];
    const requestedAuthHeaders: string[] = [];
    const verifier = createGooglePlayPurchaseVerifier({
      packageName: 'com.postdee',
      accessTokenProvider: async () => 'google-access-token',
      fetchImpl: async (url, init) => {
        requestedUrls.push(url);
        requestedAuthHeaders.push(String(init.headers?.Authorization));

        return {
          ok: true,
          status: 200,
          json: async () => ({
            subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
            lineItems: [
              {
                productId: 'postdee_pro_monthly',
                expiryTime: '2026-07-04T00:00:00Z'
              }
            ]
          })
        };
      },
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    const purchase = await verifier.verify({
      platform: 'ANDROID',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token'
    });

    expect(requestedUrls).toEqual([
      'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.postdee/purchases/subscriptionsv2/tokens/android-purchase-token'
    ]);
    expect(requestedAuthHeaders).toEqual(['Bearer google-access-token']);
    expect(purchase).toEqual({
      provider: 'google-play',
      platform: 'ANDROID',
      productId: 'postdee_pro_monthly',
      purchaseToken: 'android-purchase-token',
      verifiedAt: '2026-06-04T00:00:00.000Z'
    });
  });

  it('rejects inactive Google Play subscriptions before Pro activation', async () => {
    const verifier = createGooglePlayPurchaseVerifier({
      packageName: 'com.postdee',
      accessTokenProvider: async () => 'google-access-token',
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          subscriptionState: 'SUBSCRIPTION_STATE_CANCELED',
          lineItems: [
            {
              productId: 'postdee_pro_monthly',
              expiryTime: '2026-07-04T00:00:00Z'
            }
          ]
        })
      }),
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    await expect(
      verifier.verify({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      })
    ).rejects.toMatchObject({
      statusCode: 402,
      code: 'GOOGLE_PLAY_SUBSCRIPTION_NOT_ACTIVE'
    } satisfies Partial<StorePurchaseVerificationError>);
  });

  it('rejects Google Play subscriptions for another product id', async () => {
    const verifier = createGooglePlayPurchaseVerifier({
      packageName: 'com.postdee',
      accessTokenProvider: async () => 'google-access-token',
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({
          subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
          lineItems: [
            {
              productId: 'other_product',
              expiryTime: '2026-07-04T00:00:00Z'
            }
          ]
        })
      }),
      now: () => new Date('2026-06-04T00:00:00.000Z')
    });

    await expect(
      verifier.verify({
        platform: 'ANDROID',
        productId: 'postdee_pro_monthly',
        purchaseToken: 'android-purchase-token'
      })
    ).rejects.toMatchObject({
      statusCode: 400,
      code: 'GOOGLE_PLAY_PRODUCT_MISMATCH'
    } satisfies Partial<StorePurchaseVerificationError>);
  });
});
