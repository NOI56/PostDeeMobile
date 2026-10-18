import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createOwnerOperationRunner } from '../account/prismaOwnerOperationCoordinator.js';
import { createOwnerOperationRouter } from '../account/ownerOperationRouter.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import { createUserStore } from '../users/userStore.js';
import { registerPostRoutes } from './postRoutes.js';
import { createPostStore } from './postStore.js';

const body = {
  clientRequestId: 'accepted-old-request', caption: 'ก'.repeat(1667),
  videoS3Key: 'uploads/owner/clip/old.mp4', platforms: ['YOUTUBE_SHORTS'],
  platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } },
  mediaContentFingerprint: 'a'.repeat(64)
};
const testApp = ({ authenticated = true, assertOwnerActive = vi.fn(async (_owner: string) => undefined), lifetime = undefined as RunWithActiveOwner | undefined } = {}) => {
  const app = express();
  app.use(express.json());
  const store = createPostStore();
  const queue = createInMemoryPublishQueue();
  const userStore = createUserStore();
  const subscriptionStore = createSubscriptionStore();
  const getPlan = vi.spyOn(subscriptionStore, 'getPlan');
  const ensureUser = vi.spyOn(userStore, 'ensure');
  const resolvePlatformTarget = vi.fn();
  const assertUploadReady = vi.fn();
  const ensureEnqueued = vi.spyOn(queue, 'ensureEnqueued');
  const enqueue = vi.spyOn(queue, 'enqueue');
  const router = lifetime ? createOwnerOperationRouter(express.Router(), lifetime) : app;
  registerPostRoutes(router, store, queue, (_request, response, next) => {
    if (authenticated) response.locals.authUser = { id: 'owner', provider: 'mock' };
    next();
  }, userStore, subscriptionStore, createInMemoryPlatformPublishStore(), {
    socialPublishingEnabled: false, assertOwnerActive, runWithOwnerLifetime: lifetime,
    resolvePlatformTarget, assertUploadReady
  });
  if (router !== app) app.use(router);
  return { app, store, getPlan, ensureUser, resolvePlatformTarget, assertUploadReady, ensureEnqueued, enqueue };
};
const accept = async (store: ReturnType<typeof createPostStore>, userId = 'owner') => {
  const result = await store.createWithinMonthlyLimit({ ...body, userId, platforms: ['YOUTUBE_SHORTS'], platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } }, platformTargets: { YOUTUBE_SHORTS: { accountId: 'private-provider-id', connectedAt: '2026-10-15T10:00:00.000Z' } }, monthlyPostUnitLimit: 3, now: '2026-10-15T10:00:00.000Z' });
  if (!result.ok) throw new Error('Fixture could not accept post');
  return result.post;
};

