import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { createPostStore } from './postStore.js';
import { registerPostRoutes } from './postRoutes.js';

describe('owner-scoped single-post reads', () => {
  const fixture = async () => {
    const store = createPostStore();
    const queue = createInMemoryPublishQueue();
    const publishStore = createInMemoryPlatformPublishStore();
    const owned = await store.create({ userId: 'read-owner', caption: 'Private owned caption',
      videoS3Key: 'uploads/read-owner/clip/video.mp4', coverImageS3Key: 'uploads/read-owner/clip/cover.jpg',
      platforms: ['TIKTOK'], platformTargets: { TIKTOK: { accountId: 'private-account', connectedAt: '2026-10-21T00:00:00.000Z' } } });
    const foreign = await store.create({ userId: 'other-owner', caption: 'Foreign secret',
      videoS3Key: 'uploads/other-owner/clip/video.mp4', platforms: ['YOUTUBE_SHORTS'] });
    const sign = vi.fn(async (key: string): Promise<string | undefined> => `https://media.test/${key}?signature=private`);
    const app = express();
    const router = express.Router();
    registerPostRoutes(router, store, queue, (req, res, next) => {
      const userId = req.get('x-test-owner');
      if (userId) res.locals.authUser = { id: userId, provider: 'mock' };
      next();
    }, createUserStore(), createSubscriptionStore(), publishStore, { createMediaDownloadUrl: sign });
    app.use(router);
    return { app, store, queue, publishStore, owned, foreign, sign };
  };

  it('returns exactly one owned public post without listing history or mutating queues', async () => {
    const { app, store, queue, owned, sign } = await fixture();
    const list = vi.spyOn(store, 'list').mockRejectedValue(new Error('History must not be loaded'));
    const create = vi.spyOn(store, 'create');
    const enqueue = vi.spyOn(queue, 'enqueue');
    const response = await request(app).get(`/posts/${owned.id}`).set('x-test-owner', 'read-owner').expect(200);
    expect(response.headers['cache-control']).toBe('private, no-store');
    expect(response.body).toMatchObject({ status: 'ok', post: { id: owned.id, caption: owned.caption, status: 'QUEUED' } });
    expect(response.body.post).not.toHaveProperty('platformTargets');
    expect(response.body.post).not.toHaveProperty('platformSettings');
    expect(response.body.post).not.toHaveProperty('videoUrl');
    expect(list).not.toHaveBeenCalled();
    expect(sign).not.toHaveBeenCalled();
    expect(create).not.toHaveBeenCalled();
    expect(enqueue).not.toHaveBeenCalled();
  });

  it('makes foreign and missing ids indistinguishable and never signs foreign media', async () => {
    const { app, foreign, sign } = await fixture();
    const foreignResponse = await request(app).get(`/posts/${foreign.id}?includeMedia=true`).set('x-test-owner', 'read-owner').expect(404);
    const missingResponse = await request(app).get('/posts/missing?includeMedia=true').set('x-test-owner', 'read-owner').expect(404);
    expect(foreignResponse.body).toEqual({ status: 'error', code: 'POST_NOT_FOUND', message: 'Post not found' });
    expect(missingResponse.body).toEqual(foreignResponse.body);
    expect(sign).not.toHaveBeenCalled();
  });

  it('rejects unauthenticated reads before returning or signing anything', async () => {
    const { app, owned, sign } = await fixture();
    await request(app).get(`/posts/${owned.id}?includeMedia=true`).expect(401);
    expect(sign).not.toHaveBeenCalled();
  });

  it('returns both safe owned cover and video previews only when requested', async () => {
    const { app, owned, sign } = await fixture();
    const response = await request(app).get(`/posts/${owned.id}?includeMedia=true`).set('x-test-owner', 'read-owner').expect(200);
    expect(response.body.post.coverImageUrl).toContain('https://media.test/uploads/read-owner/');
    expect(response.body.post.videoUrl).toContain('https://media.test/uploads/read-owner/');
    expect(sign).toHaveBeenCalledTimes(2);
  });

  it.each(['javascript:alert(1)', 'https://user:password@media.test/private', undefined])(
    'keeps the owned post readable without exposing an unsafe or missing signed URL (%s)', async (url) => {
      const { app, owned, sign } = await fixture();
      sign.mockResolvedValue(url);
      const response = await request(app).get(`/posts/${owned.id}?includeMedia=true`).set('x-test-owner', 'read-owner').expect(200);
      expect(response.body.post.id).toBe(owned.id);
      expect(response.body.post).not.toHaveProperty('videoUrl');
      expect(response.body.post).not.toHaveProperty('coverImageUrl');
    }
  );
});
