import { createHmac, timingSafeEqual } from 'node:crypto';

import type { SocialConnectionPlatform } from './socialConnectionStore.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
  body?: ReadableStream<Uint8Array> | null;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

type PostPeerLegacyRecoveryConfig = {
  fingerprint: string;
  profileId: string;
};

const profileVerificationRetryDelaysMs = [100, 250, 500] as const;

export const postPeerReturnUriByTarget = {
  android: 'postdee://social-connect/return',
  'android-staging': 'postdee-staging://social-connect/return'
} as const;

const wait = async (delayMs: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delayMs));

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

const connectHostnameRootsByPlatform: Record<
  SocialConnectionPlatform,
  readonly string[]
> = {
  TIKTOK: ['tiktok.com'],
  YOUTUBE_SHORTS: ['accounts.google.com'],
  INSTAGRAM_REELS: ['instagram.com', 'facebook.com'],
  FACEBOOK_REELS: ['facebook.com']
};

const isHostnameWithinRoot = (hostname: string, root: string): boolean =>
  hostname === root || hostname.endsWith(`.${root}`);

const isTrustedConnectUrl = (
  connectUrl: string,
  platform: SocialConnectionPlatform
): boolean => {
  if (!/^https:\/\//i.test(connectUrl) || connectUrl.includes('\\')) {
    return false;
  }

  const authority = connectUrl
    .slice(connectUrl.indexOf('//') + 2)
    .split(/[/?#]/, 1)[0];

  // URL normalisation drops an empty user-info marker (`https://@host`).
  // Inspect the original authority as well so every user-info form fails closed.
  if (!authority || authority.includes('@')) {
    return false;
  }

  let parsedUrl: URL;

  try {
    parsedUrl = new URL(connectUrl);
  } catch {
    return false;
  }

  if (
    parsedUrl.protocol !== 'https:' ||
    !parsedUrl.hostname ||
    parsedUrl.username ||
    parsedUrl.password
  ) {
    return false;
  }

  const hostname = parsedUrl.hostname.toLowerCase();
  const trustedHostnameRoots = [
    'postpeer.dev',
    ...connectHostnameRootsByPlatform[platform]
  ];

  return trustedHostnameRoots.some((root) => isHostnameWithinRoot(hostname, root));
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
  reconnectRequired?: boolean;
  canPublish?: boolean;
};

/**
 * Adapter for PostPeer's real connect API (https://api.postpeer.dev):
 * - `POST /v1/profiles` creates a profile that groups a user's accounts.
 * - `GET /v1/connect/{slug}?profileId=` returns the OAuth URL to open.
 * - `GET /v1/connect/integrations?profileId=` lists connected accounts so the
 *   backend can resolve each platform's account id after OAuth. Supported
 *   Android clients opt in to a fixed app return URI; completion is still
 *   verified by authenticated integration reconciliation.
 * - `DELETE /v1/connect/integrations/{id}` removes an external connection.
 */
export type PostPeerConnectClient = {
  supportsIntegrationCleanup?: boolean;
  publishingReadinessConfigured?: boolean;
  findProfile?: (input: { userId: string }) => Promise<{ profileId: string } | undefined>;
  createProfile: (input: { userId: string }) => Promise<{ profileId: string }>;
  createConnectUrl: (input: {
    platform: SocialConnectionPlatform;
    profileId: string;
    redirectUri?: string;
  }) => Promise<{ connectUrl: string }>;
  listIntegrations: (input: { profileId: string; publishingReadiness?: boolean }) => Promise<PostPeerIntegration[]>;
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

  // PostPeer requires a profile name. Use a versioned 128-bit HMAC-derived
  // suffix so the name is stable for this account without sending a Firebase
  // uid, email, phone, or display name to the provider. Never auto-recover the
  // old 40-bit names: they are too short to safely prove profile ownership.
  const suffix = createHmac('sha256', secret ?? 'postdee-unconfigured')
    .update(`postdee-profile:${normalizedUserId}`)
    .digest('hex')
    .slice(0, 32);

  return `PostDee user v2-${suffix}`;
};

const buildLegacyProfileName = (userId: string, secret: string): string => {
  const suffix = createHmac('sha256', secret)
    .update(`postdee-profile:${userId.trim()}`)
    .digest('hex')
    .slice(0, 10);

  return `PostDee user ${suffix}`;
};

const buildLegacyRecoveryFingerprint = (userId: string, secret: string): string =>
  createHmac('sha256', secret)
    .update(`postdee-legacy-recovery:${userId.trim()}`)
    .digest('hex');

export const createPostPeerConnectClient = ({
  apiKey,
  baseUrl,
  legacyRecovery,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey?: string;
  baseUrl: string;
  legacyRecovery?: PostPeerLegacyRecoveryConfig;
  fetchImpl?: FetchImpl;
}): PostPeerConnectClient => {
  const root = baseUrl.replace(/\/$/, '');
  const normalizedLegacyRecovery = (() => {
    if (!legacyRecovery) {
      return undefined;
    }

    const fingerprint =
      typeof legacyRecovery.fingerprint === 'string'
        ? legacyRecovery.fingerprint.trim().toLowerCase()
        : '';
    const profileId =
      typeof legacyRecovery.profileId === 'string'
        ? legacyRecovery.profileId.trim()
        : '';

    if (!apiKey || !/^[a-f0-9]{64}$/.test(fingerprint) || !profileId) {
      throw new PostPeerConnectProviderError();
    }

    return { fingerprint, profileId };
  })();

  const request = async (
    path: string,
    init: {
      method: string;
      body?: string;
      allowNotFound?: boolean;
      parseJson?: boolean;
      boundedReadTimeoutMs?: number;
    } = { method: 'GET' }
  ): Promise<unknown> => {
    if (!apiKey) {
      throw new PostPeerConnectUnavailableError();
    }

    const headers: Record<string, string> = { 'x-access-key': apiKey };

    if (init.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    if (init.boundedReadTimeoutMs !== undefined) {
      let url: URL;
      try { url = new URL(root); } catch { throw new PostPeerConnectProviderError(); }
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' || root.includes('@') || root.includes('\\') || init.method !== 'GET') throw new PostPeerConnectProviderError();
      const controller = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const operation = async () => {
        const response = await fetchImpl(`${root}${path}`, { method: 'GET', headers, redirect: 'error', signal: controller.signal });
        if (!response.ok) throw new PostPeerConnectProviderError(response.status);
        const maxBytes = 512 * 1024;
        if (!response.body) {
          const payload = await response.json();
          if (Buffer.byteLength(JSON.stringify(payload) ?? '', 'utf8') > maxBytes) throw new PostPeerConnectProviderError();
          return payload;
        }
        const reader = response.body.getReader();
        const chunks: Uint8Array[] = [];
        let length = 0;
        try {
          while (true) {
            const chunk = await reader.read();
            if (chunk.done) break;
            length += chunk.value.byteLength;
            if (length > maxBytes) {
              controller.abort();
              void reader.cancel().catch(() => undefined);
              throw new PostPeerConnectProviderError();
            }
            chunks.push(chunk.value);
          }
        } finally { reader.releaseLock(); }
        return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
      };
      try {
        return await Promise.race([
          operation(),
          new Promise<never>((_resolve, reject) => {
            timer = setTimeout(() => { controller.abort(); reject(new PostPeerConnectProviderError()); }, Math.max(1, Math.min(init.boundedReadTimeoutMs!, 5000)));
          })
        ]);
      } catch { throw new PostPeerConnectProviderError(); }
      finally { if (timer) clearTimeout(timer); }
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

  const findProfileByName = async (
    name: string
  ): Promise<{ profileId: string } | undefined> => {
    const pageLimit = 100;
    const matchingProfileIds: string[] = [];
    const listedProfileIds = new Set<string>();
    let reportedLimit: number | undefined;
    let reportedTotal: number | undefined;
    let page = 1;

    while (true) {
      const payload = readRecord(
        await request(`/v1/profiles?limit=${pageLimit}&page=${page}`)
      );

      if (!Array.isArray(payload.profiles)) {
        throw new PostPeerConnectProviderError();
      }

      const profiles = payload.profiles;
      const total = readNonNegativeInteger(payload.total);
      const responsePage = readNonNegativeInteger(payload.page);
      const responseLimit = readNonNegativeInteger(payload.limit);

      if (
        total === undefined ||
        responsePage !== page ||
        responseLimit === undefined ||
        responseLimit <= 0 ||
        (reportedLimit !== undefined && responseLimit !== reportedLimit) ||
        (reportedTotal !== undefined && total !== reportedTotal)
      ) {
        throw new PostPeerConnectProviderError();
      }

      reportedLimit ??= responseLimit;
      reportedTotal ??= total;

      const pageStart = (page - 1) * responseLimit;
      const expectedPageSize = Math.min(responseLimit, Math.max(total - pageStart, 0));

      // A short/partial page can hide a matching profile. Fail closed instead
      // of treating it as "not found" and creating another provider profile.
      if (profiles.length !== expectedPageSize) {
        throw new PostPeerConnectProviderError();
      }

      for (const entry of profiles) {
        const profile = readRecord(entry);
        const profileId = readString(profile.id);
        const profileName = readString(profile.name);

        if (!profileId || !profileName || listedProfileIds.has(profileId)) {
          throw new PostPeerConnectProviderError();
        }

        listedProfileIds.add(profileId);

        if (profileName === name) {
          matchingProfileIds.push(profileId);
        }
      }

      if (pageStart + profiles.length === total) {
        break;
      }

      if (pageStart + profiles.length > total || profiles.length === 0) {
        throw new PostPeerConnectProviderError();
      }

      page += 1;
    }

    if (matchingProfileIds.length > 1) {
      throw new PostPeerConnectProviderError();
    }

    const profileId = matchingProfileIds[0];
    return profileId ? { profileId } : undefined;
  };

  const findProfile = async ({ userId }: { userId: string }) => {
    const profileName = buildProfileName(userId, apiKey);

    if (normalizedLegacyRecovery && apiKey) {
      const expectedFingerprint = buildLegacyRecoveryFingerprint(userId, apiKey);
      const fingerprintMatches = timingSafeEqual(
        Buffer.from(expectedFingerprint, 'hex'),
        Buffer.from(normalizedLegacyRecovery.fingerprint, 'hex')
      );

      if (fingerprintMatches) {
        const legacyProfile = await findProfileByName(
          buildLegacyProfileName(userId, apiKey)
        );

        if (
          !legacyProfile ||
          legacyProfile.profileId !== normalizedLegacyRecovery.profileId
        ) {
          throw new PostPeerConnectProviderError();
        }

        return legacyProfile;
      }
    }

    return findProfileByName(profileName);
  };

  const findProfileByNameWithRetry = async (
    name: string
  ): Promise<{ profileId: string } | undefined> => {
    let profile = await findProfileByName(name);

    for (const delayMs of profileVerificationRetryDelaysMs) {
      if (profile) {
        return profile;
      }

      await wait(delayMs);
      profile = await findProfileByName(name);
    }

    return profile;
  };

  const createProfileOnce = async ({
    userId,
    name
  }: {
    userId: string;
    name: string;
  }): Promise<{ profileId: string }> => {
    const existingProfile = await findProfile({ userId });

    if (existingProfile) {
      return existingProfile;
    }

    let payload: Record<string, unknown>;

    try {
      payload = readRecord(
        await request('/v1/profiles', {
          method: 'POST',
          body: JSON.stringify({ name })
        })
      );
    } catch (error) {
      if (error instanceof PostPeerConnectProviderError) {
        const recoveredProfile = await findProfileByNameWithRetry(name);

        if (recoveredProfile) {
          return recoveredProfile;
        }
      }

      throw error;
    }

    const profileId = readString(payload.id) ?? readString(readRecord(payload.profile).id);
    const confirmedProfile = await findProfileByNameWithRetry(name);

    if (!profileId || !confirmedProfile || confirmedProfile.profileId !== profileId) {
      throw new PostPeerConnectProviderError();
    }

    return confirmedProfile;
  };

  // This prevents duplicate provider POSTs from concurrent requests handled
  // by this client instance. A multi-replica deployment still needs a
  // distributed lock around creation because PostPeer does not document an
  // idempotency key for this endpoint.
  const profileCreationsInFlight = new Map<
    string,
    Promise<{ profileId: string }>
  >();

  return {
    supportsIntegrationCleanup: Boolean(apiKey),
    publishingReadinessConfigured: Boolean(apiKey),
    ...(apiKey ? { findProfile } : {}),
    createProfile: async ({ userId }) => {
      const name = buildProfileName(userId, apiKey);
      const inFlightCreation = profileCreationsInFlight.get(name);

      if (inFlightCreation) {
        return inFlightCreation;
      }

      let trackedCreation: Promise<{ profileId: string }>;
      trackedCreation = createProfileOnce({ userId, name }).finally(() => {
        if (profileCreationsInFlight.get(name) === trackedCreation) {
          profileCreationsInFlight.delete(name);
        }
      });
      profileCreationsInFlight.set(name, trackedCreation);

      return trackedCreation;
    },
    createConnectUrl: async ({ platform, profileId, redirectUri }) => {
      if (
        redirectUri !== undefined &&
        !Object.values(postPeerReturnUriByTarget).some((allowedUri) => allowedUri === redirectUri)
      ) {
        throw new PostPeerConnectProviderError();
      }

      const slug = postPeerPlatformSlug[platform];
      const redirectQuery =
        redirectUri === undefined ? '' : `&redirectUri=${encodeURIComponent(redirectUri)}`;
      const payload = readRecord(
        await request(
          `/v1/connect/${slug}?profileId=${encodeURIComponent(profileId)}${redirectQuery}`
        )
      );
      const connectUrl = readString(payload.url) ?? readString(payload.connectUrl);

      if (!connectUrl || !isTrustedConnectUrl(connectUrl, platform)) {
        throw new PostPeerConnectProviderError();
      }

      return { connectUrl };
    },
    listIntegrations: async ({ profileId, publishingReadiness = false }) => {
      const pageLimit = 100;
      const listedIntegrations: PostPeerIntegration[] = [];
      let offset = 0;
      const deadline = Date.now() + 10_000;

      while (true) {
        if (publishingReadiness && (offset >= 1000 || Date.now() >= deadline)) throw new PostPeerConnectProviderError();
        const payload = readRecord(
          await request(
            `/v1/connect/integrations?profileId=${encodeURIComponent(profileId)}` +
              `&limit=${pageLimit}&offset=${offset}`,
            publishingReadiness ? { method: 'GET', boundedReadTimeoutMs: deadline - Date.now() } : undefined
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
            const reconnectRequired = readRecord(record.tokenStatus).reconnectRequired;
            const canPublish = readRecord(readRecord(record.platformMetadata).capabilities).publish;

            return [
              {
                id,
                ...(platform ? { platform } : {}),
                ...(platformUserId ? { platformUserId } : {}),
                ...(displayName ? { displayName } : {}),
                ...(typeof reconnectRequired === 'boolean' ? { reconnectRequired } : {}),
                ...(typeof canPublish === 'boolean' ? { canPublish } : {})
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

        if (total === undefined || responseOffset !== offset ||
            (publishingReadiness && (total > 1000 || integrations.length > pageLimit))) {
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
