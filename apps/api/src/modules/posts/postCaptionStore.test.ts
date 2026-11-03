import { describe, expect, it, vi } from 'vitest';
import { createPostStore } from './postStore.js';
import { createPrismaPostRepository } from './prismaPostRepository.js';
import { withPostRepositoryFixture } from '../../../test/repositoryFixtures.js';

const scheduledAt = '2026-11-03T01:00:00.000Z';
const now = '2026-11-03T00:00:00.000Z';
const platformSettings = { INSTAGRAM_REELS: { shareToFeed: false, caption: 'New Instagram' } };

describe('caption compare-and-set stores', () => {
  it('updates a complete caption/settings pair once, preserving unrelated fields and rejecting stale snapshots', async () => {
    const store = createPostStore();
    const post = await store.create({ userId: 'owner', caption: 'Old', videoS3Key: 'uploads/owner/v.mp4',
      platforms: ['INSTAGRAM_REELS'], scheduledAt });
    const originalUpdatedAt = post.updatedAt!;
    const input = { postId: post.id, userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: originalUpdatedAt, caption: 'New shared', platformSettings, now: () => now };
    const [first, stale] = await Promise.all([store.updateCaption(input), store.updateCaption({ ...input, caption: 'Stale' })]);
    expect(first).toMatchObject({ caption: 'New shared', platformSettings, videoS3Key: post.videoS3Key, scheduledAt });
    expect(first?.updatedAt).not.toBe(originalUpdatedAt);
    expect(stale).toBeUndefined();
    platformSettings.INSTAGRAM_REELS.caption = 'Caller mutated its object';
    expect(first?.platformSettings?.INSTAGRAM_REELS?.caption).toBe('New Instagram');
    platformSettings.INSTAGRAM_REELS.caption = 'New Instagram';
  });

  it.each(['owner', 'schedule', 'status', 'window'] as const)('checks %s at the mutation boundary', async (changed) => {
    const store = createPostStore();
    const post = await store.create({ userId: 'owner', caption: 'Old', videoS3Key: 'uploads/owner/v.mp4',
      platforms: ['INSTAGRAM_REELS'], scheduledAt });
    const input = { postId: post.id, userId: changed === 'owner' ? 'other' : 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: post.updatedAt!, caption: 'New', platformSettings, now: () => changed === 'window' ? '2026-11-03T00:59:00.000Z' : now };
    if (changed === 'schedule') await store.reschedule({ postId: post.id, userId: 'owner', scheduledAt: '2026-11-04T01:00:00.000Z' });
    if (changed === 'status') await store.claimForPublish({ postId: post.id, expectedRunAt: scheduledAt });
    expect(await store.updateCaption(input)).toBeUndefined();
    expect(post.caption).toBe('Old');
  });

  it('preserves memory settings when an internal caller omits the optional settings update', async () => {
    const store = createPostStore();
    const post = await store.create({ userId: 'owner', caption: 'Old', videoS3Key: 'uploads/owner/v.mp4',
      platforms: ['INSTAGRAM_REELS'], scheduledAt, platformSettings });
    const updated = await store.updateCaption({ postId: post.id, userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: post.updatedAt!, caption: 'New shared', now: () => now });
    expect(updated?.platformSettings).toEqual(platformSettings);
  });

  it('preserves Prisma JSON when an internal caller omits the optional settings update', async () => {
    const updateMany = vi.fn().mockResolvedValue({ count: 0 });
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({
      $queryRaw: vi.fn().mockResolvedValue([{ id: 'post' }]), post: { updateMany } }) });
    await repository.updateCaption({ postId: 'post', userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: now, caption: 'New shared', now: () => now });
    expect(updateMany.mock.calls[0][0].data).not.toHaveProperty('platformSettings');
  });

  it('does not allow an edit after a successful claim, and a successful edit is the full claimed snapshot', async () => {
    const store = createPostStore();
    const make = () => store.create({ userId: 'owner', caption: 'Old', videoS3Key: 'uploads/owner/v.mp4',
      platforms: ['INSTAGRAM_REELS'], scheduledAt });
    const first = await make();
    const input = { userId: 'owner', expectedScheduledAt: scheduledAt, caption: 'New', platformSettings, now: () => now };
    await store.updateCaption({ ...input, postId: first.id, expectedUpdatedAt: first.updatedAt! });
    expect(await store.claimForPublish({ postId: first.id, expectedRunAt: scheduledAt })).toBe(true);
    expect(await store.findOwned({ postId: first.id, userId: 'owner' })).toMatchObject({ caption: 'New', platformSettings, status: 'PUBLISHING' });
    const second = await make();
    const version = second.updatedAt!;
    await store.claimForPublish({ postId: second.id, expectedRunAt: scheduledAt });
    expect(await store.updateCaption({ ...input, postId: second.id, expectedUpdatedAt: version })).toBeUndefined();
    expect(second.caption).toBe('Old');
  });

  it.each([0, 1])('Prisma CAS includes owner/status/schedule/version and writes only caption/settings/version (count=%s)', async count => {
    const originalUpdatedAt = '2026-11-02T00:00:00.000Z';
    const updateMany = vi.fn().mockResolvedValue({ count });
    const findFirst = vi.fn().mockResolvedValue({ id: 'post', userId: 'owner', caption: 'New', videoS3Key: 'uploads/owner/v.mp4',
      selectedPlatforms: ['INSTAGRAM_REELS'], platformSettings, scheduledAt: new Date(scheduledAt), status: 'QUEUED',
      publishedAt: null, createdAt: new Date(now), updatedAt: new Date(now) });
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({
      $queryRaw: vi.fn().mockResolvedValue([{ id: 'post' }]), post: { updateMany, findFirst } }) });
    const result = await repository.updateCaption({ postId: 'post', userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: originalUpdatedAt, caption: 'New', platformSettings, now: () => now });
    expect(updateMany).toHaveBeenCalledWith({
      where: { id: 'post', userId: 'owner', status: 'QUEUED', scheduledAt: new Date(scheduledAt), updatedAt: new Date(originalUpdatedAt) },
      data: { caption: 'New', platformSettings, updatedAt: expect.any(Date) }
    });
    if (count === 0) {
      expect(result).toBeUndefined();
      expect(findFirst).not.toHaveBeenCalled();
    } else {
      expect(result).toMatchObject({ caption: 'New', platformSettings, updatedAt: now });
      expect(findFirst).toHaveBeenCalledWith({ where: { id: 'post', userId: 'owner' } });
    }
  });

  it('Prisma waits for the post row lock before evaluating the edit cutoff', async () => {
    let release!: (rows: Array<{ id: string }>) => void;
    const lock = new Promise<Array<{ id: string }>>(resolve => { release = resolve; });
    const updateMany = vi.fn();
    const clock = vi.fn(() => '2026-11-03T00:59:00.000Z');
    const queryRaw = vi.fn().mockImplementation(() => lock);
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({ $queryRaw: queryRaw, post: { updateMany } }) });
    const edit = repository.updateCaption({ postId: 'post', userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: now, caption: 'Too late', platformSettings, now: clock });
    await vi.waitFor(() => expect(queryRaw).toHaveBeenCalledOnce());
    expect(clock).not.toHaveBeenCalled();
    expect(updateMany).not.toHaveBeenCalled();
    release([{ id: 'post' }]);
    expect(await edit).toBeUndefined();
    expect(clock).toHaveBeenCalledOnce();
    expect(updateMany).not.toHaveBeenCalled();
  });

  it.each(['40001', '40P01'])('treats a raw SQL serialization/deadlock conflict as a lost CAS (%s)', async code => {
    const updateMany = vi.fn();
    const repository = createPrismaPostRepository({ prisma: withPostRepositoryFixture({
      $queryRaw: vi.fn().mockRejectedValue({ code: 'P2010', meta: { code } }), post: { updateMany } }) });
    expect(await repository.updateCaption({ postId: 'post', userId: 'owner', expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: now, caption: 'Conflict', now: () => now })).toBeUndefined();
    expect(updateMany).not.toHaveBeenCalled();
  });
});
