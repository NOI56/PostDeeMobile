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
  isMatchingIdempotentIntent,
  maxDuePostsPerPoll
} from './postStore.js';
import { normalizePersistedPlatformSettings } from './platformSettings.js';
import { normalizePersistedPlatformTargets } from './platformTargets.js';
import { lockActiveOwner, runActiveOwnerTransaction, type PrismaOwnerLifecycleTransaction } from '../account/ownerLifecycle.js';
import { readPrismaMonthlyAddonCredits, type PrismaMonthlyAddonReadTransaction } from '../billing/prismaMonthlyAddonRepository.js';

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
  mediaContentFingerprint?: string | null;
  coverImageS3Key?: string | null;
  coverFrameTimeMs?: number | null;
  selectedPlatforms: Platform[];
  platformSettings?: unknown | null;
  platformTargets?: unknown | null;
  scheduledAt: Date | null;
  status: PrismaPostStatus;
  publishedAt: Date | null;
  createdAt: Date;
  addonPostUnits?: number;
};

// Publish fields only: the scheduler never needs the media fingerprint or the
// add-on allocation of a due post.
const duePostSelect = {
  id: true, userId: true, caption: true, videoS3Key: true, coverImageS3Key: true,
  coverFrameTimeMs: true, selectedPlatforms: true, platformSettings: true,
  platformTargets: true, scheduledAt: true, status: true, publishedAt: true, createdAt: true
} as const;

