import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { AppLanguage } from '../shared/appLanguage.js';
import { sendLocalizedPush } from './localizedPush.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

export type PublishOutcome = 'PUBLISHED' | 'PARTIAL_PUBLISHED' | 'FAILED';

export type PublishNotifier = {
  notifyPublishResult: (input: {
    userId?: string;
    postId: string;
    outcome: PublishOutcome;
  }) => Promise<void>;
};

export const createNoopPublishNotifier = (): PublishNotifier => ({
  notifyPublishResult: async () => undefined
});

const messageForOutcome = (
  outcome: PublishOutcome,
  language: AppLanguage
): { title: string; body: string } => {
  if (language === 'en') {
    switch (outcome) {
      case 'PUBLISHED':
        return {
          title: 'Video delivered',
          body: 'Your video was sent to the selected channels. Tap to view the result.'
        };
      case 'PARTIAL_PUBLISHED':
        return {
          title: 'Video partially delivered',
          body: 'Your video could not be sent to some channels. Tap for details.'
        };
      case 'FAILED':
        return {
          title: 'Video delivery failed',
          body: 'Your video could not be sent to the selected channels. Tap for details.'
        };
    }
  }
  switch (outcome) {
    case 'PUBLISHED':
      return {
        title: 'ส่งคลิปสำเร็จ',
        body: 'ระบบส่งคลิปไปยังช่องทางที่เลือกเรียบร้อยแล้ว แตะเพื่อดูผลลัพธ์'
      };
    case 'PARTIAL_PUBLISHED':
      return {
        title: 'ส่งคลิปสำเร็จบางช่องทาง',
        body: 'บางช่องทางส่งคลิปไม่สำเร็จ แตะเพื่อดูรายละเอียด'
      };
    case 'FAILED':
      return {
        title: 'ส่งคลิปไม่สำเร็จ',
        body: 'ส่งคลิปไปยังช่องทางที่เลือกไม่สำเร็จ แตะเพื่อดูรายละเอียด'
      };
  }
};

/**
 * Sends a push notification to all of a user's registered devices when a publish
 * job finishes. Best-effort: a missing user id, no registered devices, or a
 * sender failure must never affect publishing.
 */
export const createPublishNotifier = ({
  deviceTokenStore,
  pushSender = createMockPushSender()
}: {
  deviceTokenStore: DeviceTokenStore;
  pushSender?: PushSender;
}): PublishNotifier => ({
  notifyPublishResult: async ({ userId, postId, outcome }) => {
    if (!userId) {
      return;
    }

    await sendLocalizedPush({
      userId,
      deviceTokenStore,
      pushSender,
      messageForLanguage: language => messageForOutcome(outcome, language),
      data: { postId, userId, type: 'publish_result' }
    });
  }
});
