import {
  type SocialConnectionStore,
  createInMemorySocialConnectionStore
} from './socialConnectionStore.js';
import {
  type PrismaSocialConnectionClient,
  createPrismaSocialConnectionRepository
} from './prismaSocialConnectionRepository.js';

export const createSocialConnectionStore = ({
  prisma
}: {
  prisma?: PrismaSocialConnectionClient;
} = {}): SocialConnectionStore =>
  prisma
    ? createPrismaSocialConnectionRepository({ prisma })
    : createInMemorySocialConnectionStore();
