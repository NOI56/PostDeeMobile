import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { createOwnerOperationRunner } from '../account/prismaOwnerOperationCoordinator.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import { createInMemorySocialConnectionStore } from './socialConnectionStore.js';
import type { PostPeerIntegration } from './postPeerConnectClient.js';
import { registerPublishingReadinessRoutes } from './publishingReadinessRoutes.js';

const makeApp = ({
  authenticated = true,
  store = createInMemorySocialConnectionStore(),
  listIntegrations = vi.fn(async (_input: unknown): Promise<PostPeerIntegration[]> => []),
  assertOwnerActive = vi.fn(async (_owner: string) => undefined),
  lifetime = undefined as RunWithActiveOwner | undefined,
  configured = true
} = {}) => {
  const app = express();
  const entered = vi.fn();
  const createProfile = vi.fn();
  const setProfile = vi.spyOn(store, 'setProfileId');
  registerPublishingReadinessRoutes(app, (_request, response, next) => {
    if (authenticated) response.locals.authUser = { id: 'owner', provider: 'mock' };
    next();
  }, {
    store, client: { createProfile, createConnectUrl: vi.fn(), listIntegrations, publishingReadinessConfigured: configured }, assertOwnerActive,
    runWithOwnerLifetime: lifetime ?? (async (_owner, operation) => { entered(); return operation(); }),
    now: () => new Date('2026-10-15T10:00:00.000Z')
  });
  return { app, store, listIntegrations, assertOwnerActive, entered, createProfile, setProfile };
};
const setup = async (store: ReturnType<typeof createInMemorySocialConnectionStore>, platform = 'INSTAGRAM_REELS' as const) => {
  await store.setProfileId({ userId: 'owner', profileId: 'owned-profile' });
  return store.upsert({ userId: 'owner', platform, postPeerAccountId: 'owned-integration', externalAccountId: 'owned-platform-account' });
};

