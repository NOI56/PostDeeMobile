import type { ServerConfig } from '../../config/env.js';
import {
  type PrismaTemplateClient,
  createPrismaTemplateRepository
} from './prismaTemplateRepository.js';
import { type TemplateStore, createTemplateStore } from './templateStore.js';

type TemplateStoreConfig = Pick<ServerConfig, 'templateStore'>;

export const createTemplateStoreFromConfig = ({
  config,
  prisma
}: {
  config: TemplateStoreConfig;
  prisma?: PrismaTemplateClient;
}): TemplateStore => {
  if (config.templateStore === 'prisma') {
    if (!prisma) {
      throw new Error('Prisma template store requires a Prisma client');
    }

    return createPrismaTemplateRepository({ prisma });
  }

  return createTemplateStore();
};
