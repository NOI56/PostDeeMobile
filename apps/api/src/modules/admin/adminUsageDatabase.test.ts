import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { PrismaClient, type Prisma } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';
import { createPrismaAdminDataSource, type AdminDataSource, type AdminPage } from './adminDataSource.js';
import type { AdminConsoleConfig } from './adminConfig.js';

// This suite owns synthetic UUID fixtures only. Never accept an app/staging database.
const databaseUrl = process.env.ADMIN_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' ||
      url.port !== '55439' || url.pathname !== '/postdee_admin_fixture') {
    throw new Error('Admin usage tests require the dedicated loopback fixture database on port 55439');
  }
}

type Totals = {
  memberCount: number; captionRequests: number; editMinutes: number;
  quotaPostUnits: number; postUnits: number; livePostUnits: number;
  draftPostUnits: number; otherDeliveredPostUnits: number;
  failedPostUnits: number; pendingPostUnits: number; estimatedUsd: number | null;
};
type UsagePage = AdminPage & {
  total: number; asOf: string;
  window: { from: string | null; until: string; timezone: 'UTC' };
  summary: Totals;
};
type ReportOptions = {
  query: string; cursor?: string; from?: Date; until?: Date;
  reportScope?: 'ALL_ACCOUNTS' | 'LATEST_TRIAL';
};