describe('read-only accepted submission recovery', () => {
  it.each([undefined, true, false])('recovers accepted Meta settings without changing an omitted or explicit AI declaration (%s)', async (isAiGenerated) => {
    const context = testApp();
    const aiSetting = isAiGenerated === undefined ? {} : { isAiGenerated };
    const original = {
      ...body, clientRequestId: 'accepted-meta-intent', caption: 'Original Meta intent',
      platforms: ['INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const,
      platformSettings: {
        INSTAGRAM_REELS: { shareToFeed: false, ...aiSetting },
        FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' as const, ...aiSetting }
      }
    };
    const accepted = await context.store.createWithinMonthlyLimit({
      ...original, userId: 'owner', platforms: [...original.platforms],
      monthlyPostUnitLimit: 3, now: '2026-10-15T10:00:00.000Z'
    });
    expect(accepted.ok).toBe(true);
    const response = await request(context.app).post('/posts/submissions/recover').send(original).expect(200);
    expect(response.body.post.platformSettings).toEqual(original.platformSettings);
    expect(context.enqueue).not.toHaveBeenCalled();
    expect(context.ensureEnqueued).not.toHaveBeenCalled();

    for (const platform of ['INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const) {
      const changed = {
        ...original,
        platformSettings: { ...original.platformSettings, [platform]: { ...original.platformSettings[platform], isAiGenerated: isAiGenerated !== true } }
      };
      const conflict = await request(context.app).post('/posts/submissions/recover').send(changed).expect(409);
      expect(conflict.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
    }
  });

  it('recovers a mixed legacy YouTube/Facebook intent with only the known missing Facebook default', async () => {
    const context = testApp();
    const original = { ...body, userId: 'owner', clientRequestId: 'mixed-legacy', platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'] as const };
    const accepted = await context.store.createWithinMonthlyLimit({ ...original, platforms: [...original.platforms], platformSettings: undefined, monthlyPostUnitLimit: 3, now: '2026-10-15T10:00:00.000Z' });
    expect(accepted.ok).toBe(true);
    const create = vi.spyOn(context.store, 'createWithinMonthlyLimit');
    const response = await request(context.app).post('/posts/submissions/recover').send({ ...original, platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } } }).expect(200);
    expect(response.body).toMatchObject({ recovered: true, idempotentReplay: true });
    for (const spy of [create, context.enqueue, context.ensureEnqueued, context.resolvePlatformTarget, context.assertUploadReady, context.getPlan]) expect(spy).not.toHaveBeenCalled();
  });
  it('does not reinterpret a missing Facebook setting as an already accepted Page draft', async () => {
    const { app, store } = testApp();
    const original = { ...body, userId: 'owner', clientRequestId: 'accepted-fb-draft', platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'] as const };
    await store.createWithinMonthlyLimit({ ...original, platforms: [...original.platforms], platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' }, FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' } }, monthlyPostUnitLimit: 3, now: '2026-10-15T10:00:00.000Z' });
    const response = await request(app).post('/posts/submissions/recover').send({ ...original, platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } } }).expect(409);
    expect(response.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
  });
  it.each([
    {}, { FACEBOOK_REELS: { publishMode: 'PUBLISH' } },
    { YOUTUBE_SHORTS: { visibility: 'private' }, FACEBOOK_REELS: null },
    { YOUTUBE_SHORTS: { visibility: 'private' }, FACEBOOK_REELS: {} }
  ])('continues rejecting other missing or malformed mixed legacy settings %o', async (platformSettings) => {
    const { app, store } = testApp();
    const lookup = vi.spyOn(store, 'findIdempotent');
    const response = await request(app).post('/posts/submissions/recover').send({ ...body, platforms: ['YOUTUBE_SHORTS', 'FACEBOOK_REELS'], platformSettings }).expect(400);
    expect(response.body.code).toBe('INVALID_POST_SUBMISSION_RECOVERY');
    expect(lookup).not.toHaveBeenCalled();
  });
  it('recovers a legacy receipt before new caption/media/readiness/config/plan gates without queue writes', async () => {
    const context = testApp();
    const accepted = await accept(context.store);
    const create = vi.spyOn(context.store, 'createWithinMonthlyLimit');
    const response = await request(context.app).post('/posts/submissions/recover').send(body).expect(200);
    expect(response.body).toMatchObject({ status: 'ok', recovered: true, idempotentReplay: true, post: { id: accepted.id, caption: body.caption, status: 'QUEUED' } });
    expect(response.body.post).not.toHaveProperty('platformTargets');
    expect(response.body.post).not.toHaveProperty('mediaContentFingerprint');
    expect(JSON.stringify(response.body)).not.toContain('private-provider-id');
    expect(response.headers['cache-control']).toBe('private, no-store');
    for (const spy of [create, context.getPlan, context.ensureUser, context.resolvePlatformTarget, context.assertUploadReady, context.ensureEnqueued, context.enqueue]) expect(spy).not.toHaveBeenCalled();
  });
  it('returns the existing FAILED result without inventing publication or retrying', async () => {
    const { app, store, ensureEnqueued, enqueue } = testApp();
    const post = await accept(store);
    await store.updateStatus({ postId: post.id, status: 'FAILED' });
    const response = await request(app).post('/posts/submissions/recover').send(body).expect(200);
    expect(response.body.post.status).toBe('FAILED');
    expect(ensureEnqueued).not.toHaveBeenCalled();
    expect(enqueue).not.toHaveBeenCalled();
  });
  it('requires authentication before reading posts', async () => {
    const { app, store } = testApp({ authenticated: false });
    const lookup = vi.spyOn(store, 'findIdempotent');
    await request(app).post('/posts/submissions/recover').send(body).expect(401);
    expect(lookup).not.toHaveBeenCalled();
  });
  it('does not recover another owner request even with caller owner overrides', async () => {
    const { app, store } = testApp();
    await accept(store, 'foreign');
    const response = await request(app).post('/posts/submissions/recover?userId=foreign').send({ ...body, userId: 'foreign' }).expect(404);
    expect(response.body.code).toBe('POST_SUBMISSION_NOT_FOUND');
    expect(response.body).not.toHaveProperty('post');
  });
  it('returns missing without creating a post or recovering an upload', async () => {
    const { app, store, enqueue, ensureEnqueued } = testApp();
    const create = vi.spyOn(store, 'createWithinMonthlyLimit');
    await request(app).post('/posts/submissions/recover').send(body).expect(404);
    expect(create).not.toHaveBeenCalled();
    expect(enqueue).not.toHaveBeenCalled();
    expect(ensureEnqueued).not.toHaveBeenCalled();
  });
  it.each([
    { caption: 'changed' }, { platforms: ['INSTAGRAM_REELS'], platformSettings: { INSTAGRAM_REELS: { shareToFeed: true } } },
    { platformSettings: { YOUTUBE_SHORTS: { title: 'new', visibility: 'public', madeForKids: false, containsSyntheticMedia: false, communityGuidelinesCertified: true } } },
    { mediaContentFingerprint: 'b'.repeat(64) }, { scheduledAt: '2026-10-16T10:00:00.000Z' }
  ])('rejects changed immutable intent %o', async (change) => {
    const { app, store } = testApp();
    await accept(store);
    const response = await request(app).post('/posts/submissions/recover').send({ ...body, ...change }).expect(409);
    expect(response.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
    expect(response.body).not.toHaveProperty('post');
  });
  it('rejects malformed requests without a post lookup', async () => {
    const { app, store } = testApp();
    const lookup = vi.spyOn(store, 'findIdempotent');
    await request(app).post('/posts/submissions/recover').send({ ...body, clientRequestId: '' }).expect(400);
    expect(lookup).not.toHaveBeenCalled();
  });
  it('checks the owner again after lookup, and releases the read-only lifetime on failure', async () => {
    const release = vi.fn(async () => undefined);
    const lifetime = createOwnerOperationRunner({ admit: async () => 'recovery-read', release });
    const assertOwnerActive = vi.fn(async () => undefined).mockImplementationOnce(async () => undefined)
      .mockImplementationOnce(async () => { throw new ManagedUploadServiceError(409, 'ACCOUNT_DELETION_IN_PROGRESS', 'Account deletion is in progress.'); });
    const { app, store } = testApp({ assertOwnerActive, lifetime });
    await accept(store);
    const response = await request(app).post('/posts/submissions/recover').send(body).expect(409);
    expect(response.body.code).toBe('ACCOUNT_DELETION_IN_PROGRESS');
    expect(response.body).not.toHaveProperty('post');
    await vi.waitFor(() => expect(release).toHaveBeenCalledExactlyOnceWith('owner', 'recovery-read'));
  });
  it('sanitizes lookup failures and releases a read ticket', async () => {
    const release = vi.fn(async () => undefined);
    const lifetime = createOwnerOperationRunner({ admit: async () => 'failed-read', release });
    const { app, store } = testApp({ lifetime });
    vi.spyOn(store, 'findIdempotent').mockRejectedValue(new Error('private-provider-id secret-token'));
    const response = await request(app).post('/posts/submissions/recover').send(body).expect(503);
    expect(response.body.code).toBe('POST_SUBMISSION_RECOVERY_UNAVAILABLE');
    expect(JSON.stringify(response.body)).not.toMatch(/private-provider|secret-token/);
    await vi.waitFor(() => expect(release).toHaveBeenCalledExactlyOnceWith('owner', 'failed-read'));
  });
});
