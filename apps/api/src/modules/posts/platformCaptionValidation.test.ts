import { describe, expect, it } from 'vitest';

import { readPlatformCaptionIssue } from './platformCaptionValidation.js';

describe('platform caption preflight', () => {
  it.each(['a'.repeat(5000), 'ก'.repeat(1666) + 'ab', '😀'.repeat(1250)])('allows the exact YouTube UTF-8 byte boundary', (caption) => {
    expect(readPlatformCaptionIssue(caption, ['YOUTUBE_SHORTS'])).toBeUndefined();
  });
  it.each(['a'.repeat(5001), 'ก'.repeat(1667), '😀'.repeat(1251)])('rejects an oversized YouTube description', (caption) => {
    expect(readPlatformCaptionIssue(caption, ['YOUTUBE_SHORTS'])).toMatchObject({ platform: 'YOUTUBE_SHORTS', reason: 'YOUTUBE_DESCRIPTION_TOO_LONG', maxLength: 5000, unit: 'utf8_bytes' });
  });
  it.each(['ราคา < 100', 'ขนาด > 10'])('rejects YouTube forbidden description characters', (caption) => {
    expect(readPlatformCaptionIssue(caption, ['YOUTUBE_SHORTS'])).toMatchObject({ reason: 'YOUTUBE_DESCRIPTION_INVALID_CHARACTERS' });
  });
  it('counts Instagram conservatively in UTF-16 units', () => {
    expect(readPlatformCaptionIssue('😀'.repeat(1100), ['INSTAGRAM_REELS'])).toBeUndefined();
    expect(readPlatformCaptionIssue('😀'.repeat(1101), ['INSTAGRAM_REELS'])).toMatchObject({ reason: 'INSTAGRAM_CAPTION_TOO_LONG', maxLength: 2200, unit: 'utf16_units' });
  });
  it('uses the same conservative Facebook UTF-16 boundary as Mobile', () => {
    expect(readPlatformCaptionIssue('😀'.repeat(31603), ['FACEBOOK_REELS'])).toBeUndefined();
    expect(readPlatformCaptionIssue('😀'.repeat(31604), ['FACEBOOK_REELS'])).toMatchObject({ reason: 'FACEBOOK_CAPTION_TOO_LONG', maxLength: 63206, unit: 'utf16_units' });
  });
  it('leaves TikTok Inbox and its separate Direct limit unchanged', () => {
    expect(readPlatformCaptionIssue('<' + 'a'.repeat(65000), ['TIKTOK'])).toBeUndefined();
    expect(readPlatformCaptionIssue('a'.repeat(2201), ['YOUTUBE_SHORTS'])).toBeUndefined();
  });
});
