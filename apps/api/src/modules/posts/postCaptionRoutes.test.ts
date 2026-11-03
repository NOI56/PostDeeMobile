import express from 'express';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

import { registerPostRoutes } from './postRoutes.js';
import { createPostStore, type Platform, type PostStatus } from './postStore.js';
import { createInMemoryPublishQueue } from '../queue/publishQueue.js';
import { createInMemoryPlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';
import { createUserStore } from '../users/userStore.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';

const now = '2026-11-03T00:00:00.000Z';
const scheduledAt = '2026-11-03T01:00:00.000Z';
const allPlatforms: Platform[] = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];
const settings = {
  TIKTOK: { publishMode: 'INBOX_DRAFT' as const, caption: 'Old TikTok' },
  YOUTUBE_SHORTS: { title: 'Old title', visibility: 'unlisted' as const, madeForKids: false,
    containsSyntheticMedia: true, communityGuidelinesCertified: true as const, caption: 'Old YouTube' },
  INSTAGRAM_REELS: { shareToFeed: false, isAiGenerated: true, caption: 'Old Instagram' },
  FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' as const, isAiGenerated: true, caption: 'Old Facebook' }
};

const fixture = (options: Parameters<typeof registerPostRoutes>[7] = {}) => {
  const app = express();
  const router = express.Router();
  const store = createPostStore();
  const queue = createInMemoryPublishQueue();
  const subscriptionStore = createSubscriptionStore();
  const getPlan = vi.spyOn(subscriptionStore, 'getPlan');
  const ensureUser = vi.spyOn(createUserStore(), 'ensure');
  const userStore = { ...createUserStore(), ensure: ensureUser };
  const assertOwnerActive = vi.fn(async () => {});
  app.use(express.json({ limit: '1mb' }));
  registerPostRoutes(router, store, queue, (_request, response, next) => {
    response.locals.authUser = { id: 'owner', provider: 'mock', phoneVerified: true };
    next();
  }, userStore, subscriptionStore, createInMemoryPlatformPublishStore(), {
    now: () => new Date(now), assertOwnerActive, ...options
  });
  app.use(router);
  app.use((_error: Error, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
    response.status(500).json({ status: 'error', message: 'Request failed' });
  });
  const create = (input: Partial<Parameters<typeof store.create>[0]> = {}) => store.create({
    userId: 'owner', caption: 'Old shared', videoS3Key: 'uploads/owner/video.mp4',
    coverImageS3Key: 'uploads/owner/cover.jpg', coverFrameTimeMs: 1234,
    platforms: ['INSTAGRAM_REELS'], scheduledAt, ...input
  });
  return { app, store, queue, getPlan, ensureUser, assertOwnerActive, create };
};

