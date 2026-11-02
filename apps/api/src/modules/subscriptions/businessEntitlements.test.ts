import { describe, expect, it } from 'vitest';

import {
  canSchedulePosts,
  maxProfileLinksByPlan,
  maxScheduleAheadDaysByPlan,
  monthlyAiCaptionGenerationLimits,
  monthlyPostUnitLimits,
  readPlanLabel,
  readRealClipCaptionMode
} from './subscriptionEntitlements.js';
import { createSubscriptionStore, type SubscriptionPlan } from './subscriptionStore.js';

describe('Business monthly entitlements', () => {
  it('keeps each existing allowance and gives Business the confirmed monthly quantities', () => {
    expect(monthlyPostUnitLimits).toEqual({ BASIC: 3, STARTER: 120, PRO: 250, BUSINESS: 400 });
    expect(monthlyAiCaptionGenerationLimits).toEqual({ BASIC: 0, STARTER: 50, PRO: 120, BUSINESS: 220 });
    expect(maxProfileLinksByPlan).toEqual({ BASIC: 2, STARTER: 7, PRO: 20, BUSINESS: 50 });
  });

  it('inherits the current Pro scheduling and real-clip caption capability', () => {
    const plan = 'BUSINESS' as SubscriptionPlan;
    expect(canSchedulePosts(plan)).toBe(true);
    expect(maxScheduleAheadDaysByPlan[plan]).toBe(30);
    expect(readRealClipCaptionMode(plan)).toBe('AUDIO_WITH_FRAMES');
    expect(readPlanLabel(plan)).toBe('Business');
  });

  it('persists a Business purchase and falls back to Basic at its unchanged paid-period boundary', async () => {
    let instant = '2026-11-02T00:00:00.000Z';
    const store = createSubscriptionStore({ now: () => instant });
    const user = { id: 'business-owner', provider: 'firebase' as const };
    const result = await store.activatePlan(user, 'BUSINESS', {
      billingSubscriptionId: 'revenuecat:business-owner', currentPeriodEnd: '2026-12-02T00:00:00.000Z'
    });
    expect(result).toMatchObject({ plan: 'BUSINESS', status: 'ACTIVE', currentPeriodEnd: '2026-12-02T00:00:00.000Z' });
    expect(await store.getPlan(user)).toBe('BUSINESS');
    instant = '2026-12-02T00:00:00.000Z';
    expect(await store.getPlan(user)).toBe('BASIC');
  });

});
