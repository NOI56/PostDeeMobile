import { afterEach, describe, expect, it, vi } from 'vitest';

import { readServerConfig } from '../config/env.js';
import { createInMemorySocialConnectionStore } from '../modules/socialConnections/socialConnectionStore.js';
import type { VideoStorage } from '../modules/storage/videoStorage.js';
import { createPlatformPublisherFromConfig } from './platformPublisherFactory.js';
import {
  PostPeerPublishOutcomeUnknownError,
  createPostPeerPublisher
} from './postPeerPublisher.js';
import { PublishOutcomeUnknownError, processPublishJob } from './publishWorker.js';

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
  deleteVideo: async () => undefined,
  deleteAllVideosForOwner: async () => undefined
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('createPostPeerPublisher', () => {
  it.each(['', '   '])('sends an explicitly empty YouTube description instead of the shared caption (%j)', async (caption) => {
    const requests: Record<string, unknown>[] = [];
    const publisher = createPostPeerPublisher({ apiKey: 'key', baseUrl: 'https://api.postpeer.test',
      accountIds: { YOUTUBE_SHORTS: 'youtube-account' },
      fetchImpl: async (_url, init) => {
        requests.push(JSON.parse(String(init.body)));
        return { ok: true, status: 200, json: async () => ({ externalPostId: 'video' }) };
      } });
    await publisher.publish({ userId: 'owner', postId: 'post', platform: 'YOUTUBE_SHORTS',
      caption: 'Shared text < which must not become a YouTube description >',
      platformSettings: { YOUTUBE_SHORTS: { title: 'Title only', visibility: 'private',
        madeForKids: false, containsSyntheticMedia: false, communityGuidelinesCertified: true, caption } } });
    expect(requests[0]).toMatchObject({ content: '', platforms: [{ platformSpecificData: { title: 'Title only' } }] });
  });

  it.each(['INSTAGRAM_REELS', 'FACEBOOK_REELS', 'YOUTUBE_SHORTS'] as const)(
    'sends only the effective %s text and validates it before provider reads', async (platform) => {
      const calls: Record<string, unknown>[] = [];
      const fetchImpl = vi.fn(async (_url, init) => {
        calls.push(JSON.parse(String(init.body)));
        return { ok: true, status: 200, json: async () => ({ externalPostId: 'video' }) };
      });
      const publisher = createPostPeerPublisher({ apiKey: 'key', baseUrl: 'https://api.postpeer.test',
        accountIds: { [platform]: 'account' }, fetchImpl });
      const baseSettings = platform === 'INSTAGRAM_REELS' ? { shareToFeed: true }
        : platform === 'FACEBOOK_REELS' ? { publishMode: 'PUBLISH' } : { visibility: 'private' };
      await publisher.publish({ userId: 'owner', postId: 'post', platform, caption: 'unused < shared >',
        videoS3Key: 'https://cdn.test/video.mp4',
        platformSettings: { [platform]: { ...baseSettings, caption: 'Destination text' } } });
      expect(calls[0].content).toBe('Destination text');
      const tooLong = platform === 'YOUTUBE_SHORTS' ? 'ก'.repeat(1667)
        : 'a'.repeat(platform === 'INSTAGRAM_REELS' ? 2201 : 63207);
      await expect(publisher.publish({ userId: 'owner', postId: 'post', platform, caption: 'valid',
        platformSettings: { [platform]: { ...baseSettings, caption: tooLong } } }))
        .rejects.toMatchObject({ code: 'PLATFORM_CAPTION_INVALID', issue: { platform } });
      expect(fetchImpl).toHaveBeenCalledTimes(1);
    }
  );

  it.each(['', 'คำอธิบายเต็ม\nพร้อมรายละเอียด #สินค้า'])(
    'preserves the full description independently of an explicit YouTube title (%j)', async (caption) => {
      let requestBody: Record<string, unknown> | undefined;
      const publisher = createPostPeerPublisher({
        apiKey: 'test-key', baseUrl: 'https://api.postpeer.test',
        accountIds: { YOUTUBE_SHORTS: 'youtube-account' },
        fetchImpl: async (_url, init) => {
          requestBody = JSON.parse(String(init.body));
          return { ok: true, status: 200, json: async () => ({ externalPostId: 'youtube-video' }) };
        }
      });
      await publisher.publish({
        userId: 'owner', postId: 'youtube-title-description', caption, platform: 'YOUTUBE_SHORTS',
        platformSettings: { YOUTUBE_SHORTS: {
          title: 'kkkkk', visibility: 'unlisted', madeForKids: false,
          containsSyntheticMedia: true, communityGuidelinesCertified: true
        } }
      });

      expect(requestBody).toMatchObject({ content: caption, platforms: [{
        platform: 'youtube', platformSpecificData: {
          title: 'kkkkk', visibility: 'unlisted', madeForKids: false, containsSyntheticMedia: true
        }
      }] });
    }
  );

  for (const platform of ['INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const) {
    it.each([undefined, true, false])(`maps ${platform} AI declarations only when explicitly present (%s)`, async (isAiGenerated) => {
      const calls: { platforms: { platformSpecificData: Record<string, unknown> }[] }[] = [];
      const publisher = createPostPeerPublisher({
        apiKey: 'pp-key', baseUrl: 'https://api.postpeer.test',
        accountIds: { [platform]: 'owner-meta-account' },
        fetchImpl: async (_url, init) => {
          calls.push(JSON.parse(String(init.body)));
          return { ok: true, status: 200, json: async () => ({ externalPostId: 'meta-post' }) };
        }
      });
      const aiSetting = isAiGenerated === undefined ? {} : { isAiGenerated };
      await publisher.publish({
        userId: 'owner', postId: 'meta-post', platform,
        videoS3Key: 'https://cdn.test/video.mp4',
        platformSettings: platform === 'INSTAGRAM_REELS'
          ? { INSTAGRAM_REELS: { shareToFeed: false, ...aiSetting } }
          : { FACEBOOK_REELS: { publishMode: 'PUBLISH', ...aiSetting } }
      });
      const data = calls[0].platforms[0].platformSpecificData;
      expect(data).toEqual({ ...(platform === 'INSTAGRAM_REELS' ? { shareToFeed: false } : { contentType: 'reel', published: true }), ...aiSetting });
      if (isAiGenerated === undefined) expect(data).not.toHaveProperty('isAiGenerated');
    });
  }

  it.each([
    ['YOUTUBE_SHORTS', 'ก'.repeat(1667)],
    ['YOUTUBE_SHORTS', 'ราคา < 100'],
    ['INSTAGRAM_REELS', 'a'.repeat(2201)],
    ['FACEBOOK_REELS', 'a'.repeat(63207)],
    ['FACEBOOK_REELS', '😀'.repeat(31604)]
  ] as const)('blocks invalid %s caption before any provider/account/media read', async (platform, caption) => {
    const fetchImpl = vi.fn();
    const resolveAccountId = vi.fn();
    const resolveVideoUrl = vi.fn();
    const publisher = createPostPeerPublisher({ apiKey: 'key', baseUrl: 'https://api.postpeer.test', fetchImpl, resolveAccountId, resolveVideoUrl });
    await expect(publisher.publish({ userId: 'owner', postId: 'post', platform, caption, videoS3Key: 'video' })).rejects.toMatchObject({ code: 'PLATFORM_CAPTION_INVALID' });
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(resolveAccountId).not.toHaveBeenCalled();
    expect(resolveVideoUrl).not.toHaveBeenCalled();
  });
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
      providerPostId: 'postpeer-post-1',
      deliveryOutcome: 'PRIVATE',
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

  // Hangs until the request's abort signal fires, like a stalled connection.
  const hangUntilAborted = (_url: string, init: RequestInit) =>
    new Promise<never>((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(new Error('aborted')));
    });

  it('treats a hung PostPeer create request as an unknown outcome after the timeout', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      requestTimeoutMs: 20,
      fetchImpl: hangUntilAborted
    });

    await expect(
      publisher.publish({ userId: 'seller-1', postId: 'post-1', platform: 'TIKTOK' })
    ).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
  });

  it('stops waiting on a hung PostPeer status check after the timeout', async () => {
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      pollIntervalMs: 0,
      maxPollAttempts: 2,
      requestTimeoutMs: 20,
      fetchImpl: async (url, init) =>
        url.endsWith('/v1/posts')
          ? {
              ok: true,
              status: 202,
              json: async () => ({ success: true, status: 'publishing', postId: 'pp-1' })
            }
          : hangUntilAborted(url, init)
    });

    await expect(
      publisher.publish({ userId: 'seller-1', postId: 'post-1', platform: 'TIKTOK' })
    ).rejects.toThrow(/outcome is still unknown after 2 status checks/i);
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

  it('uses the selected frame time as the TikTok cover without resolving an image URL', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const resolveVideoUrl = vi.fn(async (key: string) => `https://cdn.test/${key}`);
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      resolveVideoUrl,
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ externalPostId: 'tiktok-video-123' })
        };
      }
    });

    await publisher.publish({
      postId: 'post-1',
      videoS3Key: 'uploads/videos/post-1.mp4',
      coverImageS3Key: 'uploads/covers/post-1.jpg',
      coverFrameTimeMs: 4200,
      platform: 'TIKTOK'
    });

    expect(resolveVideoUrl).toHaveBeenCalledTimes(1);
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/videos/post-1.mp4');
    expect(resolveVideoUrl).not.toHaveBeenCalledWith('uploads/covers/post-1.jpg');
    expect(calls[0].body).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            privacyLevel: 'SELF_ONLY',
            draft: false,
            videoCoverTimestampMs: 4200
          }
        }
      ]
    });
  });

  it('uses a signed Instagram cover URL when a custom cover image is available', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const resolveVideoUrl = vi.fn(async (key: string) => `https://cdn.test/${key}`);
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { INSTAGRAM_REELS: 'postpeer-instagram' },
      resolveVideoUrl,
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ externalPostId: 'instagram-reel-123' })
        };
      }
    });

    await publisher.publish({
      postId: 'post-1',
      videoS3Key: 'uploads/videos/post-1.mp4',
      coverImageS3Key: 'uploads/covers/post-1.jpg',
      coverFrameTimeMs: 4200,
      platform: 'INSTAGRAM_REELS'
    });

    expect(resolveVideoUrl).toHaveBeenCalledTimes(2);
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/videos/post-1.mp4');
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/covers/post-1.jpg');
    expect(calls[0].body).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            coverUrl: 'https://cdn.test/uploads/covers/post-1.jpg'
          }
        }
      ]
    });
    expect(JSON.stringify(calls[0].body)).not.toContain('thumbOffset');
  });

  it('falls back to the selected frame time for Instagram when there is no custom image', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { INSTAGRAM_REELS: 'postpeer-instagram' },
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ externalPostId: 'instagram-reel-123' })
        };
      }
    });

    await publisher.publish({
      postId: 'post-1',
      coverFrameTimeMs: 4200,
      platform: 'INSTAGRAM_REELS'
    });

    expect(calls[0].body).toMatchObject({
      platforms: [{ platformSpecificData: { thumbOffset: 4200 } }]
    });
  });

  it.each([
    { publishMode: 'PUBLISH', withCover: false },
    { publishMode: 'PUBLISH', withCover: true },
    { publishMode: 'PAGE_DRAFT', withCover: false },
    { publishMode: 'PAGE_DRAFT', withCover: true }
  ] as const)('always sends Facebook Reels while preserving owner, mode and AI settings: %j', async ({
    publishMode, withCover
  }) => {
    const calls: Record<string, unknown>[] = [];
    const resolveAccountId = vi.fn(async () => 'seller-facebook-page');
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { FACEBOOK_REELS: 'operator-facebook-page' },
      resolveAccountId,
      resolveVideoUrl: async (key) => `https://cdn.test/${key}`,
      fetchImpl: async (_url, init) => {
        calls.push(JSON.parse(String(init.body)));
        return {
          ok: true,
          status: 200,
          json: async () => ({
            postId: 'postpeer-reel-123',
            status: publishMode === 'PUBLISH' ? 'published' : 'draft',
            platforms: [{
              platform: 'facebook',
              success: true,
              platformPostUrl: 'https://www.facebook.com/reel/123'
            }]
          })
        };
      }
    });

    const result = await publisher.publish({
      userId: 'seller-1',
      postId: 'post-1',
      caption: 'รีวิวสินค้าใหม่',
      videoS3Key: 'uploads/videos/post-1.mp4',
      ...(withCover ? { coverImageS3Key: 'uploads/covers/post-1.jpg' } : {}),
      platform: 'FACEBOOK_REELS',
      platformSettings: { FACEBOOK_REELS: { publishMode, isAiGenerated: true } }
    });

    expect(resolveAccountId).toHaveBeenCalledWith({
      userId: 'seller-1', platform: 'FACEBOOK_REELS'
    });
    expect(calls).toEqual([{
      content: 'รีวิวสินค้าใหม่',
      platforms: [{
        platform: 'facebook',
        accountId: 'seller-facebook-page',
        platformSpecificData: {
          contentType: 'reel',
          published: publishMode === 'PUBLISH',
          isAiGenerated: true,
          ...(withCover ? { videoThumbnailUrl: 'https://cdn.test/uploads/covers/post-1.jpg' } : {})
        }
      }],
      mediaItems: [{ type: 'video', url: 'https://cdn.test/uploads/videos/post-1.mp4' }],
      publishNow: true
    }]);
    expect(result).toMatchObject({
      platform: 'FACEBOOK_REELS',
      status: 'PUBLISHED',
      deliveryOutcome: publishMode === 'PUBLISH' ? 'LIVE' : 'DRAFT'
    });
  });

  it('does not fall back to a Facebook feed video when Reel publishing fails', async () => {
    const fetchImpl = vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        status: 'failed',
        platforms: [{ platform: 'facebook', success: false, error: 'Reel rejected' }]
      })
    }));
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { FACEBOOK_REELS: 'postpeer-facebook' },
      fetchImpl
    });

    await expect(publisher.publish({
      postId: 'post-1',
      videoS3Key: 'https://cdn.test/video.mp4',
      platform: 'FACEBOOK_REELS'
    })).rejects.toThrow(/Reel rejected/);

    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it.each([
    { videoS3Key: undefined, resolvedUrl: undefined },
    { videoS3Key: '', resolvedUrl: undefined },
    { videoS3Key: '  ', resolvedUrl: undefined },
    { videoS3Key: 'uploads/video.mp4', resolvedUrl: '' },
    { videoS3Key: 'uploads/video.mp4', resolvedUrl: '  ' }
  ])('rejects a Facebook Reel without a video before contacting PostPeer: %j', async ({
    videoS3Key, resolvedUrl
  }) => {
    const fetchImpl = vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({ externalPostId: 'facebook-post-123' })
    }));
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { FACEBOOK_REELS: 'postpeer-facebook' },
      ...(resolvedUrl !== undefined ? { resolveVideoUrl: async () => resolvedUrl } : {}),
      fetchImpl
    });

    await expect(publisher.publish({
      postId: 'post-1',
      videoS3Key,
      platform: 'FACEBOOK_REELS'
    })).rejects.toThrow(/video is required to publish Facebook Reels/);

    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('keeps Facebook Reel mode when sending a best-effort custom thumbnail', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const resolveVideoUrl = vi.fn(async (key: string) => `https://cdn.test/${key}`);
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { FACEBOOK_REELS: 'postpeer-facebook' },
      resolveVideoUrl,
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ externalPostId: 'facebook-reel-123' })
        };
      }
    });

    await publisher.publish({
      postId: 'post-1',
      videoS3Key: 'uploads/videos/post-1.mp4',
      coverImageS3Key: 'uploads/covers/post-1.jpg',
      platform: 'FACEBOOK_REELS'
    });

    expect(resolveVideoUrl).toHaveBeenCalledTimes(2);
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/videos/post-1.mp4');
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/covers/post-1.jpg');
    expect(calls[0].body).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            contentType: 'reel',
            videoThumbnailUrl: 'https://cdn.test/uploads/covers/post-1.jpg'
          }
        }
      ]
    });
  });

  it('does not resolve or send a custom thumbnail for YouTube Shorts', async () => {
    const calls: { body: Record<string, unknown> }[] = [];
    const resolveVideoUrl = vi.fn(async (key: string) => `https://cdn.test/${key}`);
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { YOUTUBE_SHORTS: 'postpeer-youtube' },
      resolveVideoUrl,
      fetchImpl: async (_url, init) => {
        calls.push({ body: JSON.parse(String(init.body)) });
        return {
          ok: true,
          status: 200,
          json: async () => ({ externalPostId: 'youtube-video-123' })
        };
      }
    });

    await publisher.publish({
      postId: 'post-1',
      videoS3Key: 'uploads/videos/post-1.mp4',
      coverImageS3Key: 'uploads/covers/post-1.jpg',
      coverFrameTimeMs: 4200,
      platform: 'YOUTUBE_SHORTS'
    });

    expect(resolveVideoUrl).toHaveBeenCalledTimes(1);
    expect(resolveVideoUrl).toHaveBeenCalledWith('uploads/videos/post-1.mp4');
    expect(resolveVideoUrl).not.toHaveBeenCalledWith('uploads/covers/post-1.jpg');
    expect(calls[0].body).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            title: 'PostDee video',
            visibility: 'private'
          }
        }
      ]
    });
    expect(JSON.stringify(calls[0].body)).not.toMatch(
      /cover|thumbnail|thumbOffset/i
    );
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

  for (const failureStage of ['create', 'poll'] as const) {
    it(`exposes only a fixed frame-rate rejection from TikTok ${failureStage}`, async () => {
      const calls: string[] = [];
      const rawReason =
        'TikTok publish failed: frame_rate_check_failed secret=provider-secret id=private-provider-id';
      const publisher = createPostPeerPublisher({
        apiKey: 'pp-key',
        baseUrl: 'https://api.postpeer.test',
        accountIds: { TIKTOK: 'postpeer-tiktok' },
        pollIntervalMs: 0,
        fetchImpl: async (_url, init) => {
          calls.push(init.method ?? '');
          return {
            ok: true,
            json: async () =>
              failureStage === 'poll' && init.method === 'POST'
                ? { status: 'publishing', postId: 'existing-provider-post' }
                : {
                    post: {
                      status: 'failed',
                      platforms: [{ platform: 'tiktok', status: 'failed', errorMessage: rawReason }]
                    }
                  }
          };
        }
      });
      const log = vi.spyOn(console, 'error').mockImplementation(() => undefined);
      try {
        const result = await processPublishJob({
          jobData: {
            userId: 'seller-1', postId: 'post-1', videoS3Key: 'uploads/clip.mp4',
            runAt: '2026-10-14T16:40:00.000Z', status: 'READY',
            platforms: ['TIKTOK'], platformSettings: { TIKTOK: { publishMode: 'INBOX_DRAFT' } }
          },
          publisher,
          maxPublishAttempts: 3
        });
        expect(result.platformResults).toEqual([{
          platform: 'TIKTOK', status: 'FAILED',
          errorMessage: 'TikTok rejected this video because its frame rate validation failed. Export the video again before retrying.'
        }]);
        expect(calls).toEqual(failureStage === 'create' ? ['POST'] : ['POST', 'GET']);
        expect(JSON.stringify(result)).not.toContain('provider-secret');
        expect(JSON.stringify(result)).not.toContain('private-provider-id');
        expect(JSON.stringify(log.mock.calls)).not.toContain(rawReason);
        expect(JSON.stringify(log.mock.calls)).not.toContain('provider-secret');
        expect(JSON.stringify(log.mock.calls)).not.toContain('private-provider-id');
      } finally {
        log.mockRestore();
      }
    });
  }

  for (const [platform, reason] of [
    ['TIKTOK', 'frame_rate_check_failed_unknown secret=provider-secret'],
    ['YOUTUBE_SHORTS', 'TikTok publish failed: frame_rate_check_failed secret=provider-secret']
  ] as const) {
    it(`keeps an unrecognized or unrelated ${platform} rejection generic`, async () => {
      const publisher = createPostPeerPublisher({
        apiKey: 'pp-key',
        baseUrl: 'https://api.postpeer.test',
        accountIds: { [platform]: 'provider-account' },
        fetchImpl: async () => ({
          ok: true,
          json: async () => ({ status: 'failed', errorMessage: reason })
        })
      });
      const log = vi.spyOn(console, 'error').mockImplementation(() => undefined);
      try {
        const result = await processPublishJob({
          jobData: {
            postId: 'post-1', platforms: [platform],
            runAt: '2026-10-14T16:40:00.000Z', status: 'READY'
          }, publisher
        });
        expect(result.platformResults[0]).toMatchObject({
          status: 'FAILED',
          errorMessage: 'Publishing to this platform failed. Please try again later.'
        });
        expect(JSON.stringify(result)).not.toContain('provider-secret');
        expect(JSON.stringify(log.mock.calls)).not.toContain('provider-secret');
      } finally {
        log.mockRestore();
      }
    });
  }

  it('maps explicit YouTube settings into provider intent and records unlisted delivery', async () => {
    let body: Record<string, unknown> | undefined;
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { YOUTUBE_SHORTS: 'postpeer-youtube' },
      now: () => '2026-08-11T01:00:00.000Z',
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return {
          ok: true,
          status: 200,
          json: async () => ({
            status: 'published',
            postId: 'postpeer-youtube-1',
            platforms: [
              {
                platform: 'youtube',
                status: 'published',
                platformPostUrl: 'https://youtube.test/watch?v=1'
              }
            ]
          })
        };
      }
    });

    const result = await publisher.publish({
      userId: 'seller-youtube-settings',
      postId: 'post-youtube-settings',
      platform: 'YOUTUBE_SHORTS',
      platformSettings: {
        YOUTUBE_SHORTS: {
          title: 'Explicit title',
          visibility: 'unlisted',
          madeForKids: false,
          containsSyntheticMedia: true,
          communityGuidelinesCertified: true
        }
      }
    });

    expect(body).toMatchObject({
      platforms: [
        {
          platformSpecificData: {
            title: 'Explicit title',
            visibility: 'unlisted',
            madeForKids: false,
            containsSyntheticMedia: true
          }
        }
      ]
    });
    expect(JSON.stringify(body)).not.toContain('communityGuidelinesCertified');
    expect(result).toMatchObject({
      deliveryOutcome: 'UNLISTED',
      providerPostId: 'postpeer-youtube-1'
    });
  });

  it('requires an explicit provider draft result for TikTok inbox delivery', async () => {
    let body: Record<string, unknown> | undefined;
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      accountIds: { TIKTOK: 'postpeer-tiktok' },
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return {
          ok: true,
          status: 200,
          json: async () => ({
            status: 'draft',
            postId: 'postpeer-tiktok-draft',
            platforms: [{ platform: 'tiktok', status: 'draft', success: true }]
          })
        };
      }
    });

    const result = await publisher.publish({
      userId: 'seller-tiktok-draft',
      postId: 'post-tiktok-draft',
      platform: 'TIKTOK',
      platformSettings: { TIKTOK: { publishMode: 'INBOX_DRAFT' } }
    });

    expect(body).toMatchObject({
      platforms: [{ platformSpecificData: { draft: true } }]
    });
    expect(result).toMatchObject({
      deliveryOutcome: 'DRAFT',
      providerPostId: 'postpeer-tiktok-draft'
    });
    expect(result.externalPostId).toBeUndefined();
  });

  describe('published TikTok Inbox receipts', () => {
    const providerPostId = 'postpeer-tiktok-inbox';
    const inboxMessagesUrl = 'https://www.tiktok.com/messages?lang=en';
    const urlReceiptId = 'v_inbox_url~v2.1234567890123456789';
    const fileReceiptId = 'v_inbox_file~v2.9876543210987654321';
    const inboxInput = {
      userId: 'seller-inbox-receipt',
      postId: 'post-inbox-receipt',
      platform: 'TIKTOK',
      platformSettings: { TIKTOK: { publishMode: 'INBOX_DRAFT' } }
    } as const;
    const publishedPayload = (platformPostId?: string) => ({
      success: true,
      status: 'published',
      postId: providerPostId,
      platforms: [{
        platform: 'tiktok', status: 'published', success: true,
        platformPostId, platformPostUrl: inboxMessagesUrl
      }]
    });
    const publisherForReceipt = (payload: unknown, throughPoll = false) => {
      const calls: { url: string; method: string; body?: unknown }[] = [];
      const publisher = createPostPeerPublisher({
        apiKey: 'pp-key',
        baseUrl: 'https://api.postpeer.test',
        accountIds: { TIKTOK: 'postpeer-tiktok' },
        now: () => '2026-10-15T12:00:00.000Z',
        pollIntervalMs: 0,
        maxPollAttempts: 1,
        fetchImpl: async (url, init) => {
          calls.push({
            url, method: init.method ?? '',
            ...(init.body ? { body: JSON.parse(String(init.body)) } : {})
          });
          return {
            ok: true,
            status: throughPoll && init.method === 'POST' ? 202 : 200,
            json: async () => throughPoll && init.method === 'POST'
              ? { success: true, status: 'publishing', postId: providerPostId }
              : payload
          };
        }
      });
      return { publisher, calls };
    };

    for (const stage of ['create', 'poll'] as const) {
      for (const receipt of ['url', 'file'] as const) {
        it(`confirms a published Inbox ${receipt} receipt as DRAFT at ${stage}`, async () => {
          const receiptId = receipt === 'url' ? urlReceiptId : fileReceiptId;
          const base = publishedPayload(receiptId);
          const finalPost = {
            ...base,
            platforms: base.platforms.map((platform) => ({
              ...platform,
              // Published status is sufficient unless success is explicitly false.
              success: receipt === 'url' ? true : undefined,
              platformPostUrl: receipt === 'url' ? inboxMessagesUrl : undefined
            }))
          };
          const payload = stage === 'poll'
            ? { success: true, post: { ...finalPost, postId: undefined } }
            : receipt === 'file'
              ? { ...finalPost, postId: undefined, id: providerPostId }
              : finalPost;
          const { publisher, calls } = publisherForReceipt(payload, stage === 'poll');

          const result = await publisher.publish(inboxInput);

          expect(result).toEqual({
            platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'DRAFT',
            providerPostId, publishedAt: '2026-10-15T12:00:00.000Z'
          });
          expect(result.externalPostId).toBeUndefined();
          expect(calls[0].body).toMatchObject({
            platforms: [{ platform: 'tiktok', platformSpecificData: { draft: true } }]
          });
          expect(calls.map(({ method }) => method)).toEqual(
            stage === 'poll' ? ['POST', 'GET'] : ['POST']
          );
          if (stage === 'poll') {
            expect(calls[1].url).toBe(`https://api.postpeer.test/v1/posts/${providerPostId}`);
          }
        });

        it(`rejects an Inbox ${receipt} receipt for a requested Direct Post at ${stage}`, async () => {
          const { publisher } = publisherForReceipt(
            publishedPayload(receipt === 'url' ? urlReceiptId : fileReceiptId),
            stage === 'poll'
          );

          await expect(publisher.publish({
            ...inboxInput,
            platformSettings: {
              TIKTOK: { publishMode: 'DIRECT_POST', privacyLevel: 'SELF_ONLY' }
            }
          })).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
        });
      }
    }

    it('accepts the selected published Inbox receipt within a partial provider result', async () => {
      const { publisher } = publisherForReceipt({
        ...publishedPayload(urlReceiptId), status: 'partial'
      });

      const result = await publisher.publish(inboxInput);

      expect(result).toMatchObject({ status: 'PUBLISHED', deliveryOutcome: 'DRAFT', providerPostId });
      expect(result.externalPostId).toBeUndefined();
    });

    for (const [label, receiptId] of [
      ['a messages URL without an Inbox id', undefined],
      ['an empty Inbox id', ''],
      ['a normal TikTok video id', 'tiktok-video-123'],
      ['a Direct Post URL receipt', 'v_pub_url~v2.123456789'],
      ['a Direct Post file receipt', 'v_pub_file~v2.123456789'],
      ['a missing numeric suffix', 'v_inbox_url~v2.'],
      ['a nonnumeric suffix', 'v_inbox_file~v2.not-a-number'],
      ['a trailing id fragment', 'v_inbox_url~v2.12345junk'],
      ['an embedded Inbox id', 'prefix-v_inbox_url~v2.12345'],
      ['a malformed separator', 'v_inbox_url-v2.12345'],
      ['an unsupported receipt version', 'v_inbox_url~v1.12345'],
      ['a malformed uppercase prefix', 'V_INBOX_URL~v2.12345'],
      ['the messages URL used as an id', inboxMessagesUrl]
    ] as const) {
      it(`rejects published Inbox delivery with ${label}`, async () => {
        const { publisher, calls } = publisherForReceipt(publishedPayload(receiptId));

        await expect(publisher.publish(inboxInput)).rejects.toThrow(
          /PostPeer publish to TIKTOK failed/i
        );
        expect(calls.map(({ method }) => method)).toEqual(['POST']);
      });
    }

    it('requires an explicit published status on the selected TikTok platform', async () => {
      const base = publishedPayload(urlReceiptId);
      const { publisher } = publisherForReceipt({
        ...base,
        platforms: base.platforms.map((platform) => ({ ...platform, status: undefined }))
      });

      await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
    });

    it('does not borrow an Inbox receipt from a different platform', async () => {
      const base = publishedPayload('tiktok-video-123');
      const { publisher } = publisherForReceipt({
        ...base,
        platforms: [...base.platforms, {
          platform: 'youtube', status: 'published', platformPostId: urlReceiptId
        }]
      });

      await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
    });

    it('does not treat the parent provider post id as the selected Inbox receipt', async () => {
      const { publisher } = publisherForReceipt({
        ...publishedPayload(undefined), postId: urlReceiptId
      });

      await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
    });

    it('requires a genuine provider post id for an immediate published Inbox receipt', async () => {
      const { publisher, calls } = publisherForReceipt({
        ...publishedPayload(urlReceiptId), postId: undefined
      });

      await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
      expect(calls.map(({ method }) => method)).toEqual(['POST']);
    });

    for (const failure of ['response success', 'post status', 'platform success', 'platform status'] as const) {
      it(`preserves explicit failure precedence for ${failure} with an Inbox receipt`, async () => {
        const payload = publishedPayload(urlReceiptId);
        if (failure === 'response success') payload.success = false;
        if (failure === 'post status') payload.status = 'failed';
        if (failure === 'platform success') payload.platforms[0].success = false;
        if (failure === 'platform status') payload.platforms[0].status = 'failed';
        const { publisher, calls } = publisherForReceipt(payload);

        await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
        expect(calls.map(({ method }) => method)).toEqual(['POST']);
      });
    }

    for (const pending of ['post', 'platform'] as const) {
      it(`keeps ${pending} pending despite a valid Inbox receipt and another published status`, async () => {
        const payload = publishedPayload(urlReceiptId);
        if (pending === 'post') payload.status = 'pending';
        else payload.platforms[0].status = 'pending';
        const { publisher, calls } = publisherForReceipt(payload);

        await expect(publisher.publish(inboxInput)).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
        expect(calls.map(({ method }) => method)).toEqual(['POST', 'GET']);
        expect(calls[1].url).toBe(`https://api.postpeer.test/v1/posts/${providerPostId}`);
      });
    }

    it('does not poll or resend a pending Inbox receipt without a genuine provider post id', async () => {
      const base = publishedPayload(urlReceiptId);
      const { publisher, calls } = publisherForReceipt({
        ...base, postId: undefined, status: 'pending',
        platforms: base.platforms.map((platform) => ({ ...platform, status: 'pending' }))
      });

      await expect(publisher.publish(inboxInput)).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
      expect(calls.map(({ method }) => method)).toEqual(['POST']);
    });

    describe('documented CREATE summaries', () => {
      const createSummary = () => ({
        success: true,
        status: 'published',
        postId: providerPostId,
        platforms: [{ platform: 'tiktok', success: true, platformPostUrl: inboxMessagesUrl }]
      });
      const canonicalInbox = () => ({
        success: true,
        post: publishedPayload(urlReceiptId)
      });
      type StatusResponse = {
        ok: boolean;
        status?: number;
        json: () => Promise<unknown>;
      };
      const publisherForSummary = (
        summary: unknown = createSummary(),
        readStatus: () => Promise<StatusResponse> = async () => ({
          ok: true, json: async () => canonicalInbox()
        })
      ) => {
        const calls: { url: string; method: string }[] = [];
        const publisher = createPostPeerPublisher({
          apiKey: 'pp-key',
          baseUrl: 'https://api.postpeer.test',
          accountIds: { TIKTOK: 'postpeer-tiktok' },
          now: () => '2026-10-15T12:00:00.000Z',
          pollIntervalMs: 0,
          maxPollAttempts: 2,
          fetchImpl: async (url, init) => {
            calls.push({ url, method: init.method ?? '' });
            return init.method === 'POST'
              ? { ok: true, json: async () => summary }
              : readStatus();
          }
        });
        return { publisher, calls };
      };

      it('confirms the documented CREATE summary through GET on its existing provider id', async () => {
        const { publisher, calls } = publisherForSummary();

        const result = await publisher.publish(inboxInput);

        expect(result).toEqual({
          platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'DRAFT',
          providerPostId, publishedAt: '2026-10-15T12:00:00.000Z'
        });
        expect(result.externalPostId).toBeUndefined();
        expect(calls).toEqual([
          { method: 'POST', url: 'https://api.postpeer.test/v1/posts' },
          { method: 'GET', url: `https://api.postpeer.test/v1/posts/${providerPostId}` }
        ]);
      });

      for (const [label, summary] of [
        ['a wrapped post', { success: true, post: createSummary() }],
        ['the id alias', { ...createSummary(), postId: undefined, id: providerPostId }],
        ['no messages URL', {
          ...createSummary(), platforms: [{ platform: 'tiktok', success: true }]
        }]
      ] as const) {
        it(`uses canonical GET proof after CREATE returns ${label}`, async () => {
          const { publisher, calls } = publisherForSummary(summary, async () => ({
            ok: true,
            json: async () => ({ success: true, post: {
              ...publishedPayload(fileReceiptId), postId: undefined
            } })
          }));

          const result = await publisher.publish(inboxInput);

          expect(result).toMatchObject({
            status: 'PUBLISHED', deliveryOutcome: 'DRAFT', providerPostId
          });
          expect(result.externalPostId).toBeUndefined();
          expect(calls.map(({ method }) => method)).toEqual(['POST', 'GET']);
          expect(calls[1].url).toBe(`https://api.postpeer.test/v1/posts/${providerPostId}`);
        });
      }

      it('waits for a canonical pending response to finish without repeating CREATE', async () => {
        let statusChecks = 0;
        const { publisher, calls } = publisherForSummary(createSummary(), async () => ({
          ok: true,
          json: async () => ++statusChecks === 1
            ? { success: true, post: { status: 'pending', postId: providerPostId } }
            : canonicalInbox()
        }));

        await expect(publisher.publish(inboxInput)).resolves.toMatchObject({
          status: 'PUBLISHED', deliveryOutcome: 'DRAFT', providerPostId
        });
        expect(calls.map(({ method }) => method)).toEqual(['POST', 'GET', 'GET']);
        expect(calls.slice(1).map(({ url }) => url)).toEqual([
          `https://api.postpeer.test/v1/posts/${providerPostId}`,
          `https://api.postpeer.test/v1/posts/${providerPostId}`
        ]);
      });

      for (const [label, readStatus] of [
        ['another incomplete summary', async () => ({ ok: true, json: async () => createSummary() })],
        ['a pending post', async () => ({
          ok: true, json: async () => ({ status: 'pending', postId: providerPostId })
        })],
        ['a network failure', async () => { throw new Error('status connection reset'); }],
        ['an HTTP failure', async () => ({ ok: false, status: 503, json: async () => ({}) })],
        ['invalid JSON', async () => ({
          ok: true, json: async () => { throw new Error('invalid JSON'); }
        })],
        ['a different provider postId', async () => ({
          ok: true, json: async () => ({
            success: true, post: { ...publishedPayload(urlReceiptId), postId: 'another-provider-post' }
          })
        })],
        ['a different provider id alias', async () => ({
          ok: true, json: async () => ({
            ...publishedPayload(urlReceiptId), postId: undefined, id: 'another-provider-post'
          })
        })]
      ] as const) {
        it(`keeps ${label} bounded and unknown after CREATE`, async () => {
          const { publisher, calls } = publisherForSummary(createSummary(), readStatus);

          await expect(publisher.publish(inboxInput)).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
          expect(calls.map(({ method }) => method)).toEqual(['POST', 'GET', 'GET']);
          expect(calls.slice(1).every(({ url }) =>
            url === `https://api.postpeer.test/v1/posts/${providerPostId}`
          )).toBe(true);
        });
      }

      for (const [label, canonical] of [
        ['parent failure', { ...canonicalInbox(), success: false }],
        ['selected failure', { success: true, post: {
          ...publishedPayload(urlReceiptId), platforms: [{
            platform: 'tiktok', success: false, status: 'failed', platformPostId: urlReceiptId
          }]
        } }],
        ['messages URL alone', { success: true, post: publishedPayload(undefined) }],
        ['a normal video id', { success: true, post: publishedPayload('tiktok-video-123') }],
        ['a Direct Post receipt', { success: true, post: publishedPayload('v_pub_url~v2.12345') }],
        ['a malformed Inbox receipt', { success: true, post: publishedPayload('v_inbox_url~v2.bad') }],
        ['a receipt without selected status', { success: true, post: {
          ...publishedPayload(urlReceiptId), platforms: [{
            platform: 'tiktok', success: true, platformPostId: urlReceiptId
          }]
        } }]
      ] as const) {
        it(`does not confirm ${label} returned by canonical GET`, async () => {
          const { publisher, calls } = publisherForSummary(createSummary(), async () => ({
            ok: true, json: async () => canonical
          }));

          await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
          expect(calls.map(({ method }) => method)).toEqual(['POST', 'GET']);
        });
      }

      for (const [label, summary] of [
        ['no provider id', { ...createSummary(), postId: undefined }],
        ['an Inbox receipt as provider id', { ...createSummary(), postId: urlReceiptId }],
        ['a Direct Post receipt as provider id', { ...createSummary(), postId: 'v_pub_file~v2.12345' }],
        ['only parent success', { ...createSummary(), platforms: [] }],
        ['another platform success', {
          ...createSummary(), platforms: [{ platform: 'youtube', success: true }]
        }],
        ['missing selected success', {
          ...createSummary(), platforms: [{ platform: 'tiktok', platformPostUrl: inboxMessagesUrl }]
        }],
        ['selected false', {
          ...createSummary(), platforms: [{ platform: 'tiktok', success: false }]
        }],
        ['parent false', { ...createSummary(), success: false }],
        ['parent failed', { ...createSummary(), status: 'failed' }],
        ['parent partial', { ...createSummary(), status: 'partial' }],
        ['selected failed', {
          ...createSummary(), platforms: [{ platform: 'tiktok', success: true, status: 'failed' }]
        }],
        ['an unrecognized selected status', {
          ...createSummary(), platforms: [{ platform: 'tiktok', success: true, status: 'complete' }]
        }]
      ] as const) {
        it(`does not start confirmation polling for CREATE with ${label}`, async () => {
          const { publisher, calls } = publisherForSummary(summary);

          await expect(publisher.publish(inboxInput)).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
          expect(calls.map(({ method }) => method)).toEqual(['POST']);
        });
      }

      it('does not use Inbox confirmation polling to promote a Direct Post request', async () => {
        const { publisher, calls } = publisherForSummary({
          ...createSummary(), platforms: [{
            platform: 'tiktok', success: true, platformPostId: urlReceiptId,
            platformPostUrl: inboxMessagesUrl
          }]
        });

        await expect(publisher.publish({
          ...inboxInput,
          platformSettings: { TIKTOK: { publishMode: 'DIRECT_POST', privacyLevel: 'SELF_ONLY' } }
        })).rejects.toThrow(/PostPeer publish to TIKTOK failed/i);
        expect(calls.map(({ method }) => method)).toEqual(['POST']);
      });

      for (const confirmed of [true, false]) {
        it(`records ${confirmed ? 'confirmed draft' : 'unknown outcome'} without worker CREATE retries`, async () => {
          const { publisher, calls } = publisherForSummary(createSummary(), async () => ({
            ok: true, json: async () => confirmed ? canonicalInbox() : createSummary()
          }));
          const recordResults = vi.fn(async () => []);
          const log = vi.spyOn(console, 'error').mockImplementation(() => undefined);
          try {
            const result = await processPublishJob({
              jobData: {
                ...inboxInput, platforms: ['TIKTOK'], status: 'READY',
                runAt: '2026-10-15T12:00:00.000Z'
              },
              publisher,
              platformPublishStore: { recordResults },
              maxPublishAttempts: 3
            });

            expect(result.status).toBe(confirmed ? 'PUBLISHED' : 'FAILED');
            if (confirmed) {
              expect(result.platformResults).toEqual([{
                platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'DRAFT',
                providerPostId, publishedAt: '2026-10-15T12:00:00.000Z'
              }]);
              expect(result.requiresReconciliation).toBeUndefined();
            } else {
              expect(result.requiresReconciliation).toBe(true);
              expect(result.platformResults[0]).toMatchObject({ platform: 'TIKTOK', status: 'FAILED' });
              expect(result.platformResults[0]).not.toHaveProperty('deliveryOutcome');
              expect(result.platformResults[0]).not.toHaveProperty('externalPostId');
            }
            expect(recordResults).toHaveBeenCalledExactlyOnceWith({
              postId: inboxInput.postId, results: result.platformResults
            });
            expect(calls.map(({ method }) => method)).toEqual(
              confirmed ? ['POST', 'GET'] : ['POST', 'GET', 'GET']
            );
          } finally {
            log.mockRestore();
          }
        });
      }
    });
  });

  it('revalidates an immutable target snapshot before using its provider account id', async () => {
    let body: Record<string, unknown> | undefined;
    const target = {
      accountId: 'postpeer-youtube-original',
      displayName: 'Original channel',
      connectedAt: '2026-08-01T10:00:00.000Z'
    };
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      resolveCurrentPlatformTarget: async () => ({
        ...target,
        displayName: 'Renamed channel'
      }),
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init.body));
        return {
          ok: true,
          status: 200,
          json: async () => ({
            status: 'published',
            postId: 'postpeer-youtube-targeted',
            platforms: [
              {
                platform: 'youtube',
                status: 'published',
                platformPostUrl: 'https://youtube.test/watch?v=targeted'
              }
            ]
          })
        };
      }
    });

    await publisher.publish({
      userId: 'seller-targeted',
      postId: 'post-targeted',
      platform: 'YOUTUBE_SHORTS',
      platformTargets: { YOUTUBE_SHORTS: target }
    });

    expect(body).toMatchObject({
      platforms: [{ accountId: target.accountId }]
    });
  });

  it('fails before the provider call when a snapshotted target was reconnected', async () => {
    const fetchImpl = vi.fn();
    const publisher = createPostPeerPublisher({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      resolveCurrentPlatformTarget: async () => ({
        accountId: 'postpeer-tiktok-reconnected',
        connectedAt: '2026-08-02T10:00:00.000Z'
      }),
      fetchImpl
    });

    await expect(
      publisher.publish({
        userId: 'seller-reconnected',
        postId: 'post-reconnected',
        platform: 'TIKTOK',
        platformTargets: {
          TIKTOK: {
            accountId: 'postpeer-tiktok-original',
            connectedAt: '2026-08-01T10:00:00.000Z'
          }
        }
      })
    ).rejects.toThrow(/target changed/i);
    expect(fetchImpl).not.toHaveBeenCalled();
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
