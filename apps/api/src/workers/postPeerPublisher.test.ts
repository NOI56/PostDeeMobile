import { afterEach, describe, expect, it, vi } from 'vitest';

import { readServerConfig } from '../config/env.js';
import { createInMemorySocialConnectionStore } from '../modules/socialConnections/socialConnectionStore.js';
import type { VideoStorage } from '../modules/storage/videoStorage.js';
import { createPlatformPublisherFromConfig } from './platformPublisherFactory.js';
import {
  PostPeerPublishOutcomeUnknownError,
  createPostPeerPublisher
} from './postPeerPublisher.js';
import { PublishOutcomeUnknownError } from './publishWorker.js';

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
          json: async () => ({ externalPostId: 'postpeer-platform-post-1' })
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

  it('requires the post owner to connect an account instead of falling back to the operator id', async () => {
    const calls: { body: unknown }[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'operator-tiktok' },
      resolveAccountId: async () => undefined,
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: 'postpeer-post-1' })
        };
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
    ).rejects.toThrow(/Connected PostPeer account is required to publish TIKTOK/);

    expect(calls).toEqual([]);
  });

  it('requires a connected owner account when the resolver finds none', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      resolveAccountId: async () => undefined,
      fetchImpl: async () => {
        throw new Error('fetch should not run when no account id is available');
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
    ).rejects.toThrow(/Connected PostPeer account is required to publish TIKTOK/);
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
      platforms: [
        {
          platform: 'tiktok',
          accountId: 'postpeer-tiktok',
          platformSpecificData: {
            privacyLevel: 'SELF_ONLY',
            draft: false
          }
        }
      ],
      mediaItems: [{ type: 'video', url: 'https://cdn.test/uploads/clip.mp4' }],
      publishNow: true
    });
    const headers = calls[0].init.headers as Record<string, string>;
    expect(headers['x-access-key']).toBe('pp-key');
    expect(headers.Authorization).toBeUndefined();
  });

  it('polls an accepted PostPeer post until the selected platform is published', async () => {
    const calls: { url: string; method?: string }[] = [];
    const responses = [
      {
        ok: true,
        status: 202,
        json: async () => ({
          success: true,
          status: 'publishing',
          postId: 'postpeer-post-1',
          platforms: [{ platform: 'tiktok', success: true }]
        })
      },
      {
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          post: {
            postId: 'postpeer-post-1',
            status: 'pending',
            platforms: [{ platform: 'tiktok', status: 'pending' }]
          }
        })
      },
      {
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          post: {
            postId: 'postpeer-post-1',
            status: 'published',
            platforms: [
              {
                platform: 'tiktok',
                status: 'published',
                platformPostId: 'tiktok-video-123',
                platformPostUrl: 'https://tiktok.test/@postdee/video/123'
              }
            ]
          }
        })
      }
    ];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      pollIntervalMs: 0,
      maxPollAttempts: 3,
      fetchImpl: async (url, init) => {
        calls.push({ url, method: init.method });
        const response = responses.shift();

        if (!response) {
          throw new Error('Unexpected extra PostPeer request');
        }

        return response;
      }
    });

    const result = await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      videoS3Key: 'uploads/clip.mp4',
      platform: 'TIKTOK'
    });

    expect(result.externalPostId).toBe('https://tiktok.test/@postdee/video/123');
    expect(calls).toEqual([
      { url: 'https://api.postpeer.test/v1/posts', method: 'POST' },
      { url: 'https://api.postpeer.test/v1/posts/postpeer-post-1', method: 'GET' },
      { url: 'https://api.postpeer.test/v1/posts/postpeer-post-1', method: 'GET' }
    ]);
  });

  it('preserves an outer status and post id when the response also contains a nested post', async () => {
    const urls: string[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      pollIntervalMs: 0,
      maxPollAttempts: 1,
      fetchImpl: async (url) => {
        urls.push(url);

        if (url.endsWith('/v1/posts')) {
          return {
            ok: true,
            status: 202,
            json: async () => ({
              success: true,
              status: 'publishing',
              postId: 'postpeer-outer-id',
              post: {
                platforms: [{ platform: 'tiktok', status: 'publishing' }]
              }
            })
          };
        }

        return {
          ok: true,
          status: 200,
          json: async () => ({
            success: true,
            post: {
              status: 'published',
              platforms: [
                {
                  platform: 'tiktok',
                  status: 'published',
                  platformPostId: 'tiktok-video-123'
                }
              ]
            }
          })
        };
      }
    });

    const result = await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      platform: 'TIKTOK'
    });

    expect(result.externalPostId).toBe('tiktok-video-123');
    expect(urls).toEqual([
      'https://api.postpeer.test/v1/posts',
      'https://api.postpeer.test/v1/posts/postpeer-outer-id'
    ]);
  });

  it('fails closed when an accepted PostPeer post never reaches a final status', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      pollIntervalMs: 0,
      maxPollAttempts: 2,
      fetchImpl: async (url) => ({
        ok: true,
        status: url.endsWith('/v1/posts') ? 202 : 200,
        json: async () =>
          url.endsWith('/v1/posts')
            ? {
                success: true,
                status: 'publishing',
                postId: 'postpeer-post-1'
              }
            : {
                success: true,
                post: {
                  postId: 'postpeer-post-1',
                  status: 'publishing',
                  platforms: [{ platform: 'tiktok', status: 'publishing' }]
                }
              }
      })
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(/outcome is still unknown after 2 status checks/i);
  });

  it('does not report published without a real platform URL or id', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      fetchImpl: async () => ({
        ok: true,
        status: 202,
        json: async () => ({
          success: true,
          status: 'published',
          postId: 'postpeer-post-1',
          platforms: [{ platform: 'tiktok', success: true }]
        })
      })
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(/did not return a platform post URL or id/i);
  });

  it('sends a derived private YouTube title for controlled-first publishing', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { YOUTUBE_SHORTS: 'postpeer-youtube' },
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 202,
          json: async () => ({
            success: true,
            status: 'published',
            postId: 'postpeer-post-1',
            platforms: [
              {
                platform: 'youtube',
                success: true,
                platformPostId: 'youtube-video-123'
              }
            ]
          })
        };
      }
    });

    await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: '  รีวิวสินค้าใหม่\nพร้อมโปรโมชันวันนี้  ',
      platform: 'YOUTUBE_SHORTS'
    });

    expect(calls[0].body).toMatchObject({
      platforms: [
        {
          platform: 'youtube',
          accountId: 'postpeer-youtube',
          platformSpecificData: {
            title: 'รีวิวสินค้าใหม่ พร้อมโปรโมชันวันนี้',
            visibility: 'private'
          }
        }
      ]
    });
  });

  it('uses a safe YouTube title when the caption is empty', async () => {
    let requestBody: Record<string, unknown> | undefined;
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { YOUTUBE_SHORTS: 'postpeer-youtube' },
      fetchImpl: async (_url, init) => {
        requestBody = JSON.parse(String(init.body));
        return {
          ok: true,
          status: 202,
          json: async () => ({
            success: true,
            status: 'published',
            postId: 'postpeer-post-1',
            platforms: [
              {
                platform: 'youtube',
                status: 'published',
                platformPostId: 'youtube-video-123'
              }
            ]
          })
        };
      }
    });

    await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: '   ',
      platform: 'YOUTUBE_SHORTS'
    });

    expect(requestBody).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            title: 'PostDee video',
            visibility: 'private'
          }
        }
      ]
    });
  });

  it('fails when PostPeer reports a top-level unsuccessful result', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      fetchImpl: async () => ({
        ok: true,
        status: 202,
        json: async () => ({
          success: false,
          status: 'failed',
          error: 'Publishing is unavailable'
        })
      })
    });

    await expect(
      publisher.publish({
        userId: 'seller-1',
        postId: 'post-1',
        platform: 'TIKTOK'
      })
    ).rejects.toThrow(/PostPeer publish to TIKTOK failed: Publishing is unavailable/);
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

  it('marks a create-request network failure as an unknown outcome to prevent duplicates', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      fetchImpl: async () => {
        throw new Error('connection reset');
      }
    });

    const publishAttempt = publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      platform: 'TIKTOK'
    });

    await expect(publishAttempt).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    await expect(publishAttempt).rejects.toBeInstanceOf(PublishOutcomeUnknownError);
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
              status: 'failed',
              errorMessage: 'Video URL is not publicly accessible'
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

  it('fails closed without calling a provider when publishing is disabled', async () => {
    const config = readServerConfig({ SOCIAL_PUBLISHER: 'disabled' });
    const publisher = createPlatformPublisherFromConfig({ config });

    await expect(
      publisher.publish({ postId: 'p-disabled', platform: 'TIKTOK' })
    ).rejects.toThrow(/disabled for this environment/i);
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
