import type { PrismaClient, Prisma, Platform, PostStatus } from '@prisma/client';
import { activeTrial, AdminError, type TrialAccess } from './trialAccess.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import { adminPublishFailure } from './adminPublishFailure.js';
import { readAdminUsageReport, type AdminReportScope, type AdminReportSummary, type AdminUsageWindow } from './adminUsageReport.js';

const postStatusLabels: Record<string, string> = { DRAFT: 'ร่าง', QUEUED: 'รอส่ง', PENDING: 'รอส่ง', PUBLISHING: 'กำลังส่ง',
  PUBLISHED: 'ส่งถึงช่องทางแล้ว', PARTIAL_PUBLISHED: 'ส่งถึงบางช่องทาง', FAILED: 'ส่งไม่สำเร็จ' };
const platformLabels: Record<string, string> = { TIKTOK: 'TikTok', YOUTUBE_SHORTS: 'YouTube Shorts',
  INSTAGRAM_REELS: 'Instagram Reels', FACEBOOK_REELS: 'Facebook Reels' };
export const adminChannelResult = (p: { platform: string; status: string; deliveryOutcome?: string | null }): string => {
  let result = postStatusLabels[p.status] ?? 'ยังไม่ยืนยันสถานะ';
  if (p.status === 'PUBLISHED') {
    const outcomes: Record<string, string> = { LIVE: 'เผยแพร่แล้ว', PRIVATE: 'เผยแพร่แบบส่วนตัว', UNLISTED: 'เผยแพร่แบบไม่แสดงในรายการ',
      DRAFT: p.platform === 'TIKTOK' ? 'ส่งเป็นร่างเข้า TikTok Inbox · ยังไม่เผยแพร่' : 'ส่งเป็นร่างแล้ว · ยังไม่เผยแพร่' };
    result = outcomes[p.deliveryOutcome ?? ''] ?? 'ส่งถึงช่องทางแล้ว · ไม่มีข้อมูลรูปแบบการเผยแพร่';
  }
  return `${platformLabels[p.platform] ?? 'ช่องทางอื่น'}: ${result}`;
};

export const adminViews = ['overview', 'members', 'posts', 'trials', 'channels', 'reports', 'audit'] as const;
export type AdminView = typeof adminViews[number];
export type AdminMember = { id: string; email: string; displayName?: string | null; paidPlan: string;
  trial?: TrialAccess | null; [key: string]: unknown };
export type AdminPage = { rows: Record<string, unknown>[]; total?: number; nextCursor?: string; note?: string;
  asOf?: string; window?: AdminUsageWindow; reportScope?: AdminReportScope; summary?: AdminReportSummary };
