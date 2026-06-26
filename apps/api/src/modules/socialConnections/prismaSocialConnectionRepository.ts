import {
  type SocialConnection,
  type SocialConnectionPlatform,
  type SocialConnectionStore,
  type UpsertSocialConnectionInput,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

type PrismaSocialConnection = {
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName: string | null;
  externalAccountId: string | null;
  connectedAt: Date;
};

type SocialConnectionSelect = {
  userId: true;
  platform: true;
  postPeerAccountId: true;
  displayName: true;
  externalAccountId: true;
  connectedAt: true;
};

type SocialConnectionWriteData = {
  postPeerAccountId: string;
  displayName: string | null;
  externalAccountId: string | null;
};

type SocialConnectionDelegate = {
  findMany: (args: {
    where: { userId: string };
    select: SocialConnectionSelect;
  }) => Promise<PrismaSocialConnection[]>;
  findUnique: (args: {
    where: {
      userId_platform: {
        userId: string;
        platform: SocialConnectionPlatform;
      };
    };
    select: {
      postPeerAccountId: true;
    };
  }) => Promise<{ postPeerAccountId: string } | null>;
  upsert: (args: {
    where: {
      userId_platform: {
        userId: string;
        platform: SocialConnectionPlatform;
      };
    };
    update: SocialConnectionWriteData;
    create: SocialConnectionWriteData & {
      userId: string;
      platform: SocialConnectionPlatform;
    };
    select: SocialConnectionSelect;
  }) => Promise<PrismaSocialConnection>;
  deleteMany: (args: {
    where: {
      userId: string;
      platform?: SocialConnectionPlatform;
    };
  }) => Promise<{ count: number }>;
};

export type PrismaSocialConnectionClient = {
  socialConnection: SocialConnectionDelegate;
};

const socialConnectionSelect = {
  userId: true,
  platform: true,
  postPeerAccountId: true,
  displayName: true,
  externalAccountId: true,
  connectedAt: true
} satisfies SocialConnectionSelect;

const disconnectedConnection = ({
  userId,
  platform
}: {
  userId: string;
  platform: SocialConnectionPlatform;
}): SocialConnection => ({
  userId,
  platform,
  status: 'DISCONNECTED'
});

const mapConnection = (record: PrismaSocialConnection): SocialConnection => ({
  userId: record.userId,
  platform: record.platform,
  status: 'CONNECTED',
  postPeerAccountId: record.postPeerAccountId,
  ...(record.displayName !== null ? { displayName: record.displayName } : {}),
  ...(record.externalAccountId !== null
    ? { externalAccountId: record.externalAccountId }
    : {}),
  connectedAt: record.connectedAt.toISOString()
});

const writeData = ({
  postPeerAccountId,
  displayName,
  externalAccountId
}: UpsertSocialConnectionInput): SocialConnectionWriteData => ({
  postPeerAccountId,
  displayName: displayName ?? null,
  externalAccountId: externalAccountId ?? null
});

export const createPrismaSocialConnectionRepository = ({
  prisma
}: {
  prisma: PrismaSocialConnectionClient;
}): SocialConnectionStore => ({
  listForUser: async (userId) => {
    const records = await prisma.socialConnection.findMany({
      where: {
        userId
      },
      select: socialConnectionSelect
    });
    const connectedByPlatform = new Map(
      records.map((record) => [record.platform, mapConnection(record)])
    );

    return supportedSocialConnectionPlatforms.map(
      (platform) =>
        connectedByPlatform.get(platform) ?? disconnectedConnection({ userId, platform })
    );
  },
  getAccountId: async ({ userId, platform }) => {
    const record = await prisma.socialConnection.findUnique({
      where: {
        userId_platform: {
          userId,
          platform
        }
      },
      select: {
        postPeerAccountId: true
      }
    });

    return record?.postPeerAccountId;
  },
  upsert: async (input) => {
    const data = writeData(input);
    const record = await prisma.socialConnection.upsert({
      where: {
        userId_platform: {
          userId: input.userId,
          platform: input.platform
        }
      },
      update: data,
      create: {
        userId: input.userId,
        platform: input.platform,
        ...data
      },
      select: socialConnectionSelect
    });

    return mapConnection(record);
  },
  disconnect: async ({ userId, platform }) => {
    await prisma.socialConnection.deleteMany({
      where: {
        userId,
        platform
      }
    });
  },
  deleteAllForUser: async (userId) => {
    await prisma.socialConnection.deleteMany({
      where: {
        userId
      }
    });
  }
});
