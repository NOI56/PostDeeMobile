import { readFile } from 'node:fs/promises';
import { Router, type Express, type RequestHandler } from 'express';
import rateLimit from 'express-rate-limit';
import { readAuthUser } from '../auth/authTypes.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { AccountDeletionOutcome } from '../account/accountRoutes.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import { adminViews, type AdminDataSource, type AdminView } from './adminDataSource.js';
import { AdminError, type TrialAccessStore, type TrialCommand } from './trialAccess.js';
import { accountDeletionIntentHash, readAccountDeletionReason, type AdminAccountDeletionStore } from './adminAccountDeletion.js';
import { toCsv } from './adminReports.js';
import { readServiceIncidentDraft, type ServiceIncidentStore } from '../serviceStatus/serviceIncident.js';
import {
  SupportChatError, readSupportMessageBody, readSupportMessageId, supportThreadStatuses,
  type SupportChatStore, type SupportMessage, type SupportThreadStatus
} from '../supportChat/supportChat.js';
import { UploadSessionConflictError } from '../uploads/uploadSessionStore.js';
import type { SupportBotProviderKind } from '../../config/env.js';
import type { SupportBotSettingsStore } from '../supportBot/supportBot.js';
import type { SentrySignalSource } from '../../monitoring/sentrySignals.js';

type Options = { config?: AdminConsoleConfig; authenticate: RequestHandler; trials?: TrialAccessStore;
  data?: AdminDataSource; now?: () => Date; runWithTarget?: RunWithActiveOwner; incidents?: ServiceIncidentStore;
  support?: SupportChatStore; notifySupportReply?: (userId: string) => Promise<void>;
  supportBot?: { provider: SupportBotProviderKind; settings: SupportBotSettingsStore };
  signals?: SentrySignalSource;
  accountDeletions?: AdminAccountDeletionStore; deleteAccount?: (userId: string) => Promise<AccountDeletionOutcome>;
  testPreviewToken?: string; testOnly?: boolean };
const requestIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Team replies show who answered only as "you" or "the team"; UIDs stay server side.
const adminSupportMessage = (m: SupportMessage, actorId: string) => ({ id: m.id, sender: m.sender, body: m.body,
  createdAt: m.createdAt, byYou: m.sender === 'TEAM' && m.authorId === actorId });
const readSupportUserId = (value: unknown) => {
  if (typeof value !== 'string' || !value || value.length > 128) throw new AdminError('ADMIN_FILTER_INVALID', 400);
  return value;
};
const supportFailure = (error: unknown) => error instanceof AdminError ? error
  : error instanceof SupportChatError ? new AdminError(error.code, error.status)
  : error instanceof UploadSessionConflictError ? new AdminError('ADMIN_SUPPORT_MEMBER_DELETING')
  : new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
