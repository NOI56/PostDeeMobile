import type { PlatformPublishResult } from '../../workers/publishWorker.js';
import type { Platform } from '../posts/postStore.js';

export type RecordedPlatformPublish = {
  postId: string;
  platform: Platform;
  status: 'PUBLISHED' | 'FAILED';
  externalPostId?: string;
  errorMessage?: string;
  publishedAt?: string;
  views: number;
  likes: number;
};

export type RecordPlatformPublishResultsInput = {
  postId: string;
  results: PlatformPublishResult[];
};

export type PlatformPublishStore = {
  recordResults: (
    input: RecordPlatformPublishResultsInput
  ) => Promise<RecordedPlatformPublish[]>;
};

const mapResult = (
  postId: string,
  result: PlatformPublishResult
): RecordedPlatformPublish => {
  if (result.status === 'PUBLISHED') {
    return {
      postId,
      platform: result.platform,
      status: result.status,
      externalPostId: result.externalPostId,
      publishedAt: result.publishedAt,
      views: 0,
      likes: 0
    };
  }

  return {
    postId,
    platform: result.platform,
    status: result.status,
    errorMessage: result.errorMessage,
    views: 0,
    likes: 0
  };
};

export const createInMemoryPlatformPublishStore = (): PlatformPublishStore => {
  const records = new Map<string, RecordedPlatformPublish>();

  return {
    recordResults: async ({ postId, results }) => {
      const recordedResults = results.map((result) => mapResult(postId, result));

      for (const result of recordedResults) {
        records.set(`${result.postId}:${result.platform}`, result);
      }

      return recordedResults;
    }
  };
};
