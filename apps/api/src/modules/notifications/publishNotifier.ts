import type { DeviceTokenStore } from '../devices/deviceTokenStore.js';
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

// User-facing push copy is Thai (the app's primary language).
const messageForOutcome = (
  outcome: PublishOutcome
): { title: string; body: string } => {
  switch (outcome) {
    case 'PUBLISHED':
      return { title: 'โพสต์สำเร็จ', body: 'คลิปของคุณถูกโพสต์เรียบร้อยแล้ว' };
    case 'PARTIAL_PUBLISHED':
      return {
        title: 'โพสต์บางส่วนสำเร็จ',
        body: 'บางแพลตฟอร์มโพสต์ไม่สำเร็จ แตะเพื่อดูรายละเอียด'
      };
    case 'FAILED':
      return {
        title: 'โพสต์ไม่สำเร็จ',
        body: 'โพสต์คลิปไม่สำเร็จ แตะเพื่อลองอีกครั้ง'
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

    const tokens = (await deviceTokenStore.listForUser(userId)).map(
      (device) => device.token
    );

    if (tokens.length === 0) {
      return;
    }

    const { title, body } = messageForOutcome(outcome);
    await pushSender.send({
      tokens,
      title,
      body,
      data: { postId, type: 'publish_result' }
    });
  }
});
