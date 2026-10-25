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
    res.locals.authUser = { id: 'calendar-owner', provider: 'mock' };
    next();
  }, createUserStore(), createSubscriptionStore(), createInMemoryPlatformPublishStore());
  app.use(router);
  return { app, store };
};

const createAt = async (
  store: ReturnType<typeof createPostStore>, caption: string, createdAt: string, scheduledAt?: string
) => {
  vi.setSystemTime(new Date(createdAt));
  return store.create({
    userId: 'calendar-owner', caption, videoS3Key: 'uploads/calendar-owner/v.mp4', platforms: ['TIKTOK'],
    ...(scheduledAt ? { scheduledAt } : {})
  });
};

describe('GET /posts activeSince for Calendar (Codex review 2026-10-25)', () => {
  afterEach(() => { vi.useRealTimers(); });

  it('returns posts created, scheduled or published on or after activeSince across pages', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { app, store } = createFixture();
    // Created in August but rescheduled (each time within 30 days of the
    // reschedule) into October: Calendar shows it in October.
    const rescheduled = await createAt(store, 'rescheduled', '2026-08-01T00:00:00.000Z', '2026-10-05T00:00:00.000Z');
    const augustOnly = await createAt(store, 'august', '2026-08-02T00:00:00.000Z');
    await store.updateStatus({ postId: augustOnly.id, status: 'PUBLISHED', publishedAt: '2026-08-02T01:00:00.000Z' });
    const october = await createAt(store, 'october', '2026-10-03T00:00:00.000Z');
    vi.useRealTimers();

    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const response: request.Response = await request(app)
        .get(`/posts?pageSize=1&activeSince=${encodeURIComponent('2026-10-01T00:00:00.000Z')}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`)
        .expect(200);
      seen.push(...response.body.posts.map((post: { id: string }) => post.id));
      cursor = response.body.nextCursor;
    } while (cursor);

    expect(seen).toEqual([october.id, rescheduled.id]);
  });

  it.each([
    'pageSize=10&activeSince=yesterday',
    `activeSince=${encodeURIComponent('2026-10-01T00:00:00.000Z')}`
  ])('rejects an invalid activeSince request: %s', async (query) => {
    const { app } = createFixture();
    const response = await request(app).get(`/posts?${query}`).expect(400);
    expect(response.body).toMatchObject({ code: 'INVALID_POST_PAGE' });
  });

  it('adds the activeSince filter to the Prisma keyset query', async () => {
    const findMany = vi.fn().mockResolvedValue([]);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ post: { findMany } }) });
    const since = '2026-10-01T00:00:00.000Z';

    await repository.listPage({
      userId: 'calendar-owner', limit: 100, activeSince: since,
      after: { createdAt: '2026-10-20T00:00:00.000Z', id: 'post-z' }
    });

    expect(findMany).toHaveBeenCalledExactlyOnceWith({
      where: {
        userId: 'calendar-owner',
        OR: [
          { createdAt: { lt: new Date('2026-10-20T00:00:00.000Z') } },
          { createdAt: new Date('2026-10-20T00:00:00.000Z'), id: { lt: 'post-z' } }
        ],
        AND: [{
          OR: [
            { createdAt: { gte: new Date(since) } },
            { scheduledAt: { gte: new Date(since) } },
            { publishedAt: { gte: new Date(since) } }
          ]
        }]
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: 101
    });
  });
});
