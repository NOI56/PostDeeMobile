import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { readCaptionStorageIssue, readPlatformCaptionIssue } from './platformCaptionValidation.js';
import { createPostStore } from './postStore.js';
import { registerPostRoutes } from './postRoutes.js';
import { createPrismaPostRepository, type PrismaPostClient } from './prismaPostRepository.js';

const owner = 'history-owner';
const inOneDay = () => new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
const inTwoDays = () => new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();

const fixture = async () => {
  const store = createPostStore();
  const queue = createInMemoryPublishQueue();
  const scheduled = await store.create({
    userId: owner,
    caption: 'Scheduled caption',
    videoS3Key: `uploads/${owner}/clip/video.mp4`,
    platforms: ['TIKTOK'],
    scheduledAt: inOneDay()
  });
  await queue.enqueue(scheduled);
  const app = express();
  app.use(express.json());
  const router = express.Router();
  registerPostRoutes(router, store, queue, (_request, response, next) => {
    response.locals.authUser = { id: owner, provider: 'mock' };
    next();
  }, createUserStore(), { ...createSubscriptionStore(), getPlan: async () => 'PRO' as const },
  createInMemoryPlatformPublishStore());
  app.use(router);
  return { app, store, scheduled };
};

// An owner's Post rows are retained forever. Single-post mutations and limited
// lists must read only what they use, not the whole history.
describe('post history bounds', () => {
  it('reschedules one post without listing the owner history', async () => {
    const { app, store, scheduled } = await fixture();
    const list = vi.spyOn(store, 'list').mockRejectedValue(new Error('History must not be loaded'));

    const nextScheduledAt = inTwoDays();
    const response = await request(app).patch(`/posts/${scheduled.id}`).send({ scheduledAt: nextScheduledAt }).expect(200);

    expect(response.body.post).toMatchObject({ id: scheduled.id, scheduledAt: nextScheduledAt });
    expect(list).not.toHaveBeenCalled();
  });

  it('publishes one scheduled post now without listing the owner history', async () => {
    const { app, store, scheduled } = await fixture();
    const list = vi.spyOn(store, 'list').mockRejectedValue(new Error('History must not be loaded'));

    await request(app).post(`/posts/${scheduled.id}/publish-now`).expect(200);

    expect(list).not.toHaveBeenCalled();
  });

  it('asks the store for only the requested number of newest posts', async () => {
    const { app, store } = await fixture();
    const list = vi.spyOn(store, 'list');

    await request(app).get('/posts?limit=3').expect(200);

    expect(list).toHaveBeenCalledWith(expect.objectContaining({ userId: owner, limit: 3 }));
  });

  it('returns the newest posts first when the memory store is limited', async () => {
    const store = createPostStore();
    for (const createdOrder of [1, 2, 3]) {
      await store.create({ userId: 'order-owner', caption: `c${createdOrder}`, videoS3Key: `uploads/order-owner/${createdOrder}/v.mp4`, platforms: ['TIKTOK'] });
      await new Promise((resolve) => setTimeout(resolve, 2));
    }

    const posts = await store.list({ userId: 'order-owner', limit: 2 });

    expect(posts.map((post) => post.caption)).toEqual(['c3', 'c2']);
  });

  it('pushes the limit into the Prisma query and refuses an unscoped list', async () => {
    const findMany = vi.fn(async () => []);
    const repository = createPrismaPostRepository({ prisma: { post: { findMany } } as unknown as PrismaPostClient });

    await repository.list({ userId: owner, limit: 5 });

    expect(findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: owner },
      orderBy: { createdAt: 'desc' },
      take: 5
    }));
    await expect(repository.list({} as never)).rejects.toThrow('userId');
  });
});

// TikTok Inbox drafts had no caption ceiling below the 1 MiB body limit. Every
// new caption is now bounded by the largest supported platform cap (Facebook).
describe('post caption ceiling', () => {
  it('rejects a TikTok-only caption longer than the largest platform cap', () => {
    const issue = readCaptionStorageIssue('x'.repeat(63207), ['TIKTOK'], {
      TIKTOK: { publishMode: 'INBOX_DRAFT' }
    } as never);

    expect(issue).toMatchObject({ platform: 'TIKTOK', reason: 'CAPTION_TOO_LONG', maxLength: 63206 });
  });

  it('rejects an oversized shared caption even when every platform overrides it', () => {
    const issue = readCaptionStorageIssue('x'.repeat(63207), ['TIKTOK'], {
      TIKTOK: { publishMode: 'INBOX_DRAFT', caption: 'short' }
    } as never);

    expect(issue).toMatchObject({ reason: 'CAPTION_TOO_LONG' });
  });

  it('keeps accepting a long Facebook-sized TikTok Inbox caption', () => {
    expect(readCaptionStorageIssue('x'.repeat(63206), ['TIKTOK'], { TIKTOK: { publishMode: 'INBOX_DRAFT' } } as never)).toBeUndefined();
  });

  it('does not change the publisher-side platform preflight for queued posts', () => {
    expect(readPlatformCaptionIssue('x'.repeat(63207), ['TIKTOK'])).toBeUndefined();
  });
});
