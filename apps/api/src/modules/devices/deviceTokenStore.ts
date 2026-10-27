export type DevicePlatform = 'IOS' | 'ANDROID' | 'WEB';

export type DeviceToken = {
  userId: string;
  token: string;
  platform?: DevicePlatform;
  updatedAt: string;
};

export type RegisterDeviceTokenInput = {
  userId: string;
  token: string;
  platform?: DevicePlatform;
};

export type DeviceTokenStore = {
  // Upserts a device token, binding it to the current user (a token can move to
  // a new user, e.g. after a shared-device re-login).
  register: (input: RegisterDeviceTokenInput) => Promise<DeviceToken>;
  // All tokens for a user — used by the (future) push sender to target devices.
  listForUser: (userId: string) => Promise<DeviceToken[]>;
  // Deletes tokens the push provider reported as invalid, only for their owner.
  removeTokens: (input: { userId: string; tokens: string[] }) => Promise<void>;
  // Hard-deletes every token owned by userId. Used by account deletion. Optional
  // because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

// Reinstalls and new phones leave old tokens behind. Keeping only the newest
// bounds each push to a small batch and stops one account storing thousands.
export const maxDeviceTokensPerUser = 10;

export const createInMemoryDeviceTokenStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): DeviceTokenStore => {
  const tokens = new Map<string, DeviceToken>();

  return {
    register: async ({ userId, token, platform }) => {
      const record: DeviceToken = {
        userId,
        token,
        platform,
        updatedAt: now()
      };

      tokens.set(token, record);

      const staleTokens = [...tokens.values()]
        .filter((candidate) => candidate.userId === userId)
        .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
        .slice(maxDeviceTokensPerUser);
      for (const stale of staleTokens) {
        tokens.delete(stale.token);
      }

      return record;
    },
    listForUser: async (userId) =>
      [...tokens.values()].filter((record) => record.userId === userId),
    removeTokens: async ({ userId, tokens: staleTokens }) => {
      for (const token of staleTokens) {
        if (tokens.get(token)?.userId === userId) {
          tokens.delete(token);
        }
      }
    },
    deleteAllForUser: async (userId) => {
      for (const [token, record] of tokens) {
        if (record.userId === userId) {
          tokens.delete(token);
        }
      }
    }
  };
};
