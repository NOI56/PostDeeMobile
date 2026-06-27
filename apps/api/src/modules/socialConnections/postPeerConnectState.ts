import { createHmac, randomBytes as defaultRandomBytes, timingSafeEqual } from 'node:crypto';

import type { SocialConnectionPlatform } from './socialConnectionStore.js';
import { isSocialConnectionPlatform } from './socialConnectionStore.js';

type ConnectStatePayload = {
  userId: string;
  platform: SocialConnectionPlatform;
  expiresAtMs: number;
  nonce: string;
};

export type VerifiedPostPeerConnectState = {
  userId: string;
  platform: SocialConnectionPlatform;
  expiresAt: string;
};

const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');

const decode = (value: string) =>
  JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as unknown;

const sign = (secret: string, payload: string) =>
  createHmac('sha256', secret).update(payload).digest('base64url');

const signaturesMatch = (left: string, right: string) => {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
};

export const createPostPeerConnectStateManager = ({
  secret,
  nowMs = () => Date.now(),
  randomBytes = defaultRandomBytes
}: {
  secret: string;
  nowMs?: () => number;
  randomBytes?: (size: number) => Buffer;
}) => ({
  create: ({
    userId,
    platform,
    ttlSeconds = 600
  }: {
    userId: string;
    platform: SocialConnectionPlatform;
    ttlSeconds?: number;
  }) => {
    const expiresAtMs = nowMs() + ttlSeconds * 1000;
    const payload = encode({
      userId,
      platform,
      expiresAtMs,
      nonce: randomBytes(16).toString('base64url')
    } satisfies ConnectStatePayload);
    const signature = sign(secret, payload);

    return {
      token: `${payload}.${signature}`,
      expiresAt: new Date(expiresAtMs).toISOString()
    };
  },
  verify: (token: string): VerifiedPostPeerConnectState => {
    const parts = token.split('.');
    const [payload, signature] = parts;

    if (
      parts.length !== 2 ||
      !payload ||
      !signature ||
      !signaturesMatch(sign(secret, payload), signature)
    ) {
      throw new Error('Invalid PostPeer connect state');
    }

    const decoded = decode(payload) as Partial<ConnectStatePayload>;

    if (
      typeof decoded.userId !== 'string' ||
      !isSocialConnectionPlatform(decoded.platform) ||
      typeof decoded.expiresAtMs !== 'number'
    ) {
      throw new Error('Invalid PostPeer connect state');
    }

    if (decoded.expiresAtMs <= nowMs()) {
      throw new Error('PostPeer connect state expired');
    }

    return {
      userId: decoded.userId,
      platform: decoded.platform,
      expiresAt: new Date(decoded.expiresAtMs).toISOString()
    };
  }
});
