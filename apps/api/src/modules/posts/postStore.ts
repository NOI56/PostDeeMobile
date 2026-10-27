import { randomUUID } from 'node:crypto';

import { countCurrentMonthPostUnits } from './postUsage.js';
import type { RunWithActiveOwner } from '../account/ownerOperationQueue.js';

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
  youtubeTitle?: string;
  videoS3Key: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  scheduledAt?: string;
  status: PostStatus;
  publishedAt?: string;
  createdAt: string;
};

export type CreatePostInput = {
  userId: string;
  caption: string;
  youtubeTitle?: string;
  videoS3Key: string;
  coverImageS3Key?: string;
  coverFrameTimeMs?: number;
  platforms: Platform[];
  scheduledAt?: string;
};

export type CreatePostWithinMonthlyLimitInput = CreatePostInput & {
  monthlyPostUnitLimit: number;
  now: string;
};

export type CreatePostWithinMonthlyLimitResult =
  | { ok: true; post: QueuedPost }
  | { ok: false };

export type UpdatePostStatusInput = {
  postId: string;
  status: PostStatus;
  publishedAt?: string;
};

export type ReschedulePostInput = {
  postId: string;
  userId: string;
  scheduledAt: string;
};

export type RemovePostInput = {
  postId: string;
  userId: string;
};

export type ClaimPostForPublishInput = {
  postId: string;
  expectedRunAt: string;
};

export type RecoverStalePublishingInput = {
  startedBefore: string;
};

export type PostStore = {
  list: (filter?: { userId?: string; scheduledOnly?: boolean }) => Promise<QueuedPost[]>;
  create: (input: CreatePostInput) => Promise<QueuedPost>;
  // Checks the user's current-month platform units and creates the post as one
  // atomic store operation so concurrent requests cannot overspend the quota.
  createWithinMonthlyLimit: (
    input: CreatePostWithinMonthlyLimitInput
  ) => Promise<CreatePostWithinMonthlyLimitResult>;
  // Posts whose time has come: QUEUED with no schedule (post now) or scheduledAt
  // at/before `now`. Used by the publish scheduler.
  listDue: (input: { now: string }) => Promise<QueuedPost[]>;
  // Atomically moves a still-queued post into PUBLISHING before calling an
  // external publisher. Returns false for missing, already-running, or finished posts.
  claimForPublish: (input: ClaimPostForPublishInput) => Promise<boolean>;
  // Fails posts still PUBLISHING from a claim made before `startedBefore` (their
  // worker died, e.g. in a restart) and returns them. Optional: only stores the
  // in-process scheduler sweeps implement it.
  recoverStalePublishing?: (input: RecoverStalePublishingInput) => Promise<QueuedPost[]>;
  updateStatus: (input: UpdatePostStatusInput) => Promise<void>;
  // Move a still-queued post (owned by userId) to a new time. Returns the
  // updated post, or undefined if it is missing, not owned, or already publishing.
  reschedule: (input: ReschedulePostInput) => Promise<QueuedPost | undefined>;
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
  now = () => new Date()
}: { runWithActiveOwner?: RunWithActiveOwner; now?: () => Date } = {}): PostStore => {
  const posts: QueuedPost[] = [];
  const publishingStartedAt = new Map<string, number>();
  const createPost = (input: CreatePostInput, createdAt = new Date().toISOString()) => {
    const post: QueuedPost = {
      id: randomUUID(),
      userId: input.userId,
      caption: input.caption,
      ...(input.youtubeTitle ? { youtubeTitle: input.youtubeTitle } : {}),
      videoS3Key: input.videoS3Key,
      ...(input.coverImageS3Key
        ? { coverImageS3Key: input.coverImageS3Key }
        : {}),
      ...(input.coverFrameTimeMs !== undefined
        ? { coverFrameTimeMs: input.coverFrameTimeMs }
        : {}),
      platforms: [...input.platforms],
      scheduledAt: input.scheduledAt,
      status: 'QUEUED' as const,
      createdAt
    };

    posts.push(post);
    return post;
  };

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
    create: (input) => runWithActiveOwner(input.userId, async () => createPost(input)),
    createWithinMonthlyLimit: (input) => runWithActiveOwner(input.userId, async () => {
      const usedPostUnits = countCurrentMonthPostUnits(
        posts.filter((post) => post.userId === input.userId),
        new Date(input.now)
      );

      if (usedPostUnits + input.platforms.length > input.monthlyPostUnitLimit) {
        return { ok: false as const };
      }

      return {
        ok: true as const,
        post: createPost(input, input.now)
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
      publishingStartedAt.set(post.id, now().getTime());
      return true;
    },
    recoverStalePublishing: async ({ startedBefore }) => {
      const cutoff = Date.parse(startedBefore);
      const recovered: QueuedPost[] = [];

      for (const post of posts) {
        const startedAt = publishingStartedAt.get(post.id);

        if (post.status === 'PUBLISHING' && startedAt !== undefined && startedAt < cutoff) {
          post.status = 'FAILED';
          publishingStartedAt.delete(post.id);
          recovered.push(post);
        }
      }

      return recovered;
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
    reschedule: ({ postId, userId, scheduledAt }) => runWithActiveOwner(userId, async () => {
      const post = posts.find(
        (candidate) =>
          candidate.id === postId &&
          candidate.userId === userId &&
          candidate.status === 'QUEUED'
      );

      if (!post) {
        return undefined;
      }

      post.scheduledAt = scheduledAt;
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
