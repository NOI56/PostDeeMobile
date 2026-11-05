import { describe, expect, it, vi } from 'vitest';
import { createInMemoryDeviceTokenStore, type DeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createPublishNotifier } from './publishNotifier.js';
import { createSupportReplyNotifier } from './supportReplyNotifier.js';
import { createSupportTeamNotifier } from './supportTeamNotifier.js';
import type { PushSender } from './pushSender.js';

const cases = [
  {
    name: 'publish',
    notify: (deviceTokenStore: DeviceTokenStore, pushSender: PushSender) =>
      createPublishNotifier({ deviceTokenStore, pushSender }).notifyPublishResult({ userId: 'member', postId: 'post', outcome: 'PUBLISHED' }),
    thai: { title: 'ส่งคลิปสำเร็จ', body: 'ระบบส่งคลิปไปยังช่องทางที่เลือกเรียบร้อยแล้ว แตะเพื่อดูผลลัพธ์' },
    english: { title: 'Video delivered', body: 'Your video was sent to the selected channels. Tap to view the result.' },
    data: { userId: 'member', postId: 'post', type: 'publish_result' }
  },
  {
    name: 'support reply',
    notify: (deviceTokenStore: DeviceTokenStore, pushSender: PushSender) =>
      createSupportReplyNotifier({ deviceTokenStore, pushSender })('member'),
    thai: { title: 'ทีมงาน PostDee ตอบกลับแล้ว', body: 'แตะเพื่ออ่านคำตอบในแชทกับทีมงาน' },
    english: { title: 'The PostDee team replied', body: 'Tap to read the reply in your support chat.' },
    data: { userId: 'member', type: 'support_reply' }
  },
  {
    name: 'support team',
    notify: (deviceTokenStore: DeviceTokenStore, pushSender: PushSender) =>
      createSupportTeamNotifier({ deviceTokenStore, pushSender, adminUserIds: ['member', 'member'] })(),
    thai: { title: 'มีข้อความใหม่ถึงทีมงาน PostDee', body: 'เปิดเว็บแอดมินเพื่ออ่านและตอบกลับ' },
    english: { title: 'New message for the PostDee team', body: 'Open the admin console to read and reply.' },
    data: { userId: 'member', type: 'support_new_message' }
  }
];

describe.each(cases)('$name push languages', ({ notify, thai, english, data }) => {
  const devices = async () => {
    const store = createInMemoryDeviceTokenStore();
    await store.register({ userId: 'member', token: 'thai', language: 'th' });
    await store.register({ userId: 'member', token: 'legacy' });
    await store.register({ userId: 'member', token: 'english', language: 'en' });
    await store.register({ userId: 'other', token: 'private', language: 'en' });
    return store;
  };

  it('sends one message per language and treats a legacy null as Thai', async () => {
    const store = await devices();
    const send = vi.fn(async () => undefined);
    await notify(store, { send });
    expect(send).toHaveBeenCalledTimes(2);
    expect(send).toHaveBeenCalledWith({ tokens: ['thai', 'legacy'], ...thai, data });
    expect(send).toHaveBeenCalledWith({ tokens: ['english'], ...english, data });
  });

  it('sends the other language even when one group fails', async () => {
    const store = await devices();
    const send = vi.fn(async ({ tokens }: { tokens: string[] }) => {
      if (tokens.includes('thai')) throw new Error('provider unavailable');
    });
    await expect(notify(store, { send })).resolves.toBeUndefined();
    expect(send).toHaveBeenCalledTimes(2);
    expect(send).toHaveBeenCalledWith({ tokens: ['english'], ...english, data });
  });

  it('cleans dead tokens in every language group without touching another owner', async () => {
    const store = await devices();
    const send = vi.fn(async ({ tokens }: { tokens: string[] }) => ({ invalidTokens: [tokens[0], 'private'] }));
    await notify(store, { send });
    expect((await store.listForUser('member')).map(device => device.token)).toEqual(['legacy']);
    expect((await store.listForUser('other')).map(device => device.token)).toEqual(['private']);
  });

  it('continues other dead-token cleanup when one unregister fails', async () => {
    const store = await devices();
    const unregister = store.unregister;
    store.unregister = async input => {
      if (input.token === 'thai') throw new Error('delete unavailable');
      await unregister(input);
    };
    await expect(notify(store, { send: async ({ tokens }) => ({ invalidTokens: tokens }) }))
      .resolves.toBeUndefined();
    expect((await store.listForUser('member')).map(device => device.token)).toEqual(['thai']);
  });

  it('remains best-effort when token lookup fails', async () => {
    const store = await devices();
    store.listForUser = async () => { throw new Error('database unavailable'); };
    const send = vi.fn(async () => undefined);
    await expect(notify(store, { send })).resolves.toBeUndefined();
    expect(send).not.toHaveBeenCalled();
  });
});

describe('English publish templates', () => {
  it.each([
    ['PUBLISHED', 'Video delivered', 'Your video was sent to the selected channels. Tap to view the result.'],
    ['PARTIAL_PUBLISHED', 'Video partially delivered', 'Your video could not be sent to some channels. Tap for details.'],
    ['FAILED', 'Video delivery failed', 'Your video could not be sent to the selected channels. Tap for details.']
  ] as const)('matches the in-app %s template exactly', async (outcome, title, body) => {
    const store = createInMemoryDeviceTokenStore();
    await store.register({ userId: 'member', token: 'english', language: 'en' });
    const send = vi.fn(async () => undefined);
    await createPublishNotifier({ deviceTokenStore: store, pushSender: { send } })
      .notifyPublishResult({ userId: 'member', postId: 'post', outcome });
    expect(send).toHaveBeenCalledWith({ tokens: ['english'], title, body,
      data: { userId: 'member', postId: 'post', type: 'publish_result' } });
  });
});
