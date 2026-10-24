import 'dotenv/config';

import { Worker } from 'bullmq';
import { createGracefulShutdown } from '../shutdown.js';
import { createSentryMonitoring, reportMonitoringError } from '../monitoring/sentryMonitoring.js';

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
import type { PrismaSocialConnectionClient } from '../modules/socialConnections/prismaSocialConnectionRepository.js';
import { createSocialConnectionStore } from '../modules/socialConnections/socialConnectionStoreFactory.js';
import { createVideoStorageFromConfig } from '../modules/storage/videoStorageFactory.js';
import type { PrismaSubscriptionClient } from '../modules/subscriptions/prismaSubscriptionRepository.js';
import { createSubscriptionStoreFromConfig } from '../modules/subscriptions/subscriptionStoreFactory.js';
import {
  createPrismaUploadSessionRepository,
  type PrismaUploadSessionClient
} from '../modules/uploads/prismaUploadSessionRepository.js';
import { createPlatformPublisherFromConfig } from './platformPublisherFactory.js';
import { processPublishJobForPost } from './publishWorker.js';
import { createScheduledPublishPlanReader } from './scheduledPublishPlan.js';
import {
  buildPublishWorkerCompletedLog,
  buildPublishWorkerFailedLog,
  enforceRetriedPublishRecoveryPolicy
} from './publishWorkerRunnerPolicy.js';

const config = readServerConfig();
const monitoring = await createSentryMonitoring(config.sentry, { component: 'worker' });
const storage = createVideoStorageFromConfig({ config });
// Create Prisma when a configured store needs it, when real PostPeer publishing
// needs user connections, or when the worker must enforce deletion barriers.
const prisma =
  config.postStore === 'prisma' ||
  config.analyticsStore === 'prisma' ||
  config.socialPublisher === 'postpeer' ||
  config.uploadProtocolMode !== 'legacy' ||
  config.subscriptionStore === 'prisma' ||
  config.trialAccessEnabled
    ? createPrismaClient()
    : undefined;
const socialConnectionStore = createSocialConnectionStore({
  prisma: prisma as unknown as PrismaSocialConnectionClient | undefined
});
const postStore = createPostStoreFromConfig({
  config,
  prisma: prisma as unknown as PrismaPostClient | undefined
});
const uploadSessionStore =
  prisma
    ? createPrismaUploadSessionRepository({
        prisma: prisma as unknown as PrismaUploadSessionClient
      })
    : undefined;
const publisher = createPlatformPublisherFromConfig({
  config,
  videoStorage: storage,
  socialConnectionStore,
  assertOwnerActive: uploadSessionStore?.assertOwnerActive
});
const platformPublishStore = prisma
  ? createPrismaPlatformPublishRepository({
      prisma: prisma as unknown as PrismaPlatformPublishClient
    })
  : createInMemoryPlatformPublishStore();
// Scheduled posts re-check the owner's current plan (including trials) when due.
const readOwnerPlan = createScheduledPublishPlanReader({
  config,
  subscriptionStore: createSubscriptionStoreFromConfig({
    config,
    prisma: prisma as unknown as PrismaSubscriptionClient | undefined
  })
});
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
  async (job) => {
    const result = await processPublishJobForPost({
      jobData: job.data,
      postStore,
      publisher,
      storage,
      platformPublishStore,
      notifier,
      assertOwnerActive: uploadSessionStore?.assertOwnerActive,
      runWithActiveOwner: uploadSessionStore?.runWithOwnerLifetime,
      readOwnerPlan
    });

    return enforceRetriedPublishRecoveryPolicy({
      attemptsStarted: job.attemptsStarted,
      result
    });
  },
  {
    connection: parseRedisConnection(config.redisUrl)
  }
);

worker.on('completed', (job, result) => {
  console.log(
    'Publish worker completed:',
    buildPublishWorkerCompletedLog({ result })
  );
});

worker.on('failed', (job, error) => {
  reportMonitoringError(error, { operation: 'worker.failure' });
  console.error(
    'Publish worker failed:',
    buildPublishWorkerFailedLog({
      postId: job?.data.postId,
      platforms: job?.data.platforms.map((platform) => ({ platform })),
      error
    })
  );
});

console.log(`PostDee publish worker is listening on ${publishQueueName}`);

const shutdown = createGracefulShutdown({
  markUnavailable: () => undefined,
  stopScheduling: () => undefined,
  stopAcceptingRequests: async () => undefined,
  // BullMQ stops claiming new jobs and waits for the active job by default.
  drainPublishing: async () => { await worker.close(); },
  closeResources: async () => {
    try { await prisma?.$disconnect(); }
    finally { await monitoring.flush(); }
  }
});
worker.on('error', (error: unknown) => {
  reportMonitoringError(error, { operation: 'worker.connection' });
  console.error('Publish worker connection failed', { code: 'PUBLISH_WORKER_UNAVAILABLE' });
});
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    void shutdown().then(() => {
      console.log('PostDee publish worker shutdown completed');
      process.exitCode = 0;
    }, async (error: unknown) => {
      reportMonitoringError(error, { operation: 'server.shutdown' });
      console.error('PostDee publish worker shutdown did not complete', { code: 'SHUTDOWN_FAILED' });
      await monitoring.flush();
      process.exit(1);
    });
  });
}
