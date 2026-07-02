import { describe, expect, it, vi } from 'vitest';

import {
  PostPeerConnectUnavailableError,
  createPostPeerConnectClient
} from './postPeerConnectClient.js';

describe('createPostPeerConnectClient', () => {
  it('reports unavailable when no API key is configured', async () => {
    const client = createPostPeerConnectClient({
      baseUrl: 'https://api.postpeer.test'
    });

    await expect(client.createProfile()).rejects.toBeInstanceOf(
      PostPeerConnectUnavailableError
    );
    await expect(
      client.createConnectUrl({ platform: 'TIKTOK', profileId: 'profile-1' })
    ).rejects.toBeInstanceOf(PostPeerConnectUnavailableError);
  });

  it('creates a PostPeer profile', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ id: 'profile-1' })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.createProfile()).resolves.toEqual({ profileId: 'profile-1' });
    expect(fetchImpl).toHaveBeenCalledWith('https://api.postpeer.test/v1/profiles', {
      method: 'POST',
      headers: { 'x-access-key': 'pp-key', 'Content-Type': 'application/json' },
      body: '{}'
    });
  });

  it('gets a platform OAuth connect URL for a profile', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ url: 'https://www.tiktok.com/auth?x=1' })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.createConnectUrl({ platform: 'TIKTOK', profileId: 'profile-1' })
    ).resolves.toEqual({ connectUrl: 'https://www.tiktok.com/auth?x=1' });

    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/connect/tiktok?profileId=profile-1',
      {
        method: 'GET',
        headers: { 'x-access-key': 'pp-key' }
      }
    );
  });

  it('lists integrations mapped to supported social platforms', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        integrations: [
          { id: 'int-1', platform: 'tiktok', platformUserId: 'tt-123' },
          { id: 'int-2', platform: 'youtube', platformUserId: 'yt-456' },
          { id: 'int-3', platform: 'linkedin', platformUserId: 'li-789' }
        ]
      })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.listIntegrations({ profileId: 'profile-1' })).resolves.toEqual([
      { id: 'int-1', platform: 'TIKTOK', platformUserId: 'tt-123' },
      { id: 'int-2', platform: 'YOUTUBE_SHORTS', platformUserId: 'yt-456' }
    ]);

    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/connect/integrations?profileId=profile-1',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
  });
});
