import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaServiceIncidentStore } from './prismaServiceIncidentStore.js';
import { maxActiveServiceIncidents, type ServiceIncidentDraft } from './serviceIncident.js';

// Opt-in only; refuse external hosts, default Postgres ports and existing app databases.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Admin DB tests require the dedicated loopback fixture cluster on port 55439');
  }
}
describe.skipIf(!databaseUrl)('service incidents in PostgreSQL', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } } });
  let time = new Date('2026-10-28T03:00:00Z');
  const store = createPrismaServiceIncidentStore(prisma, () => time);
  const draft: ServiceIncidentDraft = { title: 'TikTok ส่งช้า', message: 'ทีมงานกำลังตรวจสอบ', platforms: ['TIKTOK', 'FACEBOOK_REELS'], stage: 'INVESTIGATING' };
  const ids: string[] = [];
  const id = () => { const next = randomUUID(); ids.push(next); return next; };
  const resolveAll = async () => {
    for (const incident of await store.active()) {
      await store.update({ id: incident.id, actorId: 'fixture-owner', expectedVersion: incident.version, draft: { ...incident, stage: 'RESOLVED' } });
    }
  };
  afterAll(async () => {
    await prisma.serviceIncident.deleteMany({ where: { id: { in: ids } } });
    await prisma.$disconnect();
  });

  it('creates once per id even for concurrent submits', async () => {
    await resolveAll();
    const command = { id: id(), actorId: 'fixture-owner', draft };
    const results = await Promise.all([store.create(command), store.create(command), store.create(command)]);
    expect(results.map(result => result.id)).toEqual([command.id, command.id, command.id]);
    expect(results[0]).toMatchObject({ ...draft, version: 1, resolvedAt: null, startedAt: time.toISOString() });
    expect(await prisma.serviceIncident.count({ where: { id: command.id } })).toBe(1);
    await expect(store.create({ ...command, draft: { ...draft, title: 'อีกเรื่องหนึ่ง' } })).rejects.toThrow('ADMIN_REQUEST_CONFLICT');
  });
  it('holds the open-notice cap under concurrent creates', async () => {
    await resolveAll();
    const results = await Promise.allSettled(Array.from({ length: maxActiveServiceIncidents + 2 },
      () => store.create({ id: id(), actorId: 'fixture-owner', draft })));
    expect((await store.active()).length).toBeLessThanOrEqual(maxActiveServiceIncidents);
    expect(results.filter(result => result.status === 'fulfilled').length).toBeLessThanOrEqual(maxActiveServiceIncidents);
    await resolveAll();
  });
  it('applies one of two racing updates and stamps resolution', async () => {
    await resolveAll();
    const created = await store.create({ id: id(), actorId: 'fixture-owner', draft });
    time = new Date('2026-10-28T04:00:00Z');
    const results = await Promise.allSettled([
      store.update({ id: created.id, actorId: 'owner-a', expectedVersion: 1, draft: { ...draft, stage: 'IDENTIFIED' } }),
      store.update({ id: created.id, actorId: 'owner-b', expectedVersion: 1, draft: { ...draft, stage: 'MONITORING' } })
    ]);
    expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
    const current = (await store.list({})).rows.find(row => row.id === created.id)!;
    expect(current.version).toBe(2);
    const resolved = await store.update({ id: created.id, actorId: 'owner-a', expectedVersion: 2, draft: { ...draft, stage: 'RESOLVED' } });
    expect(resolved).toMatchObject({ version: 3, resolvedAt: time.toISOString(), platforms: ['TIKTOK', 'FACEBOOK_REELS'] });
    await expect(store.update({ id: created.id, actorId: 'owner-a', expectedVersion: 3, draft })).rejects.toThrow('ADMIN_INCIDENT_RESOLVED');
  });
  it('enforces stage and resolution consistency in the database', async () => {
    await expect(prisma.serviceIncident.create({ data: { ...draft, id: id(), stage: 'RESOLVED', version: 1,
      createdBy: 'fixture-owner', updatedBy: 'fixture-owner', startedAt: time, updatedAt: time } })).rejects.toThrow();
    await expect(prisma.serviceIncident.create({ data: { ...draft, id: id(), stage: 'DOWN', version: 1,
      createdBy: 'fixture-owner', updatedBy: 'fixture-owner', startedAt: time, updatedAt: time } })).rejects.toThrow();
  });
});
