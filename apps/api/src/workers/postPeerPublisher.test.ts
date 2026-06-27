import { afterEach, describe, expect, it, vi } from 'vitest';

import { readServerConfig } from '../config/env.js';
import { createInMemorySocialConnectionStore } from '../modules/socialConnections/socialConnectionStore.js';
import type { VideoStorage } from '../modules/storage/videoStorage.js';
import { createPlatformPublisherFromConfig } from './platformPublisherFactory.js';
import { createPostPeerPublisher } from './postPeerPublisher.js';

const createTestVideoStorage = (): VideoStorage => ({
  createUpload: async () => {
    throw new Error('createUpload is not used by PostPeer publishing');
  },
  createDownloadAccess: async (videoS3Key) => ({
    videoS3Key,
    storageProvider: 'r2',
    accessType: 'signed-url',
    downloadUrl: `https://r2.test/signed/${encodeURIComponent(videoS3Key)}`,
    downloadMethod: 'GET',
    downloadExpiresAt: '2026-06-24T12:00:00.000Z'
  }),
  deleteVideo: async () => undefined
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('createPostPeerPublisher', () => {
  it('resolves a PostPeer account id from the post owner before publishing', async () => {
    const calls: { body: unknown }[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      resolveAccountId: async ({ userId, platform }) => {
        expect(userId).toBe('seller-1');
        expect(platform).toBe('TIKTOK');
        return 'acct-user-tiktok';
      },
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: 'postpeer-post-1' })
        };
      }
    });

    await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: 'hello',
      videoS3Key: 'https://cdn.test/video.mp4',
      platform: 'TIKTOK'
    });

    expect(calls[0].body).toMatchObject({
      platforms: [{ platform: 'tiktok', accountId: 'acct-user-tiktok' }]
    });
  });

  it('does not fall back to operator account ids when a user resolver is present', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'operator-tiktok' },
      resolveAccountId: async () => undefined,
      fetchImpl: async () => {
        throw new Error('fetch should not run when the user connection is missing');
      }
    });

    await expect(
      publisher.publish({
        userId: 'seller-2',
        postId: 'post-1',
        caption: 'hello',
        videoS3Key: 'https://cdn.test/video.mp4',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(/Connected PostPeer account is required/);
  });

  it('posts to PostPeer and returns the external post id', async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: {
        TIKTOK: 'postpeer-tiktok'
      },
      resolveVideoUrl: (key) => `https://cdn.test/${key}`,
      now: () => '2026-06-17T00:00:00.000Z',
      fetchImpl: async (url, init) => {
        calls.push({ url, init });
        return {
          ok: true,
          status: 202,
          json: async () => ({
            success: true,
            status: 'published',
            postId: 'postpeer-post-1',
            platforms: [
              {
                platform: 'tiktok',
                success: true,
                platformPostUrl: 'https://tiktok.test/@postdee/video/123'
              }
            ]
          })
        };
      }
    });

    const result = await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: 'hello',
      videoS3Key: 'uploads/clip.mp4',
      platform: 'TIKTOK'
    });

    expect(result).toEqual({
      platform: 'TIKTOK',
      status: 'PUBLISHED',
      externalPostId: 'https://tiktok.test/@postdee/video/123',
      publishedAt: '2026-06-17T00:00:00.000Z'
    });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://api.postpeer.test/v1/posts');
    const body = JSON.parse(calls[0].init.body as string);
    expect(body).toEqual({
      content: 'hello',
      platforms: [{ platform: 'tiktok', accountId: 'postpeer-tiktok' }],
      mediaItems: [{ type: 'video', url: 'https://cdn.test/uploads/clip.mp4' }],
      publishNow: true
    });
    const headers = calls[0].init.headers as Record<string, string>;
    expect(headers['x-access-key']).toBe('pp-key');
    expect(headers.Authorization).toBeUndefined();
  });

  it('throws when PostPeer responds with an error', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: {
        YOUTUBE_SHORTS: 'postpeer-youtube'
      },
      fetchImpl: async () => ({ ok: false, status: 502, json: async () => ({}) })
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'YOUTUBE_SHORTS'
      })
    ).rejects.toThrow(/PostPeer publish to YOUTUBE_SHORTS failed with status 502/);
  });

  it('throws when PostPeer reports the selected platform failed', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: {
        TIKTOK: 'postpeer-tiktok'
      },
      fetchImpl: async () => ({
        ok: true,
        status: 202,
        json: async () => ({
          success: true,
          status: 'partial',
          postId: 'postpeer-post-1',
          platforms: [
            {
              platform: 'tiktok',
              success: false,
              error: 'Video URL is not publicly accessible'
            }
          ]
        })
      })
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(
      /PostPeer publish to TIKTOK failed: Video URL is not publicly accessible/
    );
  });
});

