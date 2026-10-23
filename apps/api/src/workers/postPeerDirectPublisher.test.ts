import { describe, expect, it, vi } from 'vitest';

import type { PlatformSettings } from '../modules/posts/platformSettings.js';
import type { PlatformTarget } from '../modules/posts/platformTargets.js';
import type { TikTokCreatorInfo } from '../modules/socialConnections/postPeerTikTokClient.js';
import { buildTikTokConnectionRevision } from '../modules/posts/tikTokDirectSettings.js';
import { createPostPeerPublisher, PostPeerPublishOutcomeUnknownError } from './postPeerPublisher.js';
import { readRequestedDeliveryOutcome } from './platformDeliveryOutcome.js';

const target: PlatformTarget = {
  accountId: 'owner-tiktok',
  externalAccountId: 'creator-1',
  connectedAt: '2026-10-15T12:00:00.000Z'
};
const creatorInfo: TikTokCreatorInfo = {
  creatorAvatarUrl: 'https://cdn.tiktok.com/avatar.jpg',
  creatorUsername: 'creator',
  creatorNickname: 'Creator',
  privacyLevelOptions: [
    'PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS', 'FOLLOWER_OF_CREATOR', 'SELF_ONLY'
  ],
  commentDisabled: false,
  duetDisabled: false,
  stitchDisabled: false,
  maxVideoPostDurationSec: 3600
};
const directSettings = (privacyLevel = 'PUBLIC_TO_EVERYONE'): PlatformSettings => ({
  TIKTOK: {
    publishMode: 'DIRECT_POST',
    creatorInfoRevision: buildTikTokConnectionRevision({ userId: 'owner', target }),
    privacyLevel,
    disableComment: true,
    disableDuet: true,
    disableStitch: true,
    brandContentToggle: false,
    brandOrganicToggle: false,
    isAigc: false,
    videoDurationSeconds: 30,
    musicUsageConfirmed: true,
    brandedContentPolicyConfirmed: false
  }
} as PlatformSettings);

const publishInput = (settings = directSettings()) => ({
  userId: 'owner', postId: 'post-1', platform: 'TIKTOK' as const,
  caption: 'My original clip', videoS3Key: 'uploads/owner/clip.mp4',
  platformTargets: { TIKTOK: target }, platformSettings: settings
});
const published = (platformResult: Record<string, unknown> = {}) => ({
  success: true, status: 'published', postId: 'provider-post-1',
  platforms: [{
    platform: 'tiktok', status: 'published', success: true,
    platformPostId: '7651234567890123456',
    platformPostUrl: 'https://www.tiktok.com/@creator/video/7651234567890123456',
    ...platformResult
  }]
});
const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body });
const createFixture = (responses: unknown[] = [published()]) => {
  const calls: { url: string; init: RequestInit }[] = [];
  const getCreatorInfo = vi.fn(async () => ({
    ...creatorInfo, privacyLevelOptions: [...creatorInfo.privacyLevelOptions]
  }));
  const resolveCurrentPlatformTarget = vi.fn(async () => ({ ...target }));
  const resolveVideoUrl = vi.fn(async () => 'https://cdn.test/clip.mp4');
  const assertOwnerActive = vi.fn(async (_userId: string) => undefined);
  const publisher = createPostPeerPublisher({
    apiKey: 'test-key', baseUrl: 'https://api.postpeer.test',
    resolveCurrentPlatformTarget, resolveVideoUrl,
    tikTokClient: { getCreatorInfo },
    assertOwnerActive,
    maxPollAttempts: 1, pollIntervalMs: 0,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return ok(responses.shift());
    }
  });
  return { publisher, calls, getCreatorInfo, resolveCurrentPlatformTarget, resolveVideoUrl, assertOwnerActive };
};

