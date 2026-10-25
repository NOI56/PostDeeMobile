import { describe, expect, it, vi } from 'vitest';

import { createInMemoryLinkInBioStore } from './linkInBioStore.js';
import {
  isReservedLinkInBioSlug,
  linkInBioSlugReservationMs,
  maxLinkInBioSlugReservationsPerOwner
} from './linkInBioSlugPolicy.js';
import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';

const links = [{ id: 'shop', title: 'ซื้อสินค้า', url: 'https://example.com/shop' }];
const publishAs = (userId: string, slug: string) => ({ userId, storeName: 'ร้าน', slug, links });
const slugTaken = { statusCode: 409, code: 'LINK_IN_BIO_SLUG_TAKEN' };
const start = new Date('2026-10-24T00:00:00.000Z');

const createClockedStore = () => {
  let clock = start;
  const store = createInMemoryLinkInBioStore({ now: () => clock });
  return { store, advance: (ms: number) => { clock = new Date(clock.getTime() + ms); } };
};

describe('link in bio slug reservation (memory store)', () => {
  it('keeps a renamed slug away from other owners until the reservation ends', async () => {
    const { store, advance } = createClockedStore();
    await store.publish(publishAs('owner-a', 'my-shop'));
    await store.publish(publishAs('owner-a', 'new-shop'));

    await expect(store.publish(publishAs('owner-b', 'my-shop'))).rejects.toMatchObject(slugTaken);
    advance(linkInBioSlugReservationMs - 1);
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).rejects.toMatchObject(slugTaken);
    advance(1);
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).resolves.toMatchObject({ slug: 'my-shop' });
  });

  it('lets the previous owner take a released slug back during the reservation', async () => {
    const { store } = createClockedStore();
    await store.publish(publishAs('owner-a', 'my-shop'));
    await store.publish(publishAs('owner-a', 'new-shop'));
    await expect(store.publish(publishAs('owner-a', 'my-shop'))).resolves.toMatchObject({ slug: 'my-shop' });
    // Reclaiming ends that reservation and reserves the slug it left instead.
    await expect(store.publish(publishAs('owner-b', 'new-shop'))).rejects.toMatchObject(slugTaken);
  });

  it('reserves a deleted account slug for nobody', async () => {
    const { store, advance } = createClockedStore();
    await store.publish(publishAs('owner-a', 'my-shop'));
    await store.deleteAllForUser!('owner-a');

    await expect(store.publish(publishAs('owner-a', 'my-shop'))).rejects.toMatchObject(slugTaken);
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).rejects.toMatchObject(slugTaken);
    advance(linkInBioSlugReservationMs);
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).resolves.toMatchObject({ slug: 'my-shop' });
  });

  it('keeps only the newest reservations per owner', async () => {
    const { store, advance } = createClockedStore();
    const slugs = ['shop-one', 'shop-two', 'shop-three', 'shop-four', 'shop-five'];
    for (const slug of slugs) {
      await store.publish(publishAs('owner-a', slug));
      advance(1000);
    }
    expect(maxLinkInBioSlugReservationsPerOwner).toBe(3);

    await expect(store.publish(publishAs('owner-b', 'shop-one'))).resolves.toMatchObject({ slug: 'shop-one' });
    for (const slug of ['shop-two', 'shop-three', 'shop-four']) {
      await expect(store.publish(publishAs('owner-c', slug))).rejects.toMatchObject(slugTaken);
    }
  });

  it('refuses reserved names for new claims', async () => {
    const { store } = createClockedStore();
    for (const slug of ['admin', 'support', 'postdee', 'postdee-official', 'official-postdee-th']) {
      expect(isReservedLinkInBioSlug(slug)).toBe(true);
      await expect(store.publish(publishAs('owner-a', slug))).rejects.toMatchObject(slugTaken);
    }
    expect(isReservedLinkInBioSlug('my-shop')).toBe(false);
  });

  it('still holds the slug of an unpublished page', async () => {
    const { store } = createClockedStore();
    await store.publish(publishAs('owner-a', 'my-shop'));
    await store.unpublish('owner-a');
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).rejects.toMatchObject(slugTaken);
  });
});

