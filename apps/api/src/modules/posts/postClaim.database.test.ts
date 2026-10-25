import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';

import { createPrismaPostRepository, type PrismaPostClient } from './prismaPostRepository.js';

// Synthetic local fixtures only. Refuse app databases and external hosts.
const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Post claim DB tests require the dedicated loopback fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl).sequential('atomic publish claim on real PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const repository = createPrismaPostRepository({ prisma: prisma as unknown as PrismaPostClient });
  const userId = `claim-fixture-${randomUUID()}`;
  const runAt = '2026-10-25T03:00:00.000Z';

  const createPost = (scheduledAt: string | null) => prisma.post.create({
    data: {
      userId, caption: 'Claim fixture', videoS3Key: `uploads/${userId}/v.mp4`,
      selectedPlatforms: ['TIKTOK'], status: 'QUEUED', ...(scheduledAt ? { scheduledAt: new Date(scheduledAt) } : {})
    }
  });

  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: userId } });
    await prisma.$disconnect();
  });

  it('claims a row still scheduled at its run time and reports it as scheduled', async () => {
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    const post = await createPost(runAt);

    await expect(repository.claimForPublishWithSchedule({ postId: post.id, expectedRunAt: runAt })).resolves.toBe('scheduled');
    const claimed = await prisma.post.findUniqueOrThrow({ where: { id: post.id } });
    expect(claimed.status).toBe('PUBLISHING');
    expect(claimed.scheduledAt?.toISOString()).toBe(runAt);
    // updatedAt is stored as UTC like Prisma's own writes.
    expect(Math.abs(claimed.updatedAt.getTime() - Date.now())).toBeLessThan(60_000);

    await expect(repository.claimForPublishWithSchedule({ postId: post.id, expectedRunAt: runAt })).resolves.toBeUndefined();
  });

  it('claims a row switched to Publish now and reports it as immediate', async () => {
    const post = await createPost(null);
    await expect(repository.claimForPublishWithSchedule({ postId: post.id, expectedRunAt: runAt })).resolves.toBe('immediate');
  });

  it('does not claim a row scheduled at a different time', async () => {
    const post = await createPost('2026-10-26T03:00:00.000Z');
    await expect(repository.claimForPublishWithSchedule({ postId: post.id, expectedRunAt: runAt })).resolves.toBeUndefined();
    await expect(prisma.post.findUniqueOrThrow({ where: { id: post.id } })).resolves.toMatchObject({ status: 'QUEUED' });
  });
});
