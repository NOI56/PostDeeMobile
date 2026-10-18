import type { PrismaClient, Prisma, Platform, PostStatus } from '@prisma/client';
import { activeTrial, AdminError, type TrialAccess } from './trialAccess.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import { adminPublishFailure } from './adminPublishFailure.js';

export const adminViews = ['overview', 'members', 'posts', 'trials', 'channels', 'reports', 'audit'] as const;
export type AdminView = typeof adminViews[number];
export type AdminMember = { id: string; email: string; displayName?: string | null; paidPlan: string;
  trial?: TrialAccess | null; [key: string]: unknown };
export type AdminPage = { rows: Record<string, unknown>[]; total?: number; nextCursor?: string; note?: string };
export type AdminDataSource = {
  member: (id: string) => Promise<AdminMember | null>;
  view: (view: AdminView, options: { query: string; cursor?: string; status?: string; platform?: string;
    from?: Date; until?: Date }) => Promise<AdminPage>;
};
const trialJson = (r: { userId: string; plan: string; startsAt: Date; expiresAt: Date; revokedAt: Date | null; version: number } | null): TrialAccess | null =>
  r ? { ...r, plan: r.plan as TrialAccess['plan'], startsAt: r.startsAt.toISOString(), expiresAt: r.expiresAt.toISOString(), revokedAt: r.revokedAt?.toISOString() ?? null } : null;
const memberSelect = { id: true, email: true, displayName: true, createdAt: true, updatedAt: true,
  subscription: { select: { plan: true, status: true, currentPeriodEnd: true } }, adminTrialAccess: true,
  _count: { select: { posts: true, socialConnections: true } } } satisfies Prisma.UserSelect;
const memberJson = (r: Prisma.UserGetPayload<{ select: typeof memberSelect }>, now: Date): AdminMember => ({
  id: r.id, email: r.email, displayName: r.displayName, createdAt: r.createdAt.toISOString(), updatedAt: r.updatedAt.toISOString(),
  paidPlan: r.subscription?.status === 'ACTIVE' && (!r.subscription.currentPeriodEnd || r.subscription.currentPeriodEnd > now) ? r.subscription.plan : 'BASIC',
  paidExpiresAt: r.subscription?.currentPeriodEnd?.toISOString() ?? null,
  trial: trialJson(r.adminTrialAccess), postCount: r._count.posts, channelCount: r._count.socialConnections
});
const readTimeCursor = (cursor?: string): { time: Date; id: string } | undefined => {
  if (!cursor) return;
  try {
    const [time, id] = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown[];
    if (typeof time !== 'string' || typeof id !== 'string' || !id || id.length > 128 || new Date(time).toISOString() !== time) throw new Error();
    return { time: new Date(time), id };
  } catch { throw new AdminError('ADMIN_FILTER_INVALID', 400); }
};
const continuation = <T extends { createdAt: Date }>(rows: T[], key: keyof T) => rows.length > 50
  ? { nextCursor: Buffer.from(JSON.stringify([rows[49].createdAt.toISOString(), rows[49][key]])).toString('base64url') } : {};
