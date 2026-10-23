import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from '../app.js';
import { createPostStore } from '../modules/posts/postStore.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import { createPublishScheduler } from '../workers/publishScheduler.js';
import { createSentryMonitoring } from './sentryMonitoring.js';

const config = { dsn: 'https://public123@o123.ingest.us.sentry.io/123456', environment: 'staging' as const };
const setupReporter = async () => {
  const capture = vi.fn();
  await createSentryMonitoring(config, { initialize: async () => ({ captureException: capture, flush: async () => true }) });
  return capture;
};

afterEach(async () => {
  await createSentryMonitoring(undefined);
  vi.restoreAllMocks();
});

describe('Sentry product failure hooks', () => {
  it.each(['/captions/generate', '/captions/generate-from-clip'])(
    'reports provider fallback in %s while preserving the usable response', async (endpoint) => {
      const capture = await setupReporter();
      vi.spyOn(console, 'error').mockImplementation(() => undefined);
      const failingProvider = { generate: async () => { throw new Error('private-provider-message'); } };
      const app = createApp({
        captionGenerator: failingProvider, realClipCaptionProvider: failingProvider,
        fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' })
      });
      const response = await request(app).post(endpoint)
        .set('x-postdee-user-id', 'private-owner')
        .set('x-postdee-subscription-plan', 'PRO')
        .send(endpoint.endsWith('from-clip')
          ? { videoS3Key: 'uploads/private-owner/clip/video.mp4' }
          : { keywords: ['สินค้า'] }).expect(200);
      expect(response.body.isFallback).toBe(true);
      expect(capture).toHaveBeenCalledOnce();
      expect(capture.mock.calls[0]?.[1]).toEqual({ tags: { component: 'api', operation: 'captions.provider' } });
    }
  );

  it('reports a visual planning fallback without losing the audio plan', async () => {
    const capture = await setupReporter();
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const app = createApp({
      editPlanProvider: { plan: async () => ({ cuts: [{ start: 0, end: 10 }], summary: 'fixture', model: 'audio-fallback' }) },
      visualEditPlanProvider: { plan: async () => { throw new Error('private-provider-message'); } },
      fetchClipMedia: async () => ({ data: new Uint8Array([1]), mimeType: 'video/mp4' })
    });
    const response = await request(app).post('/ai-edits/plan')
      .set('x-postdee-subscription-plan', 'PRO')
      .send({ durationSeconds: 20, targetDurationSeconds: 10,
        segments: [{ text: 'fixture', start: 0, end: 20 }],
        visualProxyS3Key: 'uploads/local-dev-user/proxy/visual-proxy.mp4' }).expect(200);
    expect(response.body.plan.model).toBe('audio-fallback');
    expect(capture).toHaveBeenCalledOnce();
    expect(capture.mock.calls[0]?.[1]).toEqual({ tags: { component: 'api', operation: 'ai.planning' } });
  });

  it('records a failed poll and keeps the scheduler rejection and readiness safeguards', async () => {
    const capture = await setupReporter();
    const postStore = createPostStore();
    vi.spyOn(postStore, 'listDue').mockRejectedValue(new Error('private-database-url'));
    const scheduler = createPublishScheduler({ postStore, platformPublishStore: createInMemoryPlatformPublishStore() });
    await expect(scheduler.runOnce()).rejects.toThrow('private-database-url');
    expect(capture).toHaveBeenCalledOnce();
    expect(capture.mock.calls[0]?.[1]).toEqual({ tags: { component: 'api', operation: 'scheduler.poll' } });
    await expect(scheduler.checkReady!()).rejects.toThrow('Publish scheduler unavailable');
  });

  it('records per-post admission failures without resending or changing due posts', async () => {
    const capture = await setupReporter();
    const postStore = createPostStore();
    const post = await postStore.create({ userId: 'private-owner', caption: 'private-caption',
      videoS3Key: 'private-video.mp4', platforms: ['TIKTOK'] });
    const publish = vi.fn();
    const scheduler = createPublishScheduler({ postStore,
      platformPublishStore: createInMemoryPlatformPublishStore(), publisher: { publish },
      runWithActiveOwner: async () => { throw new Error('private-owner-admission'); }
    });
    await expect(scheduler.runOnce()).resolves.toBeUndefined();
    expect(post.status).toBe('QUEUED');
    expect(publish).not.toHaveBeenCalled();
    expect(capture).toHaveBeenCalledOnce();
    expect(capture.mock.calls[0]?.[1]).toEqual({ tags: { component: 'api', operation: 'scheduler.process' } });
  });
});
