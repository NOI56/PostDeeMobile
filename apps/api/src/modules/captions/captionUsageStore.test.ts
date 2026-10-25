import { describe, expect, it } from 'vitest';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';
import { createInMemoryUploadSessionStore } from '../uploads/uploadSessionStore.js';

describe('caption reservation release', () => {
  it.each([1, 4])('drains an async %i-credit bank reservation before account deletion and rejects late writes', async units => {
    const lifecycle = createInMemoryUploadSessionStore();
    let release!: () => void;
    let started!: () => void;
    const pending = new Promise<void>(resolve => { release = resolve; });
    const reading = new Promise<void>(resolve => { started = resolve; });
    const store = createInMemoryRealClipCaptionUsageStore({ runWithActiveOwner: lifecycle.runWithActiveOwner,
      monthlyAddonStore: { readCredits: async () => { started(); await pending; return { postUnits: 100, aiCaptions: 50 }; } } });
    const input = { userId: 'deleting-caption-owner', monthKey: '2026-10', limit: 0, units,
      includeMonthlyAddons: true, now: '2026-10-21T00:00:00.000Z' };
    const reservation = store.reserve(input);
    await reading;
    let deletionStarted = false;
    const deleting = lifecycle.beginOwnerDeletion(input.userId).then(() => { deletionStarted = true; });
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(deletionStarted).toBe(false);
    release();
    expect((await reservation).ok).toBe(true);
    await deleting;
    await store.deleteAllForUser!(input.userId);
    await lifecycle.finishOwnerDeletion(input.userId);
    await expect(store.reserve(input)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    await expect(store.record(input)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(await store.countAddonUsages(input)).toBe(0);
  });

  it('spends monthly included captions before the nonexpiring bank and refunds the exact allocation', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ monthlyAddonStore: {
      readCredits: async () => ({ postUnits: 100, aiCaptions: 50 })
    } });
    const input = { userId: 'persistent-caption', monthKey: '2026-10', limit: 1,
      includeMonthlyAddons: true, now: '2026-10-31T23:59:59.000Z' };
    await store.reserve(input);
    const bank = await store.reserve(input);
    expect(await store.countForMonth(input)).toBe(1);
    expect(await store.countAddonUsages(input)).toBe(1);
    await store.reserve({ ...input, monthKey: '2026-11', now: '2026-11-01T00:00:00.000Z' });
    expect(await store.countAddonUsages(input)).toBe(1);
    if (!bank.ok) throw new Error('Expected bank reservation');
    expect(await store.release!(bank.record)).toBe(true);
    expect(await store.countAddonUsages(input)).toBe(0);
  });

  it('adds caption credits atomically after an async lookup and refunds only the failed reservation', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({
      now: () => '2026-10-21T00:00:00.000Z',
      monthlyAddonStore: { readCredits: async () => ({ postUnits: 100, aiCaptions: 50 }) }
    });
    const input = { userId: 'addon-owner', monthKey: '2026-10', limit: 0,
      includeMonthlyAddons: true, now: '2026-10-21T00:00:00.000Z' };
    const results = await Promise.all(Array.from({ length: 52 }, () => store.reserve(input)));
    expect(results.filter((result) => result.ok)).toHaveLength(50);
    const first = results.find((result) => result.ok);
    if (!first?.ok) throw new Error('Expected an addon reservation');
    expect(await store.release!(first.record)).toBe(true);
    expect(await store.reserve(input)).toMatchObject({ ok: true, usedThisMonth: 0 });
    expect(await store.countAddonUsages(input)).toBe(50);
    expect(await store.reserve({ ...input, includeMonthlyAddons: false })).toMatchObject({ ok: false });
  });

  it('does not release another simultaneous generation with the same timestamp', async () => {
    const store = createInMemoryRealClipCaptionUsageStore({ now: () => '2026-10-09T00:00:00Z' });
    const input = { userId: 'owner', monthKey: '2026-10', limit: 50 };
    const first = await store.reserve(input);
    const second = await store.reserve(input);
    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) throw new Error('reservation failed');
    expect(await store.release!(first.record)).toBe(true);
    expect(await store.release!(first.record)).toBe(false);
    expect(await store.countForMonth(input)).toBe(1);
    expect(await store.release!({ ...second.record })).toBe(false);
    expect(await store.release!(second.record)).toBe(true);
  });
});
