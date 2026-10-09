import { randomUUID } from 'node:crypto';

import type { RequestHandler, Router } from 'express';

import {
  createOwnerMutationLock,
  type OwnerMutationLock
} from '../account/ownerMutationLock.js';
import { readAuthUser } from '../auth/authTypes.js';
import type {
  PlatformPublishStore,
  RecordedPlatformPublish
} from '../platformPublishes/platformPublishStore.js';
import type { PublishQueue } from '../queue/publishQueue.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import {
  canSchedulePosts,
  maxScheduleAheadDaysByPlan,
  monthlyPostUnitLimits,
  readPlanLabel
} from '../subscriptions/subscriptionEntitlements.js';
import type { SubscriptionPlan, SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import {
  PostIdempotencyKeyReusedError,
  buildIdempotentPostId,
  isMatchingIdempotentIntent,
  type CreatePostWithinMonthlyLimitInput,
  type Platform,
  type PostStore,
  type QueuedPost,
  isValidPlatform
} from './postStore.js';
import { readPlatformSettings } from './platformSettings.js';
import {
  arePlatformTargetsEqual,
  normalizePersistedPlatformTargets,
  type PlatformTargets,
  type ResolveCurrentPlatformTarget
} from './platformTargets.js';

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readPlatforms = (value: unknown) => {
  if (!Array.isArray(value)) {
    return { ok: false as const, value: [], hadDuplicates: false };
  }

  const valid = value.filter(isValidPlatform);
  const deduped = [...new Set(valid)];
  return {
    ok: valid.length === value.length && deduped.length > 0,
    value: deduped,
    hadDuplicates: deduped.length !== valid.length
  };
};

const clientRequestIdPattern = /^[A-Za-z0-9._:-]{1,128}$/;
const readOptionalClientRequestId = (value: unknown) => {
  if (value === undefined) {
    return { ok: true as const, value: undefined };
  }

  const requestId = readRequiredString(value);
  return requestId && clientRequestIdPattern.test(requestId)
    ? { ok: true as const, value: requestId }
    : { ok: false as const, value: undefined };
};

const invalidClientRequestIdResponse = {
  status: 'error',
  code: 'INVALID_CLIENT_REQUEST_ID',
  message:
    'clientRequestId must be 1-128 ASCII letters, numbers, dots, underscores, colons, or hyphens'
} as const;

const readOptionalMediaContentFingerprint = (value: unknown) =>
  value === undefined
    ? { ok: true as const, value: undefined }
    : typeof value === 'string' && /^[0-9a-f]{64}$/.test(value)
      ? { ok: true as const, value }
      : { ok: false as const, value: undefined };

const idempotencyKeyReusedResponse = {
  status: 'error',
  code: 'IDEMPOTENCY_KEY_REUSED',
  message: 'clientRequestId was already used for a different publishing intent'
} as const;

const idempotentPostFailedResponse = (postId: string) => ({
  status: 'error',
  code: 'IDEMPOTENT_POST_FAILED',
  message: 'The original post request already reached a failed terminal state',
  postId
});

const isoDateTimeWithTimezonePattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$/;

const isLeapYear = (year: number) =>
  year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);

const daysInMonth = (year: number, month: number) => {
  if (month === 2) {
    return isLeapYear(year) ? 29 : 28;
  }

  return [4, 6, 9, 11].includes(month) ? 30 : 31;
};

const readStrictIsoDate = (value: string) => {
  const match = isoDateTimeWithTimezonePattern.exec(value);

  if (!match) {
    return undefined;
  }

  const [
    ,
    yearText,
    monthText,
    dayText,
    hourText,
    minuteText,
    secondText,
    fractionText,
    timezone,
    offsetSign,
    offsetHourText,
    offsetMinuteText
  ] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  const offsetHours = Number(offsetHourText ?? 0);
  const offsetMinutes = Number(offsetMinuteText ?? 0);

  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    offsetHours > 23 ||
    offsetMinutes > 59
  ) {
    return undefined;
  }

  const milliseconds = Number((fractionText ?? '').slice(0, 3).padEnd(3, '0'));
  const localDate = new Date(0);
  localDate.setUTCFullYear(year, month - 1, day);
  localDate.setUTCHours(hour, minute, second, milliseconds);
  const signedOffsetMinutes =
    timezone === 'Z'
      ? 0
      : (offsetSign === '+' ? 1 : -1) * (offsetHours * 60 + offsetMinutes);
  const timestamp = localDate.getTime() - signedOffsetMinutes * 60_000;

  if (!Number.isFinite(timestamp)) {
    return undefined;
  }

  return new Date(timestamp).toISOString();
};

