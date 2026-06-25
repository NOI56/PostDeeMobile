import {
  StorePurchaseVerificationError,
  type StorePurchaseVerifier
} from './storePurchaseService.js';

const GOOGLE_PLAY_SUBSCRIPTIONS_V2_BASE_URL =
  'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

type GooglePlayAccessTokenProvider = () => Promise<string | undefined>;

export type GooglePlayFetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

export type GooglePlayFetchImpl = (
  url: string,
  init: {
    method: 'GET';
    headers: {
      Accept: 'application/json';
      Authorization: string;
    };
  }
) => Promise<GooglePlayFetchResponse>;

type GooglePlaySubscriptionV2Response = {
  subscriptionState?: unknown;
  lineItems?: unknown;
};

type GooglePlaySubscriptionLineItem = {
  productId?: unknown;
  expiryTime?: unknown;
};

const activeSubscriptionStates = new Set(['SUBSCRIPTION_STATE_ACTIVE']);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const readLineItems = (body: GooglePlaySubscriptionV2Response) =>
  Array.isArray(body.lineItems)
    ? (body.lineItems.filter(isRecord) as GooglePlaySubscriptionLineItem[])
    : [];

const findMatchingLineItem = (
  lineItems: GooglePlaySubscriptionLineItem[],
  productId: string
) => lineItems.find((item) => item.productId === productId);

export const createGooglePlayPurchaseVerifier = ({
  packageName,
  accessTokenProvider,
  fetchImpl = fetch as GooglePlayFetchImpl,
  now = () => new Date()
}: {
  packageName: string;
  accessTokenProvider: GooglePlayAccessTokenProvider;
  fetchImpl?: GooglePlayFetchImpl;
  now?: () => Date;
}): StorePurchaseVerifier => ({
  verify: async (purchase) => {
    if (purchase.platform !== 'ANDROID') {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'GOOGLE_PLAY_ANDROID_ONLY',
        message: 'Google Play verifier only supports Android purchases'
      });
    }

    if (!purchase.purchaseToken) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'GOOGLE_PLAY_PURCHASE_TOKEN_REQUIRED',
        message: 'Google Play purchase token is required'
      });
    }

    const accessToken = (await accessTokenProvider())?.trim();

    if (!accessToken) {
      throw new StorePurchaseVerificationError({
        statusCode: 501,
        code: 'GOOGLE_PLAY_ACCESS_TOKEN_NOT_CONFIGURED',
        message: 'Google Play access token is not configured'
      });
    }

    const url = `${GOOGLE_PLAY_SUBSCRIPTIONS_V2_BASE_URL}/${encodeURIComponent(
      packageName
    )}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchase.purchaseToken)}`;
    const response = await fetchImpl(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      throw new StorePurchaseVerificationError({
        statusCode: 502,
        code: 'GOOGLE_PLAY_VERIFICATION_FAILED',
        message: `Google Play verification failed with status ${response.status ?? 'unknown'}`
      });
    }

    const body = (await response.json()) as GooglePlaySubscriptionV2Response;
    const subscriptionState =
      typeof body.subscriptionState === 'string' ? body.subscriptionState : undefined;

    if (!subscriptionState || !activeSubscriptionStates.has(subscriptionState)) {
      throw new StorePurchaseVerificationError({
        statusCode: 402,
        code: 'GOOGLE_PLAY_SUBSCRIPTION_NOT_ACTIVE',
        message: 'Google Play subscription is not active'
      });
    }

    const matchingLineItem = findMatchingLineItem(readLineItems(body), purchase.productId);

    if (!matchingLineItem) {
      throw new StorePurchaseVerificationError({
        statusCode: 400,
        code: 'GOOGLE_PLAY_PRODUCT_MISMATCH',
        message: 'Google Play subscription product does not match the requested product'
      });
    }

    const expiryTime =
      typeof matchingLineItem.expiryTime === 'string'
        ? Date.parse(matchingLineItem.expiryTime)
        : Number.NaN;

    if (!Number.isFinite(expiryTime) || expiryTime <= now().getTime()) {
      throw new StorePurchaseVerificationError({
        statusCode: 402,
        code: 'GOOGLE_PLAY_SUBSCRIPTION_EXPIRED',
        message: 'Google Play subscription is expired'
      });
    }

    return {
      provider: 'google-play',
      platform: 'ANDROID',
      productId: purchase.productId,
      purchaseToken: purchase.purchaseToken,
      verifiedAt: now().toISOString()
    };
  }
});
