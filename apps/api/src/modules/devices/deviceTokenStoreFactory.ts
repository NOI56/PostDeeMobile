import {
  type DeviceTokenStore,
  createInMemoryDeviceTokenStore
} from './deviceTokenStore.js';
import {
  type PrismaDeviceTokenClient,
  createPrismaDeviceTokenRepository
} from './prismaDeviceTokenRepository.js';

// Persists device tokens in Prisma when a client is available (production), and
// in memory otherwise (local dev/tests).
export const createDeviceTokenStore = ({
  prisma
}: {
  prisma?: PrismaDeviceTokenClient;
}): DeviceTokenStore =>
  prisma
    ? createPrismaDeviceTokenRepository({ prisma })
    : createInMemoryDeviceTokenStore();
