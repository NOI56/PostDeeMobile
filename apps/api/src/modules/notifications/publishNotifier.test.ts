import { describe, expect, it, vi } from 'vitest';

import { createInMemoryDeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createPublishNotifier } from './publishNotifier.js';

describe('publish notifier', () => {
  it('sends a Thai push to every registered device on success', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'u1', token: 't1' });
    await deviceTokenStore.register({ userId: 'u1', token: 't2' });
    const send = vi.fn(async () => undefined);
    const notifier = createPublishNotifier({
      deviceTokenStore,
      pushSender: { send }
    });

    await notifier.notifyPublishResult({
      userId: 'u1',
      postId: 'p1',
      outcome: 'PUBLISHED'
    });

    expect(send).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledWith({
      tokens: ['t1', 't2'],
      title: 'โพสต์สำเร็จ',
      body: 'คลิปของคุณถูกโพสต์เรียบร้อยแล้ว',
      data: { postId: 'p1', type: 'publish_result' }
    });
  });

  it('uses partial-success copy for PARTIAL_PUBLISHED', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'u1', token: 't1' });
    const send = vi.fn(async () => undefined);
    const notifier = createPublishNotifier({
      deviceTokenStore,
      pushSender: { send }
    });

    await notifier.notifyPublishResult({
      userId: 'u1',
      postId: 'p1',
      outcome: 'PARTIAL_PUBLISHED'
    });

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'โพสต์บางส่วนสำเร็จ' })
    );
  });

  it('does not send when the user has no registered devices', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    const send = vi.fn(async () => undefined);
    const notifier = createPublishNotifier({
      deviceTokenStore,
      pushSender: { send }
    });

    await notifier.notifyPublishResult({
      userId: 'u1',
      postId: 'p1',
      outcome: 'FAILED'
    });

    expect(send).not.toHaveBeenCalled();
  });

  it('does not send when there is no user id', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'u1', token: 't1' });
    const send = vi.fn(async () => undefined);
    const notifier = createPublishNotifier({
      deviceTokenStore,
      pushSender: { send }
    });

    await notifier.notifyPublishResult({ postId: 'p1', outcome: 'PUBLISHED' });

    expect(send).not.toHaveBeenCalled();
  });
});
