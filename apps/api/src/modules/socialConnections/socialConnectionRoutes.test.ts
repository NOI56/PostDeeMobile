import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createApp } from '../../app.js';
import { registerSocialConnectionRoutes } from './socialConnectionRoutes.js';
import {
  createInMemorySocialConnectionStore,
  type SocialConnectionPlatform
} from './socialConnectionStore.js';
import {
  PostPeerConnectProviderError,
  PostPeerConnectUnavailableError,
  type PostPeerConnectClient
} from './postPeerConnectClient.js';

const createTestApp = ({
  userId = 'seller-social',
  connectClient,
  callbackSecret,
  callbackUrl = 'https://api.postdee.test/social-connections/postpeer/callback',
  stateManager,
  store = createInMemorySocialConnectionStore({
    now: () => '2026-06-26T09:00:00.000Z'
  })
}: {
  userId?: string;
  connectClient?: PostPeerConnectClient;
  callbackSecret?: string;
  callbackUrl?: string;
  stateManager?: {
    create: (input: {
      userId: string;
      platform: SocialConnectionPlatform;
    }) => { token: string; expiresAt: string };
    verify: (token: string) => {
      userId: string;
      platform: SocialConnectionPlatform;
      expiresAt: string;
    };
  };
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
    {
      store,
      connectClient:
        connectClient ??
        ({
          createConnectLink: vi.fn(async () => ({
            connectUrl: 'https://postpeer.test/connect/tiktok'
          }))
        } satisfies PostPeerConnectClient),
      callbackSecret,
      callbackUrl,
      stateManager:
        stateManager ??
        ({
          create: vi.fn(() => ({
            token: 'signed-state',
            expiresAt: '2026-06-26T09:10:00.000Z'
          })),
          verify: vi.fn(() => ({
            userId,
            platform: 'TIKTOK',
            expiresAt: '2026-06-26T09:10:00.000Z'
          }))
        })
    }
  );

  app.use(router);

  return { app, store };
};

describe('social connection routes', () => {
  it('is registered by createApp', async () => {
    const response = await request(createApp())
      .get('/social-connections')
      .set('x-postdee-user-id', 'seller-app')
      .expect(200);

    expect(response.body.connections).toEqual(
      expect.arrayContaining([
        {
          platform: 'TIKTOK',
          connected: false
        }
      ])
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
    expect(response.body.connections.find(
      (connection: { platform: string }) => connection.platform === 'TIKTOK'
    )).toEqual({
      platform: 'TIKTOK',
      connected: true,
      displayName: '@seller_one',
      externalAccountId: 'external-tiktok',
      connectedAt: '2026-06-26T09:00:00.000Z'
    });
    expect(response.body.connections.find(
      (connection: { platform: string }) => connection.platform === 'YOUTUBE_SHORTS'
    )).toEqual({
      platform: 'YOUTUBE_SHORTS',
      connected: false
    });
    expect(JSON.stringify(response.body)).not.toContain('acct-tiktok-private');
  });

  it('creates a PostPeer connect link for a supported platform', async () => {
    const connectClient: PostPeerConnectClient = {
      createConnectLink: vi.fn(async () => ({
        connectUrl: 'https://postpeer.test/connect/tiktok'
      }))
    };
    const stateManager = {
      create: vi.fn(() => ({
        token: 'signed-state',
        expiresAt: '2026-06-26T09:10:00.000Z'
      })),
      verify: vi.fn()
    };
    const { app } = createTestApp({ connectClient, stateManager });

    const response = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .expect(200);

    expect(stateManager.create).toHaveBeenCalledWith({
      userId: 'seller-social',
      platform: 'TIKTOK'
    });
    expect(connectClient.createConnectLink).toHaveBeenCalledWith({
      platform: 'TIKTOK',
      state: 'signed-state',
      callbackUrl: 'https://api.postdee.test/social-connections/postpeer/callback'
    });
    expect(response.body).toEqual({
      status: 'ok',
      connectUrl: 'https://postpeer.test/connect/tiktok',
      expiresAt: '2026-06-26T09:10:00.000Z'
    });
  });

  it('returns a clear error when connect-link configuration is missing', async () => {
    const { app } = createTestApp({
      callbackUrl: ''
    });

    const response = await request(app)
      .post('/social-connections/TIKTOK/connect')
      .expect(503);

    expect(response.body).toEqual({
      status: 'error',
      message: 'PostPeer account linking is not configured yet'
    });
  });

  it('maps PostPeer connect-client failures to API errors', async () => {
    const unavailableApp = createTestApp({
      connectClient: {
        createConnectLink: async () => {
          throw new PostPeerConnectUnavailableError();
        }
      }
    }).app;
    const providerFailureApp = createTestApp({
      connectClient: {
        createConnectLink: async () => {
          throw new PostPeerConnectProviderError(500);
        }
      }
    }).app;

    await request(unavailableApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(503);
    await request(providerFailureApp)
      .post('/social-connections/TIKTOK/connect')
      .expect(502);
  });

  it('rejects unsupported platforms before creating a connect link', async () => {
    const connectClient: PostPeerConnectClient = {
      createConnectLink: vi.fn()
    };
    const { app } = createTestApp({ connectClient });

    const response = await request(app)
      .post('/social-connections/LAZADA_VIDEO/connect')
      .expect(400);

    expect(response.body).toEqual({
      status: 'error',
      message: 'Unsupported social connection platform'
    });
    expect(connectClient.createConnectLink).not.toHaveBeenCalled();
  });

  it('stores a connection from a PostPeer POST callback', async () => {
    const { app, store } = createTestApp({
      callbackSecret: 'callback-secret'
    });

    await request(app)
      .post('/social-connections/postpeer/callback')
      .set('x-postpeer-callback-secret', 'callback-secret')
      .send({
        state: 'signed-state',
        accountId: 'acct-tiktok-1',
        displayName: '@seller_one',
        externalAccountId: 'external-tiktok'
      })
      .expect(200);

    await expect(
      store.getAccountId({ userId: 'seller-social', platform: 'TIKTOK' })
    ).resolves.toBe('acct-tiktok-1');
  });

  it('stores a connection from a PostPeer GET callback', async () => {
    const { app, store } = createTestApp({
      userId: 'seller-query'
    });

    await request(app)
      .get('/social-connections/postpeer/callback')
      .query({
        state: 'signed-state',
        postPeerAccountId: 'acct-query-tiktok'
      })
      .expect(200);

    await expect(
      store.getAccountId({ userId: 'seller-query', platform: 'TIKTOK' })
    ).resolves.toBe('acct-query-tiktok');
  });

  it('rejects callbacks with an invalid callback secret', async () => {
    const { app } = createTestApp({
      callbackSecret: 'callback-secret'
    });

    await request(app)
      .post('/social-connections/postpeer/callback')
      .set('x-postpeer-callback-secret', 'wrong-secret')
      .send({
        state: 'signed-state',
        accountId: 'acct-tiktok-1'
      })
      .expect(401);
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
