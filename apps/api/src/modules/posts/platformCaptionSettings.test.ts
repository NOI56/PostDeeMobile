import { describe, expect, it } from 'vitest';

import {
  arePlatformSettingsEqual,
  normalizePersistedPlatformSettings,
  readPlatformSettings
} from './platformSettings.js';

const settings = {
  TIKTOK: { publishMode: 'INBOX_DRAFT' as const, caption: 'TikTok caption' },
  YOUTUBE_SHORTS: {
    title: 'Video title', visibility: 'private' as const, madeForKids: false,
    containsSyntheticMedia: false, communityGuidelinesCertified: true as const,
    caption: 'YouTube description'
  },
  INSTAGRAM_REELS: { shareToFeed: true, caption: 'Instagram caption' },
  FACEBOOK_REELS: { publishMode: 'PUBLISH' as const, caption: 'Facebook caption' }
};
const platforms = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const;

describe('per-platform caption snapshots', () => {
  it('parses and persists distinct captions for all four destinations', () => {
    expect(readPlatformSettings(settings, [...platforms])).toEqual({ ok: true, value: settings });
    expect(normalizePersistedPlatformSettings(settings, [...platforms])).toEqual(settings);
  });

  it.each(platforms)('includes the %s override in immutable submission identity', (platform) => {
    expect(arePlatformSettingsEqual(settings, settings, [...platforms])).toBe(true);
    const changed = { ...settings, [platform]: { ...settings[platform], caption: 'Changed destination text' } };
    expect(arePlatformSettingsEqual(settings, changed, [...platforms])).toBe(false);
    const { caption: _caption, ...withoutCaption } = settings[platform];
    expect(arePlatformSettingsEqual(settings, { ...settings, [platform]: withoutCaption }, [...platforms])).toBe(false);
  });

  it.each([undefined, null, '', '   ', 123, {}, []])('rejects a present invalid caption %j', (caption) => {
    expect(readPlatformSettings({ INSTAGRAM_REELS: { shareToFeed: true, caption } }, ['INSTAGRAM_REELS']))
      .toEqual({ ok: false });
  });

  it.each(['', '   '])('retains an explicit empty YouTube description without falling back to shared text (%j)', (caption) => {
    const withEmptyYoutube = { ...settings, YOUTUBE_SHORTS: { ...settings.YOUTUBE_SHORTS, caption } };
    const normalized = { ...settings, YOUTUBE_SHORTS: { ...settings.YOUTUBE_SHORTS, caption: '' } };
    expect(readPlatformSettings(withEmptyYoutube, [...platforms])).toEqual({ ok: true, value: normalized });
    expect(normalizePersistedPlatformSettings(withEmptyYoutube, [...platforms])).toEqual(normalized);
    expect(arePlatformSettingsEqual(normalized, settings, [...platforms])).toBe(false);
    const { caption: _caption, ...youtubeWithoutCaption } = settings.YOUTUBE_SHORTS;
    expect(arePlatformSettingsEqual(normalized, { ...settings, YOUTUBE_SHORTS: youtubeWithoutCaption }, [...platforms])).toBe(false);
  });

  it.each(['TIKTOK', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'] as const)('continues rejecting an empty %s override', (platform) => {
    expect(readPlatformSettings({ ...settings, [platform]: { ...settings[platform], caption: '' } }, [...platforms]))
      .toEqual({ ok: false });
  });

  it('normalizes whitespace while keeping the original destination requirements strict', () => {
    expect(readPlatformSettings({ TIKTOK: { publishMode: 'INBOX_DRAFT', caption: '  ข้อความใหม่  ' } }, ['TIKTOK']))
      .toEqual({ ok: true, value: { TIKTOK: { publishMode: 'INBOX_DRAFT', caption: 'ข้อความใหม่' } } });
    expect(readPlatformSettings({ TIKTOK: { publishMode: 'INBOX_DRAFT', caption: 'Caption', unknown: true } }, ['TIKTOK']))
      .toEqual({ ok: false });
    expect(readPlatformSettings({ YOUTUBE_SHORTS: { visibility: 'private', caption: 'Caption' } }, ['YOUTUBE_SHORTS']))
      .toEqual({ ok: false });
  });

  it('keeps historical no-override settings unchanged', () => {
    const legacy = { TIKTOK: { publishMode: 'DIRECT_POST', privacyLevel: 'SELF_ONLY' }, YOUTUBE_SHORTS: { visibility: 'private' } };
    expect(normalizePersistedPlatformSettings(legacy, ['TIKTOK', 'YOUTUBE_SHORTS'])).toEqual(legacy);
  });
});
