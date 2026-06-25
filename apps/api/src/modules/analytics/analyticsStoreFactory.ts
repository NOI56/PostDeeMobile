import type { ServerConfig } from '../../config/env.js';
import {
  type PrismaAnalyticsClient,
  createPrismaAnalyticsRepository
} from './prismaAnalyticsRepository.js';
import { type AnalyticsStore, createInMemoryAnalyticsStore } from './analyticsStore.js';

type AnalyticsStoreConfig = Pick<ServerConfig, 'analyticsStore'>;

export const createAnalyticsStoreFromConfig = ({
  config,
  prisma
}: {
  config: AnalyticsStoreConfig;
  prisma?: PrismaAnalyticsClient;
}): AnalyticsStore => {
  if (config.analyticsStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma analytics store requires a Prisma client');
    }

    return createPrismaAnalyticsRepository({ prisma });
  }

  return createInMemoryAnalyticsStore();
};
