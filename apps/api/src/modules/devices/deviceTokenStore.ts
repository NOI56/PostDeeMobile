export type DevicePlatform = 'IOS' | 'ANDROID' | 'WEB';

export type DeviceToken = {
  userId: string;
  token: string;
  platform?: DevicePlatform;
  updatedAt: string;
};

// One owner rarely has more than a few devices. Registration keeps only the
// most recently refreshed tokens so the notifier's per-owner read stays small.
export const maxDeviceTokensPerOwner = 10;

export type RegisterDeviceTokenInput = {
  userId: string;
  token: string;
  platform?: DevicePlatform;
};

export type DeviceTokenStore = {
  // Upserts a device token, binding it to the current user (a token can move to
  // a new user, e.g. after a shared-device re-login).
  register: (input: RegisterDeviceTokenInput) => Promise<DeviceToken>;
  // The user's newest tokens (at most maxDeviceTokensPerOwner) for the push sender.
  listForUser: (userId: string) => Promise<DeviceToken[]>;
  unregister: (input: { userId: string; token: string }) => Promise<void>;
  // Hard-deletes every token owned by userId. Used by account deletion. Optional
  // because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

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

      tokens.delete(token);
      tokens.set(token, record);
      const owned = [...tokens.values()].filter((entry) => entry.userId === userId);
      // Map order is registration order, so the first entries are the oldest.
      for (const stale of owned.slice(0, Math.max(owned.length - maxDeviceTokensPerOwner, 0))) {
        tokens.delete(stale.token);
      }
      return record;
    },
    // register already evicts beyond maxDeviceTokensPerOwner.
    listForUser: async (userId) =>
      [...tokens.values()].filter((record) => record.userId === userId),
    unregister: async ({ userId, token }) => {
      if (tokens.get(token)?.userId === userId) tokens.delete(token);
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
