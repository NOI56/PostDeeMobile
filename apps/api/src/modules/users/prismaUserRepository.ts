import type { AuthUser } from '../auth/authTypes.js';
import { runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';
import {
  type AppUser,
  type UserStore,
  buildFallbackEmail,
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

// Prisma reports the violated fields in meta.target; when it is absent, treat
// the conflict as a possible email collision so the fallback retry can decide.
const isEmailUniqueConflict = (error: unknown) => {
  if (typeof error !== 'object' || error === null || (error as { code?: unknown }).code !== 'P2002') {
    return false;
  }

  const target = (error as { meta?: { target?: unknown } }).meta?.target;
  if (Array.isArray(target)) return target.includes('email');
  if (typeof target === 'string') return target.includes('email');
  return true;
};

export const createPrismaUserRepository = ({
  prisma
}: {
  prisma: PrismaUserClient;
}): UserStore => {
  const upsertUser = (authUser: AuthUser) => runActiveOwnerTransaction(prisma, authUser.id, async (transaction) => {
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
  });

  return {
    exists: async (userId) =>
      Boolean(
        await prisma.user.findUnique({
          where: { id: userId },
          select: { id: true }
        })
      ),
    ensure: async (authUser: AuthUser) => {
      try {
        return await upsertUser(authUser);
      } catch (error) {
        // Another UID (for example a deleted Firebase identity whose PostDee row
        // remains) can still hold this address. Keep that row untouched and give
        // this UID its unique fallback address instead of failing every request.
        if (!authUser.email || authUser.email === buildFallbackEmail(authUser) || !isEmailUniqueConflict(error)) {
          throw error;
        }

        return upsertUser({ ...authUser, email: undefined });
      }
    }
  };
};
