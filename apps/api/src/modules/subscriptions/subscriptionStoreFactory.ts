import type { ServerConfig } from '../../config/env.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import {
  type PrismaSubscriptionClient,
  createPrismaSubscriptionRepository
} from './prismaSubscriptionRepository.js';
import { type SubscriptionStore, createSubscriptionStore } from './subscriptionStore.js';

type SubscriptionStoreConfig = Pick<ServerConfig, 'subscriptionStore'>;

export const createSubscriptionStoreFromConfig = ({
  config,
  prisma,
  runWithActiveOwner
}: {
  config: SubscriptionStoreConfig;
  prisma?: PrismaSubscriptionClient;
  runWithActiveOwner?: RunWithActiveOwner;
}): SubscriptionStore => {
  if (config.subscriptionStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma subscription store requires a Prisma client');
    }

    return createPrismaSubscriptionRepository({ prisma });
  }

  return createSubscriptionStore({ runWithActiveOwner });
};
