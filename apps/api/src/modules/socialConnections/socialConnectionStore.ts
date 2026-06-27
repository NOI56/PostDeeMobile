import type { Platform } from '../posts/postStore.js';

export type SocialConnectionPlatform =
  | 'TIKTOK'
  | 'YOUTUBE_SHORTS'
  | 'INSTAGRAM_REELS'
  | 'FACEBOOK_REELS';

export const supportedSocialConnectionPlatforms: SocialConnectionPlatform[] = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS'
];

export const isSocialConnectionPlatform = (
  value: unknown
): value is SocialConnectionPlatform =>
  typeof value === 'string' &&
  supportedSocialConnectionPlatforms.includes(value as SocialConnectionPlatform);

export const isPublishableSocialPlatform = (
  platform: Platform
): platform is SocialConnectionPlatform => isSocialConnectionPlatform(platform);

export type SocialConnection = {
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName?: string;
  externalAccountId?: string;
  connectedAt: string;
  updatedAt: string;
};

export type SocialConnectionStatus = {
  platform: SocialConnectionPlatform;
  connected: boolean;
  displayName?: string;
  externalAccountId?: string;
  connectedAt?: string;
};

export type UpsertSocialConnectionInput = {
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName?: string;
  externalAccountId?: string;
};

export type GetSocialConnectionAccountIdInput = {
  userId: string;
  platform: SocialConnectionPlatform;
};

export type DisconnectSocialConnectionInput = {
  userId: string;
  platform: SocialConnectionPlatform;
};

export type SocialConnectionStore = {
  listForUser: (userId: string) => Promise<SocialConnectionStatus[]>;
  getAccountId: (
    input: GetSocialConnectionAccountIdInput
  ) => Promise<string | undefined>;
  upsert: (input: UpsertSocialConnectionInput) => Promise<SocialConnection>;
  disconnect: (input: DisconnectSocialConnectionInput) => Promise<boolean>;
  deleteAllForUser?: (userId: string) => Promise<void>;
};

const connectionKey = ({
  userId,
  platform
}: {
  userId: string;
  platform: SocialConnectionPlatform;
}) => `${userId}:${platform}`;

const disconnectedStatus = (platform: SocialConnectionPlatform): SocialConnectionStatus => ({
  platform,
  connected: false
});

const normalizeOptionalMetadata = (value?: string): string | undefined =>
  value === undefined || value.trim() === '' ? undefined : value;

const connectedConnection = ({
  userId,
  platform,
  postPeerAccountId,
  displayName,
  externalAccountId,
  connectedAt,
  updatedAt
}: UpsertSocialConnectionInput & {
  connectedAt: string;
  updatedAt: string;
}): SocialConnection => {
  const normalizedDisplayName = normalizeOptionalMetadata(displayName);
  const normalizedExternalAccountId = normalizeOptionalMetadata(externalAccountId);

  return {
    userId,
    platform,
    postPeerAccountId,
    ...(normalizedDisplayName ? { displayName: normalizedDisplayName } : {}),
    ...(normalizedExternalAccountId
      ? { externalAccountId: normalizedExternalAccountId }
      : {}),
    connectedAt,
    updatedAt
  };
};

const connectionStatus = (
  platform: SocialConnectionPlatform,
  connection?: SocialConnection
): SocialConnectionStatus => {
  if (!connection) {
    return disconnectedStatus(platform);
  }

  return {
    platform,
    connected: true,
    displayName: connection.displayName,
    externalAccountId: connection.externalAccountId,
    connectedAt: connection.connectedAt
  };
};

export const createInMemorySocialConnectionStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): SocialConnectionStore => {
  const connections = new Map<string, SocialConnection>();

  return {
    listForUser: async (userId) =>
      supportedSocialConnectionPlatforms.map(
        (platform) =>
          connectionStatus(platform, connections.get(connectionKey({ userId, platform })))
      ),
    getAccountId: async (input) =>
      connections.get(connectionKey(input))?.postPeerAccountId,
    upsert: async (input) => {
      const key = connectionKey(input);
      const existingConnection = connections.get(key);
      const timestamp = now();
      const record = connectedConnection({
        ...input,
        connectedAt: existingConnection?.connectedAt ?? timestamp,
        updatedAt: timestamp
      });

      connections.set(key, record);
      return record;
    },
    disconnect: async (input) => {
      return connections.delete(connectionKey(input));
    },
    deleteAllForUser: async (userId) => {
      for (const [key, record] of connections) {
        if (record.userId === userId) {
          connections.delete(key);
        }
      }
    }
  };
};
