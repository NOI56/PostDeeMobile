import { describe, expect, it } from 'vitest';

import { countCurrentMonthPosts, isCurrentMonthPost } from './postUsage.js';

describe('post usage helpers', () => {
  it('counts only posts created in the current UTC month', () => {
    const now = new Date('2026-06-15T12:00:00.000Z');
    const posts = [
      { createdAt: '2026-06-01T00:00:00.000Z' },
      { createdAt: '2026-06-30T23:59:59.000Z' },
      { createdAt: '2026-05-31T23:59:59.000Z' },
      { createdAt: '2026-07-01T00:00:00.000Z' },
      { createdAt: 'not-a-date' }
    ];

    expect(countCurrentMonthPosts(posts, now)).toBe(2);
    expect(isCurrentMonthPost({ createdAt: '2026-06-15T00:00:00.000Z' }, now)).toBe(true);
    expect(isCurrentMonthPost({ createdAt: '2026-07-01T00:00:00.000Z' }, now)).toBe(false);
  });
});
