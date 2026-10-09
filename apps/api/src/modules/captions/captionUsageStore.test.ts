import { describe, expect, it } from 'vitest';
import { createInMemoryRealClipCaptionUsageStore } from './captionUsageStore.js';

describe('caption reservation release', () => {
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
