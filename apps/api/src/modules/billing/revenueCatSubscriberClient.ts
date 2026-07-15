type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

export type RevenueCatActiveEntitlement = {
  id: string;
  productId: string;
  expiresAt?: string;
};

export type RevenueCatSubscriberSnapshot = {
  activeEntitlements: RevenueCatActiveEntitlement[];
};

export type RevenueCatSubscriberClient = {
  loadSubscriber: (appUserId: string) => Promise<RevenueCatSubscriberSnapshot>;
};

export class RevenueCatSubscriberUnavailableError extends Error {
  constructor() {
    super('RevenueCat subscriber lookup is not configured');
    this.name = 'RevenueCatSubscriberUnavailableError';
  }
}

export class RevenueCatSubscriberProviderError extends Error {
  constructor() {
    super('RevenueCat subscriber lookup failed');
    this.name = 'RevenueCatSubscriberProviderError';
  }
}

const readRecord = (value: unknown): Record<string, unknown> | undefined =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readOptionalDate = (value: unknown) => {
  if (value === null || value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw new RevenueCatSubscriberProviderError();
  }

  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    throw new RevenueCatSubscriberProviderError();
  }

  return timestamp;
};

const laterTimestamp = (timestamps: Array<number | undefined>) => {
  const values = timestamps.filter((value): value is number => value !== undefined);
  return values.length > 0 ? Math.max(...values) : undefined;
};

export const createRevenueCatSubscriberClient = ({
  apiKey,
  baseUrl = 'https://api.revenuecat.com/v1',
  fetchImpl = fetch as unknown as FetchImpl,
  now = () => new Date(),
  timeoutMs = 8_000
}: {
  apiKey?: string;
  baseUrl?: string;
  fetchImpl?: FetchImpl;
  now?: () => Date;
  timeoutMs?: number;
} = {}): RevenueCatSubscriberClient => {
  const root = baseUrl.replace(/\/$/, '');

  return {
    loadSubscriber: async (appUserId) => {
      if (!apiKey) {
        throw new RevenueCatSubscriberUnavailableError();
      }

      const abortController = new AbortController();
      const timeout = setTimeout(() => abortController.abort(), timeoutMs);

      try {
        const response = await fetchImpl(
          `${root}/subscribers/${encodeURIComponent(appUserId)}`,
          {
            method: 'GET',
            headers: { Authorization: `Bearer ${apiKey}` },
            signal: abortController.signal
          }
        );

        if (!response.ok) {
          throw new RevenueCatSubscriberProviderError();
        }

        const payload = readRecord(await response.json());
        const subscriber = readRecord(payload?.subscriber);
        const entitlements = readRecord(subscriber?.entitlements);
        const subscriptions = readRecord(subscriber?.subscriptions) ?? {};

        if (!payload || !subscriber || !entitlements) {
          throw new RevenueCatSubscriberProviderError();
        }

        const requestDateMs =
          typeof payload.request_date_ms === 'number' &&
          Number.isFinite(payload.request_date_ms)
            ? payload.request_date_ms
            : now().getTime();
        const activeEntitlements: RevenueCatActiveEntitlement[] = [];

        for (const [id, rawEntitlement] of Object.entries(entitlements)) {
          const entitlement = readRecord(rawEntitlement);
          const productId = readRequiredString(entitlement?.product_identifier);

          if (!entitlement || !productId || !('expires_date' in entitlement)) {
            throw new RevenueCatSubscriberProviderError();
          }

          if (entitlement.expires_date === null) {
            activeEntitlements.push({ id, productId });
            continue;
          }

          const subscription = readRecord(subscriptions[productId]);
          const effectiveAccessEnd = laterTimestamp([
            readOptionalDate(entitlement.expires_date),
            readOptionalDate(entitlement.grace_period_expires_date),
            readOptionalDate(subscription?.grace_period_expires_date)
          ]);

          if (effectiveAccessEnd !== undefined && effectiveAccessEnd > requestDateMs) {
            activeEntitlements.push({
              id,
              productId,
              expiresAt: new Date(effectiveAccessEnd).toISOString()
            });
          }
        }

        return { activeEntitlements };
      } catch (error) {
        if (error instanceof RevenueCatSubscriberProviderError) {
          throw error;
        }

        throw new RevenueCatSubscriberProviderError();
      } finally {
        clearTimeout(timeout);
      }
    }
  };
};
