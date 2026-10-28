import { describe, expect, it } from 'vitest';
import { createMemoryServiceIncidentStore, readServiceIncidentDraft, type ServiceIncidentDraft } from './serviceIncident.js';

const draft: ServiceIncidentDraft = { title: 'TikTok ส่งช้า', message: 'ทีมงานกำลังตรวจสอบ\nโพสต์ที่ตั้งเวลาไว้จะส่งต่ออัตโนมัติ',
  platforms: ['TIKTOK'], stage: 'INVESTIGATING' };
const ids = ['5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e01', '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e02', '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e03',
  '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e04', '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e05', '5b3a3c4e-8f1e-4a55-9d3f-0c1b2a3d4e06'];

describe('service incident drafts', () => {
  it('trims text and orders platforms canonically', () => {
    expect(readServiceIncidentDraft({ ...draft, title: '  TikTok ส่งช้า  ', platforms: ['FACEBOOK_REELS', 'TIKTOK'] }))
      .toEqual({ ...draft, platforms: ['TIKTOK', 'FACEBOOK_REELS'] });
  });
  it('rejects malformed text, stages, and platforms', () => {
    for (const body of [{ ...draft, title: 'ab' }, { ...draft, title: 'a'.repeat(81) }, { ...draft, title: 'สอง\nบรรทัด' },
      { ...draft, message: 'x'.repeat(501) }, { ...draft, message: 'bad\u0000char' }, { ...draft, stage: 'DOWN' },
      { ...draft, platforms: ['SHOPEE_VIDEO'] }, { ...draft, platforms: ['TIKTOK', 'TIKTOK'] }, { ...draft, platforms: 'TIKTOK' },
      { ...draft, title: 7 }]) {
      expect(() => readServiceIncidentDraft(body as Record<string, unknown>)).toThrow('ADMIN_INCIDENT_INVALID');
    }
  });
});

describe('memory service incident store', () => {
  it('creates idempotently and refuses a reused id with other content', async () => {
    const store = createMemoryServiceIncidentStore({ now: () => new Date('2026-10-28T03:00:00Z') });
    const created = await store.create({ id: ids[0], actorId: 'owner', draft });
    expect(created).toMatchObject({ ...draft, version: 1, createdBy: 'owner', resolvedAt: null, startedAt: '2026-10-28T03:00:00.000Z' });
    expect(await store.create({ id: ids[0], actorId: 'owner', draft })).toEqual(created);
    await expect(store.create({ id: ids[0], actorId: 'owner', draft: { ...draft, title: 'อีกเรื่อง' } })).rejects.toThrow('ADMIN_REQUEST_CONFLICT');
    await expect(store.create({ id: ids[1], actorId: 'owner', draft: { ...draft, stage: 'RESOLVED' } })).rejects.toThrow('ADMIN_INCIDENT_INVALID');
    expect(await store.active()).toHaveLength(1);
  });
  it('caps open incidents so the app banner stays readable', async () => {
    const store = createMemoryServiceIncidentStore();
    for (const id of ids.slice(0, 5)) await store.create({ id, actorId: 'owner', draft });
    await expect(store.create({ id: ids[5], actorId: 'owner', draft })).rejects.toThrow('ADMIN_INCIDENT_LIMIT');
  });
  it('updates with optimistic versions, replays a landed update, and closes on resolve', async () => {
    let time = new Date('2026-10-28T03:00:00Z');
    const store = createMemoryServiceIncidentStore({ now: () => time });
    await store.create({ id: ids[0], actorId: 'owner', draft });
    time = new Date('2026-10-28T03:30:00Z');
    const identified = { ...draft, stage: 'IDENTIFIED' as const, message: 'พบสาเหตุแล้ว กำลังแก้ไข' };
    const updated = await store.update({ id: ids[0], actorId: 'owner-2', expectedVersion: 1, draft: identified });
    expect(updated).toMatchObject({ ...identified, version: 2, createdBy: 'owner', updatedBy: 'owner-2', updatedAt: '2026-10-28T03:30:00.000Z' });
    expect(await store.update({ id: ids[0], actorId: 'owner-2', expectedVersion: 1, draft: identified })).toEqual(updated);
    await expect(store.update({ id: ids[0], actorId: 'owner', expectedVersion: 1, draft })).rejects.toThrow('ADMIN_INCIDENT_CHANGED');
    await expect(store.update({ id: ids[1], actorId: 'owner', expectedVersion: 1, draft })).rejects.toThrow('ADMIN_INCIDENT_NOT_FOUND');
    time = new Date('2026-10-28T04:00:00Z');
    const resolved = await store.update({ id: ids[0], actorId: 'owner', expectedVersion: 2, draft: { ...identified, stage: 'RESOLVED' } });
    expect(resolved.resolvedAt).toBe('2026-10-28T04:00:00.000Z');
    expect(await store.active()).toEqual([]);
    await expect(store.update({ id: ids[0], actorId: 'owner', expectedVersion: 3, draft })).rejects.toThrow('ADMIN_INCIDENT_RESOLVED');
  });
  it('lists newest first with a validated cursor', async () => {
    let minute = 0;
    const store = createMemoryServiceIncidentStore({ now: () => new Date(Date.UTC(2026, 9, 28, 0, minute++)) });
    for (const id of ids.slice(0, 3)) await store.create({ id, actorId: 'owner', draft });
    const page = await store.list({});
    expect(page.rows.map(row => row.id)).toEqual([ids[2], ids[1], ids[0]]);
    expect(page.nextCursor).toBeUndefined();
    await expect(store.list({ cursor: 'not-a-cursor' })).rejects.toThrow('ADMIN_FILTER_INVALID');
  });
});
