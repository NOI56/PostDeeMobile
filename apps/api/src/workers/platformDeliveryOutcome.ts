import type { DeliveryOutcome } from '../modules/platformPublishes/platformPublishStore.js';
import {
  normalizePersistedPlatformSettings,
  type PlatformSettings
} from '../modules/posts/platformSettings.js';
import type { Platform } from '../modules/posts/postStore.js';

/**
 * Reads the immutable settings for one provider call. A missing snapshot is
 * reserved for legacy queued work and maps to the controlled defaults that
 * were in effect before per-platform settings were persisted.
 */
export const readPlatformSettingsForPublish = ({
  platform,
  platformSettings
}: {
  platform: Platform;
  platformSettings?: PlatformSettings | null;
}): PlatformSettings =>
  normalizePersistedPlatformSettings(
    platformSettings == null
      ? undefined
      : { [platform]: platformSettings[platform] },
    [platform]
  );

/** The result is requested intent until a provider confirms final success. */
export const readRequestedDeliveryOutcome = ({
  platform,
  platformSettings
}: {
  platform: Platform;
  platformSettings?: PlatformSettings | null;
}): DeliveryOutcome => {
  const settings = readPlatformSettingsForPublish({
    platform,
    platformSettings
  });

  if (platform === 'TIKTOK') {
    return settings.TIKTOK?.publishMode === 'INBOX_DRAFT' ? 'DRAFT' : 'PRIVATE';
  }

  if (platform === 'YOUTUBE_SHORTS') {
    const visibility = settings.YOUTUBE_SHORTS?.visibility;
    if (visibility === 'public') {
      return 'LIVE';
    }
    return visibility === 'unlisted' ? 'UNLISTED' : 'PRIVATE';
  }

  if (platform === 'FACEBOOK_REELS') {
    return settings.FACEBOOK_REELS?.publishMode === 'PAGE_DRAFT' ? 'DRAFT' : 'LIVE';
  }

  return 'LIVE';
};
