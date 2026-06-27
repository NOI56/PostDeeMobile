import { describe, expect, it, vi } from 'vitest';

import {
  PostPeerConnectUnavailableError,
  createPostPeerConnectClient
} from './postPeerConnectClient.js';

describe('createPostPeerConnectClient', () => {
  it('reports unavailable when create path is not configured', async () => {
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test'
    });

    await expect(
      client.createConnectLink({
        platform: 'TIKTOK',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    ).rejects.toBeInstanceOf(PostPeerConnectUnavailableError);
  });

  it('posts a connect-link request and returns the authorize URL', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ connectUrl: 'https://postpeer.test/connect/abc' })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      createPath: '/v1/connect/links',
      fetchImpl
    });

    await expect(
      client.createConnectLink({
        platform: 'TIKTOK',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    ).resolves.toEqual({ connectUrl: 'https://postpeer.test/connect/abc' });

    expect(fetchImpl).toHaveBeenCalledWith('https://api.postpeer.test/v1/connect/links', {
      method: 'POST',
      headers: {
        'x-access-key': 'pp-key',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        platform: 'tiktok',
        state: 'signed-state',
        callbackUrl: 'https://postdee.test/social-connections/postpeer/callback'
      })
    });
  });
});
