import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { createOwnerOperationRunner } from '../account/prismaOwnerOperationCoordinator.js';
import { TikTokPublishingError } from './postPeerTikTokClient.js';
import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';
import { registerTikTokPublishingOptionsRoutes } from './tikTokPublishingOptionsRoutes.js';

const info = {
  creatorAvatarUrl: 'https://cdn.tiktok.test/avatar.jpg', creatorUsername: 'seller', creatorNickname: 'Seller',
  privacyLevelOptions: ['SELF_ONLY' as const], commentDisabled: false, duetDisabled: true,
  stitchDisabled: false, maxVideoPostDurationSec: 3600
};
const testApp = ({
  authenticated = true,
  store = createInMemorySocialConnectionStore(),
  getCreatorInfo = vi.fn(async () => info),
  assertOwnerActive = vi.fn(async (_owner: string) => undefined),
  lifetime = undefined as RunWithActiveOwner | undefined
} = {}) => {
  const app = express();
  const router = express.Router();
  const entered = vi.fn();
  const runWithOwnerLifetime: RunWithActiveOwner = async (owner, operation) => {
    entered();
    expect(owner).toBe('owner');
    return operation();
  };
  registerTikTokPublishingOptionsRoutes(router, (_request, response, next) => {
    if (authenticated) response.locals.authUser = { id: 'owner', provider: 'mock' };
    next();
  }, { store, client: { getCreatorInfo }, assertOwnerActive, runWithOwnerLifetime: lifetime ?? runWithOwnerLifetime });
  app.use(router);
  return { app, store, getCreatorInfo, assertOwnerActive, runWithOwnerLifetime: entered };
};
const connect = (store: ReturnType<typeof createInMemorySocialConnectionStore>, userId = 'owner', accountId = 'owned-account') =>
  store.upsert({ userId, platform: 'TIKTOK', postPeerAccountId: accountId });

describe('TikTok publishing options owner boundary', () => {
  it.each([
    ['TIKTOK_CREATOR_INFO_UNAVAILABLE', 503], ['TIKTOK_CREATOR_INFO_INVALID', 502],
    ['TIKTOK_PUBLISHING_UNAVAILABLE', 503]
  ] as const)('releases a read-only failure ticket for %s', async (code, statusCode) => {
    const release = vi.fn(async () => undefined);
    const lifetime = createOwnerOperationRunner({ admit: async () => 'read-only-ticket', release });
    const { app, store } = testApp({
      lifetime,
      getCreatorInfo: vi.fn(async () => { throw new TikTokPublishingError(code, statusCode, 'Options could not be checked.'); })
    });
    await connect(store);
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(statusCode);
    expect(response.body.code).toBe(code);
    await vi.waitFor(() => expect(release).toHaveBeenCalledExactlyOnceWith('owner', 'read-only-ticket'));
  });
  it('does not accept a query account or owner override', async () => {
    const { app, store, getCreatorInfo, runWithOwnerLifetime } = testApp();
    const connection = await connect(store);
    const response = await request(app)
      .get('/social-connections/TIKTOK/publishing-options?accountId=foreign&userId=other').expect(200);
    expect(response.body).toMatchObject({ status: 'ok', connectionId: connection.id, creatorInfo: info });
    const status = (await store.listForUser('owner')).find(({ platform }) => platform === 'TIKTOK');
    expect(response.body.creatorInfoRevision).toBe(status?.connectionRevision);
    expect(status?.connectionId).toBe(response.body.connectionId);
    expect(getCreatorInfo).toHaveBeenCalledExactlyOnceWith({ accountId: 'owned-account' });
    expect(runWithOwnerLifetime).toHaveBeenCalledOnce();
    expect(JSON.stringify(response.body)).not.toMatch(/owned-account|postPeerAccountId/);
    expect(response.headers['cache-control']).toBe('private, no-store');
  });

  it('requires authentication before owner/provider work', async () => {
    const { app, getCreatorInfo, runWithOwnerLifetime } = testApp({ authenticated: false });
    await request(app).get('/social-connections/TIKTOK/publishing-options').expect(401);
    expect(getCreatorInfo).not.toHaveBeenCalled();
    expect(runWithOwnerLifetime).not.toHaveBeenCalled();
  });

  it('does not use another owner or configured default account', async () => {
    const { app, store, getCreatorInfo } = testApp();
    await connect(store, 'other-owner', 'foreign-account');
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(409);
    expect(response.body.code).toBe('TIKTOK_CONNECTION_UNAVAILABLE');
    expect(getCreatorInfo).not.toHaveBeenCalled();
  });

  it('blocks an inactive owner before reading provider data', async () => {
    const assertOwnerActive = vi.fn(async () => { throw new ManagedUploadServiceError(409, 'ACCOUNT_DELETION_IN_PROGRESS', 'Account deletion is in progress.'); });
    const { app, store, getCreatorInfo } = testApp({ assertOwnerActive });
    await connect(store);
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(409);
    expect(response.body.code).toBe('ACCOUNT_DELETION_IN_PROGRESS');
    expect(getCreatorInfo).not.toHaveBeenCalled();
  });

  it('rejects a reconnect during creator-info loading even if local id is unchanged', async () => {
    const store = createInMemorySocialConnectionStore();
    const original = await connect(store);
    const getCreatorInfo = vi.fn(async () => {
      const updated = await connect(store, 'owner', 'new-provider-account');
      expect(updated.id).toBe(original.id);
      return info;
    });
    const { app } = testApp({ store, getCreatorInfo });
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(409);
    expect(response.body.code).toBe('TIKTOK_CONNECTION_CHANGED');
    expect(response.body).not.toHaveProperty('creatorInfo');
  });

  it('checks owner activity again before returning creator info', async () => {
    const assertOwnerActive = vi.fn(async () => undefined)
      .mockImplementationOnce(async () => undefined)
      .mockImplementationOnce(async () => { throw new ManagedUploadServiceError(409, 'ACCOUNT_DELETION_IN_PROGRESS', 'Account deletion is in progress.'); });
    const { app, store } = testApp({ assertOwnerActive });
    await connect(store);
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(409);
    expect(response.body).not.toHaveProperty('creatorInfo');
    expect(assertOwnerActive).toHaveBeenCalledTimes(2);
  });

  it('rejects creator identity metadata drift even when optional target matching permits it', async () => {
    const store = createInMemorySocialConnectionStore();
    await connect(store);
    const getCreatorInfo = vi.fn(async () => {
      await store.upsert({ userId: 'owner', platform: 'TIKTOK', postPeerAccountId: 'owned-account', externalAccountId: 'newly-resolved-creator' });
      return info;
    });
    const { app } = testApp({ store, getCreatorInfo });
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(409);
    expect(response.body.code).toBe('TIKTOK_CONNECTION_CHANGED');
    expect(response.body).not.toHaveProperty('creatorInfo');
  });

  it('sanitizes unexpected provider failures', async () => {
    const getCreatorInfo = vi.fn(async () => { throw new Error('private-account secret-token raw-payload'); });
    const { app, store } = testApp({ getCreatorInfo });
    await connect(store);
    const response = await request(app).get('/social-connections/TIKTOK/publishing-options').expect(503);
    expect(response.body.code).toBe('TIKTOK_CREATOR_INFO_UNAVAILABLE');
    expect(JSON.stringify(response.body)).not.toMatch(/private-account|secret-token|raw-payload/);
  });
});
