import { describe, expect, it, vi } from 'vitest';

import { createLinkInBioStoreFromConfig } from './linkInBioStoreFactory.js';
import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';

const input = {
  userId: 'owner', storeName: 'ร้านของดี', slug: 'my-shop',
  links: [{ id: 'shop', title: 'ซื้อสินค้า', url: 'https://example.com/shop' }]
};
const at = new Date('2026-10-05T10:00:00Z');
const row = { ...input, isPublished: true, publishedAt: at, updatedAt: at };
const fixture = () => {
  const linkInBioProfile = {
    findUnique: vi.fn<PrismaLinkInBioClient['linkInBioProfile']['findUnique']>(async () => row),
    findFirst: vi.fn(async () => row),
    upsert: vi.fn(async () => row),
    updateMany: vi.fn(async () => ({ count: 1 })),
    deleteMany: vi.fn(async () => ({ count: 1 }))
  };
  const store = createPrismaLinkInBioRepository({ prisma: { linkInBioProfile }, now: () => at });
  return { store, linkInBioProfile };
};

describe('Prisma link in bio repository', () => {
  it('uses one atomic user-scoped upsert and returns only the public profile fields', async () => {
    const { store, linkInBioProfile } = fixture();
    expect(await store.publish(input)).toEqual({
      storeName: input.storeName, slug: input.slug, links: input.links,
      isPublished: true, publishedAt: at.toISOString(), updatedAt: at.toISOString(),
      publicPath: '/p/my-shop'
    });
    expect(linkInBioProfile.upsert).toHaveBeenCalledWith({
      where: { userId: 'owner' },
      create: { ...input, isPublished: true, publishedAt: at, updatedAt: at },
      update: {
        storeName: input.storeName, slug: input.slug, links: input.links,
        isPublished: true, publishedAt: at, updatedAt: at
      }
    });
    expect(linkInBioProfile.findUnique).not.toHaveBeenCalled();
  });

  it('reads owner data by userId and public data only when published', async () => {
    const { store, linkInBioProfile } = fixture();
    await store.getForUser('owner');
    await store.getPublishedBySlug('my-shop');
    expect(linkInBioProfile.findUnique).toHaveBeenCalledWith({ where: { userId: 'owner' } });
    expect(linkInBioProfile.findFirst).toHaveBeenCalledWith({ where: { slug: 'my-shop', isPublished: true } });
  });

  it('maps a database unique collision to the slug-taken error', async () => {
    const { store, linkInBioProfile } = fixture();
    linkInBioProfile.upsert.mockRejectedValueOnce({ code: 'P2002', meta: { target: ['slug'] } });
    await expect(store.publish(input)).rejects.toMatchObject({
      statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN'
    });
  });

  it('does not hide a database failure as a slug collision', async () => {
    const { store, linkInBioProfile } = fixture();
    const failure = new Error('Database unavailable');
    linkInBioProfile.upsert.mockRejectedValueOnce(failure);
    await expect(store.publish(input)).rejects.toBe(failure);
  });

  it('unpublishes by owner without deleting or changing the reserved slug', async () => {
    const { store, linkInBioProfile } = fixture();
    linkInBioProfile.findUnique.mockResolvedValueOnce({ ...row, isPublished: false, publishedAt: null });
    const result = await store.unpublish('owner');
    expect(result?.publicPath).toBeNull();
    expect(linkInBioProfile.updateMany).toHaveBeenCalledWith({
      where: { userId: 'owner' }, data: { isPublished: false, publishedAt: null, updatedAt: at }
    });
    expect(linkInBioProfile.deleteMany).not.toHaveBeenCalled();
  });

  it('cleans up the profile by owner on account deletion', async () => {
    const { store, linkInBioProfile } = fixture();
    await store.deleteAllForUser?.('owner');
    expect(linkInBioProfile.deleteMany).toHaveBeenCalledWith({ where: { userId: 'owner' } });
  });
});

describe('link in bio store selection', () => {
  it('uses the configured postStore and never silently falls back to memory for Prisma', async () => {
    const memory = createLinkInBioStoreFromConfig({ config: { postStore: 'memory' } });
    await memory.publish(input);
    expect(await memory.getForUser('owner')).toMatchObject({ slug: 'my-shop' });
    const unavailable = createLinkInBioStoreFromConfig({
      config: { postStore: 'prisma' }, prisma: {} as PrismaLinkInBioClient
    });
    await expect(unavailable.getForUser('owner')).rejects.toMatchObject({
      statusCode: 503, code: 'LINK_IN_BIO_UNAVAILABLE'
    });
  });
});
