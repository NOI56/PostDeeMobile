import type { Platform } from '../modules/posts/postStore.js';
import {
  PublishOutcomeUnknownError,
  type PlatformPublisher
} from './publishWorker.js';

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;
type ResolveVideoUrl = (videoS3Key: string) => string | Promise<string>;
type Sleep = (milliseconds: number) => Promise<void>;
type ResolveAccountId = (input: {
  userId: string;
  platform: Platform;
}) => string | undefined | Promise<string | undefined>;
export type PostPeerAccountIds = Partial<Record<Platform, string>>;

type PostPeerPlatformResult = {
  platform?: string;
  status?: string;
  success?: boolean;
  platformPostId?: string;
  platformPostUrl?: string;
  errorMessage?: string | null;
  error?: string;
};

type PostPeerPublishResponse = {
  success?: boolean;
  status?: string;
  id?: string;
  externalPostId?: string;
  postId?: string;
  message?: string;
  errorMessage?: string | null;
  error?: string;
  platforms?: PostPeerPlatformResult[];
  post?: Omit<PostPeerPublishResponse, 'post'>;
};

type PostPeerResolvedPayload = Omit<PostPeerPublishResponse, 'post'>;

type PostPeerPublishEvaluation =
  | { outcome: 'publishing'; postId?: string }
  | { outcome: 'published'; externalPostId: string }
  | { outcome: 'failed'; message: string };

export class PostPeerPublishOutcomeUnknownError extends PublishOutcomeUnknownError {
  constructor(message: string) {
    super(message);
    this.name = 'PostPeerPublishOutcomeUnknownError';
  }
}

const finalPostStatuses = new Set(['published', 'partial']);
const publishingPostStatuses = new Set(['pending', 'publishing']);
const failedPostStatuses = new Set(['failed']);
// Video uploads can take well beyond the create endpoint's own wait window.
// Poll for up to roughly two minutes before declaring the outcome unknown.
const defaultMaxPollAttempts = 60;
const defaultPollIntervalMs = 2_000;
const youtubeTitleMaxLength = 100;

const sleepWithTimer: Sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

const readNormalizedStatus = (status?: string) => status?.trim().toLowerCase();

const readNonEmptyString = (value?: string | null) => {
  const normalized = value?.trim();
  return normalized || undefined;
};

const unwrapPostPeerPayload = (payload: PostPeerPublishResponse): PostPeerResolvedPayload => {
  if (!payload.post) {
    return payload;
  }

  return {
    ...payload.post,
    success: payload.success ?? payload.post.success,
    status: payload.post.status ?? payload.status,
    id: payload.post.id ?? payload.id,
    externalPostId: payload.post.externalPostId ?? payload.externalPostId,
    postId: payload.post.postId ?? payload.postId,
    message: payload.message ?? payload.post.message,
    errorMessage: payload.errorMessage ?? payload.post.errorMessage,
    error: payload.error ?? payload.post.error
  };
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

    if (!normalizedUserId) {
      throw new Error(`User id is required to resolve a connected PostPeer account for ${platform}`);
    }

    const resolvedAccountId = (
      await resolveAccountId({
        userId: normalizedUserId,
        platform
      })
    )?.trim();

    if (resolvedAccountId) {
      return resolvedAccountId;
    }

    throw new Error(`Connected PostPeer account is required to publish ${platform}`);
  }

  const accountId = accountIds[platform]?.trim();

  if (!accountId) {
    throw new Error(`${postPeerAccountIdEnv[platform]} is required to publish ${platform}`);
  }

  return accountId;
};

const readPlatformResult = (payload: PostPeerPublishResponse, platform: Platform) => {
  const postPeerPlatformId = postPeerPlatform[platform];

  return payload.platforms?.find(
    (result) => result.platform?.trim().toLowerCase() === postPeerPlatformId
  );
};

const readFailureMessage = (
  payload: PostPeerResolvedPayload,
  platformResult?: PostPeerPlatformResult
) =>
  readNonEmptyString(platformResult?.errorMessage) ??
  readNonEmptyString(platformResult?.error) ??
  readNonEmptyString(payload.errorMessage) ??
  readNonEmptyString(payload.error) ??
  readNonEmptyString(payload.message) ??
  'platform failed';

const evaluatePostPeerPayload = (
  rawPayload: PostPeerPublishResponse,
  platform: Platform
): PostPeerPublishEvaluation => {
  const payload = unwrapPostPeerPayload(rawPayload);
  const platformResult = readPlatformResult(payload, platform);
  const postStatus = readNormalizedStatus(payload.status);
  const platformStatus = readNormalizedStatus(platformResult?.status);
  const postId = readNonEmptyString(payload.postId) ?? readNonEmptyString(payload.id);

  if (
    payload.success === false ||
    (postStatus && failedPostStatuses.has(postStatus)) ||
    platformResult?.success === false ||
    (platformStatus && failedPostStatuses.has(platformStatus))
  ) {
    return {
      outcome: 'failed',
      message: readFailureMessage(payload, platformResult)
    };
  }

  if (
    (postStatus && publishingPostStatuses.has(postStatus)) ||
    (platformStatus && publishingPostStatuses.has(platformStatus))
  ) {
    return { outcome: 'publishing', postId };
  }

  const externalPostId =
    readNonEmptyString(platformResult?.platformPostUrl) ??
    readNonEmptyString(platformResult?.platformPostId) ??
    readNonEmptyString(payload.externalPostId);

  if (postStatus && finalPostStatuses.has(postStatus)) {
    if (!externalPostId) {
      return {
        outcome: 'failed',
        message: 'PostPeer did not return a platform post URL or id'
      };
    }

    return { outcome: 'published', externalPostId };
  }

  // Keep compatibility with providers that return an explicit external id but
  // omit `status`. Unlike the old fallback, this is a real provider value and
  // never fabricates an id from the PostDee post id.
  if (!postStatus && externalPostId) {
    return { outcome: 'published', externalPostId };
  }

  return {
    outcome: 'failed',
    message: postStatus
      ? `PostPeer returned non-published status ${postStatus}`
      : 'PostPeer did not return a final publish status'
  };
};

