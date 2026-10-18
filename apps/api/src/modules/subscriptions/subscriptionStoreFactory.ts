import type { ServerConfig } from '../../config/env.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import {
  type PrismaSubscriptionClient,
  createPrismaSubscriptionRepository
} from './prismaSubscriptionRepository.js';
import { type SubscriptionStore, createSubscriptionStore } from './subscriptionStore.js';
import type { PrismaClient } from '@prisma/client';
import { withTrialAccess, type TrialAccessStore } from '../admin/trialAccess.js';
import { createPrismaTrialAccessStore } from '../admin/prismaTrialAccessStore.js';

type SubscriptionStoreConfig = Pick<ServerConfig, 'subscriptionStore' | 'trialAccessEnabled'>;

export const createSubscriptionStoreFromConfig = ({
  config,
  prisma,
  runWithActiveOwner,
  trialStore,
  now
}: {
  config: SubscriptionStoreConfig;
  prisma?: PrismaSubscriptionClient;
  runWithActiveOwner?: RunWithActiveOwner;
  trialStore?: TrialAccessStore;
  now?: () => Date;
}): SubscriptionStore => {
  const wrap = (store: SubscriptionStore) => {
    if (!config.trialAccessEnabled) return store;
    const trials = trialStore ?? (prisma ? createPrismaTrialAccessStore(prisma as unknown as PrismaClient) : undefined);
    if (!trials) throw new Error('Trial access requires a durable store or an injected test store');
    return withTrialAccess(store, trials, now);
  };
  if (config.subscriptionStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma subscription store requires a Prisma client');
    }

    return wrap(createPrismaSubscriptionRepository({ prisma }));
  }

  return wrap(createSubscriptionStore({ runWithActiveOwner }));
};
