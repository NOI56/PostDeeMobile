import type { Request, Response } from 'express';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { createRateLimitMiddleware, type RateLimitOptions } from './rateLimit.js';

const fakeRequest = (ip: string) => ({ ip, socket: { remoteAddress: ip } }) as unknown as Request;

const fakeResponse = () => {
  const headers = new Map<string, string>();
  const response = {
    statusCode: 200,
    setHeader: (name: string, value: string) => {
      headers.set(name.toLowerCase(), value);
      return response;
    },
    status: (code: number) => {
      response.statusCode = code;
      return response;
    },
    json: () => response
  };
  return { response: response as unknown as Response, headers, statusCode: () => response.statusCode };
};

const send = (limiter: ReturnType<typeof createRateLimitMiddleware>, ip: string) => {
  const { response, headers, statusCode } = fakeResponse();
  const next = vi.fn();
  limiter(fakeRequest(ip), response, next);
  return { remaining: Number(headers.get('ratelimit-remaining')), status: statusCode(), passed: next.mock.calls.length === 1 };
};

afterEach(() => {
  vi.restoreAllMocks();
});

// The limiter is process-wide and synchronous. Its per-request work and memory
// must not grow with the number of distinct client addresses it has seen.
describe('rate limit bucket bounds', () => {
  it('does not sweep every tracked bucket on every request', () => {
    let currentTime = Date.UTC(2026, 9, 24, 12, 0, 0);
    const limiter = createRateLimitMiddleware({ bucket: 'test', windowMs: 60_000, maxRequests: 5, now: () => currentTime });
    for (let index = 0; index < 50; index += 1) {
      send(limiter, `198.51.100.${index}`);
    }
    const entries = vi.spyOn(Map.prototype, 'entries');

    for (let index = 0; index < 50; index += 1) {
      currentTime += 10;
      send(limiter, '203.0.113.1');
    }

    expect(entries.mock.calls.length).toBeLessThanOrEqual(1);
  });

  it('starts a fresh window for a client whose bucket expired before any sweep', () => {
    let currentTime = Date.UTC(2026, 9, 24, 12, 0, 0);
    const limiter = createRateLimitMiddleware({ bucket: 'test', windowMs: 60_000, maxRequests: 2, now: () => currentTime });

    send(limiter, '203.0.113.2');
    send(limiter, '203.0.113.2');
    expect(send(limiter, '203.0.113.2').status).toBe(429);

    currentTime += 60_000;
    const afterWindow = send(limiter, '203.0.113.2');

    expect(afterWindow.passed).toBe(true);
    expect(afterWindow.remaining).toBe(1);
  });

  it('evicts the oldest client once the tracked-client cap is reached', () => {
    const options = {
      bucket: 'test',
      windowMs: 60_000,
      maxRequests: 5,
      maxTrackedClients: 2,
      now: () => Date.UTC(2026, 9, 24, 12, 0, 0)
    } as RateLimitOptions;
    const limiter = createRateLimitMiddleware(options);

    expect(send(limiter, '203.0.113.3').remaining).toBe(4);
    send(limiter, '203.0.113.4');
    send(limiter, '203.0.113.5');

    expect(send(limiter, '203.0.113.3').remaining).toBe(4);
    expect(send(limiter, '203.0.113.5').remaining).toBe(3);
  });
});
