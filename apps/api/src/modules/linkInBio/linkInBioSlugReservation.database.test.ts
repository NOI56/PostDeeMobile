import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';

import { linkInBioSlugReservationMs } from './linkInBioSlugPolicy.js';
import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';

// Synthetic local fixtures only. Refuse app databases and external hosts.
const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Link in Bio DB tests require the dedicated loopback fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl).sequential('link in bio slug reservation on real PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const run = randomUUID().slice(0, 8);
  const userIds: string[] = [];
  const slugs: string[] = [];
  let clock = new Date('2026-10-24T00:00:00.000Z');
  const store = createPrismaLinkInBioRepository({
    prisma: prisma as unknown as PrismaLinkInBioClient, now: () => clock
  });
  const links = [{ id: 'shop', title: 'ร้าน', url: 'https://example.com/shop' }];
  const slug = (name: string) => { const value = `${name}-${run}`; slugs.push(value); return value; };
  const member = async () => {
    const userId = `slug-fixture-${randomUUID()}`; userIds.push(userId);
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    return userId;
  };
  const publish = (userId: string, value: string) => store.publish({ userId, storeName: 'ร้าน', slug: value, links });
  const slugTaken = { statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN' };

  afterAll(async () => {
    await prisma.linkInBioSlugReservation.deleteMany({ where: { slug: { in: slugs } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.$disconnect();
  });

  it('reserves a renamed slug for its owner and releases it after the period', async () => {
    const [ownerA, ownerB] = [await member(), await member()];
    const original = slug('rename');
    const renamed = slug('renamed');
    await publish(ownerA, original);
    await publish(ownerA, renamed);

    await expect(prisma.linkInBioSlugReservation.findUnique({ where: { slug: original } }))
      .resolves.toMatchObject({ ownerId: ownerA });
    await expect(publish(ownerB, original)).rejects.toMatchObject(slugTaken);

    clock = new Date(clock.getTime() + linkInBioSlugReservationMs);
    await expect(publish(ownerB, original)).resolves.toMatchObject({ slug: original });
    await expect(prisma.linkInBioSlugReservation.findUnique({ where: { slug: original } })).resolves.toBeNull();
  });

  it('keeps a deleted account slug reserved without its owner id', async () => {
    const [ownerA, ownerB] = [await member(), await member()];
    const value = slug('deleted');
    await publish(ownerA, value);
    await store.deleteAllForUser!(ownerA);

    await expect(prisma.linkInBioSlugReservation.findUnique({ where: { slug: value } }))
      .resolves.toMatchObject({ ownerId: null });
    await expect(publish(ownerB, value)).rejects.toMatchObject(slugTaken);
  });

  it('never lets another owner take a slug while its owner renames away from it', async () => {
    for (let round = 0; round < 15; round += 1) {
      const [ownerA, ownerB] = [await member(), await member()];
      const contested = slug(`race${round}`);
      const next = slug(`race${round}-next`);
      await publish(ownerA, contested);

      const [rename, claim] = await Promise.allSettled([publish(ownerA, next), publish(ownerB, contested)]);

      expect(rename.status).toBe('fulfilled');
      expect(claim).toMatchObject({ status: 'rejected', reason: slugTaken });
      await expect(prisma.linkInBioProfile.findUnique({ where: { userId: ownerB } })).resolves.toBeNull();
    }
  });
});
