import type { AuthUser } from '../auth/authTypes.js';

export type AppUser = {
  id: string;
  firebaseUid: string;
  email: string;
  displayName?: string;
  createdAt: string;
  updatedAt: string;
};

export type UserStore = {
  ensure: (authUser: AuthUser) => Promise<AppUser>;
  // Hard-deletes the user record for userId. Used by account deletion. Optional
  // because the Prisma store deletes the user (and cascades) elsewhere.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const buildFirebaseUid = (authUser: AuthUser) =>
  authUser.provider === 'firebase' ? authUser.id : `mock:${authUser.id}`;

const sanitizeEmailLocalPart = (value: string) =>
  value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '');

export const buildFallbackEmail = (authUser: AuthUser) => {
  const localPart = sanitizeEmailLocalPart(`${authUser.provider}-${authUser.id}`) || 'local-user';
  return `${localPart}@postdee.local`;
};

export const normalizeAuthUserForStorage = (authUser: AuthUser) => ({
  id: authUser.id,
  firebaseUid: buildFirebaseUid(authUser),
  email: authUser.email ?? buildFallbackEmail(authUser),
  displayName: authUser.displayName
});

export const createUserStore = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): UserStore => {
  const users = new Map<string, AppUser>();

  return {
    ensure: async (authUser) => {
      const normalizedUser = normalizeAuthUserForStorage(authUser);
      const existingUser = users.get(authUser.id);
      const timestamp = now();
      const user = {
        ...existingUser,
        ...normalizedUser,
        createdAt: existingUser?.createdAt ?? timestamp,
        updatedAt: timestamp
      };

      users.set(authUser.id, user);
      return user;
    },
    deleteAllForUser: async (userId) => {
      users.delete(userId);
    }
  };
};
