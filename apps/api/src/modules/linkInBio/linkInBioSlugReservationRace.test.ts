import { describe, expect, it, vi } from 'vitest';

import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';

const at = new Date('2026-10-25T00:00:00.000Z');
const links = [{ id: 'shop', title: 'ร้าน', url: 'https://example.com/shop' }];
const slugTaken = { statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN' };

const createFixture = ({ conditionalDeleteCount }: { conditionalDeleteCount: number }) => {
  const linkInBioProfile = {
    findUnique: vi.fn(async () => null),
    findFirst: vi.fn(async () => null),
    upsert: vi.fn(async (args: { create: { slug: string } }) => ({
      storeName: 'ร้าน', slug: args.create.slug, links, isPublished: true, publishedAt: at, updatedAt: at
    })),
    updateMany: vi.fn(async () => ({ count: 0 })),
    deleteMany: vi.fn(async () => ({ count: 0 }))
  };
  const linkInBioSlugReservation = {
    // Read as expired, so the claim decides it may take the slug.
    findUnique: vi.fn(async () => ({ slug: 'my-shop', ownerId: 'owner-a', releasedAt: at, reservedUntil: at })),
    findMany: vi.fn(async () => []),
    upsert: vi.fn(async () => ({})),
    updateMany: vi.fn(async () => ({ count: 0 })),
    // count 0: another transaction replaced the reservation after the read.
    deleteMany: vi.fn(async () => ({ count: conditionalDeleteCount }))
  };
  const transaction = { linkInBioProfile, linkInBioSlugReservation };
  const prisma = {
    ...transaction,
    $transaction: async (action: (client: typeof transaction) => Promise<unknown>) => action(transaction)
  } as unknown as PrismaLinkInBioClient;
  return { store: createPrismaLinkInBioRepository({ prisma, now: () => at }), linkInBioProfile, linkInBioSlugReservation };
};

describe('link in bio reservation delete race (Codex review 2026-10-25)', () => {
  it('deletes a reservation only while it is still expired or the claimant\'s own', async () => {
    const { store, linkInBioSlugReservation } = createFixture({ conditionalDeleteCount: 1 });
    await expect(store.publish({ userId: 'owner-b', storeName: 'ร้าน', slug: 'my-shop', links }))
      .resolves.toMatchObject({ slug: 'my-shop' });
    expect(linkInBioSlugReservation.deleteMany).toHaveBeenCalledWith({
      where: { slug: 'my-shop', OR: [{ reservedUntil: { lte: at } }, { ownerId: 'owner-b' }] }
    });
  });

  it('refuses the claim when the reservation was replaced after it was read', async () => {
    const { store, linkInBioProfile } = createFixture({ conditionalDeleteCount: 0 });
    await expect(store.publish({ userId: 'owner-b', storeName: 'ร้าน', slug: 'my-shop', links }))
      .rejects.toMatchObject(slugTaken);
    expect(linkInBioProfile.upsert).not.toHaveBeenCalled();
  });
});