const deriveYoutubeTitle = (caption?: string) => {
  const normalized = caption?.replace(/\s+/g, ' ').trim() || 'PostDee video';
  return [...normalized].slice(0, youtubeTitleMaxLength).join('').trim() || 'PostDee video';
};

const buildPlatformTarget = ({
  platform,
  accountId,
  caption
}: {
  platform: Platform;
  accountId: string;
  caption?: string;
}) => {
  const target: {
    platform: string;
    accountId: string;
    platformSpecificData?: Record<string, string | boolean>;
  } = {
    platform: postPeerPlatform[platform],
    accountId
  };

  if (platform === 'YOUTUBE_SHORTS') {
    // Controlled-first safety default. Public rollout needs an explicit
    // user-selected visibility passed through the publish input.
    target.platformSpecificData = {
      title: deriveYoutubeTitle(caption),
      visibility: 'private'
    };
  } else if (platform === 'TIKTOK') {
    target.platformSpecificData = {
      // Controlled-first safety default: TikTok requires unaudited clients to
      // use SELF_ONLY. Public rollout needs explicit creator privacy controls.
      // `draft: false` keeps this a direct post whose final status can be polled
      // while still limiting the first controlled release to the account owner.
      privacyLevel: 'SELF_ONLY',
      draft: false
    };
  }

  return target;
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
  maxPollAttempts = defaultMaxPollAttempts,
  pollIntervalMs = defaultPollIntervalMs,
  sleep = sleepWithTimer,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  baseUrl: string;
  accountIds?: PostPeerAccountIds;
  resolveAccountId?: ResolveAccountId;
  resolveVideoUrl?: ResolveVideoUrl;
  now?: () => string;
  maxPollAttempts?: number;
  pollIntervalMs?: number;
  sleep?: Sleep;
  fetchImpl?: FetchImpl;
}): PlatformPublisher => ({
  publish: async ({ userId, caption, videoS3Key, platform }) => {
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

    let response: FetchResponse;

    try {
      response = await fetchImpl(`${baseUrl}/v1/posts`, {
        method: 'POST',
        headers: {
          'x-access-key': apiKey,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          content: caption ?? '',
          platforms: [buildPlatformTarget({ platform, accountId, caption })],
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
    } catch {
      // A network failure does not prove that PostPeer rejected the request.
      // Retrying the POST could create a duplicate because their API does not
      // document an idempotency key.
      throw new PostPeerPublishOutcomeUnknownError(
        `PostPeer publish to ${platform} outcome is unknown after the create request failed`
      );
    }

    if (!response.ok) {
      throw new Error(
        `PostPeer publish to ${platform} failed with status ${response.status ?? 'unknown'}`
      );
    }

    let payload: PostPeerPublishResponse;

    try {
      payload = (await response.json()) as PostPeerPublishResponse;
    } catch {
      throw new PostPeerPublishOutcomeUnknownError(
        `PostPeer publish to ${platform} outcome is unknown because the create response was invalid`
      );
    }
    let evaluation = evaluatePostPeerPayload(payload, platform);

    if (evaluation.outcome === 'failed') {
      throw new Error(
        `PostPeer publish to ${platform} failed: ${evaluation.message}`
      );
    }

    if (evaluation.outcome === 'published') {
      return {
        platform,
        status: 'PUBLISHED',
        externalPostId: evaluation.externalPostId,
        publishedAt: now()
      };
    }

    const providerPostId = evaluation.postId;

    if (!providerPostId) {
      throw new PostPeerPublishOutcomeUnknownError(
        `PostPeer publish to ${platform} is still processing but did not return a post id`
      );
    }

    const boundedMaxPollAttempts = Math.max(1, Math.floor(maxPollAttempts));
    const boundedPollIntervalMs = Math.max(0, pollIntervalMs);

    for (let attempt = 0; attempt < boundedMaxPollAttempts; attempt += 1) {
      if (attempt > 0 && boundedPollIntervalMs > 0) {
        await sleep(boundedPollIntervalMs);
      }

      try {
        const statusResponse = await fetchImpl(
          `${baseUrl}/v1/posts/${encodeURIComponent(providerPostId)}`,
          {
            method: 'GET',
            headers: {
              'x-access-key': apiKey
            }
          }
        );

        if (!statusResponse.ok) {
          continue;
        }

        const statusPayload = (await statusResponse.json()) as PostPeerPublishResponse;
        evaluation = evaluatePostPeerPayload(statusPayload, platform);
      } catch {
        // GET status checks are read-only, so bounded retries are safe.
        continue;
      }

      if (evaluation.outcome === 'failed') {
        throw new Error(`PostPeer publish to ${platform} failed: ${evaluation.message}`);
      }

      if (evaluation.outcome === 'published') {
        return {
          platform,
          status: 'PUBLISHED',
          externalPostId: evaluation.externalPostId,
          publishedAt: now()
        };
      }
    }

    throw new PostPeerPublishOutcomeUnknownError(
      `PostPeer publish to ${platform} outcome is still unknown after ${boundedMaxPollAttempts} status checks`
    );
  }
});