describe('createPlatformPublisherFromConfig', () => {
  it('uses the mock publisher by default', async () => {
    const config = readServerConfig({});
    const publisher = createPlatformPublisherFromConfig({ config });

    const result = await publisher.publish({ postId: 'p1', platform: 'TIKTOK' });
    expect(result.status).toBe('PUBLISHED');
    expect(result.externalPostId).toContain('mock-tiktok');
  });

  it('requires an API key when SOCIAL_PUBLISHER is postpeer', () => {
    const config = readServerConfig({ SOCIAL_PUBLISHER: 'postpeer' });

    expect(() => createPlatformPublisherFromConfig({ config })).toThrow(
      /POSTPEER_API_KEY is required/
    );
  });

  it('builds a PostPeer publisher when configured', () => {
    const config = readServerConfig({
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'pp-key',
      POSTPEER_TIKTOK_ACCOUNT_ID: 'postpeer-tiktok'
    });

    expect(() =>
      createPlatformPublisherFromConfig({
        config,
        videoStorage: createTestVideoStorage()
      })
    ).not.toThrow();
  });

  it('requires video storage when SOCIAL_PUBLISHER is postpeer', () => {
    const config = readServerConfig({
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'pp-key',
      POSTPEER_TIKTOK_ACCOUNT_ID: 'postpeer-tiktok'
    });

    expect(() => createPlatformPublisherFromConfig({ config })).toThrow(
      /VideoStorage is required/
    );
  });

  it('sends a signed video URL from storage to PostPeer', async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return {
        ok: true,
        status: 200,
        json: async () => ({ externalPostId: 'pp-123' })
      };
    });

    const config = readServerConfig({
      SOCIAL_PUBLISHER: 'postpeer',
      POSTPEER_API_KEY: 'pp-key',
      POSTPEER_TIKTOK_ACCOUNT_ID: 'postpeer-tiktok'
    });
    const publisher = createPlatformPublisherFromConfig({
      config,
      videoStorage: createTestVideoStorage()
    });

    await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: 'hello',
      videoS3Key: 'uploads/clip.mp4',
      platform: 'TIKTOK'
    });

    const body = JSON.parse(calls[0].init.body as string);
    expect(body.mediaItems).toEqual([
      { type: 'video', url: 'https://r2.test/signed/uploads%2Fclip.mp4' }
    ]);
  });

  it('uses the social connection store account id for PostPeer publishing', async () => {
    const calls: { body: unknown }[] = [];
    vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
      calls.push({ body: JSON.parse(String(init.body)) });
      return {
        ok: true,
        status: 200,
        json: async () => ({ externalPostId: 'pp-123' })
      };
    });

    const socialConnectionStore = createInMemorySocialConnectionStore();
    await socialConnectionStore.upsert({
      userId: 'seller-a',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-seller-a-tiktok'
    });
    await socialConnectionStore.upsert({
      userId: 'seller-b',
      platform: 'TIKTOK',
      postPeerAccountId: 'acct-seller-b-tiktok'
    });

    const publisher = createPlatformPublisherFromConfig({
      config: readServerConfig({
        SOCIAL_PUBLISHER: 'postpeer',
        POSTPEER_API_KEY: 'pp-key'
      }),
      videoStorage: createTestVideoStorage(),
      socialConnectionStore
    });

    await publisher.publish({
      userId: 'seller-a',
      postId: 'post-1',
      videoS3Key: 'uploads/clip.mp4',
      platform: 'TIKTOK'
    });

    expect(calls[0].body).toMatchObject({
      platforms: [{ platform: 'tiktok', accountId: 'acct-seller-a-tiktok' }]
    });
  });

  it('requires a PostPeer account id for the selected platform', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: {}
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(/POSTPEER_TIKTOK_ACCOUNT_ID is required/);
  });
});
