import 'dotenv/config';

import { Worker } from 'bullmq';

import { readServerConfig } from '../config/env.js';
import { createPrismaClient } from '../config/prisma.js';
import { createDeviceTokenStore } from '../modules/devices/deviceTokenStoreFactory.js';
import type { PrismaDeviceTokenClient } from '../modules/devices/prismaDeviceTokenRepository.js';
import { createPublishNotifier } from '../modules/notifications/publishNotifier.js';
import { createPushSenderFromConfig } from '../modules/notifications/pushSenderFactory.js';
import { createInMemoryPlatformPublishStore } from '../modules/platformPublishes/platformPublishStore.js';
import {
  createPrismaPlatformPublishRepository,
  type PrismaPlatformPublishClient
} from '../modules/platformPublishes/prismaPlatformPublishRepository.js';
import type { PrismaPostClient } from '../modules/posts/prismaPostRepository.js';
import {
  type BullMqPublishJobData,
  parseRedisConnection,
  publishQueueName
} from '../modules/queue/bullMqPublishQueue.js';
import { createPostStoreFromConfig } from '../modules/posts/postStoreFactory.js';
import { createVideoStorageFromConfig } from '../modules/storage/videoStorageFactory.js';
import { createPlatformPublisherFromConfig } from './platformPublisherFactory.js';
import { processPublishJobForPost } from './publishWorker.js';

const config = readServerConfig();
const storage = createVideoStorageFromConfig({ config });
const publisher = createPlatformPublisherFromConfig({ config, videoStorage: storage });
// Create Prisma when the post store or analytics store needs it, so the worker
// can advance post status (QUEUED -> PUBLISHED/PARTIAL_PUBLISHED/FAILED) after
// publishing — otherwise BullMQ-published posts would stay QUEUED forever.
const prisma =
  config.postStore === 'prisma' || config.analyticsStore === 'prisma'
    ? createPrismaClient()
    : undefined;
const postStore = createPostStoreFromConfig({
  config,
  prisma: prisma as unknown as PrismaPostClient | undefined
});
const platformPublishStore = prisma
  ? createPrismaPlatformPublishRepository({
      prisma: prisma as unknown as PrismaPlatformPublishClient
    })
  : createInMemoryPlatformPublishStore();
const deviceTokenStore = createDeviceTokenStore({
  prisma: prisma as unknown as PrismaDeviceTokenClient | undefined
});
// Real FCM sender when PUSH_SENDER=firebase, otherwise a no-op mock.
const notifier = createPublishNotifier({
  deviceTokenStore,
  pushSender: createPushSenderFromConfig({ config })
});

const worker = new Worker<BullMqPublishJobData>(
  publishQueueName,
  async (job) =>
    processPublishJobForPost({
      jobData: job.data,
      postStore,
      publisher,
      storage,
      platformPublishStore,
      notifier
    }),
  {
    connection: parseRedisConnection(config.redisUrl)
  }
);

worker.on('completed', (job, result) => {
  console.log(`Publish worker completed job ${job.id}:`, result);
});

worker.on('failed', (job, error) => {
  console.error(`Publish worker failed job ${job?.id ?? 'unknown'}:`, error);
});

console.log(`PostDee publish worker is listening on ${publishQueueName}`);
