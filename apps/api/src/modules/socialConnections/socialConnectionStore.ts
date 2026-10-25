import { randomUUID } from 'node:crypto';

import { buildPlatformTarget } from '../posts/platformTargets.js';
import { buildTikTokConnectionRevision } from '../posts/tikTokDirectSettings.js';
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
  id?: string;
  userId: string;
  platform: SocialConnectionPlatform;
  postPeerAccountId: string;
  displayName?: string;
  externalAccountId?: string;
  connectedAt: string;
  updatedAt: string;
};

export type SocialConnectionStatus = {
  connectionId?: string;
  connectionRevision?: string;
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

export class SocialAccountAlreadyLinkedError extends Error {
  constructor() {
    super('Social account is already linked');
    this.name = 'SocialAccountAlreadyLinkedError';
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

export type DisconnectSocialConnectionSnapshot = {
  connection?: SocialConnection;
  nonceHash?: string;
};

// The raw completion nonce is returned only to the initiating authenticated
// client. Persist its hash and the integrations observed before OAuth starts.
export type SocialConnectAttempt = {
  userId: string;
  platform: SocialConnectionPlatform;
  profileId: string;
  nonceHash: string;
  expiresAt: string;
  baselineIntegrationIds: string[];
};

export type CompleteSocialConnectAttemptInput = {
  userId: string;
  platform: SocialConnectionPlatform;
  profileId: string;
  nonceHash: string;
  integration: Omit<UpsertSocialConnectionInput, 'userId' | 'platform'>;
  now: string;
};

export type ReconcileExistingSocialConnectionInput = {
  userId: string;
  platform: SocialConnectionPlatform;
  expectedPostPeerAccountId: string;
  expectedExternalAccountId?: string;
  integration?: Omit<UpsertSocialConnectionInput, 'userId' | 'platform'>;
};

export const isExpectedSocialConnection = (
  connection: SocialConnection | undefined,
  input: ReconcileExistingSocialConnectionInput
): boolean => Boolean(connection &&
  connection.postPeerAccountId === input.expectedPostPeerAccountId &&
  connection.externalAccountId === input.expectedExternalAccountId &&
  (!input.integration || (
    input.integration.postPeerAccountId === input.expectedPostPeerAccountId &&
    normalizeOptionalMetadata(input.integration.externalAccountId) === input.expectedExternalAccountId
  )));

export const isMatchingSocialConnectAttempt = (
  attempt: SocialConnectAttempt | undefined,
  input: CompleteSocialConnectAttemptInput
): boolean => Boolean(attempt &&
  attempt.userId === input.userId && attempt.platform === input.platform &&
  attempt.profileId === input.profileId && attempt.nonceHash === input.nonceHash &&
  Date.parse(attempt.expiresAt) > Date.parse(input.now) &&
  !attempt.baselineIntegrationIds.includes(input.integration.postPeerAccountId));

export type SocialConnectionStore = {
  listForUser: (userId: string) => Promise<SocialConnectionStatus[]>;
  getAccountId: (
    input: GetSocialConnectionAccountIdInput
  ) => Promise<string | undefined>;
  getConnection: (
    input: GetSocialConnectionAccountIdInput
  ) => Promise<SocialConnection | undefined>;
  upsert: (input: UpsertSocialConnectionInput) => Promise<SocialConnection>;
  reconcileExistingConnection: (input: ReconcileExistingSocialConnectionInput) => Promise<SocialConnection | undefined>;
  disconnect: (input: DisconnectSocialConnectionInput) => Promise<boolean>;
  getDisconnectSnapshot: (input: DisconnectSocialConnectionInput) => Promise<DisconnectSocialConnectionSnapshot>;
  // The PostPeer profile id groups all of a user's connected accounts. It is
  // created once per user and reused for connect URLs and integration polling.
  getProfileId: (userId: string) => Promise<string | undefined>;
  setProfileId: (input: { userId: string; profileId: string }) => Promise<string>;
  beginConnectAttempt: (input: SocialConnectAttempt) => Promise<void>;
  getConnectAttempt: (input: { userId: string; nonceHash: string }) => Promise<SocialConnectAttempt | undefined>;
  completeConnectAttempt: (input: CompleteSocialConnectAttemptInput) => Promise<SocialConnection | undefined>;
  cancelConnectAttempt: (input: { userId: string; platform: SocialConnectionPlatform; nonceHash?: string }) => Promise<void>;
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
  updatedAt,
  id
}: UpsertSocialConnectionInput & {
  connectedAt: string;
  updatedAt: string;
  id: string;
}): SocialConnection => {
  const normalizedDisplayName = normalizeOptionalMetadata(displayName);
  const normalizedExternalAccountId = normalizeOptionalMetadata(externalAccountId);

  return {
    id,
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
    ...(connection.id ? { connectionId: connection.id } : {}),
    connectionRevision: buildTikTokConnectionRevision({ userId: connection.userId, target: buildPlatformTarget(connection) }),
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
  const attempts = new Map<string, SocialConnectAttempt>();
  const providerAccountKeys = new Map<string, string>();
  const externalAccountKeys = new Map<string, string>();

  const removeConnection = (key: string): boolean => {
    const existing = connections.get(key);
    if (!existing) return false;
    providerAccountKeys.delete(existing.postPeerAccountId);
    if (existing.externalAccountId) externalAccountKeys.delete(`${existing.platform}:${existing.externalAccountId}`);
    return connections.delete(key);
  };

  // No await occurs between uniqueness checks and the write, so competing
  // in-memory claims cannot both observe an unclaimed account.
  const upsertConnection = (input: UpsertSocialConnectionInput): SocialConnection => {
    const key = connectionKey(input);
    const externalAccountId = normalizeOptionalMetadata(input.externalAccountId);
    const providerOwner = providerAccountKeys.get(input.postPeerAccountId);
    const externalOwner = externalAccountId ? externalAccountKeys.get(`${input.platform}:${externalAccountId}`) : undefined;
    if ((providerOwner && providerOwner !== key) || (externalOwner && externalOwner !== key)) {
      throw new SocialAccountAlreadyLinkedError();
    }
    const existing = connections.get(key);
    const timestamp = now();
    const record = connectedConnection({ ...input, id: existing?.id ?? randomUUID(), connectedAt: existing?.connectedAt ?? timestamp, updatedAt: timestamp });
    removeConnection(key);
    connections.set(key, record);
    providerAccountKeys.set(record.postPeerAccountId, key);
    if (record.externalAccountId) externalAccountKeys.set(`${record.platform}:${record.externalAccountId}`, key);
    return record;
  };

  return {
    listForUser: async (userId) =>
      supportedSocialConnectionPlatforms.map(
        (platform) =>
          connectionStatus(platform, connections.get(connectionKey({ userId, platform })))
      ),
    getAccountId: async (input) =>
      connections.get(connectionKey(input))?.postPeerAccountId,
    getConnection: async (input) => connections.get(connectionKey(input)),
    upsert: async (input) => upsertConnection(input),
    reconcileExistingConnection: async (input) => {
      const key = connectionKey(input);
      if (!isExpectedSocialConnection(connections.get(key), input)) return undefined;
      if (!input.integration) {
        // A provider refresh may retire an old binding, but must never cancel a
        // newer explicit connect attempt that is still waiting for OAuth.
        removeConnection(key);
        return undefined;
      }
      return upsertConnection({ userId: input.userId, platform: input.platform, ...input.integration });
    },
    disconnect: async (input) => {
      attempts.delete(connectionKey(input));
      return removeConnection(connectionKey(input));
    },
    getDisconnectSnapshot: async (input) => {
      const key = connectionKey(input);
      const connection = connections.get(key);
      const nonceHash = attempts.get(key)?.nonceHash;
      return {
        ...(connection ? { connection: { ...connection } } : {}),
        ...(nonceHash ? { nonceHash } : {})
      };
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
    beginConnectAttempt: async (input) => {
      attempts.set(connectionKey(input), { ...input, baselineIntegrationIds: [...input.baselineIntegrationIds] });
    },
    getConnectAttempt: async ({ userId, nonceHash }) => {
      for (const platform of supportedSocialConnectionPlatforms) {
        const attempt = attempts.get(connectionKey({ userId, platform }));
        if (attempt?.nonceHash === nonceHash) return { ...attempt, baselineIntegrationIds: [...attempt.baselineIntegrationIds] };
      }
      return undefined;
    },
    completeConnectAttempt: async (input) => {
      const key = connectionKey(input);
      if (!isMatchingSocialConnectAttempt(attempts.get(key), input)) return undefined;
      const connection = upsertConnection({ userId: input.userId, platform: input.platform, ...input.integration });
      attempts.delete(key);
      return connection;
    },
    cancelConnectAttempt: async ({ userId, platform, nonceHash }) => {
      const key = connectionKey({ userId, platform });
      if (nonceHash === undefined || attempts.get(key)?.nonceHash === nonceHash) attempts.delete(key);
    },
    deleteAllForUser: async (userId) => {
      const profileId = profiles.get(userId);

      if (profileId) {
        profileOwners.delete(profileId);
      }

      profiles.delete(userId);
      for (const [key, record] of connections) {
        if (record.userId === userId) {
          removeConnection(key);
        }
      }
      for (const platform of supportedSocialConnectionPlatforms) attempts.delete(connectionKey({ userId, platform }));
    }
  };
};
