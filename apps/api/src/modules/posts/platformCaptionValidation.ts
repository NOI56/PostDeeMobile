import type { Platform } from './postStore.js';

export type PlatformCaptionIssue = {
  platform: Platform;
  reason: 'YOUTUBE_DESCRIPTION_TOO_LONG' | 'YOUTUBE_DESCRIPTION_INVALID_CHARACTERS' | 'INSTAGRAM_CAPTION_TOO_LONG' | 'FACEBOOK_CAPTION_TOO_LONG';
  message: string;
  maxLength?: number;
  unit?: 'utf8_bytes' | 'utf16_units';
};

export class PlatformCaptionValidationError extends Error {
  readonly code = 'PLATFORM_CAPTION_INVALID';
  constructor(readonly issue: PlatformCaptionIssue) {
    super(issue.message);
    this.name = 'PlatformCaptionValidationError';
  }
}

export const readPlatformCaptionIssue = (caption: string | undefined, platforms: readonly Platform[]): PlatformCaptionIssue | undefined => {
  const value = caption ?? '';
  for (const platform of platforms) {
    if (platform === 'YOUTUBE_SHORTS') {
      if (/[<>]/.test(value)) return { platform, reason: 'YOUTUBE_DESCRIPTION_INVALID_CHARACTERS', message: 'YouTube descriptions cannot contain < or >. Edit the caption before posting.' };
      if (Buffer.byteLength(value, 'utf8') > 5000) return { platform, reason: 'YOUTUBE_DESCRIPTION_TOO_LONG', message: 'YouTube descriptions must not exceed 5000 UTF-8 bytes. Shorten the caption before posting.', maxLength: 5000, unit: 'utf8_bytes' };
    }
    // PostPeer's own Instagram Reels scheduler exposes a 2200-character cap.
    // UTF-16 units are a conservative preflight; never truncate the user's text.
    if (platform === 'INSTAGRAM_REELS' && value.length > 2200) return { platform, reason: 'INSTAGRAM_CAPTION_TOO_LONG', message: 'Instagram captions must not exceed 2200 characters. Shorten the caption before posting.', maxLength: 2200, unit: 'utf16_units' };
    // Meta/PostPeer document characters without a Unicode counting contract.
    // Match Mobile's conservative UTF-16 preflight at the documented cap.
    if (platform === 'FACEBOOK_REELS' && value.length > 63206) return { platform, reason: 'FACEBOOK_CAPTION_TOO_LONG', message: 'Facebook captions must not exceed 63206 characters. Shorten the caption before posting.', maxLength: 63206, unit: 'utf16_units' };
  }
  return undefined;
};
