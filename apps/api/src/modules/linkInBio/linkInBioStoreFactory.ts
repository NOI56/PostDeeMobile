import type { ServerConfig } from '../../config/env.js';
import { createInMemoryLinkInBioStore, LinkInBioError, type LinkInBioStore } from './linkInBioStore.js';
import { createPrismaLinkInBioRepository, type PrismaLinkInBioClient } from './prismaLinkInBioRepository.js';

export const createLinkInBioStoreFromConfig = ({
  config, prisma, now
}: {
  config: Pick<ServerConfig, 'postStore'>;
  prisma?: Partial<PrismaLinkInBioClient>;
  now?: () => Date;
}): LinkInBioStore => {
  if (config.postStore !== 'prisma') return createInMemoryLinkInBioStore({ now });
  if (prisma?.linkInBioProfile) {
    return createPrismaLinkInBioRepository({
      prisma: { linkInBioProfile: prisma.linkInBioProfile }, now
    });
  }
  // Older injected Prisma mocks remain compatible. A real deployment must
  // generate the new client and apply the migration; never lose data in memory.
  const unavailable = async (): Promise<never> => {
    throw new LinkInBioError(503, 'LINK_IN_BIO_UNAVAILABLE', 'ระบบหน้าเว็บร้านค้ายังไม่พร้อม กรุณาลองใหม่ภายหลัง');
  };
  return { getForUser: unavailable, getPublishedBySlug: unavailable, publish: unavailable, unpublish: unavailable };
};
