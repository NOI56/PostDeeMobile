import { describe, expect, it } from 'vitest';
import { createMemoryTrialAccessStore, withTrialAccess } from './trialAccess.js';
import { createSubscriptionStore } from '../subscriptions/subscriptionStore.js';

describe('administrator trial access', () => {
  const user = { id: 'member', provider: 'firebase' as const };
  const command = { requestId: '54ce1fea-78bc-4c8e-a4e2-01bed4234420', actorId: 'owner', userId: user.id,
    action: 'GRANT' as const, plan: 'PRO' as const, days: 7, expectedVersion: 0, reason: 'ทดสอบกับลูกค้า' };
  it('expires without changing the purchased subscription or resetting usage', async () => {
    let now = new Date('2026-10-18T00:00:00Z');
    const trials = createMemoryTrialAccessStore({ now: () => now });
    const paid = createSubscriptionStore({ now: () => now.toISOString() });
    await paid.activatePlan(user, 'STARTER', { currentPeriodEnd: '2026-12-01T00:00:00Z' });
    const access = withTrialAccess(paid, trials, () => now);
    await trials.mutate(command);
    expect(await access.getPlan(user)).toBe('PRO');
    expect(await paid.getPlan(user)).toBe('STARTER');
    now = new Date('2026-10-25T00:00:00Z');
    expect(await access.getPlan(user)).toBe('STARTER');
  });
  it('never downgrades a purchased Pro plan and revokes only the trial', async () => {
    const trials = createMemoryTrialAccessStore();
    const paid = createSubscriptionStore();
    await paid.activatePro(user);
    const access = withTrialAccess(paid, trials);
    await trials.mutate({ ...command, plan: 'STARTER' });
    expect(await access.getPlan(user)).toBe('PRO');
    await trials.mutate({ ...command, requestId: 'revoke', action: 'REVOKE', plan: 'STARTER', expectedVersion: 1 });
    expect(await access.getPlan(user)).toBe('PRO');
  });
  it('replays the same immutable command once and rejects changed intent or stale versions', async () => {
    const trials = createMemoryTrialAccessStore();
    const result = await trials.mutate(command);
    expect(await trials.mutate(command)).toEqual(result);
    await expect(trials.mutate({ ...command, days: 14 })).rejects.toMatchObject({ code: 'ADMIN_REQUEST_CONFLICT' });
    await expect(trials.mutate({ ...command, requestId: 'stale' })).rejects.toMatchObject({ code: 'ADMIN_TRIAL_CHANGED' });
    expect(await trials.history()).toHaveLength(1);
  });
  it('extends from the current expiry, preserves the plan and audits the before/after values', async () => {
    const now = () => new Date('2026-10-18T00:00:00Z');
    const trials = createMemoryTrialAccessStore({ now });
    await trials.mutate(command);
    const extended = await trials.mutate({ ...command, requestId: 'extend', action: 'EXTEND', expectedVersion: 1 });
    expect(extended.expiresAt).toBe('2026-11-01T00:00:00.000Z');
    expect((await trials.history())[0]).toMatchObject({ action: 'EXTEND', reason: command.reason, actorId: 'owner' });
  });
  it('returns free after a grant expires when there is no paid subscription', async () => {
    let now = new Date('2026-10-18T00:00:00Z');
    const trials = createMemoryTrialAccessStore({ now: () => now });
    const access = withTrialAccess(createSubscriptionStore(), trials, () => now);
    await trials.mutate(command);
    now = new Date('2026-10-26T00:00:00Z');
    expect(await access.getPlan(user)).toBe('BASIC');
  });
});
