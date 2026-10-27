import { createHash, timingSafeEqual } from 'node:crypto';

const digest = (value: string) => createHash('sha256').update(value, 'utf8').digest();

/**
 * Constant-time check for a shared webhook secret. Hashing first gives equal
 * lengths, so neither the length nor the matching prefix leaks through timing.
 */
export const isSameSecret = (provided: string | undefined, expected: string) =>
  provided !== undefined &&
  provided.length > 0 &&
  expected.length > 0 &&
  timingSafeEqual(digest(provided), digest(expected));