describe('PATCH /posts/:id/caption', () => {
  it('updates shared text without enqueueing again, checking a plan, or allocating quota/AI credits', async () => {
    const { app, create, store, queue, getPlan, ensureUser, assertOwnerActive } = fixture();
    const post = await create();
    const original = structuredClone(post);
    const usage = await store.countMonthlyPostUnits({ userId: 'owner', now });
    const allocate = vi.spyOn(store, 'createWithinMonthlyLimit');
    const enqueue = vi.spyOn(queue, 'enqueue');
    const reschedule = vi.spyOn(queue, 'reschedule');
    const result = await request(app).patch(`/posts/${post.id}/caption`)
      .send({ caption: '  New shared  ', expectedUpdatedAt: post.updatedAt }).expect(200);
    expect(result.body).toMatchObject({ status: 'ok', post: { ...original, updatedAt: expect.any(String), caption: 'New shared' } });
    expect(result.body.post.updatedAt).not.toBe(original.updatedAt);
    expect(result.body.post).not.toHaveProperty('platformSettings');
    expect((await store.findOwned({ postId: post.id, userId: 'owner' }))?.caption).toBe('New shared');
    expect(await store.countMonthlyPostUnits({ userId: 'owner', now })).toBe(usage);
    expect(await store.countAddonPostUnits({ userId: 'owner' })).toBe(0);
    for (const spy of [getPlan, ensureUser, allocate, enqueue, reschedule]) expect(spy).not.toHaveBeenCalled();
    expect(assertOwnerActive).toHaveBeenCalledWith('owner');
  });

  it('merges only caption/title fields and retains every existing destination choice and media field', async () => {
    const { app, create, store } = fixture();
    const platformTargets = Object.fromEntries(allPlatforms.map(platform => [platform, { accountId: `${platform}-owner`, connectedAt: now }]));
    const post = await create({ platforms: allPlatforms, platformSettings: settings, platformTargets });
    const original = structuredClone(post);
    const result = await request(app).patch(`/posts/${post.id}/caption`).send({
      caption: 'New representative', platformCaptions: { TIKTOK: 'New TikTok', YOUTUBE_SHORTS: '', FACEBOOK_REELS: null },
      youtubeTitle: 'New title', expectedUpdatedAt: original.updatedAt,
      scheduledAt: '2027-01-01T00:00:00.000Z', platforms: ['TIKTOK'],
      platformSettings: { FACEBOOK_REELS: { publishMode: 'PUBLISH' } }, videoS3Key: 'replacement.mp4'
    }).expect(200);
    const nextSettings = { ...settings, TIKTOK: { ...settings.TIKTOK, caption: 'New TikTok' },
      YOUTUBE_SHORTS: { ...settings.YOUTUBE_SHORTS, title: 'New title', caption: '' },
      FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT', isAiGenerated: true } };
    expect(result.body.post.platformSettings).toEqual(nextSettings);
    const persisted = await store.findOwned({ postId: post.id, userId: 'owner' });
    expect(persisted).toMatchObject({ ...original, updatedAt: expect.any(String), caption: 'New representative', platformSettings: nextSettings });
    expect(result.body.post).not.toHaveProperty('platformTargets');
  });

  it('allows a legacy YouTube title edit without inventing consent or visibility settings', async () => {
    const { app, create } = fixture();
    const post = await create({ platforms: ['YOUTUBE_SHORTS'], platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } } });
    const response = await request(app).patch(`/posts/${post.id}/caption`)
      .send({ caption: 'New description', youtubeTitle: 'Edited title' }).expect(200);
    expect(response.body.post.platformSettings).toEqual({ YOUTUBE_SHORTS: { visibility: 'private', title: 'Edited title' } });
  });

  it('preserves every TikTok Direct Post choice, account revision and consent while editing its caption', async () => {
    const { app, create } = fixture();
    const directSettings = { publishMode: 'DIRECT_POST' as const, privacyLevel: 'PUBLIC_TO_EVERYONE' as const,
      disableComment: true, disableDuet: false, disableStitch: true, brandContentToggle: true,
      brandOrganicToggle: false, isAigc: true, videoDurationSeconds: 42,
      musicUsageConfirmed: true as const, brandedContentPolicyConfirmed: true, creatorInfoRevision: 'a'.repeat(64) };
    const post = await create({ platforms: ['TIKTOK'], platformSettings: { TIKTOK: directSettings } });
    const result = await request(app).patch(`/posts/${post.id}/caption`)
      .send({ caption: 'New shared', platformCaptions: { TIKTOK: 'New direct caption' } }).expect(200);
    expect(result.body.post.platformSettings).toEqual({ TIKTOK: { ...directSettings, caption: 'New direct caption' } });
    expect((await request(app).patch(`/posts/${post.id}/caption`)
      .send({ caption: 'Valid shared', platformCaptions: { TIKTOK: '😀'.repeat(1101) } }).expect(400)).body.code).toBe('TIKTOK_CAPTION_TOO_LONG');
  });

  it('retains legacy YouTube title-from-caption behavior when youtubeTitle is omitted', async () => {
    const { app, create } = fixture();
    const post = await create({ platforms: ['YOUTUBE_SHORTS'], platformSettings: { YOUTUBE_SHORTS: { visibility: 'private' } } });
    const response = await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Changed caption' }).expect(200);
    expect(response.body.post.platformSettings.YOUTUBE_SHORTS).toEqual({ visibility: 'private' });
  });

  it('preserves title-only YouTube posts and allows an explicit empty description', async () => {
    const { app, create } = fixture();
    const post = await create({ caption: '', platforms: ['YOUTUBE_SHORTS'], platformSettings: { YOUTUBE_SHORTS: settings.YOUTUBE_SHORTS } });
    const response = await request(app).patch(`/posts/${post.id}/caption`)
      .send({ caption: '', platformCaptions: { YOUTUBE_SHORTS: '' }, youtubeTitle: 'Only title' }).expect(200);
    expect(response.body.post).toMatchObject({ caption: '', platformSettings: { YOUTUBE_SHORTS: { title: 'Only title', caption: '' } } });
  });

  it('returns the same 404 for missing and another owner’s posts', async () => {
    const { app, create } = fixture();
    const foreign = await create({ userId: 'someone-else' });
    for (const id of ['missing', foreign.id]) {
      expect((await request(app).patch(`/posts/${id}/caption`).send({ caption: 'No access' }).expect(404)).body.code).toBe('POST_NOT_FOUND');
    }
  });

  it.each(['PUBLISHING', 'PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED'] as PostStatus[])('rejects status %s', async (status) => {
    const { app, create, store } = fixture();
    const post = await create();
    await store.updateStatus({ postId: post.id, status });
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Closed' }).expect(409)).body.code).toBe('POST_NOT_EDITABLE');
  });

  it.each([undefined, '2026-11-02T23:59:59.000Z', '2026-11-03T00:00:59.999Z', '2026-11-03T00:01:00.000Z'])(
    'rejects a missing or closed editing window (%s)', async (time) => {
      const { app, create } = fixture();
      const post = await create({ scheduledAt: time });
      expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Closed' }).expect(409)).body.code).toBe('POST_CAPTION_EDIT_WINDOW_CLOSED');
    });

  it('accepts one millisecond outside the cutoff and rejects stale updatedAt', async () => {
    const { app, create } = fixture();
    const post = await create({ scheduledAt: '2026-11-03T00:01:00.001Z' });
    const expectedUpdatedAt = post.updatedAt;
    await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'First', expectedUpdatedAt }).expect(200);
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Stale', expectedUpdatedAt }).expect(409)).body.code).toBe('POST_CAPTION_CONFLICT');
    expect(post.caption).toBe('First');
  });

  it('returns conflict when a worker claims the row at the compare-and-set boundary', async () => {
    const { app, create, store } = fixture();
    const post = await create();
    const update = store.updateCaption;
    vi.spyOn(store, 'updateCaption').mockImplementation(async input => {
      await store.claimForPublish({ postId: post.id, expectedRunAt: scheduledAt });
      return update(input);
    });
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Too late' }).expect(409)).body.code).toBe('POST_CAPTION_CONFLICT');
    expect(post.caption).toBe('Old shared');
  });

  it.each([
    ['TIKTOK', '😀'.repeat(1101), 'TIKTOK_CAPTION_TOO_LONG', undefined],
    ['INSTAGRAM_REELS', 'a'.repeat(2201), 'PLATFORM_CAPTION_INVALID', 'INSTAGRAM_CAPTION_TOO_LONG'],
    ['FACEBOOK_REELS', 'a'.repeat(63207), 'PLATFORM_CAPTION_INVALID', 'FACEBOOK_CAPTION_TOO_LONG'],
    ['YOUTUBE_SHORTS', 'ก'.repeat(1667), 'PLATFORM_CAPTION_INVALID', 'YOUTUBE_DESCRIPTION_TOO_LONG'],
    ['YOUTUBE_SHORTS', 'Description < invalid >', 'PLATFORM_CAPTION_INVALID', 'YOUTUBE_DESCRIPTION_INVALID_CHARACTERS']
  ] as const)('uses existing %s effective-caption validation', async (platform, caption, code, reason) => {
    const { app, create } = fixture();
    const post = await create({ platforms: [platform] });
    const response = await request(app).patch(`/posts/${post.id}/caption`).send({ caption }).expect(400);
    expect(response.body).toMatchObject({ code, ...(reason ? { reason } : {}) });
    expect(post.caption).toBe('Old shared');
  });

  it.each(['', 'a'.repeat(101), '<title>'])('rejects an invalid YouTube title (%j)', async (youtubeTitle) => {
    const { app, create } = fixture();
    const post = await create({ platforms: ['YOUTUBE_SHORTS'] });
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Valid', youtubeTitle }).expect(400)).body.code).toBe('INVALID_YOUTUBE_TITLE');
  });

  it.each([
    { platformCaptions: { TIKTOK: 'Not selected' } },
    { platformCaptions: { INSTAGRAM_REELS: '' } },
    { platformCaptions: { INSTAGRAM_REELS: 10 } },
    { platformCaptions: [] }
  ])('rejects malformed or unselected override edits (%j)', async (body) => {
    const { app, create } = fixture();
    const post = await create();
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Valid', ...body }).expect(400)).body.code).toBe('INVALID_PLATFORM_CAPTIONS');
  });

  it('retains the publishing feature gate and active-owner guard', async () => {
    const disabled = fixture({ socialPublishingEnabled: false });
    const first = await disabled.create();
    expect((await request(disabled.app).patch(`/posts/${first.id}/caption`).send({ caption: 'Blocked' }).expect(503)).body.code).toBe('SOCIAL_PUBLISHING_UNAVAILABLE');
    const inactive = fixture({ assertOwnerActive: async () => { throw new ManagedUploadServiceError(409, 'OWNER_INACTIVE', 'Owner inactive'); } });
    const second = await inactive.create();
    await request(inactive.app).patch(`/posts/${second.id}/caption`).send({ caption: 'Blocked' }).expect(409);
    expect(second.caption).toBe('Old shared');
  });

  it.each([
    [{}, 'INVALID_CAPTION'],
    [{ caption: '' }, 'INVALID_CAPTION'],
    [{ caption: 'Valid', expectedUpdatedAt: null }, 'INVALID_EXPECTED_UPDATED_AT'],
    [{ caption: 'Valid', expectedUpdatedAt: 'not-a-date' }, 'INVALID_EXPECTED_UPDATED_AT'],
    [{ caption: 'Valid', youtubeTitle: 'Wrong platform' }, 'INVALID_YOUTUBE_TITLE']
  ])('rejects malformed caption/title/version bodies (%j)', async (body, code) => {
    const { app, create } = fixture();
    const post = await create();
    expect((await request(app).patch(`/posts/${post.id}/caption`).send(body).expect(400)).body.code).toBe(code);
  });

  it('rechecks the cutoff at the write boundary and reports the closed window', async () => {
    let clock = now;
    const { app, create, store } = fixture({ now: () => new Date(clock) });
    const post = await create();
    const update = store.updateCaption;
    vi.spyOn(store, 'updateCaption').mockImplementation(input => {
      clock = '2026-11-03T00:59:00.000Z';
      return update(input);
    });
    expect((await request(app).patch(`/posts/${post.id}/caption`).send({ caption: 'Too late' }).expect(409)).body.code).toBe('POST_CAPTION_EDIT_WINDOW_CLOSED');
    expect(post.caption).toBe('Old shared');
  });
});
