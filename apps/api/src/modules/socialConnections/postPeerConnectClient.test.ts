import { createHmac } from 'node:crypto';

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

    await expect(client.createProfile({ userId: 'firebase-user-1' })).rejects.toBeInstanceOf(
      PostPeerConnectUnavailableError
    );
    await expect(
      client.createConnectUrl({ platform: 'TIKTOK', profileId: 'profile-1' })
    ).rejects.toBeInstanceOf(PostPeerConnectUnavailableError);
    expect(client.findProfile).toBeUndefined();
  });

  it('creates a PostPeer profile', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ profiles: [], total: 0, page: 1, limit: 100 })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ id: 'profile-1' })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          profiles: [
            {
              id: 'profile-1',
              name: `PostDee user v2-${createHmac('sha256', 'pp-key')
                .update('postdee-profile:firebase-user@example.com')
                .digest('hex')
                .slice(0, 32)}`
            }
          ],
          total: 1,
          page: 1,
          limit: 100
        })
      });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.createProfile({ userId: 'firebase-user@example.com' })
    ).resolves.toEqual({ profileId: 'profile-1' });
    expect(fetchImpl).toHaveBeenNthCalledWith(
      1,
      'https://api.postpeer.test/v1/profiles?limit=100&page=1',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
    expect(fetchImpl).toHaveBeenNthCalledWith(2, 'https://api.postpeer.test/v1/profiles', {
      method: 'POST',
      headers: { 'x-access-key': 'pp-key', 'Content-Type': 'application/json' },
      body: expect.any(String)
    });
    expect(fetchImpl).toHaveBeenNthCalledWith(
      3,
      'https://api.postpeer.test/v1/profiles?limit=100&page=1',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );

    const requestBody = JSON.parse(fetchImpl.mock.calls[1][1].body as string) as {
      name?: string;
    };
    expect(requestBody.name).toMatch(/^PostDee user v2-[a-f0-9]{32}$/);
    expect(requestBody.name).not.toContain('firebase-user@example.com');
  });

  it('reuses an existing deterministic PostPeer profile instead of creating a duplicate', async () => {
    const userId = 'firebase-user@example.com';
    const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 32)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ id: 'profile-existing', name: profileName }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.createProfile({ userId })).resolves.toEqual({
      profileId: 'profile-existing'
    });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(fetchImpl).toHaveBeenCalledWith(
      'https://api.postpeer.test/v1/profiles?limit=100&page=1',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
  });

  it('reuses the single profile created by a concurrent request after PostPeer rejects create', async () => {
    const userId = 'firebase-user@example.com';
    const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 32)}`;
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ profiles: [], total: 0, page: 1, limit: 100 })
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 409,
        json: async () => ({})
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          profiles: [{ id: 'profile-created-elsewhere', name: profileName }],
          total: 1,
          page: 1,
          limit: 100
        })
      });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.createProfile({ userId })).resolves.toEqual({
      profileId: 'profile-created-elsewhere'
    });
    expect(fetchImpl).toHaveBeenCalledTimes(3);
  });

  it('waits for a newly created profile to become visible before confirming it', async () => {
    vi.useFakeTimers();

    try {
      const userId = 'firebase-user@example.com';
      const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
        .update(`postdee-profile:${userId}`)
        .digest('hex')
        .slice(0, 32)}`;
      const missingProfilePage = {
        ok: true,
        status: 200,
        json: async () => ({ profiles: [], total: 0, page: 1, limit: 100 })
      };
      const fetchImpl = vi
        .fn()
        .mockResolvedValueOnce(missingProfilePage)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ id: 'profile-eventual' })
        })
        .mockResolvedValueOnce(missingProfilePage)
        .mockResolvedValueOnce(missingProfilePage)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({
            profiles: [{ id: 'profile-eventual', name: profileName }],
            total: 1,
            page: 1,
            limit: 100
          })
        });
      const client = createPostPeerConnectClient({
        apiKey: 'pp-key',
        baseUrl: 'https://api.postpeer.test',
        fetchImpl
      });

      const assertion = expect(client.createProfile({ userId })).resolves.toEqual({
        profileId: 'profile-eventual'
      });

      await vi.runAllTimersAsync();
      await assertion;
      expect(fetchImpl).toHaveBeenCalledTimes(5);
      expect(
        fetchImpl.mock.calls.filter(([url]) => url.endsWith('/v1/profiles'))
      ).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('coalesces concurrent profile creation requests in one API process', async () => {
    const userId = 'firebase-user@example.com';
    const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 32)}`;
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ profiles: [], total: 0, page: 1, limit: 100 })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ id: 'profile-shared' })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          profiles: [{ id: 'profile-shared', name: profileName }],
          total: 1,
          page: 1,
          limit: 100
        })
      });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      Promise.all([
        client.createProfile({ userId }),
        client.createProfile({ userId })
      ])
    ).resolves.toEqual([
      { profileId: 'profile-shared' },
      { profileId: 'profile-shared' }
    ]);
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    expect(
      fetchImpl.mock.calls.filter(([url]) => url.endsWith('/v1/profiles'))
    ).toHaveLength(1);
  });

  it('fails closed after bounded verification without issuing another create request', async () => {
    vi.useFakeTimers();

    try {
      const missingProfilePage = {
        ok: true,
        status: 200,
        json: async () => ({ profiles: [], total: 0, page: 1, limit: 100 })
      };
      const fetchImpl = vi
        .fn()
        .mockResolvedValueOnce(missingProfilePage)
        .mockResolvedValueOnce({
          ok: true,
          status: 200,
          json: async () => ({ id: 'profile-not-listed' })
        })
        .mockResolvedValue(missingProfilePage);
      const client = createPostPeerConnectClient({
        apiKey: 'pp-key',
        baseUrl: 'https://api.postpeer.test',
        fetchImpl
      });

      const assertion = expect(
        client.createProfile({ userId: 'firebase-user@example.com' })
      ).rejects.toBeInstanceOf(PostPeerConnectProviderError);

      await vi.runAllTimersAsync();
      await assertion;
      expect(
        fetchImpl.mock.calls.filter(([url]) => url.endsWith('/v1/profiles'))
      ).toHaveLength(1);
      expect(fetchImpl).toHaveBeenCalledTimes(6);
    } finally {
      vi.useRealTimers();
    }
  });

  it('recovers one explicitly configured legacy profile after fingerprint validation', async () => {
    const apiKey = 'pp-key';
    const userId = 'firebase-user@example.com';
    const profileId = 'legacy-profile-explicit';
    const fingerprint = createHmac('sha256', apiKey)
      .update(`postdee-legacy-recovery:${userId}`)
      .digest('hex');
    const legacyProfileName = `PostDee user ${createHmac('sha256', apiKey)
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 10)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ id: profileId, name: legacyProfileName }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey,
      baseUrl: 'https://api.postpeer.test',
      legacyRecovery: { fingerprint, profileId },
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).resolves.toEqual({ profileId });
    await expect(client.createProfile({ userId })).resolves.toEqual({ profileId });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('never considers a legacy profile when the configured fingerprint belongs to another user', async () => {
    const apiKey = 'pp-key';
    const userId = 'firebase-user@example.com';
    const profileId = 'legacy-profile-explicit';
    const fingerprint = createHmac('sha256', apiKey)
      .update('postdee-legacy-recovery:another-user')
      .digest('hex');
    const legacyProfileName = `PostDee user ${createHmac('sha256', apiKey)
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 10)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ id: profileId, name: legacyProfileName }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey,
      baseUrl: 'https://api.postpeer.test',
      legacyRecovery: { fingerprint, profileId },
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).resolves.toBeUndefined();
  });

  it('fails closed when the explicit legacy profile id does not match the legacy name', async () => {
    const apiKey = 'pp-key';
    const userId = 'firebase-user@example.com';
    const fingerprint = createHmac('sha256', apiKey)
      .update(`postdee-legacy-recovery:${userId}`)
      .digest('hex');
    const legacyProfileName = `PostDee user ${createHmac('sha256', apiKey)
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 10)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ id: 'legacy-profile-actual', name: legacyProfileName }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey,
      baseUrl: 'https://api.postpeer.test',
      legacyRecovery: {
        fingerprint,
        profileId: 'legacy-profile-configured'
      },
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).rejects.toBeInstanceOf(
      PostPeerConnectProviderError
    );
  });

  it('leaves legacy recovery disabled without the one-time configuration', async () => {
    const apiKey = 'pp-key';
    const userId = 'firebase-user@example.com';
    const legacyProfileName = `PostDee user ${createHmac('sha256', apiKey)
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 10)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ id: 'legacy-profile', name: legacyProfileName }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey,
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).resolves.toBeUndefined();
  });

  it('finds a deterministic profile only after validating every profile page', async () => {
    const userId = 'firebase-user@example.com';
    const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 32)}`;
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          profiles: [
            { id: 'profile-other-1', name: 'Other profile 1' },
            { id: 'profile-other-2', name: 'Other profile 2' }
          ],
          total: 3,
          page: 1,
          limit: 2
        })
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          profiles: [{ id: 'profile-existing', name: profileName }],
          total: 3,
          page: 2,
          limit: 2
        })
      });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).resolves.toEqual({
      profileId: 'profile-existing'
    });
    expect(fetchImpl).toHaveBeenNthCalledWith(
      2,
      'https://api.postpeer.test/v1/profiles?limit=100&page=2',
      { method: 'GET', headers: { 'x-access-key': 'pp-key' } }
    );
  });

  it('fails closed when deterministic profile names are duplicated', async () => {
    const userId = 'firebase-user@example.com';
    const profileName = `PostDee user v2-${createHmac('sha256', 'pp-key')
      .update(`postdee-profile:${userId}`)
      .digest('hex')
      .slice(0, 32)}`;
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [
          { id: 'profile-duplicate-1', name: profileName },
          { id: 'profile-duplicate-2', name: profileName }
        ],
        total: 2,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.findProfile?.({ userId })).rejects.toBeInstanceOf(
      PostPeerConnectProviderError
    );
  });

  it('fails closed when a profile page is shorter than its reported total', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ profiles: [], total: 1, page: 1, limit: 100 })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.findProfile?.({ userId: 'firebase-user@example.com' })
    ).rejects.toBeInstanceOf(PostPeerConnectProviderError);
  });

  it('fails closed when a profile list entry is malformed', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        profiles: [{ name: 'Missing provider id' }],
        total: 1,
        page: 1,
        limit: 100
      })
    });
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(
      client.findProfile?.({ userId: 'firebase-user@example.com' })
    ).rejects.toBeInstanceOf(PostPeerConnectProviderError);
  });

  it('rejects an empty user id before contacting PostPeer', async () => {
    const fetchImpl = vi.fn();
    const client = createPostPeerConnectClient({
      apiKey: 'pp-key',
      baseUrl: 'https://api.postpeer.test',
      fetchImpl
    });

    await expect(client.createProfile({ userId: '   ' })).rejects.toBeInstanceOf(
      PostPeerConnectProviderError
    );
    expect(fetchImpl).not.toHaveBeenCalled();
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
