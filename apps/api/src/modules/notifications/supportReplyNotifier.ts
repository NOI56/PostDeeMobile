import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { AppLanguage } from '../shared/appLanguage.js';
import { sendLocalizedPush } from './localizedPush.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

const messageForLanguage = (language: AppLanguage) => language === 'en'
  ? { title: 'The PostDee team replied', body: 'Tap to read the reply in your support chat.' }
  : { title: 'ทีมงาน PostDee ตอบกลับแล้ว', body: 'แตะเพื่ออ่านคำตอบในแชทกับทีมงาน' };

/**
 * Pushes "the team replied" to a member's registered devices. The body stays
 * generic so a support conversation never shows on a lock screen. `userId` is
 * included because Mobile ignores pushes addressed to another signed-in owner.
 */
export const createSupportReplyNotifier = ({
  deviceTokenStore,
  pushSender = createMockPushSender()
}: {
  deviceTokenStore: DeviceTokenStore;
  pushSender?: PushSender;
}) => async (userId: string) => {
  await sendLocalizedPush({
    userId,
    deviceTokenStore,
    pushSender,
    messageForLanguage,
    data: { userId, type: 'support_reply' }
  });
};
