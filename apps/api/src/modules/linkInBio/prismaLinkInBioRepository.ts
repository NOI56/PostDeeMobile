import {
  type LinkInBioLink, type LinkInBioProfile, type LinkInBioStore,
  type PublishLinkInBioInput, slugTakenError
} from './linkInBioStore.js';
import { createDefaultLinkInBioAppearance, normalizeStoredLinkInBioAppearance } from './linkInBioAppearance.js';

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

export type PrismaLinkInBioClient = {
  linkInBioProfile: {
    findUnique: (args: { where: { userId: string } }) => Promise<PrismaLinkInBioProfile | null>;
    findFirst: (args: { where: { slug: string; isPublished: true } }) => Promise<PrismaLinkInBioProfile | null>;
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
      return mapProfile(await prisma.linkInBioProfile.upsert({
        where: { userId },
        create: { userId, ...data, appearance: input.appearance ?? createDefaultLinkInBioAppearance() },
        update: data
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
    await prisma.linkInBioProfile.deleteMany({ where: { userId } });
  }
});
