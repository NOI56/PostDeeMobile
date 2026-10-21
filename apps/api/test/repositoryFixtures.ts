import { vi } from 'vitest';
import type { createApp } from '../src/app.js';

import type { PrismaPostClient } from '../src/modules/posts/prismaPostRepository.js';
import type { PrismaSubscriptionClient } from '../src/modules/subscriptions/prismaSubscriptionRepository.js';
import { withOwnerLifecycleFixture } from './ownerLifecycleFixture.js';
import type { PrismaMonthlyAddonReadTransaction } from '../src/modules/billing/prismaMonthlyAddonRepository.js';

const unexpectedDelegateCall = async (method: string): Promise<never> => {
  throw new Error(`Unexpected repository fixture call: ${method}`);
};

// Supply the entire repository surface while failing loudly for methods a test
// has not arranged. Explicit overrides retain their mock call assertions.
export const withPostRepositoryFixture = <T extends { post: Partial<PrismaPostClient['post']> }>(prisma: T) => {
  const post = {
    count: vi.fn<PrismaPostClient['post']['count']>(() => unexpectedDelegateCall('post.count')),
    findMany: vi.fn<PrismaPostClient['post']['findMany']>(() => unexpectedDelegateCall('post.findMany')),
    create: vi.fn<PrismaPostClient['post']['create']>(() => unexpectedDelegateCall('post.create')),
    update: vi.fn<PrismaPostClient['post']['update']>(() => unexpectedDelegateCall('post.update')),
    updateMany: vi.fn<PrismaPostClient['post']['updateMany']>(() => unexpectedDelegateCall('post.updateMany')),
    deleteMany: vi.fn<PrismaPostClient['post']['deleteMany']>(() => unexpectedDelegateCall('post.deleteMany')),
    findFirst: vi.fn<PrismaPostClient['post']['findFirst']>(() => unexpectedDelegateCall('post.findFirst')),
    ...prisma.post
  };
  return withOwnerLifecycleFixture({ ...prisma, post });
};

export const withSubscriptionRepositoryFixture = <T extends {
  subscription: Partial<PrismaSubscriptionClient['subscription']>;
  user?: Partial<PrismaSubscriptionClient['user']>;
}>(prisma: T) => {
  const subscription = {
    findUnique: vi.fn<PrismaSubscriptionClient['subscription']['findUnique']>(() => unexpectedDelegateCall('subscription.findUnique')),
    upsert: vi.fn<PrismaSubscriptionClient['subscription']['upsert']>(() => unexpectedDelegateCall('subscription.upsert')),
    update: vi.fn<PrismaSubscriptionClient['subscription']['update']>(() => unexpectedDelegateCall('subscription.update')),
    ...prisma.subscription
  };
  const user = {
    findUnique: vi.fn<PrismaSubscriptionClient['user']['findUnique']>(() => unexpectedDelegateCall('user.findUnique')),
    update: vi.fn<PrismaSubscriptionClient['user']['update']>(() => unexpectedDelegateCall('user.update')),
    ...prisma.user
  };
  return withOwnerLifecycleFixture({ ...prisma, subscription, user });
};

type AppPrismaClient = NonNullable<NonNullable<Parameters<typeof createApp>[0]>['prisma']>;

