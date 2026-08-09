import { describe, expect, it } from 'vitest';

import {
  attachValidatedSubtitleWords,
  buildAiEditPlanningSegments,
  buildAiEditRecipe,
  readAiEditCapabilities,
  readAiEditRecipeSettings,
  readStrictTranscriptEvidence
} from './aiEditRecipe.js';
import type { EditPlanResult } from './editPlanProvider.js';
import type { SoundEffectPlanResult } from './soundEffectPlanProvider.js';
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
  durationSeconds,
  timingIntegrity = 'trusted',
  hasTimedAudioEvents = false
}: {
  text?: string;
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
  language?: string;
  durationSeconds?: number;
  timingIntegrity?: 'trusted' | 'untrusted';
  hasTimedAudioEvents?: boolean;
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
  timingIntegrity,
  hasTimedAudioEvents,
  model: 'test-whisper'
});

const buildRecipe = ({
  text,
  segments,
  words,
  language,
  durationSeconds,
  timingIntegrity,
  hasTimedAudioEvents,
  capabilities,
  settings,
  hasExplicitPlanRequest,
  plan,
  soundEffectPlan
}: {
  text?: string;
  segments?: TranscriptSegment[];
  words?: TranscriptWord[];
  language?: string;
  durationSeconds?: number;
  timingIntegrity?: 'trusted' | 'untrusted';
  hasTimedAudioEvents?: boolean;
  capabilities: Record<string, boolean>;
  settings?: unknown;
  hasExplicitPlanRequest?: boolean;
  plan?: EditPlanResult;
  soundEffectPlan?: SoundEffectPlanResult;
}) =>
  buildAiEditRecipe({
    transcript: buildTranscript({
      text,
      segments,
      words,
      language,
      durationSeconds,
      timingIntegrity,
      hasTimedAudioEvents
    }),
    capabilities: readAiEditCapabilities({
      subtitle: false,
      silence: false,
      filler: false,
      hook: false,
      ...capabilities
    }),
    settings: readAiEditRecipeSettings(settings),
    hasExplicitPlanRequest: hasExplicitPlanRequest ?? false,
    plan,
    soundEffectPlan
  });

const readLegacySubtitleSegmentFields = (
  segments: Array<{ text: string; start: number; end: number }>
) =>
  segments.map(({ text, start, end }) => ({ text, start, end }));

const readThaiSemanticWords = (value: string): string[] =>
  Array.from(
    new Intl.Segmenter('th', { granularity: 'word' }).segment(value)
  )
    .filter((segment) => segment.isWordLike)
    .map((segment) => segment.segment);

const readThaiGraphemeCount = (value: string): number =>
  Array.from(
    new Intl.Segmenter('th', { granularity: 'grapheme' }).segment(value)
  ).length;

const expectSafeThaiSubtitleCues = ({
  sourceText,
  sourceStart,
  sourceEnd,
  segments
}: {
  sourceText: string;
  sourceStart: number;
  sourceEnd: number;
  segments: Array<{ text: string; start: number; end: number }>;
}) => {
  expect(segments.map((segment) => segment.text).join('')).toBe(sourceText);
  expect(segments[0]?.start).toBeCloseTo(sourceStart);
  expect(segments.at(-1)?.end).toBeCloseTo(sourceEnd);
  for (let index = 1; index < segments.length; index += 1) {
    expect(segments[index]?.start).toBeCloseTo(segments[index - 1]!.end);
  }
  expect(
    segments.every(
      (segment) =>
        readThaiSemanticWords(segment.text).length <= 5 &&
        readThaiGraphemeCount(segment.text) <= 20
    )
  ).toBe(true);

  const semanticBoundaries = new Set<string>();
  let semanticPrefix = '';
  for (const word of readThaiSemanticWords(sourceText)) {
    semanticPrefix += word;
    semanticBoundaries.add(semanticPrefix);
  }

  let subtitlePrefix = '';
  for (const segment of segments) {
    subtitlePrefix += segment.text;
    expect(semanticBoundaries.has(subtitlePrefix)).toBe(true);
  }
};

describe('AI edit capability defaults', () => {
  it('keeps every optional capability disabled when omitted', () => {
    expect(readAiEditCapabilities(undefined)).toEqual({
      subtitle: false,
      silence: false,
      filler: false,
      hook: false,
      beatsync: false,
      reframe: false,
      zoom: false,
      color: false,
      sfx: false,
      audio: false,
      translate: false,
      pricetag: false,
      cta: false,
      watermark: false
    });
  });

  it('does not enable hidden capabilities when one capability is selected', () => {
    expect(readAiEditCapabilities({ color: true })).toMatchObject({
      color: true,
      subtitle: false,
      silence: false,
      filler: false
    });
  });
});

