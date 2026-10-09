import { LinkInBioError } from './linkInBioStore.js';

export type LinkInBioImage = {
  id: string; userId: string; slot: 'logo' | 'cover' | 'background';
  storageKey: string; sizeBytes: number; createdAt: Date;
  draftReferences?: string[];
  legacyRetention?: boolean;
  deletionClaimed?: boolean;
  // Mock storage keeps bytes in memory; real bytes live in the existing private bucket.
  bytes?: Uint8Array;
};
export type LinkInBioImageStore = {
  get: (key: string) => Promise<LinkInBioImage | null>;
  list: (userId: string) => Promise<LinkInBioImage[]>;
  save: (image: LinkInBioImage) => Promise<void>;
  remove: (userId: string, key: string) => Promise<void>;
  addDraftReference: (userId: string, key: string, reference: string) => Promise<boolean>;
  removeDraftReference: (userId: string, key: string, reference: string) => Promise<void>;
  claimPrune: (userId: string, key: string) => Promise<boolean>;
  cancelPrune: (userId: string, key: string) => Promise<void>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};
export type PrismaLinkInBioImageClient = {
  $executeRaw: (query: TemplateStringsArray, ...values: unknown[]) => Promise<number>;
  linkInBioImage: {
    findUnique: (args: { where: { storageKey: string } }) => Promise<LinkInBioImage | null>;
    findMany: (args: { where: { userId: string }; orderBy: { createdAt: 'desc' } }) => Promise<LinkInBioImage[]>;
    create: (args: { data: Omit<LinkInBioImage, 'bytes'> }) => Promise<unknown>;
    deleteMany: (args: { where: { userId: string; storageKey: string } }) => Promise<unknown>;
  };
};

const copy = (image: LinkInBioImage): LinkInBioImage => ({
  ...image, createdAt: new Date(image.createdAt), bytes: image.bytes?.slice(), draftReferences: [...(image.draftReferences ?? [])]
});
export const createInMemoryLinkInBioImageStore = (): LinkInBioImageStore => {
  const images = new Map<string, LinkInBioImage>();
  return {
    get: async (key) => images.has(key) ? copy(images.get(key)!) : null,
    list: async (userId) => [...images.values()].filter((image) => image.userId === userId)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).map(copy),
    save: async (image) => { images.set(image.storageKey, copy(image)); },
    remove: async (userId, key) => { if (images.get(key)?.userId === userId) images.delete(key); },
    addDraftReference: async (userId, key, reference) => {
      const image = images.get(key);
      if (image?.userId !== userId || image.deletionClaimed) return false;
      const references = image.draftReferences ?? [];
      if (!references.includes(reference)) {
        if (references.length >= 32) return false;
        image.draftReferences = [...references, reference];
      }
      return true;
    },
    removeDraftReference: async (userId, key, reference) => {
      const image = images.get(key);
      if (image?.userId === userId) image.draftReferences = (image.draftReferences ?? []).filter((entry) => entry !== reference);
    },
    claimPrune: async (userId, key) => {
      const image = images.get(key);
      if (image?.userId !== userId || image.deletionClaimed || image.legacyRetention !== false || image.draftReferences?.length) return false;
      image.deletionClaimed = true;
      return true;
    },
    cancelPrune: async (userId, key) => {
      const image = images.get(key);
      if (image?.userId === userId) image.deletionClaimed = false;
    },
    deleteAllForUser: async (userId) => {
      for (const [key, image] of images) if (image.userId === userId) images.delete(key);
    }
  };
};

export const createLinkInBioImageStoreFromConfig = ({ postStore, prisma }: {
  postStore: 'memory' | 'prisma'; prisma?: Partial<PrismaLinkInBioImageClient>;
}): LinkInBioImageStore => {
  if (postStore !== 'prisma') return createInMemoryLinkInBioImageStore();
  const delegate = prisma?.linkInBioImage;
  const execute = prisma?.$executeRaw?.bind(prisma);
  if (!delegate || !execute) {
    const unavailable = async (): Promise<never> => {
      throw new LinkInBioError(503, 'LINK_IN_BIO_IMAGES_UNAVAILABLE', 'ระบบรูปหน้าเว็บยังไม่พร้อม กรุณาลองใหม่ภายหลัง');
    };
    return { get: unavailable, list: unavailable, save: unavailable, remove: unavailable,
      addDraftReference: unavailable, removeDraftReference: unavailable, claimPrune: unavailable, cancelPrune: unavailable };
  }
  return {
    get: (storageKey) => delegate.findUnique({ where: { storageKey } }),
    list: (userId) => delegate.findMany({ where: { userId }, orderBy: { createdAt: 'desc' } }),
    save: async ({ bytes: _bytes, ...data }) => { await delegate.create({ data }); },
    remove: async (userId, storageKey) => { await delegate.deleteMany({ where: { userId, storageKey } }); },
    addDraftReference: async (userId, storageKey, reference) => (await execute`
      UPDATE "LinkInBioImage"
      SET "draftReferences" = CASE WHEN "draftReferences" ? ${reference}
        THEN "draftReferences" ELSE "draftReferences" || ${JSON.stringify([reference])}::jsonb END
      WHERE "userId" = ${userId} AND "storageKey" = ${storageKey} AND "deletionClaimed" = false
        AND ("draftReferences" ? ${reference} OR jsonb_array_length("draftReferences") < 32)
    `) > 0,
    removeDraftReference: async (userId, storageKey, reference) => {
      await execute`UPDATE "LinkInBioImage" SET "draftReferences" = "draftReferences" - ${reference}::text
        WHERE "userId" = ${userId} AND "storageKey" = ${storageKey} AND "deletionClaimed" = false`;
    },
    claimPrune: async (userId, storageKey) => (await execute`
      UPDATE "LinkInBioImage" SET "deletionClaimed" = true
      WHERE "userId" = ${userId} AND "storageKey" = ${storageKey}
        AND "legacyRetention" = false AND "draftReferences" = '[]'::jsonb AND "deletionClaimed" = false
        AND NOT EXISTS (SELECT 1 FROM "LinkInBioProfile" AS profile WHERE profile."userId" = ${userId}
          AND (profile."appearance"->>'logoKey' = ${storageKey}
            OR profile."appearance"->>'coverKey' = ${storageKey}
            OR profile."appearance"#>>'{background,imageKey}' = ${storageKey}))
    `) > 0,
    // Only called before attempting storage deletion, after a fresh profile read.
    cancelPrune: async (userId, storageKey) => {
      await execute`UPDATE "LinkInBioImage" SET "deletionClaimed" = false
        WHERE "userId" = ${userId} AND "storageKey" = ${storageKey} AND "deletionClaimed" = true`;
    }
    // The User cascade removes Prisma metadata after account media cleanup.
  };
};
