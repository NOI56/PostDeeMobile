import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../../app.js';
import { readServerConfig } from '../../config/env.js';
import type { AccountDeletionOutcome } from '../account/accountRoutes.js';
import { registerAdminConsole } from './adminRoutes.js';
import type { AdminConsoleConfig } from './adminConfig.js';
import type { AdminMember } from './adminDataSource.js';
import { createMemoryAdminAccountDeletionStore } from './adminAccountDeletion.js';
import { createMemoryTrialAccessStore } from './trialAccess.js';

const config: AdminConsoleConfig = { origin: 'http://localhost:4174', environment: 'LOCAL', ownerUids: ['owner'], viewerUids: ['viewer'],
  firebaseWeb: { apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' } };
const now = () => new Date('2026-10-26T00:00:00Z');
const command = { requestId: '0f6d3f5e-55a2-4c39-9a83-0d4c1b7a2f10', userId: 'member', expectedEmail: 'mali@example.com',
  reason: 'คำขอลบทางอีเมล 26 ต.ค.' };
const ok: AccountDeletionOutcome = { status: 200, body: { status: 'ok' } };

const setup = ({ withDeletion = true } = {}) => {
  const app = express(); app.use(express.json());
  const members = new Map<string, AdminMember>([
    ['member', { id: 'member', email: 'mali@example.com', paidPlan: 'BASIC' }],
    ['viewer', { id: 'viewer', email: 'viewer@example.com', paidPlan: 'BASIC' }]
  ]);
  const accountDeletions = createMemoryAdminAccountDeletionStore({ now });
  const deleteAccount = vi.fn(async (_userId: string): Promise<AccountDeletionOutcome> => ok);
  registerAdminConsole(app, { config, now, trials: createMemoryTrialAccessStore({ now }),
    data: { member: async id => members.get(id) ?? null, view: async () => ({ rows: [] }) },
    ...(withDeletion ? { accountDeletions, deleteAccount } : {}),
    authenticate: (req, res, next) => { const id = req.get('authorization')?.replace('Bearer ', '');
      if (!id) { res.sendStatus(401); return; }
      res.locals.authUser = { id: id === 'old-owner' ? 'owner' : id, provider: 'firebase',
        authenticatedAtSeconds: id === 'old-owner' ? 1 : now().getTime() / 1000 };
      next(); }
  });
  return { app, members, accountDeletions, deleteAccount };
};
const post = (app: express.Express, role: string, body: Record<string, unknown> = command) =>
  request(app).post('/admin/api/account-deletions')
    .set('Authorization', `Bearer ${role}`).set('Origin', config.origin).set('X-PostDee-Admin', '1').send(body);

describe('administrator account deletion', () => {
  it('deletes a reviewed member once and records who did it and why without the email', async () => {
    const { app, accountDeletions, deleteAccount } = setup();

    const response = await post(app, 'owner');

    expect(response.status).toBe(200);
    expect(response.body.deletion).toMatchObject({ requestId: command.requestId, actorId: 'owner', userId: 'member',
      reason: command.reason, status: 'COMPLETED', completedAt: now().toISOString(), lastErrorCode: null });
    expect(deleteAccount).toHaveBeenCalledExactlyOnceWith('member');
    const [record] = await accountDeletions.history();
    expect(JSON.stringify(record)).not.toContain('mali@example.com');

    // A replay of a completed request reports success without running cleanup again.
    expect((await post(app, 'owner')).status).toBe(200);
    expect(deleteAccount).toHaveBeenCalledOnce();
    expect(await accountDeletions.history()).toHaveLength(1);
  });

  it('rejects viewers, stale owner sign-in and cross-origin requests without deleting', async () => {
    const { app, accountDeletions, deleteAccount } = setup();

    expect((await post(app, 'viewer')).body.code).toBe('ADMIN_OWNER_REQUIRED');
    expect((await post(app, 'customer')).status).toBe(403);
    expect((await post(app, 'old-owner')).body.code).toBe('ADMIN_REAUTH_REQUIRED');
    const crossOrigin = await request(app).post('/admin/api/account-deletions').set('Authorization', 'Bearer owner')
      .set('Origin', 'https://other.example').set('X-PostDee-Admin', '1').send(command);
    expect(crossOrigin.status).toBe(403);
    expect(deleteAccount).not.toHaveBeenCalled();
    expect(await accountDeletions.history()).toHaveLength(0);
  });

  it('requires the reviewed email and a reason without addresses, and protects administrators', async () => {
    const { app, accountDeletions, deleteAccount } = setup();

    expect((await post(app, 'owner', { ...command, expectedEmail: 'other@example.com' })).body.code)
      .toBe('ADMIN_MEMBER_CHANGED');
    for (const reason of ['ok', 'ลูกค้า mali@example.com ขอลบ', 'x'.repeat(501), 'line\u0000break']) {
      expect((await post(app, 'owner', { ...command, reason })).body.code).toBe('ADMIN_DELETION_INVALID');
    }
    expect((await post(app, 'owner', { ...command, requestId: 'not-a-uuid' })).body.code).toBe('ADMIN_DELETION_INVALID');
    expect((await post(app, 'owner', { ...command, userId: 'viewer', expectedEmail: 'viewer@example.com' })).body.code)
      .toBe('ADMIN_DELETE_PROTECTED');
    expect((await post(app, 'owner', { ...command, userId: 'owner' })).body.code).toBe('ADMIN_DELETE_PROTECTED');
    expect((await post(app, 'owner', { ...command, userId: 'missing' })).body.code).toBe('ADMIN_MEMBER_NOT_FOUND');
    expect(deleteAccount).not.toHaveBeenCalled();
    expect(await accountDeletions.history()).toHaveLength(0);
  });

  it('keeps a failed deletion retryable under the same request after the member row is gone', async () => {
    const { app, members, accountDeletions, deleteAccount } = setup();
    deleteAccount.mockResolvedValueOnce({ status: 503, body: { status: 'error', code: 'ACCOUNT_IDENTITY_DELETE_FAILED' } });

    const first = await post(app, 'owner');
    expect(first.status).toBe(503);
    expect(first.body.code).toBe('ACCOUNT_IDENTITY_DELETE_FAILED');
    expect(await accountDeletions.find(command.requestId))
      .toMatchObject({ status: 'PENDING', lastErrorCode: 'ACCOUNT_IDENTITY_DELETE_FAILED', completedAt: null });

    // Local data was already removed, so the member lookup now fails; the
    // original reviewed request still finishes the deletion.
    members.delete('member');
    const retry = await post(app, 'owner');
    expect(retry.status).toBe(200);
    expect(retry.body.deletion).toMatchObject({ status: 'COMPLETED', lastErrorCode: null });
    expect(deleteAccount).toHaveBeenCalledTimes(2);
  });

  it('rejects a reused request id that carries a different decision', async () => {
    const { app, deleteAccount } = setup();
    deleteAccount.mockResolvedValueOnce({ status: 503, body: { code: 'ACCOUNT_MEDIA_CLEANUP_FAILED' } });
    await post(app, 'owner');

    const altered = await post(app, 'owner', { ...command, reason: 'เหตุผลอื่นที่ไม่ได้ตรวจ' });

    expect(altered.status).toBe(409);
    expect(altered.body.code).toBe('ADMIN_REQUEST_CONFLICT');
    expect(deleteAccount).toHaveBeenCalledOnce();
  });

  it('reports unavailable when the deletion service is not wired', async () => {
    const { app } = setup({ withDeletion: false });

    const response = await post(app, 'owner');

    expect(response.status).toBe(503);
    expect(response.body.code).toBe('ADMIN_ACCOUNT_DELETION_UNAVAILABLE');
  });
});

describe('administrator account deletion through the real account saga', () => {
  const createConsoleApp = ({ deletionEnabled = true } = {}) => {
    // The fixture URL satisfies config validation; every store here is in memory.
    const config = readServerConfig({ NODE_ENV: 'test', DATABASE_URL: 'postgresql://unused@127.0.0.1:55439/postdee_admin_fixture',
      AUTH_PROVIDER: 'firebase', FIREBASE_PROJECT_ID: 'fixture',
      FIREBASE_AUTH_DELETE_ENABLED: String(deletionEnabled), TRIAL_ACCESS_ENABLED: 'true',
      ADMIN_CONSOLE_ENABLED: 'true', ADMIN_CONSOLE_ORIGIN: 'http://localhost:4174', ADMIN_ENVIRONMENT: 'LOCAL',
      ADMIN_OWNER_UIDS: 'owner',
      ADMIN_FIREBASE_WEB_CONFIG: JSON.stringify({ apiKey: 'fixture', authDomain: 'fixture.firebaseapp.com', projectId: 'fixture', appId: 'fixture' }) });
    const verifier = { verifyIdToken: async (id: string) => ({ id, provider: 'firebase' as const, email: `${id}@example.com`,
      authenticatedAtSeconds: Math.floor(Date.now() / 1000) - (id === 'member' ? 3600 : 0) }) };
    const accountIdentityDeleter = { deleteIdentity: vi.fn(async () => undefined) };
    const accountDeletions = createMemoryAdminAccountDeletionStore();
    // Production builds no identity deleter while the flag is off; mirror that.
    const app = createApp({ config, trialAccessStore: createMemoryTrialAccessStore(), firebaseVerifier: verifier,
      adminFirebaseVerifier: verifier, ...(deletionEnabled ? { accountIdentityDeleter } : {}),
      adminAccountDeletionStore: accountDeletions,
      videoStorage: { supportsOwnerCleanup: true, createUpload: vi.fn(), createDownloadAccess: vi.fn(),
        deleteVideo: vi.fn(async () => undefined), deleteAllVideosForOwner: vi.fn(async () => undefined) },
      adminDataSource: { member: async id => id === 'member' ? { id, email: 'member@example.com', paidPlan: 'BASIC' } : null,
        view: async () => ({ rows: [] }) } });
    return { app, accountIdentityDeleter, accountDeletions };
  };
  const deleteMember = (app: express.Express) => request(app).post('/admin/api/account-deletions')
    .set('Authorization', 'Bearer owner').set('Origin', 'http://localhost:4174').set('X-PostDee-Admin', '1')
    .send({ ...command, expectedEmail: 'member@example.com' });

  it('removes the member data and Firebase identity even though the member signed in long ago', async () => {
    const { app, accountIdentityDeleter, accountDeletions } = createConsoleApp();
    await request(app).post('/templates').set('Authorization', 'Bearer member')
      .send({ title: 'Saved', body: 'Removed by an operator' }).expect(201);
    // The member's own stale session still cannot delete the account itself.
    expect((await request(app).delete('/account').set('Authorization', 'Bearer member')).body.code)
      .toBe('ACCOUNT_REAUTHENTICATION_REQUIRED');

    const response = await deleteMember(app);

    expect(response.status).toBe(200);
    expect(accountIdentityDeleter.deleteIdentity).toHaveBeenCalledExactlyOnceWith({ id: 'member', provider: 'firebase' });
    expect((await accountDeletions.find(command.requestId))?.status).toBe('COMPLETED');
    const templates = await request(app).get('/templates').set('Authorization', 'Bearer member');
    expect(templates.status).toBe(200);
    expect(templates.body.templates).toEqual([]);
  });

  it('stays closed while account deletion is disabled and records the attempt', async () => {
    const { app, accountIdentityDeleter, accountDeletions } = createConsoleApp({ deletionEnabled: false });
    await request(app).post('/templates').set('Authorization', 'Bearer member')
      .send({ title: 'Kept', body: 'Deletion is disabled' }).expect(201);

    const response = await deleteMember(app);

    expect(response.status).toBe(503);
    expect(response.body.code).toBe('ACCOUNT_DELETION_UNAVAILABLE');
    expect(accountIdentityDeleter.deleteIdentity).not.toHaveBeenCalled();
    expect(await accountDeletions.find(command.requestId))
      .toMatchObject({ status: 'PENDING', lastErrorCode: 'ACCOUNT_DELETION_UNAVAILABLE' });
    const templates = await request(app).get('/templates').set('Authorization', 'Bearer member').expect(200);
    expect(templates.body.templates).toHaveLength(1);
  });
});
