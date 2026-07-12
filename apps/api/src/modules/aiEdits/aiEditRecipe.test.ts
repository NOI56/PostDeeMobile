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
  segments = [],
  words = []
}: {
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
} = {}): TranscriptionResult => ({
  text: '',
  language: 'th',
  durationSeconds: 10,
  segments,
  words,
  model: 'test-whisper'
});

const buildRecipe = ({
  segments,
  words,
  capabilities,
  settings
}: {
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
  capabilities: Record<string, boolean>;
  settings?: unknown;
}) =>
  buildAiEditRecipe({
    transcript: buildTranscript({ segments, words }),
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
          { text: 'ก่อนหยุด', start: 0, end: 0 },
          { text: 'หลังหยุด', start: threshold, end: threshold + 0.2 }
        ]
      });
      const belowThreshold = buildRecipe({
        capabilities: { silence: true },
        settings: { silencePreset },
        segments: [
          { text: 'ก่อนหยุด', start: 0, end: 0 },
          {
            text: 'หลังหยุด',
            start: threshold - 0.05,
            end: threshold + 0.15
          }
        ]
      });

      expect(atThreshold.silenceRanges).toEqual([{ start: 0, end: threshold }]);
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

  it('keeps hook planned until a real renderer is available', () => {
    const recipe = buildRecipe({
      capabilities: { hook: true }
    });

    expect(recipe.capabilities.hook.state).toBe('planned');
  });

  it('omits unsupported hook render hints', () => {
    const recipe = buildRecipe({
      capabilities: { hook: true }
    });

    expect(recipe.renderHints).not.toHaveProperty('hookSeconds');
  });
});
