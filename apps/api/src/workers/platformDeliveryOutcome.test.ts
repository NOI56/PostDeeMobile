import { describe, expect, it } from 'vitest';

import type { PlatformSettings } from '../modules/posts/platformSettings.js';
import type { Platform } from '../modules/posts/postStore.js';
import { readRequestedDeliveryOutcome } from './platformDeliveryOutcome.js';

describe('readRequestedDeliveryOutcome', () => {
  it.each<{
    platform: Platform;
    platformSettings?: PlatformSettings | null;
    expected: 'LIVE' | 'PRIVATE' | 'UNLISTED' | 'DRAFT';
  }>([
    {
      platform: 'TIKTOK',
      platformSettings: null,
      expected: 'PRIVATE'
    },
    {
      platform: 'TIKTOK',
      platformSettings: { TIKTOK: { publishMode: 'INBOX_DRAFT' } },
      expected: 'DRAFT'
    },
    {
      platform: 'YOUTUBE_SHORTS',
      expected: 'PRIVATE'
    },
    {
      platform: 'YOUTUBE_SHORTS',
      platformSettings: {
        YOUTUBE_SHORTS: {
          title: 'Unlisted video',
          visibility: 'unlisted',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true
        }
      },
      expected: 'UNLISTED'
    },
    {
      platform: 'YOUTUBE_SHORTS',
      platformSettings: {
        YOUTUBE_SHORTS: {
          title: 'Public video',
          visibility: 'public',
          madeForKids: false,
          containsSyntheticMedia: true,
          communityGuidelinesCertified: true
        }
      },
      expected: 'LIVE'
    },
    {
      platform: 'INSTAGRAM_REELS',
      platformSettings: { INSTAGRAM_REELS: { shareToFeed: false } },
      expected: 'LIVE'
    },
    {
      platform: 'FACEBOOK_REELS',
      expected: 'LIVE'
    },
    {
      platform: 'FACEBOOK_REELS',
      platformSettings: {
        FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' }
      },
      expected: 'DRAFT'
    }
  ])('maps $platform to $expected', ({ platform, platformSettings, expected }) => {
    expect(
      readRequestedDeliveryOutcome({ platform, platformSettings })
    ).toBe(expected);
  });
});
