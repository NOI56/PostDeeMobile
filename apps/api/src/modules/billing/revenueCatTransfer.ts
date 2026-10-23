import type { Response } from 'express';

import type { OwnerMutationCoordinator } from '../account/ownerMutationLock.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import { UploadSessionConflictError } from '../uploads/uploadSessionStore.js';
import {
  type RevenueCatSubscriberClient,
  type RevenueCatSubscriberSnapshot
} from './revenueCatSubscriberClient.js';
import {
  isRevenueCatSubscriptionEntitlementAllowed,
  selectRevenueCatPaidEntitlement,
  type RevenueCatSubscriptionPolicyConfig
} from './revenueCatSubscriptionPolicy.js';

type RevenueCatTransferEvent = {
  id: string;
  timestampMs: number;
  ownerIds: string[];
};

const readIdentifier = (value: unknown) =>
  typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;

const readOwners = (value: unknown): string[] | undefined => {
  if (!Array.isArray(value) || value.length === 0) return undefined;
  const owners = value.map(readIdentifier);
  return owners.every((owner): owner is string => owner !== undefined)
    ? owners
    : undefined;
};

const readTransfer = (event: unknown): RevenueCatTransferEvent | undefined => {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return undefined;
  const raw = event as Record<string, unknown>;
  const id = readIdentifier(raw.id);
  const sourceIds = readOwners(raw.transferred_from);
  const destinationIds = readOwners(raw.transferred_to);
  if (raw.type !== 'TRANSFER' || !id || !sourceIds || !destinationIds ||
    typeof raw.event_timestamp_ms !== 'number' ||
    !Number.isSafeInteger(raw.event_timestamp_ms) || raw.event_timestamp_ms <= 0) {
    return undefined;
  }
  return {
    id,
    timestampMs: raw.event_timestamp_ms,
    ownerIds: [...new Set([...sourceIds, ...destinationIds])]
  };
};

const sendLookupFailure = (response: Response) => response.status(502).json({
  status: 'error',
  code: 'REVENUECAT_TRANSFER_RECONCILIATION_FAILED',
  message: 'RevenueCat transfer reconciliation failed. Retry this webhook.'
});

export const handleRevenueCatTransfer = async ({
  event,
  response,
  config,
  subscriberClient,
  userStore,
  subscriptionStore,
  ownerMutationLock
}: {
  event: unknown;
  response: Response;
  config: RevenueCatSubscriptionPolicyConfig;
  subscriberClient?: RevenueCatSubscriberClient;
  userStore: UserStore;
  subscriptionStore: SubscriptionStore;
  ownerMutationLock: OwnerMutationCoordinator;
}): Promise<void> => {
  const transfer = readTransfer(event);
  if (!transfer) {
    response.status(400).json({
      status: 'error',
      code: 'REVENUECAT_WEBHOOK_INVALID',
      message: 'RevenueCat transfers require event ordering metadata and source and destination user ids'
    });
    return;
  }
  if (!subscriberClient) {
    response.status(503).json({
      status: 'error',
      code: 'REVENUECAT_TRANSFER_NOT_CONFIGURED',
      message: 'RevenueCat transfer reconciliation is not configured'
    });
    return;
  }

  const owners: Array<{ id: string; release: () => void }> = [];
  try {
    for (const id of [...transfer.ownerIds].sort()) {
      const release = await ownerMutationLock.acquireMutation(id);
      owners.push({ id, release });
      if (!ownerMutationLock.isActive(id) || !(await userStore.exists(id))) {
        owners.pop();
        release();
        continue;
      }
    }
    if (owners.length === 0) {
      response.status(202).json({
        status: 'ok',
        ignored: true,
        eventType: 'TRANSFER',
        code: 'REVENUECAT_USER_NOT_FOUND'
      });
      return;
    }

    // Resolve every existing owner before changing either side. A provider
    // failure must not turn an unverified source/destination into BASIC.
    const snapshots = new Map<string, RevenueCatSubscriberSnapshot>();
    for (const owner of owners) {
      let snapshot: RevenueCatSubscriberSnapshot;
      try {
        snapshot = await subscriberClient.loadSubscriber(owner.id);
      } catch {
        sendLookupFailure(response);
        return;
      }
      // An eventually consistent response older than the transfer cannot
      // acknowledge its completion. Let RevenueCat retry with a fresh view.
      if (!Number.isSafeInteger(snapshot.observedAtMs) ||
        snapshot.observedAtMs < transfer.timestampMs) {
        sendLookupFailure(response);
        return;
      }
      const paid = selectRevenueCatPaidEntitlement(snapshot.activeEntitlements, config);
      if (!paid && snapshot.activeEntitlements.some((entitlement) =>
        isRevenueCatSubscriptionEntitlementAllowed(entitlement, config))) {
        // An eligible but unmapped entitlement is configuration drift, not
        // evidence that this owner's paid subscription was removed.
        sendLookupFailure(response);
        return;
      }
      snapshots.set(owner.id, snapshot);
    }

    let reconciledUsers = 0;
    let appliedUsers = 0;
    const ownersById = new Map(owners.map((owner) => [owner.id, owner]));
    // Remove transferred source access before granting destination access.
    // A failed source write leaves the webhook retryable without a new grant.
    for (const id of transfer.ownerIds) {
      const owner = ownersById.get(id);
      if (!owner) continue;
      if (!ownerMutationLock.isActive(owner.id) || !(await userStore.exists(owner.id))) continue;
      const snapshot = snapshots.get(owner.id)!;
      const paid = selectRevenueCatPaidEntitlement(snapshot.activeEntitlements, config);
      const common = {
        authUser: { id: owner.id, provider: 'firebase' as const },
        billingSubscriptionId: `revenuecat:${owner.id}`,
        eventId: `revenuecat-transfer:${encodeURIComponent(transfer.id)}:${encodeURIComponent(owner.id)}`,
        eventTimestampMs: snapshot.observedAtMs
      };
      try {
        const result = await subscriptionStore.applyRevenueCatEvent(paid ? {
          ...common,
          plan: paid.plan,
          status: 'ACTIVE',
          currentPeriodEnd: paid.entitlement.expiresAt ?? null
        } : {
          ...common,
          status: 'CANCELED'
        });
        reconciledUsers += 1;
        if (result.applied) appliedUsers += 1;
      } catch (error) {
        if (!(error instanceof UploadSessionConflictError) ||
          error.code !== 'ACCOUNT_DELETION_IN_PROGRESS') throw error;
      }
    }
    response.status(reconciledUsers > 0 ? 200 : 202).json({
      status: 'ok',
      ignored: appliedUsers === 0,
      eventType: 'TRANSFER',
      reconciledUsers
    });
  } finally {
    for (const owner of owners.reverse()) owner.release();
  }
};
