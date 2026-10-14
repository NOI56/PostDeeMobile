import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { registerAccountRoutes, type AccountRouteDependencies } from './accountRoutes.js';
import { OwnerOperationBusyError } from './ownerOperationQueue.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createPostStore } from '../posts/postStore.js';
import { createUserStore } from '../users/userStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createInMemorySocialConnectionStore } from '../socialConnections/socialConnectionStore.js';
import { createTemplateStore } from '../templates/templateStore.js';
import { createInMemoryAnalyticsStore } from '../analytics/analyticsStore.js';
import { createInMemoryRealClipCaptionUsageStore } from '../captions/captionUsageStore.js';
import { createInMemoryAiEditUsageStore } from '../aiEdits/aiEditUsageStore.js';
import { createInMemoryDeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';

const fixture = () => {
  const owners = createInMemoryUploadSessionStore();
  const social = createInMemorySocialConnectionStore();
  const deleteMedia = vi.fn(async () => undefined);
  const deleteIdentity = vi.fn(async () => undefined);
  const deleteUser = vi.fn(async () => undefined);
  const listIntegrations = vi.fn(async (_input: { profileId: string }) => []);
  const dependencies: AccountRouteDependencies = {
    postStore: createPostStore(), publishQueue: createInMemoryPublishQueue(),
    userStore: { ...createUserStore(), deleteAllForUser: deleteUser },
    subscriptionStore: createSubscriptionStore(),
    templateStore: createTemplateStore(), analyticsStore: createInMemoryAnalyticsStore(),
    realClipCaptionUsageStore: createInMemoryRealClipCaptionUsageStore(),
    aiEditUsageStore: createInMemoryAiEditUsageStore(), deviceTokenStore: createInMemoryDeviceTokenStore(),
    platformPublishStore: createInMemoryPlatformPublishStore(),
    videoStorage: { supportsOwnerCleanup: true, deleteAllVideosForOwner: deleteMedia,
      createUpload: vi.fn(), createDownloadAccess: vi.fn(), deleteVideo: vi.fn() },
    socialConnectionStore: social,
    postPeerConnectClient: { supportsIntegrationCleanup: true, listIntegrations, disconnectIntegration: vi.fn(),
      createProfile: vi.fn(async () => ({ profileId: 'profile-a' })),
      createConnectUrl: vi.fn(async () => ({ connectUrl: 'https://provider.test/connect' })) },
    accountIdentityDeleter: { deleteIdentity }, ownerLifecycleStore: owners
  };
  const app = express();
  const router = express.Router();
  registerAccountRoutes(router, (_request, response, next) => {
    response.locals.authUser = { id: 'owner-a', provider: 'firebase', authenticatedAtSeconds: Math.floor(Date.now() / 1000) };
    next();
  }, dependencies);
  app.use(router);
  return { app, owners, social, deleteMedia, deleteIdentity, deleteUser, listIntegrations };
};

describe('account deletion shared drain boundary', () => {
  it('retains consent/tombstone and all data when shared drain fails', async () => {
    const { app, owners, deleteMedia, deleteIdentity, deleteUser, listIntegrations } = fixture();
    const acquire = vi.fn(async () => { throw new OwnerOperationBusyError(); });
    Object.assign(owners, { acquireOwnerDeletion: acquire });
    await request(app).delete('/account').expect(503).expect(({ body }) => {
      expect(body.code).toBe('ACCOUNT_WRITE_DRAIN_FAILED');
    });
    expect(await owners.getOwnerDeletionAuthorization('owner-a')).toEqual(expect.any(String));
    await expect(owners.assertOwnerActive('owner-a')).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(acquire).toHaveBeenCalledOnce();
    expect(deleteMedia).not.toHaveBeenCalled();
    expect(deleteIdentity).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
    expect(listIntegrations).not.toHaveBeenCalled();
  });

  it('reads the final provider profile after shared work drains and releases its exact claim', async () => {
    const { app, owners, social, listIntegrations } = fixture();
    const release = vi.fn(async () => undefined);
    Object.assign(owners, { acquireOwnerDeletion: vi.fn(async () => {
      await social.setProfileId({ userId: 'owner-a', profileId: 'profile-created-before-drain' });
      return release;
    }) });
    await request(app).delete('/account').expect(200);
    expect(listIntegrations).toHaveBeenCalledWith({ profileId: 'profile-created-before-drain' });
    expect(release).toHaveBeenCalledOnce();
  });
});
