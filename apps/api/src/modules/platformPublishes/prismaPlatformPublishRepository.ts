import type {
  ReadablePlatformPublishStore,
  RecordPlatformPublishResultsInput,
  RecordedPlatformPublish
} from './platformPublishStore.js';

type PlatformPublishUpsertArgs = {
  where: {
    postId_platform: {
      postId: string;
      platform: RecordedPlatformPublish['platform'];
    };
  };
  update: {
    status: RecordedPlatformPublish['status'];
    externalPostId: string | null;
    errorMessage: string | null;
    publishedAt: Date | null;
  };
  create: {
    postId: string;
    platform: RecordedPlatformPublish['platform'];
    status: RecordedPlatformPublish['status'];
    externalPostId: string | null;
    errorMessage: string | null;
    publishedAt: Date | null;
    views: 0;
    likes: 0;
  };
};

type PlatformPublishDelegate = {
  upsert: (args: PlatformPublishUpsertArgs) => Promise<unknown>;
  findMany: (args: {
    where: { postId: { in: string[] } };
    orderBy: [{ postId: 'asc' }, { platform: 'asc' }];
  }) => Promise<
    Array<{
      postId: string;
      platform: RecordedPlatformPublish['platform'];
      status: RecordedPlatformPublish['status'];
      externalPostId: string | null;
      errorMessage: string | null;
      publishedAt: Date | null;
      views: number;
      likes: number;
    }>
  >;
};

export type PrismaPlatformPublishClient = {
  platformPublish: PlatformPublishDelegate;
};

const toRecordedResult = (
  input: RecordPlatformPublishResultsInput
): RecordedPlatformPublish[] =>
  input.results.map((result) => {
    if (result.status === 'PUBLISHED') {
      return {
        postId: input.postId,
        platform: result.platform,
        status: result.status,
        externalPostId: result.externalPostId,
        publishedAt: result.publishedAt,
        views: 0,
        likes: 0
      };
    }

    return {
      postId: input.postId,
      platform: result.platform,
      status: result.status,
      errorMessage: result.errorMessage,
      views: 0,
      likes: 0
    };
  });

const toUpsertArgs = (result: RecordedPlatformPublish): PlatformPublishUpsertArgs => {
  const publishedAt = result.publishedAt ? new Date(result.publishedAt) : null;
  const externalPostId = result.externalPostId ?? null;
  const errorMessage = result.errorMessage ?? null;

  return {
    where: {
      postId_platform: {
        postId: result.postId,
        platform: result.platform
      }
    },
    update: {
      status: result.status,
      externalPostId,
      errorMessage,
      publishedAt
    },
    create: {
      postId: result.postId,
      platform: result.platform,
      status: result.status,
      externalPostId,
      errorMessage,
      publishedAt,
      views: 0,
      likes: 0
    }
  };
};

const toRecordedRow = (
  row: Awaited<ReturnType<PlatformPublishDelegate['findMany']>>[number]
): RecordedPlatformPublish => ({
  postId: row.postId,
  platform: row.platform,
  status: row.status,
  ...(row.externalPostId ? { externalPostId: row.externalPostId } : {}),
  ...(row.errorMessage ? { errorMessage: row.errorMessage } : {}),
  ...(row.publishedAt ? { publishedAt: row.publishedAt.toISOString() } : {}),
  views: row.views,
  likes: row.likes
});

export const createPrismaPlatformPublishRepository = ({
  prisma
}: {
  prisma: PrismaPlatformPublishClient;
}): ReadablePlatformPublishStore => ({
  recordResults: async (input) => {
    const records = toRecordedResult(input);

    await Promise.all(records.map((record) => prisma.platformPublish.upsert(toUpsertArgs(record))));

    return records;
  },
  listForPostIds: async (postIds) => {
    if (postIds.length === 0) {
      return [];
    }

    const rows = await prisma.platformPublish.findMany({
      where: { postId: { in: postIds } },
      orderBy: [{ postId: 'asc' }, { platform: 'asc' }]
    });

    return rows.map(toRecordedRow);
  }
});
