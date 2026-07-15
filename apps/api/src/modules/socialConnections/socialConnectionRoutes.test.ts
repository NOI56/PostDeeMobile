import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { createUserStore, type UserStore } from '../users/userStore.js';
import { registerSocialConnectionRoutes } from './socialConnectionRoutes.js';
import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';

const createFakeConnectClient = (
  overrides: Partial<PostPeerConnectClient> = {}
): PostPeerConnectClient => ({
  supportsIntegrationCleanup: true,
  createProfile: vi.fn(async () => ({ profileId: 'profile-1' })),
  createConnectUrl: vi.fn(async () => ({
    connectUrl: 'https://postpeer.test/connect/tiktok'
  })),
  listIntegrations: vi.fn(async () => []),
  disconnectIntegration: vi.fn(async () => undefined),
  ...overrides
});

const createTestApp = ({
  userId = 'seller-social',
  connectClient = createFakeConnectClient(),
  store = createInMemorySocialConnectionStore({
    now: () => '2026-06-26T09:00:00.000Z'
  }),
  userStore = createUserStore()
}: {
  userId?: string;
  connectClient?: PostPeerConnectClient;
  store?: ReturnType<typeof createInMemorySocialConnectionStore>;
  userStore?: UserStore;
} = {}) => {
  const app = express();
  app.use(express.json());
  const router = express.Router();

  registerSocialConnectionRoutes(
    router,
    (_request, response, next) => {
      response.locals.authUser = { id: userId, provider: 'mock' };
      next();
    },
    { store, connectClient, userStore }
  );

  app.use(router);

  return { app, store, connectClient, userStore };
};

