import { describe, expect, it, vi } from 'vitest';

import {
  createPostPeerTikTokClient,
  TikTokPublishingError
} from './postPeerTikTokClient.js';

const creatorInfo = {
  creatorAvatarUrl: 'https://cdn.tiktok.test/avatar.jpg',
  creatorUsername: 'seller', creatorNickname: 'Seller',
  privacyLevelOptions: ['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS', 'SELF_ONLY'],
  commentDisabled: false, duetDisabled: true, stitchDisabled: false,
  maxVideoPostDurationSec: 3600
};

describe('PostPeer TikTok creator info', () => {
  it('uses only the explicit account id and returns a sanitized creator DTO', async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({
      success: true, data: { ...creatorInfo, accessToken: 'never-return' }
    })));
    const client = createPostPeerTikTokClient({
      apiKey: 'private-key', baseUrl: 'https://api.postpeer.test/', fetchImpl
    });

    await expect(client.getCreatorInfo({ accountId: 'stored account/id' })).resolves.toEqual(creatorInfo);
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/tiktok/creator-info?accountId=stored%20account%2Fid',
      expect.objectContaining({
        method: 'GET', headers: { 'x-access-key': 'private-key' }, redirect: 'error'
      })
    );
  });

  it.each([
    { success: false, data: creatorInfo },
    { success: true, data: { ...creatorInfo, duetDisabled: undefined } },
    { success: true, data: { ...creatorInfo, privacyLevelOptions: ['UNKNOWN'] } },
    { success: true, data: { ...creatorInfo, privacyLevelOptions: [] } },
    { success: true, data: { ...creatorInfo, maxVideoPostDurationSec: 0 } },
    { success: true, data: { ...creatorInfo, creatorAvatarUrl: 'javascript:bad' } }
  ])('fails closed on malformed or unsuccessful creator info', async (payload) => {
    const client = createPostPeerTikTokClient({
      apiKey: 'key', baseUrl: 'https://api.postpeer.test',
      fetchImpl: async () => new Response(JSON.stringify(payload))
    });
    await expect(client.getCreatorInfo({ accountId: 'owned' })).rejects.toBeInstanceOf(TikTokPublishingError);
  });

  it('bounds an oversized response', async () => {
    const client = createPostPeerTikTokClient({
      apiKey: 'key', baseUrl: 'https://api.postpeer.test',
      fetchImpl: async () => new Response('x'.repeat(40_000))
    });
    await expect(client.getCreatorInfo({ accountId: 'owned' })).rejects.toMatchObject({
      code: 'TIKTOK_CREATOR_INFO_INVALID', statusCode: 502
    });
  });

  it('bounds native requests even if a transport ignores abort', async () => {
    const client = createPostPeerTikTokClient({
      apiKey: 'key', baseUrl: 'https://api.postpeer.test', timeoutMs: 10,
      fetchImpl: () => new Promise(() => {})
    });
    await expect(client.getCreatorInfo({ accountId: 'owned' })).rejects.toMatchObject({
      code: 'TIKTOK_CREATOR_INFO_UNAVAILABLE', statusCode: 503
    });
  });

  it('does not call the provider without configuration or a stored account id', async () => {
    const fetchImpl = vi.fn();
    const unconfigured = createPostPeerTikTokClient({ baseUrl: 'https://api.postpeer.test', fetchImpl });
    await expect(unconfigured.getCreatorInfo({ accountId: 'owned' })).rejects.toBeInstanceOf(TikTokPublishingError);
    const configured = createPostPeerTikTokClient({ apiKey: 'key', baseUrl: 'https://api.postpeer.test', fetchImpl });
    await expect(configured.getCreatorInfo({ accountId: '' })).rejects.toBeInstanceOf(TikTokPublishingError);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('does not carry provider errors or credentials into its error', async () => {
    const client = createPostPeerTikTokClient({
      apiKey: 'private-key', baseUrl: 'https://api.postpeer.test',
      fetchImpl: async () => { throw new Error('secret-token raw-provider-payload'); }
    });
    const error = await client.getCreatorInfo({ accountId: 'private-account' }).catch((error: unknown) => error);
    expect(error).toMatchObject({ code: 'TIKTOK_CREATOR_INFO_UNAVAILABLE' });
    expect(String(error)).not.toMatch(/secret-token|raw-provider-payload|private-account|private-key/);
  });

  it.each([401, 429, 500])('sanitizes HTTP %s without parsing the provider body', async (status) => {
    const readBody = vi.fn(async () => 'provider-secret');
    const client = createPostPeerTikTokClient({
      apiKey: 'key', baseUrl: 'https://api.postpeer.test',
      fetchImpl: async () => ({ ok: false, text: readBody })
    });
    await expect(client.getCreatorInfo({ accountId: 'owned' })).rejects.toMatchObject({
      code: 'TIKTOK_CREATOR_INFO_UNAVAILABLE', statusCode: 503
    });
    expect(readBody).not.toHaveBeenCalled();
  });

  it('rejects invalid JSON without exposing its body', async () => {
    const client = createPostPeerTikTokClient({
      apiKey: 'key', baseUrl: 'https://api.postpeer.test',
      fetchImpl: async () => new Response('invalid-json-secret')
    });
    const error = await client.getCreatorInfo({ accountId: 'owned' }).catch((error: unknown) => error);
    expect(error).toMatchObject({ code: 'TIKTOK_CREATOR_INFO_INVALID' });
    expect(String(error)).not.toContain('invalid-json-secret');
  });
});
