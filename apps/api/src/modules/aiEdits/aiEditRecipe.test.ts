import { describe, expect, it } from 'vitest';

import {
  buildAiEditRecipe,
  readAiEditCapabilities,
  readAiEditRecipeSettings
} from './aiEditRecipe.js';
import type {
  TranscriptSegment,
  TranscriptWord,
  TranscriptionResult
} from './transcriptionProvider.js';

const buildTranscript = ({
  text = '',
  segments = [],
  words = [],
  language = 'th',
  durationSeconds
}: {
  text?: string;
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
  language?: string;
  durationSeconds?: number;
} = {}): TranscriptionResult => ({
  text,
  language,
  durationSeconds: durationSeconds ?? Math.max(
    0,
    ...segments.map((segment) => segment.end),
    ...words.map((word) => word.end)
  ),
  segments,
  words,
  model: 'test-whisper'
});

const buildRecipe = ({
  text,
  segments,
  words,
  language,
  durationSeconds,
  capabilities,
  settings
}: {
  text?: string;
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
  language?: string;
  durationSeconds?: number;
  capabilities: Record<string, boolean>;
  settings?: unknown;
}) =>
  buildAiEditRecipe({
    transcript: buildTranscript({ text, segments, words, language, durationSeconds }),
    capabilities: readAiEditCapabilities({
      subtitle: false,
      silence: false,
      filler: false,
      hook: false,
      ...capabilities
    }),
    settings: readAiEditRecipeSettings(settings)
  });

