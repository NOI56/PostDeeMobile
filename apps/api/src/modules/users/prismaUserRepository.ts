import type { AuthUser } from '../auth/authTypes.js';
import { runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';
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
  findUnique: (args: {
    where: { id: string };
    select: { id: true };
  }) => Promise<{ id: string } | null>;
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

type PrismaUserTransaction = PrismaOwnerLifecycleTransaction & {
  user: UserDelegate;
};
export type PrismaUserClient = PrismaUserTransaction & {
  $transaction: <T>(operation: (transaction: PrismaUserTransaction) => Promise<T>, options: {
    isolationLevel: 'Serializable'; maxWait: number; timeout: number;
  }) => Promise<T>;
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
  exists: async (userId) =>
    Boolean(
      await prisma.user.findUnique({
        where: { id: userId },
        select: { id: true }
      })
    ),
  ensure: (authUser: AuthUser) => runActiveOwnerTransaction(prisma, authUser.id, async (transaction) => {
    const user = normalizeAuthUserForStorage(authUser);
    const persistedUser = await transaction.user.upsert({
      where: { id: user.id },
      update: {
        email: user.email,
        displayName: user.displayName
      },
      create: user
    });

    return mapUser(persistedUser);
  })
});
