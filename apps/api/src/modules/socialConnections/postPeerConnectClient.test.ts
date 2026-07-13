import { describe, expect, it, vi } from 'vitest';

import {
  PostPeerConnectProviderError,
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

  it('lists every integration id while mapping supported social platforms', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        integrations: [
          { id: 'int-1', platform: 'tiktok', platformUserId: 'tt-123' },
          { id: 'int-2', platform: 'youtube', platformUserId: 'yt-456' },
          { id: 'int-3', platform: 'linkedin', platformUserId: 'li-789' }
        ],
        limit: 100,
        offset: 0,
        total: 3
      })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.listIntegrations({ profileId: 'profile-1' })).resolves.toEqual([
      { id: 'int-1', platform: 'TIKTOK', platformUserId: 'tt-123' },
      { id: 'int-2', platform: 'YOUTUBE_SHORTS', platformUserId: 'yt-456' },
      { id: 'int-3', platformUserId: 'li-789' }
    ]);

    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/connect/integrations?profileId=profile-1&limit=100&offset=0',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
  });

  it('follows PostPeer pagination until every integration is listed', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          integrations: [
            { id: 'int-1', platform: 'tiktok' },
            { id: 'int-2', platform: 'youtube' }
          ],
          limit: 2,
          offset: 0,
          total: 3
        })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          integrations: [{ id: 'int-3', platform: 'linkedin' }],
          limit: 2,
          offset: 2,
          total: 3
        })
      });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.listIntegrations({ profileId: 'profile-1' })).resolves.toEqual([
      { id: 'int-1', platform: 'TIKTOK' },
      { id: 'int-2', platform: 'YOUTUBE_SHORTS' },
      { id: 'int-3' }
    ]);
    expect(fetchImpl).toHaveBeenNthCalledWith(
      2,
      'https://api.postpeer.test/v1/connect/integrations?profileId=profile-1&limit=100&offset=2',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
  });

  it('fails closed when PostPeer pagination stops before the reported total', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ integrations: [], limit: 100, offset: 0, total: 1 })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.listIntegrations({ profileId: 'profile-incomplete' })
    ).rejects.toBeInstanceOf(PostPeerConnectProviderError);
  });

  it('disconnects an integration through the official PostPeer endpoint', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 204,
      json: async () => {
        throw new Error('DELETE response must not be parsed');
      }
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test/',
      fetchImpl
    });

    await expect(
      client.disconnectIntegration?.({ integrationId: 'int/one' })
    ).resolves.toBeUndefined();
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/connect/integrations/int%2Fone',
      { method: 'DELETE', headers: { 'x-access-key': 'pp-key' } }
    );
  });

  it('treats an already-missing PostPeer integration as disconnected', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 404,
      json: async () => ({})
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.disconnectIntegration?.({ integrationId: 'int-missing' })
    ).resolves.toBeUndefined();
  });

  it('surfaces non-404 disconnect failures as provider errors', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: async () => ({})
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.disconnectIntegration?.({ integrationId: 'int-1' })
    ).rejects.toBeInstanceOf(PostPeerConnectProviderError);
  });
});
