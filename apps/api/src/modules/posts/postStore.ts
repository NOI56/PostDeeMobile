import { createHash, randomUUID } from 'node:crypto';

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
};

export type CreatePostInput = {
  userId: string;
  caption: string;
  videoS3Key: string;
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
  list: (filter?: { userId?: string; scheduledOnly?: boolean }) => Promise<QueuedPost[]>;
  // Global aggregate only: used by the opt-in real-publisher activation guard.
  // It deliberately returns no post, owner, caption, or media details.
  countPublishBacklog: () => Promise<number>;
  countMonthlyPostUnits: (input: { userId: string; now: string }) => Promise<number>;
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

export const createPostStore = (): PostStore => {
  const posts: QueuedPost[] = [];
  const createPost = (
    input: CreatePostInput,
    createdAt = new Date().toISOString(),
    id: string = randomUUID()
  ) => {
    const post: QueuedPost = {
      id,
      userId: input.userId,
      caption: input.caption,
      videoS3Key: input.videoS3Key,
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

  return {
    list: async (filter) =>
      posts
        .filter((post) => (filter?.userId ? post.userId === filter.userId : true))
        .filter((post) => (filter?.scheduledOnly ? post.scheduledAt !== undefined : true))
        .sort((left, right) => {
          if (!filter?.scheduledOnly) {
            return 0;
          }

          return (left.scheduledAt ?? '').localeCompare(right.scheduledAt ?? '');
        }),
    countPublishBacklog: async () =>
      posts.filter(
        (post) => post.status === 'QUEUED' || post.status === 'PUBLISHING'
      ).length,
    countMonthlyPostUnits: async ({ userId, now }) =>
      countCurrentMonthPostUnits(
        posts.filter((post) => post.userId === userId),
        new Date(now)
      ),
    create: async (input) => createPost(input),
    findIdempotent: async (input) => findIdempotent(input),
    createWithinMonthlyLimit: async (input) => {
      if (input.clientRequestId) {
        const idempotencyKey = {
          userId: input.userId,
          clientRequestId: input.clientRequestId
        };
        const existing = findIdempotent(idempotencyKey);
        if (existing) {
          if (!isMatchingIdempotentIntent(existing, input)) {
            throw new PostIdempotencyKeyReusedError();
          }
          return { ok: true, post: existing, created: false };
        }
      }

      const usedPostUnits = countCurrentMonthPostUnits(
        posts.filter((post) => post.userId === input.userId),
        new Date(input.now)
      );

      if (usedPostUnits + input.platforms.length > input.monthlyPostUnitLimit) {
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
            : randomUUID()
        ),
        created: true
      };
    },
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
    reschedule: async ({ postId, userId, expectedScheduledAt, scheduledAt }) => {
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
    },
    publishNow: async ({ postId, userId, expectedScheduledAt }) => {
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
    },
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
