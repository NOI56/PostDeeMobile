import { describe, expect, it, vi } from 'vitest';

import { retryOwnerSerializationConflict } from './ownerSerializationRetry.js';

describe('owner serialization conflict retry', () => {
  it('caps exponential jitter and propagates the last database conflict within the backoff budget', async () => {
    vi.useFakeTimers();
    vi.spyOn(Math, 'random').mockReturnValue(0.999999);
    try {
      const conflicts = Array.from({ length: 6 }, (_, index) => Object.assign(new Error(`write conflict ${index}`), { code: 'P2034' }));
      const operation = vi.fn(async () => { throw conflicts[operation.mock.calls.length - 1]; });
      const startedAt = Date.now();
      const result = retryOwnerSerializationConflict(operation);
      const assertion = expect(result).rejects.toBe(conflicts[5]);
      await vi.advanceTimersByTimeAsync(48);
      expect(operation).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(operation).toHaveBeenCalledTimes(2);
      await vi.runAllTimersAsync();
      await assertion;
      expect(operation).toHaveBeenCalledTimes(6);
      expect(Date.now() - startedAt).toBe(1145);
    } finally { vi.useRealTimers(); vi.restoreAllMocks(); }
  });

  it.each([new Error('database unavailable'), { code: 'P2002' }, null, 'P2034'])(
    'does not retry other database failures: %j', async (error) => {
      const operation = vi.fn(async () => { throw error; });
      await expect(retryOwnerSerializationConflict(operation)).rejects.toBe(error);
      expect(operation).toHaveBeenCalledTimes(1);
    }
  );
});
