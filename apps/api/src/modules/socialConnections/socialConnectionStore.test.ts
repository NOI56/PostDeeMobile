import { describe, expect, it } from 'vitest';

import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';

describe('createInMemorySocialConnectionStore', () => {
  it('lists every supported platform as disconnected for a new user', async () => {
    const store = createInMemorySocialConnectionStore();

    await expect(store.listForUser('seller-new')).resolves.toEqual([
      {
        userId: 'seller-new',
        platform: 'TIKTOK',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-new',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-new',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-new',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
      }
    ]);
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
      status: 'CONNECTED',
      postPeerAccountId: 'postpeer-tiktok-1',
      displayName: 'Seller TikTok',
      externalAccountId: '@seller-1',
      connectedAt
    });

    await expect(store.listForUser('seller-1')).resolves.toEqual([
      {
        userId: 'seller-1',
        platform: 'TIKTOK',
        status: 'CONNECTED',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1',
        connectedAt
      },
      {
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
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
      status: 'CONNECTED',
      postPeerAccountId: 'postpeer-tiktok-updated',
      displayName: 'Updated TikTok',
      connectedAt: '2026-06-26T02:00:00.000Z'
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
      status: 'CONNECTED',
      postPeerAccountId: 'postpeer-tiktok-1',
      connectedAt: '2026-06-26T02:00:00.000Z'
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

    await store.disconnect({
      userId: 'seller-1',
      platform: 'TIKTOK'
    });

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

    await store.deleteAllForUser('seller-1');

    await expect(store.listForUser('seller-1')).resolves.toEqual([
      {
        userId: 'seller-1',
        platform: 'TIKTOK',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'YOUTUBE_SHORTS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'INSTAGRAM_REELS',
        status: 'DISCONNECTED'
      },
      {
        userId: 'seller-1',
        platform: 'FACEBOOK_REELS',
        status: 'DISCONNECTED'
      }
    ]);
    await expect(
      store.getAccountId({
        userId: 'seller-2',
        platform: 'TIKTOK'
      })
    ).resolves.toBe('postpeer-tiktok-2');
  });
});
