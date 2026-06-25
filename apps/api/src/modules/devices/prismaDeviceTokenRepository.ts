import type {
  DevicePlatform,
  DeviceToken,
  DeviceTokenStore
} from './deviceTokenStore.js';

type PrismaDeviceToken = {
  userId: string;
  token: string;
  platform: string | null;
  updatedAt: Date;
};

type DeviceTokenSelect = {
  userId: true;
  token: true;
  platform: true;
  updatedAt: true;
};

type DeviceTokenDelegate = {
  upsert: (args: {
    where: { token: string };
    update: { userId: string; platform?: string | null };
    create: { userId: string; token: string; platform?: string | null };
    select: DeviceTokenSelect;
  }) => Promise<PrismaDeviceToken>;
  findMany: (args: {
    where: { userId: string };
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
  updatedAt: true
} satisfies DeviceTokenSelect;

const mapToken = (record: PrismaDeviceToken): DeviceToken => ({
  userId: record.userId,
  token: record.token,
  platform: (record.platform ?? undefined) as DevicePlatform | undefined,
  updatedAt: record.updatedAt.toISOString()
});

export const createPrismaDeviceTokenRepository = ({
  prisma
}: {
  prisma: PrismaDeviceTokenClient;
}): DeviceTokenStore => ({
  register: async ({ userId, token, platform }) => {
    const record = await prisma.deviceToken.upsert({
      where: { token },
      update: { userId, platform: platform ?? null },
      create: { userId, token, platform: platform ?? null },
      select: deviceTokenSelect
    });

    return mapToken(record);
  },
  listForUser: async (userId) => {
    const records = await prisma.deviceToken.findMany({
      where: { userId },
      select: deviceTokenSelect
    });

    return records.map(mapToken);
  }
  // deleteAllForUser is intentionally omitted: the User cascade removes tokens.
});