export const registerAdminConsole = (app: Express, options: Options) => {
  const { config, trials, data, authenticate } = options;
  if (!config) return;
  if (!trials || !data) throw new Error('Admin console requires data and trial repositories');
  if (options.testPreviewToken && (!options.testOnly || config.environment !== 'LOCAL')) {
    throw new Error('Fixture preview authentication is local-test-only');
  }
  const now = options.now ?? (() => new Date());
  const supportBotStatus = async () => {
    const settings = options.supportBot ? await options.supportBot.settings.read() : null;
    return { provider: options.supportBot?.provider ?? 'off', enabled: !!settings?.enabled && options.supportBot?.provider !== 'off',
      updatedAt: settings?.updatedAt ?? null };
  };
  const root = Router();
  root.use((_req, res, next) => {
    res.set('Cache-Control', 'private, no-store'); res.set('Referrer-Policy', 'no-referrer');
    res.set('Cross-Origin-Opener-Policy', 'same-origin-allow-popups');
    res.set('Content-Security-Policy', `default-src 'self'; script-src 'self' https://www.gstatic.com https://apis.google.com; style-src 'self'; img-src 'self' data:; connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com; frame-src https://${config.firebaseWeb.authDomain} https://accounts.google.com; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`);
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
  api.get('/support/pending-count', async (_req, res) => {
    try {
      if (!options.support) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      const count = await options.support.countWaitingForTeam();
      if (!Number.isSafeInteger(count) || count < 0) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      res.json({ count, checkedAt: now().toISOString() });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  api.post('/view', async (req, res) => {
    try {
      const b = req.body as Record<string, unknown>;
      // Service notices live in their own store, not the read-only member snapshot.
      if (b?.view === 'incidents') {
        if (b.csv !== undefined || (b.cursor !== undefined && (typeof b.cursor !== 'string' || b.cursor.length > 160))) {
          throw new AdminError('ADMIN_FILTER_INVALID', 400);
        }
        if (!options.incidents) throw new AdminError('ADMIN_DATA_UNAVAILABLE', 503);
        const [result, signals] = await Promise.all([options.incidents.list({ cursor: b.cursor as string | undefined }),
          options.signals?.read().catch(() => ({ configured: true, checkedAt: null, failed: true, signals: [] }))]);
        res.json({ ...result, signals: signals ?? { configured: false, checkedAt: null, failed: false, signals: [] },
          asOf: now().toISOString(), checkedAt: now().toISOString() });
        return;
      }
      if (b?.view === 'support') {
        if (b.csv !== undefined || (b.cursor !== undefined && (typeof b.cursor !== 'string' || b.cursor.length > 160)) ||
            (b.query !== undefined && (typeof b.query !== 'string' || b.query.length > 120)) ||
            (b.status !== undefined && b.status !== '' && !supportThreadStatuses.includes(b.status as SupportThreadStatus))) {
          throw new AdminError('ADMIN_FILTER_INVALID', 400);
        }
        if (!options.support) throw new AdminError('ADMIN_DATA_UNAVAILABLE', 503);
        const [result, bot] = await Promise.all([options.support.listThreads({ status: (b.status || undefined) as SupportThreadStatus | undefined,
          query: String(b.query ?? '').trim() || undefined, cursor: b.cursor as string | undefined }), supportBotStatus()]);
        res.json({ ...result, bot, asOf: now().toISOString(), checkedAt: now().toISOString() });
        return;
      }
      if (!b || typeof b.view !== 'string' || !adminViews.includes(b.view as AdminView) ||
          (b.query !== undefined && (typeof b.query !== 'string' || b.query.length > 120)) ||
          (b.cursor !== undefined && (typeof b.cursor !== 'string' || b.cursor.length > 160))) {
        throw new AdminError('ADMIN_FILTER_INVALID', 400);
      }
      const statuses = ['DRAFT', 'QUEUED', 'PUBLISHING', 'PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED'];
      const platforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
      if ((b.status && !statuses.includes(String(b.status))) || (b.platform && !platforms.includes(String(b.platform)))) throw new AdminError('ADMIN_FILTER_INVALID', 400);
      if (b.reportScope !== undefined && !['ALL_ACCOUNTS', 'LATEST_TRIAL'].includes(b.reportScope as string)) {
        throw new AdminError('ADMIN_FILTER_INVALID', 400);
      }
      const reportScope = (b.reportScope ?? 'LATEST_TRIAL') as 'ALL_ACCOUNTS' | 'LATEST_TRIAL';
      const date = (v: unknown) => { if (v === undefined || v === '') return undefined;
        if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v) || !Number.isFinite(Date.parse(v))) throw new AdminError('ADMIN_FILTER_INVALID', 400);
        const parsed = new Date(`${v}T00:00:00.000Z`);
        if (parsed.toISOString().slice(0, 10) !== v) throw new AdminError('ADMIN_FILTER_INVALID', 400);
        return parsed; };
      const from = date(b.from); const through = date(b.through);
      const until = through ? new Date(through.getTime() + 86400000) : undefined;
      if (from && until && from >= until) throw new AdminError('ADMIN_FILTER_INVALID', 400);
      const result = await data.view(b.view as AdminView, { query: String(b.query ?? '').trim(), cursor: b.cursor as string | undefined,
        status: b.status ? String(b.status) : undefined, platform: b.platform ? String(b.platform) : undefined, from, until,
        reportScope });
      if (b.csv === true) {
        if (b.view !== 'reports') throw new AdminError('ADMIN_EXPORT_INVALID', 400);
        const filename = reportScope === 'LATEST_TRIAL' ? 'postdee-trial-report.csv' : 'postdee-usage-report.csv';
        res.type('text/csv').set('Content-Disposition', `attachment; filename="${filename}"`).send(toCsv(result.rows));
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
      res.json({ member, checkedAt: now().toISOString() });
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
  // Publishes or updates a customer-facing service notice. The browser makes
  // one id per reviewed create and keeps it until confirmed, so retries replay.
  api.post('/incidents', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    if (res.locals.adminRole !== 'OWNER') { res.status(403).json({ code: 'ADMIN_OWNER_REQUIRED' }); return; }
    try {
      const b = req.body as Record<string, unknown>;
      if (!b || typeof b.id !== 'string' || !requestIdPattern.test(b.id) || !['CREATE', 'UPDATE'].includes(String(b.action)) ||
          (b.action === 'UPDATE' && (!Number.isSafeInteger(b.expectedVersion) || Number(b.expectedVersion) < 1))) {
        throw new AdminError('ADMIN_INCIDENT_INVALID', 400);
      }
      if (!options.incidents) throw new AdminError('ADMIN_INCIDENT_UNAVAILABLE', 503);
      const command = { id: b.id.toLowerCase(), actorId: actor.id, draft: readServiceIncidentDraft(b) };
      const incident = b.action === 'CREATE' ? await options.incidents.create(command)
        : await options.incidents.update({ ...command, expectedVersion: Number(b.expectedVersion) });
      res.json({ status: 'ok', incident });
    } catch (error) {
      const safe = error instanceof AdminError ? error : new AdminError('ADMIN_INCIDENT_UNAVAILABLE', 503);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  // Dot's global switch. Owners only, and only when a provider is configured,
  // because turning it on sends member messages to the model provider.
  api.post('/support/bot-settings', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    if (res.locals.adminRole !== 'OWNER') { res.status(403).json({ code: 'ADMIN_OWNER_REQUIRED' }); return; }
    try {
      if (typeof req.body?.enabled !== 'boolean') throw new AdminError('ADMIN_FILTER_INVALID', 400);
      if (!options.supportBot) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      if (req.body.enabled && options.supportBot.provider === 'off') throw new AdminError('ADMIN_SUPPORT_BOT_UNCONFIGURED');
      await options.supportBot.settings.set({ enabled: req.body.enabled, actorId: actor.id });
      res.json({ status: 'ok', bot: await supportBotStatus() });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  // Per-conversation switch; any administrator who answers chats may use it.
  api.post('/support/thread-bot', async (req, res) => {
    try {
      const userId = readSupportUserId(req.body?.userId);
      if (typeof req.body?.enabled !== 'boolean') throw new AdminError('ADMIN_FILTER_INVALID', 400);
      if (!options.support) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      res.json({ status: 'ok', thread: await options.support.setBotEnabled({ userId, enabled: req.body.enabled }) });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  // Support chat: owners and viewers both read and answer member conversations.
  api.post('/support/thread', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    try {
      const userId = readSupportUserId(req.body?.userId);
      if (!options.support) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      const read = await options.support.readThread(userId);
      if (!read) throw new AdminError('ADMIN_SUPPORT_THREAD_NOT_FOUND', 404);
      const member = await data.member(userId);
      res.json({ thread: read.thread, messages: read.messages.map(m => adminSupportMessage(m, actor.id)), hasEarlier: read.hasEarlier,
        member: member ? { id: member.id, email: member.email, displayName: member.displayName ?? null, paidPlan: member.paidPlan } : null,
        checkedAt: now().toISOString() });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  // The browser makes one message id per reply and reuses it on retry, so a
  // retry after a lost response neither duplicates the reply nor its push.
  api.post('/support/reply', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    try {
      const userId = readSupportUserId(req.body?.userId);
      const id = readSupportMessageId(req.body?.id);
      const body = readSupportMessageBody(req.body?.body);
      if (!options.support) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      const store = options.support;
      const execute = async () => { try { return { reply: await store.replyAsTeam({ userId, id, actorId: actor.id, body }) }; }
        catch (error) { return { error }; } };
      const result = options.runWithTarget ? await options.runWithTarget(userId, execute) : await execute();
      if ('error' in result) throw result.error;
      // Best-effort: a push failure must not turn a saved reply into an error.
      if (result.reply.created) await options.notifySupportReply?.(userId).catch(() => undefined);
      res.json({ status: 'ok', message: adminSupportMessage(result.reply.message, actor.id) });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  api.post('/support/close', async (req, res) => {
    try {
      const userId = readSupportUserId(req.body?.userId);
      const lastMessageId = readSupportMessageId(req.body?.lastMessageId);
      if (!options.support) throw new AdminError('ADMIN_SUPPORT_UNAVAILABLE', 503);
      res.json({ status: 'ok', thread: await options.support.close({ userId, lastMessageId }) });
    } catch (error) {
      const safe = supportFailure(error);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  // Deletes a member on their verified request (e.g. by email from the public
  // deletion page) through the same saga as in-app deletion. It must not run
  // inside the target's owner lifetime, or the saga's drain would wait on it.
  api.post('/account-deletions', async (req, res) => {
    const actor = readAuthUser(res.locals)!;
    if (res.locals.adminRole !== 'OWNER') { res.status(403).json({ code: 'ADMIN_OWNER_REQUIRED' }); return; }
    const age = now().getTime() / 1000 - (actor.authenticatedAtSeconds ?? 0);
    if (!Number.isFinite(age) || age < -60 || age > 900) { res.status(401).json({ code: 'ADMIN_REAUTH_REQUIRED' }); return; }
    const { accountDeletions, deleteAccount } = options;
    if (!accountDeletions || !deleteAccount) { res.status(503).json({ code: 'ADMIN_ACCOUNT_DELETION_UNAVAILABLE' }); return; }
    try {
      const b = req.body as Record<string, unknown>;
      if (!b || typeof b.requestId !== 'string' || !requestIdPattern.test(b.requestId) ||
          typeof b.userId !== 'string' || !b.userId || b.userId.length > 128 ||
          typeof b.expectedEmail !== 'string' || b.expectedEmail.length > 254) throw new AdminError('ADMIN_DELETION_INVALID', 400);
      const reason = readAccountDeletionReason(b.reason);
      if (config.ownerUids.includes(b.userId) || config.viewerUids.includes(b.userId)) throw new AdminError('ADMIN_DELETE_PROTECTED');
      const intentHash = accountDeletionIntentHash({ actorId: actor.id, userId: b.userId, reason });
      // A retry of a reviewed request continues even after the member row is gone.
      let record = await accountDeletions.find(b.requestId);
      if (!record) {
        const member = await data.member(b.userId);
        if (!member) throw new AdminError('ADMIN_MEMBER_NOT_FOUND', 404);
        if (member.email.toLowerCase() !== b.expectedEmail.trim().toLowerCase()) throw new AdminError('ADMIN_MEMBER_CHANGED');
        record = await accountDeletions.start({ requestId: b.requestId, actorId: actor.id, userId: member.id, reason, intentHash });
      }
      if (record.intentHash !== intentHash) throw new AdminError('ADMIN_REQUEST_CONFLICT');
      if (record.status === 'COMPLETED') { res.json({ status: 'ok', deletion: record }); return; }
      const outcome = await deleteAccount(record.userId);
      if (outcome.status !== 200) {
        const code = typeof outcome.body.code === 'string' ? outcome.body.code : 'ADMIN_ACCOUNT_DELETION_UNAVAILABLE';
        await accountDeletions.fail(record.requestId, code);
        res.status(outcome.status >= 400 ? outcome.status : 503).json({ code }); return;
      }
      res.json({ status: 'ok', deletion: await accountDeletions.complete(record.requestId) });
    } catch (error) {
      const safe = error instanceof AdminError ? error : new AdminError('ADMIN_ACCOUNT_DELETION_UNAVAILABLE', 503);
      res.status(safe.status).json({ code: safe.code });
    }
  });
  root.use('/api', api); app.use('/admin', root);
};
