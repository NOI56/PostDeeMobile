import { describe, expect, it } from 'vitest';

import { isSameSecret } from './secretCompare.js';

describe('isSameSecret', () => {
  it('accepts an identical secret', () => {
    expect(isSameSecret('webhook-token-123', 'webhook-token-123')).toBe(true);
  });

  it('rejects a different secret of the same length', () => {
    expect(isSameSecret('webhook-token-124', 'webhook-token-123')).toBe(false);
  });

  it('rejects a different length without throwing', () => {
    expect(isSameSecret('short', 'webhook-token-123')).toBe(false);
    expect(isSameSecret('webhook-token-1234', 'webhook-token-123')).toBe(false);
  });

  it('rejects a missing or empty secret', () => {
    expect(isSameSecret(undefined, 'webhook-token-123')).toBe(false);
    expect(isSameSecret('', '')).toBe(false);
  });

  it('compares multi-byte secrets by bytes', () => {
    expect(isSameSecret('รหัสลับ', 'รหัสลับ')).toBe(true);
    expect(isSameSecret('รหัสลับ', 'รหัสลัข')).toBe(false);
  });
});
