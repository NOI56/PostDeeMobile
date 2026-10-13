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
import { registerBillingRoutes } from '../billing/billingRoutes.js';
import { createApp } from '../../app.js';

const authUser = { id: 'owner-a', provider: 'mock' as const };
const makeAccountApp = (overrides: Partial<AccountRouteDependencies> = {}) => {
  const owners = createInMemoryUploadSessionStore();
  const publishQueue = createInMemoryPublishQueue();
  const deleteUser = vi.fn(async () => undefined);
  const dependencies = {
    postStore: createPostStore(), publishQueue,
    userStore: { ...createUserStore(), deleteAllForUser: deleteUser },
    subscriptionStore: createSubscriptionStore(),
    templateStore: {}, analyticsStore: {}, realClipCaptionUsageStore: {},
    aiEditUsageStore: {}, deviceTokenStore: {}, platformPublishStore: {},
    videoStorage: { supportsOwnerCleanup: true, deleteAllVideosForOwner: vi.fn(async () => undefined) },
    ownerLifecycleStore: owners, ...overrides
  } as AccountRouteDependencies;
  const app = express();
  const router = express.Router();
  registerAccountRoutes(router, (_request, response, next) => { response.locals.authUser = authUser; next(); }, dependencies);
  app.use(router);
  return { app, owners, publishQueue, deleteUser };
};

const orphanPost = { id: 'orphan-a', userId: authUser.id, caption: 'Private', videoS3Key: 'uploads/owner-a/a.mp4', platforms: ['TIKTOK' as const], status: 'QUEUED' as const, createdAt: '2026-10-13T00:00:00.000Z' };

describe('delivery account lifecycle integration', () => {
  it('removes owner jobs without a post row while preserving another owner queue', async () => {
    const { app, owners, publishQueue } = makeAccountApp();
    await publishQueue.enqueue(orphanPost);
    await publishQueue.enqueue({ ...orphanPost, id: 'orphan-b', userId: 'owner-b' });
    await request(app).delete('/account').expect(200);
    expect(await publishQueue.list({ userId: authUser.id })).toEqual([]);
    expect(await publishQueue.list({ userId: 'owner-b' })).toHaveLength(1);
    await expect(owners.assertOwnerActive(authUser.id)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('reports an unfinished queue drain before deleting durable data', async () => {
    const { app, deleteUser } = makeAccountApp({ ownerLifecycleStore: {
      beginOwnerDeletion: vi.fn(async () => { throw new OwnerOperationBusyError(); }),
      finishOwnerDeletion: vi.fn()
    } });
    await request(app).delete('/account').expect(503).expect(({ body }) => {
      expect(body.code).toBe('ACCOUNT_WRITE_DRAIN_FAILED');
    });
    expect(deleteUser).not.toHaveBeenCalled();
  });

  it('keeps the tombstone and data when publish job cleanup fails', async () => {
    const queue = createInMemoryPublishQueue();
    await queue.enqueue(orphanPost);
    const { app, owners, deleteUser } = makeAccountApp({ publishQueue: {
      ...queue, remove: vi.fn(async () => { throw new Error('Redis unavailable'); })
    } });
    await request(app).delete('/account').expect(503).expect(({ body }) => {
      expect(body.code).toBe('ACCOUNT_PUBLISH_CLEANUP_FAILED');
    });
    expect(deleteUser).not.toHaveBeenCalled();
    await expect(owners.assertOwnerActive(authUser.id)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
  });

  it('retains the legacy tombstone across apps sharing the owner store', async () => {
    const owners = createInMemoryUploadSessionStore();
    const first = createApp({ uploadSessionStore: owners });
    await request(first).delete('/account').set('x-postdee-user-id', authUser.id).expect(200);
    const second = createApp({ uploadSessionStore: owners });
    await request(second).post('/billing/purchase-readiness').set('x-postdee-user-id', authUser.id).send({}).expect(409);
  });

  it('returns 409 when store verification resumes after owner deletion', async () => {
    const owners = createInMemoryUploadSessionStore();
    const userStore = createUserStore({ runWithActiveOwner: owners.runWithActiveOwner });
    const subscriptionStore = createSubscriptionStore({ runWithActiveOwner: owners.runWithActiveOwner });
    const app = express();
    const router = express.Router();
    app.use(express.json());
    registerBillingRoutes(router, (_request, response, next) => { response.locals.authUser = authUser; next(); },
      userStore, subscriptionStore, createPostStore(), { storePurchaseVerifier: {
        verify: async (purchase) => {
          await owners.beginOwnerDeletion(authUser.id);
          return { ...purchase, provider: 'mock-store', verifiedAt: '2026-10-13T00:00:00.000Z' };
        }
      } });
    app.use(router);
    app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
      response.status(409).json({ code: (error as { code: string }).code });
    });
    await request(app).post('/billing/store/verify').send({ platform: 'ANDROID', productId: 'postdee_pro_monthly', purchaseToken: 'fixture-token' })
      .expect(409).expect({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(userStore.exists(authUser.id)).resolves.toBe(false);
    await expect(subscriptionStore.getPlan(authUser)).resolves.toBe('BASIC');
  });
});