type PostDelegate = {
  aggregate?: (args: { where: { userId: string }; _sum: { addonPostUnits: true } }) =>
    Promise<{ _sum: { addonPostUnits: number | null } }>;
  count: (args: {
    where: { status: { in: PrismaPostStatus[] } };
  }) => Promise<number>;
  findMany: (args: {
    where: {
      userId?: string;
      status?: PrismaPostStatus;
      scheduledAt?: { not: null };
      createdAt?: { gte: Date; lt: Date };
      OR?:
        | Array<{ scheduledAt: null } | { scheduledAt: { lte: Date } }>
        | [{ createdAt: { lt: Date } }, { createdAt: Date; id: { lt: string } }];
    };
    orderBy?:
      | { createdAt: 'desc' }
      | { scheduledAt: 'asc' }
      | [{ createdAt: 'desc' }, { id: 'desc' }];
    take?: number;
    select?:
      | { createdAt: true; selectedPlatforms: true; addonPostUnits?: true }
      | { id: true; selectedPlatforms: true }
      | typeof duePostSelect;
  }) => Promise<PrismaPost[]>;
  create: (args: {
    data: {
      id?: string;
      userId: string;
      caption: string;
      videoS3Key: string;
      mediaContentFingerprint?: string;
      coverImageS3Key?: string;
      coverFrameTimeMs?: number;
      selectedPlatforms: Platform[];
      platformSettings?: unknown;
      platformTargets?: unknown;
      scheduledAt?: Date;
      status: 'QUEUED';
      addonPostUnits?: number;
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
    data: { scheduledAt?: Date | null; status?: PrismaPostStatus; publishedAt?: Date };
  }) => Promise<{ count: number }>;
  deleteMany: (args: {
    where: { id: string; userId: string; status: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  findFirst: (args: { where: { id: string; userId?: string } }) => Promise<PrismaPost | null>;
};

type PrismaPostTransaction = PrismaOwnerLifecycleTransaction & Partial<PrismaMonthlyAddonReadTransaction> & {
  post: PostDelegate;
};
export type PrismaPostClient = PrismaPostTransaction & {
  $transaction: <Result>(
    operation: (client: PrismaPostTransaction) => Promise<Result>,
    options: { isolationLevel: 'Serializable'; maxWait?: number; timeout?: number }
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
    ...(post.mediaContentFingerprint ? { mediaContentFingerprint: post.mediaContentFingerprint } : {}),
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
    createdAt: post.createdAt.toISOString(),
    ...(post.addonPostUnits ? { addonPostUnits: post.addonPostUnits } : {})
  };
};

const createPost = async (
  postDelegate: PostDelegate,
  input: CreatePostInput,
  id?: string,
  addonPostUnits = 0
) => {
  const post = await postDelegate.create({
    data: {
      ...(id ? { id } : {}),
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
      status: 'QUEUED' as const,
      ...(addonPostUnits > 0 ? { addonPostUnits } : {})
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
    select: { createdAt: true, selectedPlatforms: true, addonPostUnits: true }
  });
  return countCurrentMonthPostUnits(
    posts.map((post) => ({
      createdAt: post.createdAt.toISOString(),
      platforms: post.selectedPlatforms,
      addonPostUnits: post.addonPostUnits ?? 0
    })),
    new Date(now)
  );
};

const countAddonUnits = async (post: PostDelegate, userId: string) => {
  if (!post.aggregate) throw new Error('Post addon allocation aggregate is required');
  return (await post.aggregate({ where: { userId }, _sum: { addonPostUnits: true } }))._sum.addonPostUnits ?? 0;
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
          await lockActiveOwner(transaction, input.userId);
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

          let addonPostUnits = 0;
          if (input.includeMonthlyAddons) {
            if (!transaction.monthlyAddonPurchase) throw new Error('Monthly addon transaction delegate is required');
            addonPostUnits = (await readPrismaMonthlyAddonCredits(
              { monthlyAddonPurchase: transaction.monthlyAddonPurchase }, input.userId, input.now
            )).postUnits;
          }
          const usedPostUnits = await countMonthlyUnits(transaction.post, input);
          const usedAddonUnits = input.includeMonthlyAddons ? await countAddonUnits(transaction.post, input.userId) : 0;
          const neededAddonUnits = Math.max(0, input.platforms.length - Math.max(0, input.monthlyPostUnitLimit - usedPostUnits));
          if (neededAddonUnits > Math.max(0, addonPostUnits - usedAddonUnits)) {
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
                : undefined,
              neededAddonUnits
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
  listPublishing: async () => {
    const posts = await prisma.post.findMany({
      where: { status: 'PUBLISHING' },
      select: { id: true, selectedPlatforms: true },
      orderBy: { createdAt: 'desc' }
    });
    return posts.map((post) => ({ id: post.id, platforms: [...post.selectedPlatforms] }));
  },
  finalizeInterruptedPublish: async ({ postId, status, publishedAt }) => {
    const result = await prisma.post.updateMany({
      where: { id: postId, status: 'PUBLISHING' },
      data: { status, ...(publishedAt ? { publishedAt: new Date(publishedAt) } : {}) }
    });
    return result.count === 1;
  },
  countPublishBacklog: async () =>
    prisma.post.count({
      where: {
        status: { in: ['QUEUED', 'PUBLISHING'] }
      }
    }),
  countMonthlyPostUnits: async (input) => countMonthlyUnits(prisma.post, input),
  countAddonPostUnits: async ({ userId }) => countAddonUnits(prisma.post, userId),
  list: async (filter) => {
    // An unscoped list would read every owner's history in the shared process.
    if (!filter?.userId) throw new Error('PostStore.list requires userId');
    const scheduledOnly = filter.scheduledOnly ?? false;
    const limited = filter.limit !== undefined;
    const posts = await prisma.post.findMany({
      where: {
        userId: filter.userId,
        ...(scheduledOnly
          ? {
              scheduledAt: {
                not: null
              }
            }
          : {})
      },
      orderBy: scheduledOnly && !limited ? { scheduledAt: 'asc' } : { createdAt: 'desc' },
      ...(limited ? { take: filter.limit } : {})
    });

    return posts.map(mapPost);
  },
  listPage: async ({ userId, scheduledOnly = false, limit, after }) => {
    const afterTime = after ? new Date(after.createdAt) : undefined;
    // One extra row tells whether another page exists; (userId, createdAt) is indexed.
    const rows = await prisma.post.findMany({
      where: {
        userId,
        ...(scheduledOnly ? { scheduledAt: { not: null } } : {}),
        ...(after && afterTime
          ? { OR: [{ createdAt: { lt: afterTime } }, { createdAt: afterTime, id: { lt: after.id } }] }
          : {})
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1
    });
    const posts = rows.slice(0, limit).map(mapPost);
    const last = posts.at(-1);
    return {
      posts,
      ...(rows.length > limit && last ? { next: { createdAt: last.createdAt, id: last.id } } : {})
    };
  },
  findOwned: async ({ postId, userId }) => {
    const persisted = await prisma.post.findFirst({ where: { id: postId, userId } });
    return persisted ? mapPost(persisted) : undefined;
  },
  create: (input: CreatePostInput) => runActiveOwnerTransaction(prisma, input.userId,
    (transaction) => createPost(transaction.post, input)),
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
  listDue: async ({ now, limit = maxDuePostsPerPoll }) => {
    // A global read across owners: keep it to one bounded batch per poll.
    const posts = await prisma.post.findMany({
      where: {
        status: 'QUEUED',
        OR: [{ scheduledAt: null }, { scheduledAt: { lte: new Date(now) } }]
      },
      orderBy: { scheduledAt: 'asc' },
      take: limit,
      select: duePostSelect
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
  reschedule: ({ postId, userId, expectedScheduledAt, scheduledAt }) => runActiveOwnerTransaction(prisma, userId, async (transaction) => {
    const result = await transaction.post.updateMany({
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

    const post = await transaction.post.findFirst({ where: { id: postId } });
    return post ? mapPost(post) : undefined;
  }),
  publishNow: ({ postId, userId, expectedScheduledAt }) => runActiveOwnerTransaction(prisma, userId, async (transaction) => {
    const result = await transaction.post.updateMany({
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

    const post = await transaction.post.findFirst({ where: { id: postId, userId } });
    return post ? mapPost(post) : undefined;
  }),
  remove: async ({ postId, userId }) => {
    const result = await prisma.post.deleteMany({
      where: { id: postId, userId, status: 'QUEUED' }
    });

    return result.count > 0;
  }
});
