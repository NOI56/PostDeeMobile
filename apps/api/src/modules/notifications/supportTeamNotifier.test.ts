import { describe, expect, it, vi } from 'vitest';
import { createInMemoryDeviceTokenStore } from '../devices/deviceTokenStore.js';
import { createSupportTeamNotifier } from './supportTeamNotifier.js';

describe('support team notifier', () => {
  it('notifies deduplicated allowed administrators with their recipient UID and no customer details', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'owner', token: 'owner-live', platform: 'ANDROID' });
    await deviceTokenStore.register({ userId: 'owner', token: 'owner-dead', platform: 'IOS' });
    await deviceTokenStore.register({ userId: 'viewer', token: 'viewer-live', platform: 'ANDROID' });
    await deviceTokenStore.register({ userId: 'member', token: 'member-private', platform: 'ANDROID' });
    const send = vi.fn(async () => ({ invalidTokens: ['owner-dead', 'member-private'] }));
    await createSupportTeamNotifier({ deviceTokenStore, adminUserIds: ['owner', 'viewer', 'owner'], pushSender: { send } })();
    expect(send).toHaveBeenCalledTimes(2);
    expect(send).toHaveBeenCalledWith({ tokens: ['owner-live', 'owner-dead'], title: 'มีข้อความใหม่ถึงทีมงาน PostDee',
      body: 'เปิดเว็บแอดมินเพื่ออ่านและตอบกลับ', data: { userId: 'owner', type: 'support_new_message' } });
    expect(send).toHaveBeenCalledWith(expect.objectContaining({ tokens: ['viewer-live'], data: { userId: 'viewer', type: 'support_new_message' } }));
    expect(JSON.stringify(send.mock.calls)).not.toContain('member-private');
    expect((await deviceTokenStore.listForUser('owner')).map(device => device.token)).toEqual(['owner-live']);
    expect((await deviceTokenStore.listForUser('member')).map(device => device.token)).toEqual(['member-private']);
  });
  it('skips administrators without registered devices and continues after one recipient fails', async () => {
    const deviceTokenStore = createInMemoryDeviceTokenStore();
    await deviceTokenStore.register({ userId: 'owner', token: 'owner-token' });
    await deviceTokenStore.register({ userId: 'viewer', token: 'viewer-token' });
    const send = vi.fn(async ({ tokens }: { tokens: string[] }) => {
      if (tokens.includes('owner-token')) throw new Error('Push unavailable');
    });
    await expect(createSupportTeamNotifier({ deviceTokenStore, adminUserIds: ['owner', 'viewer', 'no-device'], pushSender: { send } })()).resolves.toBeUndefined();
    expect(send).toHaveBeenCalledTimes(2);
    expect(send).toHaveBeenCalledWith(expect.objectContaining({ tokens: ['viewer-token'] }));
  });
});
