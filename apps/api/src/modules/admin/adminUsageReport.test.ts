import { describe, expect, it, vi } from 'vitest';
import type { Prisma } from '@prisma/client';
import { readAdminUsageReport } from './adminUsageReport.js';

const asOf = new Date('2026-10-18T12:00:00Z');
const metrics = { captionRequests: 2, editMinutes: 3, quotaPostUnits: 4, postUnits: 6,
  livePostUnits: 1, draftPostUnits: 1, otherDeliveredPostUnits: 2, failedPostUnits: 1, pendingPostUnits: 1 };
const raw = (rows: Record<string, unknown>[] = []) => ({ rows, summary: { memberCount: 73, ...metrics } });
const client = (result: ReturnType<typeof raw>) => ({ $queryRaw: vi.fn().mockResolvedValue([result]) });

describe('batched administrator usage reports', () => {
  it('preserves latest-trial scope for existing clients that omit the new scope field', async () => {
    const tx = client(raw());
    const result = await readAdminUsageReport(tx as unknown as Prisma.TransactionClient, { query: '' }, asOf);
    expect(result.reportScope).toBe('LATEST_TRIAL');
  });
  it('uses one parameterized batch and returns whole-cohort totals even beyond the last cursor', async () => {
    const tx = client(raw());
    const query = "seller%_' OR true --";
    const result = await readAdminUsageReport(tx as unknown as Prisma.TransactionClient,
      { query, cursor: 'last-member', reportScope: 'ALL_ACCOUNTS' }, asOf);
    expect(result).toMatchObject({ rows: [], total: 73, reportScope: 'ALL_ACCOUNTS',
      asOf: asOf.toISOString(), window: { from: null, until: asOf.toISOString(), timezone: 'UTC' },
      summary: { memberCount: 73, ...metrics, estimatedUsd: null } });
    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    const sql = tx.$queryRaw.mock.calls[0][0] as Prisma.Sql;
    expect(sql.text).not.toContain(query);
    expect(sql.values).toContain(query);
    expect(sql.values).toContain('last-member');
    expect(sql.text).toContain('strpos');
    expect(sql.text).toContain('cardinality');
    expect(sql.text).not.toMatch(/ILIKE|LIKE|OFFSET|queryRawUnsafe/i);
    expect(sql.text).toContain("'PUBLISHED'");
    expect(sql.text).toContain("'PENDING', 'PUBLISHING'");
  });

  it('keeps a 50-row page separate from the complete summary and retains nullable trial metadata for ordinary accounts', async () => {
    const tx = client(raw(Array.from({ length: 51 }, (_, i) => ({ userId: `member-${String(i).padStart(2, '0')}`,
      email: `member-${i}@example.com`, plan: null, startsAt: null, expiresAt: null, revokedAt: null,
      usageFrom: null, usageUntil: asOf.toISOString(), purchasedPlanNow: 'BASIC', ...metrics }))));
    const result = await readAdminUsageReport(tx as unknown as Prisma.TransactionClient,
      { query: '', reportScope: 'ALL_ACCOUNTS' }, asOf, { captionRequestUsd: 0.01, editMinuteUsd: 0.02, postUnitUsd: 0.03 });
    expect(result.rows).toHaveLength(50);
    expect(result.nextCursor).toBe('member-49');
    expect(result.total).toBe(73);
    expect(result.rows[0]).toMatchObject({ plan: null, startsAt: null, usageFrom: null, ...metrics, estimatedUsd: 0.26 });
    expect(result.summary).toMatchObject({ memberCount: 73, ...metrics, estimatedUsd: 0.26 });
  });

  it('caps a selected end at asOf and intersects each latest trial window inside SQL', async () => {
    const tx = client(raw());
    const from = new Date('2026-10-01T00:00:00Z');
    const result = await readAdminUsageReport(tx as unknown as Prisma.TransactionClient,
      { query: '', reportScope: 'LATEST_TRIAL', from, until: new Date('2026-11-01T00:00:00Z') }, asOf);
    expect(result.window).toEqual({ from: from.toISOString(), until: asOf.toISOString(), timezone: 'UTC' });
    expect(result.reportScope).toBe('LATEST_TRIAL');
    const sql = tx.$queryRaw.mock.calls[0][0] as Prisma.Sql;
    expect(sql.text).toContain('GREATEST');
    expect(sql.text).toContain('LEAST');
    expect(sql.text).toContain('"revokedAt"');
    expect(sql.text).toContain('"expiresAt"');
    expect(sql.values).toContain('LATEST_TRIAL');
    expect(sql.values).toContainEqual(from);
    expect(sql.values).toContainEqual(asOf);
  });

  it('interprets PostgreSQL timestamp-without-zone JSON as UTC rather than the API host timezone', async () => {
    const previousTimezone = process.env.TZ;
    process.env.TZ = 'Asia/Bangkok';
    try {
      const tx = client(raw([{ userId: 'member', email: 'fixture@example.com', plan: 'PRO',
        startsAt: '2026-10-01T00:00:00', expiresAt: '2026-11-01T00:00:00', revokedAt: null,
        usageFrom: '2026-10-01T00:00:00', usageUntil: '2026-10-18T12:00:00', purchasedPlanNow: 'BASIC', ...metrics }]));
      const result = await readAdminUsageReport(tx as unknown as Prisma.TransactionClient, { query: '' }, asOf);
      expect(result.rows[0]).toMatchObject({ startsAt: '2026-10-01T00:00:00.000Z',
        usageFrom: '2026-10-01T00:00:00.000Z', usageUntil: asOf.toISOString() });
    } finally {
      if (previousTimezone === undefined) delete process.env.TZ;
      else process.env.TZ = previousTimezone;
    }
  });
});
