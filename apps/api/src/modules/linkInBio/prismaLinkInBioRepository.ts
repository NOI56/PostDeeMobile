import {
  type LinkInBioLink, type LinkInBioProfile, type LinkInBioStore,
  type PublishLinkInBioInput, slugTakenError
} from './linkInBioStore.js';
import { createDefaultLinkInBioAppearance, normalizeStoredLinkInBioAppearance } from './linkInBioAppearance.js';
import {
  isReservedLinkInBioSlug,
  linkInBioSlugReservationMs,
  maxLinkInBioSlugReservationsPerOwner
} from './linkInBioSlugPolicy.js';

type PrismaLinkInBioProfile = {
  storeName: string;
  slug: string;
  links: unknown;
  appearance?: unknown;
  isPublished: boolean;
  publishedAt: Date | null;
  updatedAt: Date;
};
type ProfileData = Omit<PublishLinkInBioInput, 'userId'> & {
  isPublished: boolean; publishedAt: Date; updatedAt: Date;
};

type PrismaSlugReservation = {
  slug: string;
  ownerId: string | null;
  releasedAt: Date;
  reservedUntil: Date;
};
type SlugReservationData = Omit<PrismaSlugReservation, 'slug'>;

type PrismaLinkInBioTransaction = {
  linkInBioProfile: {
    findUnique: (args: { where: { userId: string } }) => Promise<PrismaLinkInBioProfile | null>;
    findFirst: {
      (args: { where: { slug: string; isPublished: true } }): Promise<PrismaLinkInBioProfile | null>;
      (args: { where: { slug: string }; select: { userId: true } }): Promise<{ userId: string } | null>;
    };
    upsert: (args: {
      where: { userId: string };
      create: ProfileData & { userId: string };
      update: ProfileData;
    }) => Promise<PrismaLinkInBioProfile>;
    updateMany: (args: {
      where: { userId: string };
      data: { isPublished: false; publishedAt: null; updatedAt: Date };
    }) => Promise<{ count: number }>;
    deleteMany: (args: { where: { userId: string } }) => Promise<{ count: number }>;
  };
  linkInBioSlugReservation: {
    findUnique: (args: { where: { slug: string } }) => Promise<PrismaSlugReservation | null>;
    findMany: (args: {
      where: { ownerId: string };
      orderBy: { releasedAt: 'desc' };
      skip: number;
      select: { slug: true };
    }) => Promise<Array<{ slug: string }>>;
    upsert: (args: {
      where: { slug: string };
      create: PrismaSlugReservation;
      update: SlugReservationData;
    }) => Promise<unknown>;
    updateMany: (args: {
      where: { ownerId: string };
      data: { ownerId: null };
    }) => Promise<{ count: number }>;
    deleteMany: (args: {
      where:
        | { slug: { in: string[] } }
        | { slug: string; OR: [{ reservedUntil: { lte: Date } }, { ownerId: string }] };
    }) => Promise<{ count: number }>;
  };
};

export type PrismaLinkInBioClient = PrismaLinkInBioTransaction & {
  $transaction: <T>(action: (transaction: PrismaLinkInBioTransaction) => Promise<T>) => Promise<T>;
};

const assertSlugClaimable = async (
  transaction: PrismaLinkInBioTransaction,
  { userId, slug, now }: { userId: string; slug: string; now: Date }
) => {
  if (isReservedLinkInBioSlug(slug)) throw slugTakenError();
  // Read the holder before the reservation. A rename commits the profile
  // change and the reservation together, so one of these two reads always
  // sees the slug as taken.
  if (await transaction.linkInBioProfile.findFirst({ where: { slug }, select: { userId: true } })) {
    throw slugTakenError();
  }
  const reservation = await transaction.linkInBioSlugReservation.findUnique({ where: { slug } });
  if (!reservation) return;
  if (reservation.ownerId !== userId && reservation.reservedUntil > now) throw slugTakenError();
  // Delete only while the row is still expired or the claimant's own. A rename
  // that re-reserved the slug after the read leaves nothing to delete, and the
  // claim then fails instead of removing that fresh reservation.
  const removed = await transaction.linkInBioSlugReservation.deleteMany({
    where: { slug, OR: [{ reservedUntil: { lte: now } }, { ownerId: userId }] }
  });
  if (removed.count === 0) throw slugTakenError();
};

