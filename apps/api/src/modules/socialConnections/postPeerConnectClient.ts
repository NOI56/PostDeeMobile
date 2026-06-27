import type { SocialConnectionPlatform } from './socialConnectionStore.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

const postPeerPlatform: Record<SocialConnectionPlatform, string> = {
  TIKTOK: 'tiktok',
  YOUTUBE_SHORTS: 'youtube',
  INSTAGRAM_REELS: 'instagram',
  FACEBOOK_REELS: 'facebook'
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

export type PostPeerConnectClient = {
  createConnectLink: (input: {
    platform: SocialConnectionPlatform;
    state: string;
    callbackUrl: string;
  }) => Promise<{ connectUrl: string }>;
};

const readConnectUrl = (payload: unknown) => {
  if (typeof payload !== 'object' || payload === null) {
    return undefined;
  }

  const body = payload as Record<string, unknown>;
  const value = body.connectUrl ?? body.url ?? body.authorizeUrl;

  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
};

export const createPostPeerConnectClient = ({
  apiKey,
  baseUrl,
  createPath,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey?: string;
  baseUrl: string;
  createPath?: string;
  fetchImpl?: FetchImpl;
}): PostPeerConnectClient => ({
  createConnectLink: async ({ platform, state, callbackUrl }) => {
    if (!apiKey || !createPath) {
      throw new PostPeerConnectUnavailableError();
    }

    const response = await fetchImpl(`${baseUrl.replace(/\/$/, '')}${createPath}`, {
      method: 'POST',
      headers: {
        'x-access-key': apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        platform: postPeerPlatform[platform],
        state,
        callbackUrl
      })
    });

    if (!response.ok) {
      throw new PostPeerConnectProviderError(response.status);
    }

    const connectUrl = readConnectUrl(await response.json());

    if (!connectUrl) {
      throw new PostPeerConnectProviderError(response.status);
    }

    return { connectUrl };
  }
});
