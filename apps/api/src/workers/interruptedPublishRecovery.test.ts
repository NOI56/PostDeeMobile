import { describe, expect, it, vi } from 'vitest';

import { createPostStore } from '../modules/posts/postStore.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { reconcileInterruptedPublishes } from './interruptedPublishRecovery.js';

const createInterruptedPost = async () => {
  const postStore = createPostStore();
  const post = await postStore.create({
    userId: 'seller-recovery', caption: 'private caption', videoS3Key: 'private.mp4',
    platforms: ['TIKTOK', 'YOUTUBE_SHORTS']
  });
  await postStore.claimForPublish({ postId: post.id, expectedRunAt: post.createdAt });
  return { postStore, post };
};

describe('interrupted publish recovery', () => {
  it.each(['PUBLISHED', 'PARTIAL_PUBLISHED', 'FAILED'] as const)('restores %s from complete saved platform results', async (status) => {
    const { postStore, post } = await createInterruptedPost();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    await platformPublishStore.recordResults({
      postId: post.id,
      results: post.platforms.map((platform, index) =>
        status === 'PUBLISHED' || (status === 'PARTIAL_PUBLISHED' && index === 0)
          ? { platform, status: 'PUBLISHED' as const, externalPostId: `receipt-${index}`, deliveryOutcome: 'PRIVATE' as const, publishedAt: '2026-10-05T00:00:00.000Z' }
          : { platform, status: 'FAILED' as const, errorMessage: 'safe failure' }
      )
    });
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore }))
      .toEqual({ recovered: 1, requiresReconciliation: 0 });
    expect(post.status).toBe(status);
    expect(post.publishedAt).toBe(status === 'FAILED' ? undefined : '2026-10-05T00:00:00.000Z');
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore }))
      .toEqual({ recovered: 0, requiresReconciliation: 0 });
  });

  it('leaves missing or incomplete outcomes untouched and creates no failure receipts', async () => {
    const { postStore, post } = await createInterruptedPost();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const recordResults = vi.spyOn(platformPublishStore, 'recordResults');
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore }))
      .toEqual({ recovered: 0, requiresReconciliation: 1 });
    await platformPublishStore.recordResults({
      postId: post.id, results: [{ platform: 'TIKTOK', status: 'FAILED', errorMessage: 'safe failure' }]
    });
    recordResults.mockClear();
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore }))
      .toEqual({ recovered: 0, requiresReconciliation: 1 });
    expect(post.status).toBe('PUBLISHING');
    expect(recordResults).not.toHaveBeenCalled();
  });

  it('does not overwrite a status changed while recovery was inspecting records', async () => {
    const { postStore, post } = await createInterruptedPost();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const listForPostIds = async () => {
      await postStore.updateStatus({ postId: post.id, status: 'FAILED' });
      return post.platforms.map((platform) => ({
        postId: post.id, platform, status: 'PUBLISHED' as const, externalPostId: 'receipt',
        deliveryOutcome: 'LIVE' as const, publishedAt: '2026-10-05T00:00:00.000Z', views: 0, likes: 0
      }));
    };
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore: { ...platformPublishStore, listForPostIds } }))
      .toEqual({ recovered: 0, requiresReconciliation: 0 });
    expect(post.status).toBe('FAILED');
  });

  it.each(['missing receipt', 'invalid timestamp', 'pending result', 'missing outcome'])('does not guess a terminal outcome from %s', async (problem) => {
    const { postStore, post } = await createInterruptedPost();
    const platformPublishStore = createInMemoryPlatformPublishStore();
    const listForPostIds = async () => post.platforms.map((platform) => ({
      postId: post.id, platform,
      status: problem === 'pending result' ? 'PENDING' as const : 'PUBLISHED' as const,
      externalPostId: problem === 'missing receipt' ? undefined : 'receipt',
      deliveryOutcome: problem === 'missing outcome' ? undefined : 'PRIVATE' as const,
      publishedAt: problem === 'invalid timestamp' ? 'invalid' : '2026-10-05T00:00:00.000Z',
      views: 0, likes: 0
    }));
    expect(await reconcileInterruptedPublishes({ postStore, platformPublishStore: { ...platformPublishStore, listForPostIds } }))
      .toEqual({ recovered: 0, requiresReconciliation: 1 });
    expect(post.status).toBe('PUBLISHING');
  });
});
