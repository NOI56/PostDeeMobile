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

  it('updates caption/settings atomically once and preserves every unrelated persisted field', async () => {
    const post = await createPost(runAt);
    const platformSettings = { TIKTOK: { publishMode: 'INBOX_DRAFT' as const, caption: 'Edited destination' } };
    const input = { postId: post.id, userId, expectedScheduledAt: runAt,
      expectedUpdatedAt: post.updatedAt.toISOString(), caption: 'Edited shared', platformSettings,
      now: () => '2026-10-25T02:00:00.000Z' };
    const results = await Promise.all([repository.updateCaption(input), repository.updateCaption({ ...input, caption: 'Stale overwrite' })]);
    expect(results.filter(Boolean)).toHaveLength(1);
    const persisted = await prisma.post.findUniqueOrThrow({ where: { id: post.id } });
    expect(persisted).toMatchObject({ caption: results.find(Boolean)!.caption, platformSettings, videoS3Key: post.videoS3Key,
      selectedPlatforms: post.selectedPlatforms, scheduledAt: post.scheduledAt, status: 'QUEUED', addonPostUnits: post.addonPostUnits });
    expect(persisted.updatedAt.getTime()).toBeGreaterThan(post.updatedAt.getTime());
    expect(await repository.updateCaption({ ...input, userId: 'another-owner' })).toBeUndefined();
  });

  it('serializes a concurrent edit and publish claim without a mixed caption/settings pair', async () => {
    const post = await createPost(runAt);
    const platformSettings = { TIKTOK: { publishMode: 'INBOX_DRAFT' as const, caption: 'Edited destination' } };
    const [edited, claimed] = await Promise.all([
      repository.updateCaption({ postId: post.id, userId, expectedScheduledAt: runAt,
        expectedUpdatedAt: post.updatedAt.toISOString(), caption: 'Edited shared', platformSettings,
        now: () => '2026-10-25T02:00:00.000Z' }),
      repository.claimForPublishWithSchedule({ postId: post.id, expectedRunAt: runAt })
    ]);
    expect(claimed).toBe('scheduled');
    const persisted = await repository.findOwned({ postId: post.id, userId });
    expect(persisted?.status).toBe('PUBLISHING');
    expect(persisted?.caption).toBe(edited ? 'Edited shared' : 'Claim fixture');
    expect(persisted?.platformSettings?.TIKTOK).toEqual(edited ? platformSettings.TIKTOK : undefined);
    expect(await repository.updateCaption({ postId: post.id, userId, expectedScheduledAt: runAt,
      expectedUpdatedAt: persisted!.updatedAt!, caption: 'Too late', platformSettings,
      now: () => '2026-10-25T02:00:00.000Z' })).toBeUndefined();
  });

  it('refuses an edit that crosses the 60-second cutoff while waiting for a real post row lock', async () => {
    const post = await createPost(runAt);
    let release!: () => void;
    let acquired!: () => void;
    const ready = new Promise<void>(resolve => { acquired = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    const holding = prisma.$transaction(async transaction => {
      await transaction.$queryRaw`SELECT "id" FROM "Post" WHERE "id" = ${post.id} FOR UPDATE`;
      acquired();
      await gate;
    });
    await ready;
    let clock = '2026-10-25T02:58:59.000Z';
    const editing = repository.updateCaption({ postId: post.id, userId, expectedScheduledAt: runAt,
      expectedUpdatedAt: post.updatedAt.toISOString(), caption: 'Too late', now: () => clock });
    try {
      // Observe the SQL lock wait rather than assuming a sleep let the edit start.
      let waiting = false;
      for (let attempt = 0; attempt < 50 && !waiting; attempt += 1) {
        const rows = await prisma.$queryRaw<Array<{ waiting: boolean }>>`
          SELECT EXISTS (SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database() AND wait_event_type = 'Lock'
              AND query LIKE '%Post%') AS waiting`;
        waiting = rows[0]?.waiting ?? false;
        if (!waiting) await new Promise(resolve => setTimeout(resolve, 20));
      }
      expect(waiting).toBe(true);
      clock = '2026-10-25T02:59:00.000Z';
    } finally {
      release();
      await holding;
    }
    expect(await editing).toBeUndefined();
    const persisted = await prisma.post.findUniqueOrThrow({ where: { id: post.id } });
    expect(persisted.caption).toBe('Claim fixture');
    expect(persisted.updatedAt).toEqual(post.updatedAt);
  });
});