describe('AI edit analysis outcomes', () => {
  const notRequested = {
    plan: 'not-requested',
    subtitle: 'not-requested',
    silence: 'not-requested',
    speechReduction: 'not-requested',
    sfx: 'not-requested'
  } as const;

  it('marks every outcome not requested when no analysis was selected', () => {
    expect(buildRecipe({ capabilities: {} }).analysisOutcomes)
      .toEqual(notRequested);
  });

  it('records a validated AI sound-effect selection as applied', () => {
    const soundEffectPlan: SoundEffectPlanResult = {
      soundEffects: [
        { soundId: 'attention_boop', sourceSeconds: 0 },
        { soundId: 'coin_ping', sourceSeconds: 4 }
      ],
      summary: 'เน้นช่วงเปิดและราคา',
      model: 'test-sfx-model'
    };
    const recipe = buildRecipe({
      capabilities: { sfx: true },
      soundEffectPlan
    });

    expect(recipe.soundEffects).toEqual(soundEffectPlan.soundEffects);
    expect(recipe.analysisOutcomes.sfx).toBe('succeeded');
    expect(recipe.capabilities.sfx.state).toBe('applied');
  });

  it('counts a valid empty AI sound-effect result as succeeded', () => {
    const recipe = buildRecipe({
      capabilities: { sfx: true },
      soundEffectPlan: {
        soundEffects: [],
        summary: 'ไม่ควรใส่เสียงเพิ่ม',
        model: 'test-sfx-model'
      }
    });

    expect(recipe.soundEffects).toEqual([]);
    expect(recipe.analysisOutcomes.sfx).toBe('succeeded');
    expect(recipe.capabilities.sfx.state).toBe('applied');
    expect(recipe.capabilities.sfx.message).toContain('เลือกไม่ใส่');
  });

  it('fails closed when AI sound-effect analysis is unavailable', () => {
    const recipe = buildRecipe({ capabilities: { sfx: true } });

    expect(recipe.soundEffects).toEqual([]);
    expect(recipe.analysisOutcomes.sfx).toBe('unavailable');
    expect(recipe.capabilities.sfx.state).toBe('hinted');
    expect(recipe.capabilities.sfx.message).toContain('ยังเลือก');
  });

  it('records only a usable explicit plan as succeeded', () => {
    const plan: EditPlanResult = {
      cuts: [{ start: 0, end: 1 }],
      summary: 'shortened',
      model: 'test-plan'
    };

    expect(buildRecipe({
      capabilities: {},
      hasExplicitPlanRequest: true,
      plan
    }).analysisOutcomes.plan).toBe('succeeded');
    expect(buildRecipe({
      capabilities: {},
      hasExplicitPlanRequest: true
    }).analysisOutcomes.plan).toBe('unavailable');
  });

  it('requires at least one safe subtitle segment for subtitle success', () => {
    expect(buildRecipe({
      capabilities: { subtitle: true },
      text: 'สินค้า',
      segments: [{ text: 'สินค้า', start: 0, end: 1 }],
      words: [{ word: 'สินค้า', start: 0, end: 1 }],
      durationSeconds: 1
    }).analysisOutcomes.subtitle).toBe('succeeded');

    expect(buildRecipe({
      capabilities: { subtitle: true },
      text: 'สินค้า',
      segments: [{ text: 'สินค้า', start: 0, end: 1 }],
      words: [{ word: 'สินค้า', start: 0, end: 1 }],
      durationSeconds: 1,
      timingIntegrity: 'untrusted'
    }).analysisOutcomes.subtitle).toBe('unavailable');
  });

  it('counts a safe silence analysis even when it finds no candidate', () => {
    const safe = buildRecipe({
      capabilities: { silence: true },
      text: 'สินค้า',
      segments: [{ text: 'สินค้า', start: 0, end: 1 }],
      words: [{ word: 'สินค้า', start: 0, end: 1 }],
      durationSeconds: 1
    });
    const unsafe = buildRecipe({
      capabilities: { silence: true },
      text: 'สินค้า',
      segments: [{ text: 'สินค้า', start: 0, end: 1 }],
      words: [{ word: 'สินค้า', start: 0, end: 1 }],
      durationSeconds: 1,
      timingIntegrity: 'untrusted'
    });

    expect(safe.silenceRanges).toEqual([]);
    expect(safe.analysisOutcomes.silence).toBe('succeeded');
    expect(unsafe.analysisOutcomes.silence).toBe('unavailable');
  });

  it('uses the actual repeated-speech result instead of the requested flag', () => {
    const ready = buildRecipe({
      capabilities: { filler: true },
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1 }],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.4 },
        { word: 'ชุมชน', start: 0.5, end: 1 }
      ],
      durationSeconds: 1,
      settings: { speechReductionMode: 'auto' }
    });
    const unavailable = buildRecipe({
      capabilities: { filler: true },
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1 }],
      words: [
        { word: 'ชุม', start: 0, end: 0.1 },
        { word: 'ชล', start: 0.2, end: 0.4 },
        { word: 'ชุมชน', start: 0.5, end: 1 }
      ],
      durationSeconds: 1,
      settings: { speechReductionMode: 'auto' }
    });

    expect(ready.analysisOutcomes.speechReduction).toBe('succeeded');
    expect(unavailable.analysisOutcomes.speechReduction).toBe('unavailable');
  });

  it('meters only a usable legacy fixed-filler result', () => {
    const found = buildRecipe({
      capabilities: { filler: true },
      words: [
        { word: 'เอ่อ', start: 0, end: 0.2 },
        { word: 'สินค้า', start: 0.3, end: 0.8 }
      ],
      durationSeconds: 1,
      settings: { fillerWords: ['เอ่อ'] }
    });
    const absent = buildRecipe({
      capabilities: { filler: true },
      words: [{ word: 'สินค้า', start: 0, end: 0.8 }],
      durationSeconds: 1,
      settings: { fillerWords: ['เอ่อ'] }
    });

    expect(found.fillerRanges).toEqual([{ start: 0, end: 0.2 }]);
    expect(found.analysisOutcomes.speechReduction).toBe('succeeded');
    expect(absent.fillerRanges).toEqual([]);
    expect(absent.analysisOutcomes.speechReduction).toBe('unavailable');
  });
});

describe('AI edit transcript boundary evidence', () => {
  it('repairs a Thai word split across raw transcript segments even when subtitles are off', () => {
    const recipe = buildRecipe({
      capabilities: {},
      language: 'Thai',
      text: 'ดุ๊กดิ๊กมาก',
      durationSeconds: 2,
      segments: [
        { text: 'ดุ๊ก', start: 0, end: 1 },
        { text: 'ดิ๊กมาก', start: 1, end: 2 }
      ]
    });

    expect(recipe.subtitles.enabled).toBe(false);
    expect(recipe.subtitles.segments).toEqual([]);
    expect(recipe.transcript.segments).toEqual([
      { text: 'ดุ๊ก', start: 0, end: 1 },
      { text: 'ดิ๊กมาก', start: 1, end: 2 }
    ]);
    expect(recipe.transcript.boundarySegments).toEqual([
      { text: 'ดุ๊กดิ๊กมาก', start: 0, end: 2 }
    ]);
  });

  it('fails boundary evidence closed when provider timing is untrusted', () => {
    const recipe = buildRecipe({
      capabilities: {},
      language: 'th',
      text: 'ดุ๊กดิ๊กมาก',
      durationSeconds: 2,
      timingIntegrity: 'untrusted',
      segments: [
        { text: 'ดุ๊ก', start: 0, end: 1 },
        { text: 'ดิ๊กมาก', start: 1, end: 2 }
      ]
    });

    expect(recipe.transcript.boundarySegments).toEqual([]);
  });

  it('rejects the whole boundary timeline instead of clamping an invalid segment', () => {
    const recipe = buildRecipe({
      capabilities: {},
      language: 'th',
      text: 'ช่วงแรกช่วงเวลาเกินคลิป',
      durationSeconds: 2,
      segments: [
        { text: 'ช่วงแรก', start: 0, end: 1 },
        { text: 'ช่วงเวลาเกินคลิป', start: 1, end: 999 }
      ]
    });

    expect(recipe.transcript.segments).toHaveLength(2);
    expect(recipe.transcript.boundarySegments).toEqual([]);
  });
});

describe('AI edit subtitle length settings', () => {
  it.each([1, 2, 3, 4, 5])(
    'accepts the backward-compatible %i word limit',
    (subtitleWordsPerLine) => {
      expect(
        readAiEditRecipeSettings({ subtitleWordsPerLine })
          .subtitleWordsPerLine
      ).toBe(subtitleWordsPerLine);
    }
  );

  it.each([0, 6, -1, 1.5, '3', null])(
    'rejects an explicit invalid word limit: %s',
    (subtitleWordsPerLine) => {
      expect(() =>
        readAiEditRecipeSettings({ subtitleWordsPerLine })
      ).toThrow(/subtitleWordsPerLine.*between 1 and 5/i);
    }
  );
});

