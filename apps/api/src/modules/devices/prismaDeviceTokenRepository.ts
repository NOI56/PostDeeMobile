import type { AppLanguage } from '../shared/appLanguage.js';
import {
  maxDeviceTokensPerOwner,
  type DevicePlatform,
  type DeviceToken,
  type DeviceTokenStore
} from './deviceTokenStore.js';

type PrismaDeviceToken = {
  userId: string;
  token: string;
  platform: string | null;
  language: AppLanguage | null;
  updatedAt: Date;
};

type DeviceTokenSelect = {
  userId: true;
  token: true;
  platform: true;
  language: true;
  updatedAt: true;
};

type DeviceTokenDelegate = {
  deleteMany: (args: {
    where: { userId: string; token: string | { in: string[] } };
  }) => Promise<{ count: number }>;
  upsert: (args: {
    where: { token: string };
    update: { userId: string; platform?: string | null; language: AppLanguage | null };
    create: { userId: string; token: string; platform?: string | null; language: AppLanguage | null };
    select: DeviceTokenSelect;
  }) => Promise<PrismaDeviceToken>;
  findMany: (args: {
    where: { userId: string };
    orderBy: { updatedAt: 'desc' };
    take?: number;
    skip?: number;
    select: DeviceTokenSelect;
  }) => Promise<PrismaDeviceToken[]>;
};

export type PrismaDeviceTokenClient = {
  deviceToken: DeviceTokenDelegate;
};

const deviceTokenSelect = {
  userId: true,
  token: true,
  platform: true,
  language: true,
  updatedAt: true
} satisfies DeviceTokenSelect;

const mapToken = (record: PrismaDeviceToken): DeviceToken => ({
  userId: record.userId,
  token: record.token,
  platform: (record.platform ?? undefined) as DevicePlatform | undefined,
  language: record.language ?? null,
  updatedAt: record.updatedAt.toISOString()
});

export const createPrismaDeviceTokenRepository = ({
  prisma
}: {
  prisma: PrismaDeviceTokenClient;
}): DeviceTokenStore => ({
  register: async ({ userId, token, platform, language }) => {
    const record = await prisma.deviceToken.upsert({
      where: { token },
      update: { userId, platform: platform ?? null, language: language ?? null },
      create: { userId, token, platform: platform ?? null, language: language ?? null },
      select: deviceTokenSelect
    });
    // upsert refreshes updatedAt, so everything past the newest N is stale.
    const staleTokens = await prisma.deviceToken.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
      skip: maxDeviceTokensPerOwner,
      select: deviceTokenSelect
    });
    if (staleTokens.length > 0) {
      await prisma.deviceToken.deleteMany({
        where: { userId, token: { in: staleTokens.map((stale) => stale.token) } }
      });
    }

    return mapToken(record);
  },
  listForUser: async (userId) => {
    const records = await prisma.deviceToken.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
      take: maxDeviceTokensPerOwner,
      select: deviceTokenSelect
    });

    return records.map(mapToken);
  },
  unregister: async ({ userId, token }) => {
    await prisma.deviceToken.deleteMany({ where: { userId, token } });
  }
  // deleteAllForUser is intentionally omitted: the User cascade removes tokens.
});
