import { createHash } from 'node:crypto';

import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createUserStore } from '../users/userStore.js';
import {
  type PostPeerConnectClient,
  type PostPeerIntegration,
  PostPeerConnectProviderError
} from './postPeerConnectClient.js';
import { registerSocialConnectionRoutes } from './socialConnectionRoutes.js';
import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';

const createLinkingFixture = ({ now }: { now?: () => Date } = {}) => {
  const store = createInMemorySocialConnectionStore();
  const integrationsByProfile = new Map<string, PostPeerIntegration[]>();
  const connectClient: PostPeerConnectClient = {
    createProfile: vi.fn(async ({ userId }) => ({ profileId: `profile-${userId}` })),
    createConnectUrl: vi.fn(async () => ({
      connectUrl: 'https://postpeer.test/connect/tiktok'
    })),
    listIntegrations: vi.fn(async ({ profileId }) =>
      integrationsByProfile.get(profileId) ?? []
    )
  };
  const app = express();
  app.use(express.json());
  const router = express.Router();
  registerSocialConnectionRoutes(
    router,
    (httpRequest, response, next) => {
      const id = httpRequest.header('x-postdee-user-id');
      if (id) {
        response.locals.authUser = { id, provider: 'mock' };
      }
      next();
    },
    { store, connectClient, userStore: createUserStore(), ...(now ? { now } : {}) }
  );
  app.use(router);
  return { app, store, connectClient, integrationsByProfile };
};

// Keep these requests valid against the unpatched baseline too: the baseline
// lacks a nonce response, so the RED evidence tests actual linking behavior.
const completionBody = (nonce: unknown) =>
  typeof nonce === 'string' ? { nonce } : {};

