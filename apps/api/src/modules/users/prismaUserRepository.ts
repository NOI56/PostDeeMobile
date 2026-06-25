import type { AuthUser } from '../auth/authTypes.js';
import {
  type AppUser,
  type UserStore,
  normalizeAuthUserForStorage
} from './userStore.js';

type PrismaUser = {
  id: string;
  firebaseUid: string;
  email: string;
  displayName?: string | null;
  createdAt: Date;
  updatedAt: Date;
};

type UserDelegate = {
  upsert: (args: {
    where: { id: string };
    update: {
      email: string;
      displayName?: string;
    };
    create: {
      id: string;
      firebaseUid: string;
      email: string;
      displayName?: string;
    };
  }) => Promise<PrismaUser>;
};

export type PrismaUserClient = {
  user: UserDelegate;
};

const mapUser = (user: PrismaUser): AppUser => ({
  id: user.id,
  firebaseUid: user.firebaseUid,
  email: user.email,
  displayName: user.displayName ?? undefined,
  createdAt: user.createdAt.toISOString(),
  updatedAt: user.updatedAt.toISOString()
});

export const createPrismaUserRepository = ({
  prisma
}: {
  prisma: PrismaUserClient;
}): UserStore => ({
  ensure: async (authUser: AuthUser) => {
    const user = normalizeAuthUserForStorage(authUser);
    const persistedUser = await prisma.user.upsert({
      where: { id: user.id },
      update: {
        email: user.email,
        displayName: user.displayName
      },
      create: user
    });

    return mapUser(persistedUser);
  }
});
