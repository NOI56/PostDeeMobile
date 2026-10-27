import { describe, expect, it, vi } from 'vitest';

import { createInMemoryDeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createPublishNotifier } from './publishNotifier.js';

describe('publish notifier', () => {
  it('labels the exact recipient and sends only that owner device tokens', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'owner-a', token: 'token-a' });
    await deviceTokenStore.register({ userId: 'owner-b', token: 'token-b' });
    const send = vi.fn(async () => undefined);
    await createPublishNotifier({ deviceTokenStore, pushSender: { send } })
      .notifyPublishResult({ userId: 'owner-a', postId: 'private-a', outcome: 'PUBLISHED' });
    expect(send).toHaveBeenCalledWith(expect.objectContaining({
      tokens: ['token-a'], data: { postId: 'private-a', type: 'publish_result', userId: 'owner-a' }
    }));
  });

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
      title: 'ส่งคลิปสำเร็จ',
      body: 'ระบบส่งคลิปไปยังช่องทางที่เลือกเรียบร้อยแล้ว แตะเพื่อดูผลลัพธ์',
      data: { postId: 'p1', userId: 'u1', type: 'publish_result' }
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
      expect.objectContaining({ title: 'ส่งคลิปสำเร็จบางช่องทาง' })
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

  it('unregisters tokens the push provider reports as no longer valid', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'u1', token: 'stale' });
    await deviceTokenStore.register({ userId: 'u1', token: 'live' });
    await deviceTokenStore.register({ userId: 'u2', token: 'other' });
    const notifier = createPublishNotifier({
      deviceTokenStore,
      pushSender: { send: async () => ({ invalidTokens: ['stale'] }) }
    });

    await notifier.notifyPublishResult({ userId: 'u1', postId: 'p1', outcome: 'PUBLISHED' });

    expect((await deviceTokenStore.listForUser('u1')).map((device) => device.token))
      .toEqual(['live']);
    expect(await deviceTokenStore.listForUser('u2')).toHaveLength(1);
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
