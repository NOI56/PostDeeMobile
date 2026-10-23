import { describe, expect, it } from 'vitest';

import {
  PostPeerProfileOwnershipConflictError,
  createInMemorySocialConnectionStore,
  type CompleteSocialConnectAttemptInput,
  type SocialConnectAttempt,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

const connectAttempt: SocialConnectAttempt = {
  userId: 'owner-a', platform: 'TIKTOK', profileId: 'profile-a', nonceHash: 'hash-a',
  expiresAt: '2026-10-23T10:15:00.000Z', baselineIntegrationIds: ['integration-old']
};
const completion: CompleteSocialConnectAttemptInput = {
  userId: 'owner-a', platform: 'TIKTOK', profileId: 'profile-a', nonceHash: 'hash-a',
  integration: { postPeerAccountId: 'integration-new', externalAccountId: 'external-new' },
  now: '2026-10-23T10:01:00.000Z'
};

describe('createInMemorySocialConnectionStore', () => {
  it('snapshots the current connection and pending nonce together without changing either', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old' });
    await store.beginConnectAttempt(connectAttempt);
    const snapshot = await store.getDisconnectSnapshot({ userId: 'owner-a', platform: 'TIKTOK' });
    expect(snapshot).toMatchObject({ connection: { userId: 'owner-a', postPeerAccountId: 'integration-old' }, nonceHash: 'hash-a' });
    await store.beginConnectAttempt({ ...connectAttempt, nonceHash: 'hash-new' });
    await store.cancelConnectAttempt({ userId: 'owner-a', platform: 'TIKTOK', nonceHash: snapshot.nonceHash });
    expect((await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-new' }))?.nonceHash).toBe('hash-new');
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.postPeerAccountId).toBe('integration-old');
    snapshot.connection!.postPeerAccountId = 'mutated-snapshot';
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.postPeerAccountId).toBe('integration-old');
  });

  it('returns only a pending nonce for an unlinked platform and nothing for another user', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    await expect(store.getDisconnectSnapshot({ userId: 'owner-a', platform: 'TIKTOK' })).resolves.toEqual({ nonceHash: 'hash-a' });
    await expect(store.getDisconnectSnapshot({ userId: 'owner-b', platform: 'TIKTOK' })).resolves.toEqual({});
  });
  it.each([false, true])('ignores a stale maintenance snapshot after a newer link completes (missing integration: %s)', async (missing) => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' });
    await store.beginConnectAttempt(connectAttempt);
    await store.completeConnectAttempt(completion);
    await expect(store.reconcileExistingConnection({ userId: 'owner-a', platform: 'TIKTOK', expectedPostPeerAccountId: 'integration-old', expectedExternalAccountId: 'external-old',
      ...(missing ? {} : { integration: { postPeerAccountId: 'integration-old', externalAccountId: 'external-old', displayName: 'Stale display name' } })
    })).resolves.toBeUndefined();
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.postPeerAccountId).toBe('integration-new');
  });

  it('retires only the expected missing connection while preserving a pending attempt', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' });
    await store.beginConnectAttempt(connectAttempt);
    await store.reconcileExistingConnection({ userId: 'owner-a', platform: 'TIKTOK', expectedPostPeerAccountId: 'integration-old', expectedExternalAccountId: 'external-old' });
    expect(await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' })).toBeUndefined();
    expect(await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' })).toEqual(connectAttempt);
    expect(await store.completeConnectAttempt(completion)).toBeDefined();
  });

  it('updates known account metadata but refuses to replace its provider or external identity', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' });
    const expected = { userId: 'owner-a', platform: 'TIKTOK' as const, expectedPostPeerAccountId: 'integration-old', expectedExternalAccountId: 'external-old' };
    expect((await store.reconcileExistingConnection({ ...expected, integration: { postPeerAccountId: 'integration-old', externalAccountId: 'external-old', displayName: 'Updated name' } }))?.displayName).toBe('Updated name');
    expect(await store.reconcileExistingConnection({ ...expected, integration: { postPeerAccountId: 'integration-new', externalAccountId: 'external-old' } })).toBeUndefined();
    expect(await store.reconcileExistingConnection({ ...expected, integration: { postPeerAccountId: 'integration-old', externalAccountId: 'external-new' } })).toBeUndefined();
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.displayName).toBe('Updated name');
  });
  it('consumes a matching connect attempt exactly once under concurrent refreshes', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    const results = await Promise.all([store.completeConnectAttempt(completion), store.completeConnectAttempt(completion)]);
    expect(results.filter(Boolean)).toHaveLength(1);
    await expect(store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' })).resolves.toBeUndefined();
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.postPeerAccountId).toBe('integration-new');
  });

  it.each([
    ['wrong owner', { userId: 'owner-b' }],
    ['wrong platform', { platform: 'YOUTUBE_SHORTS' }],
    ['wrong profile', { profileId: 'profile-b' }],
    ['wrong nonce', { nonceHash: 'hash-b' }],
    ['expired attempt', { now: '2026-10-23T10:15:00.000Z' }],
    ['invalid clock', { now: 'invalid' }],
    ['pre-existing integration', { integration: { postPeerAccountId: 'integration-old' } }]
  ] as const)('does not complete or consume an attempt for %s', async (_label, override) => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    await expect(store.completeConnectAttempt({ ...completion, ...override })).resolves.toBeUndefined();
    await expect(store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' })).resolves.toBeUndefined();
    await expect(store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' })).resolves.toEqual(connectAttempt);
  });

  it('never exposes another owner attempt and returns copies of baseline identifiers', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    await expect(store.getConnectAttempt({ userId: 'owner-b', nonceHash: 'hash-a' })).resolves.toBeUndefined();
    const first = await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' });
    first!.baselineIntegrationIds.push('integration-new');
    expect((await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' }))?.baselineIntegrationIds).toEqual(['integration-old']);
  });

  it('replacing an attempt makes an old completion and stale failure cleanup harmless', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    await store.beginConnectAttempt({ ...connectAttempt, nonceHash: 'hash-new' });
    await expect(store.completeConnectAttempt(completion)).resolves.toBeUndefined();
    await store.cancelConnectAttempt({ userId: 'owner-a', platform: 'TIKTOK', nonceHash: 'hash-a' });
    expect((await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-new' }))?.nonceHash).toBe('hash-new');
    expect(await store.completeConnectAttempt({ ...completion, nonceHash: 'hash-new' })).toBeDefined();
  });

  it('keeps the attempt unconsumed if completing it conflicts with an existing owner', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-b', platform: 'TIKTOK', postPeerAccountId: 'integration-b', externalAccountId: 'external-new' });
    await store.beginConnectAttempt(connectAttempt);
    await expect(store.completeConnectAttempt(completion)).rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
    expect(await store.getConnectAttempt({ userId: 'owner-a', nonceHash: 'hash-a' })).toEqual(connectAttempt);
    await expect(store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' })).resolves.toBeUndefined();
  });

  it.each(['disconnect', 'deleteAllForUser'] as const)('%s cancels pending attempts before they can recreate a link', async (operation) => {
    const store = createInMemorySocialConnectionStore();
    await store.beginConnectAttempt(connectAttempt);
    if (operation === 'disconnect') await store.disconnect({ userId: 'owner-a', platform: 'TIKTOK' });
    else await store.deleteAllForUser?.('owner-a');
    await expect(store.completeConnectAttempt(completion)).resolves.toBeUndefined();
  });

  it('releases both uniqueness claims when updating, disconnecting or deleting an owner', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' });
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-new', externalAccountId: 'external-new' });
    await expect(store.upsert({ userId: 'owner-b', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' })).resolves.toBeDefined();
    await store.disconnect({ userId: 'owner-b', platform: 'TIKTOK' });
    await expect(store.upsert({ userId: 'owner-c', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old' })).resolves.toBeDefined();
    await store.deleteAllForUser?.('owner-a');
    await expect(store.upsert({ userId: 'owner-d', platform: 'TIKTOK', postPeerAccountId: 'integration-new', externalAccountId: 'external-new' })).resolves.toBeDefined();
  });

  it('rejects a global provider integration collision across platforms', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-shared' });
    await expect(store.upsert({ userId: 'owner-a', platform: 'YOUTUBE_SHORTS', postPeerAccountId: 'integration-shared' })).rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
  });
  it('rejects claiming another owner external social account', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-a', externalAccountId: 'external-shared' });

    await expect(store.upsert({ userId: 'owner-b', platform: 'TIKTOK', postPeerAccountId: 'integration-b', externalAccountId: 'external-shared' }))
      .rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
    await expect(store.getConnection({ userId: 'owner-b', platform: 'TIKTOK' })).resolves.toBeUndefined();
    expect((await store.getConnection({ userId: 'owner-a', platform: 'TIKTOK' }))?.postPeerAccountId).toBe('integration-a');
  });

  it('rejects claiming another owner PostPeer integration even with a different external id', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-shared', externalAccountId: 'external-a' });

    await expect(store.upsert({ userId: 'owner-b', platform: 'TIKTOK', postPeerAccountId: 'integration-shared', externalAccountId: 'external-b' }))
      .rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
    await expect(store.getConnection({ userId: 'owner-b', platform: 'TIKTOK' })).resolves.toBeUndefined();
  });

  it('allows exactly one owner when two users race to claim a social account', async () => {
    const store = createInMemorySocialConnectionStore();
    const results = await Promise.allSettled(['owner-a', 'owner-b'].map((userId) => store.upsert({ userId, platform: 'TIKTOK', postPeerAccountId: `integration-${userId}`, externalAccountId: 'external-shared' })));

    expect(results.filter(({ status }) => status === 'fulfilled')).toHaveLength(1);
    expect(results.find(({ status }) => status === 'rejected')).toMatchObject({ status: 'rejected', reason: { name: 'SocialAccountAlreadyLinkedError' } });
  });
  it.each(['YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const)('revisions bind %s to the owner and current provider account', async (platform) => {
    const store = createInMemorySocialConnectionStore({ now: () => '2026-10-15T10:00:00.000Z' });
    const original = await store.upsert({ userId: 'owner', platform, postPeerAccountId: 'provider-secret-old' });
    const first = (await store.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(first.connectionRevision).toMatch(/^[a-f0-9]{64}$/);
    const replacement = await store.upsert({ userId: 'owner', platform, postPeerAccountId: 'provider-secret-new' });
    const next = (await store.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(replacement.id).toBe(original.id);
    expect(next.connectionRevision).not.toBe(first.connectionRevision);
    await store.disconnect({ userId: 'owner', platform });
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
