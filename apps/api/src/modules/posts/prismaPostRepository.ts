import type {
  CreatePostInput,
  Platform,
  PostStatus,
  PostStore,
  QueuedPost,
  ClaimPostForPublishInput,
  UpdatePostStatusInput
} from './postStore.js';

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
      OR?: Array<{ scheduledAt: null } | { scheduledAt: { lte: Date } }>;
    };
    orderBy: { createdAt: 'desc' } | { scheduledAt: 'asc' };
  }) => Promise<PrismaPost[]>;
  create: (args: {
    data: {
      userId: string;
      caption: string;
      videoS3Key: string;
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
      OR?: Array<{ scheduledAt: null } | { scheduledAt: Date }>;
    };
    data: { scheduledAt?: Date; status?: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  deleteMany: (args: {
    where: { id: string; userId: string; status: PrismaPostStatus };
  }) => Promise<{ count: number }>;
  findFirst: (args: { where: { id: string } }) => Promise<PrismaPost | null>;
};

export type PrismaPostClient = {
  post: PostDelegate;
};

const toPostStatus = (status: PrismaPostStatus): PostStatus =>
  status === 'DRAFT' ? 'QUEUED' : status;

const mapPost = (post: PrismaPost): QueuedPost => ({
  id: post.id,
  userId: post.userId,
  caption: post.caption,
  videoS3Key: post.videoS3Key,
  platforms: [...post.selectedPlatforms],
  scheduledAt: post.scheduledAt?.toISOString(),
  status: toPostStatus(post.status),
  publishedAt: post.publishedAt?.toISOString(),
  createdAt: post.createdAt.toISOString()
});

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
  create: async (input: CreatePostInput) => {
    const post = await prisma.post.create({
      data: {
        userId: input.userId,
        caption: input.caption,
        videoS3Key: input.videoS3Key,
        selectedPlatforms: input.platforms,
        scheduledAt: input.scheduledAt ? new Date(input.scheduledAt) : undefined,
        status: 'QUEUED'
      }
    });

    return mapPost(post);
  },
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
  reschedule: async ({ postId, userId, scheduledAt }) => {
    const result = await prisma.post.updateMany({
      where: { id: postId, userId, status: 'QUEUED' },
      data: { scheduledAt: new Date(scheduledAt) }
    });

    if (result.count === 0) {
      return undefined;
    }

    const post = await prisma.post.findFirst({ where: { id: postId } });
    return post ? mapPost(post) : undefined;
  },
  remove: async ({ postId, userId }) => {
    const result = await prisma.post.deleteMany({
      where: { id: postId, userId, status: 'QUEUED' }
    });

    return result.count > 0;
  }
});
