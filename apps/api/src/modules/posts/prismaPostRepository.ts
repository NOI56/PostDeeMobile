import type {
  CreatePostInput,
  CreatePostWithinMonthlyLimitInput,
  CreatePostWithinMonthlyLimitResult,
  Platform,
  PostStatus,
  PostStore,
  QueuedPost,
  ClaimPostForPublishInput,
  UpdatePostStatusInput
} from './postStore.js';
import { countCurrentMonthPostUnits } from './postUsage.js';
import { runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';

type PrismaPostStatus =
  | 'DRAFT'
  | 'QUEUED'
  | 'PUBLISHING'
  | 'PUBLISHED'
  | 'PARTIAL_PUBLISHED'
  | 'FAILED';

type PrismaPost = {
  id: string;
  userId: string;
  caption: string;
  youtubeTitle?: string | null;
  videoS3Key: string;
  coverImageS3Key?: string | null;
  coverFrameTimeMs?: number | null;
  selectedPlatforms: Platform[];
  scheduledAt: Date | null;
  status: PrismaPostStatus;
  publishedAt: Date | null;
  createdAt: Date;
};

type PostDelegate = {
  findMany: (args: {
    where: {
      userId?: string;
      status?: PrismaPostStatus;
      scheduledAt?: { not: null };
      updatedAt?: { lt: Date };
      OR?: Array<{ scheduledAt: null } | { scheduledAt: { lte: Date } }>;
    };
    orderBy: { createdAt: 'desc' } | { scheduledAt: 'asc' } | { updatedAt: 'asc' };
  }) => Promise<PrismaPost[]>;
  create: (args: {
    data: {
      userId: string;
      caption: string;
      youtubeTitle?: string;
      videoS3Key: string;
      coverImageS3Key?: string;
      coverFrameTimeMs?: number;
      selectedPlatforms: Platform[];
      scheduledAt?: Date;
      status: 'QUEUED';
    };
  }) => Promise<PrismaPost>;
  update: (args: {
    where: { id: string };
    data: { status: PrismaPostStatus; publishedAt?: Date };
  }) => Promise<PrismaPost>;
  updateMany: (args: {
    where: {
      id: string;
      userId?: string;
      status: PrismaPostStatus;
      updatedAt?: { lt: Date };
      OR?: Array<{ scheduledAt: null } | { scheduledAt: Date }>;
    };
    data: { scheduledAt?: Date; status?: PrismaPostStatus; updatedAt?: Date };
  }) => Promise<{ count: number }>;
  deleteMany: (args: {
    where: { id: string; userId: string; status: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  findFirst: (args: { where: { id: string } }) => Promise<PrismaPost | null>;
};

type PrismaPostTransaction = PrismaOwnerLifecycleTransaction & { post: PostDelegate };
export type PrismaPostClient = PrismaPostTransaction & {
  $transaction: <Result>(
    operation: (client: PrismaPostTransaction) => Promise<Result>,
    options: { isolationLevel: 'Serializable'; maxWait: number; timeout: number }
  ) => Promise<Result>;
};

const toPostStatus = (status: PrismaPostStatus): PostStatus =>
  status === 'DRAFT' ? 'QUEUED' : status;

const mapPost = (post: PrismaPost): QueuedPost => ({
  id: post.id,
  userId: post.userId,
  caption: post.caption,
  ...(post.youtubeTitle ? { youtubeTitle: post.youtubeTitle } : {}),
  videoS3Key: post.videoS3Key,
  ...(post.coverImageS3Key
    ? { coverImageS3Key: post.coverImageS3Key }
    : {}),
  ...(post.coverFrameTimeMs !== null && post.coverFrameTimeMs !== undefined
    ? { coverFrameTimeMs: post.coverFrameTimeMs }
    : {}),
  platforms: [...post.selectedPlatforms],
  scheduledAt: post.scheduledAt?.toISOString(),
  status: toPostStatus(post.status),
  publishedAt: post.publishedAt?.toISOString(),
  createdAt: post.createdAt.toISOString()
});

const createPost = async (postDelegate: PostDelegate, input: CreatePostInput) => {
  const post = await postDelegate.create({
    data: {
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
      selectedPlatforms: [...input.platforms],
      scheduledAt: input.scheduledAt ? new Date(input.scheduledAt) : undefined,
      status: 'QUEUED' as const
    }
  });

  return mapPost(post);
};

const createWithinMonthlyLimit = async (
  prisma: PrismaPostClient,
  input: CreatePostWithinMonthlyLimitInput
): Promise<CreatePostWithinMonthlyLimitResult> => {
  return runActiveOwnerTransaction(prisma, input.userId, async (transaction) => {
    const posts = await transaction.post.findMany({
      where: { userId: input.userId },
      orderBy: { createdAt: 'desc' }
    });
    const usedPostUnits = countCurrentMonthPostUnits(
      posts.map((post) => ({
        createdAt: post.createdAt.toISOString(),
        platforms: post.selectedPlatforms
      })),
      new Date(input.now)
    );

    if (usedPostUnits + input.platforms.length > input.monthlyPostUnitLimit) {
      return { ok: false as const };
    }

    return { ok: true as const, post: await createPost(transaction.post, input) };
  });
};

export const createPrismaPostRepository = ({
  prisma
}: {
  prisma: PrismaPostClient;
}): PostStore => ({
  list: async (filter) => {
    const scheduledOnly = filter?.scheduledOnly ?? false;
    const posts = await prisma.post.findMany({
      where: {
        userId: filter?.userId,
        ...(scheduledOnly
          ? {
              scheduledAt: {
                not: null
              }
            }
          : {})
      },
      orderBy: scheduledOnly ? { scheduledAt: 'asc' } : { createdAt: 'desc' }
    });

    return posts.map(mapPost);
  },
  create: (input: CreatePostInput) => runActiveOwnerTransaction(prisma, input.userId,
    (transaction) => createPost(transaction.post, input)),
  createWithinMonthlyLimit: async (input) => createWithinMonthlyLimit(prisma, input),
  listDue: async ({ now }: { now: string }) => {
    const posts = await prisma.post.findMany({
      where: {
        status: 'QUEUED',
        OR: [{ scheduledAt: null }, { scheduledAt: { lte: new Date(now) } }]
      },
      orderBy: { scheduledAt: 'asc' }
    });

    return posts.map(mapPost);
  },
  claimForPublish: async ({ postId, expectedRunAt }: ClaimPostForPublishInput) => {
    const result = await prisma.post.updateMany({
      where: {
        id: postId,
        status: 'QUEUED',
        OR: [{ scheduledAt: null }, { scheduledAt: new Date(expectedRunAt) }]
      },
      // updatedAt marks when publishing started; recoverStalePublishing reads it.
      data: { status: 'PUBLISHING', updatedAt: new Date() }
    });

    return result.count > 0;
  },
  recoverStalePublishing: async ({ startedBefore }) => {
    const cutoff = new Date(startedBefore);
    const stalePosts = await prisma.post.findMany({
      where: { status: 'PUBLISHING', updatedAt: { lt: cutoff } },
      orderBy: { updatedAt: 'asc' }
    });
    const recovered: QueuedPost[] = [];

    for (const post of stalePosts) {
      // Conditional so a worker that finishes meanwhile keeps its real outcome.
      const result = await prisma.post.updateMany({
        where: { id: post.id, status: 'PUBLISHING', updatedAt: { lt: cutoff } },
        data: { status: 'FAILED' }
      });

      if (result.count > 0) {
        recovered.push(mapPost({ ...post, status: 'FAILED' }));
      }
    }

    return recovered;
  },
  updateStatus: async ({ postId, status, publishedAt }: UpdatePostStatusInput) => {
    await prisma.post.update({
      where: { id: postId },
      data: {
        status,
        ...(publishedAt ? { publishedAt: new Date(publishedAt) } : {})
      }
    });
  },
  reschedule: ({ postId, userId, scheduledAt }) => runActiveOwnerTransaction(prisma, userId, async (transaction) => {
    const result = await transaction.post.updateMany({
      where: { id: postId, userId, status: 'QUEUED' },
      data: { scheduledAt: new Date(scheduledAt) }
    });

    if (result.count === 0) {
      return undefined;
    }

    const post = await transaction.post.findFirst({ where: { id: postId } });
    return post ? mapPost(post) : undefined;
  }),
  remove: async ({ postId, userId }) => {
    const result = await prisma.post.deleteMany({
      where: { id: postId, userId, status: 'QUEUED' }
    });

    return result.count > 0;
  }
});
