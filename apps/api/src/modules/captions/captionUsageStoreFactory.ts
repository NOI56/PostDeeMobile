import type { ServerConfig } from '../../config/env.js';
import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import {
  createInMemoryRealClipCaptionUsageStore,
  type RealClipCaptionUsageStore
} from './captionUsageStore.js';
import {
  createPrismaRealClipCaptionUsageRepository,
  type PrismaRealClipCaptionUsageClient
} from './prismaRealClipCaptionUsageRepository.js';

type CaptionUsageStoreConfig = Pick<ServerConfig, 'captionUsageStore'>;

export const createRealClipCaptionUsageStoreFromConfig = ({
  config,
  prisma,
  monthlyAddonStore,
  runWithActiveOwner
}: {
  config: CaptionUsageStoreConfig;
  prisma?: PrismaRealClipCaptionUsageClient;
  monthlyAddonStore?: Pick<MonthlyAddonStore, 'readCredits'>;
  runWithActiveOwner?: RunWithActiveOwner;
}): RealClipCaptionUsageStore => {
  if (config.captionUsageStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma real-clip caption usage store requires a Prisma client');
    }

    return createPrismaRealClipCaptionUsageRepository({ prisma });
  }

  return createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore, runWithActiveOwner });
};
