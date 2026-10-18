import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { createPrismaAdminDataSource } from './adminDataSource.js';
import type { AdminConsoleConfig } from './adminConfig.js';

const config: AdminConsoleConfig = { origin: 'http://127.0.0.1:4174', environment: 'LOCAL', ownerUids: ['owner'], viewerUids: [],
  firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' } };
const time = new Date('2026-10-18T00:00:00Z');
const post = (platformPublishes: Record<string, unknown>[], status = 'PUBLISHED') => ({
  id: 'post', user: { email: 'fixture@example.com' }, caption: 'ตัวอย่าง', status, createdAt: time, scheduledAt: null, platformPublishes
});
const snapshotClient = (delegates: Record<string, unknown>) => {
  const tx = { ...delegates, $executeRaw: vi.fn().mockResolvedValue(0) };
  return { ...delegates, $transaction: vi.fn(async (run: (client: unknown) => Promise<unknown>) => run(tx)), tx };
};
const source = (rows: ReturnType<typeof post>[]) => createPrismaAdminDataSource(snapshotClient({
  post: { findMany: vi.fn().mockResolvedValue(rows) }
}) as unknown as PrismaClient, config, () => time);

describe('administrator post presentation', () => {
  it('uses Thai overview labels without calling successful delivery public publication', async () => {
    const data = createPrismaAdminDataSource(snapshotClient({
      user: { count: async () => 3 }, subscription: { count: async () => 0 }, adminTrialAccess: { count: async () => 0 },
      post: { groupBy: async () => ['DRAFT', 'QUEUED', 'PUBLISHING', 'PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED']
        .map(status => ({ status, _count: { _all: 1 } })) }
    }) as unknown as PrismaClient, config, () => time);
    const result = await data.view('overview', { query: '' });
    expect(result.rows.slice(3).map(row => row.label)).toEqual([
      'โพสต์ · ร่าง', 'โพสต์ · รอส่ง', 'โพสต์ · กำลังส่ง', 'โพสต์ · ส่งถึงช่องทางแล้ว', 'โพสต์ · ส่งถึงบางช่องทาง', 'โพสต์ · ส่งไม่สำเร็จ'
    ]);
  });

  it('distinguishes TikTok Inbox drafts, live, private and unlisted delivery while preserving status filters', async () => {
    const data = source([post([
      { platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'DRAFT' },
      { platform: 'YOUTUBE_SHORTS', status: 'PUBLISHED', deliveryOutcome: 'LIVE' },
      { platform: 'INSTAGRAM_REELS', status: 'PUBLISHED', deliveryOutcome: 'PRIVATE' },
      { platform: 'FACEBOOK_REELS', status: 'PUBLISHED', deliveryOutcome: 'UNLISTED' }
    ])]);
    const { rows } = await data.view('posts', { query: '' });
    expect(rows[0]).toMatchObject({ status: 'PUBLISHED', channels: [
      'TikTok: ส่งเป็นร่างเข้า TikTok Inbox · ยังไม่เผยแพร่', 'YouTube Shorts: เผยแพร่แล้ว',
      'Instagram Reels: เผยแพร่แบบส่วนตัว', 'Facebook Page Video: เผยแพร่แบบไม่แสดงในรายการ'
    ].join(' · ') });
  });

  it('does not infer publication from missing delivery data or a stale outcome on a failed channel', async () => {
    const data = source([post([
      { platform: 'TIKTOK', status: 'FAILED', deliveryOutcome: 'LIVE', errorMessage: 'token=secret' },
      { platform: 'YOUTUBE_SHORTS', status: 'PUBLISHED', deliveryOutcome: null },
      { platform: 'INSTAGRAM_REELS', status: 'PENDING', deliveryOutcome: null },
      { platform: 'FACEBOOK_REELS', status: 'PUBLISHING', deliveryOutcome: null },
      { platform: 'SHOPEE_VIDEO', status: 'FAILED', deliveryOutcome: null }
    ], 'PARTIAL_PUBLISHED')]);
    const { rows } = await data.view('posts', { query: '' });
    expect(rows[0].channels).toBe([
      'TikTok: ส่งไม่สำเร็จ', 'YouTube Shorts: ส่งถึงช่องทางแล้ว · ไม่มีข้อมูลรูปแบบการเผยแพร่',
      'Instagram Reels: รอส่ง', 'Facebook Page Video: กำลังส่ง', 'ช่องทางอื่น: ส่งไม่สำเร็จ'
    ].join(' · '));
    expect(rows[0].failureReason).toMatch(/^TikTok: /);
    expect(rows[0].failureReason).toContain('ช่องทางอื่น: ');
    expect(rows[0].failureReason).not.toContain('secret');
    expect(rows[0].help).toContain('ก่อนส่งซ้ำ');
  });
});

describe('administrator usage snapshots', () => {
  it('reads member identity and quota from one bounded read-only repeatable snapshot with one clock capture', async () => {
    const clock = vi.fn(() => time);
    const delegates = {
      user: { findUnique: vi.fn().mockResolvedValue({ id: 'member', email: 'fixture@example.com', displayName: null,
        createdAt: time, updatedAt: time, subscription: { plan: 'PRO', status: 'ACTIVE', currentPeriodEnd: time },
        adminTrialAccess: null, _count: { posts: 2, socialConnections: 1 } }) },
      realClipCaptionUsage: { count: vi.fn().mockResolvedValue(3) },
      aiEditUsage: { aggregate: vi.fn().mockResolvedValue({ _sum: { minutes: 4 } }) },
      post: { findMany: vi.fn().mockResolvedValue([{ selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'] }, { selectedPlatforms: ['TIKTOK'] }]) }
    };
    const client = snapshotClient(delegates);
    const data = createPrismaAdminDataSource(client as unknown as PrismaClient, config, clock);
    const member = await data.member('member');
    expect(member).toMatchObject({ paidPlan: 'BASIC', postUnits: 3, quotaPostUnits: 3, captionRequests: 3, editMinutes: 4,
      monthKey: '2026-10', asOf: time.toISOString(), window: { from: '2026-10-01T00:00:00.000Z', until: '2026-11-01T00:00:00.000Z', timezone: 'UTC' } });
    expect(clock).toHaveBeenCalledTimes(1);
    expect(client.$transaction).toHaveBeenCalledWith(expect.any(Function), { isolationLevel: 'RepeatableRead', maxWait: 5000, timeout: 15000 });
    expect(client.tx.$executeRaw.mock.calls.map(call => String(call[0]))).toEqual(expect.arrayContaining([
      expect.stringContaining('READ ONLY'), expect.stringContaining('statement_timeout')
    ]));
    expect(delegates.post.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: 'member', createdAt: { gte: new Date('2026-10-01T00:00:00Z'), lt: new Date('2026-11-01T00:00:00Z') } } }));
    expect(delegates.realClipCaptionUsage.count).toHaveBeenCalledWith({ where: { userId: 'member', monthKey: '2026-10' } });
    expect(delegates.aiEditUsage.aggregate).toHaveBeenCalledWith({ where: { userId: 'member', monthKey: '2026-10' }, _sum: { minutes: true } });
  });

  it('uses the same transaction for overview counts and captures the expiry boundary once', async () => {
    const clock = vi.fn(() => time);
    const client = snapshotClient({ user: { count: vi.fn().mockResolvedValue(2) },
      subscription: { count: vi.fn().mockResolvedValue(1) }, adminTrialAccess: { count: vi.fn().mockResolvedValue(1) },
      post: { groupBy: vi.fn().mockResolvedValue([]) } });
    const data = createPrismaAdminDataSource(client as unknown as PrismaClient, config, clock);
    const result = await data.view('overview', { query: '' });
    expect(result.asOf).toBe(time.toISOString());
    expect(result.rows.map(row => row.value)).toEqual([2, 1, 1]);
    expect(client.$transaction).toHaveBeenCalledTimes(1);
    expect(clock).toHaveBeenCalledTimes(1);
  });

  it('searches members using literal percent, underscore and backslash characters just like reports', async () => {
    const findMany = vi.fn().mockResolvedValue([]);
    const count = vi.fn().mockResolvedValue(0);
    const client = snapshotClient({ user: { findMany, count } });
    const data = createPrismaAdminDataSource(client as unknown as PrismaClient, config, () => time);
    await data.view('members', { query: 'seller%_\\store' });
    const expected = { OR: [
      { email: { contains: 'seller\\%\\_\\\\store', mode: 'insensitive' } },
      { displayName: { contains: 'seller\\%\\_\\\\store', mode: 'insensitive' } }
    ] };
    expect(findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expected }));
    expect(count).toHaveBeenCalledWith({ where: expected });
  });
});