const reserveReleasedSlug = async (
  transaction: PrismaLinkInBioTransaction,
  { ownerId, slug, now }: { ownerId: string | null; slug: string; now: Date }
) => {
  const data = { ownerId, releasedAt: now, reservedUntil: new Date(now.getTime() + linkInBioSlugReservationMs) };
  await transaction.linkInBioSlugReservation.upsert({ where: { slug }, create: { slug, ...data }, update: data });
  if (!ownerId) return;
  const surplus = await transaction.linkInBioSlugReservation.findMany({
    where: { ownerId }, orderBy: { releasedAt: 'desc' },
    skip: maxLinkInBioSlugReservationsPerOwner, select: { slug: true }
  });
  if (surplus.length > 0) {
    await transaction.linkInBioSlugReservation.deleteMany({
      where: { slug: { in: surplus.map((reservation) => reservation.slug) } }
    });
  }
};

const mapProfile = (profile: PrismaLinkInBioProfile | null): LinkInBioProfile | null => profile ? ({
  storeName: profile.storeName,
  slug: profile.slug,
  links: (profile.links as LinkInBioLink[]).map((link) => ({ ...link })),
  appearance: normalizeStoredLinkInBioAppearance(profile.appearance, profile.links as LinkInBioLink[]),
  isPublished: profile.isPublished,
  publishedAt: profile.publishedAt?.toISOString() ?? null,
  updatedAt: profile.updatedAt.toISOString(),
  publicPath: profile.isPublished ? `/p/${profile.slug}` : null
}) : null;

export const createPrismaLinkInBioRepository = ({
  prisma, now = () => new Date()
}: { prisma: PrismaLinkInBioClient; now?: () => Date }): LinkInBioStore => ({
  getForUser: async (userId) => mapProfile(await prisma.linkInBioProfile.findUnique({ where: { userId } })),
  getPublishedBySlug: async (slug) => mapProfile(await prisma.linkInBioProfile.findFirst({
    where: { slug, isPublished: true }
  })),
  publish: async ({ userId, ...input }) => {
    const timestamp = now();
    const data = { ...input, isPublished: true, publishedAt: timestamp, updatedAt: timestamp };
    try {
      return mapProfile(await prisma.$transaction(async (transaction) => {
        const current = await transaction.linkInBioProfile.findUnique({ where: { userId } });
        if (current?.slug !== input.slug) {
          await assertSlugClaimable(transaction, { userId, slug: input.slug, now: timestamp });
        }
        const profile = await transaction.linkInBioProfile.upsert({
          where: { userId },
          create: { userId, ...data, appearance: input.appearance ?? createDefaultLinkInBioAppearance() },
          update: data
        });
        if (current && current.slug !== input.slug) {
          await reserveReleasedSlug(transaction, { ownerId: userId, slug: current.slug, now: timestamp });
        }
        return profile;
      }))!;
    } catch (error) {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'P2002') {
        throw slugTakenError();
      }
      throw error;
    }
  },
  unpublish: async (userId) => {
    await prisma.linkInBioProfile.updateMany({
      where: { userId }, data: { isPublished: false, publishedAt: null, updatedAt: now() }
    });
    return mapProfile(await prisma.linkInBioProfile.findUnique({ where: { userId } }));
  },
  deleteAllForUser: async (userId) => {
    await prisma.$transaction(async (transaction) => {
      const profile = await transaction.linkInBioProfile.findUnique({ where: { userId } });
      // Old links stay protected after deletion, but no reservation keeps the
      // deleted owner's id.
      await transaction.linkInBioSlugReservation.updateMany({ where: { ownerId: userId }, data: { ownerId: null } });
      if (profile) {
        await reserveReleasedSlug(transaction, { ownerId: null, slug: profile.slug, now: now() });
      }
      await transaction.linkInBioProfile.deleteMany({ where: { userId } });
    });
  }
});
