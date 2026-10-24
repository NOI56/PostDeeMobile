import { createHash, randomUUID } from 'node:crypto';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';

import { countCurrentMonthPostUnits } from './postUsage.js';
import {
  arePlatformSettingsEqual,
  type PlatformSettings
} from './platformSettings.js';
import {
  arePlatformTargetsEqual,
  normalizePersistedPlatformTargets,
  type PlatformTargets
} from './platformTargets.js';

export type Platform = 'TIKTOK' | 'YOUTUBE_SHORTS' | 'INSTAGRAM_REELS' | 'FACEBOOK_REELS';

const validPlatforms: Platform[] = [
  'TIKTOK',
  'YOUTUBE_SHORTS',
  'INSTAGRAM_REELS',
  'FACEBOOK_REELS'
];

export type PostStatus =
  | 'QUEUED'
  | 'PUBLISHING'
  | 'PUBLISHED'
  | 'PARTIAL_PUBLISHED'
  | 'FAILED';

export type QueuedPost = {
  id: string;
  userId: string;
  caption: string;
  videoS3Key: string;
  mediaContentFingerprint?: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  platformSettings?: PlatformSettings;
  // Internal immutable provider target snapshot. Public response mappers must redact it.
  platformTargets?: PlatformTargets;
  scheduledAt?: string;
  status: PostStatus;
  publishedAt?: string;
  createdAt: string;
  // Internal allocation, fixed when accepted; never reallocated after a plan change.
  addonPostUnits?: number;
};

export type CreatePostInput = {
  userId: string;
  caption: string;
  videoS3Key: string;
  mediaContentFingerprint?: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  platformSettings?: PlatformSettings;
  platformTargets?: PlatformTargets;
  scheduledAt?: string;
};

export type CreatePostWithinMonthlyLimitInput = CreatePostInput & {
  clientRequestId?: string;
  monthlyPostUnitLimit: number;
  includeMonthlyAddons?: boolean;
  now: string;
};

export type CreatePostWithinMonthlyLimitResult =
  | { ok: true; post: QueuedPost; created: boolean }
  | { ok: false };

export type FindIdempotentPostInput = {
  userId: string;
  clientRequestId: string;
};

export const buildIdempotentPostId = ({
  userId,
  clientRequestId
}: FindIdempotentPostInput) =>
  `post_idem_${createHash('sha256')
    .update(userId)
    .update('\0')
    .update(clientRequestId)
    .digest('hex')}`;

export class PostIdempotencyKeyReusedError extends Error {
  constructor() {
    super('clientRequestId was already used for a different publishing intent');
    this.name = 'PostIdempotencyKeyReusedError';
  }
}

export const isMatchingIdempotentIntent = (
  post: QueuedPost,
  input: CreatePostInput
) =>
  post.userId === input.userId &&
  post.caption === input.caption &&
  post.scheduledAt === input.scheduledAt &&
  post.coverFrameTimeMs === input.coverFrameTimeMs &&
  Boolean(post.coverImageS3Key) === Boolean(input.coverImageS3Key) &&
  (post.mediaContentFingerprint && input.mediaContentFingerprint
    ? post.mediaContentFingerprint === input.mediaContentFingerprint
    : post.videoS3Key === input.videoS3Key && post.coverImageS3Key === input.coverImageS3Key) &&
  post.platforms.length === input.platforms.length &&
  post.platforms.every((platform) => input.platforms.includes(platform)) &&
  arePlatformSettingsEqual(post.platformSettings, input.platformSettings, input.platforms) &&
  (input.platformTargets === undefined ||
    arePlatformTargetsEqual(post.platformTargets, input.platformTargets, input.platforms));

export type UpdatePostStatusInput = {
  postId: string;
  status: PostStatus;
  publishedAt?: string;
};

export type FinalizeInterruptedPublishInput = UpdatePostStatusInput & {
  status: 'PUBLISHED' | 'PARTIAL_PUBLISHED' | 'FAILED';
};

export type ReschedulePostInput = {
  postId: string;
  userId: string;
  expectedScheduledAt?: string | null;
  scheduledAt: string;
};

export type PublishPostNowInput = {
  postId: string;
  userId: string;
  expectedScheduledAt?: string;
};

export type RemovePostInput = {
  postId: string;
  userId: string;
};

export type ClaimPostForPublishInput = {
  postId: string;
  expectedRunAt: string;
};

