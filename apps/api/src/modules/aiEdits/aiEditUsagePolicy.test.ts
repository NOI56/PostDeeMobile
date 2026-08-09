import { describe, expect, it } from 'vitest';

import {
  shouldReserveAiEditMinutes,
  type AiEditAnalysisOutcomes
} from './aiEditUsagePolicy.js';

const outcomes = (
  value: Partial<AiEditAnalysisOutcomes>
): AiEditAnalysisOutcomes => ({
  plan: 'not-requested',
  subtitle: 'not-requested',
  silence: 'not-requested',
  speechReduction: 'not-requested',
  sfx: 'not-requested',
  ...value
});

describe('shouldReserveAiEditMinutes', () => {
  it.each([
    [
      'repeat-only unavailable',
      outcomes({ speechReduction: 'unavailable' }),
      false
    ],
    [
      'repeat-only ready',
      outcomes({ speechReduction: 'succeeded' }),
      true
    ],
    [
      'repeat unavailable plus subtitle success',
      outcomes({
        speechReduction: 'unavailable',
        subtitle: 'succeeded'
      }),
      true
    ],
    [
      'repeat unavailable plus subtitle unavailable',
      outcomes({
        speechReduction: 'unavailable',
        subtitle: 'unavailable'
      }),
      false
    ],
    [
      'repeat unavailable plus silence success-empty',
      outcomes({
        speechReduction: 'unavailable',
        silence: 'succeeded'
      }),
      true
    ],
    [
      'repeat unavailable plus silence unavailable',
      outcomes({
        speechReduction: 'unavailable',
        silence: 'unavailable'
      }),
      false
    ],
    [
      'repeat unavailable plus plan success',
      outcomes({
        speechReduction: 'unavailable',
        plan: 'succeeded'
      }),
      true
    ],
    [
      'repeat unavailable plus plan unavailable',
      outcomes({
        speechReduction: 'unavailable',
        plan: 'unavailable'
      }),
      false
    ],
    [
      'sound-effect analysis succeeded with an empty selection',
      outcomes({ sfx: 'succeeded' }),
      true
    ],
    [
      'sound-effect provider unavailable',
      outcomes({ sfx: 'unavailable' }),
      false
    ],
    [
      'color-only defense in depth',
      outcomes({}),
      false
    ]
  ] as const)('%s => reserve=%s', (_name, analysisOutcomes, expected) => {
    expect(shouldReserveAiEditMinutes({
      outcomes: analysisOutcomes,
      isLegacyRequest: false
    })).toBe(expected);
  });

  it('keeps charging a legacy request without explicit capabilities or a plan', () => {
    expect(shouldReserveAiEditMinutes({
      outcomes: outcomes({}),
      isLegacyRequest: true
    })).toBe(true);
  });
});