describe('AI edit cached subtitle length variants', () => {
  it('builds complete safe 1/3/5-word variants from one trusted transcript', () => {
    const text = 'มาไปดูของดีราคาถูกมากนะ';
    const semanticWords = readThaiSemanticWords(text);
    const durationSeconds = semanticWords.length;
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'th',
      text,
      durationSeconds,
      settings: { subtitleWordsPerLine: 2 },
      segments: [{ text, start: 0, end: durationSeconds }],
      words: semanticWords.map((word, index) => ({
        word,
        start: index,
        end: index + 1
      }))
    });

    expect(Object.keys(recipe.subtitles.variants ?? {})).toEqual(['1', '3', '5']);
    for (const [key, maximumWords] of [
      ['1', 1],
      ['3', 3],
      ['5', 5]
    ] as const) {
      const segments = recipe.subtitles.variants?.[key] ?? [];
      expectSafeThaiSubtitleCues({
        sourceText: text,
        sourceStart: 0,
        sourceEnd: durationSeconds,
        segments
      });
      expect(
        segments.every(
          (segment) =>
            readThaiSemanticWords(segment.text).length <= maximumWords
        )
      ).toBe(true);
    }

    expect(recipe.subtitles.variants?.['1'].length)
      .toBeGreaterThan(recipe.subtitles.variants?.['3'].length ?? 0);
    expect(recipe.subtitles.variants?.['3'].length)
      .toBeGreaterThan(recipe.subtitles.variants?.['5'].length ?? 0);
    expect(
      recipe.subtitles.segments.every(
        (segment) => readThaiSemanticWords(segment.text).length <= 2
      )
    ).toBe(true);
  });

  it('omits cached subtitle variants when subtitles are disabled', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: false },
      text: 'one two three',
      language: 'en',
      durationSeconds: 3,
      segments: [{ text: 'one two three', start: 0, end: 3 }],
      words: [
        { word: 'one', start: 0, end: 1 },
        { word: 'two', start: 1, end: 2 },
        { word: 'three', start: 2, end: 3 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([]);
    expect(recipe.subtitles).not.toHaveProperty('variants');
  });
});

