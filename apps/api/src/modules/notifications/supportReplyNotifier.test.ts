import { describe, expect, it, vi } from 'vitest';
import { createInMemoryDeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createSupportReplyNotifier } from './supportReplyNotifier.js';

describe('support reply notifier', () => {
  it('pushes a generic reply notice to the member’s devices and drops dead tokens', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'member', token: 'token-live', platform: 'ANDROID' });
    await deviceTokenStore.register({ userId: 'member', token: 'token-dead', platform: 'IOS' });
    await deviceTokenStore.register({ userId: 'other', token: 'token-other', platform: 'ANDROID' });
    const send = vi.fn(async () => ({ invalidTokens: ['token-dead'] }));
    await createSupportReplyNotifier({ deviceTokenStore, pushSender: { send } })('member');
    expect(send).toHaveBeenCalledWith({ tokens: expect.arrayContaining(['token-live', 'token-dead']),
      title: 'ทีมงาน PostDee ตอบกลับแล้ว', body: 'แตะเพื่ออ่านคำตอบในแชทกับทีมงาน',
      data: { userId: 'member', type: 'support_reply' } });
    expect(JSON.stringify(send.mock.calls)).not.toContain('token-other');
    expect((await deviceTokenStore.listForUser('member')).map(d => d.token)).toEqual(['token-live']);
  });
  it('skips members without a registered device', async () => {
    const send = vi.fn(async () => undefined);
    await createSupportReplyNotifier({ deviceTokenStore: createInMemoryDeviceTokenStore(), pushSender: { send } })('member');
    expect(send).not.toHaveBeenCalled();
  });
});
