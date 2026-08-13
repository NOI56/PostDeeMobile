import type { ServerConfig } from '../../config/env.js';
import {
  type PrismaUserClient,
  createPrismaUserRepository
} from './prismaUserRepository.js';
import { type UserStore, createUserStore } from './userStore.js';

type UserStoreConfig = Pick<ServerConfig, 'postStore'>;

export const createUserStoreForPostStore = ({
  config,
  prisma
}: {
  config: UserStoreConfig;
  prisma?: PrismaUserClient;
}): UserStore => {
  // Every Prisma-backed relation points at User. Once a Prisma client exists,
  // keep the canonical user in the same database even when posts use memory.
  if (prisma) {
    return createPrismaUserRepository({ prisma });
  }

  if (config.postStore === 'prisma') {
    throw new Error('Prisma user store requires a Prisma client');
  }

  return createUserStore();
};
