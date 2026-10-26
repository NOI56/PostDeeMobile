import { Prisma, type PrismaClient } from '@prisma/client';
import { AdminError } from './trialAccess.js';
import type { AdminAccountDeletion, AdminAccountDeletionStore } from './adminAccountDeletion.js';

type Row = { requestId: string; actorId: string; userId: string; reason: string; intentHash: string; status: string;
  lastErrorCode: string | null; createdAt: Date; completedAt: Date | null };
const map = (r: Row): AdminAccountDeletion => ({ ...r, status: r.status as AdminAccountDeletion['status'],
  createdAt: r.createdAt.toISOString(), completedAt: r.completedAt?.toISOString() ?? null });

export const createPrismaAdminAccountDeletionStore = (prisma: PrismaClient,
  now: () => Date = () => new Date()): AdminAccountDeletionStore => ({
  find: async requestId => {
    const row = await prisma.adminAccountDeletion.findUnique({ where: { requestId } });
    return row ? map(row) : null;
  },
  start: async record => {
    try {
      return map(await prisma.adminAccountDeletion.create({ data: { ...record, status: 'PENDING', createdAt: now() } }));
    } catch (error) {
      // A concurrent submit of the same request id inserted first.
      if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') throw error;
      const row = await prisma.adminAccountDeletion.findUnique({ where: { requestId: record.requestId } });
      if (!row) throw new AdminError('ADMIN_ACCOUNT_DELETION_UNAVAILABLE', 503);
      return map(row);
    }
  },
  complete: async requestId => {
    await prisma.adminAccountDeletion.updateMany({ where: { requestId, status: 'PENDING' },
      data: { status: 'COMPLETED', lastErrorCode: null, completedAt: now() } });
    const row = await prisma.adminAccountDeletion.findUnique({ where: { requestId } });
    if (!row) throw new AdminError('ADMIN_ACCOUNT_DELETION_UNAVAILABLE', 503);
    return map(row);
  },
  fail: async (requestId, code) => {
    await prisma.adminAccountDeletion.updateMany({ where: { requestId, status: 'PENDING' }, data: { lastErrorCode: code } });
  },
  history: async () => (await prisma.adminAccountDeletion.findMany({ orderBy: [{ createdAt: 'desc' }, { requestId: 'desc' }], take: 100 }))
    .map(map)
});
