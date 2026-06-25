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
  if (config.postStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma user store requires a Prisma client');
    }

    return createPrismaUserRepository({ prisma });
  }

  return createUserStore();
};
