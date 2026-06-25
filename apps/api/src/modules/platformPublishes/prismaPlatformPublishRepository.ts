import type {
  PlatformPublishStore,
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

export const createPrismaPlatformPublishRepository = ({
  prisma
}: {
  prisma: PrismaPlatformPublishClient;
}): PlatformPublishStore => ({
  recordResults: async (input) => {
    const records = toRecordedResult(input);

    await Promise.all(records.map((record) => prisma.platformPublish.upsert(toUpsertArgs(record))));

    return records;
  }
});
