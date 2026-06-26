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

export type SocialConnectionStatus = 'CONNECTED' | 'DISCONNECTED';

export type SocialConnection = {
  userId: string;
  platform: SocialConnectionPlatform;
  status: SocialConnectionStatus;
  postPeerAccountId?: string;
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
  listForUser: (userId: string) => Promise<SocialConnection[]>;
  getAccountId: (
    input: GetSocialConnectionAccountIdInput
  ) => Promise<string | undefined>;
  upsert: (input: UpsertSocialConnectionInput) => Promise<SocialConnection>;
  disconnect: (input: DisconnectSocialConnectionInput) => Promise<void>;
  deleteAllForUser: (userId: string) => Promise<void>;
};

const connectionKey = ({
  userId,
  platform
}: {
  userId: string;
  platform: SocialConnectionPlatform;
}) => `${userId}:${platform}`;

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

const connectedConnection = ({
  userId,
  platform,
  postPeerAccountId,
  displayName,
  externalAccountId,
  connectedAt
}: UpsertSocialConnectionInput & { connectedAt: string }): SocialConnection => ({
  userId,
  platform,
  status: 'CONNECTED',
  postPeerAccountId,
  ...(displayName ? { displayName } : {}),
  ...(externalAccountId ? { externalAccountId } : {}),
  connectedAt
});

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
          connections.get(connectionKey({ userId, platform })) ??
          disconnectedConnection({ userId, platform })
      ),
    getAccountId: async (input) =>
      connections.get(connectionKey(input))?.postPeerAccountId,
    upsert: async (input) => {
      const record = connectedConnection({
        ...input,
        connectedAt: now()
      });

      connections.set(connectionKey(input), record);
      return record;
    },
    disconnect: async (input) => {
      connections.delete(connectionKey(input));
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