describe('AI edit recipe pacing settings', () => {
  it.each([
    ['natural', 1],
    ['balanced', 0.6],
    ['compact', 0.4]
  ])(
    'uses the %s silence preset threshold of %s seconds',
    (silencePreset, threshold) => {
      const atThreshold = buildRecipe({
        capabilities: { silence: true },
        settings: { silencePreset },
        segments: [
          { text: 'ก่อนหยุด', start: 0, end: 0.1 },
          { text: 'หลังหยุด', start: threshold + 0.1, end: threshold + 0.3 }
        ]
      });
      const belowThreshold = buildRecipe({
        capabilities: { silence: true },
        settings: { silencePreset },
        segments: [
          { text: 'ก่อนหยุด', start: 0, end: 0.1 },
          {
            text: 'หลังหยุด',
            start: threshold + 0.05,
            end: threshold + 0.25
          }
        ]
      });

      expect(atThreshold.silenceRanges).toEqual([
        { start: 0.1, end: threshold + 0.1 }
      ]);
      expect(belowThreshold.silenceRanges).toEqual([]);
    }
  );

  it('keeps the missing silence preset backward compatible with balanced', () => {
    const segments = [
      { text: 'ช่วงแรก', start: 0, end: 1 },
      { text: 'เว้นสั้น', start: 1.5, end: 2 },
      { text: 'เว้นสมดุล', start: 2.75, end: 3 },
      { text: 'เว้นยาว', start: 4, end: 5 }
    ];
    const withoutPreset = buildRecipe({
      capabilities: { silence: true },
      segments
    });
    const balanced = buildRecipe({
      capabilities: { silence: true },
      settings: { silencePreset: 'balanced' },
      segments
    });

    expect(withoutPreset.silenceRanges).toEqual([
      { start: 2, end: 2.75 },
      { start: 3, end: 4 }
    ]);
    expect(withoutPreset.silenceRanges).toEqual(balanced.silenceRanges);
  });

  it('uses valid word timings to find silence inside continuous transcript segments', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      segments: [
        { text: 'ช่วงแรก', start: 0, end: 0.9 },
        { text: 'ช่วงต่อมา', start: 0.9, end: 1.8 }
      ],
      words: [
        { word: 'ช่วงแรก', start: 0, end: 0.5 },
        { word: 'ช่วงต่อมา', start: 1.2, end: 1.8 }
      ]
    });

    expect(recipe.silenceRanges).toEqual([{ start: 0.5, end: 1.2 }]);
  });

  it('uses fragmented Thai timings for silence but keeps segment subtitles', () => {
    const segments = [{ text: 'สวัสดีครับ', start: 0, end: 1.55 }];
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      language: 'Thai',
      segments,
      words: [
        { word: 'ส', start: 0, end: 0.1 },
        { word: 'ว', start: 0.1, end: 0.2 },
        { word: 'ั', start: 0.2, end: 0.25 },
        { word: 'ส', start: 0.25, end: 0.35 },
        { word: 'ด', start: 0.35, end: 0.45 },
        { word: 'ี', start: 0.45, end: 0.55 },
        { word: 'ค', start: 1.2, end: 1.3 },
        { word: 'ร', start: 1.3, end: 1.4 },
        { word: 'ั', start: 1.4, end: 1.45 },
        { word: 'บ', start: 1.45, end: 1.55 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual(segments);
    expect(recipe.silenceRanges).toEqual([{ start: 0.55, end: 1.2 }]);
  });

  it('rebuilds readable Thai subtitle words from fragmented provider timings', () => {
    const text = 'จนกระทั่งแทบจะไม่มีที่เดินสำหรับคน';
    const tokens = Array.from(text);
    const durationSeconds = 3.2;
    const words = tokens.map((word, index) => ({
      word,
      start: index * durationSeconds / tokens.length,
      end: (index + 1) * durationSeconds / tokens.length
    }));
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds,
      settings: { subtitleWordsPerLine: 2 },
      segments: [{ text, start: 0, end: durationSeconds }],
      words
    });

    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe(text);
    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
    expect(recipe.subtitles.segments).not.toContainEqual(
      expect.objectContaining({ text: expect.stringMatching(/เดิ$/u) })
    );
    expect(recipe.subtitles.segments).not.toContainEqual(
      expect.objectContaining({ text: expect.stringMatching(/^นสำหรับ/u) })
    );
    expect(
      recipe.subtitles.segments.every(
        (segment) => segment.end - segment.start >= 0.7 - Number.EPSILON
      )
    ).toBe(true);
  });

  it('splits long Thai fallback segments when word timings are unavailable', () => {
    const text =
      'ที่รู้อยู่ว่ากรุงเทพมีรถเยอะเกินไปจนแทบไม่มีที่เดินสำหรับคน';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 8.3,
      settings: { subtitleWordsPerLine: 4 },
      segments: [{ text, start: 0, end: 8.3 }],
      words: []
    });

    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe(text);
    expect(
      recipe.subtitles.segments.every(
        (segment) => segment.end - segment.start <= 4
      )
    ).toBe(true);
  });

  it('merges provider subtitle fragments that are too short to read', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text: 'เช่นช่วงเสาร์อาทิตย์',
      durationSeconds: 1.2,
      segments: [
        { text: 'เช่น', start: 0, end: 0.18 },
        { text: 'ช่วงเสาร์อาทิตย์', start: 0.18, end: 1.2 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'เช่นช่วงเสาร์อาทิตย์', start: 0, end: 1.2 }
    ]);
  });

  it('groups semantic Thai words into readable-duration subtitle cues', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      settings: { subtitleWordsPerLine: 2 },
      segments: [{ text: 'มีดีมาไปดูของใหม่นะ', start: 0, end: 1.6 }],
      words: [
        { word: 'มี', start: 0, end: 0.2 },
        { word: 'ดี', start: 0.2, end: 0.4 },
        { word: 'มา', start: 0.4, end: 0.6 },
        { word: 'ไป', start: 0.6, end: 0.8 },
        { word: 'ดู', start: 0.8, end: 1 },
        { word: 'ของ', start: 1, end: 1.2 },
        { word: 'ใหม่', start: 1.2, end: 1.4 },
        { word: 'นะ', start: 1.4, end: 1.6 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'มีดีมาไป', start: 0, end: 0.8 },
      { text: 'ดูของใหม่นะ', start: 0.8, end: 1.6 }
    ]);
  });

  it('omits low-confidence and leaked prompt ranges from rendered subtitles', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      settings: { subtitleWordsPerLine: 2 },
      text:
        'Good intro garbled words ชื่อแอปให้เขียนเป็นภาษาไทยว่า โพสต์ดี',
      durationSeconds: 6,
      segments: [
        {
          text: 'Good intro',
          start: 0,
          end: 2,
          avgLogprob: -0.2,
          noSpeechProbability: 0.01,
          compressionRatio: 1.1
        },
        {
          text: 'garbled words',
          start: 2,
          end: 4,
          avgLogprob: -1.4,
          noSpeechProbability: 0.1,
          compressionRatio: 1.2
        },
        {
          text: 'ชื่อแอปให้เขียนเป็นภาษาไทยว่า โพสต์ดี',
          start: 4,
          end: 6,
          avgLogprob: -0.1,
          noSpeechProbability: 0.01,
          compressionRatio: 1.1
        }
      ],
      words: [
        { word: 'Good', start: 0, end: 1 },
        { word: 'intro', start: 1, end: 2 },
        { word: 'garbled', start: 2, end: 3 },
        { word: 'words', start: 3, end: 4 },
        {
          word: 'ชื่อแอปให้เขียนเป็นภาษาไทยว่า โพสต์ดี',
          start: 4,
          end: 6
        }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'Good intro', start: 0, end: 2 }
    ]);
  });

  it('recognizes a short Thai character-token stream as fragmented', () => {
    const segments = [{ text: 'เออครับนะ', start: 0, end: 0.9 }];
    const recipe = buildRecipe({
      capabilities: { subtitle: true, filler: true },
      language: 'Thai',
      settings: { subtitleWordsPerLine: 2, fillerWords: ['เอ่อ'] },
      segments,
      words: [
        { word: 'เอ', start: 0, end: 0.1 },
        { word: 'อ', start: 0.1, end: 0.2 },
        { word: 'ค', start: 0.4, end: 0.5 },
        { word: 'ร', start: 0.5, end: 0.6 },
        { word: 'ั', start: 0.6, end: 0.65 },
        { word: 'บ', start: 0.65, end: 0.75 },
        { word: 'นะ', start: 0.75, end: 0.9 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual(segments);
    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.2 }]);
  });

  it('does not treat a long numeric token stream as fragmented Thai', () => {
    const words = Array.from('123456789012', (word, index) => ({
      word,
      start: index * 0.1,
      end: (index + 1) * 0.1
    }));
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      settings: { subtitleWordsPerLine: 2 },
      segments: [{ text: '123456789012', start: 0, end: 1.2 }],
      words
    });

    expect(recipe.subtitles.segments).toHaveLength(1);
    expect(recipe.subtitles.segments[0]?.text).toBe('12 34 56 78 90 12');
    expect(recipe.subtitles.segments[0]?.start).toBe(0);
    expect(recipe.subtitles.segments[0]?.end).toBeCloseTo(1.2);
  });

  it.each([
    ['character', 'กดราคา', ['ก', 'ด', 'ร', 'า', 'ค', 'า']],
    ['grapheme', 'สวัสดี', ['ส', 'วั', 'ส', 'ดี']]
  ])('uses readable segments for a Thai %s-token stream', (_, text, tokens) => {
    const words = tokens.map((word, index) => ({
      word,
      start: index * 0.1,
      end: (index + 1) * 0.1
    }));
    const segments = [{ text, start: 0, end: tokens.length * 0.1 }];
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      segments,
      words
    });

    expect(recipe.subtitles.segments).toEqual(segments);
  });

  it('detects silence at the start and end of the transcript timeline', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds: 3,
      segments: [{ text: 'สวัสดี', start: 0.8, end: 2 }],
      words: [{ word: 'สวัสดี', start: 0.8, end: 2 }]
    });

    expect(recipe.silenceRanges).toEqual([
      { start: 0, end: 0.8 },
      { start: 2, end: 3 }
    ]);
  });

  it('does not cut transcript-covered edges when word timing uses tolerance', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds: 3,
      segments: [{ text: 'พูดตลอดช่วง', start: 0, end: 3 }],
      words: [{ word: 'พูดตลอดช่วง', start: 1, end: 2 }]
    });

    expect(recipe.silenceRanges).toEqual([]);
  });

  it('rejects word timings from a different transcript timeline', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds: 12,
      text: 'ab',
      segments: [{ text: 'ab', start: 5, end: 6 }],
      words: [
        { word: 'a', start: 0, end: 0.5 },
        { word: 'b', start: 10, end: 10.5 }
      ]
    });

    expect(recipe.silenceRanges).toEqual([
      { start: 0, end: 5 },
      { start: 6, end: 12 }
    ]);
  });

  it('rejects word timings that straddle outside segment edges', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds: 12,
      text: 'ab',
      segments: [{ text: 'ab', start: 5, end: 6 }],
      words: [
        { word: 'a', start: 4, end: 4.2 },
        { word: 'b', start: 6.8, end: 7 }
      ]
    });

    expect(recipe.silenceRanges).toEqual([
      { start: 0, end: 5 },
      { start: 6, end: 12 }
    ]);
  });

  it('does not trim edges from partial words when no segments exist', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds: 3,
      language: 'en',
      text: 'abcde',
      words: [{ word: 'abcd', start: 1, end: 2 }]
    });

    expect(recipe.silenceRanges).toEqual([]);
  });

  it.each([
    ['zero-length', 10, [{ text: 'เวลาศูนย์', start: 0, end: 0 }]],
    ['outside-duration', 3, [{ text: 'อยู่นอกคลิป', start: 5, end: 6 }]]
  ])('does not cut from an invalid %s segment', (_, durationSeconds, segments) => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      durationSeconds,
      segments
    });

    expect(recipe.silenceRanges).toEqual([]);
  });

  it('fails silence detection closed when transcript segments were dropped', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      durationSeconds: 3,
      text: 'ช่วงแรกช่วงท้าย',
      segments: [
        { text: 'ช่วงแรก', start: 0, end: 1 },
        { text: 'ช่วงท้าย', start: 2, end: 2 }
      ],
      words: [{ word: 'ช่วงแรก', start: 0, end: 1 }]
    });

    expect(recipe.silenceRanges).toEqual([]);
    expect(recipe.subtitles.segments).toEqual([
      { text: 'ช่วงแรก', start: 0, end: 1 }
    ]);
  });

  it('does not report silence inside overlapping timing ranges', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      segments: [
        { text: 'ช่วงหลัก', start: 0, end: 10 },
        { text: 'ซ้อนหนึ่ง', start: 1, end: 2 },
        { text: 'ซ้อนสอง', start: 5, end: 6 },
        { text: 'ซ้อนสาม', start: 9, end: 10 }
      ],
      words: [
        { word: 'ช่วงหลัก', start: 0, end: 10 },
        { word: 'ซ้อนหนึ่ง', start: 1, end: 2 },
        { word: 'ซ้อนสอง', start: 5, end: 6 },
        { word: 'ซ้อนสาม', start: 9, end: 10 }
      ]
    });

    expect(recipe.silenceRanges).toEqual([]);
    expect(recipe.subtitles.segments).toEqual([
      { text: 'ช่วงหลัก', start: 0, end: 10 },
      { text: 'ซ้อนหนึ่ง', start: 1, end: 2 },
      { text: 'ซ้อนสอง', start: 5, end: 6 },
      { text: 'ซ้อนสาม', start: 9, end: 10 }
    ]);
  });

  it('ignores empty segment placeholders when valid words are available', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      segments: [{ text: '', start: 0, end: 0 }],
      words: [
        { word: 'ส', start: 0, end: 0.1 },
        { word: 'ว', start: 0.1, end: 0.2 },
        { word: 'ั', start: 0.2, end: 0.25 },
        { word: 'ส', start: 0.25, end: 0.35 },
        { word: 'ด', start: 0.35, end: 0.45 },
        { word: 'ี', start: 0.45, end: 0.55 }
      ]
    });

    expect(recipe.subtitles.segments).not.toEqual([{ text: '', start: 0, end: 0 }]);
    expect(recipe.subtitles.segments.map((segment) => segment.text).join('')).toBe(
      'สวัสดี'
    );
  });

  it('falls back to segments when valid word timings cover only part of the transcript', () => {
    const segments = [
      { text: 'สวัสดีค่ะ', start: 0, end: 2 },
      { text: 'ราคา 99 บาท', start: 4, end: 7 },
      { text: 'กดตะกร้าได้เลย', start: 10, end: 13 }
    ];
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      segments,
      words: [
        { word: 'ราคา', start: 4, end: 4.4 },
        { word: '99', start: 4.5, end: 4.8 },
        { word: 'บาท', start: 4.9, end: 5.2 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual(segments);
    expect(recipe.silenceRanges).toEqual([
      { start: 2, end: 4 },
      { start: 7, end: 10 }
    ]);
  });

  it('falls back when word timings reach both ends but omit most transcript text', () => {
    const segments = [
      { text: 'หนึ่ง สอง สาม สี่ ห้า', start: 0, end: 4 }
    ];
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      segments,
      words: [
        { word: 'หนึ่ง', start: 0, end: 0.5 },
        { word: 'ห้า', start: 3.5, end: 4 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual(segments);
    expect(recipe.silenceRanges).toEqual([]);
  });

  it('falls back to transcript segments when word timings are invalid', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      segments: [
        { text: 'ก่อนหยุด', start: 0, end: 1 },
        { text: 'หลังหยุด', start: 1.8, end: 2.5 }
      ],
      words: [{ word: 'เวลาผิด', start: 0.5, end: 0.5 }]
    });

    expect(recipe.silenceRanges).toEqual([{ start: 1, end: 1.8 }]);
  });

  it('groups Thai word timings into subtitle lines without inserting spaces', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      settings: { subtitleWordsPerLine: 2 },
      words: [
        { word: 'สวัสดี', start: 0, end: 0.4 },
        { word: 'ค่ะ', start: 0.4, end: 0.7 },
        { word: 'วันนี้', start: 0.8, end: 1.2 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'สวัสดีค่ะวันนี้', start: 0, end: 1.2 }
    ]);
  });

  it('keeps spaces around Latin product names and numbers in Thai subtitles', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'th',
      settings: { subtitleWordsPerLine: 4 },
      words: [
        { word: 'รุ่น', start: 0, end: 0.3 },
        { word: 'iPhone', start: 0.3, end: 0.7 },
        { word: '15', start: 0.7, end: 0.9 },
        { word: 'Pro', start: 0.9, end: 1.2 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'รุ่น iPhone 15 Pro', start: 0, end: 1.2 }
    ]);
  });

  it.each(['99.50', '1,299'])(
    'keeps spaces around the formatted Thai price %s',
    (price) => {
      const recipe = buildRecipe({
        capabilities: { subtitle: true },
        language: 'th',
        settings: { subtitleWordsPerLine: 3 },
        words: [
          { word: 'ราคา', start: 0, end: 0.3 },
          { word: price, start: 0.3, end: 0.7 },
          { word: 'บาท', start: 0.7, end: 1 }
        ]
      });

      expect(recipe.subtitles.segments).toEqual([
        { text: `ราคา ${price} บาท`, start: 0, end: 1 }
      ]);
    }
  );

  it.each(['Thai', 'tha', 'th-TH', 'th_TH'])(
    'recognizes the %s language alias as Thai',
    (language) => {
      const recipe = buildRecipe({
        capabilities: { subtitle: true },
        language,
        settings: { subtitleWordsPerLine: 2 },
        words: [
          { word: 'สวัสดี', start: 0, end: 0.4 },
          { word: 'ค่ะ', start: 0.4, end: 0.7 }
        ]
      });

      expect(recipe.subtitles.segments).toEqual([
        { text: 'สวัสดีค่ะ', start: 0, end: 0.7 }
      ]);
    }
  );

  it('groups non-Thai word timings into subtitle lines with spaces', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      settings: { subtitleWordsPerLine: 2 },
      language: 'en',
      words: [
        { word: 'Hello', start: 0, end: 0.4 },
        { word: 'world', start: 0.4, end: 0.8 },
        { word: 'again', start: 0.9, end: 1.3 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([
      { text: 'Hello world again', start: 0, end: 1.3 }
    ]);
  });

  it('falls back to transcript segments for subtitles when word timings are invalid', () => {
    const segments = [{ text: 'ใช้ซับเดิม', start: 0, end: 1 }];
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      segments,
      words: [{ word: 'เวลาผิด', start: 0.5, end: 0.5 }]
    });

    expect(recipe.subtitles.segments).toEqual(segments);
  });

  it('uses only supported filler words selected by the request', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['อ่า', 'สินค้า', 42, null] },
      words: [
        { word: 'อ่า', start: 0, end: 0.3 },
        { word: 'สินค้า', start: 0.4, end: 0.9 },
        { word: 'แบบว่า', start: 1, end: 1.4 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.3 }]);
  });

  it('matches normalized filler words exactly without cutting longer words', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['อ่า'] },
      words: [
        { word: '  อ่า! ', start: 0, end: 0.3 },
        { word: 'อ่าง', start: 0.4, end: 0.8 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.3 }]);
  });

  it("matches the exact 'เออ' transcription alias for the 'เอ่อ' filler", () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['เอ่อ'] },
      words: [
        { word: 'เออ', start: 0, end: 0.2 },
        { word: 'เออแล้ว', start: 0.3, end: 0.7 },
        { word: 'เอ่อ', start: 0.8, end: 1 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([
      { start: 0, end: 0.2 },
      { start: 0.8, end: 1 }
    ]);
  });

  it('reassembles fragmented Thai tokens to find supported filler phrases', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text: 'ก เออ วัน แบบว่า ส',
      settings: { fillerWords: ['เอ่อ', 'แบบว่า'] },
      words: [
        { word: 'ก', start: 0, end: 0.1 },
        { word: 'เอ', start: 0.5, end: 0.6 },
        { word: 'อ', start: 0.6, end: 0.62 },
        { word: 'ว', start: 0.62, end: 0.72 },
        { word: 'ั', start: 0.72, end: 0.74 },
        { word: 'น', start: 0.74, end: 0.84 },
        { word: 'แ', start: 1.5, end: 1.6 },
        { word: 'บ', start: 1.6, end: 1.62 },
        { word: 'บ', start: 1.62, end: 1.64 },
        { word: 'ว', start: 1.64, end: 1.74 },
        { word: '่', start: 1.74, end: 1.76 },
        { word: 'า', start: 1.76, end: 1.82 },
        { word: 'ส', start: 1.82, end: 1.92 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([
      { start: 0.5, end: 0.62 },
      { start: 1.5, end: 1.82 }
    ]);
  });

  it('ignores Groq whitespace tokens while validating fragmented fillers', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text: 'เอ่อ วันนี้ แบบว่า สินค้า',
      settings: { fillerWords: ['เอ่อ', 'แบบว่า'] },
      segments: [
        { text: 'เอ่อ วันนี้', start: 0, end: 0.8 },
        { text: 'แบบว่า สินค้า', start: 1.5, end: 2.3 }
      ],
      words: [
        { word: 'เอ', start: 0, end: 0.1 },
        { word: '่', start: 0.1, end: 0.12 },
        { word: 'อ', start: 0.12, end: 0.2 },
        { word: ' ', start: 0.2, end: 0.25 },
        { word: 'วันนี้', start: 0.25, end: 0.8 },
        { word: 'แ', start: 1.5, end: 1.6 },
        { word: 'บ', start: 1.6, end: 1.62 },
        { word: 'บ', start: 1.62, end: 1.64 },
        { word: 'ว', start: 1.64, end: 1.74 },
        { word: '่', start: 1.74, end: 1.76 },
        { word: 'า', start: 1.76, end: 1.82 },
        { word: ' ', start: 1.82, end: 1.86 },
        { word: 'สินค้า', start: 1.86, end: 2.3 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([
      { start: 0, end: 0.2 },
      { start: 1.5, end: 1.82 }
    ]);
  });

  it('uses Thai text boundaries to find a short fragmented filler without timing gaps', () => {
    const text = 'วันนี้ เอ่อ สินค้า';
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text,
      settings: { fillerWords: ['เอ่อ'] },
      segments: [{ text, start: 0, end: 1 }],
      words: [
        { word: 'วันนี้', start: 0, end: 0.4 },
        { word: 'เอ', start: 0.4, end: 0.5 },
        { word: '่', start: 0.5, end: 0.52 },
        { word: 'อ', start: 0.52, end: 0.6 },
        { word: 'สินค้า', start: 0.6, end: 1 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0.4, end: 0.6 }]);
  });

  it('does not cut short filler prefixes from a continuous fragmented Thai word', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      settings: { fillerWords: ['เอ่อ', 'อ่า'] },
      words: [
        { word: 'เอ', start: 0, end: 0.1 },
        { word: 'อ', start: 0.1, end: 0.2 },
        { word: 'แ', start: 0.2, end: 0.3 },
        { word: 'ล', start: 0.3, end: 0.4 },
        { word: '้', start: 0.4, end: 0.45 },
        { word: 'ว', start: 0.45, end: 0.55 },
        { word: 'อ่', start: 0.55, end: 0.65 },
        { word: 'า', start: 0.65, end: 0.7 },
        { word: 'ง', start: 0.7, end: 0.8 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([]);
  });

  it('finds a fragmented filler at the transcript start when text has a boundary', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text: 'เออ ครับ',
      settings: { fillerWords: ['เอ่อ'] },
      segments: [{ text: 'เออ ครับ', start: 0, end: 0.55 }],
      words: [
        { word: 'เอ', start: 0, end: 0.1 },
        { word: 'อ', start: 0.1, end: 0.2 },
        { word: 'ค', start: 0.2, end: 0.3 },
        { word: 'ร', start: 0.3, end: 0.4 },
        { word: 'ั', start: 0.4, end: 0.45 },
        { word: 'บ', start: 0.45, end: 0.55 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.2 }]);
  });

  it('does not reassemble a filler phrase across a large timing gap', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      settings: { fillerWords: ['เอ่อ'] },
      segments: [{ text: 'กเออครับ', start: 0, end: 1.95 }],
      words: [
        { word: 'ก', start: 0, end: 0.1 },
        { word: 'เอ', start: 0.5, end: 0.6 },
        { word: 'อ', start: 1.5, end: 1.6 },
        { word: 'ค', start: 1.6, end: 1.7 },
        { word: 'ร', start: 1.7, end: 1.8 },
        { word: 'ั', start: 1.8, end: 1.85 },
        { word: 'บ', start: 1.85, end: 1.95 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([]);
  });

  it('does not cut a filler phrase assembled across real Thai word boundaries', () => {
    const text = 'รูปแบบว่ายน้ำ';
    const words = Array.from(text, (word, index) => ({
      word,
      start: index * 0.1,
      end: (index + 1) * 0.1
    }));
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text,
      settings: { fillerWords: ['แบบว่า'] },
      segments: [{ text, start: 0, end: words.length * 0.1 }],
      words
    });

    expect(recipe.fillerRanges).toEqual([]);
  });

  it('does not cut a fragmented filler substring when only one timing boundary exists', () => {
    const text = 'รูปแบบว่ายน้ำ';
    const words = Array.from(text, (word, index) => {
      const gapAfterSubstring = index > 8 ? 0.1 : 0;
      return {
        word,
        start: index * 0.05 + gapAfterSubstring,
        end: (index + 1) * 0.05 + gapAfterSubstring
      };
    });
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text,
      settings: { fillerWords: ['แบบว่า'] },
      segments: [{ text, start: 0, end: words.at(-1)!.end }],
      words
    });

    expect(recipe.fillerRanges).toEqual([]);
  });

  it('never creates filler ranges from invalid negative timings', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['อ่า'] },
      words: [
        { word: 'อ่า', start: -1, end: 0.2 },
        { word: 'สินค้า', start: 0.2, end: 0.8 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([]);
    expect(recipe.cutRanges).toEqual([]);
  });

  it('keeps the missing filler allowlist backward compatible', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      words: [
        { word: 'เอ่อ', start: 0, end: 0.2 },
        { word: 'อ่า', start: 0.3, end: 0.5 },
        { word: 'แบบว่า', start: 0.6, end: 0.9 },
        { word: 'คือว่า', start: 1, end: 1.3 },
        { word: 'ประมาณว่า', start: 1.4, end: 1.8 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([
      { start: 0, end: 0.2 },
      { start: 0.3, end: 0.5 },
      { start: 0.6, end: 0.9 },
      { start: 1, end: 1.3 },
      { start: 1.4, end: 1.8 }
    ]);
  });

  it.each([
    ['empty', []],
    ['invalid', ['สินค้า', '', 42, null]]
  ])('fails closed for an %s filler allowlist', (_, fillerWords) => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords },
      words: [
        { word: 'อ่า', start: 0, end: 0.3 },
        { word: 'สินค้า', start: 0.4, end: 0.9 }
      ]
    });

    expect(recipe.fillerRanges).toEqual([]);
  });

  it('marks enabled silence and filler as hinted when nothing was found', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true, filler: true },
      segments: [{ text: 'พูดต่อเนื่อง', start: 0, end: 2 }],
      words: [{ word: 'พูดต่อเนื่อง', start: 0, end: 2 }]
    });

    expect(recipe.silenceRanges).toEqual([]);
    expect(recipe.fillerRanges).toEqual([]);
    expect(recipe.capabilities.silence.state).toBe('hinted');
    expect(recipe.capabilities.filler.state).toBe('hinted');
  });

  it.each([
    'hook',
    'beatsync',
    'reframe',
    'zoom',
    'sfx',
    'audio',
    'translate',
    'pricetag',
    'cta',
    'watermark'
  ] as const)('keeps %s planned until a real renderer is available', (capability) => {
    const recipe = buildRecipe({
      capabilities: { [capability]: true }
    });

    expect(recipe.capabilities[capability].state).toBe('planned');
  });

  it('omits unsupported hook render hints', () => {
    const recipe = buildRecipe({
      capabilities: { hook: true }
    });

    expect(recipe.renderHints).not.toHaveProperty('hookSeconds');
  });
});
