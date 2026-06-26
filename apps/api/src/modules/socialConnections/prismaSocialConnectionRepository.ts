import {
  type SocialConnection,
  type SocialConnectionPlatform,
  type SocialConnectionStore,
  type UpsertSocialConnectionInput,
  isSocialConnectionPlatform,
  supportedSocialConnectionPlatforms
} from './socialConnectionStore.js';

type PrismaSocialConnection = {
  userId: string;
  platform: string;
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
    where: {
      userId: string;
      platform?: {
        in: SocialConnectionPlatform[];
      };
    };
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

const normalizeOptionalMetadata = (value?: string | null): string | undefined =>
  value === undefined || value === null || value.trim() === '' ? undefined : value;

const mapConnection = (
  record: PrismaSocialConnection
): SocialConnection | undefined => {
  if (!isSocialConnectionPlatform(record.platform)) {
    return undefined;
  }

  const displayName = normalizeOptionalMetadata(record.displayName);
  const externalAccountId = normalizeOptionalMetadata(record.externalAccountId);

  return {
    userId: record.userId,
    platform: record.platform,
    status: 'CONNECTED',
    postPeerAccountId: record.postPeerAccountId,
    ...(displayName ? { displayName } : {}),
    ...(externalAccountId ? { externalAccountId } : {}),
    connectedAt: record.connectedAt.toISOString()
  };
};

const writeData = ({
  postPeerAccountId,
  displayName,
  externalAccountId
}: UpsertSocialConnectionInput): SocialConnectionWriteData => ({
  postPeerAccountId,
  displayName: normalizeOptionalMetadata(displayName) ?? null,
  externalAccountId: normalizeOptionalMetadata(externalAccountId) ?? null
});

export const createPrismaSocialConnectionRepository = ({
  prisma
}: {
  prisma: PrismaSocialConnectionClient;
}): SocialConnectionStore => ({
  listForUser: async (userId) => {
    const records = await prisma.socialConnection.findMany({
      where: {
        userId,
        platform: {
          in: supportedSocialConnectionPlatforms
        }
      },
      select: socialConnectionSelect
    });
    const connectedByPlatform = new Map<SocialConnectionPlatform, SocialConnection>();

    for (const record of records) {
      const connection = mapConnection(record);

      if (connection) {
        connectedByPlatform.set(connection.platform, connection);
      }
    }

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

    const connection = mapConnection(record);

    if (!connection) {
      throw new Error('Unsupported social connection platform returned from Prisma');
    }

    return connection;
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