export const createPrismaAdminDataSource = (prisma: PrismaClient, config: AdminConsoleConfig,
  now: () => Date = () => new Date()): AdminDataSource => ({
  member: async id => {
    const r = await prisma.user.findUnique({ where: { id }, select: memberSelect });
    if (!r) return null;
    const time = now(); const monthKey = time.toISOString().slice(0, 7);
    const monthStart = new Date(`${monthKey}-01T00:00:00Z`);
    const monthEnd = new Date(Date.UTC(time.getUTCFullYear(), time.getUTCMonth() + 1, 1));
    const [captions, edits, postUnits] = await Promise.all([
      prisma.realClipCaptionUsage.count({ where: { userId: id, monthKey } }),
      prisma.aiEditUsage.aggregate({ where: { userId: id, monthKey }, _sum: { minutes: true } }),
      prisma.post.findMany({ where: { userId: id, createdAt: { gte: monthStart, lt: monthEnd } }, select: { selectedPlatforms: true } })
    ]);
    return { ...memberJson(r, time), monthKey, captionRequests: captions, editMinutes: edits._sum.minutes ?? 0, postUnits: postUnits.reduce((sum, post) => sum + post.selectedPlatforms.length, 0) };
  },
  view: async (view, options) => {
    const time = now(); const take = 51;
    const search = options.query ? { OR: [ { email: { contains: options.query, mode: 'insensitive' as const } },
      { displayName: { contains: options.query, mode: 'insensitive' as const } } ] } : {};
    const userFilter = { ...search };
    const window = { ...(options.from ? { gte: options.from } : {}), ...(options.until ? { lt: options.until } : {}) };
    const page = <T extends { id?: string; requestId?: string; userId?: string }>(rows: T[], map: (r: T) => Record<string, unknown>, key: 'id' | 'requestId' | 'userId' = 'id'): AdminPage => ({
      rows: rows.slice(0, 50).map(map), ...(rows.length > 50 ? { nextCursor: String(rows[49][key]) } : {})
    });
    if (view === 'overview') {
      const [members, paid, trials, posts] = await Promise.all([
        prisma.user.count(), prisma.subscription.count({ where: { status: 'ACTIVE', plan: { not: 'BASIC' }, OR: [{ currentPeriodEnd: null }, { currentPeriodEnd: { gt: time } }] } }),
        prisma.adminTrialAccess.count({ where: { revokedAt: null, startsAt: { lte: time }, expiresAt: { gt: time } } }),
        prisma.post.groupBy({ by: ['status'], _count: { _all: true } })
      ]);
      return { rows: [{ label: 'สมาชิกทั้งหมด', value: members }, { label: 'แพ็กเกจที่ซื้อยังใช้งานได้', value: paid },
        { label: 'สิทธิ์ทดลองที่ใช้งานอยู่', value: trials }, ...posts.map(r => ({ label: `โพสต์ ${r.status}`, value: r._count._all }))] };
    }
    if (view === 'members') {
      const rows = await prisma.user.findMany({ where: { ...userFilter, ...(options.cursor ? { id: { gt: options.cursor } } : {}) }, select: memberSelect, orderBy: { id: 'asc' }, take });
      return { ...page(rows, r => memberJson(r, time)), total: await prisma.user.count({ where: userFilter }) };
    }
    if (view === 'posts') {
      const cursor = readTimeCursor(options.cursor);
      const where: Prisma.PostWhereInput = { user: userFilter, ...(cursor ? { OR: [{ createdAt: { lt: cursor.time } }, { createdAt: cursor.time, id: { lt: cursor.id } }] } : {}),
...(options.status ? { status: options.status as PostStatus } : {}),
...(options.platform ? { selectedPlatforms: { has: options.platform as Platform } } : {}),
        ...(Object.keys(window).length ? { createdAt: window } : {}) };
      const rows = await prisma.post.findMany({ where, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take,
        select: { id: true, caption: true, status: true, createdAt: true, scheduledAt: true,
          user: { select: { email: true } }, platformPublishes: { select: { platform: true, status: true, deliveryOutcome: true, errorMessage: true } } } });
      return { ...page(rows, r => ({ id: r.id, email: r.user.email, caption: r.caption.slice(0, 300), status: r.status,
        createdAt: r.createdAt.toISOString(), scheduledAt: r.scheduledAt?.toISOString() ?? null,
        channels: r.platformPublishes.map(p => `${p.platform}: ${p.status}${p.deliveryOutcome ? ` (${p.deliveryOutcome})` : ''}`).join(' · '),
        failureReason: r.platformPublishes.filter(p => p.status === 'FAILED').map(p => `${p.platform}: ${adminPublishFailure(p.errorMessage)}`).join(' · '),
        help: r.status === 'FAILED' || r.status === 'PARTIAL_PUBLISHED' ? 'ตรวจผลในแอปและบนช่องทางก่อนส่งซ้ำ' : '' })), ...continuation(rows, 'id') };
    }
    if (view === 'channels') {
      const rows = await prisma.socialConnection.findMany({ where: { user: userFilter, ...(options.cursor ? { id: { gt: options.cursor } } : {}) }, orderBy: { id: 'asc' }, take,
        select: { id: true, platform: true, displayName: true, connectedAt: true, user: { select: { email: true } } } });
      return { ...page(rows, r => ({ id: r.id, email: r.user.email, platform: r.platform, displayName: r.displayName,
        connectedAt: r.connectedAt.toISOString(), status: 'มีการเชื่อมต่อที่บันทึกไว้ · ยังไม่ยืนยันสิทธิ์เผยแพร่ล่าสุด' })),
        note: 'ข้อมูลที่บันทึกใน PostDee ไม่ใช่ผลตรวจสิทธิ์แบบสด เจ้าของบัญชีต้องเชื่อม OAuth ด้วยตนเอง' };
    }
    if (view === 'audit') {
      const cursor = readTimeCursor(options.cursor);
      const rows = await prisma.adminTrialAudit.findMany({ where: { user: userFilter, ...(cursor ? { OR: [{ createdAt: { lt: cursor.time } }, { createdAt: cursor.time, requestId: { lt: cursor.id } }] } : {}) }, orderBy: [{ createdAt: 'desc' }, { requestId: 'desc' }], take,
        select: { requestId: true, actorId: true, action: true, plan: true, days: true, reason: true, before: true, after: true, createdAt: true, user: { select: { email: true } } } });
      return { ...page(rows, r => ({ requestId: r.requestId, actorId: r.actorId, email: r.user.email, action: r.action,
        plan: r.plan, days: r.days, reason: r.reason, before: r.before, after: r.after, createdAt: r.createdAt.toISOString() }), 'requestId'), ...continuation(rows, 'requestId') };
    }
    const rows = await prisma.adminTrialAccess.findMany({ where: { user: userFilter, ...(options.cursor ? { userId: { gt: options.cursor } } : {}) }, orderBy: { userId: 'asc' }, take,
      include: { user: { select: memberSelect } } });
    if (view === 'trials') return page(rows, r => ({ ...memberJson(r.user, time), trialStatus: activeTrial(trialJson(r), time) ? 'ACTIVE' : r.revokedAt ? 'REVOKED' : 'EXPIRED' }), 'userId');
    const reports: Record<string, unknown>[] = [];
    // Bounded sequential cohort queries avoid flooding the application's connection pool.
    for (const r of rows.slice(0, 50)) {
      const until = new Date(Math.min(time.getTime(), r.expiresAt.getTime(), r.revokedAt?.getTime() ?? Infinity));
      const createdAt = { gte: r.startsAt, lt: until };
      const [captions, edits, postUnits] = await Promise.all([
        prisma.realClipCaptionUsage.count({ where: { userId: r.userId, createdAt } }),
        prisma.aiEditUsage.aggregate({ where: { userId: r.userId, createdAt }, _sum: { minutes: true } }),
        prisma.platformPublish.count({ where: { post: { userId: r.userId }, createdAt } })
      ]);
      const editMinutes = edits._sum.minutes ?? 0; const rates = config.costRates;
      reports.push({ userId: r.userId, email: r.user.email, plan: r.plan, startsAt: r.startsAt.toISOString(),
        expiresAt: r.expiresAt.toISOString(), revokedAt: r.revokedAt?.toISOString() ?? null,
        captionRequests: captions, editMinutes, postUnits,
        estimatedUsd: rates ? +(captions * rates.captionRequestUsd + editMinutes * rates.editMinuteUsd + postUnits * rates.postUnitUsd).toFixed(6) : null,
        purchasedPlanNow: memberJson(r.user, time).paidPlan });
    }
    return { rows: reports, ...(rows.length > 50 ? { nextCursor: rows[49].userId } : {}),
      note: 'แสดงช่วงทดลองล่าสุดของแต่ละบัญชีเท่านั้น ประวัติช่วงเก่าอยู่ที่ประวัติผู้ดูแล การใช้งานรวมกิจกรรมที่ใช้แพ็กเกจซื้ออยู่ด้วย แพ็กเกจที่ซื้อปัจจุบันไม่ใช่อัตราเปลี่ยนเป็นลูกค้าเสียเงิน ต้นทุนเป็นประมาณการ ไม่ใช่ใบแจ้งหนี้' };
  }
});