const readOptionalIsoDate = (value: unknown) => {
  if (value === undefined || value === null) {
    return { ok: true as const, value: undefined };
  }

  const rawDate = readRequiredString(value);

  if (!rawDate) {
    return { ok: false as const, value: undefined };
  }

  const normalizedDate = readStrictIsoDate(rawDate);
  return normalizedDate === undefined
    ? { ok: false as const, value: undefined }
    : { ok: true as const, value: normalizedDate };
};

export const platformSettingsVersion = 1;

const isScheduleBeyondLimit = (scheduledAt: string, now: Date, maxDays: number) =>
  Date.parse(scheduledAt) > now.getTime() + maxDays * 24 * 60 * 60 * 1000;

const isScheduleInPastOrPresent = (scheduledAt: string, now: Date) =>
  Date.parse(scheduledAt) <= now.getTime();

const invalidPlatformsResponse = {
  status: 'error',
  code: 'INVALID_PLATFORMS',
  message: 'platforms must contain at least one supported platform'
} as const;

const invalidPlatformSettingsResponse = {
  status: 'error',
  code: 'INVALID_PLATFORM_SETTINGS',
  message:
    'platformSettings must contain exactly one valid settings object for every selected platform'
} as const;

const platformTargetUnavailableResponse = {
  status: 'error',
  code: 'PLATFORM_TARGET_UNAVAILABLE',
  message: 'A selected connected account is no longer available. Review the post again.'
} as const;

const toPublicPost = ({ platformTargets: _platformTargets, mediaContentFingerprint: _mediaContentFingerprint, ...post }: QueuedPost) => post;
const toPublicPlatformResult = ({
  providerPostId: _providerPostId,
  ...result
}: RecordedPlatformPublish) => result;

const readOptionalCoverImageKey = (value: unknown) => {
  if (value === undefined || value === null) {
    return { ok: true as const, value: undefined };
  }

  const key = readRequiredString(value);
  return key
    ? { ok: true as const, value: key }
    : { ok: false as const, value: undefined };
};

const readOptionalCoverFrameTimeMs = (value: unknown) => {
  if (value === undefined || value === null) {
    return { ok: true as const, value: undefined };
  }

  return typeof value === 'number' &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= 2_147_483_647
    ? { ok: true as const, value }
    : { ok: false as const, value: undefined };
};

const socialPublishingUnavailableResponse = {
  status: 'error',
  code: 'SOCIAL_PUBLISHING_UNAVAILABLE',
  message: 'Social publishing is temporarily unavailable. Please try again later.'
} as const;

type SubscriptionPlanOverrideResult =
  | {
      ok: true;
      plan?: SubscriptionPlan;
    }
  | {
      ok: false;
      message: string;
    };

const readSubscriptionPlanOverride = (value: unknown): SubscriptionPlanOverrideResult => {
  if (value === undefined || value === null) {
    return {
      ok: true as const,
      plan: undefined
    };
  }

  if (value === 'BASIC' || value === 'STARTER' || value === 'PRO') {
    return {
      ok: true as const,
      plan: value
    };
  }

  return {
    ok: false as const,
    message: 'subscriptionPlan must be BASIC, STARTER, or PRO'
  };
};

export const postCoverUploadPolicy = {
  acceptedContentTypes: ['image/jpeg', 'image/png'] as const,
  maxSizeBytes: 2 * 1024 * 1024
};

