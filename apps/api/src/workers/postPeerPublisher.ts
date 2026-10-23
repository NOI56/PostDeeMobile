import type { Platform } from '../modules/posts/postStore.js';
import { readEffectivePlatformCaption, type PlatformSettings } from '../modules/posts/platformSettings.js';
import { PlatformCaptionValidationError, readPlatformCaptionIssue } from '../modules/posts/platformCaptionValidation.js';
import {
  buildTikTokConnectionRevision,
  isExplicitTikTokDirectSettings,
  validateTikTokDirectCaption,
  validateTikTokDirectSettings
} from '../modules/posts/tikTokDirectSettings.js';
import type { PostPeerTikTokClient } from '../modules/socialConnections/postPeerTikTokClient.js';
import {
  isSamePlatformTarget,
  normalizePersistedPlatformTargets,
  type PlatformTargets,
  type ResolveCurrentPlatformTarget
} from '../modules/posts/platformTargets.js';
import {
  readPlatformSettingsForPublish,
  readRequestedDeliveryOutcome
} from './platformDeliveryOutcome.js';
import {
  PlatformPublishRejectionError,
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
  | { outcome: 'published'; externalPostId?: string; providerPostId?: string }
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
const draftPostStatus = 'draft';
const tikTokInboxReceiptPattern = /^v_inbox_(?:url|file)~v2\.[0-9]+$/;
const tikTokPublishReceiptPrefix = /^v_(?:inbox|pub)_(?:url|file)~/;
const tikTokDirectReceiptPattern = /^v_pub_(?:url|file)~v2(?:-[1-9][0-9]*)?\.[0-9]+$/;
const tikTokVideoIdPattern = /^[0-9]{10,30}$/;
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

const readTikTokVideoUrl = (value?: string): string | undefined => {
  if (!value || value.includes('\\')) return undefined;
  try {
    const url = new URL(value);
    if (
      url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      (url.hostname === 'tiktok.com' || url.hostname.endsWith('.tiktok.com')) &&
      /^\/@[^/]+\/video\/[0-9]{10,30}\/?$/.test(url.pathname)
    ) {
      return url.toString();
    }
  } catch {
    // A provider reference is not automatically a link to a TikTok video.
  }
  return undefined;
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
  resolveCurrentPlatformTarget,
  userId,
  platform,
  platformTargets,
  expectedTikTokCreatorInfoRevision
}: {
  accountIds: PostPeerAccountIds;
  resolveAccountId?: ResolveAccountId;
  resolveCurrentPlatformTarget?: ResolveCurrentPlatformTarget;
  userId?: string;
  platform: Platform;
  platformTargets?: PlatformTargets | null;
  expectedTikTokCreatorInfoRevision?: string;
}) => {
  if (platformTargets != null) {
    const normalizedUserId = userId?.trim();
    if (!normalizedUserId) {
      throw new Error(`User id is required to revalidate the publish target for ${platform}`);
    }
    if (!resolveCurrentPlatformTarget) {
      throw new Error(`Publish target revalidation is required for ${platform}`);
    }
    const normalizedTargets = normalizePersistedPlatformTargets(
      { [platform]: platformTargets[platform] },
      [platform]
    );
    const snapshottedTarget = normalizedTargets?.[platform];
    if (!snapshottedTarget) {
      throw new Error(`Persisted publish target is invalid for ${platform}`);
    }
    const currentTarget = await resolveCurrentPlatformTarget({
      userId: normalizedUserId,
      platform
    });
    if (!currentTarget || !isSamePlatformTarget(snapshottedTarget, currentTarget)) {
      throw new Error(`Connected publish target changed before publishing ${platform}`);
    }
    if (expectedTikTokCreatorInfoRevision &&
        buildTikTokConnectionRevision({ userId: normalizedUserId, target: currentTarget }) !== expectedTikTokCreatorInfoRevision) {
      throw new Error('The TikTok creator information revision changed before publishing');
    }
    return snapshottedTarget.accountId;
  }

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

const createPostPeerFailure = (platform: Platform, message: string) =>
  platform === 'TIKTOK' && /\bframe_rate_check_failed\b/i.test(message)
    ? new PlatformPublishRejectionError()
    : new Error(`PostPeer publish to ${platform} failed: ${message}`);

const evaluatePostPeerPayload = (
  rawPayload: PostPeerPublishResponse,
  platform: Platform,
  requestedDeliveryOutcome: ReturnType<typeof readRequestedDeliveryOutcome>,
  knownProviderPostId?: string,
  requireTikTokDirectProof = false
): PostPeerPublishEvaluation => {
  const payload = unwrapPostPeerPayload(rawPayload);
  const platformResult = readPlatformResult(payload, platform);
  const postStatus = readNormalizedStatus(payload.status);
  const platformStatus = readNormalizedStatus(platformResult?.status);
  const platformPostId = readNonEmptyString(platformResult?.platformPostId);
  const returnedProviderPostId =
    readNonEmptyString(payload.postId) ??
    readNonEmptyString(payload.id);
  const providerPostId = knownProviderPostId ?? returnedProviderPostId;
  if (
    knownProviderPostId && returnedProviderPostId &&
    returnedProviderPostId !== knownProviderPostId
  ) {
    // A status response for another record cannot confirm this CREATE request.
    return { outcome: 'publishing', postId: knownProviderPostId };
  }
  const hasTikTokInboxReceipt =
    platform === 'TIKTOK' &&
    platformPostId !== undefined &&
    tikTokInboxReceiptPattern.test(platformPostId);
  // An Inbox publish receipt belongs to TikTok, not PostPeer's GET /posts/:id.
  // Never use it as a fallback provider id when polling a pending response.
  const postId = requireTikTokDirectProof
    ? providerPostId && !tikTokPublishReceiptPrefix.test(providerPostId) ? providerPostId : undefined
    : providerPostId ?? (hasTikTokInboxReceipt ? undefined : platformPostId);

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
    platformPostId ??
    readNonEmptyString(payload.externalPostId);

  const hasExplicitDraftStatus =
    postStatus === draftPostStatus || platformStatus === draftPostStatus;
  const hasExplicitPublishedStatus =
    Boolean(postStatus && finalPostStatuses.has(postStatus)) ||
    Boolean(platformStatus && finalPostStatuses.has(platformStatus));
  const hasExplicitPublishedSuccessStatus =
    postStatus === 'published' || platformStatus === 'published';

  if (platform === 'TIKTOK' && requireTikTokDirectProof) {
    const videoUrl = readTikTokVideoUrl(platformResult?.platformPostUrl);
    const videoId = platformPostId && tikTokVideoIdPattern.test(platformPostId)
      ? platformPostId
      : undefined;
    const directReceipt = platformPostId && tikTokDirectReceiptPattern.test(platformPostId);
    // TikTok's Inbox URL/receipt is never evidence that Direct Post completed.
    // Ambiguous successful CREATE responses must be reconciled by GET without
    // issuing another POST. A final private post may have a direct receipt but
    // no video URL, so do not fabricate a public link for it.
    if (
      providerPostId && !tikTokPublishReceiptPrefix.test(providerPostId) &&
      platformStatus === 'published' && !hasExplicitDraftStatus && !hasTikTokInboxReceipt &&
      (videoUrl || videoId || directReceipt)
    ) {
      return {
        outcome: 'published', providerPostId,
        ...(videoUrl || videoId ? { externalPostId: videoUrl ?? videoId } : {})
      };
    }
    return {
      outcome: 'publishing',
      ...(providerPostId && !tikTokPublishReceiptPrefix.test(providerPostId)
        ? { postId: providerPostId }
        : {})
    };
  }

  if (requestedDeliveryOutcome === 'DRAFT') {
    if (hasTikTokInboxReceipt && platformStatus === 'published') {
      if (!providerPostId) {
        return {
          outcome: 'failed',
          message: 'PostPeer did not return a provider post id for the draft'
        };
      }
      // PostPeer calls a completed Inbox handoff "published". The requested
      // delivery is still a draft that the user must finish inside TikTok.
      // Its messages URL is not a public video reference.
      return { outcome: 'published', providerPostId };
    }
    if (
      platform === 'TIKTOK' &&
      postStatus === 'published' &&
      platformResult?.success === true &&
      platformStatus === undefined &&
      platformPostId === undefined &&
      providerPostId &&
      !tikTokPublishReceiptPrefix.test(providerPostId)
    ) {
      // CREATE's documented success summary omits platform status and Inbox
      // receipt. Read GET /posts/:id for canonical proof before confirming DRAFT.
      return { outcome: 'publishing', postId: providerPostId };
    }
    const facebookPageDraftConfirmedAsPublished =
      platform === 'FACEBOOK_REELS' && hasExplicitPublishedSuccessStatus;
    if (hasExplicitDraftStatus || facebookPageDraftConfirmedAsPublished) {
      if (!postId) {
        return {
          outcome: 'failed',
          message: 'PostPeer did not return a provider post id for the draft'
        };
      }
      return {
        outcome: 'published',
        providerPostId: postId,
        ...(externalPostId ? { externalPostId } : {})
      };
    }
    return {
      outcome: 'failed',
      message: 'PostPeer did not return an explicit final draft status'
    };
  }

  if (hasExplicitDraftStatus || hasTikTokInboxReceipt) {
    return {
      outcome: 'failed',
      message: 'PostPeer returned a draft for a non-draft publish request'
    };
  }

  if (hasExplicitPublishedStatus) {
    if (!externalPostId) {
      return {
        outcome: 'failed',
        message: 'PostPeer did not return a platform post URL or id'
      };
    }

    return {
      outcome: 'published',
      externalPostId,
      ...(postId ? { providerPostId: postId } : {})
    };
  }

  // Keep compatibility with providers that return an explicit external id but
  // omit `status`. Unlike the old fallback, this is a real provider value and
  // never fabricates an id from the PostDee post id.
  if (!postStatus && externalPostId) {
    return {
      outcome: 'published',
      externalPostId,
      ...(postId ? { providerPostId: postId } : {})
    };
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
  caption,
  coverUrl,
  coverFrameTimeMs,
  platformSettings
}: {
  platform: Platform;
  accountId: string;
  caption?: string;
  coverUrl?: string;
  coverFrameTimeMs?: number;
  platformSettings: PlatformSettings;
}) => {
  const target: {
    platform: string;
    accountId: string;
    platformSpecificData?: Record<string, string | boolean | number>;
  } = {
    platform: postPeerPlatform[platform],
    accountId
  };

  if (platform === 'YOUTUBE_SHORTS') {
    const youtubeSettings = platformSettings.YOUTUBE_SHORTS;
    if (!youtubeSettings) {
      throw new Error('YouTube publish settings are required');
    }
    target.platformSpecificData = {
      title: 'title' in youtubeSettings ? youtubeSettings.title : deriveYoutubeTitle(caption),
      visibility: youtubeSettings.visibility,
      ...('title' in youtubeSettings
        ? {
            madeForKids: youtubeSettings.madeForKids,
            containsSyntheticMedia: youtubeSettings.containsSyntheticMedia
          }
        : {})
    };
  } else if (platform === 'TIKTOK') {
    const tiktokSettings = platformSettings.TIKTOK;
    if (!tiktokSettings) {
      throw new Error('TikTok publish settings are required');
    }
    target.platformSpecificData = {
      ...(tiktokSettings.publishMode === 'DIRECT_POST'
        ? {
            privacyLevel: tiktokSettings.privacyLevel, draft: false,
            ...(isExplicitTikTokDirectSettings(tiktokSettings)
              ? {
                  disableComment: tiktokSettings.disableComment,
                  disableDuet: tiktokSettings.disableDuet,
                  disableStitch: tiktokSettings.disableStitch,
                  brandContentToggle: tiktokSettings.brandContentToggle,
                  brandOrganicToggle: tiktokSettings.brandOrganicToggle,
                  isAigc: tiktokSettings.isAigc
                }
              : {})
          }
        : { draft: true }),
      ...(coverFrameTimeMs !== undefined
        ? { videoCoverTimestampMs: coverFrameTimeMs }
        : {})
    };
  } else if (platform === 'INSTAGRAM_REELS') {
    const instagramSettings = platformSettings.INSTAGRAM_REELS;
    if (!instagramSettings) {
      throw new Error('Instagram publish settings are required');
    }
    target.platformSpecificData = {
      shareToFeed: instagramSettings.shareToFeed,
      ...(instagramSettings.isAiGenerated !== undefined
        ? { isAiGenerated: instagramSettings.isAiGenerated }
        : {}),
      ...(coverUrl
        ? { coverUrl }
        : coverFrameTimeMs !== undefined
          ? { thumbOffset: coverFrameTimeMs }
          : {})
    };
  } else if (platform === 'FACEBOOK_REELS') {
    const facebookSettings = platformSettings.FACEBOOK_REELS;
    if (!facebookSettings) {
      throw new Error('Facebook publish settings are required');
    }
    target.platformSpecificData = {
      published: facebookSettings.publishMode === 'PUBLISH',
      ...(facebookSettings.isAiGenerated !== undefined
        ? { isAiGenerated: facebookSettings.isAiGenerated }
        : {}),
      ...(coverUrl ? { videoThumbnailUrl: coverUrl } : {})
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
  resolveCurrentPlatformTarget,
  tikTokClient,
  assertOwnerActive,
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
  resolveCurrentPlatformTarget?: ResolveCurrentPlatformTarget;
  tikTokClient?: PostPeerTikTokClient;
  assertOwnerActive?: (userId: string) => Promise<void>;
  resolveVideoUrl?: ResolveVideoUrl;
  now?: () => string;
  maxPollAttempts?: number;
  pollIntervalMs?: number;
  sleep?: Sleep;
  fetchImpl?: FetchImpl;
}): PlatformPublisher => ({
  publish: async ({
    userId,
    caption,
    videoS3Key,
    coverImageS3Key,
    coverFrameTimeMs,
    platform,
    platformSettings,
    platformTargets
  }) => {
    const normalizedPlatformSettings = readPlatformSettingsForPublish({
      platform,
      platformSettings
    });
    caption = readEffectivePlatformCaption(caption, platform, normalizedPlatformSettings);
    const captionIssue = readPlatformCaptionIssue(caption, [platform]);
    if (captionIssue) throw new PlatformCaptionValidationError(captionIssue);
    const requestedDeliveryOutcome = readRequestedDeliveryOutcome({
      platform,
      platformSettings
    });
    const explicitTikTokSettings = platform === 'TIKTOK' &&
      isExplicitTikTokDirectSettings(normalizedPlatformSettings.TIKTOK)
      ? normalizedPlatformSettings.TIKTOK
      : undefined;
    if (explicitTikTokSettings) validateTikTokDirectCaption(caption);
    if (explicitTikTokSettings && (!userId || !platformTargets?.TIKTOK || !resolveCurrentPlatformTarget || !assertOwnerActive)) {
      throw new Error('A persisted owner publish target is required for TikTok Direct Post');
    }
    if (
      explicitTikTokSettings && userId && platformTargets?.TIKTOK &&
      explicitTikTokSettings.creatorInfoRevision !== buildTikTokConnectionRevision({
        userId, target: platformTargets.TIKTOK
      })
    ) {
      throw new Error('The TikTok creator information revision no longer matches the publish target');
    }
    const accountId = await readPostPeerAccountId({
      accountIds,
      resolveAccountId,
      resolveCurrentPlatformTarget,
      userId,
      platform,
      platformTargets,
      expectedTikTokCreatorInfoRevision: explicitTikTokSettings?.creatorInfoRevision
    });
    if (explicitTikTokSettings) {
      if (!tikTokClient) {
        throw new Error('Current TikTok creator information is required for Direct Post');
      }
      const creatorInfo = await tikTokClient.getCreatorInfo({ accountId });
      validateTikTokDirectSettings(creatorInfo, explicitTikTokSettings);
    }
    const videoUrl = videoS3Key
      ? resolveVideoUrl
        ? await resolveVideoUrl(videoS3Key)
        : videoS3Key
      : undefined;
    // PostPeer accepts custom cover image URLs only for Instagram and
    // Facebook. TikTok selects a frame timestamp, while YouTube thumbnails
    // require a separate authenticated API flow and must not be sent here.
    const shouldResolveCoverImage =
      platform === 'INSTAGRAM_REELS' || platform === 'FACEBOOK_REELS';
    const coverUrl =
      shouldResolveCoverImage && coverImageS3Key
        ? resolveVideoUrl
          ? await resolveVideoUrl(coverImageS3Key)
          : coverImageS3Key
        : undefined;

    if (explicitTikTokSettings) {
      // Account reconnection while fetching creator info/media must not send
      // the immutable intent to the account that has since been replaced.
      await readPostPeerAccountId({
        accountIds, resolveAccountId, resolveCurrentPlatformTarget,
        userId, platform, platformTargets,
        expectedTikTokCreatorInfoRevision: explicitTikTokSettings.creatorInfoRevision
      });
      await assertOwnerActive!(userId!);
    }

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
          platforms: [
            buildPlatformTarget({
              platform,
              accountId,
              caption,
              coverUrl,
              coverFrameTimeMs,
              platformSettings: normalizedPlatformSettings
            })
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
    } catch {
      // A network failure does not prove that PostPeer rejected the request.
      // This adapter does not supply a stable provider idempotency key, so
      // retrying the POST could create a duplicate.
      throw new PostPeerPublishOutcomeUnknownError(
        `PostPeer publish to ${platform} outcome is unknown after the create request failed`
      );
    }

    if (!response.ok) {
      if (explicitTikTokSettings && (response.status === undefined || response.status >= 500)) {
        throw new PostPeerPublishOutcomeUnknownError(
          'PostPeer TikTok Direct Post outcome is unknown after a create response server error'
        );
      }
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
    let evaluation: PostPeerPublishEvaluation;
    try {
      evaluation = evaluatePostPeerPayload(
        payload, platform, requestedDeliveryOutcome, undefined,
        explicitTikTokSettings !== undefined
      );
    } catch (error) {
      if (!explicitTikTokSettings) throw error;
      throw new PostPeerPublishOutcomeUnknownError(
        'PostPeer TikTok Direct Post outcome is unknown because its confirmation could not be read'
      );
    }

    if (evaluation.outcome === 'failed') {
      throw createPostPeerFailure(platform, evaluation.message);
    }

    if (evaluation.outcome === 'published') {
      return {
        platform,
        status: 'PUBLISHED',
        ...(evaluation.externalPostId
          ? { externalPostId: evaluation.externalPostId }
          : {}),
        ...(evaluation.providerPostId
          ? { providerPostId: evaluation.providerPostId }
          : {}),
        deliveryOutcome: requestedDeliveryOutcome,
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
        evaluation = evaluatePostPeerPayload(
          statusPayload,
          platform,
          requestedDeliveryOutcome,
          providerPostId,
          explicitTikTokSettings !== undefined
        );
      } catch {
        // GET status checks are read-only, so bounded retries are safe.
        continue;
      }

      if (evaluation.outcome === 'failed') {
        throw createPostPeerFailure(platform, evaluation.message);
      }

      if (evaluation.outcome === 'published') {
        return {
          platform,
          status: 'PUBLISHED',
          ...(evaluation.externalPostId
            ? { externalPostId: evaluation.externalPostId }
            : {}),
          ...(evaluation.providerPostId
            ? { providerPostId: evaluation.providerPostId }
            : {}),
          deliveryOutcome: requestedDeliveryOutcome,
          publishedAt: now()
        };
      }
    }

    throw new PostPeerPublishOutcomeUnknownError(
      `PostPeer publish to ${platform} outcome is still unknown after ${boundedMaxPollAttempts} status checks`
    );
  }
});
