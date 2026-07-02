import type { Request, RequestHandler } from 'express';

export type RateLimitOptions = {
  bucket: string;
  windowMs: number;
  maxRequests: number;
  now?: () => number;
};

type RateBucket = {
  count: number;
  resetAt: number;
};

const readFirstHeaderValue = (value: string | string[] | undefined) =>
  Array.isArray(value) ? value[0] : value;

const readClientAddress = (request: Request) => {
  const forwardedFor = readFirstHeaderValue(request.headers['x-forwarded-for']);
  const forwardedAddress = forwardedFor?.split(',').at(0)?.trim();

  return (
    forwardedAddress ||
    request.ip ||
    request.socket.remoteAddress ||
    'unknown-client'
  );
};

const deleteExpiredBuckets = (buckets: Map<string, RateBucket>, now: number) => {
  for (const [key, bucket] of buckets.entries()) {
    if (bucket.resetAt <= now) {
      buckets.delete(key);
    }
  }
};

export const createRateLimitMiddleware = ({
  bucket,
  windowMs,
  maxRequests,
  now = Date.now
}: RateLimitOptions): RequestHandler => {
  const buckets = new Map<string, RateBucket>();

  return (request, response, next) => {
    const currentTime = now();
    deleteExpiredBuckets(buckets, currentTime);

    const clientKey = `${bucket}:${readClientAddress(request)}`;
    const currentBucket = buckets.get(clientKey) ?? {
      count: 0,
      resetAt: currentTime + windowMs
    };
    currentBucket.count += 1;
    buckets.set(clientKey, currentBucket);

    const remaining = Math.max(maxRequests - currentBucket.count, 0);
    const retryAfterSeconds = Math.max(
      Math.ceil((currentBucket.resetAt - currentTime) / 1000),
      1
    );

    response.setHeader('RateLimit-Limit', String(maxRequests));
    response.setHeader('RateLimit-Remaining', String(remaining));
    response.setHeader('RateLimit-Reset', String(Math.ceil(currentBucket.resetAt / 1000)));

    if (currentBucket.count > maxRequests) {
      response.setHeader('Retry-After', String(retryAfterSeconds));
      response.status(429).json({
        status: 'error',
        code: 'RATE_LIMITED',
        message: 'Too many requests. Please try again shortly.'
      });
      return;
    }

    next();
  };
};