import { describe, expect, it, vi } from 'vitest';

import {
  createPrismaSocialConnectionRepository,
  type PrismaSocialConnectionClient,
  type PrismaSocialConnectionTransaction
} from './prismaSocialConnectionRepository.js';
import {
  PostPeerProfileOwnershipConflictError,
  type CompleteSocialConnectAttemptInput,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

const attemptRow = {
  userId: 'owner-a', platform: 'TIKTOK', profileId: 'profile-a', nonceHash: 'hash-a',
  expiresAt: new Date('2026-10-23T10:15:00.000Z'), baselineIntegrationIds: ['integration-old']
};
const completion: CompleteSocialConnectAttemptInput = {
  userId: 'owner-a', platform: 'TIKTOK', profileId: 'profile-a', nonceHash: 'hash-a',
  integration: { postPeerAccountId: 'integration-new', externalAccountId: 'external-new' },
  now: '2026-10-23T10:01:00.000Z'
};

const createPrisma = (
  delegate: Partial<PrismaSocialConnectionClient['socialConnection']>,
  profileDelegate: Partial<PrismaSocialConnectionClient['postPeerProfile']> = {},
  attemptDelegate: Partial<PrismaSocialConnectionClient['socialConnectAttempt']> = {}
): PrismaSocialConnectionClient => {
  const transaction: PrismaSocialConnectionTransaction = {
  socialConnection: {
    findMany: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
      .mockResolvedValue([]),
    findUnique: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['findUnique']>()
      .mockResolvedValue(null),
    upsert: vi.fn<PrismaSocialConnectionClient['socialConnection']['upsert']>(),
    deleteMany: vi
      .fn<PrismaSocialConnectionClient['socialConnection']['deleteMany']>()
      .mockResolvedValue({ count: 0 }),
    ...delegate
  },
  postPeerProfile: {
    findUnique: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
      .mockResolvedValue(null),
    create: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
      .mockResolvedValue({ profileId: 'profile-1' }),
    deleteMany: vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['deleteMany']>()
      .mockResolvedValue({ count: 0 }),
    ...profileDelegate
  },
  managedUploadOwner: {
    upsert: vi.fn().mockResolvedValue({ status: 'ACTIVE' }),
    updateMany: vi.fn().mockResolvedValue({ count: 1 })
  },
  socialConnectAttempt: {
    findUnique: vi.fn().mockResolvedValue(null),
    upsert: vi.fn(),
    deleteMany: vi.fn().mockResolvedValue({ count: 0 }),
    ...attemptDelegate
  }
  };
  return { ...transaction, $transaction: vi.fn(async (operation) => operation(transaction)) };
};

describe('createPrismaSocialConnectionRepository', () => {
  it('reads a coherent disconnect snapshot under the owner lock without consuming its nonce or deleting its link', async () => {
    const order: string[] = [];
    const prisma = createPrisma({ findUnique: vi.fn(async () => {
      order.push('read-connection');
      return { id: 'connection-a', userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old', displayName: null, connectedAt: new Date(completion.now), updatedAt: new Date(completion.now) };
    }) }, {}, { findUnique: vi.fn(async () => { order.push('read-attempt'); return attemptRow; }) });
    prisma.managedUploadOwner.updateMany = vi.fn(async () => { order.push('owner-lock'); return { count: 1 }; });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.getDisconnectSnapshot({ userId: 'owner-a', platform: 'TIKTOK' })).resolves.toMatchObject({ connection: { postPeerAccountId: 'integration-old' }, nonceHash: 'hash-a' });
    expect(order).toEqual(['owner-lock', 'read-connection', 'read-attempt']);
    expect(prisma.socialConnectAttempt.findUnique).toHaveBeenCalledWith({ where: { userId_platform: { userId: 'owner-a', platform: 'TIKTOK' } } });
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
    expect(prisma.socialConnection.deleteMany).not.toHaveBeenCalled();
    expect(prisma.socialConnection.upsert).not.toHaveBeenCalled();
  });

  it('snapshots a pending attempt even when no local connection exists', async () => {
    const prisma = createPrisma({}, {}, { findUnique: vi.fn().mockResolvedValue(attemptRow) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.getDisconnectSnapshot({ userId: 'owner-a', platform: 'TIKTOK' })).resolves.toEqual({ nonceHash: 'hash-a' });
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
  });
  it.each([false, true])('does not overwrite or remove a newer stored binding using stale maintenance (missing integration: %s)', async (missing) => {
    const prisma = createPrisma({ findUnique: vi.fn().mockResolvedValue({
      id: 'connection-a', userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-new', externalAccountId: 'external-new', displayName: null,
      connectedAt: new Date(completion.now), updatedAt: new Date(completion.now)
    }) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.reconcileExistingConnection({ userId: 'owner-a', platform: 'TIKTOK', expectedPostPeerAccountId: 'integration-old', expectedExternalAccountId: 'external-old',
      ...(missing ? {} : { integration: { postPeerAccountId: 'integration-old', externalAccountId: 'external-old' } })
    })).resolves.toBeUndefined();
    expect(prisma.socialConnection.upsert).not.toHaveBeenCalled();
    expect(prisma.socialConnection.deleteMany).not.toHaveBeenCalled();
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
  });

  it('retires the expected missing connection in an owner transaction without deleting attempts', async () => {
    const prisma = createPrisma({ findUnique: vi.fn().mockResolvedValue({
      id: 'connection-a', userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-old', externalAccountId: 'external-old', displayName: null,
      connectedAt: new Date(completion.now), updatedAt: new Date(completion.now)
    }) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await repository.reconcileExistingConnection({ userId: 'owner-a', platform: 'TIKTOK', expectedPostPeerAccountId: 'integration-old', expectedExternalAccountId: 'external-old' });
    expect(prisma.socialConnection.deleteMany).toHaveBeenCalledWith({ where: { userId: 'owner-a', platform: 'TIKTOK' } });
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
    expect(prisma.$transaction).toHaveBeenCalled();
  });
  it('consumes a matching nonce and writes the connection in the same owner-fenced transaction', async () => {
    const order: string[] = [];
    const prisma = createPrisma({ upsert: vi.fn(async () => {
      order.push('upsert');
      return { id: 'connection-a', userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-new', externalAccountId: 'external-new', displayName: null, connectedAt: new Date(completion.now), updatedAt: new Date(completion.now) };
    }) }, {}, {
      findUnique: vi.fn().mockResolvedValue(attemptRow),
      deleteMany: vi.fn(async () => { order.push('consume'); return { count: 1 }; })
    });
    prisma.managedUploadOwner.updateMany = vi.fn(async () => { order.push('owner-lock'); return { count: 1 }; });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    expect((await repository.completeConnectAttempt(completion))?.postPeerAccountId).toBe('integration-new');
    expect(order).toEqual(['owner-lock', 'consume', 'upsert']);
    expect(prisma.socialConnectAttempt.deleteMany).toHaveBeenCalledWith({ where: {
      userId: 'owner-a', platform: 'TIKTOK', profileId: 'profile-a', nonceHash: 'hash-a', expiresAt: { gt: new Date(completion.now) }
    } });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), { isolationLevel: 'Serializable', maxWait: 5000, timeout: 10000 });
  });

  it.each([
    ['wrong owner', { userId: 'owner-b' }],
    ['wrong platform', { platform: 'YOUTUBE_SHORTS' }],
    ['wrong profile', { profileId: 'profile-b' }],
    ['wrong nonce', { nonceHash: 'hash-b' }],
    ['expired', { now: '2026-10-23T10:15:00.000Z' }],
    ['pre-existing integration', { integration: { postPeerAccountId: 'integration-old' } }]
  ] as const)('does not consume or write for %s completion', async (_label, override) => {
    const prisma = createPrisma({}, {}, { findUnique: vi.fn().mockResolvedValue(attemptRow) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.completeConnectAttempt({ ...completion, ...override })).resolves.toBeUndefined();
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
    expect(prisma.socialConnection.upsert).not.toHaveBeenCalled();
  });

  it('does not write if another refresh already consumed the conditional nonce', async () => {
    const prisma = createPrisma({}, {}, { findUnique: vi.fn().mockResolvedValue(attemptRow), deleteMany: vi.fn().mockResolvedValue({ count: 0 }) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.completeConnectAttempt(completion)).resolves.toBeUndefined();
    expect(prisma.socialConnection.upsert).not.toHaveBeenCalled();
  });

  it('throws a completion collision out of the transaction so its nonce deletion rolls back', async () => {
    const prisma = createPrisma({ upsert: vi.fn().mockRejectedValue(Object.assign(new Error('unique'), { code: 'P2002' })) }, {}, {
      findUnique: vi.fn().mockResolvedValue(attemptRow), deleteMany: vi.fn().mockResolvedValue({ count: 1 })
    });
    const rejectedTransaction = vi.fn();
    const execute = prisma.$transaction;
    prisma.$transaction = async (operation, options) => {
      try { return await execute(operation, options); }
      catch (error) { rejectedTransaction(error); throw error; }
    };
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.completeConnectAttempt(completion)).rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
    expect(rejectedTransaction).toHaveBeenCalledWith(expect.objectContaining({ code: 'P2002' }));
  });

  it('replaces the one user-platform attempt and stores only a hash and a baseline snapshot', async () => {
    const prisma = createPrisma({});
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await repository.beginConnectAttempt({ ...attemptRow, platform: 'TIKTOK', expiresAt: attemptRow.expiresAt.toISOString() });
    expect(prisma.socialConnectAttempt.upsert).toHaveBeenCalledWith({
      where: { userId_platform: { userId: 'owner-a', platform: 'TIKTOK' } },
      create: attemptRow,
      update: { profileId: 'profile-a', nonceHash: 'hash-a', expiresAt: attemptRow.expiresAt, baselineIntegrationIds: ['integration-old'] }
    });
  });

  it('does not expose another owner attempt and scopes stale cleanup to its nonce', async () => {
    const prisma = createPrisma({}, {}, { findUnique: vi.fn().mockResolvedValue(attemptRow) });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.getConnectAttempt({ userId: 'owner-b', nonceHash: 'hash-a' })).resolves.toBeUndefined();
    await repository.cancelConnectAttempt({ userId: 'owner-a', platform: 'TIKTOK', nonceHash: 'stale-hash' });
    expect(prisma.socialConnectAttempt.deleteMany).toHaveBeenCalledWith({ where: { userId: 'owner-a', platform: 'TIKTOK', nonceHash: 'stale-hash' } });
  });

  it.each(['DELETING', 'DELETED'] as const)('never writes an attempt or connection after the owner becomes %s', async (status) => {
    const prisma = createPrisma({});
    prisma.managedUploadOwner.upsert = vi.fn().mockResolvedValue({ status });
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await expect(repository.beginConnectAttempt({ ...attemptRow, platform: 'TIKTOK', expiresAt: attemptRow.expiresAt.toISOString() })).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(repository.completeConnectAttempt(completion)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(repository.upsert({ userId: 'owner-a', platform: 'TIKTOK', postPeerAccountId: 'integration-a' })).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(prisma.socialConnectAttempt.upsert).not.toHaveBeenCalled();
    expect(prisma.socialConnectAttempt.deleteMany).not.toHaveBeenCalled();
    expect(prisma.socialConnection.upsert).not.toHaveBeenCalled();
  });

  it('disconnect and account deletion remove pending attempts', async () => {
    const prisma = createPrisma({});
    const repository = createPrismaSocialConnectionRepository({ prisma });
    await repository.disconnect({ userId: 'owner-a', platform: 'TIKTOK' });
    expect(prisma.socialConnectAttempt.deleteMany).toHaveBeenLastCalledWith({ where: { userId: 'owner-a', platform: 'TIKTOK' } });
    await repository.deleteAllForUser?.('owner-a');
    expect(prisma.socialConnectAttempt.deleteMany).toHaveBeenLastCalledWith({ where: { userId: 'owner-a' } });
  });
  it.each(['platform_externalAccountId', 'postPeerAccountId'])('maps %s account uniqueness conflicts to a safe ownership error', async (target) => {
    const prisma = createPrisma({ upsert: vi.fn().mockRejectedValue(Object.assign(new Error('Unique constraint failed'), { code: 'P2002', meta: { target } })) });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.upsert({ userId: 'owner-b', platform: 'TIKTOK', postPeerAccountId: 'integration-owned', externalAccountId: 'external-owned' }))
      .rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
  });
  it.each(['YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const)('returns an opaque changing %s account revision', async (platform) => {
    const record = { id: 'local-connection', userId: 'owner', platform, postPeerAccountId: 'provider-secret-old', displayName: null, externalAccountId: null, connectedAt: new Date('2026-10-15T10:00:00.000Z'), updatedAt: new Date('2026-10-15T10:00:00.000Z') };
    const findMany = vi.fn<PrismaSocialConnectionClient['socialConnection']['findMany']>().mockResolvedValue([record]);
    const repository = createPrismaSocialConnectionRepository({ prisma: createPrisma({ findMany }) });
    const first = (await repository.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(first.connectionRevision).toMatch(/^[a-f0-9]{64}$/);
    findMany.mockResolvedValue([{ ...record, postPeerAccountId: 'provider-secret-new' }]);
    const next = (await repository.listForUser('owner')).find((entry) => entry.platform === platform)!;
    expect(next.connectionId).toBe(first.connectionId);
    expect(next.connectionRevision).not.toBe(first.connectionRevision);
    expect(JSON.stringify(next)).not.toContain('provider-secret');
  });
  it('lists connected social accounts with disconnected defaults', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            id: 'local-connection-1',
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'postpeer-tiktok-1',
            displayName: 'Seller TikTok',
            externalAccountId: '@seller-1',
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        platform: 'TIKTOK',
        connected: true,
        connectionId: 'local-connection-1',
        connectionRevision: expect.stringMatching(/^[a-f0-9]{64}$/),
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1',
        connectedAt: '2026-06-26T02:00:00.000Z'
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
    expect(prisma.socialConnection.findMany).toHaveBeenCalledWith({
      where: {
        userId: 'seller-1',
        platform: {
          in: supportedSocialConnectionPlatforms
        }
      },
      select: {
        id: true,
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('does not map unsupported Prisma platform rows into domain connections', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'SHOPEE_VIDEO',
            postPeerAccountId: 'postpeer-shopee-1',
            displayName: 'Seller Shopee',
            externalAccountId: 'seller-shopee',
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual(
      supportedSocialConnectionPlatforms.map((platform) => ({
        platform,
        connected: false
      }))
    );
  });

  it('upserts a social connection by user and platform', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: 'Seller TikTok',
          externalAccountId: '@seller-1',
          connectedAt,
          updatedAt
        })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.upsert({
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
      connectedAt: '2026-06-26T02:00:00.000Z',
      updatedAt: '2026-06-26T03:00:00.000Z'
    });
    expect(prisma.socialConnection.upsert).toHaveBeenCalledWith({
      where: {
        userId_platform: {
          userId: 'seller-1',
          platform: 'TIKTOK'
        }
      },
      update: {
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      },
      create: {
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: 'Seller TikTok',
        externalAccountId: '@seller-1'
      },
      select: {
        id: true,
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('normalizes empty optional metadata to null before upserting', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      upsert: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['upsert']>()
        .mockResolvedValue({
          userId: 'seller-1',
          platform: 'TIKTOK',
          postPeerAccountId: 'postpeer-tiktok-1',
          displayName: null,
          externalAccountId: null,
          connectedAt,
          updatedAt
        })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.upsert({
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
      updatedAt: '2026-06-26T03:00:00.000Z'
    });
    expect(prisma.socialConnection.upsert).toHaveBeenCalledWith({
      where: {
        userId_platform: {
          userId: 'seller-1',
          platform: 'TIKTOK'
        }
      },
      update: {
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: null,
        externalAccountId: null
      },
      create: {
        userId: 'seller-1',
        platform: 'TIKTOK',
        postPeerAccountId: 'postpeer-tiktok-1',
        displayName: null,
        externalAccountId: null
      },
      select: {
        id: true,
        userId: true,
        platform: true,
        postPeerAccountId: true,
        displayName: true,
        externalAccountId: true,
        connectedAt: true,
        updatedAt: true
      }
    });
  });

  it('omits null optional metadata returned from Prisma', async () => {
    const connectedAt = new Date('2026-06-26T02:00:00.000Z');
    const updatedAt = new Date('2026-06-26T03:00:00.000Z');
    const prisma = createPrisma({
      findMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['findMany']>()
        .mockResolvedValue([
          {
            userId: 'seller-1',
            platform: 'TIKTOK',
            postPeerAccountId: 'postpeer-tiktok-1',
            displayName: null,
            externalAccountId: null,
            connectedAt,
            updatedAt
          }
        ])
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.listForUser('seller-1')).resolves.toEqual([
      {
        platform: 'TIKTOK',
        connected: true,
        connectionRevision: expect.stringMatching(/^[a-f0-9]{64}$/),
        connectedAt: '2026-06-26T02:00:00.000Z'
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
  });

  it('returns whether disconnect removed a connection', async () => {
    const prisma = createPrisma({
      deleteMany: vi
        .fn<PrismaSocialConnectionClient['socialConnection']['deleteMany']>()
        .mockResolvedValue({ count: 1 })
    });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.disconnect({
        userId: 'seller-1',
        platform: 'TIKTOK'
      })
    ).resolves.toBe(true);
  });

  it('reads the stored PostPeer profile id for a user', async () => {
    const prisma = createPrisma(
      {},
      {
        findUnique: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
          .mockResolvedValue({ profileId: 'profile-1' })
      }
    );
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(repository.getProfileId('seller-1')).resolves.toBe('profile-1');
    expect(prisma.postPeerProfile.findUnique).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: { profileId: true }
    });
  });

  it('claims the PostPeer profile id for a user', async () => {
    const prisma = createPrisma({});
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-1' })
    ).resolves.toBe('profile-1');

    expect(prisma.postPeerProfile.create).toHaveBeenCalledWith({
      data: { userId: 'seller-1', profileId: 'profile-1' },
      select: { profileId: true }
    });
  });

  it('preserves same-user PostPeer profile assignment idempotence', async () => {
    const prismaError = Object.assign(new Error('Unique constraint failed'), {
      code: 'P2002'
    });
    const create = vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
      .mockResolvedValueOnce({ profileId: 'profile-1' })
      .mockRejectedValueOnce(prismaError);
    const findUnique = vi
      .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
      .mockResolvedValue({ profileId: 'profile-1' });
    const prisma = createPrisma({}, { create, findUnique });
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-1' })
    ).resolves.toBe('profile-1');
    await expect(
      repository.setProfileId({ userId: 'seller-1', profileId: 'profile-race-loser' })
    ).resolves.toBe('profile-1');
    expect(create).toHaveBeenCalledTimes(2);
    expect(findUnique).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: { profileId: true }
    });
  });

  it('maps Prisma profileId unique conflicts to an ownership domain error', async () => {
    const prismaError = Object.assign(new Error('Unique constraint failed'), {
      code: 'P2002',
      meta: { target: ['profileId'] }
    });
    const prisma = createPrisma(
      {},
      {
        create: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['create']>()
          .mockRejectedValue(prismaError),
        findUnique: vi
          .fn<PrismaSocialConnectionClient['postPeerProfile']['findUnique']>()
          .mockResolvedValue(null)
      }
    );
    const repository = createPrismaSocialConnectionRepository({ prisma });

    await expect(
      repository.setProfileId({ userId: 'seller-2', profileId: 'profile-owned' })
    ).rejects.toBeInstanceOf(PostPeerProfileOwnershipConflictError);
  });
});
