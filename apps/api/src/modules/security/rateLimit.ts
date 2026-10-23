import type { Request, RequestHandler } from 'express';
import { ipKeyGenerator } from 'express-rate-limit';

export type RateLimitOptions = {
  bucket: string;
  windowMs: number;
  maxRequests: number;
  // Upper bound on remembered client addresses; the oldest is evicted first.
  maxTrackedClients?: number;
  now?: () => number;
};

const DEFAULT_MAX_TRACKED_CLIENTS = 10_000;

type RateBucket = {
  count: number;
  resetAt: number;
};

// Express resolves req.ip using the configured proxy trust boundary. Reading
// X-Forwarded-For ourselves lets clients prepend an arbitrary bucket key.
const readClientAddress = (request: Request) =>
  ipKeyGenerator(request.ip || request.socket.remoteAddress || 'unknown-client');

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
  maxTrackedClients = DEFAULT_MAX_TRACKED_CLIENTS,
  now = Date.now
}: RateLimitOptions): RequestHandler => {
  const buckets = new Map<string, RateBucket>();
  let nextSweepAt = 0;

  return (request, response, next) => {
    const currentTime = now();

    // Sweep at most once per window instead of scanning every bucket on every
    // request; an expired bucket that is still stored is replaced below.
    if (currentTime >= nextSweepAt) {
      deleteExpiredBuckets(buckets, currentTime);
      nextSweepAt = currentTime + windowMs;
    }

    const clientKey = `${bucket}:${readClientAddress(request)}`;
    let currentBucket = buckets.get(clientKey);

    if (!currentBucket || currentBucket.resetAt <= currentTime) {
      buckets.delete(clientKey);

      if (buckets.size >= maxTrackedClients) {
        const oldestKey = buckets.keys().next().value;
        if (oldestKey !== undefined) buckets.delete(oldestKey);
      }

      currentBucket = { count: 0, resetAt: currentTime + windowMs };
      buckets.set(clientKey, currentBucket);
    }

    currentBucket.count += 1;

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