describe('link in bio slug reservation (Prisma repository)', () => {
  const at = start;
  const reservedUntil = new Date(at.getTime() + linkInBioSlugReservationMs);
  const row = (userId: string, slug: string) => ({
    userId, storeName: 'ร้าน', slug, links, isPublished: true, publishedAt: at, updatedAt: at
  });

  const createFixture = ({
    current = null as ReturnType<typeof row> | null,
    holder = null as { userId: string } | null,
    reservation = null as { slug: string; ownerId: string | null; releasedAt: Date; reservedUntil: Date } | null,
    surplus = [] as Array<{ slug: string }>
  } = {}) => {
    const linkInBioProfile = {
      findUnique: vi.fn(async () => current),
      findFirst: vi.fn(async () => holder),
      upsert: vi.fn(async (args: { create: { slug: string } }) => row('owner-a', args.create.slug)),
      updateMany: vi.fn(async () => ({ count: 1 })),
      deleteMany: vi.fn(async () => ({ count: 1 }))
    };
    const linkInBioSlugReservation = {
      findUnique: vi.fn(async () => reservation),
      findMany: vi.fn(async () => surplus),
      upsert: vi.fn(async () => ({})),
      updateMany: vi.fn(async () => ({ count: 0 })),
      deleteMany: vi.fn(async () => ({ count: 1 }))
    };
    const transaction = { linkInBioProfile, linkInBioSlugReservation };
    const $transaction = vi.fn(async (action: (client: typeof transaction) => Promise<unknown>) => action(transaction));
    const prisma = { ...transaction, $transaction } as unknown as PrismaLinkInBioClient;
    return { store: createPrismaLinkInBioRepository({ prisma, now: () => at }), linkInBioProfile, linkInBioSlugReservation, $transaction };
  };

  it('refuses a slug another owner released less than the reservation period ago', async () => {
    const { store, linkInBioProfile, linkInBioSlugReservation } = createFixture({
      reservation: { slug: 'my-shop', ownerId: 'owner-a', releasedAt: at, reservedUntil }
    });
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).rejects.toMatchObject(slugTaken);
    expect(linkInBioProfile.upsert).not.toHaveBeenCalled();
    expect(linkInBioSlugReservation.deleteMany).not.toHaveBeenCalled();
  });

  it('reads the current holder before the reservation, so a concurrent rename cannot slip through', async () => {
    const { store, linkInBioProfile, linkInBioSlugReservation } = createFixture();
    await store.publish(publishAs('owner-b', 'free-shop'));
    expect(linkInBioProfile.findFirst).toHaveBeenCalledWith({ where: { slug: 'free-shop' }, select: { userId: true } });
    expect(linkInBioSlugReservation.findUnique).toHaveBeenCalledWith({ where: { slug: 'free-shop' } });
    expect(linkInBioProfile.findFirst.mock.invocationCallOrder[0])
      .toBeLessThan(linkInBioSlugReservation.findUnique.mock.invocationCallOrder[0]!);
  });

  it('claims an expired reservation and clears it in the same transaction', async () => {
    const { store, linkInBioProfile, linkInBioSlugReservation, $transaction } = createFixture({
      reservation: { slug: 'my-shop', ownerId: 'owner-a', releasedAt: at, reservedUntil: at }
    });
    await expect(store.publish(publishAs('owner-b', 'my-shop'))).resolves.toMatchObject({ slug: 'my-shop' });
    expect($transaction).toHaveBeenCalledTimes(1);
    expect(linkInBioSlugReservation.deleteMany).toHaveBeenCalledWith({
      where: { slug: 'my-shop', OR: [{ reservedUntil: { lte: at } }, { ownerId: 'owner-b' }] }
    });
    expect(linkInBioProfile.upsert).toHaveBeenCalledTimes(1);
  });

  it('reserves the old slug for its owner when the owner renames and trims older reservations', async () => {
    const { store, linkInBioSlugReservation } = createFixture({
      current: row('owner-a', 'my-shop'), surplus: [{ slug: 'oldest-shop' }]
    });
    await store.publish(publishAs('owner-a', 'new-shop'));
    expect(linkInBioSlugReservation.upsert).toHaveBeenCalledWith({
      where: { slug: 'my-shop' },
      create: { slug: 'my-shop', ownerId: 'owner-a', releasedAt: at, reservedUntil },
      update: { ownerId: 'owner-a', releasedAt: at, reservedUntil }
    });
    expect(linkInBioSlugReservation.findMany).toHaveBeenCalledWith({
      where: { ownerId: 'owner-a' }, orderBy: { releasedAt: 'desc' },
      skip: maxLinkInBioSlugReservationsPerOwner, select: { slug: true }
    });
    expect(linkInBioSlugReservation.deleteMany).toHaveBeenCalledWith({ where: { slug: { in: ['oldest-shop'] } } });
  });

  it('republishes the same slug without reservation work, including a grandfathered reserved name', async () => {
    const { store, linkInBioProfile, linkInBioSlugReservation } = createFixture({ current: row('owner-a', 'support') });
    await expect(store.publish(publishAs('owner-a', 'support'))).resolves.toMatchObject({ slug: 'support' });
    expect(linkInBioProfile.findFirst).not.toHaveBeenCalled();
    expect(linkInBioSlugReservation.findUnique).not.toHaveBeenCalled();
    expect(linkInBioSlugReservation.upsert).not.toHaveBeenCalled();
  });

  it('refuses a reserved name before any database work', async () => {
    const { store, linkInBioProfile } = createFixture();
    await expect(store.publish(publishAs('owner-b', 'postdee-help'))).rejects.toMatchObject(slugTaken);
    expect(linkInBioProfile.upsert).not.toHaveBeenCalled();
  });

  it('keeps a deleted account slug reserved without the owner id', async () => {
    const { store, linkInBioProfile, linkInBioSlugReservation } = createFixture({ current: row('owner-a', 'my-shop') });
    await store.deleteAllForUser!('owner-a');
    expect(linkInBioSlugReservation.updateMany).toHaveBeenCalledWith({ where: { ownerId: 'owner-a' }, data: { ownerId: null } });
    expect(linkInBioSlugReservation.upsert).toHaveBeenCalledWith({
      where: { slug: 'my-shop' },
      create: { slug: 'my-shop', ownerId: null, releasedAt: at, reservedUntil },
      update: { ownerId: null, releasedAt: at, reservedUntil }
    });
    expect(linkInBioProfile.deleteMany).toHaveBeenCalledWith({ where: { userId: 'owner-a' } });
  });
});