export type PostStore = {
  // Internal startup recovery reads ids and platforms, never private content.
  listPublishing: () => Promise<Array<Pick<QueuedPost, 'id' | 'platforms'>>>;
  finalizeInterruptedPublish: (input: FinalizeInterruptedPublishInput) => Promise<boolean>;
  // With limit, returns at most that many of the newest posts (createdAt desc).
  list: (filter?: { userId?: string; scheduledOnly?: boolean; limit?: number }) => Promise<QueuedPost[]>;
  // Direct owner-scoped reads must not scan or return another owner's history.
  findOwned: (input: { postId: string; userId: string }) => Promise<QueuedPost | undefined>;
  // Global aggregate only: used by the opt-in real-publisher activation guard.
  // It deliberately returns no post, owner, caption, or media details.
  countPublishBacklog: () => Promise<number>;
  countMonthlyPostUnits: (input: { userId: string; now: string }) => Promise<number>;
  countAddonPostUnits: (input: { userId: string }) => Promise<number>;
  create: (input: CreatePostInput) => Promise<QueuedPost>;
  findIdempotent: (input: FindIdempotentPostInput) => Promise<QueuedPost | undefined>;
  // Checks current-month platform units and inserts as one store operation so
  // concurrent requests cannot overspend the user's quota.
  createWithinMonthlyLimit: (
    input: CreatePostWithinMonthlyLimitInput
  ) => Promise<CreatePostWithinMonthlyLimitResult>;
  // Posts whose time has come: QUEUED with no schedule (post now) or scheduledAt
  // at/before `now`. Used by the publish scheduler.
  listDue: (input: { now: string }) => Promise<QueuedPost[]>;
  // Atomically moves a still-queued post into PUBLISHING before calling an
  // external publisher. Returns false for missing, already-running, or finished posts.
  claimForPublish: (input: ClaimPostForPublishInput) => Promise<boolean>;
  updateStatus: (input: UpdatePostStatusInput) => Promise<void>;
  // Move a still-queued post (owned by userId) to a new time. Returns the
  // updated post, or undefined if it is missing, not owned, or already publishing.
  reschedule: (input: ReschedulePostInput) => Promise<QueuedPost | undefined>;
  publishNow: (input: PublishPostNowInput) => Promise<QueuedPost | undefined>;
  // Cancel a still-queued post (owned by userId). Returns true if removed.
  remove: (input: RemovePostInput) => Promise<boolean>;
  // Hard-deletes every post owned by userId. Used by account deletion. Optional
  // because the Prisma store relies on the User cascade instead.
  deleteAllForUser?: (userId: string) => Promise<void>;
};

export const isValidPlatform = (value: unknown): value is Platform =>
  typeof value === 'string' && validPlatforms.includes(value as Platform);

