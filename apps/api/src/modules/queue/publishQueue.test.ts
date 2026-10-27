import { describe, expect, it } from 'vitest';

import type { QueuedPost } from '../posts/postStore.js';
import { createInMemoryPublishQueue } from './publishQueue.js';

const queuedPost = (id: string): QueuedPost => ({
  id,
  userId: 'seller-queue',
  caption: 'caption',
  videoS3Key: 'uploads/seller-queue/clip.mp4',
  platforms: ['TIKTOK'],
  status: 'QUEUED',
  createdAt: '2026-10-26T00:00:00.000Z'
});

describe('createInMemoryPublishQueue', () => {
  it('removes a job from a very large queue without overflowing the stack', async () => {
    const queue = createInMemoryPublishQueue();

    for (let index = 0; index < 300_000; index += 1) {
      await queue.enqueue(queuedPost(`post-${index}`));
    }

    await expect(queue.remove('post-0')).resolves.toBeUndefined();
    expect((await queue.list()).length).toBe(299_999);
  });
});