describe.skipIf(!databaseUrl).sequential('admin usage projections on isolated PostgreSQL', () => {
  const prisma = new PrismaClient({
    datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture' } },
    log: [{ emit: 'event', level: 'query' }]
  });
  const runPrefix = `admin-usage-${randomUUID()}`;
  const ownedIds: string[] = [];
  const now = () => new Date('2026-11-15T12:00:00.000Z');
  const eventTime = new Date('2026-10-18T12:00:00.000Z');
  const config: AdminConsoleConfig = {
    origin: 'http://127.0.0.1:4174', environment: 'LOCAL', ownerUids: ['fixture-owner'], viewerUids: [],
    firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' }
  };
  const data = () => createPrismaAdminDataSource(prisma, config, now);
  const report = async (options: ReportOptions, source = data()) =>
    await source.view('reports', { reportScope: 'ALL_ACCOUNTS', ...options }) as UsagePage;
  const cohort = (label: string) => `${runPrefix}-${label}`;
  const users = async (label: string, count: number) => {
    const query = cohort(label);
    const rows = Array.from({ length: count }, (_, index) => {
      const id = `${query}-${String(index).padStart(4, '0')}`;
      return { id, firebaseUid: id, email: `${id}@example.test`, displayName: query, createdAt: eventTime };
    });
    ownedIds.push(...rows.map(row => row.id));
    await prisma.user.createMany({ data: rows });
    return { query, ids: rows.map(row => row.id) };
  };
  const usageAt = async (userId: string, times: Date[], minutes = 2) => {
    await prisma.realClipCaptionUsage.createMany({ data: times.map(createdAt => ({
      userId, createdAt, monthKey: createdAt.toISOString().slice(0, 7)
    })) });
    await prisma.aiEditUsage.createMany({ data: times.map(createdAt => ({
      userId, createdAt, monthKey: createdAt.toISOString().slice(0, 7), minutes
    })) });
    for (const createdAt of times) {
      const post = await prisma.post.create({ data: {
        userId, caption: 'Synthetic usage fixture', videoS3Key: 'fixture/not-uploaded.mp4',
        selectedPlatforms: ['TIKTOK'], status: 'PUBLISHED', createdAt
      } });
      await prisma.platformPublish.create({ data: {
        postId: post.id, platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'LIVE', createdAt
      } });
    }
  };
  const emptyTotals = (memberCount: number): Totals => ({
    memberCount, captionRequests: 0, editMinutes: 0, quotaPostUnits: 0, postUnits: 0,
    livePostUnits: 0, draftPostUnits: 0, otherDeliveredPostUnits: 0,
    failedPostUnits: 0, pendingPostUnits: 0, estimatedUsd: null
  });
  afterAll(async () => {
    try {
      if (ownedIds.length) await prisma.user.deleteMany({ where: { id: { in: ownedIds } } });
    } finally { await prisma.$disconnect(); }
  });

  it('reports every matching account, including free/paid users without a trial and zero usage', async () => {
    const group = await users('all-plans', 4);
    await prisma.subscription.createMany({ data: [
      { userId: group.ids[1], plan: 'STARTER', status: 'ACTIVE' },
      { userId: group.ids[2], plan: 'PRO', status: 'ACTIVE' }
    ] });
    await prisma.adminTrialAccess.create({ data: {
      userId: group.ids[3], plan: 'PRO', version: 1,
      startsAt: new Date('2026-10-01T00:00:00.000Z'), expiresAt: new Date('2026-12-01T00:00:00.000Z')
    } });
    const page = await report({ query: group.query });
    expect(page.total).toBe(4);
    expect(page.rows.map(row => row.userId).sort()).toEqual([...group.ids].sort());
    expect(page.summary).toEqual(emptyTotals(4));
    expect(page.asOf).toBe(now().toISOString());
    expect(page.window).toEqual({ from: null, until: now().toISOString(), timezone: 'UTC' });
    expect(page.rows.every(row => row.captionRequests === 0 && row.postUnits === 0 && row.estimatedUsd === null)).toBe(true);
    expect(page.rows.find(row => row.userId === group.ids[0])?.purchasedPlanNow).toBe('BASIC');
    expect(page.rows.find(row => row.userId === group.ids[1])?.purchasedPlanNow).toBe('STARTER');
    expect(page.rows.find(row => row.userId === group.ids[2])?.purchasedPlanNow).toBe('PRO');
    expect((await report({ query: group.query, reportScope: 'LATEST_TRIAL' })).total).toBe(1);
    const legacy = await data().view('reports', { query: group.query });
    expect(legacy.reportScope).toBe('LATEST_TRIAL');
    expect(legacy.total).toBe(1);
  });

  it('keeps the total and summary on the whole cohort across stable keyset pages over 50 members', async () => {
    const group = await users('pagination', 125);
    await prisma.realClipCaptionUsage.createMany({ data: group.ids.map(userId => ({ userId, monthKey: '2026-10', createdAt: eventTime })) });
    const found: string[] = [];
    let cursor: string | undefined;
    let pages = 0;
    do {
      expect(++pages).toBeLessThanOrEqual(4);
      const page = await report({ query: group.query, cursor });
      expect(page.total).toBe(125);
      expect(page.summary).toEqual({ ...emptyTotals(125), captionRequests: 125 });
      expect(page.rows.length).toBeLessThanOrEqual(50);
      found.push(...page.rows.map(row => String(row.userId)));
      cursor = page.nextCursor;
    } while (cursor);
    expect(found).toHaveLength(125);
    expect(new Set(found).size).toBe(125);
    expect(found.sort()).toEqual([...group.ids].sort());
    const beyond = await report({ query: group.query, cursor: `${group.query}-9999` });
    expect(beyond.rows).toEqual([]);
    expect(beyond.total).toBe(125);
    expect(beyond.summary.captionRequests).toBe(125);
  });

  it('treats percent and underscore in account searches literally in both members and reports', async () => {
    const group = await users('literal-search', 3);
    const query = `${group.query} 50%_off`;
    await prisma.user.update({ where: { id: group.ids[0] }, data: { displayName: query } });
    await prisma.user.update({ where: { id: group.ids[1] }, data: { displayName: `${group.query} 50XXoff` } });
    await prisma.user.update({ where: { id: group.ids[2] }, data: { displayName: `${group.query} 50%Xoff` } });
    const members = await data().view('members', { query });
    expect(members.total).toBe(1);
    expect(members.rows.map(row => row.id)).toEqual([group.ids[0]]);
    const reports = await report({ query });
    expect(reports.total).toBe(1);
    expect(reports.rows.map(row => row.userId)).toEqual([group.ids[0]]);
  });

  it('uses inclusive UTC start and exclusive UTC end for quota, caption, edit and result timestamps', async () => {
    const group = await users('utc-window', 1);
    await usageAt(group.ids[0], [
      new Date('2026-09-30T23:59:59.999Z'), new Date('2026-10-01T00:00:00.000Z'),
      new Date('2026-10-31T23:59:59.999Z'), new Date('2026-11-01T00:00:00.000Z')
    ]);
    const from = new Date('2026-10-01T00:00:00.000Z');
    const until = new Date('2026-11-01T00:00:00.000Z');
    const page = await report({ query: group.query, from, until });
    expect(page.window).toEqual({ from: from.toISOString(), until: until.toISOString(), timezone: 'UTC' });
    expect(page.summary).toEqual({ ...emptyTotals(1), captionRequests: 2, editMinutes: 4,
      quotaPostUnits: 2, postUnits: 2, livePostUnits: 2 });
    expect(page.rows[0]).toMatchObject({ usageFrom: from.toISOString(), usageUntil: until.toISOString() });
  });

  it('preserves the application monthly-quota definition while reports use their observation window', async () => {
    const group = await users('monthly-quota', 1);
    await prisma.realClipCaptionUsage.createMany({ data: [
      { userId: group.ids[0], monthKey: '2026-11', createdAt: new Date('2026-11-30T00:00:00.000Z') },
      { userId: group.ids[0], monthKey: '2026-11', createdAt: new Date('2026-11-30T01:00:00.000Z') },
      { userId: group.ids[0], monthKey: '2026-10', createdAt: new Date('2026-11-01T00:00:00.000Z') }
    ] });
    await prisma.aiEditUsage.createMany({ data: [
      { userId: group.ids[0], monthKey: '2026-11', minutes: 3, createdAt: new Date('2026-11-30T00:00:00.000Z') },
      { userId: group.ids[0], monthKey: '2026-10', minutes: 9, createdAt: new Date('2026-11-01T00:00:00.000Z') }
    ] });
    await prisma.post.createMany({ data: [
      { userId: group.ids[0], caption: 'Synthetic quota fixture', videoS3Key: 'fixture/not-uploaded.mp4', selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'], createdAt: new Date('2026-11-30T00:00:00.000Z') },
      { userId: group.ids[0], caption: 'Synthetic quota fixture', videoS3Key: 'fixture/not-uploaded.mp4', selectedPlatforms: ['TIKTOK'], createdAt: new Date('2026-11-01T00:00:00.000Z') },
      { userId: group.ids[0], caption: 'Synthetic quota fixture', videoS3Key: 'fixture/not-uploaded.mp4', selectedPlatforms: ['TIKTOK'], createdAt: new Date('2026-10-31T23:59:59.999Z') }
    ] });
    const member = await data().member(group.ids[0]);
    expect(member).toMatchObject({ monthKey: '2026-11', captionRequests: 2, editMinutes: 3,
      postUnits: 3, quotaPostUnits: 3, asOf: now().toISOString(),
      window: { from: '2026-11-01T00:00:00.000Z', until: '2026-12-01T00:00:00.000Z', timezone: 'UTC' } });
    const page = await report({ query: group.query });
    expect(page.summary).toEqual({ ...emptyTotals(1), captionRequests: 1, editMinutes: 9, quotaPostUnits: 2 });
  });

  it('intersects each latest trial with requested dates, expiry/revocation/as-of and preserves zero-use future trials', async () => {
    const group = await users('trial-window', 4);
    const trials = [
      { startsAt: '2026-10-10T00:00:00.000Z', expiresAt: '2026-10-25T00:00:00.000Z', revokedAt: '2026-10-15T00:00:00.000Z' },
      { startsAt: '2026-10-05T00:00:00.000Z', expiresAt: '2026-10-12T00:00:00.000Z', revokedAt: null },
      { startsAt: '2026-12-01T00:00:00.000Z', expiresAt: '2026-12-08T00:00:00.000Z', revokedAt: null },
      { startsAt: '2026-10-05T00:00:00.000Z', expiresAt: '2026-12-01T00:00:00.000Z', revokedAt: null }
    ];
    await prisma.adminTrialAccess.createMany({ data: trials.map((trial, index) => ({
      userId: group.ids[index], plan: 'PRO', version: 1, startsAt: new Date(trial.startsAt),
      expiresAt: new Date(trial.expiresAt), revokedAt: trial.revokedAt ? new Date(trial.revokedAt) : null
    })) });
    const trialPage = await data().view('trials', { query: group.query });
    expect(trialPage.rows.find(row => row.id === group.ids[2])?.trialStatus).toBe('NOT_STARTED');
    await usageAt(group.ids[0], ['2026-10-09T23:59:59.999Z', '2026-10-10T00:00:00.000Z',
      '2026-10-14T23:59:59.999Z', '2026-10-15T00:00:00.000Z'].map(value => new Date(value)));
    await usageAt(group.ids[1], ['2026-10-07T23:59:59.999Z', '2026-10-08T00:00:00.000Z',
      '2026-10-11T23:59:59.999Z', '2026-10-12T00:00:00.000Z'].map(value => new Date(value)));
    await usageAt(group.ids[2], [new Date('2026-10-12T00:00:00.000Z')]);
    await usageAt(group.ids[3], [new Date(now().getTime() - 1), now(), new Date(now().getTime() + 1)]);
    const page = await report({ query: group.query, reportScope: 'LATEST_TRIAL',
      from: new Date('2026-10-08T00:00:00.000Z'), until: new Date('2026-10-20T00:00:00.000Z') });
    expect(page.total).toBe(4);
    expect(page.summary).toEqual({ ...emptyTotals(4), captionRequests: 4, editMinutes: 8,
      quotaPostUnits: 4, postUnits: 4, livePostUnits: 4 });
    expect(page.rows.find(row => row.userId === group.ids[0])).toMatchObject({ captionRequests: 2,
      usageFrom: '2026-10-10T00:00:00.000Z', usageUntil: '2026-10-15T00:00:00.000Z' });
    expect(page.rows.find(row => row.userId === group.ids[1])).toMatchObject({ captionRequests: 2,
      usageFrom: '2026-10-08T00:00:00.000Z', usageUntil: '2026-10-12T00:00:00.000Z' });
    expect(page.rows.find(row => row.userId === group.ids[2])).toMatchObject({ captionRequests: 0, postUnits: 0, estimatedUsd: null });
    expect(page.rows.find(row => row.userId === group.ids[3])).toMatchObject({ captionRequests: 0, editMinutes: 0 });
    const cappedAtNow = await report({ query: group.query, reportScope: 'LATEST_TRIAL' });
    expect(cappedAtNow.rows.find(row => row.userId === group.ids[3])).toMatchObject({
      usageUntil: now().toISOString(), captionRequests: 1, editMinutes: 2, quotaPostUnits: 1, postUnits: 1
    });
  });

  it('separates accepted quota from saved results and never calls draft/private/failed/pending outcomes live', async () => {
    const group = await users('delivery', 1);
    const results: Array<{ status: 'PUBLISHED' | 'FAILED' | 'PENDING' | 'PUBLISHING'; deliveryOutcome: 'LIVE' | 'DRAFT' | 'PRIVATE' | 'UNLISTED' | null }> = [
      { status: 'PUBLISHED', deliveryOutcome: 'LIVE' }, { status: 'PUBLISHED', deliveryOutcome: 'DRAFT' },
      { status: 'PUBLISHED', deliveryOutcome: 'PRIVATE' }, { status: 'PUBLISHED', deliveryOutcome: 'UNLISTED' },
      { status: 'PUBLISHED', deliveryOutcome: null }, { status: 'FAILED', deliveryOutcome: 'LIVE' },
      { status: 'PENDING', deliveryOutcome: 'DRAFT' }, { status: 'PUBLISHING', deliveryOutcome: 'LIVE' }
    ];
    for (const result of results) {
      const post = await prisma.post.create({ data: { userId: group.ids[0], caption: 'Outcome fixture',
        videoS3Key: 'fixture/not-uploaded.mp4', selectedPlatforms: ['TIKTOK'], createdAt: eventTime } });
      await prisma.platformPublish.create({ data: { postId: post.id, platform: 'TIKTOK', ...result, createdAt: eventTime } });
    }
    await prisma.post.create({ data: { userId: group.ids[0], caption: 'Accepted with no saved result yet',
      videoS3Key: 'fixture/not-uploaded.mp4', selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'], status: 'QUEUED', createdAt: eventTime } });
    const page = await report({ query: group.query });
    expect(page.summary).toEqual({ ...emptyTotals(1), quotaPostUnits: 10, postUnits: 8,
      livePostUnits: 1, draftPostUnits: 1, otherDeliveredPostUnits: 3, failedPostUnits: 1, pendingPostUnits: 2 });
    expect(page.rows[0]).toMatchObject({ quotaPostUnits: 10, postUnits: 8, livePostUnits: 1,
      draftPostUnits: 1, otherDeliveredPostUnits: 3, failedPostUnits: 1, pendingPostUnits: 2, estimatedUsd: null });
  });

  const pausedSnapshot = () => {
    let reached!: () => void; let release!: () => void; let paused = false;
    const firstRead = new Promise<void>(resolve => { reached = resolve; });
    const resume = new Promise<void>(resolve => { release = resolve; });
    const pauseOnce = async <T>(result: T): Promise<T> => {
      if (!paused) { paused = true; reached(); await resume; }
      return result;
    };
    const wrapped = new Proxy(prisma, { get(target, property) {
      if (property === '$transaction') return (operation: (tx: Prisma.TransactionClient) => Promise<unknown>, options?: {
        maxWait?: number; timeout?: number; isolationLevel?: Prisma.TransactionIsolationLevel
      }) => target.$transaction(tx => operation(new Proxy(tx, { get(transaction, key) {
        const value = Reflect.get(transaction, key, transaction);
        if (key === '$queryRaw' || key === '$queryRawUnsafe') return async (...args: unknown[]) =>
          pauseOnce(await value.apply(transaction, args));
        if (typeof key === 'string' && !key.startsWith('$') && value && typeof value === 'object') {
          return new Proxy(value, { get(delegate, method) {
            const call = Reflect.get(delegate, method, delegate);
            return typeof call === 'function' ? async (...args: unknown[]) => pauseOnce(await call.apply(delegate, args)) : call;
          } });
        }
        return typeof value === 'function' ? value.bind(transaction) : value;
      } })), options);
      const value = Reflect.get(target, property, target);
      return typeof value === 'function' ? value.bind(target) : value;
    } });
    return { source: createPrismaAdminDataSource(wrapped, config, now), firstRead, release };
  };
  for (const view of ['members', 'reports'] as const) {
    it(`holds a repeatable-read ${view} snapshot while a second connection commits a matching user`, async () => {
      const group = await users(`snapshot-${view}`, 3);
      const paused = pausedSnapshot();
      const running = paused.source.view(view, { query: group.query, reportScope: 'ALL_ACCOUNTS' });
      try {
        await Promise.race([paused.firstRead, running.then(() => { throw new Error('Read completed without opening its snapshot transaction'); })]);
        const writerId = `${group.query}-writer`; ownedIds.push(writerId);
        await prisma.user.create({ data: { id: writerId, firebaseUid: writerId,
          email: `${writerId}@example.test`, displayName: group.query, createdAt: eventTime } });
        paused.release();
        const page = await running as UsagePage;
        expect(page.total).toBe(3);
        expect(page.rows).toHaveLength(3);
        expect(page.rows.some(row => row.userId === writerId || row.id === writerId)).toBe(false);
        if (view === 'reports') expect(page.summary.memberCount).toBe(3);
        expect(await prisma.user.count({ where: { displayName: group.query } })).toBe(4);
      } finally { paused.release(); await running.catch(() => undefined); }
    }, 20_000);
  }

  it('reads 1000 members / 10000 posts / 20000 saved results with bounded queries and 15 concurrent correct reports', async () => {
    const group = await users('load', 1000);
    const posts: Prisma.PostCreateManyInput[] = [];
    const publishes: Prisma.PlatformPublishCreateManyInput[] = [];
    for (let index = 0; index < 10_000; index++) {
      const userId = group.ids[index % group.ids.length]; const id = `${group.query}-post-${index}`;
      posts.push({ id, userId, caption: 'Local load fixture', videoS3Key: 'fixture/not-uploaded.mp4',
        selectedPlatforms: ['TIKTOK', 'YOUTUBE_SHORTS'], createdAt: eventTime });
      const kind = index % 5;
      for (const platform of ['TIKTOK', 'YOUTUBE_SHORTS'] as const) {
        const status = kind === 2 ? 'FAILED' : kind === 3 ? 'PENDING' : kind === 4 && platform === 'YOUTUBE_SHORTS' ? 'PUBLISHING' : 'PUBLISHED';
        const deliveryOutcome = kind === 0 || kind === 2 ? 'LIVE' : kind === 1 ? 'DRAFT' : kind === 4 ? 'PRIVATE' : null;
        publishes.push({ postId: id, platform, status, deliveryOutcome, createdAt: eventTime });
      }
    }
    for (let offset = 0; offset < posts.length; offset += 1000) await prisma.post.createMany({ data: posts.slice(offset, offset + 1000) });
    for (let offset = 0; offset < publishes.length; offset += 1000) await prisma.platformPublish.createMany({ data: publishes.slice(offset, offset + 1000) });
    await prisma.realClipCaptionUsage.createMany({ data: group.ids.map(userId => ({ userId, monthKey: '2026-10', createdAt: eventTime })) });
    await prisma.aiEditUsage.createMany({ data: group.ids.map(userId => ({ userId, monthKey: '2026-10', minutes: 2, createdAt: eventTime })) });
    expect(await prisma.post.count({ where: { userId: { in: group.ids } } })).toBe(10_000);
    expect(await prisma.platformPublish.count({ where: { post: { userId: { in: group.ids } } } })).toBe(20_000);
    const expected = { ...emptyTotals(1000), captionRequests: 1000, editMinutes: 2000,
      quotaPostUnits: 20_000, postUnits: 20_000, livePostUnits: 4000, draftPostUnits: 4000,
      otherDeliveredPostUnits: 2000, failedPostUnits: 4000, pendingPostUnits: 6000 };
    let observing = false; let selectQueries = 0;
    prisma.$on('query', event => { if (observing && /^\s*(?:SELECT|WITH)\b/i.test(event.query)) selectQueries++; });
    observing = true;
    const initial = await report({ query: group.query });
    observing = false;
    expect(initial.summary).toEqual(expected);
    expect(initial.total).toBe(1000);
    expect(initial.rows).toHaveLength(50);
    expect(selectQueries).toBeLessThanOrEqual(7);
    const durations: number[] = [];
    const pages = await Promise.all(Array.from({ length: 15 }, async () => {
      const started = performance.now(); const page = await report({ query: group.query });
      durations.push(performance.now() - started); return page;
    }));
    for (const page of pages) { expect(page.total).toBe(1000); expect(page.summary).toEqual(expected); expect(page.rows).toHaveLength(50); }
    durations.sort((a, b) => a - b);
    console.info(JSON.stringify({ fixture: 'loopback-only-admin-usage', users: 1000, posts: 10_000,
      platformResults: 20_000, concurrentReads: 15, errors: 0, selectQueriesPerReport: selectQueries,
      p50Ms: +durations[Math.ceil(durations.length * 0.5) - 1].toFixed(2),
      p95Ms: +durations[Math.ceil(durations.length * 0.95) - 1].toFixed(2) }));
  }, 120_000);
});