export const registerPostRoutes = (
  router: Router,
  store: PostStore,
  publishQueue: PublishQueue,
  authMiddleware: RequestHandler,
  userStore: UserStore,
  subscriptionStore: SubscriptionStore,
  platformPublishStore: PlatformPublishStore,
  options: {
    allowSubscriptionPlanOverride?: boolean;
    socialPublishingEnabled?: boolean;
    assertOwnerActive?: (ownerId: string) => Promise<void>;
    ownerMutationLock?: OwnerMutationLock;
    resolvePlatformTarget?: ResolveCurrentPlatformTarget;
    assertUploadReady?: (ownerId: string, videoS3Key: string) => Promise<void>;
    assertCoverUploadReady?: (ownerId: string, coverImageS3Key: string) => Promise<void>;
    createMediaDownloadUrl?: (storageKey: string) => Promise<string | undefined>;
    now?: () => Date;
  } = {}
) => {
  const allowSubscriptionPlanOverride = options.allowSubscriptionPlanOverride ?? true;
  const socialPublishingEnabled = options.socialPublishingEnabled ?? true;
  const now = options.now ?? (() => new Date());
  const ownerMutationLock = options.ownerMutationLock ?? createOwnerMutationLock();
  const creationLocks = new Map<string, Promise<void>>();
  const mutationLocks = new Map<string, Promise<void>>();

  const createOptionalPreviewUrl = async (storageKey: string | undefined, userId: string) => {
    if (
      !storageKey ||
      !options.createMediaDownloadUrl ||
      !isStorageKeyOwnedByUser({ videoS3Key: storageKey, userId })
    ) {
      return undefined;
    }

    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      const rawUrl = await Promise.race([
        options.createMediaDownloadUrl(storageKey),
        new Promise<undefined>((resolve) => {
          timeout = setTimeout(() => resolve(undefined), 1500);
        })
      ]);
      if (!rawUrl) return undefined;
      const url = new URL(rawUrl);
      return (url.protocol === 'https:' || url.protocol === 'http:') &&
        url.hostname && !url.username && !url.password
        ? rawUrl
        : undefined;
    } catch {
      // Media is temporary. A removed object or unavailable signer must not
      // hide an otherwise valid post or expose provider errors/signed URLs.
      return undefined;
    } finally {
      if (timeout !== undefined) clearTimeout(timeout);
    }
  };

  const acquireLock = async (locks: Map<string, Promise<void>>, key: string) => {
    const previous = locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const current = new Promise<void>((resolve) => {
      release = resolve;
    });
    locks.set(key, current);
    await previous;
    return () => {
      release();
      if (locks.get(key) === current) {
        locks.delete(key);
      }
    };
  };

  const resolvePlatformTargets = async (userId: string, platforms: Platform[]) => {
    if (!options.resolvePlatformTarget) {
      return undefined;
    }

    const targets: PlatformTargets = {};
    for (const platform of platforms) {
      const target = await options.resolvePlatformTarget({ userId, platform });
      if (!target) {
        return undefined;
      }
      targets[platform] = target;
    }
    return normalizePersistedPlatformTargets(targets, platforms);
  };

  const respondWithManagedUploadError = (
    response: Parameters<RequestHandler>[1],
    error: unknown
  ) => {
    if (!(error instanceof ManagedUploadServiceError)) {
      return false;
    }
    response.status(error.statusCode).json({
      status: 'error',
      code: error.code,
      message: error.message
    });
    return true;
  };

  // This is a fast configuration gate for clients before they upload media. It
  // intentionally does not probe the external publisher, storage, queue, or a
  // user's platform connection; POST /posts repeats the same check at the
  // write boundary.
  router.get('/publishing/readiness', authMiddleware, (_request, response) => {
    response.setHeader('Cache-Control', 'private, no-store');
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!socialPublishingEnabled) {
      response.status(503).json(socialPublishingUnavailableResponse);
      return;
    }

    response.json({
      status: 'ok',
      acceptingPosts: true,
      platformSettingsVersion
    });
  });

  router.get('/posts', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const includeMedia = request.query.includeMedia === 'true';
    const rawLimit = request.query.limit;
    const parsedLimit = typeof rawLimit === 'string' && /^\d+$/.test(rawLimit)
      ? Number(rawLimit)
      : undefined;
    if (rawLimit !== undefined &&
      (parsedLimit === undefined || !Number.isSafeInteger(parsedLimit) || parsedLimit < 1)) {
      response.status(400).json({
        status: 'error',
        code: 'INVALID_POST_LIMIT',
        message: 'limit must be a positive integer'
      });
      return;
    }

    response.setHeader('Cache-Control', 'private, no-store');
    let posts = (await store.list({
      userId: authUser.id,
      scheduledOnly: request.query.scheduled === 'true'
    })).filter((post) => post.userId === authUser.id);
    // Bound the optional preview work before signing any private objects.
    // Legacy lists keep their existing ordering and complete result set.
    if (includeMedia || parsedLimit !== undefined) {
      posts = [...posts]
        .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt))
        .slice(0, Math.min(parsedLimit ?? 50, 50));
    }
    const ownedPostIds = new Set(posts.map((post) => post.id));
    const platformResults = platformPublishStore.listForPostIds
      ? (await platformPublishStore.listForPostIds([...ownedPostIds])).filter((result) =>
          ownedPostIds.has(result.postId)
        )
      : [];
    const resultsByPostId = new Map<
      string,
      ReturnType<typeof toPublicPlatformResult>[]
    >();

    for (const result of platformResults) {
      const existingResults = resultsByPostId.get(result.postId) ?? [];
      existingResults.push(toPublicPlatformResult(result));
      resultsByPostId.set(result.postId, existingResults);
    }

    const publicPosts = await Promise.all(posts.map(async (post) => {
      const coverImageUrl = includeMedia
        ? await createOptionalPreviewUrl(post.coverImageS3Key, authUser.id)
        : undefined;
      const videoUrl = includeMedia && !coverImageUrl
        ? await createOptionalPreviewUrl(post.videoS3Key, authUser.id)
        : undefined;
      return {
        ...toPublicPost(post),
        ...(coverImageUrl ? { coverImageUrl } : {}),
        ...(videoUrl ? { videoUrl } : {}),
        platformResults: resultsByPostId.get(post.id) ?? []
      };
    }));
    response.json({
      status: 'ok',
      posts: publicPosts
    });
  });

  router.post('/posts', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const caption = readRequiredString(request.body?.caption);
    const videoS3Key = readRequiredString(request.body?.videoS3Key);
    const clientRequestIdResult = readOptionalClientRequestId(request.body?.clientRequestId);
    const clientRequestId = clientRequestIdResult.value;
    const mediaFingerprintResult = readOptionalMediaContentFingerprint(request.body?.mediaContentFingerprint);
    const mediaContentFingerprint = mediaFingerprintResult.value;
    const platformsResult = readPlatforms(request.body?.platforms);
    const platformSettingsResult = readPlatformSettings(
      request.body?.platformSettings,
      platformsResult.value
    );
    const scheduledAtResult = readOptionalIsoDate(request.body?.scheduledAt);
    const scheduledAt = scheduledAtResult.value;
    const coverImageKeyResult = readOptionalCoverImageKey(request.body?.coverImageS3Key);
    const coverFrameTimeResult = readOptionalCoverFrameTimeMs(request.body?.coverFrameTimeMs);
    const subscriptionPlanOverride = readSubscriptionPlanOverride(request.body?.subscriptionPlan);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!socialPublishingEnabled) {
      response.status(503).json(socialPublishingUnavailableResponse);
      return;
    }

    if (
      clientRequestId &&
      caption &&
      videoS3Key &&
      platformsResult.ok &&
      !platformsResult.hadDuplicates &&
      platformSettingsResult.ok &&
      scheduledAtResult.ok &&
      coverImageKeyResult.ok &&
      coverFrameTimeResult.ok &&
      mediaFingerprintResult.ok
    ) {
      const existing = await store.findIdempotent({
        userId: authUser.id,
        clientRequestId
      });
      if (existing) {
        const replayInput: CreatePostWithinMonthlyLimitInput = {
          userId: authUser.id,
          clientRequestId,
          caption,
          videoS3Key,
          ...(mediaContentFingerprint ? { mediaContentFingerprint } : {}),
          ...(coverImageKeyResult.value
            ? { coverImageS3Key: coverImageKeyResult.value }
            : {}),
          ...(coverFrameTimeResult.value !== undefined
            ? { coverFrameTimeMs: coverFrameTimeResult.value }
            : {}),
          platforms: platformsResult.value,
          platformSettings: platformSettingsResult.value,
          scheduledAt,
          monthlyPostUnitLimit: 0,
          now: now().toISOString()
        };

        if (!isMatchingIdempotentIntent(existing, replayInput)) {
          response.status(409).json(idempotencyKeyReusedResponse);
          return;
        }

        const releaseOwner = await ownerMutationLock.acquire(authUser.id);
        try {
          await options.assertOwnerActive?.(authUser.id);
          const current = await store.findIdempotent({
            userId: authUser.id,
            clientRequestId
          });
          if (current) {
            if (!isMatchingIdempotentIntent(current, replayInput)) {
              response.status(409).json(idempotencyKeyReusedResponse);
              return;
            }
            if (current.status === 'FAILED') {
              response.status(409).json(idempotentPostFailedResponse(current.id));
              return;
            }
            const publishJob =
              current.status === 'QUEUED'
                ? await publishQueue.ensureEnqueued(current)
                : undefined;
            response.status(200).json({
              status: 'ok',
              post: toPublicPost(current),
              ...(publishJob ? { publishJob } : {}),
              idempotentReplay: true
            });
            return;
          }
        } catch (error) {
          if (respondWithManagedUploadError(response, error)) {
            return;
          }
          console.error('Publish queue recovery failed:', error);
          response.status(503).json({
            status: 'error',
            code: 'PUBLISH_QUEUE_UNAVAILABLE',
            message: 'Publish queue is temporarily unavailable. Please try again.'
          });
          return;
        } finally {
          releaseOwner();
        }
      }
    }

    if (!caption || !videoS3Key) {
      response.status(400).json({
        status: 'error',
        message: 'caption, videoS3Key, and at least one valid platform are required'
      });
      return;
    }

    if (
      !platformsResult.ok ||
      (clientRequestId !== undefined && platformsResult.hadDuplicates)
    ) {
      response.status(400).json(invalidPlatformsResponse);
      return;
    }

    if (!platformSettingsResult.ok) {
      response.status(400).json(invalidPlatformSettingsResponse);
      return;
    }

    if (!clientRequestIdResult.ok) {
      response.status(400).json(invalidClientRequestIdResponse);
      return;
    }

    if (!mediaFingerprintResult.ok) {
      response.status(400).json({ status: 'error', code: 'INVALID_MEDIA_CONTENT_FINGERPRINT',
        message: 'mediaContentFingerprint must be a lowercase SHA-256 digest when provided' });
      return;
    }

    const platforms = platformsResult.value;
    const platformSettings = platformSettingsResult.value;

    if (!scheduledAtResult.ok) {
      response.status(400).json({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });
      return;
    }

    if (!coverImageKeyResult.ok) {
      response.status(400).json({
        status: 'error',
        message: 'coverImageS3Key must be a non-empty string when provided'
      });
      return;
    }

    if (!coverFrameTimeResult.ok) {
      response.status(400).json({
        status: 'error',
        message: 'coverFrameTimeMs must be a non-negative integer when provided'
      });
      return;
    }

    const coverImageS3Key = coverImageKeyResult.value;
    const coverFrameTimeMs = coverFrameTimeResult.value;
    const requestNow = now();

    if (scheduledAt && isScheduleInPastOrPresent(scheduledAt, requestNow)) {
      response.status(400).json({
        status: 'error',
        code: 'SCHEDULE_MUST_BE_FUTURE',
        message: 'scheduledAt must be in the future'
      });
      return;
    }

    if (!isStorageKeyOwnedByUser({ videoS3Key, userId: authUser.id })) {
      response.status(403).json({
        status: 'error',
        message: 'Selected media does not belong to the authenticated user'
      });
      return;
    }

    if (
      coverImageS3Key &&
      !isStorageKeyOwnedByUser({
        videoS3Key: coverImageS3Key,
        userId: authUser.id
      })
    ) {
      response.status(403).json({
        status: 'error',
        message: 'Selected cover does not belong to the authenticated user'
      });
      return;
    }

    if (
      options.assertUploadReady ||
      (coverImageS3Key && options.assertCoverUploadReady)
    ) {
      try {
        if (options.assertUploadReady) {
          await options.assertUploadReady(authUser.id, videoS3Key);
        }
        if (coverImageS3Key) {
          const assertCoverUploadReady =
            options.assertCoverUploadReady ?? options.assertUploadReady;
          await assertCoverUploadReady?.(authUser.id, coverImageS3Key);
        }
      } catch (error) {
        if (!(error instanceof ManagedUploadServiceError)) {
          throw error;
        }

        response.status(error.statusCode).json({
          status: 'error',
          code: error.code,
          message: error.message
        });
        return;
      }
    }

    if (!subscriptionPlanOverride.ok) {
      response.status(400).json({
        status: 'error',
        message: subscriptionPlanOverride.message
      });
      return;
    }

    if (subscriptionPlanOverride.plan && !allowSubscriptionPlanOverride) {
      response.status(403).json({
        status: 'error',
        code: 'SUBSCRIPTION_PLAN_OVERRIDE_DISABLED',
        message: 'subscriptionPlan overrides are only available in local mock development'
      });
      return;
    }

    let subscriptionPlan =
      subscriptionPlanOverride.plan ?? (await subscriptionStore.getPlan(authUser));

    if (scheduledAt && !canSchedulePosts(subscriptionPlan)) {
      response.status(402).json({
        status: 'error',
        code: 'PAID_PLAN_REQUIRED',
        message: 'Cloud Scheduling requires the Starter or Pro plan'
      });
      return;
    }

    const maxScheduleAheadDays = maxScheduleAheadDaysByPlan[subscriptionPlan];
    if (scheduledAt && isScheduleBeyondLimit(scheduledAt, requestNow, maxScheduleAheadDays)) {
      response.status(400).json({
        status: 'error',
        code: 'SCHEDULE_LIMIT_EXCEEDED',
        message: `Posts can be scheduled up to ${maxScheduleAheadDays} days in advance`
      });
      return;
    }

    if (subscriptionPlan === 'BASIC' && !authUser.phoneVerified) {
      response.status(403).json({
        status: 'error',
        code: 'PHONE_VERIFICATION_REQUIRED',
        message: 'Phone verification is required to use the Basic free post quota'
      });
      return;
    }

    let platformTargets: PlatformTargets | undefined;
    if (options.resolvePlatformTarget) {
      try {
        platformTargets = await resolvePlatformTargets(authUser.id, platforms);
      } catch (error) {
        console.error('Platform target lookup failed:', error);
        response.status(503).json({
          status: 'error',
          code: 'PLATFORM_TARGET_LOOKUP_FAILED',
          message: 'Connected accounts could not be checked. Please try again.'
        });
        return;
      }
      if (!platformTargets) {
        response.status(409).json(platformTargetUnavailableResponse);
        return;
      }
    }

    let monthlyPostLimit = monthlyPostUnitLimits[subscriptionPlan];
    const idempotentInput: CreatePostWithinMonthlyLimitInput = {
      userId: authUser.id,
      ...(clientRequestId ? { clientRequestId } : {}),
      caption,
      videoS3Key,
      ...(mediaContentFingerprint ? { mediaContentFingerprint } : {}),
      ...(coverImageS3Key ? { coverImageS3Key } : {}),
      ...(coverFrameTimeMs !== undefined ? { coverFrameTimeMs } : {}),
      platforms,
      platformSettings,
      ...(platformTargets ? { platformTargets } : {}),
      scheduledAt,
      monthlyPostUnitLimit: monthlyPostLimit,
      now: requestNow.toISOString()
    };
    const releaseCreation = await acquireLock(
      creationLocks,
      clientRequestId
        ? buildIdempotentPostId({ userId: authUser.id, clientRequestId })
        : `legacy:${randomUUID()}`
    );

    try {
      const releaseOwner = await ownerMutationLock.acquire(authUser.id);
      try {
        try {
          await options.assertOwnerActive?.(authUser.id);
        } catch (error) {
          if (respondWithManagedUploadError(response, error)) {
            return;
          }
          throw error;
        }

        if (platformTargets && options.resolvePlatformTarget) {
          let currentTargets: PlatformTargets | undefined;
          try {
            currentTargets = await resolvePlatformTargets(authUser.id, platforms);
          } catch (error) {
            console.error('Platform target revalidation failed:', error);
            response.status(503).json({
              status: 'error',
              code: 'PLATFORM_TARGET_LOOKUP_FAILED',
              message: 'Connected accounts could not be checked. Please try again.'
            });
            return;
          }
          if (
            !currentTargets ||
            !arePlatformTargetsEqual(platformTargets, currentTargets, platforms)
          ) {
            response.status(409).json(platformTargetUnavailableResponse);
            return;
          }
        }

        if (scheduledAt) {
          // A matching intent accepted while this request waited keeps its original
          // entitlement. Only new schedules must recheck the plan under the owner lock.
          const acceptedPost = clientRequestId
            ? await store.findIdempotent({ userId: authUser.id, clientRequestId })
            : undefined;
          if (!acceptedPost) {
            subscriptionPlan = subscriptionPlanOverride.plan ?? (await subscriptionStore.getPlan(authUser));
            if (!canSchedulePosts(subscriptionPlan)) {
              response.status(402).json({
                status: 'error',
                code: 'PAID_PLAN_REQUIRED',
                message: 'Cloud Scheduling requires the Starter or Pro plan'
              });
              return;
            }
            const currentMaxDays = maxScheduleAheadDaysByPlan[subscriptionPlan];
            if (isScheduleBeyondLimit(scheduledAt, requestNow, currentMaxDays)) {
              response.status(400).json({
                status: 'error',
                code: 'SCHEDULE_LIMIT_EXCEEDED',
                message: `Posts can be scheduled up to ${currentMaxDays} days in advance`
              });
              return;
            }
            monthlyPostLimit = monthlyPostUnitLimits[subscriptionPlan];
            idempotentInput.monthlyPostUnitLimit = monthlyPostLimit;
          }
        }

        if (scheduledAt && isScheduleInPastOrPresent(scheduledAt, now())) {
          response.status(400).json({
            status: 'error',
            code: 'SCHEDULE_MUST_BE_FUTURE',
            message: 'scheduledAt must be in the future'
          });
          return;
        }

        const user = await userStore.ensure(authUser);
        let createResult;
        try {
          createResult = await store.createWithinMonthlyLimit({
            ...idempotentInput,
            userId: user.id,
            now: now().toISOString()
          });
        } catch (error) {
          if (!(error instanceof PostIdempotencyKeyReusedError)) {
            throw error;
          }
          response.status(409).json(idempotencyKeyReusedResponse);
          return;
        }

        if (!createResult.ok) {
          response.status(402).json({
            status: 'error',
            code: 'POST_LIMIT_REACHED',
            message: `${readPlanLabel(subscriptionPlan)} plan is limited to ${monthlyPostLimit} post units per month`
          });
          return;
        }

        const post = createResult.post;
        if (!createResult.created && post.status === 'FAILED') {
          response.status(409).json(idempotentPostFailedResponse(post.id));
          return;
        }
        let publishJob;
        try {
          publishJob = createResult.created
            ? await publishQueue.enqueue(post)
            : post.status === 'QUEUED'
              ? await publishQueue.ensureEnqueued(post)
              : undefined;
        } catch (error) {
          if (createResult.created && !clientRequestId) {
            try {
              await store.remove({ postId: post.id, userId: user.id });
            } catch (rollbackError) {
              console.error(
                'Failed to rollback legacy post after queue failure:',
                rollbackError
              );
            }
          }
          console.error('Publish queue enqueue failed:', error);
          response.status(503).json({
            status: 'error',
            code: 'PUBLISH_QUEUE_UNAVAILABLE',
            message: 'Publish queue is temporarily unavailable. Please try again.'
          });
          return;
        }

        response.status(createResult.created ? 201 : 200).json({
          status: 'ok',
          post: toPublicPost(post),
          ...(publishJob ? { publishJob } : {}),
          ...(createResult.created ? {} : { idempotentReplay: true })
        });
      } finally {
        releaseOwner();
      }
    } finally {
      releaseCreation();
    }
  });

  router.patch('/posts/:id', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    if (!socialPublishingEnabled) {
      response.status(503).json(socialPublishingUnavailableResponse);
      return;
    }

    const scheduledAtResult = readOptionalIsoDate(request.body?.scheduledAt);
    const scheduledAt = scheduledAtResult.value;

    if (!scheduledAtResult.ok || !scheduledAt) {
      response.status(400).json({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });
      return;
    }

    const requestNow = now();

    if (isScheduleInPastOrPresent(scheduledAt, requestNow)) {
      response.status(400).json({
        status: 'error',
        code: 'SCHEDULE_MUST_BE_FUTURE',
        message: 'scheduledAt must be in the future'
      });
      return;
    }

    const postId = String(request.params.id);
    const releaseOwner = await ownerMutationLock.acquire(authUser.id);
    const releaseMutation = await acquireLock(
      mutationLocks,
      `${authUser.id}\0${postId}`
    );
    try {
      try {
        await options.assertOwnerActive?.(authUser.id);
      } catch (error) {
        if (respondWithManagedUploadError(response, error)) {
          return;
        }
        throw error;
      }

      if (isScheduleInPastOrPresent(scheduledAt, now())) {
        response.status(400).json({
          status: 'error',
          code: 'SCHEDULE_MUST_BE_FUTURE',
          message: 'scheduledAt must be in the future'
        });
        return;
      }

      const existingPost = (await store.list({ userId: authUser.id })).find(
        (post) => post.id === postId && post.status === 'QUEUED'
      );
      if (!existingPost) {
        response.status(404).json({
          status: 'error',
          message: 'Scheduled post not found'
        });
        return;
      }

      const subscriptionPlan = await subscriptionStore.getPlan(authUser);
      if (!canSchedulePosts(subscriptionPlan)) {
        response.status(402).json({
          status: 'error',
          code: 'PAID_PLAN_REQUIRED',
          message: 'Cloud Scheduling requires the Starter or Pro plan'
        });
        return;
      }

      const maxScheduleAheadDays = maxScheduleAheadDaysByPlan[subscriptionPlan];
      if (isScheduleBeyondLimit(scheduledAt, requestNow, maxScheduleAheadDays)) {
        response.status(400).json({
          status: 'error',
          code: 'SCHEDULE_LIMIT_EXCEEDED',
          message: `Posts can be scheduled up to ${maxScheduleAheadDays} days in advance`
        });
        return;
      }

      if (isScheduleInPastOrPresent(scheduledAt, now())) {
        response.status(400).json({
          status: 'error',
          code: 'SCHEDULE_MUST_BE_FUTURE',
          message: 'scheduledAt must be in the future'
        });
        return;
      }

      const originalScheduledAt = existingPost.scheduledAt;
      const post = await store.reschedule({
        postId,
        userId: authUser.id,
        expectedScheduledAt: originalScheduledAt ?? null,
        scheduledAt
      });
      if (!post) {
        response.status(404).json({
          status: 'error',
          message: 'Scheduled post not found'
        });
        return;
      }

      try {
        await publishQueue.reschedule(post);
      } catch (error) {
        console.error('Publish queue reschedule failed:', error);
        try {
          if (originalScheduledAt === undefined) {
            await store.publishNow({
              postId,
              userId: authUser.id,
              expectedScheduledAt: scheduledAt
            });
          } else {
            await store.reschedule({
              postId,
              userId: authUser.id,
              expectedScheduledAt: scheduledAt,
              scheduledAt: originalScheduledAt
            });
          }
        } catch (rollbackError) {
          console.error('Publish queue reschedule rollback failed:', rollbackError);
        }
        response.status(503).json({
          status: 'error',
          code: 'PUBLISH_QUEUE_UNAVAILABLE',
          message: 'Publish queue is temporarily unavailable. Please try again.'
        });
        return;
      }

      response.json({ status: 'ok', post: toPublicPost(post) });
    } finally {
      releaseMutation();
      releaseOwner();
    }
  });

  router.post('/posts/:id/publish-now', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }
    if (!socialPublishingEnabled) {
      response.status(503).json(socialPublishingUnavailableResponse);
      return;
    }

    const postId = String(request.params.id);
    const releaseOwner = await ownerMutationLock.acquire(authUser.id);
    const releaseMutation = await acquireLock(
      mutationLocks,
      `${authUser.id}\0${postId}`
    );
    try {
      try {
        await options.assertOwnerActive?.(authUser.id);
      } catch (error) {
        if (respondWithManagedUploadError(response, error)) {
          return;
        }
        throw error;
      }

      const existingPost = (await store.list({ userId: authUser.id })).find(
        (post) =>
          post.id === postId &&
          post.status === 'QUEUED' &&
          post.scheduledAt !== undefined
      );
      if (!existingPost) {
        response.status(404).json({
          status: 'error',
          code: 'SCHEDULED_POST_NOT_FOUND',
          message: 'Scheduled post not found'
        });
        return;
      }

      const originalScheduledAt = existingPost.scheduledAt as string;
      const post = await store.publishNow({
        postId,
        userId: authUser.id,
        expectedScheduledAt: originalScheduledAt
      });
      if (!post) {
        response.status(404).json({
          status: 'error',
          code: 'SCHEDULED_POST_NOT_FOUND',
          message: 'Scheduled post not found'
        });
        return;
      }

      let publishJob;
      try {
        publishJob = await publishQueue.reschedule(post);
      } catch (error) {
        console.error('Publish-now queue transition failed:', error);
        try {
          await store.reschedule({
            postId,
            userId: authUser.id,
            expectedScheduledAt: null,
            scheduledAt: originalScheduledAt
          });
        } catch (rollbackError) {
          console.error('Publish-now rollback failed:', rollbackError);
        }
        response.status(503).json({
          status: 'error',
          code: 'PUBLISH_QUEUE_UNAVAILABLE',
          message: 'Publish queue is temporarily unavailable. Please try again.'
        });
        return;
      }

      response.json({
        status: 'ok',
        post: toPublicPost(post),
        publishJob
      });
    } finally {
      releaseMutation();
      releaseOwner();
    }
  });

  router.delete('/posts/:id', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const postId = String(request.params.id);
    const releaseOwner = await ownerMutationLock.acquire(authUser.id);
    const releaseMutation = await acquireLock(
      mutationLocks,
      `${authUser.id}\0${postId}`
    );
    try {
      try {
        await options.assertOwnerActive?.(authUser.id);
      } catch (error) {
        if (respondWithManagedUploadError(response, error)) {
          return;
        }
        throw error;
      }

      const removed = await store.remove({
        postId,
        userId: authUser.id
      });

      if (!removed) {
        response.status(404).json({
          status: 'error',
          message: 'Scheduled post not found'
        });
        return;
      }

      await publishQueue.remove(postId);

      response.json({ status: 'ok' });
    } finally {
      releaseMutation();
      releaseOwner();
    }
  });
};
