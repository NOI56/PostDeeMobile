import type {
  CreatePostInput,
  CreatePostWithinMonthlyLimitInput,
  CreatePostWithinMonthlyLimitResult,
  FindIdempotentPostInput,
  Platform,
  PostStatus,
  PostStore,
  QueuedPost,
  ClaimPostForPublishInput,
  UpdatePostStatusInput
} from './postStore.js';
import { countCurrentMonthPostUnits, readUtcMonthBounds } from './postUsage.js';
import {
  PostIdempotencyKeyReusedError,
  buildIdempotentPostId,
  isMatchingIdempotentIntent
} from './postStore.js';
import { normalizePersistedPlatformSettings } from './platformSettings.js';
import { normalizePersistedPlatformTargets } from './platformTargets.js';

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
  videoS3Key: string;
  coverImageS3Key?: string | null;
  coverFrameTimeMs?: number | null;
  selectedPlatforms: Platform[];
  platformSettings?: unknown | null;
  platformTargets?: unknown | null;
  scheduledAt: Date | null;
  status: PrismaPostStatus;
  publishedAt: Date | null;
  createdAt: Date;
};

type PostDelegate = {
  count: (args: {
    where: { status: { in: PrismaPostStatus[] } };
  }) => Promise<number>;
  findMany: (args: {
    where: {
      userId?: string;
      status?: PrismaPostStatus;
      scheduledAt?: { not: null };
      createdAt?: { gte: Date; lt: Date };
      OR?: Array<{ scheduledAt: null } | { scheduledAt: { lte: Date } }>;
    };
    orderBy?: { createdAt: 'desc' } | { scheduledAt: 'asc' };
    select?: { createdAt: true; selectedPlatforms: true };
  }) => Promise<PrismaPost[]>;
  create: (args: {
    data: {
      id?: string;
      userId: string;
      caption: string;
      videoS3Key: string;
      coverImageS3Key?: string;
      coverFrameTimeMs?: number;
      selectedPlatforms: Platform[];
      platformSettings?: unknown;
      platformTargets?: unknown;
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
      OR?: Array<{ scheduledAt: null } | { scheduledAt: Date }>;
      scheduledAt?: Date | null | { not: null };
    };
    data: { scheduledAt?: Date | null; status?: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  deleteMany: (args: {
    where: { id: string; userId: string; status: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  findFirst: (args: { where: { id: string; userId?: string } }) => Promise<PrismaPost | null>;
};

export type PrismaPostClient = {
  post: PostDelegate;
  $transaction?: <Result>(
    operation: (client: { post: PostDelegate }) => Promise<Result>,
    options: { isolationLevel: 'Serializable' }
  ) => Promise<Result>;
};

const toPostStatus = (status: PrismaPostStatus): PostStatus =>
  status === 'DRAFT' ? 'QUEUED' : status;

const mapPost = (post: PrismaPost): QueuedPost => {
  const platformTargets = normalizePersistedPlatformTargets(
    post.platformTargets,
    post.selectedPlatforms
  );

  return {
    id: post.id,
    userId: post.userId,
    caption: post.caption,
    videoS3Key: post.videoS3Key,
    ...(post.coverImageS3Key
      ? { coverImageS3Key: post.coverImageS3Key }
      : {}),
    ...(post.coverFrameTimeMs !== null && post.coverFrameTimeMs !== undefined
      ? { coverFrameTimeMs: post.coverFrameTimeMs }
      : {}),
    platforms: [...post.selectedPlatforms],
    ...(post.platformSettings != null
      ? {
          platformSettings: normalizePersistedPlatformSettings(
            post.platformSettings,
            post.selectedPlatforms
          )
        }
      : {}),
    ...(platformTargets ? { platformTargets } : {}),
    scheduledAt: post.scheduledAt?.toISOString(),
    status: toPostStatus(post.status),
    publishedAt: post.publishedAt?.toISOString(),
    createdAt: post.createdAt.toISOString()
  };
};

const createPost = async (
  postDelegate: PostDelegate,
  input: CreatePostInput,
  id?: string
) => {
  const post = await postDelegate.create({
    data: {
      ...(id ? { id } : {}),
      userId: input.userId,
      caption: input.caption,
      videoS3Key: input.videoS3Key,
      ...(input.coverImageS3Key
        ? { coverImageS3Key: input.coverImageS3Key }
        : {}),
      ...(input.coverFrameTimeMs !== undefined
        ? { coverFrameTimeMs: input.coverFrameTimeMs }
        : {}),
      selectedPlatforms: [...input.platforms],
      ...(input.platformSettings
        ? {
            platformSettings: normalizePersistedPlatformSettings(
              input.platformSettings,
              input.platforms
            )
          }
        : {}),
      ...(input.platformTargets
        ? {
            platformTargets: normalizePersistedPlatformTargets(
              input.platformTargets,
              input.platforms
            )
          }
        : {}),
      scheduledAt: input.scheduledAt ? new Date(input.scheduledAt) : undefined,
      status: 'QUEUED' as const
    }
  });

  return mapPost(post);
};

const isRetryableTransactionConflict = (
  error: unknown,
  hasIdempotencyKey: boolean
) =>
  typeof error === 'object' &&
  error !== null &&
  'code' in error &&
  (error.code === 'P2034' || (hasIdempotencyKey && error.code === 'P2002'));

const countMonthlyUnits = async (
  postDelegate: PostDelegate,
  { userId, now }: { userId: string; now: string }
) => {
  const { start, end } = readUtcMonthBounds(new Date(now));
  const posts = await postDelegate.findMany({
    where: { userId, createdAt: { gte: start, lt: end } },
    select: { createdAt: true, selectedPlatforms: true }
  });
  return countCurrentMonthPostUnits(
    posts.map((post) => ({
      createdAt: post.createdAt.toISOString(),
      platforms: post.selectedPlatforms
    })),
    new Date(now)
  );
};

const createWithinMonthlyLimit = async (
  prisma: PrismaPostClient,
  input: CreatePostWithinMonthlyLimitInput
): Promise<CreatePostWithinMonthlyLimitResult> => {
  if (!prisma.$transaction) {
    throw new Error('Prisma post store requires transaction support');
  }

  const maxAttempts = 3;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await prisma.$transaction(
        async (transaction) => {
          if (input.clientRequestId) {
            const idempotencyKey = {
              userId: input.userId,
              clientRequestId: input.clientRequestId
            };
            const persisted = await transaction.post.findFirst({
              where: {
                id: buildIdempotentPostId(idempotencyKey),
                userId: input.userId
              }
            });

            if (persisted) {
              const post = mapPost(persisted);
              if (!isMatchingIdempotentIntent(post, input)) {
                throw new PostIdempotencyKeyReusedError();
              }
              return { ok: true as const, post, created: false };
            }
          }

          const usedPostUnits = await countMonthlyUnits(transaction.post, input);

          if (usedPostUnits + input.platforms.length > input.monthlyPostUnitLimit) {
            return { ok: false as const };
          }

          return {
            ok: true as const,
            post: await createPost(
              transaction.post,
              input,
              input.clientRequestId
                ? buildIdempotentPostId({
                    userId: input.userId,
                    clientRequestId: input.clientRequestId
                  })
                : undefined
            ),
            created: true
          };
        },
        { isolationLevel: 'Serializable' }
      );
    } catch (error) {
      if (
        !isRetryableTransactionConflict(error, Boolean(input.clientRequestId)) ||
        attempt === maxAttempts
      ) {
        throw error;
      }
    }
  }

  throw new Error('Prisma post quota transaction retry exhausted');
};

export const createPrismaPostRepository = ({
  prisma
}: {
  prisma: PrismaPostClient;
}): PostStore => ({
  countPublishBacklog: async () =>
    prisma.post.count({
      where: {
        status: { in: ['QUEUED', 'PUBLISHING'] }
      }
    }),
  countMonthlyPostUnits: async (input) => countMonthlyUnits(prisma.post, input),
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
  create: async (input: CreatePostInput) => createPost(prisma.post, input),
  findIdempotent: async (input: FindIdempotentPostInput) => {
    const persisted = await prisma.post.findFirst({
      where: {
        id: buildIdempotentPostId(input),
        userId: input.userId
      }
    });
    return persisted ? mapPost(persisted) : undefined;
  },
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
      data: { status: 'PUBLISHING' }
    });

    return result.count > 0;
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
  reschedule: async ({ postId, userId, expectedScheduledAt, scheduledAt }) => {
    const result = await prisma.post.updateMany({
      where: {
        id: postId,
        userId,
        status: 'QUEUED',
        ...(expectedScheduledAt !== undefined
          ? {
              scheduledAt:
                expectedScheduledAt === null ? null : new Date(expectedScheduledAt)
            }
          : {})
      },
      data: { scheduledAt: new Date(scheduledAt) }
    });

    if (result.count === 0) {
      return undefined;
    }

    const post = await prisma.post.findFirst({ where: { id: postId } });
    return post ? mapPost(post) : undefined;
  },
  publishNow: async ({ postId, userId, expectedScheduledAt }) => {
    const result = await prisma.post.updateMany({
      where: {
        id: postId,
        userId,
        status: 'QUEUED',
        scheduledAt: expectedScheduledAt
          ? new Date(expectedScheduledAt)
          : { not: null }
      },
      data: { scheduledAt: null }
    });

    if (result.count === 0) {
      return undefined;
    }

    const post = await prisma.post.findFirst({ where: { id: postId, userId } });
    return post ? mapPost(post) : undefined;
  },
  remove: async ({ postId, userId }) => {
    const result = await prisma.post.deleteMany({
      where: { id: postId, userId, status: 'QUEUED' }
    });

    return result.count > 0;
  }
});
