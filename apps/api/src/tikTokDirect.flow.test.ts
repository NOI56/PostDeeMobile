import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createApp } from './app.js';
import { readServerConfig } from './config/env.js';
import { createInMemorySocialConnectionStore } from './modules/socialConnections/socialConnectionStore.js';
import { createMockVideoStorage } from './modules/storage/videoStorage.js';

afterEach(() => vi.unstubAllGlobals());

describe('TikTok Direct API to worker integration (injected provider only)', () => {
  const setup = async () => {
    const providerCalls: { url: string; method: string; body?: unknown }[] = [];
    const creatorInfo = {
      creatorAvatarUrl: 'https://cdn.tiktok.com/avatar.jpg', creatorUsername: 'creator',
      creatorNickname: 'Creator', privacyLevelOptions: ['PUBLIC_TO_EVERYONE', 'SELF_ONLY'],
      commentDisabled: false, duetDisabled: true, stitchDisabled: false,
      maxVideoPostDurationSec: 600
    };
    vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
      providerCalls.push({ url, method: init.method ?? 'GET', ...(init.body ? { body: JSON.parse(String(init.body)) } : {}) });
      return new Response(JSON.stringify(url.includes('/creator-info?')
        ? { success: true, data: creatorInfo }
        : {
            success: true, status: 'published', postId: 'provider-direct-1',
            platforms: [{ platform: 'tiktok', status: 'published', success: true,
              platformPostId: '7651234567890123456',
              platformPostUrl: 'https://www.tiktok.com/@creator/video/7651234567890123456' }]
          }), { status: 200 });
    });
    const connections = createInMemorySocialConnectionStore();
    await connections.upsert({ userId: 'direct-owner', platform: 'TIKTOK', postPeerAccountId: 'own-tiktok', externalAccountId: 'creator' });
    await connections.upsert({ userId: 'other-owner', platform: 'TIKTOK', postPeerAccountId: 'other-tiktok' });
    const app = createApp({
      config: readServerConfig({ SOCIAL_PUBLISHER: 'postpeer', POSTPEER_API_KEY: 'test-key' }),
      socialConnectionStore: connections,
      videoStorage: {
        ...createMockVideoStorage(),
        createDownloadAccess: async videoS3Key => ({
          videoS3Key, storageProvider: 'r2', accessType: 'signed-url',
          downloadUrl: 'https://r2.test/direct-original.mp4', downloadMethod: 'GET',
          downloadExpiresAt: '2026-10-15T23:00:00.000Z'
        })
      }
    });
    const options = await request(app).get('/social-connections/TIKTOK/publishing-options')
      .set('x-postdee-user-id', 'direct-owner').expect(200);
    const intent = {
      clientRequestId: 'direct-idempotent-1', caption: 'My original video',
      videoS3Key: 'uploads/direct-owner/upload-1/clip.mp4', platforms: ['TIKTOK'],
      platformSettings: { TIKTOK: {
        publishMode: 'DIRECT_POST', creatorInfoRevision: options.body.creatorInfoRevision,
        privacyLevel: 'PUBLIC_TO_EVERYONE', disableComment: true, disableDuet: true,
        disableStitch: true, brandContentToggle: false, brandOrganicToggle: false,
        isAigc: false, videoDurationSeconds: 30, musicUsageConfirmed: true,
        brandedContentPolicyConfirmed: false
      } }
    };
    const send = () => request(app).post('/posts').set('x-postdee-user-id', 'direct-owner')
      .set('x-postdee-phone-verified', 'true').send(intent);
    return { app, creatorInfo, providerCalls, intent, send };
  };

  it('loads owned options, validates before commit, publishes once and exposes the selected audience outcome', async () => {
    const { app, providerCalls, send } = await setup();
    const created = await send().expect(201);
    await app.locals.publishScheduler.runOnce();
    const posts = await request(app).get('/posts').set('x-postdee-user-id', 'direct-owner').expect(200);
    expect(posts.body.posts).toHaveLength(1);
    expect(posts.body.posts[0]).toMatchObject({
      id: created.body.post.id, status: 'PUBLISHED',
      platformResults: [{ platform: 'TIKTOK', status: 'PUBLISHED', deliveryOutcome: 'LIVE' }]
    });
    expect(providerCalls.filter(call => call.url.includes('/creator-info?'))).toHaveLength(3);
    expect(providerCalls.filter(call => call.method === 'POST')).toHaveLength(1);
    expect(providerCalls.every(call => !call.url.includes('other-tiktok'))).toBe(true);
    const published = JSON.stringify(providerCalls.find(call => call.method === 'POST')?.body);
    expect(published).toContain('"draft":false');
    expect(published).not.toContain('creatorInfoRevision');
    expect(published).not.toContain('musicUsageConfirmed');
    await send().expect(200);
    await app.locals.publishScheduler.runOnce();
    expect(providerCalls.filter(call => call.method === 'POST')).toHaveLength(1);
    const usage = await request(app).get('/billing/subscription')
      .set('x-postdee-user-id', 'direct-owner').set('x-postdee-phone-verified', 'true').expect(200);
    expect(usage.body.subscription.usedPostsThisMonth).toBe(1);
  });

  it('does not create a post or consume quota if creator options changed after review', async () => {
    const { app, creatorInfo, providerCalls, send } = await setup();
    creatorInfo.privacyLevelOptions = ['SELF_ONLY'];
    const response = await send().expect(409);
    expect(response.body.code).toBe('TIKTOK_DIRECT_SETTINGS_INVALID');
    const posts = await request(app).get('/posts').set('x-postdee-user-id', 'direct-owner').expect(200);
    expect(posts.body.posts).toEqual([]);
    const usage = await request(app).get('/billing/subscription')
      .set('x-postdee-user-id', 'direct-owner').set('x-postdee-phone-verified', 'true').expect(200);
    expect(usage.body.subscription.usedPostsThisMonth).toBe(0);
    expect(providerCalls.filter(call => call.method === 'POST')).toEqual([]);
  });

  it('rechecks queued intent and sends no CREATE when the creator loses the selected privacy', async () => {
    const { app, creatorInfo, providerCalls, send } = await setup();
    await send().expect(201);
    creatorInfo.privacyLevelOptions = ['SELF_ONLY'];
    const errors = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    try { await app.locals.publishScheduler.runOnce(); } finally { errors.mockRestore(); }
    expect(providerCalls.filter(call => call.method === 'POST')).toEqual([]);
    const posts = await request(app).get('/posts').set('x-postdee-user-id', 'direct-owner').expect(200);
    expect(posts.body.posts[0]).toMatchObject({ status: 'FAILED', platformResults: [{
      status: 'FAILED',
      errorMessage: 'TikTok publishing options changed. Review the account and publishing settings before trying again.'
    }] });
  });
});
