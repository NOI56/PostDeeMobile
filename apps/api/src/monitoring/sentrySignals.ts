import { readSentryConfig } from './sentryConfig.js';

// Reads recent unresolved Sentry issues so the support helper and the admin
// console know which parts of PostDee are failing right now. Opt-in: it needs
// a read-only token (scope event:read) next to the existing SENTRY_DSN.
export type SentrySignalsConfig = {
  apiBaseUrl: string; organizationId: string; projectIds: string[];
  environment: string; token: string; windowMinutes: number;
};

/**
 * Derives the organization, region and project from SENTRY_DSN (validated by
 * readSentryConfig), so the only new secret is SENTRY_SIGNALS_TOKEN.
 * SENTRY_SIGNALS_PROJECT_IDS may add more projects, e.g. the Mobile one.
 */
export const readSentrySignalsConfig = (env: Record<string, string | undefined>): SentrySignalsConfig | undefined => {
  const token = env.SENTRY_SIGNALS_TOKEN?.trim();
  if (!token) return undefined;
  // Never include the token in startup errors.
  if (!/^[A-Za-z0-9_.=-]{20,512}$/.test(token)) throw new Error('SENTRY_SIGNALS_TOKEN must be a Sentry auth token');
  const sentry = readSentryConfig(env);
  if (!sentry) throw new Error('SENTRY_SIGNALS_TOKEN needs SENTRY_DSN and SENTRY_ENVIRONMENT');
  const dsn = new URL(sentry.dsn);
  const organizationId = dsn.hostname.match(/^o(\d+)\./i)![1];
  const apiBaseUrl = /\.de\.sentry\.io$/i.test(dsn.hostname) ? 'https://de.sentry.io' : 'https://sentry.io';
  const extra = (env.SENTRY_SIGNALS_PROJECT_IDS ?? '').split(',').map(id => id.trim()).filter(Boolean);
  if (extra.some(id => !/^\d{1,20}$/.test(id))) throw new Error('SENTRY_SIGNALS_PROJECT_IDS must be numeric Sentry project ids');
  const minutes = Number(env.SENTRY_SIGNALS_WINDOW_MINUTES ?? 30);
  if (!Number.isInteger(minutes) || minutes < 5 || minutes > 240) {
    throw new Error('SENTRY_SIGNALS_WINDOW_MINUTES must be a whole number from 5 to 240');
  }
  return { apiBaseUrl, organizationId, projectIds: [...new Set([dsn.pathname.slice(1), ...extra])],
    environment: sentry.environment, token, windowMinutes: minutes };
};

// Each area is one Sentry search over the safe tags the API attaches to
// every report (see sentryMonitoring.ts). Labels are fixed Thai text, so no
// error message ever reaches a member or the model.
export const sentrySignalAreas = [
  { key: 'publish-tiktok', label: 'การส่งโพสต์ไป TikTok', platform: 'TIKTOK', query: 'operation:publishing.platform platform:TIKTOK' },
  { key: 'publish-youtube', label: 'การส่งโพสต์ไป YouTube Shorts', platform: 'YOUTUBE_SHORTS',
    query: 'operation:publishing.platform platform:YOUTUBE_SHORTS' },
  { key: 'publish-instagram', label: 'การส่งโพสต์ไป Instagram Reels', platform: 'INSTAGRAM_REELS',
    query: 'operation:publishing.platform platform:INSTAGRAM_REELS' },
  { key: 'publish-facebook', label: 'การส่งโพสต์ไป Facebook Reels', platform: 'FACEBOOK_REELS',
    query: 'operation:publishing.platform platform:FACEBOOK_REELS' },
  { key: 'scheduler', label: 'ระบบส่งโพสต์ตามเวลาที่ตั้งไว้',
    query: 'operation:[scheduler.poll,scheduler.process,worker.failure,worker.connection,publishing.cleanup]' },
  { key: 'uploads', label: 'การอัปโหลดวิดีโอ', query: 'route:/uploads*' },
  { key: 'captions', label: 'AI แคปชัน', query: 'operation:captions.provider' },
  { key: 'app', label: 'ระบบของแอปโดยรวม', query: 'operation:[http.unhandled,http.response] !route:/uploads*' }
] as const;
export type SentrySignalArea = typeof sentrySignalAreas[number];

