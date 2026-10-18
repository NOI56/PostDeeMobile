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
const source = (rows: ReturnType<typeof post>[]) => createPrismaAdminDataSource({
  post: { findMany: vi.fn().mockResolvedValue(rows) }
} as unknown as PrismaClient, config, () => time);

describe('administrator post presentation', () => {
  it('uses Thai overview labels without calling successful delivery public publication', async () => {
    const data = createPrismaAdminDataSource({
      user: { count: async () => 3 }, subscription: { count: async () => 0 }, adminTrialAccess: { count: async () => 0 },
      post: { groupBy: async () => ['DRAFT', 'QUEUED', 'PUBLISHING', 'PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED']
        .map(status => ({ status, _count: { _all: 1 } })) }
    } as unknown as PrismaClient, config, () => time);
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
