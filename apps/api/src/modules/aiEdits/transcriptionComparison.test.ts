import { describe, expect, it } from 'vitest';

import {
  buildTranscriptionComparison,
  normalizeThaiForCer,
  validateSanitizedBenchmarkValue
} from './transcriptionComparison.js';

describe('transcription comparison', () => {
  it('compares accuracy, timing, latency, and cost', () => {
    const comparison = buildTranscriptionComparison({
      referenceText: 'สวัสดีครับ วันนี้ลดราคา',
      providers: [
        {
          provider: 'groq',
          text: 'สวัสดีครับ วันนี้ลดรา',
          audioDurationSeconds: 60,
          elapsedMilliseconds: 400,
          usdPerHour: 0.111,
          hallucinatedPhraseCount: 1,
          openingSpeechOmitted: false,
          timingErrorsMilliseconds: [100, 200, 300, 400]
        },
        {
          provider: 'elevenlabs',
          text: 'สวัสดีครับ วันนี้ลดราคา',
          audioDurationSeconds: 60,
          elapsedMilliseconds: 700,
          usdPerHour: 0.22,
          hallucinatedPhraseCount: 0,
          openingSpeechOmitted: false,
          timingErrorsMilliseconds: [50, 100, 150, 200]
        }
      ]
    });

    expect(comparison.providers[0]).toMatchObject({
      provider: 'groq',
      estimatedCostUsd: 0.00185,
      medianTimingErrorMilliseconds: 250,
      p95TimingErrorMilliseconds: 400
    });
    expect(comparison.providers[1]?.characterErrorRate).toBe(0);
    expect(comparison.accuracyWinner).toBe('elevenlabs');
    expect(comparison.relativeCerImprovementPercent).toBe(100);
  });

  it('normalizes whitespace, punctuation, symbols, and case for CER', () => {
    expect(normalizeThaiForCer(' สวัสดี, Weekend! ฿100 ')).toBe(
      'สวัสดีweekend100'
    );
  });

  it('reports an accuracy tie below three percentage points', () => {
    const comparison = buildTranscriptionComparison({
      referenceText: 'ก'.repeat(100),
      providers: [
        {
          provider: 'groq',
          text: 'ก'.repeat(98),
          audioDurationSeconds: 60,
          elapsedMilliseconds: 400,
          usdPerHour: 0.111,
          hallucinatedPhraseCount: 0,
          openingSpeechOmitted: false,
          timingErrorsMilliseconds: [100]
        },
        {
          provider: 'elevenlabs',
          text: 'ก'.repeat(96),
          audioDurationSeconds: 60,
          elapsedMilliseconds: 700,
          usdPerHour: 0.22,
          hallucinatedPhraseCount: 0,
          openingSpeechOmitted: false,
          timingErrorsMilliseconds: [50]
        }
      ]
    });

    expect(comparison.accuracyWinner).toBe('tie');
    expect(comparison.providers.map((provider) => provider.characterErrorRate)).toEqual([
      0.02,
      0.04
    ]);
  });

  it('rejects credential-like fields from benchmark data', () => {
    expect(() =>
      validateSanitizedBenchmarkValue({
        provider: 'groq',
        authorization: 'Bearer hidden'
      })
    ).toThrow(/authorization/);
    expect(() =>
      validateSanitizedBenchmarkValue({
        nested: { api_key: 'hidden' }
      })
    ).toThrow(/api_key/);
  });
});
