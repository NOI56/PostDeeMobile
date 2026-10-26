import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaAdminAccountDeletionStore } from './prismaAdminAccountDeletionStore.js';
import { createPrismaAdminDataSource } from './adminDataSource.js';
import type { AdminConsoleConfig } from './adminConfig.js';

// Opt-in only; refuse external hosts, default Postgres ports and existing app databases.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Admin DB tests require the dedicated loopback fixture cluster on port 55439');
  }
}
describe.skipIf(!databaseUrl)('admin account deletion records in PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } } });
  const userIds: string[] = [];
  const requestIds: string[] = [];
  const time = new Date('2026-10-26T00:00:00Z');
  const store = createPrismaAdminAccountDeletionStore(prisma, () => time);
  const config: AdminConsoleConfig = { origin: 'http://127.0.0.1:4174', environment: 'LOCAL', ownerUids: ['fixture-owner'], viewerUids: [],
    firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' } };
  const record = (userId = `deleted-fixture-${randomUUID()}`) => {
    const requestId = randomUUID(); requestIds.push(requestId); userIds.push(userId);
    return { requestId, actorId: 'fixture-owner', userId, reason: 'ทดสอบฐานข้อมูลเฉพาะในเครื่อง', intentHash: 'fixture-intent' };
  };
  afterAll(async () => {
    await prisma.adminAccountDeletion.deleteMany({ where: { requestId: { in: requestIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.$disconnect();
  });

  it('inserts one pending record per request id, even for concurrent submits', async () => {
    const input = record();
    const results = await Promise.all([store.start(input), store.start(input), store.start(input)]);

    expect(results.map(result => result.requestId)).toEqual([input.requestId, input.requestId, input.requestId]);
    expect(results[0]).toMatchObject({ status: 'PENDING', lastErrorCode: null, completedAt: null, createdAt: time.toISOString() });
    expect(await prisma.adminAccountDeletion.count({ where: { requestId: input.requestId } })).toBe(1);
  });

  it('records the latest failure, completes once and ignores failures after completion', async () => {
    const input = record();
    await store.start(input);
    await store.fail(input.requestId, 'ACCOUNT_MEDIA_CLEANUP_FAILED');
    expect(await store.find(input.requestId)).toMatchObject({ status: 'PENDING', lastErrorCode: 'ACCOUNT_MEDIA_CLEANUP_FAILED' });

    const completed = await store.complete(input.requestId);
    await store.fail(input.requestId, 'ACCOUNT_IDENTITY_DELETE_FAILED');

    expect(completed).toMatchObject({ status: 'COMPLETED', lastErrorCode: null, completedAt: time.toISOString() });
    expect(await store.find(input.requestId)).toEqual(completed);
  });

  it('keeps the record after the deleted User row is gone and rejects inconsistent rows', async () => {
    const userId = `deleted-fixture-${randomUUID()}`;
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.com` } });
    const input = record(userId);
    await store.start(input);

    await prisma.user.delete({ where: { id: userId } });

    expect(await store.find(input.requestId)).toMatchObject({ userId, status: 'PENDING' });
    await expect(prisma.$executeRaw`INSERT INTO "AdminAccountDeletion"
      ("requestId", "actorId", "userId", "reason", "intentHash", "status") VALUES (${randomUUID()}, 'a', 'u', 'r', 'h', 'COMPLETED')`)
      .rejects.toThrow();
  });

  it('serves the deletion history view by exact UID from a read-only snapshot', async () => {
    const input = record();
    await store.start(input); await store.complete(input.requestId);
    const data = createPrismaAdminDataSource(prisma, config, () => time);

    const page = await data.view('deletions', { query: input.userId });

    expect(page.rows).toEqual([expect.objectContaining({ requestId: input.requestId, userId: input.userId, status: 'COMPLETED',
      completedAt: time.toISOString() })]);
  });
});