describe('read-only publishing readiness', () => {
  it('requires authentication before provider or lifetime work', async () => {
    const { app, listIntegrations, entered } = makeApp({ authenticated: false });
    await request(app).get('/social-connections/publishing-readiness').expect(401);
    expect(listIntegrations).not.toHaveBeenCalled();
    expect(entered).not.toHaveBeenCalled();
  });
  it('returns disconnected statuses without creating or finding a remote profile', async () => {
    const { app, listIntegrations, createProfile, setProfile } = makeApp();
    const response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections).toHaveLength(4);
    expect(response.body.connections.every((value: { state: string }) => value.state === 'not_connected')).toBe(true);
    expect(listIntegrations).not.toHaveBeenCalled();
    expect(createProfile).not.toHaveBeenCalled();
    expect(setProfile).not.toHaveBeenCalled();
  });
  it.each([
    [{ canPublish: true }, 'ready', undefined],
    [{}, 'connected', 'PUBLISH_CAPABILITY_UNCONFIRMED'],
    [{ canPublish: false }, 'permission_missing', 'PUBLISH_PERMISSION_MISSING'],
    [{ canPublish: true, reconnectRequired: true }, 'reconnect_required', 'PROVIDER_RECONNECT_REQUIRED'],
    [{ canPublish: false, reconnectRequired: true }, 'reconnect_required', 'PROVIDER_RECONNECT_REQUIRED']
  ] as const)('uses only explicit provider evidence %o', async (flags, state, reasonCode) => {
    const store = createInMemorySocialConnectionStore();
    const connection = await setup(store);
    const listIntegrations = vi.fn(async () => [{ id: 'owned-integration', platform: 'INSTAGRAM_REELS' as const, ...flags }]);
    const { app } = makeApp({ store, listIntegrations });
    const response = await request(app).get('/social-connections/publishing-readiness?userId=foreign&profileId=foreign').expect(200);
    expect(listIntegrations).toHaveBeenCalledExactlyOnceWith({ profileId: 'owned-profile', publishingReadiness: true });
    expect(response.body).toMatchObject({ status: 'ok', checkedAt: '2026-10-15T10:00:00.000Z' });
    const result = response.body.connections.find((value: { platform: string }) => value.platform === 'INSTAGRAM_REELS');
    expect(result).toMatchObject({ platform: 'INSTAGRAM_REELS', connectionId: connection.id, state });
    expect(result.connectionRevision).toMatch(/^[a-f0-9]{64}$/);
    expect(result.reasonCode).toBe(reasonCode);
    expect(JSON.stringify(response.body)).not.toMatch(/owned-profile|owned-integration|owned-platform-account|tokenStatus|canPublish/);
    expect(response.headers['cache-control']).toBe('private, no-store');
  });
  it('does not choose another provider integration from the same profile', async () => {
    const store = createInMemorySocialConnectionStore();
    await setup(store);
    const { app } = makeApp({ store, listIntegrations: vi.fn(async () => [{ id: 'other-account', platform: 'INSTAGRAM_REELS', canPublish: true }]) });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections.find((value: { platform: string }) => value.platform === 'INSTAGRAM_REELS')).toMatchObject({ state: 'reconnect_required', reasonCode: 'PROVIDER_INTEGRATION_MISSING' });
  });
  it('rejects replaced accounts during provider lookup even when local id is retained', async () => {
    const store = createInMemorySocialConnectionStore();
    await setup(store);
    const { app } = makeApp({ store, listIntegrations: vi.fn(async () => {
      await store.upsert({ userId: 'owner', platform: 'INSTAGRAM_REELS', postPeerAccountId: 'replacement' });
      return [{ id: 'owned-integration', platform: 'INSTAGRAM_REELS', canPublish: true }];
    }) });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(409);
    expect(response.body.code).toBe('SOCIAL_CONNECTIONS_CHANGED');
    expect(response.body).not.toHaveProperty('connections');
  });
  it('blocks deletion before any provider access', async () => {
    const assertOwnerActive = vi.fn(async () => { throw new ManagedUploadServiceError(409, 'ACCOUNT_DELETION_IN_PROGRESS', 'Account deletion is in progress.'); });
    const { app, listIntegrations } = makeApp({ assertOwnerActive });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(409);
    expect(response.body.code).toBe('ACCOUNT_DELETION_IN_PROGRESS');
    expect(listIntegrations).not.toHaveBeenCalled();
  });
  it('rechecks owner activity after reading the provider', async () => {
    const store = createInMemorySocialConnectionStore();
    await setup(store);
    const assertOwnerActive = vi.fn(async () => undefined).mockImplementationOnce(async () => undefined)
      .mockImplementationOnce(async () => { throw new ManagedUploadServiceError(409, 'ACCOUNT_DELETION_IN_PROGRESS', 'Account deletion is in progress.'); });
    const { app } = makeApp({ store, assertOwnerActive });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(409);
    expect(response.body.code).toBe('ACCOUNT_DELETION_IN_PROGRESS');
    expect(response.body).not.toHaveProperty('connections');
  });
  it('does not read a foreign owner profile or integration', async () => {
    const { app, store, listIntegrations } = makeApp();
    await store.setProfileId({ userId: 'foreign', profileId: 'foreign-profile' });
    await store.upsert({ userId: 'foreign', platform: 'INSTAGRAM_REELS', postPeerAccountId: 'foreign-integration' });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections.every((value: { state: string }) => value.state === 'not_connected')).toBe(true);
    expect(listIntegrations).not.toHaveBeenCalled();
  });
  it('asks to reconnect a stored connection without a profile rather than creating one', async () => {
    const { app, store, listIntegrations, createProfile } = makeApp();
    await store.upsert({ userId: 'owner', platform: 'INSTAGRAM_REELS', postPeerAccountId: 'owned-integration' });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections.find((value: { platform: string }) => value.platform === 'INSTAGRAM_REELS')).toMatchObject({ state: 'reconnect_required', reasonCode: 'PROVIDER_PROFILE_MISSING' });
    expect(listIntegrations).not.toHaveBeenCalled();
    expect(createProfile).not.toHaveBeenCalled();
  });
  it('does not trust duplicate integrations or a mismatched external identity', async () => {
    const store = createInMemorySocialConnectionStore();
    await setup(store);
    const entry: PostPeerIntegration = { id: 'owned-integration', platform: 'INSTAGRAM_REELS', canPublish: true };
    const listIntegrations = vi.fn(async () => [entry, entry]);
    const { app } = makeApp({ store, listIntegrations });
    let response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections.find((value: { platform: string }) => value.platform === 'INSTAGRAM_REELS').state).toBe('reconnect_required');
    listIntegrations.mockResolvedValue([{ ...entry, platformUserId: 'other-creator' }]);
    response = await request(app).get('/social-connections/publishing-readiness').expect(200);
    expect(response.body.connections.find((value: { platform: string }) => value.platform === 'INSTAGRAM_REELS').state).toBe('reconnect_required');
  });
  it('releases the actual owner lifetime ticket after a failed read and sanitizes errors', async () => {
    const release = vi.fn(async () => undefined);
    const lifetime = createOwnerOperationRunner({ admit: async () => 'read-ticket', release });
    const store = createInMemorySocialConnectionStore();
    await setup(store);
    const { app } = makeApp({ store, lifetime, listIntegrations: vi.fn(async () => { throw new Error('secret-token raw-provider-response'); }) });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(503);
    expect(response.body.code).toBe('PUBLISHING_READINESS_UNAVAILABLE');
    expect(JSON.stringify(response.body)).not.toMatch(/secret-token|raw-provider/);
    await vi.waitFor(() => expect(release).toHaveBeenCalledExactlyOnceWith('owner', 'read-ticket'));
  });
  it('returns unavailable when provider credentials are absent', async () => {
    const { app, listIntegrations } = makeApp({ configured: false });
    const response = await request(app).get('/social-connections/publishing-readiness').expect(503);
    expect(response.body.code).toBe('PUBLISHING_READINESS_UNAVAILABLE');
    expect(listIntegrations).not.toHaveBeenCalled();
  });
});
