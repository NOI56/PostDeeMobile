import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaDeviceTokenRepository, type PrismaDeviceTokenClient } from './prismaDeviceTokenRepository.js';

// Never run against a developer or hosted database.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Device language DB tests require the dedicated loopback fixture cluster on port 55439');
  }
}

describe.skipIf(!databaseUrl)('device language in PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } } });
  const store = createPrismaDeviceTokenRepository({ prisma: prisma as unknown as PrismaDeviceTokenClient });
  const userIds: string[] = [];
  const member = async () => {
    const id = `device-language-${randomUUID()}`;
    userIds.push(id);
    await prisma.user.create({ data: { id, firebaseUid: id, email: `${id}@example.com` } });
    return id;
  };
  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.$disconnect();
  });

  it('saves, reads and updates language when the same token is registered again', async () => {
    const userId = await member();
    const token = randomUUID();
    expect(await store.register({ userId, token, language: 'th' })).toMatchObject({ language: 'th' });
    expect(await store.listForUser(userId)).toMatchObject([{ language: 'th' }]);
    expect(await store.register({ userId, token, language: 'en' })).toMatchObject({ language: 'en' });
    expect(await store.listForUser(userId)).toMatchObject([{ language: 'en' }]);
    expect(await prisma.deviceToken.count({ where: { userId } })).toBe(1);
    expect(await prisma.deviceToken.findUnique({ where: { token } })).toMatchObject({ language: 'en' });
  });

  it('keeps old-client rows nullable and clears language when an old client re-registers', async () => {
    const userId = await member();
    const token = randomUUID();
    await prisma.deviceToken.create({ data: { userId, token } });
    expect(await store.listForUser(userId)).toMatchObject([{ language: null }]);
    await store.register({ userId, token, language: 'en' });
    expect(await store.register({ userId, token })).toMatchObject({ language: null });
    await prisma.user.delete({ where: { id: userId } });
    expect(await prisma.deviceToken.count({ where: { userId } })).toBe(0);
  });
});
