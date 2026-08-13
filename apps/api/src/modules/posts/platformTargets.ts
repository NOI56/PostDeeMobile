import type { SocialConnection } from '../socialConnections/socialConnectionStore.js';
import type { Platform } from './postStore.js';

export type PlatformTarget = {
  accountId: string;
  displayName?: string;
  externalAccountId?: string;
  connectedAt: string;
};

export type PlatformTargets = Partial<Record<Platform, PlatformTarget>>;

export type ResolveCurrentPlatformTarget = (input: {
  userId: string;
  platform: Platform;
}) => Promise<PlatformTarget | undefined>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const normalizeOptionalString = (value: unknown) =>
  typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;

const readTarget = (value: unknown): PlatformTarget | undefined => {
  if (!isRecord(value)) {
    return undefined;
  }

  const allowedKeys = new Set([
    'accountId',
    'displayName',
    'externalAccountId',
    'connectedAt'
  ]);
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) {
    return undefined;
  }

  const accountId = normalizeOptionalString(value.accountId);
  const connectedAt = normalizeOptionalString(value.connectedAt);
  const displayName = normalizeOptionalString(value.displayName);
  const externalAccountId = normalizeOptionalString(value.externalAccountId);

  if (
    !accountId ||
    !connectedAt ||
    Number.isNaN(Date.parse(connectedAt)) ||
    (value.displayName !== undefined && !displayName) ||
    (value.externalAccountId !== undefined && !externalAccountId)
  ) {
    return undefined;
  }

  return {
    accountId,
    ...(displayName ? { displayName } : {}),
    ...(externalAccountId ? { externalAccountId } : {}),
    connectedAt: new Date(connectedAt).toISOString()
  };
};

export const buildPlatformTarget = (connection: SocialConnection): PlatformTarget => ({
  accountId: connection.postPeerAccountId,
  ...(connection.displayName ? { displayName: connection.displayName } : {}),
  ...(connection.externalAccountId
    ? { externalAccountId: connection.externalAccountId }
    : {}),
  connectedAt: connection.connectedAt
});

export const normalizePersistedPlatformTargets = (
  value: unknown,
  platforms: Platform[]
): PlatformTargets | undefined => {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (!isRecord(value)) {
    throw new Error('Persisted platform targets are invalid');
  }

  const keys = Object.keys(value);
  if (
    keys.length !== platforms.length ||
    platforms.some((platform) => !Object.prototype.hasOwnProperty.call(value, platform))
  ) {
    throw new Error('Persisted platform targets are invalid');
  }

  const targets: PlatformTargets = {};
  for (const platform of platforms) {
    const target = readTarget(value[platform]);
    if (!target) {
      throw new Error('Persisted platform targets are invalid');
    }
    targets[platform] = target;
  }

  return targets;
};

export const arePlatformTargetsEqual = (
  left: PlatformTargets | undefined,
  right: PlatformTargets | undefined,
  platforms: Platform[]
) => {
  if (!left || !right) {
    return left === right;
  }

  return platforms.every((platform) => {
    const leftTarget = left[platform];
    const rightTarget = right[platform];
    return Boolean(leftTarget && rightTarget && isSamePlatformTarget(leftTarget, rightTarget));
  });
};

export const isSamePlatformTarget = (
  left: PlatformTarget,
  right: PlatformTarget
) =>
  left.accountId === right.accountId &&
  left.connectedAt === right.connectedAt &&
  (!left.externalAccountId ||
    !right.externalAccountId ||
    left.externalAccountId === right.externalAccountId);
