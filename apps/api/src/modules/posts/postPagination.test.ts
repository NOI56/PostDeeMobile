import express from 'express';
import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { withPostRepositoryFixture } from '../../../test/repositoryFixtures.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { createPostStore } from './postStore.js';
import { createPrismaPostRepository } from './prismaPostRepository.js';
import { registerPostRoutes } from './postRoutes.js';

const createFixture = () => {
  const store = createPostStore();
  const app = express();
  const router = express.Router();
  registerPostRoutes(router, store, createInMemoryPublishQueue(), (req, res, next) => {
    const userId = req.get('x-test-owner');
    if (userId) res.locals.authUser = { id: userId, provider: 'mock' };
    next();
  }, createUserStore(), createSubscriptionStore(), createInMemoryPlatformPublishStore());
  app.use(router);
  return { app, store };
};

const seed = async (store: ReturnType<typeof createPostStore>, userId: string, at: string, scheduledAt?: string) => {
  vi.setSystemTime(new Date(at));
  return store.create({
    userId, caption: `Post at ${at}`, videoS3Key: `uploads/${userId}/v.mp4`, platforms: ['TIKTOK'],
    ...(scheduledAt ? { scheduledAt } : {})
  });
};

const getPage = (app: express.Express, query: string) =>
  request(app).get(`/posts?${query}`).set('x-test-owner', 'page-owner');

describe('GET /posts cursor pagination', () => {
  afterEach(() => { vi.useRealTimers(); });

  it('keeps the plain list complete and cursor-free for installed apps', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { app, store } = createFixture();
    for (const day of ['01', '02', '03']) await seed(store, 'page-owner', `2026-10-${day}T00:00:00.000Z`);

    const response = await request(app).get('/posts').set('x-test-owner', 'page-owner').expect(200);
    expect(response.body.posts).toHaveLength(3);
    expect(response.body).not.toHaveProperty('nextCursor');
  });

  it('pages one owner newest-created first with an opaque cursor and never reads the full history', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { app, store } = createFixture();
    const days = ['01', '02', '03', '04', '05'];
    for (const day of days) await seed(store, 'page-owner', `2026-10-${day}T00:00:00.000Z`);
    await seed(store, 'other-owner', '2026-10-06T00:00:00.000Z');
    vi.spyOn(store, 'list').mockRejectedValue(new Error('History must not be loaded'));

    const first = await getPage(app, 'pageSize=2').expect(200);
    expect(first.headers['cache-control']).toBe('private, no-store');
    expect(first.body.posts.map((post: { createdAt: string }) => post.createdAt.slice(8, 10))).toEqual(['05', '04']);
    expect(typeof first.body.nextCursor).toBe('string');

    const second = await getPage(app, `pageSize=2&cursor=${encodeURIComponent(first.body.nextCursor)}`).expect(200);
    expect(second.body.posts.map((post: { createdAt: string }) => post.createdAt.slice(8, 10))).toEqual(['03', '02']);

    const last = await getPage(app, `pageSize=2&cursor=${encodeURIComponent(second.body.nextCursor)}`).expect(200);
    expect(last.body.posts.map((post: { createdAt: string }) => post.createdAt.slice(8, 10))).toEqual(['01']);
    expect(last.body.nextCursor).toBeNull();
    for (const page of [first, second, last]) {
      expect(page.body.posts.every((post: { userId?: string }) => post.userId === undefined || post.userId === 'page-owner')).toBe(true);
    }
  });

  it('does not skip or repeat posts created in the same millisecond', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { app, store } = createFixture();
    const created = [];
    for (let index = 0; index < 5; index += 1) created.push(await seed(store, 'page-owner', '2026-10-01T00:00:00.000Z'));

    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const response: request.Response = await getPage(app, `pageSize=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`).expect(200);
      seen.push(...response.body.posts.map((post: { id: string }) => post.id));
      cursor = response.body.nextCursor;
    } while (cursor);
    expect([...seen].sort()).toEqual(created.map((post) => post.id).sort());
    expect(new Set(seen).size).toBe(5);
  });

  it('pages only scheduled posts when asked', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { app, store } = createFixture();
    await seed(store, 'page-owner', '2026-10-01T00:00:00.000Z', '2026-10-20T00:00:00.000Z');
    await seed(store, 'page-owner', '2026-10-02T00:00:00.000Z');

    const response = await getPage(app, 'pageSize=10&scheduled=true').expect(200);
    expect(response.body.posts).toHaveLength(1);
    expect(response.body.posts[0].scheduledAt).toBe('2026-10-20T00:00:00.000Z');
    expect(response.body.nextCursor).toBeNull();
  });

  it.each([
    'pageSize=0', 'pageSize=101', 'pageSize=abc', 'cursor=not-a-cursor',
    `cursor=${Buffer.from('{"v":1,"c":"yesterday","i":"x"}').toString('base64url')}`,
    'pageSize=10&limit=3', 'pageSize=10&includeMedia=true'
  ])('rejects an invalid page request: %s', async (query) => {
    const { app } = createFixture();
    const response = await getPage(app, query).expect(400);
    expect(response.body).toMatchObject({ status: 'error', code: 'INVALID_POST_PAGE' });
  });
});

describe('Prisma post page read', () => {
  const row = (id: string, createdAt: string) => ({
    id, userId: 'page-owner', caption: 'Post', videoS3Key: 'uploads/page-owner/v.mp4',
    selectedPlatforms: ['TIKTOK'], scheduledAt: null, publishedAt: null, status: 'QUEUED',
    createdAt: new Date(createdAt)
  });

  it('uses an owner-scoped keyset query with one extra row to detect the next page', async () => {
    const findMany = vi.fn().mockResolvedValue([
      row('post-c', '2026-10-03T00:00:00.000Z'), row('post-b', '2026-10-02T00:00:00.000Z'),
      row('post-a', '2026-10-01T00:00:00.000Z')
    ]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });

    const page = await repository.listPage({
      userId: 'page-owner', limit: 2, after: { createdAt: '2026-10-04T00:00:00.000Z', id: 'post-d' }
    });

    expect(page.posts.map((post) => post.id)).toEqual(['post-c', 'post-b']);
    expect(page.next).toEqual({ createdAt: '2026-10-02T00:00:00.000Z', id: 'post-b' });
    expect(findMany).toHaveBeenCalledExactlyOnceWith({
      where: {
        userId: 'page-owner',
        OR: [
          { createdAt: { lt: new Date('2026-10-04T00:00:00.000Z') } },
          { createdAt: new Date('2026-10-04T00:00:00.000Z'), id: { lt: 'post-d' } }
        ]
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: 3
    });
  });

  it('reports no next page when the extra row is absent', async () => {
    const findMany = vi.fn().mockResolvedValue([row('post-a', '2026-10-01T00:00:00.000Z')]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });

    const page = await repository.listPage({ userId: 'page-owner', limit: 2, scheduledOnly: true });

    expect(page).toEqual({ posts: [expect.objectContaining({ id: 'post-a' })] });
    expect(findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { userId: 'page-owner', scheduledAt: { not: null } }, take: 3
    }));
  });
});
