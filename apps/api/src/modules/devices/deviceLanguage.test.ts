import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { registerDeviceRoutes } from './deviceRoutes.js';
import { createInMemoryDeviceTokenStore } from './deviceTokenStore.js';
import { createPrismaDeviceTokenRepository, type PrismaDeviceTokenClient } from './prismaDeviceTokenRepository.js';

const fixture = () => {
  const app = express();
  const router = express.Router();
  const store = createInMemoryDeviceTokenStore();
  const userStore = {
    ensure: vi.fn(async () => ({ id: 'member', firebaseUid: 'member', email: 'member@example.com',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() })),
    exists: vi.fn(async () => true)
  };
  const auth: express.RequestHandler = (_request, response, next) => {
    response.locals.authUser = { id: 'member', provider: 'mock' };
    next();
  };
  app.use(express.json());
  registerDeviceRoutes(router, auth, store, userStore);
  app.use(router);
  return { app, store };
};

describe('device language', () => {
  it.each([
    ['th', 'th'], ['en', 'en'], ['en-US', 'en'], ['ja', 'en'],
    ['TH-th', 'th'], [undefined, null]
  ])('normalizes registration language %s to %s', async (language, expected) => {
    const { app, store } = fixture();
    await request(app).post('/devices').send({ token: 'member-token', language }).expect(200);
    expect(await store.listForUser('member')).toMatchObject([{ token: 'member-token', language: expected }]);
  });

  it('updates the language on re-registration, including an old client without a language', async () => {
    const { app, store } = fixture();
    for (const language of ['th', 'en', undefined]) {
      await request(app).post('/devices').send({ token: 'member-token', language }).expect(200);
      expect(await store.listForUser('member')).toMatchObject([{ token: 'member-token', language: language ?? null }]);
      expect(await store.listForUser('member')).toHaveLength(1);
    }
  });

  it('writes language on both Prisma upsert paths and selects it when reading', async () => {
    const row = { userId: 'member', token: 'token', platform: null, language: 'en', updatedAt: new Date() };
    const prisma = { deviceToken: {
      upsert: vi.fn(async () => row),
      findMany: vi.fn().mockResolvedValueOnce([]).mockResolvedValueOnce([row]),
      deleteMany: vi.fn()
    } };
    const store = createPrismaDeviceTokenRepository({ prisma: prisma as unknown as PrismaDeviceTokenClient });
    expect(await store.register({ userId: 'member', token: 'token', language: 'en' }))
      .toMatchObject({ language: 'en' });
    expect(prisma.deviceToken.upsert).toHaveBeenCalledWith(expect.objectContaining({
      create: { userId: 'member', token: 'token', platform: null, language: 'en' },
      update: { userId: 'member', platform: null, language: 'en' },
      select: expect.objectContaining({ language: true })
    }));
    expect(await store.listForUser('member')).toMatchObject([{ language: 'en' }]);
    expect(prisma.deviceToken.findMany).toHaveBeenLastCalledWith(expect.objectContaining({
      select: expect.objectContaining({ language: true })
    }));
  });
});
