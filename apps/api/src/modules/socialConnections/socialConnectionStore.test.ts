import { describe, expect, it } from 'vitest';

import {
  createInMemorySocialConnectionStore,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

describe('createInMemorySocialConnectionStore', () => {
  it('lists every supported platform as disconnected for a new user', async () => {
    const store = createInMemorySocialConnectionStore();

    await expect(store.listForUser('seller-new')).resolves.toEqual(
      supportedSocialConnectionPlatforms.map((platform) => ({
        platform,
        connected: false
      }))
    );
  });

  it('upserts a TikTok connection scoped to one seller account', async () => {
    const connectedAt = '2026-06-26T02:00:00.000Z';
    const store = createInMemorySocialConnectionStore({
      now: () => connectedAt
    });

    await expect(
      store.upsert({
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-1',
      displayName: 'Seller TikTok',
      externalAccountId: '@seller-1',
      connectedAt,
      updatedAt: connectedAt
    });

    await expect(store.listForUser('seller-1')).resolves.toEqual([
      {
        platform: 'TIKTOK',
        connected: true,
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1',
        connectedAt
      },
      {
        platform: 'YOUTUBE_SHORTS',
        connected: false
      },
      {
        platform: 'INSTAGRAM_REELS',
        connected: false
      },
      {
        platform: 'FACEBOOK_REELS',
        connected: false
      }
    ]);
    await expect(
      store.getAccountId({
        userId: 'seller-1',
        platform: 'TIKTOK'
      })
    ).resolves.toBe('postpeer-tiktok-1');
    await expect(
      store.getAccountId({
        userId: 'seller-2',
        platform: 'TIKTOK'
      })
    ).resolves.toBeUndefined();
  });

  it('preserves the original connected time when updating an existing connection', async () => {
    let currentTime = '2026-06-26T02:00:00.000Z';
    const store = createInMemorySocialConnectionStore({
      now: () => currentTime
    });

    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-1',
      displayName: 'Old TikTok'
    });
    currentTime = '2026-06-26T03:00:00.000Z';

    await expect(
      store.upsert({
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-updated',
        displayName: 'Updated TikTok'
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-updated',
      displayName: 'Updated TikTok',
      connectedAt: '2026-06-26T02:00:00.000Z',
      updatedAt: '2026-06-26T03:00:00.000Z'
    });
  });

  it('omits blank optional metadata when storing a connection', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T02:00:00.000Z'
    });

    await expect(
      store.upsert({
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: '',
        externalAccountId: '   '
      })
    ).resolves.toEqual({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-1',
      connectedAt: '2026-06-26T02:00:00.000Z',
      updatedAt: '2026-06-26T02:00:00.000Z'
    });
  });

  it('disconnects one platform and deletes every connection for a user', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T02:00:00.000Z'
    });

    await store.upsert({
      userId: 'seller-1',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-1'
    });
    await store.upsert({
      userId: 'seller-1',
      platform: 'YOUTUBE_SHORTS',
      postPeerAccountId: 'postpeer-youtube-1'
    });
    await store.upsert({
      userId: 'seller-2',
      platform: 'TIKTOK',
      postPeerAccountId: 'postpeer-tiktok-2'
    });

    await expect(
      store.disconnect({
        userId: 'seller-1',
        platform: 'TIKTOK'
      })
    ).resolves.toBe(true);

    await expect(
      store.getAccountId({
        userId: 'seller-1',
        platform: 'TIKTOK'
      })
    ).resolves.toBeUndefined();
    await expect(
      store.getAccountId({
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS'
      })
    ).resolves.toBe('postpeer-youtube-1');

    await store.deleteAllForUser?.('seller-1');

    await expect(store.listForUser('seller-1')).resolves.toEqual(
      supportedSocialConnectionPlatforms.map((platform) => ({
        platform,
        connected: false
      }))
    );
    await expect(
      store.getAccountId({
        userId: 'seller-2',
        platform: 'TIKTOK'
      })
    ).resolves.toBe('postpeer-tiktok-2');
  });
});
