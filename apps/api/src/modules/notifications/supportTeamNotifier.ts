import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

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
    const tokens = (await deviceTokenStore.listForUser(userId)).map(device => device.token);
    if (!tokens.length) return;
    // A customer message or identity must never appear on an administrator's lock screen.
    const result = await pushSender.send({
      tokens,
      title: 'มีข้อความใหม่ถึงทีมงาน PostDee',
      body: 'เปิดเว็บแอดมินเพื่ออ่านและตอบกลับ',
      data: { userId, type: 'support_new_message' }
    });
    for (const token of result?.invalidTokens ?? []) {
      await deviceTokenStore.unregister({ userId, token });
    }
  }));
};
