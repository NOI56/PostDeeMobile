import { describe, expect, it } from 'vitest';

import {
  PostPeerProfileOwnershipConflictError,
  createInMemorySocialConnectionStore,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

describe('createInMemorySocialConnectionStore', () => {
  it.each(['YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const)('revisions bind %s to the owner and current provider account', async (platform) => {
    const store = createInMemorySocialConnectionStore({ now: () => '2026-10-15T10:00:00.000Z' });
    const original = await store.upsert({ userId: 'owner', platform, postPeerAccountId: 'provider-secret-old' });
    const first = (await store.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(first.connectionRevision).toMatch(/^[a-f0-9]{64}$/);
    const replacement = await store.upsert({ userId: 'owner', platform, postPeerAccountId: 'provider-secret-new' });
    const next = (await store.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(replacement.id).toBe(original.id);
    expect(next.connectionRevision).not.toBe(first.connectionRevision);
    await store.upsert({ userId: 'other-owner', platform, postPeerAccountId: 'provider-secret-new' });
    expect((await store.listForUser('other-owner')).find((entry) => entry.platform === platform)?.connectionRevision).not.toBe(next.connectionRevision);
    expect(JSON.stringify(next)).not.toContain('provider-secret');
  });
  it('keeps assigning the same PostPeer profile to the same user idempotently', async () => {
    const store = createInMemorySocialConnectionStore();

    await store.setProfileId({ userId: 'seller-1', profileId: 'profile-shared' });
    await expect(
      store.setProfileId({ userId: 'seller-1', profileId: 'profile-shared' })
    ).resolves.toBe('profile-shared');
    await expect(
      store.setProfileId({ userId: 'seller-1', profileId: 'profile-race-loser' })
    ).resolves.toBe('profile-shared');
    await expect(store.getProfileId('seller-1')).resolves.toBe('profile-shared');
  });

  it('atomically rejects two users racing to claim the same PostPeer profile', async () => {
    const store = createInMemorySocialConnectionStore();
    const results = await Promise.allSettled([
      store.setProfileId({ userId: 'seller-1', profileId: 'profile-shared' }),
      store.setProfileId({ userId: 'seller-2', profileId: 'profile-shared' })
    ]);

    expect(results.filter(({ status }) => status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find(({ status }) => status === 'rejected');
    expect(rejected).toMatchObject({
      status: 'rejected',
      reason: expect.any(PostPeerProfileOwnershipConflictError)
    });
    await expect(store.getProfileId('seller-1')).resolves.toBe('profile-shared');
    await expect(store.getProfileId('seller-2')).resolves.toBeUndefined();
  });

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
      id: expect.any(String),
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
        connectionId: expect.any(String),
        connectionRevision: expect.stringMatching(/^[a-f0-9]{64}$/),
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
      id: expect.any(String),
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
      id: expect.any(String),
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
