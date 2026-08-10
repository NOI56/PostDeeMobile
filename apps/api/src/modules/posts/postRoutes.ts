import type { RequestHandler, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { PlatformPublishStore } from '../platformPublishes/platformPublishStore.js';
import type { PublishQueue } from '../queue/publishQueue.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import {
  canSchedulePosts,
  monthlyPostUnitLimits,
  readPlanLabel
} from '../subscriptions/subscriptionEntitlements.js';
import type { SubscriptionPlan, SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import { ManagedUploadServiceError } from '../uploads/managedUploadService.js';
import { type PostStore, isValidPlatform } from './postStore.js';
import { countCurrentMonthPostUnits } from './postUsage.js';

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readPlatforms = (value: unknown) => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isValidPlatform);
};

const readOptionalIsoDate = (value: unknown) => {
  const rawDate = readRequiredString(value);

  if (!rawDate) {
    return undefined;
  }

  const timestamp = Date.parse(rawDate);
  return Number.isNaN(timestamp) ? undefined : new Date(timestamp).toISOString();
};

export const maxScheduleAheadDays = 30;
const maxScheduleAheadMs = maxScheduleAheadDays * 24 * 60 * 60 * 1000;

const isScheduleBeyondLimit = (scheduledAt: string, now: Date) =>
  Date.parse(scheduledAt) > now.getTime() + maxScheduleAheadMs;

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
    assertUploadReady?: (ownerId: string, videoS3Key: string) => Promise<void>;
    assertCoverUploadReady?: (ownerId: string, coverImageS3Key: string) => Promise<void>;
    now?: () => Date;
  } = {}
) => {
  const allowSubscriptionPlanOverride = options.allowSubscriptionPlanOverride ?? true;
  const socialPublishingEnabled = options.socialPublishingEnabled ?? true;
  const now = options.now ?? (() => new Date());

  // This is a fast configuration gate for clients before they upload media. It
  // intentionally does not probe the external publisher, storage, queue, or a
  // user's platform connection; POST /posts repeats the same check at the
  // write boundary.
  router.get('/publishing/readiness', authMiddleware, (_request, response) => {
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
      acceptingPosts: true
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

    const posts = await store.list({
      userId: authUser.id,
      scheduledOnly: request.query.scheduled === 'true'
    });
    const ownedPostIds = new Set(posts.map((post) => post.id));
    const platformResults = platformPublishStore.listForPostIds
      ? (await platformPublishStore.listForPostIds([...ownedPostIds])).filter((result) =>
          ownedPostIds.has(result.postId)
        )
      : [];
    const resultsByPostId = new Map<string, typeof platformResults>();

    for (const result of platformResults) {
      const existingResults = resultsByPostId.get(result.postId) ?? [];
      existingResults.push(result);
      resultsByPostId.set(result.postId, existingResults);
    }

    response.json({
      status: 'ok',
      posts: posts.map((post) => ({
        ...post,
        platformResults: resultsByPostId.get(post.id) ?? []
      }))
    });
  });

  router.post('/posts', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);
    const caption = readRequiredString(request.body?.caption);
    const videoS3Key = readRequiredString(request.body?.videoS3Key);
    const platforms = readPlatforms(request.body?.platforms);
    const scheduledAt = readOptionalIsoDate(request.body?.scheduledAt);
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

    if (!caption || !videoS3Key || platforms.length === 0) {
      response.status(400).json({
        status: 'error',
        message: 'caption, videoS3Key, and at least one valid platform are required'
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

    if (scheduledAt && isScheduleBeyondLimit(scheduledAt, now())) {
      response.status(400).json({
        status: 'error',
        code: 'SCHEDULE_LIMIT_EXCEEDED',
        message: 'Posts can be scheduled up to 30 days in advance'
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

    const subscriptionPlan =
      subscriptionPlanOverride.plan ?? (await subscriptionStore.getPlan(authUser));

    if (scheduledAt && !canSchedulePosts(subscriptionPlan)) {
      response.status(402).json({
        status: 'error',
        code: 'PAID_PLAN_REQUIRED',
        message: 'Cloud Scheduling requires the Starter or Pro plan'
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

    const monthlyPostLimit = monthlyPostUnitLimits[subscriptionPlan];
    const usedPostUnits = countCurrentMonthPostUnits(await store.list({ userId: authUser.id }));
    const requestedPostUnits = platforms.length;

    if (usedPostUnits + requestedPostUnits > monthlyPostLimit) {
      response.status(402).json({
        status: 'error',
        code: 'POST_LIMIT_REACHED',
        message: `${readPlanLabel(subscriptionPlan)} plan is limited to ${monthlyPostLimit} post units per month`
      });
      return;
    }

    const user = await userStore.ensure(authUser);
    const post = await store.create({
      userId: user.id,
      caption,
      videoS3Key,
      ...(coverImageS3Key ? { coverImageS3Key } : {}),
      ...(coverFrameTimeMs !== undefined ? { coverFrameTimeMs } : {}),
      platforms,
      scheduledAt
    });
    let publishJob;

    try {
      publishJob = await publishQueue.enqueue(post);
    } catch (error) {
      try {
        await store.remove({ postId: post.id, userId: user.id });
      } catch (rollbackError) {
        console.error('Failed to rollback post after publish queue enqueue failure:', rollbackError);
      }

      console.error('Publish queue enqueue failed:', error);
      response.status(503).json({
        status: 'error',
        code: 'PUBLISH_QUEUE_UNAVAILABLE',
        message: 'Publish queue is temporarily unavailable. Please try again.'
      });
      return;
    }

    response.status(201).json({
      status: 'ok',
      post,
      publishJob
    });
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

    const scheduledAt = readOptionalIsoDate(request.body?.scheduledAt);

    if (!scheduledAt) {
      response.status(400).json({
        status: 'error',
        message: 'scheduledAt must be a valid ISO date'
      });
      return;
    }

    if (isScheduleBeyondLimit(scheduledAt, now())) {
      response.status(400).json({
        status: 'error',
        code: 'SCHEDULE_LIMIT_EXCEEDED',
        message: 'Posts can be scheduled up to 30 days in advance'
      });
      return;
    }

    const postId = String(request.params.id);
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

    try {
      await publishQueue.reschedule({
        ...existingPost,
        scheduledAt
      });
    } catch (error) {
      console.error('Publish queue reschedule failed:', error);
      response.status(503).json({
        status: 'error',
        code: 'PUBLISH_QUEUE_UNAVAILABLE',
        message: 'Publish queue is temporarily unavailable. Please try again.'
      });
      return;
    }

    const post = await store.reschedule({
      postId,
      userId: authUser.id,
      scheduledAt
    });

    if (!post) {
      await publishQueue.remove(postId);
      response.status(404).json({
        status: 'error',
        message: 'Scheduled post not found'
      });
      return;
    }

    response.json({ status: 'ok', post });
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

    const removed = await store.remove({
      postId: String(request.params.id),
      userId: authUser.id
    });

    if (!removed) {
      response.status(404).json({
        status: 'error',
        message: 'Scheduled post not found'
      });
      return;
    }

    await publishQueue.remove(String(request.params.id));

    response.json({ status: 'ok' });
  });
};
