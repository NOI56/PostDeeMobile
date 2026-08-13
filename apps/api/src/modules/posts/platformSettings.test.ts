import { describe, expect, it } from 'vitest';

import {
  createDefaultPlatformSettings,
  normalizePersistedPlatformSettings,
  readPlatformSettings
} from './platformSettings.js';

describe('platform publishing settings', () => {
  it('preserves the controlled legacy defaults when the field is omitted', () => {
    expect(
      readPlatformSettings(undefined, [
        'TIKTOK',
        'YOUTUBE_SHORTS',
        'INSTAGRAM_REELS',
        'FACEBOOK_REELS'
      ])
    ).toEqual({
      ok: true,
      value: {
        TIKTOK: {
          publishMode: 'DIRECT_POST',
          privacyLevel: 'SELF_ONLY'
        },
        YOUTUBE_SHORTS: { visibility: 'private' },
        INSTAGRAM_REELS: { shareToFeed: true },
        FACEBOOK_REELS: { publishMode: 'PUBLISH' }
      }
    });
  });

  it('accepts an explicit complete snapshot for every selected platform', () => {
    const explicitSettings = {
      TIKTOK: { publishMode: 'INBOX_DRAFT' },
      YOUTUBE_SHORTS: {
        title: 'Launch walkthrough',
        visibility: 'unlisted',
        madeForKids: false,
        containsSyntheticMedia: true,
        communityGuidelinesCertified: true
      },
      INSTAGRAM_REELS: { shareToFeed: false },
      FACEBOOK_REELS: { publishMode: 'PAGE_DRAFT' }
    };

    expect(
      readPlatformSettings(explicitSettings, [
        'TIKTOK',
        'YOUTUBE_SHORTS',
        'INSTAGRAM_REELS',
        'FACEBOOK_REELS'
      ])
    ).toEqual({ ok: true, value: explicitSettings });
  });

  it.each([
    {
      name: 'a missing selected platform',
      value: { TIKTOK: { publishMode: 'INBOX_DRAFT' } },
      platforms: ['TIKTOK', 'YOUTUBE_SHORTS'] as const
    },
    {
      name: 'an unselected platform',
      value: {
        TIKTOK: { publishMode: 'INBOX_DRAFT' },
        YOUTUBE_SHORTS: {
          title: 'Unselected destination',
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true
        }
      },
      platforms: ['TIKTOK'] as const
    },
    {
      name: 'an unknown setting field',
      value: {
        YOUTUBE_SHORTS: {
          title: 'Safe title',
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true,
          categoryId: '22'
        }
      },
      platforms: ['YOUTUBE_SHORTS'] as const
    },
    {
      name: 'an explicit direct TikTok post before compliance controls exist',
      value: {
        TIKTOK: {
          publishMode: 'DIRECT_POST',
          privacyLevel: 'SELF_ONLY'
        }
      },
      platforms: ['TIKTOK'] as const
    },
    {
      name: 'an unsafe direct TikTok privacy level',
      value: {
        TIKTOK: {
          publishMode: 'DIRECT_POST',
          privacyLevel: 'PUBLIC_TO_EVERYONE'
        }
      },
      platforms: ['TIKTOK'] as const
    },
    {
      name: 'a privacy level on a TikTok inbox draft',
      value: {
        TIKTOK: {
          publishMode: 'INBOX_DRAFT',
          privacyLevel: 'SELF_ONLY'
        }
      },
      platforms: ['TIKTOK'] as const
    },
    {
      name: 'a missing YouTube community-guidelines certification',
      value: {
        YOUTUBE_SHORTS: {
          title: 'Safe title',
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: false
        }
      },
      platforms: ['YOUTUBE_SHORTS'] as const
    },
    {
      name: 'an invalid YouTube title',
      value: {
        YOUTUBE_SHORTS: {
          title: '<unsafe title>',
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true
        }
      },
      platforms: ['YOUTUBE_SHORTS'] as const
    },
    {
      name: 'a YouTube title longer than 100 Unicode characters',
      value: {
        YOUTUBE_SHORTS: {
          title: 'ก'.repeat(101),
          visibility: 'private',
          madeForKids: false,
          containsSyntheticMedia: false,
          communityGuidelinesCertified: true
        }
      },
      platforms: ['YOUTUBE_SHORTS'] as const
    }
  ])('rejects $name instead of silently changing publishing intent', ({ value, platforms }) => {
    expect(readPlatformSettings(value, [...platforms])).toMatchObject({ ok: false });
  });

  it('builds defaults only for selected platforms', () => {
    expect(createDefaultPlatformSettings(['YOUTUBE_SHORTS', 'FACEBOOK_REELS'])).toEqual({
      YOUTUBE_SHORTS: { visibility: 'private' },
      FACEBOOK_REELS: { publishMode: 'PUBLISH' }
    });
  });

  it('keeps direct/self-only readable only as a legacy persisted snapshot', () => {
    expect(
      normalizePersistedPlatformSettings(
        {
          TIKTOK: {
            publishMode: 'DIRECT_POST',
            privacyLevel: 'SELF_ONLY'
          }
        },
        ['TIKTOK']
      )
    ).toEqual({
      TIKTOK: {
        publishMode: 'DIRECT_POST',
        privacyLevel: 'SELF_ONLY'
      }
    });

    expect(
      readPlatformSettings(
        {
          TIKTOK: {
            publishMode: 'DIRECT_POST',
            privacyLevel: 'SELF_ONLY'
          }
        },
        ['TIKTOK']
      )
    ).toEqual({ ok: false });
  });
});
