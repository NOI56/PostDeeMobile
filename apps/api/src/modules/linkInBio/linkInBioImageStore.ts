import { LinkInBioError } from './linkInBioStore.js';

export type LinkInBioImage = {
  id: string; userId: string; slot: 'logo' | 'cover' | 'background';
  storageKey: string; sizeBytes: number; createdAt: Date;
  // Mock storage keeps bytes in memory; real bytes live in the existing private bucket.
  bytes?: Uint8Array;
};
export type LinkInBioImageStore = {
  get: (key: string) => Promise<LinkInBioImage | null>;
  list: (userId: string) => Promise<LinkInBioImage[]>;
  save: (image: LinkInBioImage) => Promise<void>;
  remove: (userId: string, key: string) => Promise<void>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};
export type PrismaLinkInBioImageClient = {
  linkInBioImage: {
    findUnique: (args: { where: { storageKey: string } }) => Promise<LinkInBioImage | null>;
    findMany: (args: { where: { userId: string }; orderBy: { createdAt: 'desc' } }) => Promise<LinkInBioImage[]>;
    create: (args: { data: Omit<LinkInBioImage, 'bytes'> }) => Promise<unknown>;
    deleteMany: (args: { where: { userId: string; storageKey: string } }) => Promise<unknown>;
  };
};

const copy = (image: LinkInBioImage): LinkInBioImage => ({
  ...image, createdAt: new Date(image.createdAt), bytes: image.bytes?.slice()
});
export const createInMemoryLinkInBioImageStore = (): LinkInBioImageStore => {
  const images = new Map<string, LinkInBioImage>();
  return {
    get: async (key) => images.has(key) ? copy(images.get(key)!) : null,
    list: async (userId) => [...images.values()].filter((image) => image.userId === userId)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).map(copy),
    save: async (image) => { images.set(image.storageKey, copy(image)); },
    remove: async (userId, key) => { if (images.get(key)?.userId === userId) images.delete(key); },
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
  if (!delegate) {
    const unavailable = async (): Promise<never> => {
      throw new LinkInBioError(503, 'LINK_IN_BIO_IMAGES_UNAVAILABLE', 'ระบบรูปหน้าเว็บยังไม่พร้อม กรุณาลองใหม่ภายหลัง');
    };
    return { get: unavailable, list: unavailable, save: unavailable, remove: unavailable };
  }
  return {
    get: (storageKey) => delegate.findUnique({ where: { storageKey } }),
    list: (userId) => delegate.findMany({ where: { userId }, orderBy: { createdAt: 'desc' } }),
    save: async ({ bytes: _bytes, ...data }) => { await delegate.create({ data }); },
    remove: async (userId, storageKey) => { await delegate.deleteMany({ where: { userId, storageKey } }); }
    // The User cascade removes Prisma metadata after account media cleanup.
  };
};
