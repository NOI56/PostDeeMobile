import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createInMemoryDeviceTokenStore } from './deviceTokenStore.js';
import { createPrismaDeviceTokenRepository, type PrismaDeviceTokenClient } from './prismaDeviceTokenRepository.js';

// Device tokens are read in full by the publish notifier inside the shared API
// and scheduler process, so registration must not grow one owner's set forever.
describe('device token limits', () => {
  it('rejects tokens that are too long or not FCM-shaped', async () => {
    const app = createApp();

    const tooLong = await request(app)
      .post('/devices')
      .set('x-postdee-user-id', 'seller-device-shape')
      .send({ token: 'a'.repeat(4097), platform: 'ANDROID' })
      .expect(400);
    const badShape = await request(app)
      .post('/devices')
      .set('x-postdee-user-id', 'seller-device-shape')
      .send({ token: 'token with spaces <script>', platform: 'ANDROID' })
      .expect(400);
    await request(app)
      .post('/devices')
      .set('x-postdee-user-id', 'seller-device-shape')
      .send({ token: 'fcm-Token_123:APA91b-abc', platform: 'ANDROID' })
      .expect(200);

    expect(tooLong.body).toMatchObject({ status: 'error', code: 'DEVICE_TOKEN_INVALID' });
    expect(badShape.body).toMatchObject({ status: 'error', code: 'DEVICE_TOKEN_INVALID' });
  });

  it('keeps only the ten most recently registered tokens per owner in memory', async () => {
    let tick = 0;
    const store = createInMemoryDeviceTokenStore({
      now: () => new Date(Date.UTC(2026, 9, 24, 0, 0, tick++)).toISOString()
    });

    for (let index = 0; index < 12; index += 1) {
      await store.register({ userId: 'seller-many', token: `token-${index}` });
    }
    await store.register({ userId: 'seller-other', token: 'other-token' });

    const tokens = (await store.listForUser('seller-many')).map((record) => record.token).sort();
    expect(tokens).toHaveLength(10);
    expect(tokens).not.toContain('token-0');
    expect(tokens).not.toContain('token-1');
    expect(await store.listForUser('seller-other')).toHaveLength(1);
  });

  it('prunes older Prisma tokens after registration and bounds the owner list', async () => {
    const updatedAt = new Date('2026-10-24T00:00:00.000Z');
    const prisma = {
      deviceToken: {
        upsert: vi.fn(async () => ({ userId: 'seller-1', token: 'newest', platform: null, updatedAt })),
        findMany: vi
          .fn()
          .mockResolvedValueOnce([{ token: 'stale-a' }, { token: 'stale-b' }])
          .mockResolvedValueOnce([]),
        deleteMany: vi.fn(async () => ({ count: 2 }))
      }
    };
    const repository = createPrismaDeviceTokenRepository({ prisma: prisma as unknown as PrismaDeviceTokenClient });

    await repository.register({ userId: 'seller-1', token: 'newest' });
    await repository.listForUser('seller-1');

    expect(prisma.deviceToken.findMany).toHaveBeenNthCalledWith(1, expect.objectContaining({
      where: { userId: 'seller-1' },
      orderBy: { updatedAt: 'desc' },
      skip: 10
    }));
    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({
      where: { userId: 'seller-1', token: { in: ['stale-a', 'stale-b'] } }
    });
    expect(prisma.deviceToken.findMany).toHaveBeenNthCalledWith(2, expect.objectContaining({
      where: { userId: 'seller-1' },
      orderBy: { updatedAt: 'desc' },
      take: 10
    }));
  });
});
