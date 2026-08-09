import { describe, expect, it, vi } from 'vitest';

import {
  aiSoundEffectCatalog,
  buildSoundEffectTimingAnchors,
  createGeminiSoundEffectPlanProvider,
  maxAiSoundEffectsPerVideo,
  parseLlmSoundEffectPlan,
  validateSoundEffectPlanResult
} from './soundEffectPlanProvider.js';

const request = {
  durationSeconds: 12,
  segments: [
    { text: 'หยุดดูสินค้านี้ก่อน', start: 0, end: 2 },
    { text: 'ราคาเพียง 99 บาท', start: 4, end: 7 },
    { text: 'กดตะกร้าได้เลย', start: 9, end: 12 }
  ]
};

describe('AI sound-effect catalog and timing anchors', () => {
  it('exposes only the ten bundled PostDee sound IDs', () => {
    expect(aiSoundEffectCatalog.map((effect) => effect.id)).toEqual([
      'soft_pop',
      'clean_tap',
      'short_whoosh',
      'medium_whoosh',
      'sparkle',
      'success_ding',
      'coin_ping',
      'soft_impact',
      'short_riser',
      'attention_boop'
    ]);
    expect(maxAiSoundEffectsPerVideo).toBe(8);
  });

  it('builds source-time anchors only from valid transcript boundaries', () => {
    expect(buildSoundEffectTimingAnchors({
      durationSeconds: 12,
      segments: [
        ...request.segments,
        { text: 'outside', start: 13, end: 14 },
        { text: 'backwards', start: 8, end: 7 }
      ]
    })).toEqual([
      { sourceSeconds: 0, text: 'หยุดดูสินค้านี้ก่อน', position: 'start' },
      { sourceSeconds: 2, text: 'หยุดดูสินค้านี้ก่อน', position: 'end' },
      { sourceSeconds: 4, text: 'ราคาเพียง 99 บาท', position: 'start' },
      { sourceSeconds: 7, text: 'ราคาเพียง 99 บาท', position: 'end' },
      { sourceSeconds: 9, text: 'กดตะกร้าได้เลย', position: 'start' }
    ]);
  });
});

describe('parseLlmSoundEffectPlan', () => {
  it('accepts allowlisted sounds at trusted anchors and sorts them', () => {
    expect(parseLlmSoundEffectPlan(
      JSON.stringify({
        soundEffects: [
          { soundId: 'success_ding', sourceSeconds: 9 },
          { soundId: 'attention_boop', sourceSeconds: 0 }
        ],
        summary: 'เน้นจุดเปิดและคำชวนซื้อ'
      }),
      request,
      'test-model'
    )).toEqual({
      soundEffects: [
        { soundId: 'attention_boop', sourceSeconds: 0 },
        { soundId: 'success_ding', sourceSeconds: 9 }
      ],
      summary: 'เน้นจุดเปิดและคำชวนซื้อ',
      model: 'test-model'
    });
  });

  it('treats a valid empty selection as a completed analysis', () => {
    expect(parseLlmSoundEffectPlan(
      '{"soundEffects":[],"summary":"คลิปนี้ไม่ควรใส่เสียงเพิ่ม"}',
      request,
      'test-model'
    )).toEqual({
      soundEffects: [],
      summary: 'คลิปนี้ไม่ควรใส่เสียงเพิ่ม',
      model: 'test-model'
    });
  });

  it.each([
    [
      'unknown sound ID',
      { soundEffects: [{ soundId: 'remote_asset', sourceSeconds: 0 }], summary: '' }
    ],
    [
      'non-anchor timestamp',
      { soundEffects: [{ soundId: 'soft_pop', sourceSeconds: 1.5 }], summary: '' }
    ],
    [
      'external asset field',
      {
        soundEffects: [{
          soundId: 'soft_pop',
          sourceSeconds: 0,
          url: 'https://example.com/effect.wav'
        }],
        summary: ''
      }
    ],
    [
      'too many placements',
      {
        soundEffects: Array.from(
          { length: maxAiSoundEffectsPerVideo + 1 },
          () => ({ soundId: 'soft_pop', sourceSeconds: 0 })
        ),
        summary: ''
      }
    ],
    [
      'stacked effects at one timestamp',
      {
        soundEffects: [
          { soundId: 'soft_pop', sourceSeconds: 0 },
          { soundId: 'attention_boop', sourceSeconds: 0 }
        ],
        summary: ''
      }
    ]
  ])('fails closed for %s', (_name, payload) => {
    expect(() => parseLlmSoundEffectPlan(
      JSON.stringify(payload),
      request,
      'test-model'
    )).toThrow();
  });

  it('re-validates internal provider results atomically', () => {
    expect(validateSoundEffectPlanResult({
      soundEffects: [{ soundId: 'coin_ping', sourceSeconds: 4 }],
      summary: 'เน้นราคา',
      model: 'internal-model'
    }, request)).toEqual({
      soundEffects: [{ soundId: 'coin_ping', sourceSeconds: 4 }],
      summary: 'เน้นราคา',
      model: 'internal-model'
    });
    expect(validateSoundEffectPlanResult({
      soundEffects: [
        { soundId: 'coin_ping', sourceSeconds: 4 },
        { soundId: 'soft_pop', sourceSeconds: 1.5 }
      ],
      summary: 'one unsafe item',
      model: 'internal-model'
    }, request)).toBeUndefined();
  });
});

describe('Gemini AI sound-effect provider', () => {
  it('asks for catalog-only source-timed JSON and returns a validated plan', async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => ({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                soundEffects: [{ soundId: 'coin_ping', sourceSeconds: 4 }],
                summary: 'เน้นช่วงบอกราคา'
              })
            }]
          }
        }]
      }),
      init
    }));
    const provider = createGeminiSoundEffectPlanProvider({
      apiKey: 'test-key',
      model: 'test-gemini',
      fetchImpl
    });

    await expect(provider.plan(request)).resolves.toEqual({
      soundEffects: [{ soundId: 'coin_ping', sourceSeconds: 4 }],
      summary: 'เน้นช่วงบอกราคา',
      model: 'test-gemini'
    });

    const body = JSON.parse(
      (fetchImpl.mock.calls[0]?.[1] as RequestInit).body as string
    ) as Record<string, unknown>;
    expect(body).toMatchObject({
      generationConfig: { responseMimeType: 'application/json' }
    });
    expect(JSON.stringify(body)).toContain('soft_pop');
    expect(JSON.stringify(body)).toContain('sourceSeconds');
    expect(JSON.stringify(body)).not.toContain('.wav');
    expect(JSON.stringify(body)).not.toContain('assetPath');
  });

  it.each([
    ['network failure', async () => { throw new Error('offline'); }],
    ['invalid provider output', async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: '{"soundEffects":[{"soundId":"unknown","sourceSeconds":0}],"summary":""}'
            }]
          }
        }]
      })
    })]
  ])('fails closed on %s', async (_name, fetchImpl) => {
    const provider = createGeminiSoundEffectPlanProvider({
      apiKey: 'test-key',
      model: 'test-gemini',
      fetchImpl
    });

    await expect(provider.plan(request)).resolves.toBeUndefined();
  });

  it('does not contact an AI provider without a trusted timing anchor', async () => {
    const fetchImpl = vi.fn();
    const provider = createGeminiSoundEffectPlanProvider({
      apiKey: 'test-key',
      model: 'test-gemini',
      fetchImpl
    });

    await expect(provider.plan({
      durationSeconds: 12,
      segments: []
    })).resolves.toBeUndefined();
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