export const createPostStore = ({
  runWithActiveOwner = async (_ownerId, operation) => operation(),
  monthlyAddonStore
}: { runWithActiveOwner?: RunWithActiveOwner;
  monthlyAddonStore?: Pick<MonthlyAddonStore, 'readCredits'> } = {}): PostStore => {
  const posts: QueuedPost[] = [];
  const createPost = (
    input: CreatePostInput,
    createdAt = new Date().toISOString(),
    id: string = randomUUID(),
    addonPostUnits = 0
  ) => {
    const post: QueuedPost = {
      id,
      ...(addonPostUnits > 0 ? { addonPostUnits } : {}),
      userId: input.userId,
      caption: input.caption,
      videoS3Key: input.videoS3Key,
      ...(input.mediaContentFingerprint ? { mediaContentFingerprint: input.mediaContentFingerprint } : {}),
      ...(input.coverImageS3Key
        ? { coverImageS3Key: input.coverImageS3Key }
        : {}),
      ...(input.coverFrameTimeMs !== undefined
        ? { coverFrameTimeMs: input.coverFrameTimeMs }
        : {}),
      platforms: [...input.platforms],
      ...(input.platformSettings ? { platformSettings: input.platformSettings } : {}),
      ...(input.platformTargets
        ? {
            platformTargets: normalizePersistedPlatformTargets(
              input.platformTargets,
              input.platforms
            )
          }
        : {}),
      scheduledAt: input.scheduledAt,
      status: 'QUEUED' as const,
      createdAt
    };

    posts.push(post);
    return post;
  };

  const findIdempotent = (input: FindIdempotentPostInput) =>
    posts.find((post) => post.id === buildIdempotentPostId(input));
  const readIdempotentReplay = (input: CreatePostWithinMonthlyLimitInput) => {
    if (!input.clientRequestId) return undefined;
    const existing = findIdempotent({ userId: input.userId, clientRequestId: input.clientRequestId });
    if (!existing) return undefined;
    if (!isMatchingIdempotentIntent(existing, input)) throw new PostIdempotencyKeyReusedError();
    return { ok: true as const, post: existing, created: false };
  };

  return {
    listPublishing: async () => posts
      .filter((post) => post.status === 'PUBLISHING')
      .map((post) => ({ id: post.id, platforms: [...post.platforms] })),
    finalizeInterruptedPublish: async ({ postId, status, publishedAt }) => {
      const post = posts.find((candidate) => candidate.id === postId && candidate.status === 'PUBLISHING');
      if (!post) return false;
      post.status = status;
      if (publishedAt) post.publishedAt = publishedAt;
      return true;
    },
    list: async (filter) => {
      const matching = posts
        .filter((post) => (filter?.userId ? post.userId === filter.userId : true))
        .filter((post) => (filter?.scheduledOnly ? post.scheduledAt !== undefined : true));

      if (filter?.limit !== undefined) {
        return matching
          .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt))
          .slice(0, filter.limit);
      }

      return matching.sort((left, right) => {
        if (!filter?.scheduledOnly) {
          return 0;
        }

        return (left.scheduledAt ?? '').localeCompare(right.scheduledAt ?? '');
      });
    },
    findOwned: async ({ postId, userId }) => posts.find((post) => post.id === postId && post.userId === userId),
    countPublishBacklog: async () =>
      posts.filter(
        (post) => post.status === 'QUEUED' || post.status === 'PUBLISHING'
      ).length,
    countMonthlyPostUnits: async ({ userId, now }) =>
      countCurrentMonthPostUnits(
        posts.filter((post) => post.userId === userId),
        new Date(now)
      ),
    countAddonPostUnits: async ({ userId }) => posts.filter(post => post.userId === userId)
      .reduce((total, post) => total + (post.addonPostUnits ?? 0), 0),
    create: (input) => runWithActiveOwner(input.userId, async () => createPost(input)),
    findIdempotent: async (input) => findIdempotent(input),
    createWithinMonthlyLimit: (input) => runWithActiveOwner(input.userId, async () => {
      const replay = readIdempotentReplay(input);
      if (replay) return replay;

      let addonPostUnits = 0;
      if (input.includeMonthlyAddons) {
        addonPostUnits = (await monthlyAddonStore?.readCredits({ userId: input.userId, now: input.now }))?.postUnits ?? 0;
        const concurrentReplay = readIdempotentReplay(input);
        if (concurrentReplay) return concurrentReplay;
      }
      // There is no await between counting and inserting: concurrent memory
      // reservations share the same combined allowance without overspending it.
      const usedPostUnits = countCurrentMonthPostUnits(
        posts.filter((post) => post.userId === input.userId),
        new Date(input.now)
      );

      const addonUsed = posts.filter(post => post.userId === input.userId)
        .reduce((total, post) => total + (post.addonPostUnits ?? 0), 0);
      const neededAddonUnits = Math.max(0, input.platforms.length - Math.max(0, input.monthlyPostUnitLimit - usedPostUnits));
      if (neededAddonUnits > Math.max(0, addonPostUnits - addonUsed)) {
        return { ok: false };
      }

      return {
        ok: true,
        post: createPost(
          input,
          input.now,
          input.clientRequestId
            ? buildIdempotentPostId({
                userId: input.userId,
                clientRequestId: input.clientRequestId
              })
            : randomUUID(),
          neededAddonUnits
        ),
        created: true
      };
    }),
    listDue: async ({ now }) =>
      posts.filter(
        (post) =>
          post.status === 'QUEUED' &&
          (post.scheduledAt === undefined || post.scheduledAt <= now)
      ),
    claimForPublish: async ({ postId, expectedRunAt }) => {
      const post = posts.find((candidate) => candidate.id === postId);

      if (!post || post.status !== 'QUEUED') {
        return false;
      }

      if (post.scheduledAt && post.scheduledAt !== expectedRunAt) {
        return false;
      }

      post.status = 'PUBLISHING';
      return true;
    },
    updateStatus: async ({ postId, status, publishedAt }) => {
      const post = posts.find((candidate) => candidate.id === postId);

      if (post) {
        post.status = status;

        if (publishedAt) {
          post.publishedAt = publishedAt;
        }
      }
    },
    reschedule: ({ postId, userId, expectedScheduledAt, scheduledAt }) => runWithActiveOwner(userId, async () => {
      const post = posts.find(
        (candidate) =>
          candidate.id === postId &&
          candidate.userId === userId &&
          candidate.status === 'QUEUED' &&
          (expectedScheduledAt === undefined ||
            (expectedScheduledAt === null
              ? candidate.scheduledAt === undefined
              : candidate.scheduledAt === expectedScheduledAt))
      );

      if (!post) {
        return undefined;
      }

      post.scheduledAt = scheduledAt;
      return post;
    }),
    publishNow: ({ postId, userId, expectedScheduledAt }) => runWithActiveOwner(userId, async () => {
      const post = posts.find(
        (candidate) =>
          candidate.id === postId &&
          candidate.userId === userId &&
          candidate.status === 'QUEUED' &&
          candidate.scheduledAt !== undefined &&
          (expectedScheduledAt === undefined ||
            candidate.scheduledAt === expectedScheduledAt)
      );

      if (!post) {
        return undefined;
      }

      delete post.scheduledAt;
      return post;
    }),
    remove: async ({ postId, userId }) => {
      const index = posts.findIndex(
        (candidate) =>
          candidate.id === postId &&
          candidate.userId === userId &&
          candidate.status === 'QUEUED'
      );

      if (index === -1) {
        return false;
      }

      posts.splice(index, 1);
      return true;
    },
    deleteAllForUser: async (userId) => {
      for (let index = posts.length - 1; index >= 0; index -= 1) {
        if (posts[index].userId === userId) {
          posts.splice(index, 1);
        }
      }
    }
  };
};
