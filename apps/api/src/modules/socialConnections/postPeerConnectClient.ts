import type { SocialConnectionPlatform } from './socialConnectionStore.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

// PostPeer platform slugs used in /v1/connect/{slug} and the integrations list.
const postPeerPlatformSlug: Record<SocialConnectionPlatform, string> = {
  TIKTOK: 'tiktok',
  YOUTUBE_SHORTS: 'youtube',
  INSTAGRAM_REELS: 'instagram',
  FACEBOOK_REELS: 'facebook'
};

const socialPlatformBySlug: Record<string, SocialConnectionPlatform> = {
  tiktok: 'TIKTOK',
  youtube: 'YOUTUBE_SHORTS',
  instagram: 'INSTAGRAM_REELS',
  facebook: 'FACEBOOK_REELS'
};

export class PostPeerConnectUnavailableError extends Error {
  constructor() {
    super('PostPeer account linking is not configured yet');
  }
}

export class PostPeerConnectProviderError extends Error {
  constructor(status?: number) {
    super(`PostPeer account linking failed with status ${status ?? 'unknown'}`);
  }
}

export type PostPeerIntegration = {
  id: string;
  platform: SocialConnectionPlatform;
  platformUserId?: string;
  displayName?: string;
};

/**
 * Adapter for PostPeer's real connect API (https://api.postpeer.dev):
 * - `POST /v1/profiles` creates a profile that groups a user's accounts.
 * - `GET /v1/connect/{slug}?profileId=` returns the OAuth URL to open.
 * - `GET /v1/connect/integrations?profileId=` lists connected accounts so the
 *   backend can resolve each platform's account id after OAuth (PostPeer does
 *   not call back, so the backend polls this instead).
 */
export type PostPeerConnectClient = {
  createProfile: () => Promise<{ profileId: string }>;
  createConnectUrl: (input: {
    platform: SocialConnectionPlatform;
    profileId: string;
  }) => Promise<{ connectUrl: string }>;
  listIntegrations: (input: { profileId: string }) => Promise<PostPeerIntegration[]>;
};

const readRecord = (value: unknown): Record<string, unknown> =>
  typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {};

const readString = (value: unknown): string | undefined =>
  typeof value === 'string' && value.trim() ? value.trim() : undefined;

export const createPostPeerConnectClient = ({
  apiKey,
  baseUrl,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey?: string;
  baseUrl: string;
  fetchImpl?: FetchImpl;
}): PostPeerConnectClient => {
  const root = baseUrl.replace(/\/$/, '');

  const request = async (
    path: string,
    init: { method: string; body?: string } = { method: 'GET' }
  ): Promise<unknown> => {
    if (!apiKey) {
      throw new PostPeerConnectUnavailableError();
    }

    const headers: Record<string, string> = { 'x-access-key': apiKey };

    if (init.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    const response = await fetchImpl(`${root}${path}`, {
      method: init.method,
      headers,
      ...(init.body !== undefined ? { body: init.body } : {})
    });

    if (!response.ok) {
      throw new PostPeerConnectProviderError(response.status);
    }

    return response.json();
  };

  return {
    createProfile: async () => {
      const payload = readRecord(await request('/v1/profiles', { method: 'POST', body: '{}' }));
      const profileId = readString(payload.id) ?? readString(readRecord(payload.profile).id);

      if (!profileId) {
        throw new PostPeerConnectProviderError();
      }

      return { profileId };
    },
    createConnectUrl: async ({ platform, profileId }) => {
      const slug = postPeerPlatformSlug[platform];
      const payload = readRecord(
        await request(`/v1/connect/${slug}?profileId=${encodeURIComponent(profileId)}`)
      );
      const connectUrl = readString(payload.url) ?? readString(payload.connectUrl);

      if (!connectUrl) {
        throw new PostPeerConnectProviderError();
      }

      return { connectUrl };
    },
    listIntegrations: async ({ profileId }) => {
      const payload = readRecord(
        await request(`/v1/connect/integrations?profileId=${encodeURIComponent(profileId)}`)
      );
      const integrations = Array.isArray(payload.integrations) ? payload.integrations : [];

      return integrations.flatMap((entry) => {
        const record = readRecord(entry);
        const id = readString(record.id);
        const slug = readString(record.platform);
        const platform = slug ? socialPlatformBySlug[slug] : undefined;

        if (!id || !platform) {
          return [];
        }

        return [
          {
            id,
            platform,
            platformUserId: readString(record.platformUserId),
            displayName: readString(record.displayName) ?? readString(record.username)
          }
        ];
      });
    }
  };
};
