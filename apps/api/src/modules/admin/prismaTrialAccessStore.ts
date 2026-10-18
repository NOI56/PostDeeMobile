import { Prisma, type PrismaClient } from '@prisma/client';
import { runActiveOwnerTransaction } from '../account/ownerLifecycle.js';
import { AdminError, applyTrialCommand, trialIntentHash, type TrialAccess, type TrialAccessStore, type TrialAudit } from './trialAccess.js';

type Row = { userId: string; plan: string; startsAt: Date; expiresAt: Date; revokedAt: Date | null; version: number };
const map = (r: Row): TrialAccess => ({ ...r, plan: r.plan as TrialAccess['plan'],
  startsAt: r.startsAt.toISOString(), expiresAt: r.expiresAt.toISOString(), revokedAt: r.revokedAt?.toISOString() ?? null });
export const createPrismaTrialAccessStore = (prisma: PrismaClient, now: () => Date = () => new Date()): TrialAccessStore => ({
  find: async userId => {
    const row = await prisma.adminTrialAccess.findUnique({ where: { userId } });
    return row ? map(row) : null;
  },
  history: async () => (await prisma.adminTrialAudit.findMany({ orderBy: [{ createdAt: 'desc' }, { requestId: 'desc' }], take: 100 }))
    .map(r => ({ ...r, action: r.action as TrialAudit['action'], plan: r.plan as TrialAudit['plan'],
      expectedVersion: ((r.before as unknown as TrialAccess | null)?.version ?? 0),
      before: r.before as unknown as TrialAccess | null, after: r.after as unknown as TrialAccess,
      createdAt: r.createdAt.toISOString() })),
  mutate: c => runActiveOwnerTransaction(prisma, c.userId, async tx => {
    const intentHash = trialIntentHash(c);
    const replay = await tx.adminTrialAudit.findUnique({ where: { requestId: c.requestId } });
    if (replay) {
      if (replay.intentHash !== intentHash) throw new AdminError('ADMIN_REQUEST_CONFLICT');
      return replay.after as unknown as TrialAccess;
    }
    const member = await tx.user.findUnique({ where: { id: c.userId }, select: { id: true, email: true } });
    if (!member) {
      throw new AdminError('ADMIN_MEMBER_NOT_FOUND', 404);
    }
    if (c.expectedEmail && member.email.toLowerCase() !== c.expectedEmail.toLowerCase()) throw new AdminError('ADMIN_MEMBER_CHANGED');
    const row = await tx.adminTrialAccess.findUnique({ where: { userId: c.userId } });
    const before = row ? map(row) : null;
    const time = now();
    const after = applyTrialCommand(before, c, time);
    const data = { ...after, startsAt: new Date(after.startsAt), expiresAt: new Date(after.expiresAt),
      revokedAt: after.revokedAt ? new Date(after.revokedAt) : null };
    await tx.adminTrialAccess.upsert({ where: { userId: c.userId }, create: data, update: data });
    await tx.adminTrialAudit.create({ data: { requestId: c.requestId, actorId: c.actorId, userId: c.userId,
      action: c.action, plan: after.plan, days: c.days, reason: c.reason, intentHash,
      before: before ? before as unknown as Prisma.InputJsonValue : Prisma.JsonNull,
      after: after as unknown as Prisma.InputJsonValue, createdAt: time } });
    return after;
  })
});
