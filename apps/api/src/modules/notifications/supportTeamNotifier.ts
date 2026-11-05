import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import type { AppLanguage } from '../shared/appLanguage.js';
import { sendLocalizedPush } from './localizedPush.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

const messageForLanguage = (language: AppLanguage) => language === 'en'
  ? { title: 'New message for the PostDee team', body: 'Open the admin console to read and reply.' }
  : { title: 'มีข้อความใหม่ถึงทีมงาน PostDee', body: 'เปิดเว็บแอดมินเพื่ออ่านและตอบกลับ' };

/** Notify allowlisted administrators on their own registered devices. */
export const createSupportTeamNotifier = ({
  deviceTokenStore,
  adminUserIds,
  pushSender = createMockPushSender()
}: {
  deviceTokenStore: DeviceTokenStore;
  adminUserIds: string[];
  pushSender?: PushSender;
}) => async () => {
  await Promise.allSettled([...new Set(adminUserIds)].map(async userId => {
    // A customer message or identity must never appear on an administrator's lock screen.
    await sendLocalizedPush({
      userId,
      deviceTokenStore,
      pushSender,
      messageForLanguage,
      data: { userId, type: 'support_new_message' }
    });
  }));
};
