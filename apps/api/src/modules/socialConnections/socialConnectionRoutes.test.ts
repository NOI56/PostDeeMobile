import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
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
  createProfile: vi.fn(async () => ({ profileId: 'profile-1' })),
  createConnectUrl: vi.fn(async () => ({
    connectUrl: 'https://postpeer.test/connect/tiktok'
  })),
  listIntegrations: vi.fn(async () => []),
  ...overrides
});

const createTestApp = ({
  userId = 'seller-social',
  connectClient = createFakeConnectClient(),
  store = createInMemorySocialConnectionStore({
    now: () => '2026-06-26T09:00:00.000Z'
  })
}: {
  userId?: string;
  connectClient?: PostPeerConnectClient;
  store?: ReturnType<typeof createInMemorySocialConnectionStore>;
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
    { store, connectClient }
  );

  app.use(router);

  return { app, store, connectClient };
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
    const { app, store, connectClient } = createTestApp();

    const response = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .expect(200);

    expect(connectClient.createProfile).toHaveBeenCalledTimes(1);
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

    await request(unavailableApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(503);
    await request(providerFailureApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(502);
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

  it('skips polling when the user has no PostPeer profile yet', async () => {
    const { app, connectClient } = createTestApp();

    const response = await request(app)
      .post('/social-connections/refresh')
      .expect(200);

    expect(connectClient.listIntegrations).not.toHaveBeenCalled();
    expect(response.body.status).toBe('ok');
  });

  it('disconnects a linked platform for the authenticated user', async () => {
    const { app, store } = createTestApp();
    await store.upsert({
      userId: 'seller-social',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-tiktok-1'
    });

    await request(app).delete('/social-connections/TIKTOK').expect(200);

    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBeUndefined();
  });
});