describe('TikTok explicit Direct Post worker', () => {
  it('sends and validates the TikTok override even when called without the queue worker', async () => {
    const fixture = createFixture();
    const settings = directSettings();
    settings.TIKTOK = { ...settings.TIKTOK!, caption: 'TikTok destination text' };
    await fixture.publisher.publish({ ...publishInput(settings), caption: 'a'.repeat(2201) });
    expect(JSON.parse(String(fixture.calls[0].init.body)).content).toBe('TikTok destination text');
    const denied = createFixture();
    settings.TIKTOK = { ...settings.TIKTOK!, caption: '😀'.repeat(1101) };
    await expect(denied.publisher.publish(publishInput(settings))).rejects.toMatchObject({ code: 'TIKTOK_CAPTION_TOO_LONG' });
    expect(denied.getCreatorInfo).not.toHaveBeenCalled();
    expect(denied.calls).toEqual([]);
  });

  it.each([
    ['PUBLIC_TO_EVERYONE', 'LIVE'], ['MUTUAL_FOLLOW_FRIENDS', 'LIVE'],
    ['FOLLOWER_OF_CREATOR', 'LIVE'], ['SELF_ONLY', 'PRIVATE']
  ])('publishes %s only after checking current creator information', async (privacy, outcome) => {
    const fixture = createFixture();
    const settings = directSettings(privacy);
    const result = await fixture.publisher.publish(publishInput(settings));
    expect(fixture.getCreatorInfo).toHaveBeenCalledExactlyOnceWith({ accountId: target.accountId });
    expect(fixture.resolveCurrentPlatformTarget).toHaveBeenCalledTimes(2);
    expect(result).toMatchObject({ status: 'PUBLISHED', deliveryOutcome: outcome });
    expect(readRequestedDeliveryOutcome({ platform: 'TIKTOK', platformSettings: settings })).toBe(outcome);
    expect(fixture.calls).toHaveLength(1);
    expect(JSON.parse(String(fixture.calls[0].init.body))).toMatchObject({
      platforms: [{ accountId: target.accountId, platformSpecificData: {
        privacyLevel: privacy, draft: false,
        disableComment: true, disableDuet: true, disableStitch: true,
        brandContentToggle: false, brandOrganicToggle: false, isAigc: false
      } }]
    });
    const data = JSON.parse(String(fixture.calls[0].init.body)).platforms[0].platformSpecificData;
    expect(data.musicUsageConfirmed).toBeUndefined();
    expect(data.brandedContentPolicyConfirmed).toBeUndefined();
    expect(data.videoDurationSeconds).toBeUndefined();
  });

  it('forwards commercial and AI disclosures selected by the creator', async () => {
    const fixture = createFixture();
    const settings = directSettings();
    Object.assign(settings.TIKTOK!, {
      disableComment: false, disableStitch: false,
      brandContentToggle: true, brandOrganicToggle: true, isAigc: true,
      brandedContentPolicyConfirmed: true
    });
    await fixture.publisher.publish(publishInput(settings));
    expect(JSON.parse(String(fixture.calls[0].init.body)).platforms[0].platformSpecificData).toMatchObject({
      disableComment: false, disableDuet: true, disableStitch: false,
      brandContentToggle: true, brandOrganicToggle: true, isAigc: true
    });
  });

  it.each(['privacy', 'comments', 'duet', 'stitch', 'duration', 'api-duration'])('stops before media access and CREATE when %s no longer permits the choice', async (change) => {
    const fixture = createFixture();
    const settings = directSettings();
    if (change === 'privacy') fixture.getCreatorInfo.mockResolvedValue({ ...creatorInfo, privacyLevelOptions: ['SELF_ONLY'] });
    if (change === 'comments') {
      fixture.getCreatorInfo.mockResolvedValue({ ...creatorInfo, privacyLevelOptions: [...creatorInfo.privacyLevelOptions], commentDisabled: true });
      Object.assign(settings.TIKTOK!, { disableComment: false });
    }
    if (change === 'duet') {
      fixture.getCreatorInfo.mockResolvedValue({ ...creatorInfo, privacyLevelOptions: [...creatorInfo.privacyLevelOptions], duetDisabled: true });
      Object.assign(settings.TIKTOK!, { disableDuet: false });
    }
    if (change === 'stitch') {
      fixture.getCreatorInfo.mockResolvedValue({ ...creatorInfo, privacyLevelOptions: [...creatorInfo.privacyLevelOptions], stitchDisabled: true });
      Object.assign(settings.TIKTOK!, { disableStitch: false });
    }
    if (change === 'duration') fixture.getCreatorInfo.mockResolvedValue({ ...creatorInfo, privacyLevelOptions: [...creatorInfo.privacyLevelOptions], maxVideoPostDurationSec: 10 });
    if (change === 'api-duration') Object.assign(settings.TIKTOK!, { videoDurationSeconds: 601 });
    await expect(fixture.publisher.publish(publishInput(settings))).rejects.toThrow();
    expect(fixture.resolveVideoUrl).not.toHaveBeenCalled();
    expect(fixture.calls).toEqual([]);
  });

  it('does not send media or CREATE when the creator lookup fails', async () => {
    const fixture = createFixture();
    fixture.getCreatorInfo.mockRejectedValue(new Error('TikTok temporarily unavailable'));
    await expect(fixture.publisher.publish(publishInput())).rejects.toThrow();
    expect(fixture.resolveVideoUrl).not.toHaveBeenCalled();
    expect(fixture.calls).toEqual([]);
  });

  it('rejects a reconnected account after the creator lookup and never posts to either account', async () => {
    const fixture = createFixture();
    fixture.resolveCurrentPlatformTarget.mockResolvedValueOnce({ ...target }).mockResolvedValue({ ...target, connectedAt: '2026-10-15T13:00:00.000Z' });
    await expect(fixture.publisher.publish(publishInput())).rejects.toThrow(/target changed/i);
    expect(fixture.calls).toEqual([]);
  });

  it('requires a persisted owner target for the new explicit direct mode', async () => {
    const fixture = createFixture();
    await expect(fixture.publisher.publish({ ...publishInput(), platformTargets: undefined })).rejects.toThrow();
    expect(fixture.calls).toEqual([]);
  });

  it('rejects choices shown for an older connection revision before creator/media access', async () => {
    const fixture = createFixture();
    const settings = directSettings();
    Object.assign(settings.TIKTOK!, { creatorInfoRevision: '0'.repeat(64) });
    await expect(fixture.publisher.publish(publishInput(settings))).rejects.toThrow(/revision/i);
    expect(fixture.getCreatorInfo).not.toHaveBeenCalled();
    expect(fixture.resolveVideoUrl).not.toHaveBeenCalled();
    expect(fixture.calls).toEqual([]);
  });

  it('rechecks the exact revision when optional account identity appears during the creator lookup', async () => {
    const fixture = createFixture();
    const original = { ...target, externalAccountId: undefined };
    const settings = directSettings();
    Object.assign(settings.TIKTOK!, { creatorInfoRevision: buildTikTokConnectionRevision({ userId: 'owner', target: original }) });
    fixture.resolveCurrentPlatformTarget.mockResolvedValueOnce(original).mockResolvedValue({ ...target });
    await expect(fixture.publisher.publish({ ...publishInput(settings), platformTargets: { TIKTOK: original } })).rejects.toThrow(/revision|target changed/i);
    expect(fixture.calls).toEqual([]);
  });

  it('stops before CREATE when owner deletion begins while checking capabilities', async () => {
    const fixture = createFixture();
    fixture.assertOwnerActive.mockRejectedValue(new Error('Account deletion is in progress'));
    await expect(fixture.publisher.publish(publishInput())).rejects.toThrow(/deletion/i);
    expect(fixture.assertOwnerActive).toHaveBeenCalledExactlyOnceWith('owner');
    expect(fixture.calls).toEqual([]);
  });

  it('reads canonical status for a CREATE summary before confirming direct publication', async () => {
    const fixture = createFixture([
      { success: true, status: 'published', postId: 'provider-post-1', platforms: [{ platform: 'tiktok', success: true }] },
      published()
    ]);
    expect(await fixture.publisher.publish(publishInput())).toMatchObject({ status: 'PUBLISHED', deliveryOutcome: 'LIVE' });
    expect(fixture.calls.map(call => call.init.method)).toEqual(['POST', 'GET']);
    expect(fixture.calls[1].url).toBe('https://api.postpeer.test/v1/posts/provider-post-1');
  });

  it.each([
    { platformPostId: 'v_inbox_file~v2.7651234567890123456', platformPostUrl: 'https://www.tiktok.com/messages?lang=en' },
    { platformPostId: undefined, platformPostUrl: 'https://www.tiktok.com/messages?lang=en' },
    { platformPostId: undefined, platformPostUrl: 'https://evil.test/@creator/video/7651234567890123456' },
    { platformPostId: 'not-a-tiktok-video', platformPostUrl: undefined },
    { status: undefined, platformPostId: 'v_pub_file~v2.7651234567890123456', platformPostUrl: undefined }
  ])('never marks an ambiguous or Inbox result as direct publication: %j', async (result) => {
    const body = published(result);
    const fixture = createFixture([body, body]);
    await expect(fixture.publisher.publish(publishInput())).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    expect(fixture.calls.filter(call => call.init.method === 'POST')).toHaveLength(1);
    expect(fixture.calls.filter(call => call.init.method === 'GET')).toHaveLength(1);
  });

  it.each(['v_pub_file~v2.7651234567890123456', 'v_pub_file~v2-1.123456789'])('accepts a final direct receipt without inventing a public video URL: %s', async receipt => {
    const fixture = createFixture([published({ platformPostId: receipt, platformPostUrl: undefined })]);
    const result = await fixture.publisher.publish(publishInput(directSettings('SELF_ONLY')));
    expect(result).toMatchObject({ status: 'PUBLISHED', deliveryOutcome: 'PRIVATE', providerPostId: 'provider-post-1' });
    expect(result.externalPostId).toBeUndefined();
  });

  it('rejects an oversized UTF-16 caption before creator lookup or media access', async () => {
    const fixture = createFixture();
    await expect(fixture.publisher.publish({ ...publishInput(), caption: '😀'.repeat(1101) })).rejects.toMatchObject({ code: 'TIKTOK_CAPTION_TOO_LONG' });
    expect(fixture.getCreatorInfo).not.toHaveBeenCalled();
    expect(fixture.resolveVideoUrl).not.toHaveBeenCalled();
    expect(fixture.calls).toEqual([]);
  });

  it('keeps polling the original provider id when canonical status refers to another post', async () => {
    const fixture = createFixture([
      { success: true, status: 'publishing', postId: 'provider-post-1' },
      { ...published(), postId: 'different-post' }
    ]);
    await expect(fixture.publisher.publish(publishInput())).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    expect(fixture.calls.map(call => call.init.method)).toEqual(['POST', 'GET']);
    expect(fixture.calls[1].url).toBe('https://api.postpeer.test/v1/posts/provider-post-1');
  });

  it('never polls a TikTok receipt as if it were a PostPeer record id', async () => {
    const fixture = createFixture([{
      success: true, status: 'publishing',
      platforms: [{ platform: 'tiktok', status: 'publishing', platformPostId: 'v_pub_file~v2.7651234567890123456' }]
    }]);
    await expect(fixture.publisher.publish(publishInput())).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    expect(fixture.calls.map(call => call.init.method)).toEqual(['POST']);
  });

  it.each([null, { status: 'published', platforms: [{ platform: 'tiktok', platformPostUrl: { invalid: true } }] }])('treats a malformed accepted response as unknown without resending: %j', async body => {
    const fixture = createFixture([body]);
    await expect(fixture.publisher.publish(publishInput())).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    expect(fixture.calls.filter(call => call.init.method === 'POST')).toHaveLength(1);
  });

  it('does not report a provider server error after CREATE as proof that nothing was accepted', async () => {
    const fetchImpl = vi.fn(async () => ({ ok: false, status: 502, json: async () => ({}) }));
    const publisher = createPostPeerPublisher({
      apiKey: 'test-key', baseUrl: 'https://api.postpeer.test',
      resolveCurrentPlatformTarget: async () => ({ ...target }),
      assertOwnerActive: async () => undefined,
      tikTokClient: { getCreatorInfo: async () => creatorInfo }, fetchImpl
    });
    await expect(publisher.publish(publishInput())).rejects.toBeInstanceOf(PostPeerPublishOutcomeUnknownError);
    expect(fetchImpl).toHaveBeenCalledOnce();
  });
});