describe('AI edit subtitle style settings', () => {
  it('accepts validated colors and paired normalized coordinates', () => {
    const settings = readAiEditRecipeSettings({
      subtitleColor: '#a1b2c3',
      subtitleOutlineColor: '#0f1e2d',
      subtitleNormalizedX: 0.25,
      subtitleNormalizedY: 0.6,
      subtitlePosition: 'top'
    });

    expect(settings).toMatchObject({
      subtitleColor: '#A1B2C3',
      subtitleOutlineColor: '#0F1E2D',
      subtitleNormalizedX: 0.25,
      subtitleNormalizedY: 0.6
    });

    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      settings
    });

    expect(recipe.subtitles.style).toEqual({
      mode: 'bold',
      color: '#A1B2C3',
      outlineColor: '#0F1E2D',
      wordsPerLine: 2,
      normalizedX: 0.25,
      normalizedY: 0.6,
      position: 'middle'
    });
  });

  it('keeps the legacy white-on-black style and legacy position when coordinates are absent', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      settings: { subtitlePosition: 'top' }
    });

    expect(recipe.subtitles.style).toEqual({
      mode: 'bold',
      color: '#FFFFFF',
      outlineColor: '#000000',
      wordsPerLine: 2,
      position: 'top'
    });
    expect(recipe.subtitles.style).not.toHaveProperty('normalizedX');
    expect(recipe.subtitles.style).not.toHaveProperty('normalizedY');
  });

  it.each([
    ['subtitleColor', 'white'],
    ['subtitleColor', '#FFF'],
    ['subtitleOutlineColor', '#11223344'],
    ['subtitleOutlineColor', '#GG2233'],
    ['subtitleOutlineColor', ''],
    ['subtitleOutlineColor', null]
  ])('rejects an explicit invalid %s value: %s', (field, value) => {
    expect(() =>
      readAiEditRecipeSettings({ [field]: value })
    ).toThrow(new RegExp(`${field}.*#RRGGBB`, 'i'));
  });

  it.each([
    { subtitleNormalizedX: 0.5 },
    { subtitleNormalizedY: 0.5 },
    { subtitleNormalizedX: -0.01, subtitleNormalizedY: 0.5 },
    { subtitleNormalizedX: 0.5, subtitleNormalizedY: 1.01 },
    { subtitleNormalizedX: Number.NaN, subtitleNormalizedY: 0.5 },
    { subtitleNormalizedX: 0.5, subtitleNormalizedY: Number.POSITIVE_INFINITY },
    { subtitleNormalizedX: '0.5', subtitleNormalizedY: 0.5 },
    { subtitleNormalizedX: null, subtitleNormalizedY: 0.5 }
  ])('rejects invalid or unpaired normalized coordinates: $subtitleNormalizedX, $subtitleNormalizedY', (settings) => {
    expect(() => readAiEditRecipeSettings(settings)).toThrow(
      /subtitleNormalizedX.*subtitleNormalizedY.*between 0 and 1/i
    );
  });

  it('accepts normalized coordinate boundary values', () => {
    expect(
      readAiEditRecipeSettings({
        subtitleNormalizedX: 0,
        subtitleNormalizedY: 1
      })
    ).toMatchObject({
      subtitleNormalizedX: 0,
      subtitleNormalizedY: 1
    });
  });
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments))
      .toEqual(segments);
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
        (segment) => readThaiSemanticWords(segment.text).length <= 2
      )
    ).toBe(true);
  });

  it('never exceeds the requested word limit for fragmented Thai timings', () => {
    const text = 'วันนี้เราจะพาไปดูสินค้าคุณภาพดีราคาประหยัด';
    const tokens = Array.from(text);
    const durationSeconds = 0.6;
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds,
      settings: { subtitleWordsPerLine: 1 },
      segments: [{ text, start: 0, end: durationSeconds }],
      words: tokens.map((word, index) => ({
        word,
        start: index * durationSeconds / tokens.length,
        end: (index + 1) * durationSeconds / tokens.length
      }))
    });

    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe(text);
    expect(
      recipe.subtitles.segments.every(
        (segment) => readThaiSemanticWords(segment.text).length <= 1
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

  it('splits word-dense Thai fallback segments even under four seconds', () => {
    const text = 'จนกระทั่งแทบจะไม่มีที่เดินสำหรับคน';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 3.2,
      settings: { subtitleWordsPerLine: 4 },
      segments: [{ text, start: 0, end: 3.2 }],
      words: []
    });

    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe(text);
    expect(
      recipe.subtitles.segments.every((segment) => segment.text !== text)
    ).toBe(true);
  });

  it.each([1, 3, 5])(
    'never exceeds a %i-word limit for Thai fallback timing',
    (subtitleWordsPerLine) => {
      const text = 'วันนี้เราจะพาไปดูสินค้าคุณภาพดีราคาประหยัด';
      const durationSeconds = 0.6;
      const recipe = buildRecipe({
        capabilities: { subtitle: true },
        language: 'Thai',
        text,
        durationSeconds,
        settings: { subtitleWordsPerLine },
        segments: [{ text, start: 0, end: durationSeconds }],
        words: []
      });

      expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
        .toBe(text);
      expect(
        recipe.subtitles.segments.every(
          (segment) =>
            readThaiSemanticWords(segment.text).length <= subtitleWordsPerLine
        )
      ).toBe(true);
    }
  );

  it('never exceeds the requested word limit for non-Thai fallback timing', () => {
    const text = 'one two three four five';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'en',
      text,
      durationSeconds: 0.5,
      settings: { subtitleWordsPerLine: 3 },
      segments: [{ text, start: 0, end: 0.5 }],
      words: []
    });

    expect(recipe.subtitles.segments.map((segment) => segment.text).join(' '))
      .toBe(text);
    expect(
      recipe.subtitles.segments.every(
        (segment) => segment.text.split(/\s+/u).length <= 3
      )
    ).toBe(true);
  });

  it('repairs a Thai word split across stored transcript segments', () => {
    const text =
      'คะเก็บชีวิตสองข้างต่างๆก็จะมีอาหารที่ที่ส่วนใหญ่';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 120.785,
      settings: { subtitleWordsPerLine: 2 },
      segments: [
        { text: 'คะเก็บชีวิ', start: 112.912, end: 113.742 },
        { text: 'ตสองข้าง', start: 113.742, end: 114.531 },
        { text: 'ต่างๆก็จะมีอาห', start: 118.878, end: 119.843 },
        { text: 'ารที่ที่ส่วนใหญ่', start: 119.843, end: 120.785 }
      ],
      words: []
    });
    const subtitleTexts = recipe.subtitles.segments.map(
      (segment) => segment.text
    );

    expect(subtitleTexts.join('')).toBe(text);
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/ชีวิ$/u));
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/^ตสอง/u));
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/อาห$/u));
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/^าร/u));
  });

  it('rebuilds a short ElevenLabs token pair split inside a Thai word', () => {
    const text = 'ต่างๆก็จะมีอาหารที่ต้องการ';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 5.2,
      settings: { subtitleWordsPerLine: 1 },
      segments: [{ text, start: 0, end: 5.2 }],
      words: [
        { word: 'ต่างๆก็จะมีอาห', start: 0, end: 4.1 },
        { word: 'ารที่ต้องการ', start: 4.1, end: 5.2 }
      ]
    });
    const subtitleTexts = recipe.subtitles.segments.map(
      (segment) => segment.text
    );

    expect(subtitleTexts.join('')).toBe(text);
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/อาห$/u));
    expect(subtitleTexts).not.toContainEqual(expect.stringMatching(/^าร/u));
  });

  it.each([
    'ดุ๊กดิ๊ก',
    'โซเชียล',
    'ซุปเปอร์สตาร์',
    'ฮิปโปซุปเปอร์สตาร์',
    'สวนสัตว์เขาเขียว',
    'สวนสัตว์เปิดเขาเขียว'
  ])(
    'keeps the real Thai term %s in one subtitle cue',
    (text) => {
      const recipe = buildRecipe({
        capabilities: { subtitle: true },
        language: 'Thai',
        text,
        durationSeconds: 4,
        settings: { subtitleWordsPerLine: 1 },
        segments: [{ text, start: 0, end: 4 }],
        words: []
      });

      expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
        { text, start: 0, end: 4 }
      ]);
    }
  );

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

    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe('เช่นช่วงเสาร์อาทิตย์');
    expect(recipe.subtitles.segments[0]?.start).toBe(0);
    expect(recipe.subtitles.segments.at(-1)?.end).toBe(1.2);
    expect(
      recipe.subtitles.segments.every(
        (segment) => readThaiSemanticWords(segment.text).length <= 2
      )
    ).toBe(true);
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
      { text: 'มีดี', start: 0, end: 0.4 },
      { text: 'มาไป', start: 0.4, end: 0.8 },
      { text: 'ดูของ', start: 0.8, end: 1.2 },
      { text: 'ใหม่นะ', start: 1.2, end: 1.6 }
    ]);
  });

  it('caps live Thai cues when minimum-duration grouping would overfill them', () => {
    const text = 'แต่จะเป็นอาหารข้างทางต่างๆ';
    const durationSeconds = 0.6;
    const characters = Array.from(text);
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds,
      settings: { subtitleWordsPerLine: 5 },
      segments: [{ text, start: 0, end: durationSeconds }],
      words: characters.map((word, index) => ({
        word,
        start: index * durationSeconds / characters.length,
        end: (index + 1) * durationSeconds / characters.length
      }))
    });

    expectSafeThaiSubtitleCues({
      sourceText: text,
      sourceStart: 0,
      sourceEnd: durationSeconds,
      segments: recipe.subtitles.segments
    });
    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
  });

  it('does not tail-merge a live Thai cue beyond its safe limits', () => {
    const text = 'นักท่องเที่ยวไม่ใช่ร้านอาหาร';
    const semanticWords = readThaiSemanticWords(text);
    const words = semanticWords.map((word, index) => ({
      word,
      start: index * 0.2,
      end: (index + 1) * 0.2
    }));
    const durationSeconds = words.length * 0.2;
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds,
      settings: { subtitleWordsPerLine: 5 },
      segments: [{ text, start: 0, end: durationSeconds }],
      words
    });

    expectSafeThaiSubtitleCues({
      sourceText: text,
      sourceStart: 0,
      sourceEnd: durationSeconds,
      segments: recipe.subtitles.segments
    });
    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
  });

  it('does not tail-merge a Thai cue beyond the requested word limit', () => {
    const text = 'สินค้าใหม่ราคาดี';
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 1,
      settings: { subtitleWordsPerLine: 3 },
      segments: [{ text, start: 0, end: 1 }],
      words: [
        { word: 'สินค้า', start: 0, end: 0.3 },
        { word: 'ใหม่', start: 0.3, end: 0.6 },
        { word: 'ราคา', start: 0.6, end: 0.9 },
        { word: 'ดี', start: 0.9, end: 1 }
      ]
    });

    expect(recipe.subtitles.segments).toHaveLength(2);
    expect(
      recipe.subtitles.segments.every(
        (segment) => readThaiSemanticWords(segment.text).length <= 3
      )
    ).toBe(true);
  });

  it('does not tail-merge a non-Thai cue beyond the requested word limit', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'en',
      text: 'one two three four',
      durationSeconds: 1,
      settings: { subtitleWordsPerLine: 3 },
      segments: [{ text: 'one two three four', start: 0, end: 1 }],
      words: [
        { word: 'one', start: 0, end: 0.3 },
        { word: 'two', start: 0.3, end: 0.6 },
        { word: 'three', start: 0.6, end: 0.9 },
        { word: 'four', start: 0.9, end: 1 }
      ]
    });

    expect(recipe.subtitles.segments).toHaveLength(2);
    expect(
      recipe.subtitles.segments.every(
        (segment) => segment.text.split(/\s+/u).length <= 3
      )
    ).toBe(true);
  });

  it('splits a non-Thai provider token that contains multiple semantic words', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'en',
      text: 'one two three four',
      durationSeconds: 1,
      settings: { subtitleWordsPerLine: 1 },
      segments: [{ text: 'one two three four', start: 0, end: 1 }],
      words: [
        { word: 'one two', start: 0, end: 0.5 },
        { word: 'three four', start: 0.5, end: 1 }
      ]
    });

    expect(recipe.subtitles.segments.map((segment) => segment.text)).toEqual([
      'one',
      'two',
      'three',
      'four'
    ]);
  });

  it('caps Thai cue width even when it contains no more than five words', () => {
    const text = 'ประชาสัมพันธ์สินค้าออนไลน์คุณภาพ';
    const semanticWords = readThaiSemanticWords(text);
    const words = semanticWords.map((word, index) => ({
      word,
      start: index * 0.25,
      end: (index + 1) * 0.25
    }));
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'Thai',
      text,
      durationSeconds: 1,
      settings: { subtitleWordsPerLine: 5 },
      segments: [{ text, start: 0, end: 1 }],
      words
    });

    expect(readThaiSemanticWords(text)).toHaveLength(4);
    expect(readThaiGraphemeCount(text)).toBeGreaterThan(20);
    expectSafeThaiSubtitleCues({
      sourceText: text,
      sourceStart: 0,
      sourceEnd: 1,
      segments: recipe.subtitles.segments
    });
    expect(recipe.subtitles.segments.length).toBeGreaterThan(1);
  });

  it.each([
    {
      position: 'leading',
      text: 'supercalifragilisticexpialidocious ดี',
      words: [
        {
          word: 'supercalifragilisticexpialidocious',
          start: 0,
          end: 0.2
        },
        { word: 'ดี', start: 0.2, end: 1 }
      ],
      expectedTexts: ['supercalifragilisticexpialidocious', 'ดี'],
      expectedStart: 0,
      expectedEnd: 0.2
    },
    {
      position: 'trailing',
      text: 'ดี supercalifragilisticexpialidocious',
      words: [
        { word: 'ดี', start: 0, end: 0.8 },
        {
          word: 'supercalifragilisticexpialidocious',
          start: 0.8,
          end: 1
        }
      ],
      expectedTexts: ['ดี', 'supercalifragilisticexpialidocious'],
      expectedStart: 0.8,
      expectedEnd: 1
    }
  ])(
    'keeps an indivisible overlong $position token whole and isolated',
    ({ text, words, expectedTexts, expectedStart, expectedEnd }) => {
      const recipe = buildRecipe({
        capabilities: { subtitle: true },
        language: 'Thai',
        text,
        durationSeconds: 1,
        settings: { subtitleWordsPerLine: 5 },
        segments: [{ text, start: 0, end: 1 }],
        words
      });
      const segments = recipe.subtitles.segments;
      const overlongCue = segments.find(
        (segment) => segment.text === 'supercalifragilisticexpialidocious'
      );

      expect(segments.map((segment) => segment.text)).toEqual(expectedTexts);
      expect(overlongCue).toBeDefined();
      expect(readThaiSemanticWords(overlongCue!.text)).toHaveLength(1);
      expect(readThaiGraphemeCount(overlongCue!.text)).toBeGreaterThan(20);
      expect(overlongCue!.start).toBeCloseTo(expectedStart);
      expect(overlongCue!.end).toBeCloseTo(expectedEnd);
      expect(overlongCue!.words).toEqual([
        expect.objectContaining({
          word: 'supercalifragilisticexpialidocious'
        })
      ]);
    }
  );

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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
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

    expect(recipe.subtitles.segments.map((segment) => segment.text).join(''))
      .toBe(segments[0]!.text);
    expect(
      recipe.subtitles.segments.every(
        (segment) => readThaiSemanticWords(segment.text).length <= 2
      )
    ).toBe(true);
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

    expect(recipe.subtitles.segments).toHaveLength(3);
    expect(recipe.subtitles.segments.map((segment) => segment.text)).toEqual([
      '12 34',
      '56 78',
      '90 12'
    ]);
    expect(recipe.subtitles.segments[0]?.start).toBe(0);
    expect(recipe.subtitles.segments.at(-1)?.end).toBeCloseTo(1.2);
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments))
      .toEqual(segments);
  });

  it('reports only internal transcript gaps as silence candidates', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      text: 'หนึ่ง สอง',
      durationSeconds: 10,
      segments: [
        { text: 'หนึ่ง', start: 2, end: 3 },
        { text: 'สอง', start: 5, end: 6 }
      ]
    });

    expect(recipe.silenceRanges).toEqual([{ start: 3, end: 5 }]);
    expect(recipe.cutRanges).not.toContainEqual({ start: 3, end: 5 });
    expect(recipe.cutRanges).not.toContainEqual({ start: 0, end: 2 });
    expect(recipe.cutRanges).not.toContainEqual({ start: 6, end: 10 });
    expect(recipe.capabilities.silence.state).toBe('hinted');
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

    expect(recipe.silenceRanges).toEqual([]);
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

    expect(recipe.silenceRanges).toEqual([]);
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

  it.each([
    ['negative start', [{ start: -1, end: 1 }]],
    ['end beyond duration', [{ start: 5, end: 999 }]],
    ['non-finite start', [{ start: Number.NaN, end: 2 }]],
    ['non-finite end', [{ start: 1, end: Number.POSITIVE_INFINITY }]],
    ['zero length', [{ start: 1, end: 1 }]],
    ['backward order', [
      { start: 5, end: 6 },
      { start: 1, end: 2 }
    ]],
    ['overlap', [
      { start: 0, end: 2 },
      { start: 1.5, end: 3 }
    ]]
  ])('rejects an unsafe %s transcript timeline without clamping', (_, ranges) => {
    expect(readStrictTranscriptEvidence(ranges, 20)).toBeUndefined();
  });

  it('keeps subtitle and silence output empty when timing integrity is untrusted', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      timingIntegrity: 'untrusted',
      text: 'ชุมชน เอ่อ ชุมชน',
      durationSeconds: 4,
      segments: [
        { text: 'ชุมชน', start: 0, end: 1 },
        { text: 'ชุมชน', start: 3, end: 4 }
      ],
      words: [
        { word: 'ชุมชน', start: 0, end: 1 },
        { word: 'ชุมชน', start: 3, end: 4 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([]);
    expect(recipe.subtitles.variants).toEqual({
      '1': [],
      '3': [],
      '5': []
    });
    expect(recipe.silenceRanges).toEqual([]);
    expect(recipe.cutRanges).toEqual([]);
    expect(recipe.capabilities.subtitle.state).toBe('hinted');
    expect(recipe.capabilities.silence.state).toBe('hinted');
  });

  it('does not claim timing output was applied when trusted input is malformed', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true, silence: true },
      durationSeconds: 20,
      segments: [{ text: 'เวลาเกินคลิป', start: 5, end: 999 }]
    });

    expect(recipe.subtitles.segments).toEqual([]);
    expect(recipe.silenceRanges).toEqual([]);
    expect(recipe.cutRanges).toEqual([]);
    expect(recipe.capabilities.subtitle.state).toBe('hinted');
    expect(recipe.capabilities.silence.state).toBe('hinted');
  });

  it('does not build planning segments from untrusted timing evidence', () => {
    expect(buildAiEditPlanningSegments({
      transcript: buildTranscript({
        text: 'ช่วงแรก ช่วงสอง',
        timingIntegrity: 'untrusted',
        durationSeconds: 4,
        segments: [
          { text: 'ช่วงแรก', start: 0, end: 1 },
          { text: 'ช่วงสอง', start: 3, end: 4 }
        ]
      })
    })).toEqual([]);
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
    expect(recipe.subtitles.segments).toEqual([]);
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
    expect(recipe.subtitles.segments).toEqual([]);
  });

  it('fails closed when an empty segment placeholder has invalid timing', () => {
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

    expect(recipe.subtitles.segments).toEqual([]);
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

    expect(recipe.subtitles.segments.length).toBeGreaterThan(segments.length);
    expect(
      recipe.subtitles.segments
        .map((segment) => segment.text)
        .join('')
        .replace(/\s+/g, '')
    ).toBe(
      segments
        .map((segment) => segment.text)
        .join('')
        .replace(/\s+/g, '')
    );
    expect(
      recipe.subtitles.segments.every((segment) => segment.end > segment.start)
    ).toBe(true);
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

    expect(recipe.subtitles.segments.length).toBeGreaterThan(segments.length);
    expect(
      recipe.subtitles.segments
        .map((segment) => segment.text)
        .join('')
        .replace(/\s+/g, '')
    ).toBe(
      segments
        .map((segment) => segment.text)
        .join('')
        .replace(/\s+/g, '')
    );
    expect(recipe.silenceRanges).toEqual([]);
  });

  it('does not infer silence when any word timing is invalid', () => {
    const recipe = buildRecipe({
      capabilities: { silence: true },
      segments: [
        { text: 'ก่อนหยุด', start: 0, end: 1 },
        { text: 'หลังหยุด', start: 1.8, end: 2.5 }
      ],
      words: [{ word: 'เวลาผิด', start: 0.5, end: 0.5 }]
    });

    expect(recipe.silenceRanges).toEqual([]);
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
      { text: 'สวัสดีค่ะ', start: 0, end: 0.7 },
      { text: 'วันนี้', start: 0.8, end: 1.2 }
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
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

      expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
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

      expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
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

    expect(readLegacySubtitleSegmentFields(recipe.subtitles.segments)).toEqual([
      { text: 'Hello world', start: 0, end: 0.8 },
      { text: 'again', start: 0.9, end: 1.3 }
    ]);
  });

  it('does not burn subtitles when any word timing is invalid', () => {
    const segments = [{ text: 'ใช้ซับเดิม', start: 0, end: 1 }];
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      segments,
      words: [{ word: 'เวลาผิด', start: 0.5, end: 0.5 }]
    });

    expect(recipe.subtitles.segments).toEqual([]);
    expect(recipe.analysisOutcomes.subtitle).toBe('unavailable');
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

  it('suggests removing the earlier adjacent repeated Thai word', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text: 'สินค้าสินค้ารายการ',
      segments: [
        { text: 'สินค้าสินค้ารายการ', start: 0, end: 1.3 },
      ],
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'สินค้า', start: 0, end: 0.4 },
        { word: 'สินค้า', start: 0.45, end: 0.85 },
        { word: 'รายการ', start: 0.9, end: 1.3 },
      ],
    });

    expect(recipe.speechReduction?.status).toBe('ready');
    expect(recipe.speechReduction?.groups).toHaveLength(1);
    expect(recipe.speechReduction?.groups[0]).toMatchObject({
      text: 'สินค้า',
      normalizedText: 'สินค้า',
      totalOccurrences: 2,
    });
    expect(recipe.speechReduction?.occurrences).toEqual([
      expect.objectContaining({
        text: 'สินค้า',
        start: 0,
        end: 0.4,
        occurrenceIndex: 1,
        occurrenceCount: 2,
        kind: 'adjacent-word',
        recommendation: 'cut',
        canAutoRemove: true,
        selectedByDefault: true,
      }),
      expect.objectContaining({
        text: 'สินค้า',
        start: 0.45,
        end: 0.85,
        occurrenceIndex: 2,
        occurrenceCount: 2,
        kind: 'adjacent-word',
        recommendation: 'keep',
        canAutoRemove: false,
        selectedByDefault: false,
      }),
    ]);
    expect(recipe.speechReduction?.defaultCutRanges).toEqual([
      expect.objectContaining({ start: 0, end: 0.4 }),
    ]);
    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.4 }]);
    expect(recipe.cutRanges).toContainEqual({ start: 0, end: 0.4 });
  });

  it('keeps only the last anchor in an adjacent run and returns stable IDs', () => {
    const buildRepeatedRecipe = () => buildRecipe({
      capabilities: { filler: true },
      text: 'สินค้าสินค้าสินค้า',
      segments: [{ text: 'สินค้าสินค้าสินค้า', start: 0, end: 1.3 }],
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'สินค้า', start: 0, end: 0.4 },
        { word: 'สินค้า', start: 0.45, end: 0.85 },
        { word: 'สินค้า', start: 0.9, end: 1.3 },
      ],
    });
    const first = buildRepeatedRecipe();
    const second = buildRepeatedRecipe();

    expect(first.speechReduction).toEqual(second.speechReduction);
    expect(first.speechReduction?.groups[0]?.id).toMatch(/^srg_[a-f0-9]{16}$/u);
    expect(first.speechReduction?.occurrences.map((item) => item.recommendation))
      .toEqual(['cut', 'cut', 'keep']);
    expect(first.speechReduction?.defaultCutRanges).toHaveLength(2);
  });

  it('suggests removing the earlier adjacent repeated Thai phrase', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text: 'สินค้าคุณภาพสินค้าคุณภาพรายการ',
      segments: [
        {
          text: 'สินค้าคุณภาพสินค้าคุณภาพรายการ',
          start: 0,
          end: 2.2,
        },
      ],
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'สินค้า', start: 0, end: 0.4 },
        { word: 'คุณภาพ', start: 0.45, end: 0.85 },
        { word: 'สินค้า', start: 0.9, end: 1.3 },
        { word: 'คุณภาพ', start: 1.35, end: 1.75 },
        { word: 'รายการ', start: 1.8, end: 2.2 },
      ],
    });

    expect(recipe.speechReduction?.groups).toHaveLength(1);
    expect(recipe.speechReduction?.groups[0]).toMatchObject({
      text: 'สินค้าคุณภาพ',
      totalOccurrences: 2,
    });
    expect(recipe.speechReduction?.occurrences).toEqual([
      expect.objectContaining({
        text: 'สินค้าคุณภาพ',
        start: 0,
        end: 0.85,
        kind: 'adjacent-phrase',
        recommendation: 'cut',
      }),
      expect.objectContaining({
        text: 'สินค้าคุณภาพ',
        start: 0.9,
        end: 1.75,
        kind: 'adjacent-phrase',
        recommendation: 'keep',
      }),
    ]);
    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.85 }]);
  });

  it('allows an adjacent restart with a common Thai word but keeps it globally protected', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text: 'เราเราจะไป',
      segments: [{ text: 'เราเราจะไป', start: 0, end: 0.9 }],
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'เรา', start: 0, end: 0.2 },
        { word: 'เรา', start: 0.25, end: 0.45 },
        { word: 'จะ', start: 0.5, end: 0.65 },
        { word: 'ไป', start: 0.7, end: 0.9 },
      ],
    });

    expect(recipe.speechReduction?.groups).toHaveLength(1);
    expect(recipe.speechReduction?.occurrences).toEqual([
      expect.objectContaining({
        text: 'เรา',
        recommendation: 'cut',
        canAutoRemove: true,
      }),
      expect.objectContaining({
        text: 'เรา',
        recommendation: 'keep',
        canAutoRemove: false,
      }),
    ]);
    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.2 }]);
  });

  it('reports a distributed frequent Thai word but keeps every occurrence', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text: 'สินค้ารายการสินค้าคุณภาพสินค้า',
      segments: [
        { text: 'สินค้ารายการ', start: 0, end: 0.9 },
        { text: 'สินค้าคุณภาพ', start: 2, end: 2.9 },
        { text: 'สินค้า', start: 4, end: 4.4 },
      ],
      durationSeconds: 4.4,
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'สินค้า', start: 0, end: 0.4 },
        { word: 'รายการ', start: 0.5, end: 0.9 },
        { word: 'สินค้า', start: 2, end: 2.4 },
        { word: 'คุณภาพ', start: 2.5, end: 2.9 },
        { word: 'สินค้า', start: 4, end: 4.4 },
      ],
    });

    expect(recipe.speechReduction?.groups).toHaveLength(1);
    expect(recipe.speechReduction?.groups[0]).toMatchObject({
      text: 'สินค้า',
      totalOccurrences: 3,
    });
    expect(recipe.speechReduction?.occurrences).toHaveLength(3);
    expect(recipe.speechReduction?.occurrences).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: 'frequent-only',
          recommendation: 'keep',
          canAutoRemove: false,
          selectedByDefault: false,
        }),
      ]),
    );
    expect(recipe.speechReduction?.defaultCutRanges).toEqual([]);
    expect(recipe.fillerRanges).toEqual([]);
  });

  it('keeps intentional repeated negation and protected short words', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text: 'ไม่ไม่สินค้า',
      segments: [{ text: 'ไม่ไม่สินค้า', start: 0, end: 0.9 }],
      settings: { speechReductionMode: 'auto' },
      words: [
        { word: 'ไม่', start: 0, end: 0.2 },
        { word: 'ไม่', start: 0.25, end: 0.45 },
        { word: 'สินค้า', start: 0.5, end: 0.9 },
      ],
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'ready',
      groups: [],
      occurrences: [],
      defaultCutRanges: [],
    });
    expect(recipe.analysisOutcomes.speechReduction).toBe('succeeded');
    expect(recipe.fillerRanges).toEqual([]);
  });

  it.each([
    {
      label: 'overlapping timing',
      text: 'สินค้าสินค้า',
      words: [
        { word: 'สินค้า', start: 0, end: 0.5 },
        { word: 'สินค้า', start: 0.4, end: 0.8 },
      ],
      expectedReason: 'unsafe-word-timing',
    },
    {
      label: 'unverified fragmented Thai timing',
      text: 'สินค้าสินค้า',
      words: [
        { word: 'ส', start: 0, end: 0.05 },
        { word: 'ิ', start: 0.05, end: 0.1 },
        { word: 'น', start: 0.1, end: 0.15 },
        { word: 'ข', start: 0.15, end: 0.2 },
        { word: '้', start: 0.2, end: 0.25 },
        { word: 'า', start: 0.25, end: 0.3 },
        { word: 'ส', start: 0.3, end: 0.35 },
        { word: 'ิ', start: 0.35, end: 0.4 },
        { word: 'น', start: 0.4, end: 0.45 },
        { word: 'ค', start: 0.45, end: 0.5 },
        { word: '้', start: 0.5, end: 0.55 },
        { word: 'า', start: 0.55, end: 0.6 },
      ],
      expectedReason: 'fragmented-word-timing',
    },
  ])('fails closed for $label in speech reduction mode', ({
    text,
    words,
    expectedReason,
  }) => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      text,
      segments: [{ text, start: 0, end: words.at(-1)!.end }],
      settings: { speechReductionMode: 'auto' },
      words,
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      unavailableReason: expectedReason,
      groups: [],
      occurrences: [],
      defaultCutRanges: [],
    });
    expect(recipe.fillerRanges).toEqual([]);
  });

  it('uses exact reconstructed Thai words for adjacent repeat reduction', () => {
    const words: TranscriptWord[] = [
      { word: 'ชุม', start: 1, end: 1.2 },
      { word: 'ชน', start: 1.3, end: 1.5 },
      { word: 'ชุม', start: 1.6, end: 1.8 },
      { word: 'ชน', start: 1.9, end: 2.1 },
    ];
    const originalWords = structuredClone(words);
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 2.1 }],
      words,
      durationSeconds: 3,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction?.status).toBe('ready');
    expect(recipe.speechReduction?.defaultCutRanges).toEqual([
      expect.objectContaining({ start: 1, end: 1.5 }),
    ]);
    expect(words).toEqual(originalWords);
  });

  it('does not cut when Thai character fragments cannot be proven exact', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 3 }],
      words: [
        { word: 'ชุม', start: 1, end: 1.1 },
        { word: 'ชล', start: 1.2, end: 1.5 },
        { word: 'ชุมชน', start: 2, end: 2.5 },
      ],
      durationSeconds: 3,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      unavailableReason: 'fragmented-word-timing',
      defaultCutRanges: [],
    });
    expect(recipe.fillerRanges).toEqual([]);
  });

  it('reports exact fragmented frequent words without auto-cutting them', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน รายการ ชุมชน คุณภาพ ชุมชน',
      segments: [{
        text: 'ชุมชน รายการ ชุมชน คุณภาพ ชุมชน',
        start: 0,
        end: 4.4,
      }],
      words: [
        { word: 'ชุม', start: 0, end: 0.2 },
        { word: 'ชน', start: 0.25, end: 0.4 },
        { word: 'รายการ', start: 0.5, end: 0.9 },
        { word: 'ชุม', start: 2, end: 2.2 },
        { word: 'ชน', start: 2.25, end: 2.4 },
        { word: 'คุณภาพ', start: 2.5, end: 2.9 },
        { word: 'ชุม', start: 4, end: 4.2 },
        { word: 'ชน', start: 4.25, end: 4.4 },
      ],
      durationSeconds: 4.4,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction?.groups).toEqual([
      expect.objectContaining({
        text: 'ชุมชน',
        totalOccurrences: 3,
      }),
    ]);
    expect(recipe.speechReduction?.occurrences).toHaveLength(3);
    expect(recipe.speechReduction?.occurrences).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: 'frequent-only',
          canAutoRemove: false,
          selectedByDefault: false,
        }),
      ]),
    );
    expect(recipe.speechReduction?.defaultCutRanges).toEqual([]);
    expect(recipe.fillerRanges).toEqual([]);
  });

  it('fails closed when an internal Thai fragment gap exceeds 150ms', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 1, end: 3 }],
      words: [
        { word: 'ชุม', start: 1, end: 1.1 },
        { word: 'ชน', start: 1.26, end: 1.5 },
        { word: 'ชุม', start: 1.7, end: 1.9 },
        { word: 'ชน', start: 2, end: 2.2 },
      ],
      durationSeconds: 3,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      unavailableReason: 'fragmented-word-timing',
      defaultCutRanges: [],
    });
  });

  it('does not reconstruct a Thai word across transcript segments', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [
        { text: 'ชุมชน', start: 1, end: 1.45 },
        { text: 'ชุมชน', start: 1.45, end: 2.5 },
      ],
      words: [
        { word: 'ชุม', start: 1, end: 1.2 },
        { word: 'ชน', start: 1.3, end: 1.5 },
        { word: 'ชุมชน', start: 1.7, end: 2.2 },
      ],
      durationSeconds: 3,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      defaultCutRanges: [],
    });
  });

  it('does not hide provider-order timing errors before repeat detection', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 2 }],
      words: [
        { word: 'ชุมชน', start: 1.2, end: 1.5 },
        { word: 'ชุมชน', start: 0.5, end: 0.9 },
      ],
      durationSeconds: 2,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      defaultCutRanges: [],
    });
  });

  it('preserves punctuation as a sentence barrier after reconstruction', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน? ชุมชน?',
      segments: [{ text: 'ชุมชน? ชุมชน?', start: 0, end: 2 }],
      words: [
        { word: 'ชุมชน?', start: 0.1, end: 0.7 },
        { word: 'ชุมชน?', start: 1, end: 1.6 },
      ],
      durationSeconds: 2,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'ready',
      groups: [],
      defaultCutRanges: [],
    });
  });

  it('rejects clamped display evidence as a repeat timeline', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 5, end: 999 }],
      words: [
        { word: 'ชุมชน', start: 5, end: 6 },
        { word: 'ชุมชน', start: 6.1, end: 7 },
      ],
      durationSeconds: 20,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      defaultCutRanges: [],
    });
  });

  it('does not connect reliable repeat islands across unreliable speech', () => {
    const recipe = buildRecipe({
      text: 'ชุมชน เอ่อ ชุมชน',
      segments: [
        { text: 'ชุมชน', start: 0, end: 0.4 },
        {
          text: 'เอ่อ',
          start: 0.45,
          end: 0.7,
          noSpeechProbability: 0.9,
        },
        { text: 'ชุมชน', start: 0.75, end: 1.2 },
      ],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.4 },
        { word: 'เอ่อ', start: 0.45, end: 0.7 },
        { word: 'ชุมชน', start: 0.75, end: 1.2 },
      ],
      durationSeconds: 1.2,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      defaultCutRanges: [],
    });
  });

  it.each([
    {
      label: 'provider timing integrity is untrusted',
      timingIntegrity: 'untrusted' as const,
      hasTimedAudioEvents: false,
    },
    {
      label: 'a timed audio event exists between words',
      timingIntegrity: 'trusted' as const,
      hasTimedAudioEvents: true,
    },
  ])('does not auto-cut when $label', ({
    timingIntegrity,
    hasTimedAudioEvents,
  }) => {
    const recipe = buildRecipe({
      text: 'ชุมชน ชุมชน',
      segments: [{ text: 'ชุมชน ชุมชน', start: 0, end: 1.2 }],
      words: [
        { word: 'ชุมชน', start: 0, end: 0.4 },
        { word: 'ชุมชน', start: 0.75, end: 1.2 },
      ],
      durationSeconds: 1.2,
      timingIntegrity,
      hasTimedAudioEvents,
      capabilities: { filler: true },
      settings: { speechReductionMode: 'auto' },
    });

    expect(recipe.speechReduction).toMatchObject({
      status: 'unavailable',
      defaultCutRanges: [],
    });
  });

  it('keeps the legacy fixed filler behavior when speech reduction mode is omitted', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['เอ่อ'] },
      words: [
        { word: 'เอ่อ', start: 0, end: 0.2 },
        { word: 'สินค้า', start: 0.25, end: 0.7 },
      ],
    });

    expect(recipe.speechReduction).toBeUndefined();
    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.2 }]);
    expect(recipe.cutRanges).toContainEqual({ start: 0, end: 0.2 });
  });

  it('removes a fragmented weak อะฮะ opening before the first real word', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text: 'อะฮะเราก็เลยมาเลี้ยงนก',
      segments: [
        { text: 'อะฮะเราก็เลยมาเลี้ยงนก', start: 0, end: 1.2 },
      ],
      settings: { fillerWords: ['อาฮะ'] },
      words: [
        { word: 'อะ', start: 0, end: 0.14 },
        { word: 'ฮะ', start: 0.14, end: 0.28 },
        { word: 'เรา', start: 0.28, end: 0.5 },
        { word: 'ก็เลยมาเลี้ยงนก', start: 0.5, end: 1.2 },
      ],
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.28 }]);
  });

  it('matches exact อะฮะ as the transcription alias of selected อาฮะ', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      settings: { fillerWords: ['อาฮะ'] },
      words: [
        { word: 'อะฮะ', start: 0, end: 0.28 },
        { word: 'เรา', start: 0.28, end: 0.5 },
      ],
    });

    expect(recipe.fillerRanges).toEqual([{ start: 0, end: 0.28 }]);
  });

  it('does not cut อะฮะ from a larger token without a safe timing boundary', () => {
    const recipe = buildRecipe({
      capabilities: { filler: true },
      language: 'Thai',
      text: 'อะฮะเรา',
      settings: { fillerWords: ['อาฮะ'] },
      words: [{ word: 'อะฮะเรา', start: 0, end: 0.5 }],
    });

    expect(recipe.fillerRanges).toEqual([]);
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

  it('ignores provider whitespace tokens while validating fragmented fillers', () => {
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

  it('adds validated word timings to the final subtitle cue', () => {
    const words = [
      { word: 'Hello', start: 0, end: 0.4 },
      { word: 'world', start: 0.4, end: 0.8 },
      { word: 'again', start: 0.9, end: 1.3 }
    ];
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'en',
      text: 'Hello world again',
      durationSeconds: 1.3,
      settings: { subtitleWordsPerLine: 2 },
      segments: [{ text: 'Hello world again', start: 0, end: 1.3 }],
      words
    });

    expect(recipe.subtitles.segments).toEqual([
      {
        text: 'Hello world',
        start: 0,
        end: 0.8,
        words: words.slice(0, 2)
      },
      {
        text: 'again',
        start: 0.9,
        end: 1.3,
        words: words.slice(2)
      }
    ]);
  });

  it('rejects word timing whose capitalization differs from the cue', () => {
    expect(attachValidatedSubtitleWords(
      [{ text: 'Hello', start: 0, end: 0.8 }],
      [{ word: 'hello', start: 0, end: 0.8 }]
    )).toEqual([
      { text: 'Hello', start: 0, end: 0.8, words: [] }
    ]);
  });

  it('rejects canonically different word text from the cue', () => {
    expect(attachValidatedSubtitleWords(
      [{ text: 'Café', start: 0, end: 0.8 }],
      [{ word: 'Cafe\u0301', start: 0, end: 0.8 }]
    )).toEqual([
      { text: 'Café', start: 0, end: 0.8, words: [] }
    ]);
  });

  it('returns an authoritative empty word list for unsafe cue timing', () => {
    const recipe = buildRecipe({
      capabilities: { subtitle: true },
      language: 'en',
      text: 'one two',
      durationSeconds: 1.2,
      segments: [{ text: 'one two', start: 0, end: 1.2 }],
      words: [
        { word: 'one', start: 0, end: 0.7 },
        { word: 'two', start: 0.6, end: 1.2 }
      ]
    });

    expect(recipe.subtitles.segments).toEqual([]);
  });
});
