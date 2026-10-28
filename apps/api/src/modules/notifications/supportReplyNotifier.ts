import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
import { type PushSender, createMockPushSender } from './pushSender.js';

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
  const tokens = (await deviceTokenStore.listForUser(userId)).map((device) => device.token);
  if (tokens.length === 0) return;
  const result = await pushSender.send({
    tokens,
    title: 'ทีมงาน PostDee ตอบกลับแล้ว',
    body: 'แตะเพื่ออ่านคำตอบในแชทกับทีมงาน',
    data: { userId, type: 'support_reply' }
  });
  // Dead tokens (uninstalled apps) are removed for this owner only.
  for (const token of result?.invalidTokens ?? []) {
    await deviceTokenStore.unregister({ userId, token });
  }
};
