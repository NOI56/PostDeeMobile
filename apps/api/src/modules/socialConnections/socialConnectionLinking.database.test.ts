import { createHash, randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';

import {
  createPrismaSocialConnectionRepository,
  type PrismaSocialConnectionClient
} from './prismaSocialConnectionRepository.js';

// This opt-in suite must never access an application or hosted database.
const databaseUrl = process.env.POSTDEE_SOCIAL_LINKING_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' ||
    url.port !== '55482' || url.pathname !== '/postdee_batch2_test') {
    throw new Error('Social linking DB tests require the dedicated loopback fixture on port 55482');
  }
}

describe.skipIf(!databaseUrl).sequential('social linking real PostgreSQL transactions', () => {
  const prisma = new PrismaClient({ datasources: {
    db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55482/postdee_batch2_test' }
  } });
  const store = createPrismaSocialConnectionRepository({
    prisma: prisma as unknown as PrismaSocialConnectionClient
  });
  const userIds: string[] = [];
  const member = async () => {
    const userId = `social-fixture-${randomUUID()}`;
    userIds.push(userId);
    await prisma.user.create({ data: { id: userId, firebaseUid: userId, email: `${userId}@example.test` } });
    return userId;
  };
  const attempt = async (userId: string, overrides: { expiresAt?: string; baselineIntegrationIds?: string[] } = {}) => {
    const input = { userId, platform: 'TIKTOK' as const, profileId: `profile-${userId}`,
      nonceHash: createHash('sha256').update(randomUUID()).digest('hex'),
      expiresAt: new Date(Date.now() + 60_000).toISOString(), baselineIntegrationIds: ['seen-before'], ...overrides };
    await store.setProfileId({ userId, profileId: input.profileId });
    await store.beginConnectAttempt(input);
    return input;
  };
  const completion = (input: Awaited<ReturnType<typeof attempt>>, externalAccountId = `external-${randomUUID()}`) => ({
    userId: input.userId, platform: input.platform, profileId: input.profileId,
    nonceHash: input.nonceHash, now: new Date().toISOString(),
    integration: { postPeerAccountId: `integration-${randomUUID()}`, externalAccountId }
  });

  afterAll(async () => {
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.managedUploadOwner.deleteMany({ where: { ownerId: { in: userIds } } });
    await prisma.$disconnect();
  });

  it.each(['externalAccountId', 'postPeerAccountId'] as const)(
    'permits only one owner in a concurrent %s claim', async (identity) => {
      const owners = await Promise.all([member(), member()]);
      const shared = `shared-${randomUUID()}`;
      const results = await Promise.allSettled(owners.map((userId, index) => store.upsert({
        userId, platform: 'TIKTOK', postPeerAccountId: identity === 'postPeerAccountId' ? shared : `integration-${index}-${shared}`,
        externalAccountId: identity === 'externalAccountId' ? shared : `external-${index}-${shared}`
      })));
      expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
      expect(results.filter(result => result.status === 'rejected').map(result => result.reason.name))
        .toEqual(['SocialAccountAlreadyLinkedError']);
      expect(await prisma.socialConnection.count({ where: { userId: { in: owners } } })).toBe(1);
    }
  );

  it('consumes a nonce exactly once when completions race', async () => {
    const userId = await member();
    const pending = await attempt(userId);
    const input = completion(pending);
    const results = await Promise.all([
      store.completeConnectAttempt(input), store.completeConnectAttempt(input)
    ]);
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(await store.getConnectAttempt(pending)).toBeUndefined();
    expect(await prisma.socialConnection.count({ where: { userId } })).toBe(1);
  });

  it('rolls back nonce consumption when the account belongs to another owner', async () => {
    const [owner, caller] = await Promise.all([member(), member()]);
    const externalAccountId = `owned-${randomUUID()}`;
    await store.upsert({ userId: owner, platform: 'TIKTOK', postPeerAccountId: `owned-integration-${randomUUID()}`, externalAccountId });
    const pending = await attempt(caller);
    await expect(store.completeConnectAttempt(completion(pending, externalAccountId)))
      .rejects.toMatchObject({ name: 'SocialAccountAlreadyLinkedError' });
    expect(await store.getConnectAttempt(pending)).toMatchObject({ nonceHash: pending.nonceHash });
    expect(await store.getConnection({ userId: caller, platform: 'TIKTOK' })).toBeUndefined();
    expect(await store.getConnection({ userId: owner, platform: 'TIKTOK' })).toMatchObject({ externalAccountId });
  });

  it('does not consume a replacement attempt using the stale nonce', async () => {
    const userId = await member();
    const oldAttempt = await attempt(userId);
    const replacement = await attempt(userId);
    expect(await store.completeConnectAttempt(completion(oldAttempt))).toBeUndefined();
    expect(await store.getConnectAttempt(replacement)).toMatchObject({ nonceHash: replacement.nonceHash });
    expect(await store.completeConnectAttempt(completion(replacement))).toMatchObject({ userId });
  });

  it.each(['expiry', 'profile', 'baseline'] as const)('refuses completion with invalid %s', async (invalid) => {
    const userId = await member();
    const pending = await attempt(userId, invalid === 'expiry' ? { expiresAt: new Date(Date.now() - 1000).toISOString() } : {});
    const input = completion(pending);
    if (invalid === 'profile') input.profileId = 'different-profile';
    if (invalid === 'baseline') input.integration.postPeerAccountId = 'seen-before';
    expect(await store.completeConnectAttempt(input)).toBeUndefined();
    expect(await store.getConnection({ userId, platform: 'TIKTOK' })).toBeUndefined();
  });

  it('respects a durable deleting-owner marker without creating an attempt', async () => {
    const userId = await member();
    await prisma.managedUploadOwner.create({ data: { ownerId: userId, status: 'DELETING' } });
    await expect(attempt(userId)).rejects.toMatchObject({ code: 'ACCOUNT_DELETION_IN_PROGRESS' });
    expect(await prisma.socialConnectAttempt.count({ where: { userId } })).toBe(0);
    expect((await prisma.managedUploadOwner.findUnique({ where: { ownerId: userId } }))?.status).toBe('DELETING');
  });

  it('cascades pending attempts when the owning user is deleted', async () => {
    const userId = await member();
    await attempt(userId);
    await prisma.user.delete({ where: { id: userId } });
    expect(await prisma.socialConnectAttempt.count({ where: { userId } })).toBe(0);
  });

  it('rejects stale maintenance after a newer connection completes without cancelling another attempt', async () => {
    const userId = await member();
    const old = await store.upsert({ userId, platform: 'TIKTOK', postPeerAccountId: `old-${randomUUID()}`, externalAccountId: `old-external-${randomUUID()}` });
    const pending = await attempt(userId);
    const disconnectSnapshot = await store.getDisconnectSnapshot({ userId, platform: 'TIKTOK' });
    expect(disconnectSnapshot).toEqual({ connection: old, nonceHash: pending.nonceHash });
    const replacement = await store.completeConnectAttempt(completion(pending));
    const nextAttempt = await attempt(userId);
    const stale = { userId, platform: 'TIKTOK' as const,
      expectedPostPeerAccountId: old.postPeerAccountId, expectedExternalAccountId: old.externalAccountId };
    expect(await store.reconcileExistingConnection({ ...stale, integration: {
      postPeerAccountId: old.postPeerAccountId, externalAccountId: old.externalAccountId, displayName: 'Stale'
    } })).toBeUndefined();
    expect(await store.reconcileExistingConnection(stale)).toBeUndefined();
    await store.cancelConnectAttempt({ userId, platform: 'TIKTOK', nonceHash: disconnectSnapshot.nonceHash });
    expect(await store.getConnection({ userId, platform: 'TIKTOK' })).toEqual(replacement);
    expect(await store.getConnectAttempt(nextAttempt)).toMatchObject({ nonceHash: nextAttempt.nonceHash });
  });

  it('conditionally removes the exact old binding while preserving a pending attempt', async () => {
    const userId = await member();
    const old = await store.upsert({ userId, platform: 'TIKTOK', postPeerAccountId: `old-${randomUUID()}` });
    const pending = await attempt(userId);
    await store.reconcileExistingConnection({ userId, platform: 'TIKTOK', expectedPostPeerAccountId: old.postPeerAccountId });
    expect(await store.getConnection({ userId, platform: 'TIKTOK' })).toBeUndefined();
    expect(await store.getConnectAttempt(pending)).toMatchObject({ nonceHash: pending.nonceHash });
    expect(await store.completeConnectAttempt(completion(pending))).toMatchObject({ userId });
  });
});
