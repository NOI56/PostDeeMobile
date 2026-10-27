import type { ServerConfig } from '../../config/env.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import {
  type PrismaUserClient,
  createPrismaUserRepository
} from './prismaUserRepository.js';
import { type UserStore, createUserStore } from './userStore.js';

type UserStoreConfig = Pick<ServerConfig, 'postStore'>;

export const createUserStoreForPostStore = ({
  config,
  prisma,
  runWithActiveOwner
}: {
  config: UserStoreConfig;
  prisma?: PrismaUserClient;
  runWithActiveOwner?: RunWithActiveOwner;
}): UserStore => {
  // Every Prisma-backed relation points at User, including templates,
  // subscriptions, device tokens, and social connections. Once the app has a
  // Prisma client, keep the canonical user in the same database even when posts
  // themselves intentionally use the in-memory store.
  if (prisma) {
    return createPrismaUserRepository({ prisma });
  }

  if (config.postStore === 'prisma') {
    throw new Error('Prisma user store requires a Prisma client');
  }

  return createUserStore({ runWithActiveOwner });
};
