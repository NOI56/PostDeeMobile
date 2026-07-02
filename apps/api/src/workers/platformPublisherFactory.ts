import type { ServerConfig } from '../config/env.js';
import {
  isPublishableSocialPlatform,
  type SocialConnectionStore
} from '../modules/socialConnections/socialConnectionStore.js';
import type { VideoStorage } from '../modules/storage/videoStorage.js';
import { createPostPeerPublisher } from './postPeerPublisher.js';
import { type PlatformPublisher, createMockPlatformPublisher } from './publishWorker.js';

const createSignedVideoUrlResolver =
  (videoStorage: VideoStorage) => async (videoS3Key: string) => {
    const access = await videoStorage.createDownloadAccess(videoS3Key);

    if (access.accessType !== 'signed-url' || !access.downloadUrl) {
      throw new Error('Signed video download access is required for PostPeer publishing');
    }

    return access.downloadUrl;
  };

/**
 * Selects the social publisher from config. Default is the mock publisher;
 * set SOCIAL_PUBLISHER=postpeer with a POSTPEER_API_KEY to publish for real.
 */
export const createPlatformPublisherFromConfig = ({
  config,
  videoStorage,
  socialConnectionStore
}: {
  config: ServerConfig;
  videoStorage?: VideoStorage;
  socialConnectionStore?: SocialConnectionStore;
}): PlatformPublisher => {
  if (config.socialPublisher === 'postpeer') {
    if (!config.postPeerApiKey) {
      throw new Error('POSTPEER_API_KEY is required when SOCIAL_PUBLISHER is postpeer');
    }

    if (!videoStorage) {
      throw new Error('VideoStorage is required when SOCIAL_PUBLISHER is postpeer');
    }

    return createPostPeerPublisher({
      apiKey: config.postPeerApiKey,
      baseUrl: config.postPeerApiBaseUrl,
      accountIds: {
        TIKTOK: config.postPeerTiktokAccountId,
        YOUTUBE_SHORTS: config.postPeerYoutubeAccountId,
        INSTAGRAM_REELS: config.postPeerInstagramAccountId,
        FACEBOOK_REELS: config.postPeerFacebookAccountId
      },
      resolveAccountId: socialConnectionStore
        ? async ({ userId, platform }) =>
            isPublishableSocialPlatform(platform)
              ? socialConnectionStore.getAccountId({ userId, platform })
              : undefined
        : undefined,
      resolveVideoUrl: createSignedVideoUrlResolver(videoStorage)
    });
  }

  return createMockPlatformPublisher();
};
