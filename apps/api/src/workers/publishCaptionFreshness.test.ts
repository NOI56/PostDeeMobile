import { describe, expect, it, vi } from 'vitest';

import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPostStore, type QueuedPost } from '../modules/posts/postStore.js';
import type { PlatformSettings } from '../modules/posts/platformSettings.js';
import {
  createBullMqPublishQueueFromClient,
  type BullMqPublishJobData
} from '../modules/queue/bullMqPublishQueue.js';
import { createPublishScheduler } from './publishScheduler.js';
import {
  createMockPlatformPublisher,
  processPublishJobForPost,
  type PlatformPublishInput
} from './publishWorker.js';

const scheduledAt = '2030-01-01T01:00:00.000Z';
const editNow = '2030-01-01T00:00:00.000Z';
const oldSettings: PlatformSettings = {
  TIKTOK: { publishMode: 'INBOX_DRAFT', caption: 'Old TikTok caption' },
  YOUTUBE_SHORTS: {
    title: 'Old title', caption: 'Old description', visibility: 'unlisted',
    madeForKids: false, containsSyntheticMedia: true, communityGuidelinesCertified: true
  },
  FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT', isAiGenerated: true }
};
const newSettings: PlatformSettings = {
  ...oldSettings,
  TIKTOK: { ...oldSettings.TIKTOK!, caption: 'New TikTok caption' },
  YOUTUBE_SHORTS: { ...oldSettings.YOUTUBE_SHORTS!, title: 'New title', caption: 'New description' }
};

const fixture = async () => {
  const postStore = createPostStore();
  const post = await postStore.create({
    userId: 'caption-owner', caption: 'Old shared caption', scheduledAt,
    videoS3Key: 'uploads/caption-owner/video.mp4',
    coverImageS3Key: 'uploads/caption-owner/cover.jpg', coverFrameTimeMs: 500,
    platforms: ['TIKTOK', 'YOUTUBE_SHORTS', 'FACEBOOK_REELS'],
    platformSettings: structuredClone(oldSettings)
  });
  const original = structuredClone(post);
  const publisher = createMockPlatformPublisher();
  const publish = vi.fn((input: PlatformPublishInput) => publisher.publish(input));
  const save = () => postStore.updateCaption({
    postId: post.id, userId: post.userId,
    expectedScheduledAt: scheduledAt, expectedUpdatedAt: original.updatedAt!,
    caption: 'New shared caption', platformSettings: structuredClone(newSettings), now: () => editNow
  });
  const jobData: BullMqPublishJobData = {
    userId: original.userId, postId: original.id, caption: original.caption,
    videoS3Key: original.videoS3Key, coverImageS3Key: original.coverImageS3Key,
    coverFrameTimeMs: original.coverFrameTimeMs, platforms: original.platforms,
    platformSettings: original.platformSettings, runAt: scheduledAt, status: 'SCHEDULED'
  };
  return { postStore, post, original, publish, save, jobData };
};

const expectSavedContent = (publish: ReturnType<typeof vi.fn>, post: QueuedPost) => {
  expect(publish).toHaveBeenCalledTimes(3);
  for (const [platform, caption] of [
    ['TIKTOK', 'New TikTok caption'],
    ['YOUTUBE_SHORTS', 'New description'],
    ['FACEBOOK_REELS', 'New shared caption']
  ]) {
    expect(publish).toHaveBeenCalledWith(expect.objectContaining({
      platform, caption, platformSettings: newSettings,
      videoS3Key: post.videoS3Key, coverImageS3Key: post.coverImageS3Key,
      coverFrameTimeMs: post.coverFrameTimeMs
    }));
  }
};

