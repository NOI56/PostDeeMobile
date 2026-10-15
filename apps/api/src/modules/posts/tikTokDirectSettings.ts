import { createHash } from 'node:crypto';

import { TikTokPublishingError, type TikTokCreatorInfo } from '../socialConnections/postPeerTikTokClient.js';
import type { TikTokDirectPostSettings, TikTokPlatformSettings } from './platformSettings.js';
import { normalizePersistedPlatformTargets, type PlatformTarget } from './platformTargets.js';

export type { TikTokDirectPostSettings } from './platformSettings.js';
export const validateTikTokDirectCaption = (caption: string | undefined): void => {
  // TikTok's title limit counts UTF-16 units, matching JavaScript string length.
  if ((caption?.length ?? 0) > 2200) throw new TikTokPublishingError(
    'TIKTOK_CAPTION_TOO_LONG', 400,
    'TikTok captions must not exceed 2200 UTF-16 characters. Shorten the caption before posting.'
  );
};
export const buildTikTokConnectionRevision = ({ userId, target }: {
  userId: string;
  target: PlatformTarget;
}): string => {
  const normalized = normalizePersistedPlatformTargets({ TIKTOK: target }, ['TIKTOK'])?.TIKTOK;
  if (!userId.trim() || !normalized) throw new Error('TikTok connection is required');
  return createHash('sha256').update(JSON.stringify([
    userId.trim(), normalized.accountId, normalized.connectedAt, normalized.externalAccountId ?? null
  ])).digest('hex');
};
export const isExplicitTikTokDirectSettings = (
  settings: TikTokPlatformSettings | undefined
): settings is TikTokDirectPostSettings =>
  settings?.publishMode === 'DIRECT_POST' && 'musicUsageConfirmed' in settings;

export const validateTikTokDirectSettings = (
  info: TikTokCreatorInfo,
  settings: TikTokDirectPostSettings
): void => {
  if (
    !info.privacyLevelOptions.includes(settings.privacyLevel) ||
    (info.commentDisabled && !settings.disableComment) ||
    (info.duetDisabled && !settings.disableDuet) ||
    (info.stitchDisabled && !settings.disableStitch) ||
    !Number.isFinite(settings.videoDurationSeconds) || settings.videoDurationSeconds <= 0 ||
    settings.videoDurationSeconds > Math.min(info.maxVideoPostDurationSec, 600) ||
    settings.musicUsageConfirmed !== true ||
    (settings.brandContentToggle &&
      (!settings.brandedContentPolicyConfirmed || settings.privacyLevel === 'SELF_ONLY'))
  ) throw new TikTokPublishingError(
    'TIKTOK_DIRECT_SETTINGS_INVALID', 409,
    'TikTok publishing options changed or are unavailable. Review the post again.'
  );
};