export const withAppPrismaFixture = <T extends {
  post: Partial<AppPrismaClient['post']>;
  user: Partial<AppPrismaClient['user']>;
  template: Partial<AppPrismaClient['template']>;
  monthlyAddonPurchase?: Partial<PrismaMonthlyAddonReadTransaction['monthlyAddonPurchase']>;
}>(prisma: T) => {
  const fail = () => unexpectedDelegateCall('unarranged app delegate');
  return withOwnerLifecycleFixture({
    ...prisma,
    post: {
      count: vi.fn<AppPrismaClient['post']['count']>(fail),
      aggregate: vi.fn<NonNullable<AppPrismaClient['post']['aggregate']>>().mockResolvedValue({ _sum: { addonPostUnits: 0 } }),
      findMany: vi.fn<AppPrismaClient['post']['findMany']>(fail),
      create: vi.fn<AppPrismaClient['post']['create']>(fail),
      update: vi.fn<AppPrismaClient['post']['update']>(fail),
      updateMany: vi.fn<AppPrismaClient['post']['updateMany']>(fail),
      deleteMany: vi.fn<AppPrismaClient['post']['deleteMany']>(fail),
      findFirst: vi.fn<AppPrismaClient['post']['findFirst']>(fail),
      ...prisma.post
    },
    user: {
      // A zero-argument throwing stub supports both User read projections;
      // Vitest's function generic retains only the last overload.
      findUnique: vi.fn(fail),
      upsert: vi.fn<AppPrismaClient['user']['upsert']>(fail),
      update: vi.fn<AppPrismaClient['user']['update']>(fail),
      ...prisma.user
    },
    template: {
      findMany: vi.fn<AppPrismaClient['template']['findMany']>(fail),
      create: vi.fn<AppPrismaClient['template']['create']>(fail),
      ...prisma.template
    },
    subscription: {
      findUnique: vi.fn<AppPrismaClient['subscription']['findUnique']>(fail),
      upsert: vi.fn<AppPrismaClient['subscription']['upsert']>(fail),
      update: vi.fn<AppPrismaClient['subscription']['update']>(fail)
    },
    platformPublish: { findMany: vi.fn<AppPrismaClient['platformPublish']['findMany']>(fail) },
    realClipCaptionUsage: {
      count: vi.fn<AppPrismaClient['realClipCaptionUsage']['count']>(async args =>
        args.where.usesAddonCredit === true ? 0 : fail()),
      create: vi.fn<AppPrismaClient['realClipCaptionUsage']['create']>(fail)
    },
    monthlyAddonPurchase: {
      // Existing fixtures have no purchased credits unless a test supplies its
      // own ledger. All other unarranged repository operations stay strict.
      findMany: vi.fn().mockResolvedValue([]),
      ...prisma.monthlyAddonPurchase
    },
    aiEditUsage: {
      aggregate: vi.fn<AppPrismaClient['aiEditUsage']['aggregate']>(fail),
      create: vi.fn<AppPrismaClient['aiEditUsage']['create']>(fail)
    },
    deviceToken: {
      deleteMany: vi.fn<AppPrismaClient['deviceToken']['deleteMany']>(fail),
      upsert: vi.fn<AppPrismaClient['deviceToken']['upsert']>(fail),
      findMany: vi.fn<AppPrismaClient['deviceToken']['findMany']>(fail)
    },
    socialConnection: {
      findMany: vi.fn<AppPrismaClient['socialConnection']['findMany']>(fail),
      findUnique: vi.fn<AppPrismaClient['socialConnection']['findUnique']>(fail),
      upsert: vi.fn<AppPrismaClient['socialConnection']['upsert']>(fail),
      deleteMany: vi.fn<AppPrismaClient['socialConnection']['deleteMany']>(fail)
    },
    postPeerProfile: {
      findUnique: vi.fn<AppPrismaClient['postPeerProfile']['findUnique']>(fail),
      create: vi.fn<AppPrismaClient['postPeerProfile']['create']>(fail),
      deleteMany: vi.fn<AppPrismaClient['postPeerProfile']['deleteMany']>(fail)
    },
    managedUploadSession: {
      create: vi.fn<AppPrismaClient['managedUploadSession']['create']>(fail),
      findFirst: vi.fn<AppPrismaClient['managedUploadSession']['findFirst']>(fail),
      findUnique: vi.fn<AppPrismaClient['managedUploadSession']['findUnique']>(fail),
      findMany: vi.fn<AppPrismaClient['managedUploadSession']['findMany']>(fail),
      update: vi.fn<AppPrismaClient['managedUploadSession']['update']>(fail),
      deleteMany: vi.fn<AppPrismaClient['managedUploadSession']['deleteMany']>(fail)
    }
  }) satisfies AppPrismaClient;
};
