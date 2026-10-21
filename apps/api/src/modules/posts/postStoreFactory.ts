import type { ServerConfig } from '../../config/env.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import {
  type PrismaPostClient,
  createPrismaPostRepository
} from './prismaPostRepository.js';
import { type PostStore, createPostStore } from './postStore.js';

type PostStoreConfig = Pick<ServerConfig, 'postStore'>;

export const createPostStoreFromConfig = ({
  config,
  prisma,
  runWithActiveOwner,
  monthlyAddonStore
}: {
  config: PostStoreConfig;
  prisma?: PrismaPostClient;
  runWithActiveOwner?: RunWithActiveOwner;
  monthlyAddonStore?: Pick<MonthlyAddonStore, 'readCredits'>;
}): PostStore => {
  if (config.postStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma post store requires a Prisma client');
    }

    return createPrismaPostRepository({ prisma });
  }

  return createPostStore({ runWithActiveOwner, monthlyAddonStore });
};