export type AdminDataSource = {
  member: (id: string) => Promise<AdminMember | null>;
  view: (view: AdminView, options: { query: string; cursor?: string; status?: string; platform?: string;
    from?: Date; until?: Date; reportScope?: AdminReportScope }) => Promise<AdminPage>;
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
const readSnapshot = <T>(prisma: PrismaClient, now: () => Date,
  run: (client: Prisma.TransactionClient, time: Date) => Promise<T>) => {
  const time = now();
  return prisma.$transaction(async tx => {
    await tx.$executeRaw`SET TRANSACTION READ ONLY`;
    await tx.$executeRaw`SET LOCAL statement_timeout = '10000ms'`;
    return run(tx, time);
  }, { isolationLevel: 'RepeatableRead', maxWait: 5000, timeout: 15000 });
};
export const createPrismaAdminDataSource = (prisma: PrismaClient, config: AdminConsoleConfig,
  now: () => Date = () => new Date()): AdminDataSource => ({
  member: id => readSnapshot(prisma, now, async (prisma, time) => {
    const r = await prisma.user.findUnique({ where: { id }, select: memberSelect });
    if (!r) return null;
    const monthKey = time.toISOString().slice(0, 7);
    const monthStart = new Date(`${monthKey}-01T00:00:00Z`);
    const monthEnd = new Date(Date.UTC(time.getUTCFullYear(), time.getUTCMonth() + 1, 1));
    const [captions, edits, postUnits] = await Promise.all([
      prisma.realClipCaptionUsage.count({ where: { userId: id, monthKey } }),
      prisma.aiEditUsage.aggregate({ where: { userId: id, monthKey }, _sum: { minutes: true } }),
      prisma.post.findMany({ where: { userId: id, createdAt: { gte: monthStart, lt: monthEnd } }, select: { selectedPlatforms: true } })
    ]);
    const quotaPostUnits = postUnits.reduce((sum, post) => sum + post.selectedPlatforms.length, 0);
    return { ...memberJson(r, time), monthKey, captionRequests: captions, editMinutes: edits._sum.minutes ?? 0,
      postUnits: quotaPostUnits, quotaPostUnits, asOf: time.toISOString(),
      window: { from: monthStart.toISOString(), until: monthEnd.toISOString(), timezone: 'UTC' } };
  }),
  view: (view, options) => readSnapshot(prisma, now, async (prisma, time) => {
    const take = 51;
    const literalQuery = options.query.replace(/[\\%_]/g, '\\$&');
    const search = options.query ? { OR: [ { email: { contains: literalQuery, mode: 'insensitive' as const } },
      { displayName: { contains: literalQuery, mode: 'insensitive' as const } } ] } : {};
    const userFilter = { ...search };
    const window = { ...(options.from ? { gte: options.from } : {}), ...(options.until ? { lt: options.until } : {}) };
    const page = <T extends { id?: string; requestId?: string; userId?: string }>(rows: T[], map: (r: T) => Record<string, unknown>, key: 'id' | 'requestId' | 'userId' = 'id'): AdminPage => ({
      rows: rows.slice(0, 50).map(map), asOf: time.toISOString(), ...(rows.length > 50 ? { nextCursor: String(rows[49][key]) } : {})
    });
    if (view === 'overview') {
      const [members, paid, trials, posts] = await Promise.all([
        prisma.user.count(), prisma.subscription.count({ where: { status: 'ACTIVE', plan: { not: 'BASIC' }, OR: [{ currentPeriodEnd: null }, { currentPeriodEnd: { gt: time } }] } }),
        prisma.adminTrialAccess.count({ where: { revokedAt: null, startsAt: { lte: time }, expiresAt: { gt: time } } }),
        prisma.post.groupBy({ by: ['status'], _count: { _all: true } })
      ]);
      return { rows: [{ label: 'สมาชิกทั้งหมด', value: members }, { label: 'แพ็กเกจที่ซื้อยังใช้งานได้', value: paid },
        { label: 'สิทธิ์ทดลองที่ใช้งานอยู่', value: trials }, ...posts.map(r => ({ label: `โพสต์ · ${postStatusLabels[r.status]}`, value: r._count._all }))],
        asOf: time.toISOString(), note: 'สมาชิกทั้งหมดนับบัญชีที่ลงทะเบียน ไม่ใช่จำนวนผู้ใช้ออนไลน์ · ส่งถึงช่องทางแล้วรวมการส่งเป็นร่างด้วย ดูรูปแบบการเผยแพร่ของแต่ละช่องทางในหน้าโพสต์' };
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
        channels: r.platformPublishes.map(adminChannelResult).join(' · '),
        failureReason: r.platformPublishes.filter(p => p.status === 'FAILED').map(p => `${platformLabels[p.platform] ?? 'ช่องทางอื่น'}: ${adminPublishFailure(p.errorMessage)}`).join(' · '),
        help: r.status === 'FAILED' || r.status === 'PARTIAL_PUBLISHED' ? 'ตรวจผลในแอปและบนช่องทางก่อนส่งซ้ำ' : '' })), ...continuation(rows, 'id'),
        note: 'ส่งถึงช่องทางแล้วอาจเป็นร่างที่ยังไม่เผยแพร่ ผลแต่ละช่องทางแสดงตามข้อมูลที่บันทึกไว้ การมองเห็นล่าสุดให้ตรวจบนช่องทางนั้น' };
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
    if (view === 'reports') return readAdminUsageReport(prisma, options, time, config.costRates);
    const rows = await prisma.adminTrialAccess.findMany({ where: { user: userFilter, ...(options.cursor ? { userId: { gt: options.cursor } } : {}) }, orderBy: { userId: 'asc' }, take,
      include: { user: { select: memberSelect } } });
    return page(rows, r => ({ ...memberJson(r.user, time), trialStatus: activeTrial(trialJson(r), time) ? 'ACTIVE' : r.revokedAt ? 'REVOKED' : r.startsAt > time ? 'NOT_STARTED' : 'EXPIRED' }), 'userId');
  })
});
