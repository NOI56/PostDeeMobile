import { describe, expect, it, vi } from 'vitest';

import { createPostStoreFromConfig } from './postStoreFactory.js';
import type { PrismaPostClient } from './prismaPostRepository.js';

describe('createPostStoreFromConfig', () => {
  it('uses the in-memory post store by default', async () => {
    const store = createPostStoreFromConfig({
      config: {
        postStore: 'memory'
      }
    });

    const post = await store.create({
      userId: 'seller-1',
      caption: 'Memory post',
      videoS3Key: 'uploads/video.mp4',
      platforms: ['TIKTOK']
    });

    expect(await store.list({ userId: 'seller-1' })).toEqual([post]);
  });

  it('uses the Prisma post repository when configured', async () => {
    const createdAt = new Date('2026-06-01T00:00:00.000Z');
    const transaction: Omit<PrismaPostClient, '$transaction'> = {
      managedUploadOwner: {
        upsert: vi.fn<PrismaPostClient['managedUploadOwner']['upsert']>(),
        updateMany: vi.fn<PrismaPostClient['managedUploadOwner']['updateMany']>()
      },
      post: {
        findMany: vi.fn<PrismaPostClient['post']['findMany']>().mockResolvedValue([
          {
            id: 'post-1',
            userId: 'seller-1',
            caption: 'Prisma post',
            videoS3Key: 'uploads/video.mp4',
            selectedPlatforms: ['FACEBOOK_REELS'],
            scheduledAt: null,
            status: 'QUEUED',
            publishedAt: null,
            createdAt
          }
        ]),
        create: vi.fn<PrismaPostClient['post']['create']>(),
        update: vi.fn<PrismaPostClient['post']['update']>(),
        updateMany: vi.fn<PrismaPostClient['post']['updateMany']>(),
        deleteMany: vi.fn<PrismaPostClient['post']['deleteMany']>(),
        findFirst: vi.fn<PrismaPostClient['post']['findFirst']>()
      }
    };
    const prisma: PrismaPostClient = {
      ...transaction,
      $transaction: async (operation) => operation(transaction)
    };
    const store = createPostStoreFromConfig({
      config: {
        postStore: 'prisma'
      },
      prisma
    });

    expect(await store.list({ userId: 'seller-1' })).toEqual([
      {
        id: 'post-1',
        userId: 'seller-1',
        caption: 'Prisma post',
        videoS3Key: 'uploads/video.mp4',
        platforms: ['FACEBOOK_REELS'],
        scheduledAt: undefined,
        status: 'QUEUED',
        createdAt: '2026-06-01T00:00:00.000Z'
      }
    ]);
  });

  it('requires a Prisma client when Prisma post storage is configured', () => {
    expect(() =>
      createPostStoreFromConfig({
        config: {
          postStore: 'prisma'
        }
      })
    ).toThrow('Prisma post store requires a Prisma client');
  });
});
