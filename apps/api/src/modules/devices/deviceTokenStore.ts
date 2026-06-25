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

      tokens.set(token, record);
      return record;
    },
    listForUser: async (userId) =>
      [...tokens.values()].filter((record) => record.userId === userId),
    deleteAllForUser: async (userId) => {
      for (const [token, record] of tokens) {
        if (record.userId === userId) {
          tokens.delete(token);
        }
      }
    }
  };
};