describe('scheduled caption edits at the publish boundary', () => {
  it('ignores the old BullMQ enqueue snapshot and publishes the saved caption/settings pair', async () => {
    const { postStore, post, publish, save } = await fixture();
    let queuedData: BullMqPublishJobData | undefined;
    const queue = createBullMqPublishQueueFromClient({
      queue: {
        add: async (_name, data) => { queuedData = structuredClone(data); return { id: 'caption-job' }; },
        getJobs: async () => []
      },
      now: () => Date.parse(editNow)
    });
    await queue.enqueue(post);
    expect(await save()).toBeDefined();
    expect(queuedData?.caption).toBe('Old shared caption');
    expect(queuedData?.platformSettings).toEqual(oldSettings);

    const result = await processPublishJobForPost({
      jobData: queuedData!, postStore, publisher: { publish }
    });

    expectSavedContent(publish, post);
    expect(result.platformResults).toEqual(expect.arrayContaining([
      expect.objectContaining({ platform: 'TIKTOK', deliveryOutcome: 'DRAFT' }),
      expect.objectContaining({ platform: 'FACEBOOK_REELS', deliveryOutcome: 'DRAFT' }),
      expect.objectContaining({ platform: 'YOUTUBE_SHORTS', deliveryOutcome: 'UNLISTED' })
    ]));
    expect((await postStore.findOwned({ postId: post.id, userId: post.userId }))?.status).toBe('PUBLISHED');
  });

  it('uses the saved content when the memory scheduler poll still holds an older snapshot', async () => {
    const { postStore, post, publish, save } = await fixture();
    const polledPosts = structuredClone(await postStore.listDue({ now: scheduledAt }));
    expect(await save()).toBeDefined();
    await createPublishScheduler({
      postStore: { ...postStore, listDue: async () => polledPosts },
      platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish },
      now: () => scheduledAt
    }).runOnce();

    expectSavedContent(publish, post);
  });

  it.each([true, false])('keeps captions and settings coherent when save and claim race (save first: %s)', async (saveFirst) => {
    const { postStore, publish, save, jobData, original } = await fixture();
    const run = () => processPublishJobForPost({ jobData, postStore, publisher: { publish } });
    const savingAndPublishing = saveFirst ? [save(), run()] : [run(), save()];
    const results = await Promise.all(savingAndPublishing);
    const saved = results[saveFirst ? 0 : 1];
    expect(Boolean(saved)).toBe(saveFirst);
    for (const [input] of publish.mock.calls) {
      expect(input.platformSettings).toEqual(saveFirst ? newSettings : oldSettings);
      const expectedCaption = input.platform === 'TIKTOK'
        ? saveFirst ? 'New TikTok caption' : 'Old TikTok caption'
        : input.platform === 'YOUTUBE_SHORTS'
          ? saveFirst ? 'New description' : 'Old description'
          : saveFirst ? 'New shared caption' : original.caption;
      expect(input.caption).toBe(expectedCaption);
    }
    expect(publish).toHaveBeenCalledTimes(3);
  });

  it('does not reuse a stale override when an edit removes a platform caption', async () => {
    const { postStore, post, original, jobData, publish } = await fixture();
    const settings = structuredClone(oldSettings);
    delete settings.TIKTOK!.caption;
    expect(await postStore.updateCaption({
      postId: post.id, userId: post.userId, expectedScheduledAt: scheduledAt,
      expectedUpdatedAt: original.updatedAt!, caption: 'Fresh fallback', platformSettings: settings, now: () => editNow
    })).toBeDefined();
    await processPublishJobForPost({ jobData, postStore, publisher: { publish } });
    expect(publish).toHaveBeenCalledWith(expect.objectContaining({ platform: 'TIKTOK', caption: 'Fresh fallback' }));
  });

  it('sends nothing if the authoritative claimed post cannot be read', async () => {
    const { postStore, jobData, publish } = await fixture();
    await expect(processPublishJobForPost({
      jobData, postStore: { ...postStore, findOwned: async () => undefined }, publisher: { publish }
    })).rejects.toThrow('Claimed publish post is unavailable');
    expect(publish).not.toHaveBeenCalled();
  });
});
