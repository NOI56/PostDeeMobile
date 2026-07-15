import { createHmac } from 'node:crypto';

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
  platform?: SocialConnectionPlatform;
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
 * - `DELETE /v1/connect/integrations/{id}` removes an external connection.
 */
export type PostPeerConnectClient = {
  supportsIntegrationCleanup?: boolean;
  createProfile: (input: { userId: string }) => Promise<{ profileId: string }>;
  createConnectUrl: (input: {
    platform: SocialConnectionPlatform;
    profileId: string;
  }) => Promise<{ connectUrl: string }>;
  listIntegrations: (input: { profileId: string }) => Promise<PostPeerIntegration[]>;
  disconnectIntegration?: (input: { integrationId: string }) => Promise<void>;
};

const readRecord = (value: unknown): Record<string, unknown> =>
  typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {};

const readString = (value: unknown): string | undefined =>
  typeof value === 'string' && value.trim() ? value.trim() : undefined;

const readNonNegativeInteger = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isInteger(value) && value >= 0 ? value : undefined;

const buildProfileName = (userId: string, secret: string | undefined): string => {
  const normalizedUserId = userId.trim();

  if (!normalizedUserId) {
    throw new PostPeerConnectProviderError();
  }

  // PostPeer requires a profile name. Use an HMAC-derived suffix so the name
  // is stable for this account without sending a Firebase uid, email, phone,
  // or display name to the provider.
  const suffix = createHmac('sha256', secret ?? 'postdee-unconfigured')
    .update(`postdee-profile:${normalizedUserId}`)
    .digest('hex')
    .slice(0, 10);

  return `PostDee user ${suffix}`;
};

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
    init: {
      method: string;
      body?: string;
      allowNotFound?: boolean;
      parseJson?: boolean;
    } = { method: 'GET' }
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

    if (!response.ok && !(init.allowNotFound && response.status === 404)) {
      throw new PostPeerConnectProviderError(response.status);
    }

    return init.parseJson === false ? undefined : response.json();
  };

  return {
    supportsIntegrationCleanup: Boolean(apiKey),
    createProfile: async ({ userId }) => {
      const name = buildProfileName(userId, apiKey);
      const payload = readRecord(
        await request('/v1/profiles', {
          method: 'POST',
          body: JSON.stringify({ name })
        })
      );
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
      const pageLimit = 100;
      const listedIntegrations: PostPeerIntegration[] = [];
      let offset = 0;

      while (true) {
        const payload = readRecord(
          await request(
            `/v1/connect/integrations?profileId=${encodeURIComponent(profileId)}` +
              `&limit=${pageLimit}&offset=${offset}`
          )
        );
        const integrations = Array.isArray(payload.integrations) ? payload.integrations : [];

        listedIntegrations.push(
          ...integrations.flatMap((entry) => {
            const record = readRecord(entry);
            const id = readString(record.id);
            const slug = readString(record.platform);
            const platform = slug ? socialPlatformBySlug[slug] : undefined;

            if (!id) {
              return [];
            }

            const platformUserId = readString(record.platformUserId);
            const displayName =
              readString(record.displayName) ?? readString(record.username);

            return [
              {
                id,
                ...(platform ? { platform } : {}),
                ...(platformUserId ? { platformUserId } : {}),
                ...(displayName ? { displayName } : {})
              }
            ];
          })
        );

        const pagination = readRecord(payload.pagination);
        const total =
          readNonNegativeInteger(payload.total) ?? readNonNegativeInteger(pagination.total);
        const responseOffset =
          readNonNegativeInteger(payload.offset) ??
          readNonNegativeInteger(pagination.offset) ??
          offset;
        const nextOffset = responseOffset + integrations.length;

        if (total === undefined || responseOffset !== offset) {
          throw new PostPeerConnectProviderError();
        }

        if (nextOffset >= total) {
          return listedIntegrations;
        }

        if (integrations.length === 0 || nextOffset <= offset) {
          throw new PostPeerConnectProviderError();
        }

        offset = nextOffset;
      }
    },
    disconnectIntegration: async ({ integrationId }) => {
      await request(
        `/v1/connect/integrations/${encodeURIComponent(integrationId)}`,
        {
          method: 'DELETE',
          allowNotFound: true,
          parseJson: false
        }
      );
    }
  };
};
