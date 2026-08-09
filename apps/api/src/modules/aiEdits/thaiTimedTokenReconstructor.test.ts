import { describe, expect, it } from 'vitest';

import { reconstructThaiTimedWords } from './thaiTimedTokenReconstructor.js';
import type { TranscriptWord } from './transcriptionProvider.js';

describe('reconstructThaiTimedWords', () => {
  it('returns an empty result only for an empty valid timeline', () => {
    expect(reconstructThaiTimedWords({
      segments: [],
      fragments: [],
      durationSeconds: 3
    })).toEqual([]);

    expect(reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน', start: 1, end: 2 }],
      fragments: [],
      durationSeconds: 3
    })).toBeUndefined();
  });

  it('reconstructs exact Thai character fragments inside one segment', () => {
    const semanticWords = Array.from(
      new Intl.Segmenter('th', { granularity: 'word' })
        .segment('ชุมชน ชุมชน')
    )
      .filter((part) => part.isWordLike)
      .map((part) => part.segment);
    expect(semanticWords).toEqual(['ชุมชน', 'ชุมชน']);

    expect(reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 3 }],
      durationSeconds: 3,
      fragments: [
        { word: 'ชุม', start: 1, end: 1.3 },
        { word: 'ชน', start: 1.3, end: 1.6 },
        { word: 'ชุมชน', start: 2, end: 2.6 }
      ]
    })).toEqual([
      { word: 'ชุมชน', start: 1, end: 1.6 },
      { word: 'ชุมชน', start: 2, end: 2.6 }
    ]);
  });

  it.each([
    { gap: 0.15, succeeds: true },
    { gap: 0.1501, succeeds: false }
  ])('enforces the exact 150ms fragment gap boundary: $gap', ({
    gap,
    succeeds
  }) => {
    const result = reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน', start: 1, end: 2 }],
      durationSeconds: 2,
      fragments: [
        { word: 'ชุม', start: 1, end: 1.1 },
        { word: 'ชน', start: 1.1 + gap, end: 1.7 }
      ]
    });

    expect(result !== undefined).toBe(succeeds);
  });

  it.each([
    {
      name: 'fragment gap over 150ms',
      fragments: [
        { word: 'ชุม', start: 1, end: 1.1 },
        { word: 'ชน', start: 1.26, end: 1.6 },
        { word: 'มาก', start: 2, end: 2.3 }
      ]
    },
    {
      name: 'backwards timing',
      fragments: [
        { word: 'ชุม', start: 1.2, end: 1.3 },
        { word: 'ชน', start: 1.1, end: 1.4 },
        { word: 'มาก', start: 2, end: 2.3 }
      ]
    },
    {
      name: 'provider token spans two words',
      fragments: [{ word: 'ชุมชน มาก', start: 1, end: 2.3 }]
    },
    {
      name: 'text mismatch',
      fragments: [
        { word: 'ชุมชล', start: 1, end: 1.6 },
        { word: 'มาก', start: 2, end: 2.3 }
      ]
    }
  ] satisfies Array<{ name: string; fragments: TranscriptWord[] }>) (
    'fails closed for $name',
    ({ fragments }) => {
      expect(reconstructThaiTimedWords({
        segments: [{ text: 'ชุมชน มาก', start: 1, end: 3 }],
        durationSeconds: 3,
        fragments
      })).toBeUndefined();
    }
  );

  it('keeps whitespace between semantic words untimed', () => {
    expect(reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน   มาก', start: 1, end: 3 }],
      durationSeconds: 3,
      fragments: [
        { word: ' ชุมชน ', start: 1, end: 1.4 },
        { word: 'มาก', start: 2.2, end: 2.6 }
      ]
    })).toEqual([
      { word: 'ชุมชน', start: 1, end: 1.4 },
      { word: 'มาก', start: 2.2, end: 2.6 }
    ]);
  });

  it('matches canonically equivalent Unicode after NFC normalization', () => {
    expect(reconstructThaiTimedWords({
      segments: [{ text: 'คาเฟe\u0301', start: 0, end: 1 }],
      durationSeconds: 1,
      fragments: [{ word: 'คาเฟé', start: 0.1, end: 0.8 }]
    })).toEqual([{ word: 'คาเฟé', start: 0.1, end: 0.8 }]);
  });

  it('rejects Thai lookalikes that are not equal after NFC normalization', () => {
    expect(reconstructThaiTimedWords({
      segments: [{ text: 'กำ', start: 0, end: 1 }],
      durationSeconds: 1,
      fragments: [{ word: 'กํา', start: 0.1, end: 0.8 }]
    })).toBeUndefined();
  });

  it.each(['ฯ', '.', '?']) (
    'attaches exact %s punctuation even when the provider omits its timing',
    (mark) => {
      expect(reconstructThaiTimedWords({
        segments: [{ text: `ชุมชน${mark}`, start: 1, end: 2 }],
        durationSeconds: 2,
        fragments: [{ word: 'ชุมชน', start: 1, end: 1.5 }]
      })).toEqual([{ word: `ชุมชน${mark}`, start: 1, end: 1.5 }]);
    }
  );

  it('accepts punctuation attached to or separated from the provider word', () => {
    expect(reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน?', start: 1, end: 2 }],
      durationSeconds: 2,
      fragments: [{ word: 'ชุมชน?', start: 1, end: 1.5 }]
    })).toEqual([{ word: 'ชุมชน?', start: 1, end: 1.5 }]);

    expect(reconstructThaiTimedWords({
      segments: [{ text: 'ชุมชน?', start: 1, end: 2 }],
      durationSeconds: 2,
      fragments: [
        { word: 'ชุมชน', start: 1, end: 1.4 },
        { word: '?', start: 1.45, end: 1.5 }
      ]
    })).toEqual([{ word: 'ชุมชน?', start: 1, end: 1.5 }]);
  });

  it.each([
    [{ word: 'ชุมชน!', start: 1, end: 1.5 }],
    [
      { word: 'ชุมชน', start: 1, end: 1.4 },
      { word: '!', start: 1.45, end: 1.5 }
    ]
  ] satisfies TranscriptWord[][]) (
    'rejects mismatched or excess provider punctuation',
    (fragments) => {
      expect(reconstructThaiTimedWords({
        segments: [{ text: 'ชุมชน?', start: 1, end: 2 }],
        durationSeconds: 2,
        fragments
      })).toBeUndefined();
    }
  );

  it('never consumes fragments across a segment boundary', () => {
    expect(reconstructThaiTimedWords({
      segments: [
        { text: 'ชุมชน', start: 1, end: 1.5 },
        { text: 'มาก', start: 1.5, end: 2.5 }
      ],
      durationSeconds: 3,
      fragments: [
        { word: 'ชุม', start: 1, end: 1.2 },
        { word: 'ชน', start: 1.25, end: 1.6 },
        { word: 'มาก', start: 1.7, end: 2.3 }
      ]
    })).toBeUndefined();
  });

  it.each([
    {
      name: 'negative fragment start',
      segments: [{ text: 'ชุมชน', start: 0, end: 1 }],
      fragments: [{ word: 'ชุมชน', start: -0.1, end: 0.5 }],
      durationSeconds: 1
    },
    {
      name: 'fragment beyond duration',
      segments: [{ text: 'ชุมชน', start: 0, end: 1 }],
      fragments: [{ word: 'ชุมชน', start: 0.1, end: 1.1 }],
      durationSeconds: 1
    },
    {
      name: 'segment beyond duration',
      segments: [{ text: 'ชุมชน', start: 0, end: 2 }],
      fragments: [{ word: 'ชุมชน', start: 0.1, end: 0.9 }],
      durationSeconds: 1
    },
    {
      name: 'overlapping segments',
      segments: [
        { text: 'ชุมชน', start: 0, end: 1 },
        { text: 'มาก', start: 0.9, end: 2 }
      ],
      fragments: [
        { word: 'ชุมชน', start: 0.1, end: 0.8 },
        { word: 'มาก', start: 1, end: 1.8 }
      ],
      durationSeconds: 2
    }
  ])('fails closed for $name', ({ segments, fragments, durationSeconds }) => {
    expect(reconstructThaiTimedWords({
      segments,
      fragments,
      durationSeconds
    })).toBeUndefined();
  });
});
