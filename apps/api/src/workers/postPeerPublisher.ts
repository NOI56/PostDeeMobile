import type { Platform } from '../modules/posts/postStore.js';
import type { PlatformPublisher } from './publishWorker.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;
type ResolveVideoUrl = (videoS3Key: string) => string | Promise<string>;
type ResolveAccountId = (input: {
  userId: string;
  platform: Platform;
}) => string | undefined | Promise<string | undefined>;
export type PostPeerAccountIds = Partial<Record<Platform, string>>;

type PostPeerPlatformResult = {
  platform?: string;
  success?: boolean;
  platformPostUrl?: string;
  error?: string;
};

type PostPeerPublishResponse = {
  id?: string;
  externalPostId?: string;
  postId?: string;
  platforms?: PostPeerPlatformResult[];
};

// PostPeer platform identifiers. Confirm exact values against PostPeer docs
// when activating real publishing.
const postPeerPlatform: Record<Platform, string> = {
  TIKTOK: 'tiktok',
  YOUTUBE_SHORTS: 'youtube',
  INSTAGRAM_REELS: 'instagram',
  FACEBOOK_REELS: 'facebook'
};

const postPeerAccountIdEnv: Record<Platform, string> = {
  TIKTOK: 'POSTPEER_TIKTOK_ACCOUNT_ID',
  YOUTUBE_SHORTS: 'POSTPEER_YOUTUBE_ACCOUNT_ID',
  INSTAGRAM_REELS: 'POSTPEER_INSTAGRAM_ACCOUNT_ID',
  FACEBOOK_REELS: 'POSTPEER_FACEBOOK_ACCOUNT_ID'
};

const readPostPeerAccountId = async ({
  accountIds,
  resolveAccountId,
  userId,
  platform
}: {
  accountIds: PostPeerAccountIds;
  resolveAccountId?: ResolveAccountId;
  userId?: string;
  platform: Platform;
}) => {
  if (resolveAccountId) {
    const normalizedUserId = userId?.trim();
    const resolvedAccountId = normalizedUserId
      ? (
          await resolveAccountId({
            userId: normalizedUserId,
            platform
          })
        )?.trim()
      : undefined;

    if (resolvedAccountId) {
      return resolvedAccountId;
    }

    // The post owner has not connected their own PostPeer account yet, so fall
    // back to the shared operator account id below to keep publishing working.
  }

  const accountId = accountIds[platform]?.trim();

  if (!accountId) {
    throw new Error(`${postPeerAccountIdEnv[platform]} is required to publish ${platform}`);
  }

  return accountId;
};

const readPlatformResult = (payload: PostPeerPublishResponse, platform: Platform) => {
  const postPeerPlatformId = postPeerPlatform[platform];

  return payload.platforms?.find((result) => result.platform === postPeerPlatformId);
};

/**
 * Real social publisher backed by the PostPeer unified posting API
 * (https://postpeer.dev). Used when SOCIAL_PUBLISHER=postpeer and a
 * POSTPEER_API_KEY is set; otherwise the mock publisher is used.
 *
 * The request shape follows PostPeer's /v1/posts API. The config factory wires
 * `resolveVideoUrl` to signed R2/S3 download access so PostPeer receives a
 * downloadable media URL rather than the internal storage key.
 */
export const createPostPeerPublisher = ({
  apiKey,
  baseUrl,
  accountIds = {},
  resolveAccountId,
  resolveVideoUrl,
  now = () => new Date().toISOString(),
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  baseUrl: string;
  accountIds?: PostPeerAccountIds;
  resolveAccountId?: ResolveAccountId;
  resolveVideoUrl?: ResolveVideoUrl;
  now?: () => string;
  fetchImpl?: FetchImpl;
}): PlatformPublisher => ({
  publish: async ({ userId, postId, caption, videoS3Key, platform }) => {
    const accountId = await readPostPeerAccountId({
      accountIds,
      resolveAccountId,
      userId,
      platform
    });
    const videoUrl = videoS3Key
      ? resolveVideoUrl
        ? await resolveVideoUrl(videoS3Key)
        : videoS3Key
      : undefined;

    const response = await fetchImpl(`${baseUrl}/v1/posts`, {
      method: 'POST',
      headers: {
        'x-access-key': apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        content: caption ?? '',
        platforms: [
          {
            platform: postPeerPlatform[platform],
            accountId
          }
        ],
        ...(videoUrl
          ? {
              mediaItems: [
                {
                  type: 'video',
                  url: videoUrl
                }
              ]
            }
          : {}),
        publishNow: true
      })
    });

    if (!response.ok) {
      throw new Error(
        `PostPeer publish to ${platform} failed with status ${response.status ?? 'unknown'}`
      );
    }

    const payload = (await response.json()) as PostPeerPublishResponse;
    const platformResult = readPlatformResult(payload, platform);

    if (platformResult?.success === false) {
      throw new Error(
        `PostPeer publish to ${platform} failed: ${platformResult.error ?? 'platform failed'}`
      );
    }

    const externalPostId =
      platformResult?.platformPostUrl ??
      payload.externalPostId ??
      payload.id ??
      payload.postId ??
      `postpeer-${platform.toLowerCase()}-${postId}`;

    return {
      platform,
      status: 'PUBLISHED',
      externalPostId,
      publishedAt: now()
    };
  }
});
