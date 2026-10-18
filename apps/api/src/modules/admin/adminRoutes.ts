import { readFile } from 'node:fs/promises';
import { Router, type Express, type RequestHandler } from 'express';
import rateLimit from 'express-rate-limit';
import { readAuthUser } from '../auth/authTypes.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import { adminViews, type AdminDataSource, type AdminView } from './adminDataSource.js';
import { AdminError, type TrialAccessStore, type TrialCommand } from './trialAccess.js';
import { toCsv } from './adminReports.js';

type Options = { config?: AdminConsoleConfig; authenticate: RequestHandler; trials?: TrialAccessStore;
  data?: AdminDataSource; now?: () => Date; runWithTarget?: RunWithActiveOwner;
  testPreviewToken?: string; testOnly?: boolean };
export const registerAdminConsole = (app: Express, options: Options) => {
  const { config, trials, data, authenticate } = options;
  if (!config) return;
  if (!trials || !data) throw new Error('Admin console requires data and trial repositories');
  if (options.testPreviewToken && (!options.testOnly || config.environment !== 'LOCAL')) {
    throw new Error('Fixture preview authentication is local-test-only');
  }
  const now = options.now ?? (() => new Date());
  const root = Router();
  root.use((_req, res, next) => {
    res.set('Cache-Control', 'private, no-store'); res.set('Referrer-Policy', 'no-referrer');
    res.set('Cross-Origin-Opener-Policy', 'same-origin-allow-popups');
    res.set('Content-Security-Policy', `default-src 'self'; script-src 'self' https://www.gstatic.com; style-src 'self'; img-src 'self' data:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com; frame-src https://${config.firebaseWeb.authDomain} https://accounts.google.com; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`);
    next();
  });
  root.get(['/', ''], async (_req, res) => res.type('html').send(await readFile(new URL('./web/admin.html', import.meta.url), 'utf8')));
  root.get('/assets/:name', async (req, res) => {
    const name = req.params.name;
    if (['anuphan-regular.ttf', 'anuphan-semibold.ttf'].includes(name)) {
      res.type('font/ttf').send(await readFile(new URL(`../../../assets/profile-fonts/${name}`, import.meta.url))); return;
    }
    if (!['admin.js', 'admin.css'].includes(name)) { res.sendStatus(404); return; }
    res.type(name.endsWith('.js') ? 'text/javascript' : 'text/css').send(await readFile(new URL(`./web/${name}`, import.meta.url), 'utf8'));
  });
  root.get('/config', (_req, res) => res.json({ firebaseWeb: config.firebaseWeb, environment: config.environment,
    ...(options.testPreviewToken ? { previewToken: options.testPreviewToken } : {}) }));
  const api = Router();
  api.use(rateLimit({ windowMs: 60000, limit: 90, standardHeaders: true, legacyHeaders: false }));
  api.use(authenticate);
  api.use((req, res, next) => {
    const user = readAuthUser(res.locals);
    if (!user || user.provider !== 'firebase' || user.identityAlreadyDeleted) { res.sendStatus(403); return; }
    const role = config.ownerUids.includes(user.id) ? 'OWNER' : config.viewerUids.includes(user.id) ? 'VIEWER' : null;
    if (!role) { res.status(403).json({ code: 'ADMIN_ACCESS_DENIED' }); return; }
    res.locals.adminRole = role;
    if (req.method === 'POST' && (req.get('Origin') !== config.origin || req.get('X-PostDee-Admin') !== '1' || !req.is('application/json'))) {
      res.status(403).json({ code: 'ADMIN_ORIGIN_REQUIRED' }); return;
    }
    next();
  });
  api.get('/session', (_req, res) => {
    const user = readAuthUser(res.locals)!;
    res.json({ role: res.locals.adminRole, email: user.email ?? '', environment: config.environment });
  });
  api.post('/view', async (req, res) => {
    try {
      const b = req.body as Record<string, unknown>;
      if (!b || typeof b.view !== 'string' || !adminViews.includes(b.view as AdminView) ||
          (b.query !== undefined && (typeof b.query !== 'string' || b.query.length > 120)) ||
          (b.cursor !== undefined && (typeof b.cursor !== 'string' || b.cursor.length > 160))) {
        throw new AdminError('ADMIN_FILTER_INVALID', 400);
      }
      const statuses = ['DRAFT', 'QUEUED', 'PUBLISHING', 'PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED'];
      const platforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
      if ((b.status && !statuses.includes(String(b.status))) || (b.platform && !platforms.includes(String(b.platform)))) throw new AdminError('ADMIN_FILTER_INVALID', 400);
      const date = (v: unknown) => { if (v === undefined || v === '') return undefined;
        if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v) || !Number.isFinite(Date.parse(v))) throw new AdminError('ADMIN_FILTER_INVALID', 400);
        const parsed = new Date(`${v}T00:00:00.000Z`);
        if (parsed.toISOString().slice(0, 10) !== v) throw new AdminError('ADMIN_FILTER_INVALID', 400);
        return parsed; };
      const from = date(b.from); const through = date(b.through);
      const until = through ? new Date(through.getTime() + 86400000) : undefined;
      if (from && until && from >= until) throw new AdminError('ADMIN_FILTER_INVALID', 400);
      const result = await data.view(b.view as AdminView, { query: String(b.query ?? '').trim(), cursor: b.cursor as string | undefined,
        status: b.status ? String(b.status) : undefined, platform: b.platform ? String(b.platform) : undefined, from, until });
      if (b.csv === true) {
        if (b.view !== 'reports') throw new AdminError('ADMIN_EXPORT_INVALID', 400);
        res.type('text/csv').set('Content-Disposition', 'attachment; filename="postdee-trial-report.csv"').send(toCsv(result.rows));
        return;
      }
      res.json({ ...result, checkedAt: now().toISOString() });
    } catch (error) {
      const safe = error instanceof AdminError ? error : new AdminError('ADMIN_DATA_UNAVAILABLE', 503);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  api.post('/member', async (req, res) => {
    try {
      const id = req.body?.userId;
      if (typeof id !== 'string' || !id || id.length > 128) throw new AdminError('ADMIN_FILTER_INVALID', 400);
      const member = await data.member(id);
      if (!member) throw new AdminError('ADMIN_MEMBER_NOT_FOUND', 404);
      res.json({ member });
    } catch (error) {
      const safe = error instanceof AdminError ? error : new AdminError('ADMIN_DATA_UNAVAILABLE', 503);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  api.post('/trials', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    if (res.locals.adminRole !== 'OWNER') { res.status(403).json({ code: 'ADMIN_OWNER_REQUIRED' }); return; }
    const age = now().getTime() / 1000 - (actor.authenticatedAtSeconds ?? 0);
    if (!Number.isFinite(age) || age < -60 || age > 900) { res.status(401).json({ code: 'ADMIN_REAUTH_REQUIRED' }); return; }
    try {
      const b = req.body as Record<string, unknown>;
      if (!b || typeof b.requestId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(b.requestId) ||
          typeof b.userId !== 'string' || !b.userId || b.userId.length > 128 ||
          typeof b.expectedEmail !== 'string' || b.expectedEmail.length > 254 ||
          typeof b.reason !== 'string' || typeof b.expectedVersion !== 'number' ||
          typeof b.days !== 'number' || !['GRANT', 'EXTEND', 'REVOKE'].includes(String(b.action)) ||
          !['STARTER', 'PRO'].includes(String(b.plan))) throw new AdminError('ADMIN_TRIAL_INVALID', 400);
      const member = await data.member(b.userId);
      if (!member) throw new AdminError('ADMIN_MEMBER_NOT_FOUND', 404);
      if (member.email.toLowerCase() !== b.expectedEmail.trim().toLowerCase()) throw new AdminError('ADMIN_MEMBER_CHANGED');
      const command: TrialCommand = { requestId: b.requestId, actorId: actor.id, userId: member.id,
        expectedEmail: member.email,
        action: b.action as TrialCommand['action'], plan: b.plan as TrialCommand['plan'], days: b.days,
        expectedVersion: b.expectedVersion, reason: b.reason.trim() };
      // Catch inside the target lifetime: local validation/transaction failures cannot create remote uncertainty.
      const execute = async () => { try { return { trial: await trials.mutate(command) }; }
        catch (error) { return { error }; } };
      const result = options.runWithTarget ? await options.runWithTarget(member.id, execute) : await execute();
      if ('error' in result) throw result.error;
      res.json({ status: 'ok', trial: result.trial });
    } catch (error) {
      const safe = error instanceof AdminError ? error : new AdminError('ADMIN_TRIAL_UNAVAILABLE', 503);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  root.use('/api', api); app.use('/admin', root);
};
