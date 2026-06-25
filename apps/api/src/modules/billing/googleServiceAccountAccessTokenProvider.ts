import { createSign } from 'node:crypto';

import { StorePurchaseVerificationError } from './storePurchaseService.js';

const androidPublisherScope = 'https://www.googleapis.com/auth/androidpublisher';
const jwtBearerGrantType = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
const tokenExpirySkewMs = 60_000;

type GoogleServiceAccountAccessTokenResponse = {
  access_token?: unknown;
  expires_in?: unknown;
};

type GoogleServiceAccountKey = {
  client_email?: unknown;
  private_key?: unknown;
  private_key_id?: unknown;
  token_uri?: unknown;
};

export type GoogleAccessTokenFetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

export type GoogleAccessTokenFetchImpl = (
  url: string,
  init: {
    method: 'POST';
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded';
    };
    body: string;
  }
) => Promise<GoogleAccessTokenFetchResponse>;

export type GoogleServiceAccountAccessTokenProvider = () => Promise<string>;

const encodeBase64UrlJson = (value: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

const parseServiceAccountKey = (serviceAccountKeyJson: string) => {
  let parsed: GoogleServiceAccountKey;

  try {
    parsed = JSON.parse(serviceAccountKeyJson) as GoogleServiceAccountKey;
  } catch {
    throw new StorePurchaseVerificationError({
      statusCode: 501,
      code: 'GOOGLE_SERVICE_ACCOUNT_KEY_INVALID',
      message: 'Google Play service account key JSON is invalid'
    });
  }

  const clientEmail =
    typeof parsed.client_email === 'string' && parsed.client_email.trim()
      ? parsed.client_email.trim()
      : undefined;
  const privateKey =
    typeof parsed.private_key === 'string' && parsed.private_key.trim()
      ? parsed.private_key
      : undefined;
  const privateKeyId =
    typeof parsed.private_key_id === 'string' && parsed.private_key_id.trim()
      ? parsed.private_key_id.trim()
      : undefined;
  const tokenUri =
    typeof parsed.token_uri === 'string' && parsed.token_uri.trim()
      ? parsed.token_uri.trim()
      : 'https://oauth2.googleapis.com/token';

  if (!clientEmail || !privateKey) {
    throw new StorePurchaseVerificationError({
      statusCode: 501,
      code: 'GOOGLE_SERVICE_ACCOUNT_KEY_INVALID',
      message: 'Google Play service account key must include client_email and private_key'
    });
  }

  return {
    clientEmail,
    privateKey,
    privateKeyId,
    tokenUri
  };
};

const createSignedJwtAssertion = ({
  clientEmail,
  privateKey,
  privateKeyId,
  tokenUri,
  now
}: {
  clientEmail: string;
  privateKey: string;
  privateKeyId?: string;
  tokenUri: string;
  now: Date;
}) => {
  const issuedAtSeconds = Math.floor(now.getTime() / 1000);
  const expiresAtSeconds = issuedAtSeconds + 3600;
  const header = encodeBase64UrlJson({
    alg: 'RS256',
    typ: 'JWT',
    ...(privateKeyId ? { kid: privateKeyId } : {})
  });
  const payload = encodeBase64UrlJson({
    iss: clientEmail,
    scope: androidPublisherScope,
    aud: tokenUri,
    iat: issuedAtSeconds,
    exp: expiresAtSeconds
  });
  const unsignedJwt = `${header}.${payload}`;
  const signature = createSign('RSA-SHA256')
    .update(unsignedJwt)
    .end()
    .sign(privateKey, 'base64url');

  return `${unsignedJwt}.${signature}`;
};

const readTokenResponse = (body: unknown): GoogleServiceAccountAccessTokenResponse =>
  body && typeof body === 'object'
    ? (body as GoogleServiceAccountAccessTokenResponse)
    : {};

export const createGoogleServiceAccountAccessTokenProvider = ({
  serviceAccountKeyJson,
  fetchImpl = fetch as GoogleAccessTokenFetchImpl,
  now = () => new Date()
}: {
  serviceAccountKeyJson: string;
  fetchImpl?: GoogleAccessTokenFetchImpl;
  now?: () => Date;
}): GoogleServiceAccountAccessTokenProvider => {
  let cachedToken:
    | {
        accessToken: string;
        expiresAtMs: number;
      }
    | undefined;

  return async () => {
    const currentTime = now();

    if (cachedToken && cachedToken.expiresAtMs - tokenExpirySkewMs > currentTime.getTime()) {
      return cachedToken.accessToken;
    }

    const serviceAccountKey = parseServiceAccountKey(serviceAccountKeyJson);
    const assertion = createSignedJwtAssertion({
      ...serviceAccountKey,
      now: currentTime
    });
    const body = new URLSearchParams({
      grant_type: jwtBearerGrantType,
      assertion
    }).toString();
    const response = await fetchImpl(serviceAccountKey.tokenUri, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body
    });

    if (!response.ok) {
      throw new StorePurchaseVerificationError({
        statusCode: 502,
        code: 'GOOGLE_ACCESS_TOKEN_REQUEST_FAILED',
        message: `Google OAuth token request failed with status ${response.status ?? 'unknown'}`
      });
    }

    const tokenResponse = readTokenResponse(await response.json());
    const accessToken =
      typeof tokenResponse.access_token === 'string' && tokenResponse.access_token.trim()
        ? tokenResponse.access_token.trim()
        : undefined;
    const expiresIn =
      typeof tokenResponse.expires_in === 'number' && Number.isFinite(tokenResponse.expires_in)
        ? tokenResponse.expires_in
        : undefined;

    if (!accessToken || !expiresIn || expiresIn <= 0) {
      throw new StorePurchaseVerificationError({
        statusCode: 502,
        code: 'GOOGLE_ACCESS_TOKEN_RESPONSE_INVALID',
        message: 'Google OAuth token response is missing access_token or expires_in'
      });
    }

    cachedToken = {
      accessToken,
      expiresAtMs: currentTime.getTime() + expiresIn * 1000
    };

    return accessToken;
  };
};
