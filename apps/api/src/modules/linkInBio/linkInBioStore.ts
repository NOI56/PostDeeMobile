import { normalizeStoredLinkInBioAppearance, type LinkInBioAppearance, type LinkInBioFont, type LinkInBioIcon } from './linkInBioAppearance.js';
import {
  isReservedLinkInBioSlug,
  linkInBioSlugReservationMs,
  maxLinkInBioSlugReservationsPerOwner
} from './linkInBioSlugPolicy.js';

export type { LinkInBioAppearance } from './linkInBioAppearance.js';
export type LinkInBioLink = {
  id: string; title: string; url: string;
  category?: string; icon?: LinkInBioIcon; font?: LinkInBioFont;
  textColor?: string; buttonColor?: string;
};

export type LinkInBioProfile = {
  storeName: string;
  slug: string;
  links: LinkInBioLink[];
  appearance?: LinkInBioAppearance;
  isPublished: boolean;
  publishedAt: string | null;
  updatedAt: string;
  publicPath: string | null;
};

export type PublishLinkInBioInput = {
  userId: string;
  storeName: string;
  slug: string;
  links: LinkInBioLink[];
  appearance?: LinkInBioAppearance;
};

export type LinkInBioStore = {
  getForUser: (userId: string) => Promise<LinkInBioProfile | null>;
  getPublishedBySlug: (slug: string) => Promise<LinkInBioProfile | null>;
  publish: (input: PublishLinkInBioInput) => Promise<LinkInBioProfile>;
  unpublish: (userId: string) => Promise<LinkInBioProfile | null>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export class LinkInBioError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string
  ) {
    super(message);
  }
}

export const slugTakenError = () => new LinkInBioError(
  409, 'LINK_IN_BIO_SLUG_TAKEN', 'ชื่อหน้าเว็บนี้ถูกใช้แล้ว กรุณาเลือกชื่ออื่น'
);

const copyProfile = (profile: LinkInBioProfile | undefined): LinkInBioProfile | null =>
  profile ? {
    ...profile, links: profile.links.map((link) => ({ ...link })),
    appearance: normalizeStoredLinkInBioAppearance(profile.appearance, profile.links)
  } : null;

type SlugReservation = { ownerId: string | null; releasedAt: number; reservedUntil: number };

export const createInMemoryLinkInBioStore = ({ now = () => new Date() } = {}): LinkInBioStore => {
  const profiles = new Map<string, LinkInBioProfile>();
  const ownersBySlug = new Map<string, string>();
  const reservations = new Map<string, SlugReservation>();
  const reserveReleasedSlug = (slug: string, ownerId: string | null, releasedAt: number) => {
    reservations.set(slug, { ownerId, releasedAt, reservedUntil: releasedAt + linkInBioSlugReservationMs });
    if (!ownerId) return;
    [...reservations.entries()]
      .filter(([, reservation]) => reservation.ownerId === ownerId)
      .sort(([, left], [, right]) => right.releasedAt - left.releasedAt)
      .slice(maxLinkInBioSlugReservationsPerOwner)
      .forEach(([surplusSlug]) => reservations.delete(surplusSlug));
  };

  return {
    getForUser: async (userId) => copyProfile(profiles.get(userId)),
    getPublishedBySlug: async (slug) => {
      const ownerId = ownersBySlug.get(slug);
      const profile = ownerId ? profiles.get(ownerId) : undefined;
      return profile?.isPublished ? copyProfile(profile) : null;
    },
    publish: async ({ userId, storeName, slug, links, appearance }) => {
      // No await between the uniqueness check and write: concurrent requests
      // cannot claim the same slug in this process. Prisma uses a unique index.
      const existingOwner = ownersBySlug.get(slug);
      if (existingOwner && existingOwner !== userId) {
        throw slugTakenError();
      }
      const previous = profiles.get(userId);
      const currentTime = now();
      if (previous?.slug !== slug) {
        const reservation = reservations.get(slug);
        if (
          isReservedLinkInBioSlug(slug) ||
          (reservation && reservation.ownerId !== userId &&
            reservation.reservedUntil > currentTime.getTime())
        ) {
          throw slugTakenError();
        }
        reservations.delete(slug);
      }
      if (previous && previous.slug !== slug) {
        ownersBySlug.delete(previous.slug);
        reserveReleasedSlug(previous.slug, userId, currentTime.getTime());
      }
      const timestamp = currentTime.toISOString();
      const profile: LinkInBioProfile = {
        storeName, slug, links: links.map((link) => ({ ...link })),
        appearance: normalizeStoredLinkInBioAppearance(appearance ?? previous?.appearance, links),
        isPublished: true, publishedAt: timestamp, updatedAt: timestamp,
        publicPath: `/p/${slug}`
      };
      ownersBySlug.set(slug, userId);
      profiles.set(userId, profile);
      return copyProfile(profile)!;
    },
    unpublish: async (userId) => {
      const profile = profiles.get(userId);
      if (!profile) return null;
      const unpublished = {
        ...profile, isPublished: false, publishedAt: null,
        updatedAt: now().toISOString(), publicPath: null
      };
      profiles.set(userId, unpublished);
      return copyProfile(unpublished);
    },
    deleteAllForUser: async (userId) => {
      const profile = profiles.get(userId);
      for (const reservation of reservations.values()) {
        if (reservation.ownerId === userId) reservation.ownerId = null;
      }
      if (profile) {
        ownersBySlug.delete(profile.slug);
        reserveReleasedSlug(profile.slug, null, now().getTime());
      }
      profiles.delete(userId);
    }
  };
};
