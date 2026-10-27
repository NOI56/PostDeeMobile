import { describe, expect, it, vi } from 'vitest';

import { createInMemoryDeviceTokenStore, maxDeviceTokensPerUser } from './deviceTokenStore.js';
import {
  createPrismaDeviceTokenRepository,
  type PrismaDeviceTokenClient
} from './prismaDeviceTokenRepository.js';

describe('in-memory device token store', () => {
  it('keeps only the newest tokens for each user', async () => {
    let tick = 0;
    const store = createInMemoryDeviceTokenStore({
      now: () => new Date(Date.UTC(2026, 9, 27, 0, 0, tick++)).toISOString()
    });
    await store.register({ userId: 'other-user', token: 'other-token' });

    for (let index = 0; index <= maxDeviceTokensPerUser; index += 1) {
      await store.register({ userId: 'busy-user', token: `token-${index}` });
    }
    // Re-registering refreshes a token, so it is no longer the oldest.
    await store.register({ userId: 'busy-user', token: 'token-1' });
    await store.register({ userId: 'busy-user', token: 'token-new' });

    const tokens = (await store.listForUser('busy-user')).map((device) => device.token);
    expect(tokens).toHaveLength(maxDeviceTokensPerUser);
    expect(tokens).not.toContain('token-0');
    expect(tokens).not.toContain('token-2');
    expect(tokens).toContain('token-1');
    expect(tokens).toContain('token-new');
    expect(await store.listForUser('other-user')).toHaveLength(1);
  });

  it('removes only the given tokens of the given user', async () => {
    const store = createInMemoryDeviceTokenStore();
    await store.register({ userId: 'u1', token: 'stale' });
    await store.register({ userId: 'u1', token: 'live' });
    await store.register({ userId: 'u2', token: 'other' });

    await store.removeTokens({ userId: 'u1', tokens: ['stale', 'other'] });

    expect((await store.listForUser('u1')).map((device) => device.token)).toEqual(['live']);
    expect(await store.listForUser('u2')).toHaveLength(1);
  });
});

describe('Prisma device token repository', () => {
  const createPrisma = () => {
    const record = {
      userId: 'u1', token: 't1', platform: null, updatedAt: new Date('2026-10-27T00:00:00.000Z')
    };
    return {
      deviceToken: {
        upsert: vi.fn(async () => record),
        findMany: vi.fn(async () => [{ id: 'old-1' }, { id: 'old-2' }]),
        deleteMany: vi.fn(async () => ({ count: 2 }))
      }
    };
  };

  it('deletes tokens beyond the per-user cap after registering', async () => {
    const prisma = createPrisma();
    const repository = createPrismaDeviceTokenRepository({
      prisma: prisma as unknown as PrismaDeviceTokenClient
    });

    await repository.register({ userId: 'u1', token: 't1' });

    expect(prisma.deviceToken.findMany).toHaveBeenCalledWith({
      where: { userId: 'u1' },
      orderBy: { updatedAt: 'desc' },
      skip: maxDeviceTokensPerUser,
      select: { id: true }
    });
    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ['old-1', 'old-2'] } }
    });
  });

  it('removes reported tokens scoped to their owner', async () => {
    const prisma = createPrisma();
    const repository = createPrismaDeviceTokenRepository({
      prisma: prisma as unknown as PrismaDeviceTokenClient
    });

    await repository.removeTokens({ userId: 'u1', tokens: ['stale-1'] });

    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'u1', token: { in: ['stale-1'] } }
    });
  });
});
