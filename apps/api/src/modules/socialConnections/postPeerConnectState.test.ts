import { describe, expect, it } from 'vitest';

import { createPostPeerConnectStateManager } from './postPeerConnectState.js';

describe('createPostPeerConnectStateManager', () => {
  it('signs and verifies user/platform state', () => {
    const manager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => Date.parse('2026-06-26T09:20:00.000Z'),
      randomBytes: () => Buffer.from('nonce-1234567890')
    });

    const signed = manager.create({
      userId: 'seller-1',
      platform: 'TIKTOK',
      ttlSeconds: 300
    });

    expect(manager.verify(signed.token)).toMatchObject({
      userId: 'seller-1',
      platform: 'TIKTOK',
      expiresAt: '2026-06-26T09:25:00.000Z'
    });
    expect(signed.expiresAt).toBe('2026-06-26T09:25:00.000Z');
  });

  it('rejects tampered and expired state tokens', () => {
    const manager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => Date.parse('2026-06-26T09:20:00.000Z'),
      randomBytes: () => Buffer.from('nonce-1234567890')
    });
    const signed = manager.create({
      userId: 'seller-1',
      platform: 'TIKTOK',
      ttlSeconds: 1
    });
    const expiredManager = createPostPeerConnectStateManager({
      secret: 'state-secret',
      nowMs: () => Date.parse('2026-06-26T09:20:02.000Z')
    });

    expect(() => manager.verify(`${signed.token}x`)).toThrow(
      /Invalid PostPeer connect state/
    );
    expect(() => manager.verify(`${signed.token}.extra`)).toThrow(
      /Invalid PostPeer connect state/
    );
    expect(() => expiredManager.verify(signed.token)).toThrow(
      /PostPeer connect state expired/
    );
  });
});
