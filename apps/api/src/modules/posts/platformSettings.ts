import type { Platform } from './postStore.js';

export type YoutubeVisibility = 'private' | 'unlisted' | 'public';

export type TikTokPlatformSettings =
  | {
      publishMode: 'DIRECT_POST';
      // Direct Post remains controlled-first until creator-info, consent, and
      // the full TikTok audit flow are implemented. Do not broaden this union
      // from provider documentation alone.
      privacyLevel: 'SELF_ONLY';
    }
  | {
      publishMode: 'INBOX_DRAFT';
    };

export type YoutubePlatformSettings =
  | {
      // Legacy installed clients did not collect YouTube's required uploader
      // certification or title. Preserve their existing private behavior;
      // only the explicit request parser may create the full shape below.
      visibility: 'private';
    }
  | {
      title: string;
      visibility: YoutubeVisibility;
      madeForKids: boolean;
      containsSyntheticMedia: boolean;
      communityGuidelinesCertified: true;
    };

export type PlatformSettings = Partial<{
  TIKTOK: TikTokPlatformSettings;
  YOUTUBE_SHORTS: YoutubePlatformSettings;
  INSTAGRAM_REELS: {
    shareToFeed: boolean;
  };
  FACEBOOK_REELS: {
    // FACEBOOK_REELS is the legacy internal key. The provider target is a
    // Facebook Page Video; PAGE_DRAFT means an unpublished Page draft.
    publishMode: 'PUBLISH' | 'PAGE_DRAFT';
  };
}>;

export type ReadPlatformSettingsResult =
  | { ok: true; value: PlatformSettings }
  | { ok: false };

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, expectedKeys: string[]) => {
  const keys = Object.keys(value);
  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key))
  );
};

export const createDefaultPlatformSettings = (platforms: Platform[]): PlatformSettings => {
  let settings: PlatformSettings = {};

  for (const platform of platforms) {
    if (platform === 'TIKTOK') {
      settings = {
        ...settings,
        TIKTOK: {
          publishMode: 'DIRECT_POST',
          privacyLevel: 'SELF_ONLY'
        }
      };
    } else if (platform === 'YOUTUBE_SHORTS') {
      settings = {
        ...settings,
        YOUTUBE_SHORTS: { visibility: 'private' }
      };
    } else if (platform === 'INSTAGRAM_REELS') {
      settings = {
        ...settings,
        INSTAGRAM_REELS: { shareToFeed: true }
      };
    } else if (platform === 'FACEBOOK_REELS') {
      settings = {
        ...settings,
        FACEBOOK_REELS: { publishMode: 'PUBLISH' }
      };
    }
  }

  return settings;
};

const readTikTokSettings = (
  value: unknown,
  allowLegacyDirectPost: boolean
): TikTokPlatformSettings | undefined => {
  if (!isRecord(value) || typeof value.publishMode !== 'string') {
    return undefined;
  }

  if (value.publishMode === 'INBOX_DRAFT' && hasExactKeys(value, ['publishMode'])) {
    return { publishMode: 'INBOX_DRAFT' };
  }

  if (
    allowLegacyDirectPost &&
    value.publishMode === 'DIRECT_POST' &&
    value.privacyLevel === 'SELF_ONLY' &&
    hasExactKeys(value, ['publishMode', 'privacyLevel'])
  ) {
    return {
      publishMode: 'DIRECT_POST',
      privacyLevel: 'SELF_ONLY'
    };
  }

  return undefined;
};

const readYoutubeSettings = (
  value: unknown,
  allowLegacyShape: boolean
): PlatformSettings['YOUTUBE_SHORTS'] | undefined => {
  if (!isRecord(value)) {
    return undefined;
  }

  if (
    allowLegacyShape &&
    value.visibility === 'private' &&
    hasExactKeys(value, ['visibility'])
  ) {
    return { visibility: 'private' };
  }

  if (
    !hasExactKeys(value, [
      'title',
      'visibility',
      'madeForKids',
      'containsSyntheticMedia',
      'communityGuidelinesCertified'
    ]) ||
    typeof value.title !== 'string' ||
    value.title.trim().length === 0 ||
    [...value.title.trim()].length > 100 ||
    /[<>]/.test(value.title) ||
    (value.visibility !== 'private' &&
      value.visibility !== 'unlisted' &&
      value.visibility !== 'public') ||
    typeof value.madeForKids !== 'boolean' ||
    typeof value.containsSyntheticMedia !== 'boolean' ||
    value.communityGuidelinesCertified !== true
  ) {
    return undefined;
  }

  return {
    title: value.title.trim(),
    visibility: value.visibility,
    madeForKids: value.madeForKids,
    containsSyntheticMedia: value.containsSyntheticMedia,
    communityGuidelinesCertified: true
  };
};

const readInstagramSettings = (
  value: unknown
): PlatformSettings['INSTAGRAM_REELS'] | undefined =>
  isRecord(value) &&
  hasExactKeys(value, ['shareToFeed']) &&
  typeof value.shareToFeed === 'boolean'
    ? { shareToFeed: value.shareToFeed }
    : undefined;

