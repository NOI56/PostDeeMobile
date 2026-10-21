import { describe, expect, it } from 'vitest';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';

describe('caption reservation release', () => {
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
    expect(await store.reserve(input)).toMatchObject({ ok: true, usedThisMonth: 50 });
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
