import { randomUUID } from 'node:crypto';

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
  platforms: Platform[];
  scheduledAt?: string;
  status: PostStatus;
  publishedAt?: string;
  createdAt: string;
};

export type CreatePostInput = {
  userId: string;
  caption: string;
  videoS3Key: string;
  platforms: Platform[];
  scheduledAt?: string;
};

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

export type PostStore = {
  list: (filter?: { userId?: string; scheduledOnly?: boolean }) => Promise<QueuedPost[]>;
  create: (input: CreatePostInput) => Promise<QueuedPost>;
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
    create: async (input) => {
      const post: QueuedPost = {
        id: randomUUID(),
        userId: input.userId,
        caption: input.caption,
        videoS3Key: input.videoS3Key,
        platforms: input.platforms,
        scheduledAt: input.scheduledAt,
        status: 'QUEUED',
        createdAt: new Date().toISOString()
      };

      posts.push(post);
      return post;
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
    reschedule: async ({ postId, userId, scheduledAt }) => {
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