export type SentrySignal = { key: SentrySignalArea['key']; label: string; platform?: string; lastSeen: string;
  // For administrators only: Sentry titles can contain technical details.
  issues: { shortId: string; title: string; permalink: string; lastSeen: string; count: number }[] };
export type SentrySignalsSnapshot = { configured: boolean; checkedAt: string | null; failed: boolean; signals: SentrySignal[] };
export type SentrySignalSource = { read: () => Promise<SentrySignalsSnapshot> };

type Issue = { shortId?: unknown; title?: unknown; permalink?: unknown; lastSeen?: unknown; count?: unknown };
const readIssues = (payload: unknown) => (Array.isArray(payload) ? payload as Issue[] : []).flatMap(issue =>
  typeof issue.shortId === 'string' && typeof issue.title === 'string' && typeof issue.lastSeen === 'string' &&
  Number.isFinite(Date.parse(issue.lastSeen))
    ? [{ shortId: issue.shortId, title: issue.title.slice(0, 200), lastSeen: new Date(issue.lastSeen).toISOString(),
      permalink: typeof issue.permalink === 'string' && issue.permalink.startsWith('https://') ? issue.permalink : '',
      count: Number(issue.count) || 0 }]
    : []);

export const createSentrySignalSource = ({ config, fetchImpl = fetch, now = () => new Date(), cacheMs = 120_000,
  timeoutMs = 5_000 }: {
  config?: SentrySignalsConfig; fetchImpl?: typeof fetch; now?: () => Date; cacheMs?: number; timeoutMs?: number;
}): SentrySignalSource => {
  let cached: { snapshot: SentrySignalsSnapshot; at: number } | undefined;
  let pending: Promise<SentrySignalsSnapshot> | undefined;
  const queryArea = async (area: SentrySignalArea, c: SentrySignalsConfig) => {
    const params = new URLSearchParams({ query: `is:unresolved lastSeen:-${c.windowMinutes}m ${area.query}`,
      environment: c.environment, statsPeriod: '24h', sort: 'date', limit: '5' });
    for (const project of c.projectIds) params.append('project', project);
    const response = await fetchImpl(`${c.apiBaseUrl}/api/0/organizations/${c.organizationId}/issues/?${params}`, {
      headers: { Authorization: `Bearer ${c.token}` }, signal: AbortSignal.timeout(timeoutMs) });
    if (!response.ok) throw new Error(`Sentry issues request failed with ${response.status}`);
    return readIssues(await response.json());
  };
  const load = async (c: SentrySignalsConfig): Promise<SentrySignalsSnapshot> => {
    const results = await Promise.allSettled(sentrySignalAreas.map(area => queryArea(area, c)));
    const signals = sentrySignalAreas.flatMap((area, index) => {
      const result = results[index];
      if (result.status !== 'fulfilled' || !result.value.length) return [];
      const lastSeen = result.value.map(issue => issue.lastSeen).sort().at(-1)!;
      return [{ key: area.key, label: area.label, ...('platform' in area ? { platform: area.platform } : {}), lastSeen,
        issues: result.value }];
    });
    return { configured: true, checkedAt: now().toISOString(), failed: results.every(result => result.status === 'rejected'), signals };
  };
  return {
    read: async () => {
      if (!config) return { configured: false, checkedAt: null, failed: false, signals: [] };
      if (cached && now().getTime() - cached.at < cacheMs) return cached.snapshot;
      pending ??= load(config).then(snapshot => {
        cached = { snapshot, at: now().getTime() };
        return snapshot;
      }).finally(() => { pending = undefined; });
      return pending;
    }
  };
};
