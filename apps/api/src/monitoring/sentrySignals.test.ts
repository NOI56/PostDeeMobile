import { describe, expect, it, vi } from 'vitest';
import { createSentrySignalSource, readSentrySignalsConfig, sentrySignalAreas, type SentrySignalsConfig } from './sentrySignals.js';

const token = 'sntryu_0123456789abcdef0123456789abcdef';
const env = { SENTRY_DSN: 'https://abc123@o4507.ingest.de.sentry.io/4508', SENTRY_ENVIRONMENT: 'staging', SENTRY_SIGNALS_TOKEN: token };
const config: SentrySignalsConfig = { apiBaseUrl: 'https://de.sentry.io', organizationId: '4507', projectIds: ['4508'],
  environment: 'staging', token, windowMinutes: 30 };

describe('Sentry signal config', () => {
  it('stays off without a token and derives everything else from the DSN', () => {
    expect(readSentrySignalsConfig({ SENTRY_DSN: env.SENTRY_DSN, SENTRY_ENVIRONMENT: 'staging' })).toBeUndefined();
    expect(readSentrySignalsConfig(env)).toEqual(config);
    expect(readSentrySignalsConfig({ ...env, SENTRY_DSN: 'https://abc123@o9.ingest.us.sentry.io/77',
      SENTRY_SIGNALS_PROJECT_IDS: '88, 77', SENTRY_SIGNALS_WINDOW_MINUTES: '60' }))
      .toMatchObject({ apiBaseUrl: 'https://sentry.io', organizationId: '9', projectIds: ['77', '88'], windowMinutes: 60 });
  });
  it('rejects bad values without echoing the token', () => {
    expect(() => readSentrySignalsConfig({ SENTRY_SIGNALS_TOKEN: token })).toThrow('needs SENTRY_DSN');
    expect(() => readSentrySignalsConfig({ ...env, SENTRY_SIGNALS_TOKEN: 'short' })).toThrow('must be a Sentry auth token');
    expect(() => readSentrySignalsConfig({ ...env, SENTRY_SIGNALS_PROJECT_IDS: 'mobile' })).toThrow('numeric Sentry project ids');
    expect(() => readSentrySignalsConfig({ ...env, SENTRY_SIGNALS_WINDOW_MINUTES: '1' })).toThrow('from 5 to 240');
    try { readSentrySignalsConfig({ ...env, SENTRY_SIGNALS_TOKEN: `${token} bad` }); } catch (error) {
      expect(String(error)).not.toContain(token);
    }
  });
});

describe('Sentry signal source', () => {
  const issue = (shortId: string, lastSeen: string) => ({ shortId, title: `TypeError in ${shortId}`, lastSeen,
    permalink: `https://postdee.sentry.io/issues/${shortId}/`, count: '12' });
  it('runs one read-only issue search per area and reports only areas with recent issues', async () => {
    const fetchImpl = vi.fn(async (url: string | URL | Request) => {
      const query = new URL(String(url)).searchParams.get('query')!;
      const body = query.includes('platform:TIKTOK') ? [issue('API-1', '2026-10-28T02:50:00Z'), issue('API-2', '2026-10-28T02:58:00Z')]
        : query.includes('route:/uploads*') && !query.includes('!route') ? [issue('API-3', '2026-10-28T02:40:00Z')] : [];
      return new Response(JSON.stringify(body), { status: 200 });
    });
    const source = createSentrySignalSource({ config, fetchImpl: fetchImpl as unknown as typeof fetch, now: () => new Date('2026-10-28T03:00:00Z') });
    const snapshot = await source.read();
    expect(fetchImpl).toHaveBeenCalledTimes(sentrySignalAreas.length);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    const parsed = new URL(url);
    expect(parsed.origin + parsed.pathname).toBe('https://de.sentry.io/api/0/organizations/4507/issues/');
    expect(parsed.searchParams.get('query')).toBe('is:unresolved lastSeen:-30m operation:publishing.platform platform:TIKTOK');
    expect(parsed.searchParams.getAll('project')).toEqual(['4508']);
    expect(parsed.searchParams.get('environment')).toBe('staging');
    expect((init.headers as Record<string, string>).Authorization).toBe(`Bearer ${token}`);
    expect(init.method).toBeUndefined();
    expect(snapshot).toMatchObject({ configured: true, failed: false, checkedAt: '2026-10-28T03:00:00.000Z' });
    expect(snapshot.signals.map(s => [s.key, s.label, s.lastSeen])).toEqual([
      ['publish-tiktok', 'การส่งโพสต์ไป TikTok', '2026-10-28T02:58:00.000Z'],
      ['uploads', 'การอัปโหลดวิดีโอ', '2026-10-28T02:40:00.000Z']]);
    expect(snapshot.signals[0]).toMatchObject({ platform: 'TIKTOK', issues: [{ shortId: 'API-1', count: 12 }, { shortId: 'API-2' }] });
  });
  it('caches for two minutes and shares one refresh between callers', async () => {
    let time = Date.parse('2026-10-28T03:00:00Z');
    const fetchImpl = vi.fn(async () => new Response('[]', { status: 200 }));
    const source = createSentrySignalSource({ config, fetchImpl: fetchImpl as unknown as typeof fetch, now: () => new Date(time) });
    await Promise.all([source.read(), source.read()]);
    await source.read();
    expect(fetchImpl).toHaveBeenCalledTimes(sentrySignalAreas.length);
    time += 121_000;
    await source.read();
    expect(fetchImpl).toHaveBeenCalledTimes(sentrySignalAreas.length * 2);
  });
  it('marks a failed refresh, ignores malformed issues, and stays off without config', async () => {
    const failing = createSentrySignalSource({ config, fetchImpl: (async () => new Response('{}', { status: 401 })) as unknown as typeof fetch });
    expect(await failing.read()).toMatchObject({ configured: true, failed: true, signals: [] });
    const malformed = createSentrySignalSource({ config, fetchImpl: (async () => new Response(JSON.stringify([{ title: 'no id' },
      { shortId: 'API-9', title: 'x', lastSeen: 'not a date' }]), { status: 200 })) as unknown as typeof fetch });
    expect((await malformed.read()).signals).toEqual([]);
    const fetchImpl = vi.fn();
    expect(await createSentrySignalSource({ fetchImpl: fetchImpl as unknown as typeof fetch }).read())
      .toEqual({ configured: false, checkedAt: null, failed: false, signals: [] });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
