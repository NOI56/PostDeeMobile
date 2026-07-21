import { describe, expect, it, vi } from 'vitest';

import { createPrismaSubscriptionRepository } from './prismaSubscriptionRepository.js';

describe('createPrismaSubscriptionRepository', () => {
  it('returns PRO for active Pro subscriptions', async () => {
    const prisma = {
      subscription: {
        findUnique: vi.fn().mockResolvedValue({
          plan: 'PRO',
          status: 'ACTIVE'
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await expect(repository.getPlan({ id: 'seller-1', provider: 'mock' })).resolves.toBe('PRO');
    expect(prisma.subscription.findUnique).toHaveBeenCalledWith({
      where: { userId: 'seller-1' },
      select: {
        plan: true,
        status: true,
        currentPeriodEnd: true
      }
    });
  });

  it('falls back to BASIC when the subscription is missing or inactive', async () => {
    const prisma = {
      subscription: {
        findUnique: vi.fn().mockResolvedValue({
          plan: 'PRO',
          status: 'CANCELED'
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await expect(repository.getPlan({ id: 'seller-1', provider: 'mock' })).resolves.toBe('BASIC');
  });

  it('upserts an active Pro subscription for a user', async () => {
    const updatedAt = new Date('2026-06-02T00:00:00.000Z');
    const prisma = {
      subscription: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          userId: 'seller-pro',
          plan: 'PRO',
          status: 'ACTIVE',
          billingSubscriptionId: 'google-play:android-purchase-token',
          currentPeriodEnd: new Date('2026-07-02T00:00:00.000Z'),
          updatedAt
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await expect(
      repository.activatePro(
        { id: 'seller-pro', provider: 'mock' },
        {
          billingSubscriptionId: 'google-play:android-purchase-token',
          currentPeriodEnd: '2026-07-02T00:00:00.000Z'
        }
      )
    ).resolves.toEqual({
      userId: 'seller-pro',
      plan: 'PRO',
      status: 'ACTIVE',
      billingSubscriptionId: 'google-play:android-purchase-token',
      currentPeriodEnd: '2026-07-02T00:00:00.000Z',
      updatedAt: '2026-06-02T00:00:00.000Z'
    });
    expect(prisma.subscription.upsert).toHaveBeenCalledWith({
      where: { userId: 'seller-pro' },
      update: {
        plan: 'PRO',
        status: 'ACTIVE',
        billingSubscriptionId: 'google-play:android-purchase-token',
        currentPeriodEnd: new Date('2026-07-02T00:00:00.000Z')
      },
      create: {
        userId: 'seller-pro',
        plan: 'PRO',
        status: 'ACTIVE',
        billingSubscriptionId: 'google-play:android-purchase-token',
        currentPeriodEnd: new Date('2026-07-02T00:00:00.000Z')
      },
      select: {
        userId: true,
        plan: true,
        status: true,
        billingSubscriptionId: true,
        currentPeriodEnd: true,
        updatedAt: true
      }
    });
  });

  it('clears a stale period end when lifetime access is explicit', async () => {
    const updatedAt = new Date('2026-07-15T00:00:00.000Z');
    const prisma = {
      subscription: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          userId: 'seller-lifetime',
          plan: 'PRO',
          status: 'ACTIVE',
          billingSubscriptionId: 'revenuecat:seller-lifetime',
          currentPeriodEnd: null,
          updatedAt
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await repository.activatePlan(
      { id: 'seller-lifetime', provider: 'firebase' },
      'PRO',
      {
        billingSubscriptionId: 'revenuecat:seller-lifetime',
        currentPeriodEnd: null
      }
    );

    expect(prisma.subscription.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: expect.objectContaining({ currentPeriodEnd: null }),
        create: expect.objectContaining({ currentPeriodEnd: null })
      })
    );
  });

  it('preserves the stored period end when an activation omits it', async () => {
    const updatedAt = new Date('2026-07-15T00:00:00.000Z');
    const prisma = {
      subscription: {
        findUnique: vi.fn(),
        upsert: vi.fn().mockResolvedValue({
          userId: 'seller-preserve-period',
          plan: 'PRO',
          status: 'ACTIVE',
          billingSubscriptionId: 'revenuecat:seller-preserve-period',
          currentPeriodEnd: new Date('2026-08-15T00:00:00.000Z'),
          updatedAt
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await repository.activatePlan(
      { id: 'seller-preserve-period', provider: 'firebase' },
      'PRO',
      { billingSubscriptionId: 'revenuecat:seller-preserve-period' }
    );

    const upsertCall = prisma.subscription.upsert.mock.calls[0]?.[0];
    expect(upsertCall.update).not.toHaveProperty('currentPeriodEnd');
    expect(upsertCall.create).not.toHaveProperty('currentPeriodEnd');
  });

  it('updates a subscription status by billing subscription id', async () => {
    const updatedAt = new Date('2026-06-03T00:00:00.000Z');
    const prisma = {
      subscription: {
        findUnique: vi.fn(),
        upsert: vi.fn(),
        update: vi.fn().mockResolvedValue({
          userId: 'seller-store',
          plan: 'PRO',
          status: 'CANCELED',
          billingSubscriptionId: 'google-play:android-purchase-token',
          currentPeriodEnd: null,
          updatedAt
        })
      }
    };
    const repository = createPrismaSubscriptionRepository({ prisma });

    await expect(
      repository.updateStatusByBillingSubscriptionId({
        billingSubscriptionId: 'google-play:android-purchase-token',
        status: 'CANCELED'
      })
    ).resolves.toEqual({
      userId: 'seller-store',
      plan: 'PRO',
      status: 'CANCELED',
      billingSubscriptionId: 'google-play:android-purchase-token',
      updatedAt: '2026-06-03T00:00:00.000Z'
    });
    expect(prisma.subscription.update).toHaveBeenCalledWith({
      where: {
        billingSubscriptionId: 'google-play:android-purchase-token'
      },
      data: {
        status: 'CANCELED'
      },
      select: {
        userId: true,
        plan: true,
        status: true,
        billingSubscriptionId: true,
        currentPeriodEnd: true,
        updatedAt: true
      }
    });
  });

});
