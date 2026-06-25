import type { ServerConfig } from '../../config/env.js';
import {
  type AiEditUsageStore,
  createInMemoryAiEditUsageStore
} from './aiEditUsageStore.js';
import {
  createPrismaAiEditUsageRepository,
  type PrismaAiEditUsageClient
} from './prismaAiEditUsageRepository.js';

type AiEditUsageStoreConfig = Pick<ServerConfig, 'aiEditUsageStore'>;

export const createAiEditUsageStoreFromConfig = ({
  config,
  prisma
}: {
  config: AiEditUsageStoreConfig;
  prisma?: PrismaAiEditUsageClient;
}): AiEditUsageStore => {
  if (config.aiEditUsageStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma AI edit usage store requires a Prisma client');
    }

    return createPrismaAiEditUsageRepository({ prisma });
  }

  return createInMemoryAiEditUsageStore();
};