describe('social connection linking security regression', () => {
  it('does not import a newly listed integration when the user has no connect attempt', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    integrationsByProfile.set('profile-caller', [{
      id: 'unexpected-integration',
      platform: 'TIKTOK',
      platformUserId: 'unexpected-external-account'
    }]);

    const response = await request(app)
      .post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller')
      .expect(200);

    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
    expect(response.body.connections).toContainEqual({
      platform: 'TIKTOK', connected: false
    });
  });

  it.each(['externalAccountId', 'postPeerAccountId'] as const)(
    'rejects a new integration whose %s belongs to another user',
    async (collisionField) => {
      const { app, store, integrationsByProfile } = createLinkingFixture();
      await store.upsert({
        userId: 'original-owner', platform: 'TIKTOK',
        postPeerAccountId: 'original-integration',
        externalAccountId: 'original-external-account'
      });
      const connectResponse = await request(app)
        .post('/social-connections/TIKTOK/connect')
        .set('x-postdee-user-id', 'caller')
        .expect(200);
      integrationsByProfile.set('profile-caller', [{
        id: collisionField === 'postPeerAccountId'
          ? 'original-integration' : 'new-integration',
        platform: 'TIKTOK',
        platformUserId: collisionField === 'externalAccountId'
          ? 'original-external-account' : 'different-external-account'
      }]);

      const response = await request(app)
        .post('/social-connections/refresh')
        .set('x-postdee-user-id', 'caller')
        .send(completionBody(connectResponse.body.nonce))
        .expect(409);

      expect(response.body.code).toBe('SOCIAL_ACCOUNT_ALREADY_LINKED');
      expect(JSON.stringify(response.body)).not.toContain('original-owner');
      await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
        .resolves.toBeUndefined();
      await expect(store.getAccountId({ userId: 'original-owner', platform: 'TIKTOK' }))
        .resolves.toBe('original-integration');
    }
  );

  it('still connects and refreshes one new integration for the same authenticated user', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connectResponse = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller')
      .expect(200);
    integrationsByProfile.set('profile-caller', [{
      id: 'new-integration', platform: 'TIKTOK',
      platformUserId: 'caller-external-account', displayName: '@caller'
    }]);

    const response = await request(app)
      .post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller')
      .send(completionBody(connectResponse.body.nonce))
      .expect(200);

    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toMatchObject({
        postPeerAccountId: 'new-integration',
        externalAccountId: 'caller-external-account'
      });
    expect(response.body.connections).toContainEqual(expect.objectContaining({
      platform: 'TIKTOK', connected: true, displayName: '@caller'
    }));
    expect(response.body.connectAttemptConsumed).toBe(true);
  });

  it('returns an uncacheable short-lived nonce while storing only its hash', async () => {
    const now = () => new Date('2026-10-23T09:00:00.000Z');
    const { app, store } = createLinkingFixture({ now });
    const begin = vi.spyOn(store, 'beginConnectAttempt');
    const response = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);

    expect(response.headers['cache-control']).toBe('private, no-store');
    expect(response.body.nonce).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(response.body.expiresAt).toBe('2026-10-23T09:15:00.000Z');
    expect(begin).toHaveBeenCalledWith({
      userId: 'caller', platform: 'TIKTOK', profileId: 'profile-caller',
      nonceHash: createHash('sha256').update(response.body.nonce).digest('hex'),
      expiresAt: response.body.expiresAt, baselineIntegrationIds: []
    });
    expect(JSON.stringify(begin.mock.calls)).not.toContain(response.body.nonce);
  });

  it('does not complete an integration that existed before the connect attempt', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    integrationsByProfile.set('profile-caller', [{
      id: 'pre-existing-integration', platform: 'TIKTOK', platformUserId: 'pre-existing-account'
    }]);
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    const refresh = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);

    expect(refresh.body.connectAttemptConsumed).toBe(false);
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
  });

  it('does not import a different platform during a TikTok connect attempt', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [{
      id: 'unexpected-youtube', platform: 'YOUTUBE_SHORTS', platformUserId: 'youtube-account'
    }]);
    const refresh = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);

    expect(refresh.body.connectAttemptConsumed).toBe(false);
    await expect(store.getConnection({ userId: 'caller', platform: 'YOUTUBE_SHORTS' }))
      .resolves.toBeUndefined();
  });

  it('requires the attempt nonce even while a valid connect attempt is pending', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [{ id: 'new-tiktok', platform: 'TIKTOK' }]);
    await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').expect(200);
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();

    const refresh = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
    expect(refresh.body.connectAttemptConsumed).toBe(true);
  });

  it('keeps zero-candidate polling pending and consumes the nonce exactly once', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    const pending = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
    expect(pending.body.connectAttemptConsumed).toBe(false);
    integrationsByProfile.set('profile-caller', [{ id: 'new-tiktok', platform: 'TIKTOK' }]);
    const completed = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
    expect(completed.body.connectAttemptConsumed).toBe(true);

    const replay = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(409);
    expect(replay.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_EXPIRED');
    await expect(store.getAccountId({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBe('new-tiktok');
  });

  it('rejects another authenticated user replaying the initiating user nonce', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    await store.setProfileId({ userId: 'other-user', profileId: 'profile-other' });
    integrationsByProfile.set('profile-other', [{ id: 'other-tiktok', platform: 'TIKTOK' }]);
    const response = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'other-user')
      .send({ nonce: connect.body.nonce, userId: 'caller', profileId: 'profile-caller' })
      .expect(409);

    expect(response.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_EXPIRED');
    await expect(store.getConnection({ userId: 'other-user', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
  });

  it('rejects the nonce at its exact expiry without importing an integration', async () => {
    let instant = new Date('2026-10-23T09:00:00.000Z');
    const { app, store, integrationsByProfile } = createLinkingFixture({ now: () => instant });
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [{ id: 'late-tiktok', platform: 'TIKTOK' }]);
    instant = new Date(connect.body.expiresAt);
    const response = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(409);

    expect(response.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_EXPIRED');
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
  });

  it('invalidates an older attempt when the user starts another on the same platform', async () => {
    const { app, integrationsByProfile } = createLinkingFixture();
    const older = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    const newer = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [{ id: 'new-tiktok', platform: 'TIKTOK' }]);
    const stale = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: older.body.nonce }).expect(409);
    expect(stale.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_EXPIRED');
    const latest = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: newer.body.nonce }).expect(200);
    expect(latest.body.connectAttemptConsumed).toBe(true);
  });

  it('fails closed when several new integrations could complete the same attempt', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [
      { id: 'new-tiktok-1', platform: 'TIKTOK' },
      { id: 'new-tiktok-2', platform: 'TIKTOK' }
    ]);
    const response = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(409);

    expect(response.body.code).toBe('SOCIAL_CONNECTION_COMPLETION_AMBIGUOUS');
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
  });

  it.each([null, '', 'invalid', 12, {}, ['nonce']])(
    'rejects malformed nonce %j before querying provider integrations', async (nonce) => {
      const { app, connectClient } = createLinkingFixture();
      const response = await request(app).post('/social-connections/refresh')
        .set('x-postdee-user-id', 'caller').send({ nonce }).expect(400);
      expect(response.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_INVALID');
      expect(connectClient.listIntegrations).not.toHaveBeenCalled();
    }
  );

  it('removes a failed URL attempt without retaining usable completion state', async () => {
    const { app, store, connectClient } = createLinkingFixture();
    const begin = vi.spyOn(store, 'beginConnectAttempt');
    connectClient.createConnectUrl = vi.fn(async () => {
      throw new PostPeerConnectProviderError(503);
    });
    await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(502);

    const nonceHash = begin.mock.calls[0]?.[0].nonceHash;
    expect(nonceHash).toEqual(expect.any(String));
    await expect(store.getConnectAttempt({ userId: 'caller', nonceHash: nonceHash! }))
      .resolves.toBeUndefined();
  });

  it('cancels a pending attempt when the user disconnects before completion', async () => {
    const { app, integrationsByProfile } = createLinkingFixture();
    const connect = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    await request(app).delete('/social-connections/TIKTOK')
      .set('x-postdee-user-id', 'caller').expect(200);
    integrationsByProfile.set('profile-caller', [{ id: 'late-tiktok', platform: 'TIKTOK' }]);
    const response = await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(409);
    expect(response.body.code).toBe('SOCIAL_CONNECTION_ATTEMPT_EXPIRED');
  });

  it('refreshes display metadata for an already stored exact account without a nonce', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    await store.upsert({ userId: 'caller', platform: 'TIKTOK',
      postPeerAccountId: 'known-tiktok', externalAccountId: 'known-external', displayName: '@old' });
    integrationsByProfile.set('profile-caller', [{
      id: 'known-tiktok', platform: 'TIKTOK', platformUserId: 'known-external', displayName: '@new'
    }]);

    await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').expect(200);
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toMatchObject({ postPeerAccountId: 'known-tiktok',
        externalAccountId: 'known-external', displayName: '@new' });
  });

  it('does not silently replace the external identity behind an existing provider integration', async () => {
    const { app, store, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    await store.upsert({ userId: 'caller', platform: 'TIKTOK',
      postPeerAccountId: 'known-tiktok', externalAccountId: 'known-external' });
    integrationsByProfile.set('profile-caller', [{
      id: 'known-tiktok', platform: 'TIKTOK', platformUserId: 'different-external'
    }]);

    await request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').expect(200);
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBeUndefined();
  });

  it.each(['overwrite', 'disconnect'] as const)(
    'does not let a stale ordinary refresh %s a newer completed connection',
    async (staleAction) => {
      const { app, store, integrationsByProfile } = createLinkingFixture();
      await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
      await store.upsert({ userId: 'caller', platform: 'TIKTOK',
        postPeerAccountId: 'old-integration', externalAccountId: 'old-external' });
      const oldIntegration: PostPeerIntegration = {
        id: 'old-integration', platform: 'TIKTOK', platformUserId: 'old-external'
      };
      integrationsByProfile.set('profile-caller', staleAction === 'overwrite' ? [oldIntegration] : []);
      const readConnection = store.getConnection.bind(store);
      let releaseRead!: () => void;
      const blockedRead = new Promise<void>((resolve) => { releaseRead = resolve; });
      let signalCaptured!: () => void;
      const capturedRead = new Promise<void>((resolve) => { signalCaptured = resolve; });
      let pauseNextTikTokRead = true;
      vi.spyOn(store, 'getConnection').mockImplementation(async (input) => {
        const snapshot = await readConnection(input);
        if (pauseNextTikTokRead && input.platform === 'TIKTOK') {
          pauseNextTikTokRead = false;
          signalCaptured();
          await blockedRead;
        }
        return snapshot;
      });
      // Start the real request and pause after its stored-identity snapshot.
      const staleRefresh = request(app).post('/social-connections/refresh')
        .set('x-postdee-user-id', 'caller').then((response) => response);
      await capturedRead;
      try {
        const connect = await request(app).post('/social-connections/TIKTOK/connect')
          .set('x-postdee-user-id', 'caller').expect(200);
        const replacement: PostPeerIntegration = {
          id: 'new-integration', platform: 'TIKTOK', platformUserId: 'new-external'
        };
        integrationsByProfile.set('profile-caller', staleAction === 'overwrite'
          ? [oldIntegration, replacement] : [replacement]);
        await request(app).post('/social-connections/refresh')
          .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
      } finally {
        releaseRead();
      }
      expect((await staleRefresh).status).toBe(200);
      await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
        .resolves.toMatchObject({
          postPeerAccountId: 'new-integration', externalAccountId: 'new-external'
        });
    }
  );

  it('does not apply an old provider snapshot to a connection completed while polling', async () => {
    const { app, store, connectClient, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    await store.upsert({ userId: 'caller', platform: 'TIKTOK',
      postPeerAccountId: 'old-integration', externalAccountId: 'old-external' });
    const oldIntegration: PostPeerIntegration = {
      id: 'old-integration', platform: 'TIKTOK', platformUserId: 'old-external'
    };
    integrationsByProfile.set('profile-caller', [oldIntegration]);
    const listIntegrations = connectClient.listIntegrations;
    let releaseSnapshot!: () => void;
    const blockedSnapshot = new Promise<void>((resolve) => { releaseSnapshot = resolve; });
    let signalSnapshot!: () => void;
    const snapshotCaptured = new Promise<void>((resolve) => { signalSnapshot = resolve; });
    vi.spyOn(connectClient, 'listIntegrations').mockImplementationOnce(async (input) => {
      const snapshot = await listIntegrations(input);
      signalSnapshot();
      await blockedSnapshot;
      return snapshot;
    });
    const staleRefresh = request(app).post('/social-connections/refresh')
      .set('x-postdee-user-id', 'caller').then((response) => response);
    await snapshotCaptured;
    try {
      const connect = await request(app).post('/social-connections/TIKTOK/connect')
        .set('x-postdee-user-id', 'caller').expect(200);
      integrationsByProfile.set('profile-caller', [oldIntegration, {
        id: 'new-integration', platform: 'TIKTOK', platformUserId: 'new-external'
      }]);
      await request(app).post('/social-connections/refresh')
        .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
    } finally {
      releaseSnapshot();
    }
    expect((await staleRefresh).status).toBe(200);
    await expect(store.getConnection({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toMatchObject({
        postPeerAccountId: 'new-integration', externalAccountId: 'new-external'
      });
  });

  it('does not let a delayed explicit disconnect remove a newer connection or its next attempt', async () => {
    const { app, store, connectClient, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    await store.upsert({ userId: 'caller', platform: 'TIKTOK',
      postPeerAccountId: 'old-integration', externalAccountId: 'old-external' });
    const oldIntegration: PostPeerIntegration = {
      id: 'old-integration', platform: 'TIKTOK', platformUserId: 'old-external'
    };
    integrationsByProfile.set('profile-caller', [oldIntegration]);
    let releaseDisconnect!: () => void;
    const blockedDisconnect = new Promise<void>((resolve) => { releaseDisconnect = resolve; });
    let signalDisconnect!: () => void;
    const disconnectStarted = new Promise<void>((resolve) => { signalDisconnect = resolve; });
    connectClient.supportsIntegrationCleanup = true;
    connectClient.disconnectIntegration = vi.fn(async ({ integrationId }) => {
      signalDisconnect();
      await blockedDisconnect;
      integrationsByProfile.set('profile-caller',
        (integrationsByProfile.get('profile-caller') ?? []).filter(({ id }) => id !== integrationId));
    });
    const delayedDelete = request(app).delete('/social-connections/TIKTOK')
      .set('x-postdee-user-id', 'caller').then((response) => response);
    await disconnectStarted;
    let pendingNonceHash = '';
    try {
      const connect = await request(app).post('/social-connections/TIKTOK/connect')
        .set('x-postdee-user-id', 'caller').expect(200);
      integrationsByProfile.set('profile-caller', [oldIntegration, {
        id: 'new-integration', platform: 'TIKTOK', platformUserId: 'new-external'
      }]);
      await request(app).post('/social-connections/refresh')
        .set('x-postdee-user-id', 'caller').send({ nonce: connect.body.nonce }).expect(200);
      const nextAttempt = await request(app).post('/social-connections/TIKTOK/connect')
        .set('x-postdee-user-id', 'caller').expect(200);
      pendingNonceHash = createHash('sha256').update(nextAttempt.body.nonce).digest('hex');
    } finally {
      releaseDisconnect();
    }
    expect((await delayedDelete).status).toBe(200);
    expect(connectClient.disconnectIntegration).toHaveBeenCalledExactlyOnceWith({ integrationId: 'old-integration' });
    const connection = await store.getConnection({ userId: 'caller', platform: 'TIKTOK' });
    const nextAttempt = await store.getConnectAttempt({ userId: 'caller', nonceHash: pendingNonceHash });
    expect({ postPeerAccountId: connection?.postPeerAccountId, pendingNonceHash: nextAttempt?.nonceHash })
      .toEqual({ postPeerAccountId: 'new-integration', pendingNonceHash });
  });

  it('does not cancel a newer attempt created after a disconnected DELETE snapshot', async () => {
    const { app, store } = createLinkingFixture();
    const oldAttempt = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    const readSnapshot = store.getDisconnectSnapshot.bind(store);
    let releaseSnapshot!: () => void;
    const blockedSnapshot = new Promise<void>((resolve) => { releaseSnapshot = resolve; });
    let signalSnapshot!: () => void;
    const snapshotCaptured = new Promise<void>((resolve) => { signalSnapshot = resolve; });
    vi.spyOn(store, 'getDisconnectSnapshot').mockImplementationOnce(async (input) => {
      const snapshot = await readSnapshot(input);
      signalSnapshot();
      await blockedSnapshot;
      return snapshot;
    });
    const delayedDelete = request(app).delete('/social-connections/TIKTOK')
      .set('x-postdee-user-id', 'caller').then((response) => response);
    await snapshotCaptured;
    let pendingNonceHash = '';
    try {
      const nextAttempt = await request(app).post('/social-connections/TIKTOK/connect')
        .set('x-postdee-user-id', 'caller').expect(200);
      pendingNonceHash = createHash('sha256').update(nextAttempt.body.nonce).digest('hex');
    } finally {
      releaseSnapshot();
    }
    expect((await delayedDelete).status).toBe(200);
    await expect(store.getConnectAttempt({ userId: 'caller', nonceHash: pendingNonceHash }))
      .resolves.toMatchObject({ nonceHash: pendingNonceHash });
    const oldNonceHash = createHash('sha256').update(oldAttempt.body.nonce).digest('hex');
    await expect(store.getConnectAttempt({ userId: 'caller', nonceHash: oldNonceHash }))
      .resolves.toBeUndefined();
  });

  it('preserves the current connection and pending attempt when provider disconnect fails', async () => {
    const { app, store, connectClient, integrationsByProfile } = createLinkingFixture();
    await store.setProfileId({ userId: 'caller', profileId: 'profile-caller' });
    await store.upsert({ userId: 'caller', platform: 'TIKTOK',
      postPeerAccountId: 'old-integration', externalAccountId: 'old-external' });
    integrationsByProfile.set('profile-caller', [{
      id: 'old-integration', platform: 'TIKTOK', platformUserId: 'old-external'
    }]);
    const pending = await request(app).post('/social-connections/TIKTOK/connect')
      .set('x-postdee-user-id', 'caller').expect(200);
    connectClient.supportsIntegrationCleanup = true;
    connectClient.disconnectIntegration = vi.fn(async () => {
      throw new PostPeerConnectProviderError(503);
    });

    await request(app).delete('/social-connections/TIKTOK')
      .set('x-postdee-user-id', 'caller').expect(502);
    await expect(store.getAccountId({ userId: 'caller', platform: 'TIKTOK' }))
      .resolves.toBe('old-integration');
    const nonceHash = createHash('sha256').update(pending.body.nonce).digest('hex');
    await expect(store.getConnectAttempt({ userId: 'caller', nonceHash }))
      .resolves.toMatchObject({ nonceHash });
  });
});
