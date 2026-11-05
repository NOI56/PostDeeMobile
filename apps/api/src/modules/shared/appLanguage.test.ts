import { describe, expect, it } from 'vitest';
import { normalizeAppLanguage } from './appLanguage.js';

describe('app language normalization', () => {
  it.each([
    ['th', 'th'], ['en', 'en'], ['en-US', 'en'], ['TH-th', 'th'],
    ['th_TH', 'th'], ['ja', 'en'], [' fr-FR ', 'en'], ['', 'en'],
    [undefined, null], [null, null], [42, 'en']
  ])('normalizes %s to %s', (input, expected) => {
    expect(normalizeAppLanguage(input)).toBe(expected);
  });
});
