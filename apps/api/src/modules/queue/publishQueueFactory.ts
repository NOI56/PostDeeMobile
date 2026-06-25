import type { ServerConfig } from '../../config/env.js';
import {
  type BullMqQueueClient,
  createBullMqPublishQueue,
  createBullMqPublishQueueFromClient
} from './bullMqPublishQueue.js';
import { type PublishQueue, createInMemoryPublishQueue } from './publishQueue.js';

type PublishQueueConfig = Pick<ServerConfig, 'publishQueue' | 'redisUrl'>;

export const createPublishQueueFromConfig = ({
  config,
  bullMqQueue,
  now
}: {
  config: PublishQueueConfig;
  bullMqQueue?: BullMqQueueClient;
  now?: () => number;
}): PublishQueue => {
  if (config.publishQueue === 'bullmq') {
    if (bullMqQueue) {
      return createBullMqPublishQueueFromClient({
        queue: bullMqQueue,
        now
      });
    }

    return createBullMqPublishQueue({
      redisUrl: config.redisUrl,
      now
    });
  }

  return createInMemoryPublishQueue();
};
