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

export class PostPeerProfileOwnershipConflictError extends Error {
  constructor() {
    super('PostPeer profile is already assigned to another user');
    this.name = 'PostPeerProfileOwnershipConflictError';
  }
}

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
  // The PostPeer profile id groups all of a user's connected accounts. It is
  // created once per user and reused for connect URLs and integration polling.
  getProfileId: (userId: string) => Promise<string | undefined>;
  setProfileId: (input: { userId: string; profileId: string }) => Promise<string>;
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
  const profiles = new Map<string, string>();
  const profileOwners = new Map<string, string>();

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
    getProfileId: async (userId) => profiles.get(userId),
    setProfileId: async ({ userId, profileId }) => {
      const existingProfileId = profiles.get(userId);

      if (existingProfileId) {
        return existingProfileId;
      }

      const currentOwner = profileOwners.get(profileId);

      if (currentOwner && currentOwner !== userId) {
        throw new PostPeerProfileOwnershipConflictError();
      }

      profiles.set(userId, profileId);
      profileOwners.set(profileId, userId);
      return profileId;
    },
    deleteAllForUser: async (userId) => {
      const profileId = profiles.get(userId);

      if (profileId) {
        profileOwners.delete(profileId);
      }

      profiles.delete(userId);
      for (const [key, record] of connections) {
        if (record.userId === userId) {
          connections.delete(key);
        }
      }
    }
  };
};