const readFacebookSettings = (
  value: unknown
): PlatformSettings['FACEBOOK_REELS'] | undefined =>
  isRecord(value) &&
  hasExactKeys(value, ['publishMode']) &&
  (value.publishMode === 'PUBLISH' || value.publishMode === 'PAGE_DRAFT')
    ? { publishMode: value.publishMode }
    : undefined;

/**
 * Reads one immutable settings snapshot for the selected destinations.
 * Omission is reserved for installed legacy clients and maps to the exact
 * controlled defaults used before this field existed. Once the object is
 * present, every selected platform must be explicit so malformed new-client
 * intent cannot silently fall back to a different outcome.
 */
const readPlatformSettingsSnapshot = (
  value: unknown,
  platforms: Platform[],
  allowLegacyShapes: boolean
): ReadPlatformSettingsResult => {
  if (value === undefined) {
    return { ok: true, value: createDefaultPlatformSettings(platforms) };
  }

  if (
    !isRecord(value) ||
    new Set(platforms).size !== platforms.length ||
    !hasExactKeys(value, platforms)
  ) {
    return { ok: false };
  }

  let settings: PlatformSettings = {};

  for (const platform of platforms) {
    if (platform === 'TIKTOK') {
      const parsed = readTikTokSettings(value.TIKTOK, allowLegacyShapes);
      if (!parsed) {
        return { ok: false };
      }
      settings = { ...settings, TIKTOK: parsed };
    } else if (platform === 'YOUTUBE_SHORTS') {
      const parsed = readYoutubeSettings(
        value.YOUTUBE_SHORTS,
        allowLegacyShapes
      );
      if (!parsed) {
        return { ok: false };
      }
      settings = { ...settings, YOUTUBE_SHORTS: parsed };
    } else if (platform === 'INSTAGRAM_REELS') {
      const parsed = readInstagramSettings(value.INSTAGRAM_REELS);
      if (!parsed) {
        return { ok: false };
      }
      settings = { ...settings, INSTAGRAM_REELS: parsed };
    } else if (platform === 'FACEBOOK_REELS') {
      const parsed = readFacebookSettings(value.FACEBOOK_REELS);
      if (!parsed) {
        return { ok: false };
      }
      settings = { ...settings, FACEBOOK_REELS: parsed };
    }
  }

  return { ok: true, value: settings };
};

export const readPlatformSettings = (
  value: unknown,
  platforms: Platform[]
): ReadPlatformSettingsResult =>
  readPlatformSettingsSnapshot(value, platforms, false);

export const normalizePersistedPlatformSettings = (
  value: unknown,
  platforms: Platform[]
): PlatformSettings => {
  const parsed = readPlatformSettingsSnapshot(
    value === null ? undefined : value,
    platforms,
    true
  );

  if (!parsed.ok) {
    throw new Error('Persisted platform settings are invalid');
  }

  return parsed.value;
};

export const arePlatformSettingsEqual = (
  left: PlatformSettings | undefined,
  right: PlatformSettings | undefined,
  platforms: Platform[]
) => {
  const normalizedLeft = normalizePersistedPlatformSettings(left, platforms);
  const normalizedRight = normalizePersistedPlatformSettings(right, platforms);

  return platforms.every((platform) => {
    if (platform === 'TIKTOK') {
      const leftSettings = normalizedLeft.TIKTOK;
      const rightSettings = normalizedRight.TIKTOK;
      return (
        leftSettings?.publishMode === rightSettings?.publishMode &&
        (leftSettings?.publishMode !== 'DIRECT_POST' ||
          (rightSettings?.publishMode === 'DIRECT_POST' &&
            leftSettings.privacyLevel === rightSettings.privacyLevel))
      );
    }

    if (platform === 'YOUTUBE_SHORTS') {
      const leftSettings = normalizedLeft.YOUTUBE_SHORTS;
      const rightSettings = normalizedRight.YOUTUBE_SHORTS;

      if (leftSettings?.visibility !== rightSettings?.visibility) {
        return false;
      }

      const leftIsExplicit = leftSettings && 'title' in leftSettings;
      const rightIsExplicit = rightSettings && 'title' in rightSettings;
      if (!leftIsExplicit || !rightIsExplicit) {
        return leftIsExplicit === rightIsExplicit;
      }

      return (
        leftSettings.title === rightSettings.title &&
        leftSettings.madeForKids === rightSettings.madeForKids &&
        leftSettings.containsSyntheticMedia === rightSettings.containsSyntheticMedia &&
        leftSettings.communityGuidelinesCertified ===
          rightSettings.communityGuidelinesCertified
      );
    }

    if (platform === 'INSTAGRAM_REELS') {
      return (
        normalizedLeft.INSTAGRAM_REELS?.shareToFeed ===
        normalizedRight.INSTAGRAM_REELS?.shareToFeed
      );
    }

    return (
      normalizedLeft.FACEBOOK_REELS?.publishMode ===
      normalizedRight.FACEBOOK_REELS?.publishMode
    );
  });
};