describe('social connection routes', () => {
  it('is registered by createApp', async () => {
    const response = await request(createApp())
      .get('/social-connections')
      .set('x-postdee-user-id', 'seller-app')
      .expect(200);

    expect(response.body.connections).toEqual(
      expect.arrayContaining([{ platform: 'TIKTOK', connected: false }])
    );
  });

  it('lists safe connection statuses for the authenticated user', async () => {
    const { app, store } = createTestApp();

    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-private',
      displayName: '@seller_one',
      externalAccountId: 'external-tiktok'
    });

    const response = await request(app).get('/social-connections').expect(200);

    expect(response.body.status).toBe('ok');
    expect(
      response.body.connections.find(
        (connection: { platform: string }) => connection.platform === 'TIKTOK'
      )
    ).toEqual({
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one',
      externalAccountId: 'external-tiktok',
      connectedAt: '2026-06-26T09:00:00.000Z'
    });
    expect(JSON.stringify(response.body)).not.toContain('acct-tiktok-private');
  });

  it('creates a PostPeer profile and returns the OAuth connect URL', async () => {
    const { app, store, connectClient, userStore } = createTestApp();

    const response = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .expect(200);

    expect(connectClient.createProfile).toHaveBeenCalledTimes(1);
    expect(connectClient.createProfile).toHaveBeenCalledWith({
      userId: 'seller-social'
    });
    await expect(userStore.exists('seller-social')).resolves.toBe(true);
    await expect(store.getProfileId('seller-social')).resolves.toBe('profile-1');
    expect(connectClient.createConnectUrl).toHaveBeenCalledWith({
      platform: 'TIKTOK',
      profileId: 'profile-1'
    });
    expect(response.body).toEqual({
      status: 'ok',
      connectUrl: 'https://postpeer.test/connect/tiktok'
    });
  });

  it('persists a fresh authenticated user before saving their PostPeer profile', async () => {
    const events: string[] = [];
    const userStore = createUserStore();
    const originalEnsure = userStore.ensure;
    userStore.ensure = vi.fn(async (authUser) => {
      events.push('ensure-user');
      return originalEnsure(authUser);
    });
    const store = createInMemorySocialConnectionStore();
    const originalSetProfileId = store.setProfileId;
    store.setProfileId = vi.fn(async (input) => {
      events.push('save-profile');
      expect(await userStore.exists(input.userId)).toBe(true);
      await originalSetProfileId(input);
    });
    const connectClient = createFakeConnectClient({
      createProfile: vi.fn(async () => {
        events.push('create-profile');
        return { profileId: 'profile-fresh-user' };
      })
    });
    const { app } = createTestApp({ store, connectClient, userStore });

    await request(app).post('/social-connections/TIKTOK/connect').expect(200);

    expect(events).toEqual(['ensure-user', 'create-profile', 'save-profile']);
  });

  it('coalesces concurrent connect requests into one external profile creation', async () => {
    const createProfile = vi.fn(async () => {
      await new Promise((resolve) => setTimeout(resolve, 10));
      return { profileId: 'profile-concurrent' };
    });
    const { app, store } = createTestApp({
      connectClient: createFakeConnectClient({ createProfile })
    });

    await Promise.all([
      request(app).post('/social-connections/TIKTOK/connect').expect(200),
      request(app).post('/social-connections/YOUTUBE_SHORTS/connect').expect(200)
    ]);

    expect(createProfile).toHaveBeenCalledTimes(1);
    await expect(store.getProfileId('seller-social')).resolves.toBe('profile-concurrent');
  });

  it('reuses an existing PostPeer profile instead of creating a new one', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });
    await store.setProfileId({ userId: 'seller-social', profileId: 'existing-profile' });
    const { app, connectClient } = createTestApp({ store });

    await request(app).post('/social-connections/TIKTOK/connect').expect(200);

    expect(connectClient.createProfile).not.toHaveBeenCalled();
    expect(connectClient.createConnectUrl).toHaveBeenCalledWith({
      platform: 'TIKTOK',
      profileId: 'existing-profile'
    });
  });

  it('maps PostPeer connect-client failures to API errors', async () => {
    const unavailableApp = createTestApp({
      connectClient: createFakeConnectClient({
        createProfile: async () => {
          throw new PostPeerConnectUnavailableError();
        }
      })
    }).app;
    const providerFailureApp = createTestApp({
      connectClient: createFakeConnectClient({
        createConnectUrl: async () => {
          throw new PostPeerConnectProviderError(500);
        }
      })
    }).app;

    const unavailableResponse = await request(unavailableApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(503);
    const providerFailureResponse = await request(providerFailureApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(502);

    expect(unavailableResponse.body).toEqual({
      status: 'error',
      code: 'SOCIAL_CONNECTION_UNAVAILABLE',
      message: 'Social account linking is not available. Please try again later.'
    });
    expect(providerFailureResponse.body).toEqual({
      status: 'error',
      code: 'SOCIAL_CONNECTION_FAILED',
      message: 'Social account linking failed. Please try again later.'
    });
    expect(JSON.stringify(unavailableResponse.body)).not.toContain('PostPeer');
    expect(JSON.stringify(providerFailureResponse.body)).not.toContain('PostPeer');
  });

  it('rejects unsupported platforms before contacting PostPeer', async () => {
    const { app, connectClient } = createTestApp();

    const response = await request(app)
      .post('/social-connections/LAZADA_VIDEO/connect')
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'Unsupported social connection platform'
    });
    expect(connectClient.createProfile).not.toHaveBeenCalled();
    expect(connectClient.createConnectUrl).not.toHaveBeenCalled();
  });

  it('refreshes connections by polling PostPeer integrations', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });
    await store.setProfileId({ userId: 'seller-social', profileId: 'profile-1' });
    const connectClient = createFakeConnectClient({
      listIntegrations: vi.fn(async () => [
        {
          id: 'acct-tiktok-1',
          platform: 'TIKTOK',
          platformUserId: 'tt-1',
          displayName: '@seller_one'
        }
      ])
    });
    const { app } = createTestApp({ store, connectClient });

    const response = await request(app)
      .post('/social-connections/refresh')
      .expect(200);

    expect(connectClient.listIntegrations).toHaveBeenCalledWith({
      profileId: 'profile-1'
    });
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBe('acct-tiktok-1');
    expect(
      response.body.connections.find(
        (connection: { platform: string }) => connection.platform === 'TIKTOK'
      )
    ).toMatchObject({
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one'
    });
  });

  it('removes stale connections that are missing from PostPeer integrations', async () => {
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });
    await store.setProfileId({ userId: 'seller-social', profileId: 'profile-1' });
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });
    await store.upsert({
      userId: 'seller-social',
      platform: 'YOUTUBE_SHORTS',
      postPeerAccountId: 'acct-youtube-stale'
    });
    const connectClient = createFakeConnectClient({
      listIntegrations: vi.fn(async () => [
        {
          id: 'acct-tiktok-1',
          platform: 'TIKTOK'
        }
      ])
    });
    const { app } = createTestApp({ store, connectClient });

    const response = await request(app)
      .post('/social-connections/refresh')
      .expect(200);

    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBe('acct-tiktok-1');
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'YOUTUBE_SHORTS' })
    ).resolves.toBeUndefined();
    expect(
      response.body.connections.find(
        (connection: { platform: string }) => connection.platform === 'YOUTUBE_SHORTS'
      )
    ).toMatchObject({
      platform: 'YOUTUBE_SHORTS',
      connected: false
    });
  });

  it('skips polling when the user has no PostPeer profile yet', async () => {
    const { app, connectClient } = createTestApp();

    const response = await request(app)
      .post('/social-connections/refresh')
      .expect(200);

    expect(connectClient.listIntegrations).not.toHaveBeenCalled();
    expect(response.body.status).toBe('ok');
  });

  it('disconnects PostPeer before removing the authenticated user local connection', async () => {
    const events: string[] = [];
    const store = createInMemorySocialConnectionStore({
      now: () => '2026-06-26T09:00:00.000Z'
    });
    const originalDisconnect = store.disconnect;
    store.disconnect = vi.fn(async (input) => {
      events.push('local');
      return originalDisconnect(input);
    });
    const disconnectIntegration = vi.fn(async () => {
      events.push('provider');
    });
    const { app } = createTestApp({
      store,
      connectClient: createFakeConnectClient({ disconnectIntegration })
    });
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });

    await request(app).delete('/social-connections/TIKTOK').expect(200);

    expect(disconnectIntegration).toHaveBeenCalledWith({
      integrationId: 'acct-tiktok-1'
    });
    expect(events).toEqual(['provider', 'local']);
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBeUndefined();
  });

  it('keeps the local connection when PostPeer disconnect fails', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });
    const { app } = createTestApp({
      store,
      connectClient: createFakeConnectClient({
        disconnectIntegration: vi.fn(async () => {
          throw new PostPeerConnectProviderError(503);
        })
      })
    });

    const response = await request(app)
      .delete('/social-connections/TIKTOK')
      .expect(502);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'SOCIAL_CONNECTION_FAILED'
    });
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBe('acct-tiktok-1');
  });

  it('keeps the local connection when provider cleanup is unavailable', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });
    const { app } = createTestApp({
      store,
      connectClient: createFakeConnectClient({
        supportsIntegrationCleanup: false,
        disconnectIntegration: undefined
      })
    });

    const response = await request(app)
      .delete('/social-connections/TIKTOK')
      .expect(503);

    expect(response.body).toMatchObject({
      status: 'error',
      code: 'SOCIAL_CONNECTION_UNAVAILABLE'
    });
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBe('acct-tiktok-1');
  });

  it('treats an already-disconnected local platform as an idempotent success', async () => {
    const disconnectIntegration = vi.fn(async () => undefined);
    const { app, store } = createTestApp({
      connectClient: createFakeConnectClient({ disconnectIntegration })
    });

    await request(app).delete('/social-connections/TIKTOK').expect(200);

    expect(disconnectIntegration).not.toHaveBeenCalled();
    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBeUndefined();
  });

  it('never disconnects another user connection on the same platform', async () => {
    const store = createInMemorySocialConnectionStore();
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-owner'
    });
    await store.upsert({
      userId: 'seller-other',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-other'
    });
    const disconnectIntegration = vi.fn(async () => undefined);
    const { app } = createTestApp({
      store,
      connectClient: createFakeConnectClient({ disconnectIntegration })
    });

    await request(app).delete('/social-connections/TIKTOK').expect(200);

    expect(disconnectIntegration).toHaveBeenCalledWith({
      integrationId: 'acct-owner'
    });
    await expect(
      store.getAccountId({ userId: 'seller-other', platform: 'TIKTOK' })
    ).resolves.toBe('acct-other');
  });
});
