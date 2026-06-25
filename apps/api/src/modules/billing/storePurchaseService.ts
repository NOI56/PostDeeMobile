export type StorePurchasePlatform = 'ANDROID' | 'IOS';
export type StorePurchaseProvider = 'mock-store' | 'google-play' | 'apple-app-store';

export type StorePurchaseRequest = {
  platform: StorePurchasePlatform;
  productId: string;
  purchaseToken?: string;
  transactionId?: string;
};

export type VerifiedStorePurchase = StorePurchaseRequest & {
  provider: StorePurchaseProvider;
  originalTransactionId?: string;
  verifiedAt: string;
};

export type StorePurchaseVerifier = {
  verify: (purchase: StorePurchaseRequest) => Promise<VerifiedStorePurchase>;
};

export class StorePurchaseVerificationError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor({
    statusCode,
    code,
    message
  }: {
    statusCode: number;
    code: string;
    message: string;
  }) {
    super(message);
    this.name = 'StorePurchaseVerificationError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export const createMockStorePurchaseVerifier = ({
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): StorePurchaseVerifier => ({
  verify: async (purchase) => ({
    ...purchase,
    provider: 'mock-store',
    verifiedAt: now()
  })
});

export const buildBillingSubscriptionId = (purchase: VerifiedStorePurchase) => {
  if (purchase.platform === 'ANDROID' && purchase.purchaseToken) {
    return `google-play:${purchase.purchaseToken}`;
  }

  if (purchase.platform === 'IOS') {
    const transactionId = purchase.originalTransactionId ?? purchase.transactionId;

    if (transactionId) {
      return `apple-app-store:${transactionId}`;
    }
  }

  return undefined;
};
