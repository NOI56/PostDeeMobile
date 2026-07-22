import { describe, expect, it } from 'vitest';

import {
  buildHighlightCuts,
  buildKeywordKeepCuts,
  createMockEditPlanProvider,
  createOpenAiCompatibleEditPlanProvider,
  isReliableHighlightSegment,
  matchesAnyKeyword,
  parseLlmEditPlan,
  parsePromptInstruction,
  trimToTarget
} from './editPlanProvider.js';

describe('edit plan provider', () => {
  it('matches keywords case-insensitively', () => {
    expect(matchesAnyKeyword('ราคาพิเศษ', ['ราคา'])).toBe(true);
    expect(matchesAnyKeyword('FLASH sale', ['flash'])).toBe(true);
    expect(matchesAnyKeyword('สวัสดี', ['ราคา'])).toBe(false);
  });

  it('keeps keyword segments and cuts the rest', () => {
    const cuts = buildKeywordKeepCuts(
      [
        { text: 'สวัสดีค่ะ', start: 0, end: 3 },
        { text: 'ราคาพิเศษ 99 บาท', start: 3, end: 6 },
        { text: 'ขอบคุณค่ะ', start: 6, end: 10 }
      ],
      10,
      ['ราคา', 'บาท'],
      false
    );

    expect(cuts).toEqual([
      { start: 0, end: 3 },
      { start: 6, end: 10 }
    ]);
  });

  it('trims the tail to a target length', () => {
    const cuts = trimToTarget([], 60, 45);
    expect(cuts).toEqual([{ start: 45, end: 60 }]);
  });

  it('selects the strongest selling moments instead of the first seconds', () => {
    const cuts = buildHighlightCuts(
      [
        { text: 'สวัสดีค่ะ วันนี้จะมาเล่าให้ฟัง', start: 0, end: 4 },
        { text: 'ใช้แล้วช่วยประหยัดเวลาและใช้ง่ายมาก', start: 4, end: 8 },
        { text: 'ตรงนี้เป็นรายละเอียดทั่วไป', start: 8, end: 12 },
        { text: 'ราคาพิเศษ 99 บาท ส่งฟรีวันนี้', start: 12, end: 15 },
        { text: 'กดตะกร้าสั่งซื้อได้เลย', start: 15, end: 18 }
      ],
      18,
      10
    );

    expect(cuts).toEqual([{ start: 0, end: 8 }]);
  });

  it('uses targetDurationSeconds to plan transcript highlights', async () => {
    const provider = createMockEditPlanProvider();
    const result = await provider.plan({
      durationSeconds: 18,
      targetDurationSeconds: 10,
      segments: [
        { text: 'สวัสดีค่ะ วันนี้จะมาเล่าให้ฟัง', start: 0, end: 4 },
        { text: 'ใช้แล้วช่วยประหยัดเวลาและใช้ง่ายมาก', start: 4, end: 8 },
        { text: 'ตรงนี้เป็นรายละเอียดทั่วไป', start: 8, end: 12 },
        { text: 'ราคาพิเศษ 99 บาท ส่งฟรีวันนี้', start: 12, end: 15 },
        { text: 'กดตะกร้าสั่งซื้อได้เลย', start: 15, end: 18 }
      ]
    });

    expect(result.cuts).toEqual([{ start: 0, end: 8 }]);
    expect(result.summary).toContain('10');
  });

  it('rejects leaked prompts and low-confidence transcript segments', () => {
    expect(
      isReliableHighlightSegment({
        text: 'ชื่อแอปให้เขียนเป็นภาษาไทยว่า โพสต์ดี',
        start: 0,
        end: 4
      })
    ).toBe(false);
    expect(
      isReliableHighlightSegment({
        text: 'รีวิวสินค้านี้ดีมาก',
        start: 4,
        end: 8,
        avgLogprob: -1.2
      })
    ).toBe(false);
    expect(
      isReliableHighlightSegment({
        text: 'รีวิวสินค้านี้ดีมาก',
        start: 8,
        end: 12,
        avgLogprob: -0.2
      })
    ).toBe(true);
  });

  it('parses a prompt target length and profanity intent', () => {
    expect(parsePromptInstruction('เหลือ 45 วิ').targetSeconds).toBe(45);
    expect(parsePromptInstruction('เอาแค่ 1 นาที').targetSeconds).toBe(60);
    expect(parsePromptInstruction('ตัดคำหยาบออก').removeProfanity).toBe(true);
    expect(parsePromptInstruction('ทำให้ดี').removeProfanity).toBe(false);
  });

  it('plans a style by keyword keep', async () => {
    const provider = createMockEditPlanProvider();
    const result = await provider.plan({
      styleId: 'flash_sale',
      durationSeconds: 10,
      segments: [
        { text: 'สวัสดีค่ะ', start: 0, end: 3 },
        { text: 'ราคา 99 บาท', start: 3, end: 6 },
        { text: 'บายค่ะ', start: 6, end: 10 }
      ]
    });

    expect(result.model).toBe('mock-rule');
    expect(result.cuts).toEqual([
      { start: 0, end: 3 },
      { start: 6, end: 10 }
    ]);
  });

  it('plans a prompt with profanity removal and target length', async () => {
    const provider = createMockEditPlanProvider();
    const result = await provider.plan({
      prompt: 'ตัดคำหยาบออกแล้วเหลือ 15 วิ',
      durationSeconds: 30,
      segments: [
        { text: 'สวัสดีค่ะ', start: 0, end: 10 },
        { text: 'ไอ้เหี้ยอะไรเนี่ย', start: 10, end: 12 },
        { text: 'ขายของต่อ', start: 12, end: 30 }
      ]
    });

    expect(result.cuts.some((c) => c.start === 10 && c.end === 12)).toBe(true);
    expect(result.cuts.some((c) => Math.abs(c.start - 17) < 0.01 && c.end === 30)).toBe(
      true
    );
  });

  it('parses and clamps an LLM JSON edit plan', () => {
    const result = parseLlmEditPlan(
      '{"cuts":[{"start":-2,"end":3},{"start":5,"end":99},{"start":7,"end":7}],"summary":"ตัดต้นกับท้าย"}',
      10,
      'llm-x'
    );

    expect(result.model).toBe('llm-x');
    expect(result.summary).toBe('ตัดต้นกับท้าย');
    // -2 clamps to 0; 99 clamps to 10; the zero-length 7-7 is dropped.
    expect(result.cuts).toEqual([
      { start: 0, end: 3 },
      { start: 5, end: 10 }
    ]);
  });

  it('uses the LLM response when the chat call succeeds', async () => {
    const provider = createOpenAiCompatibleEditPlanProvider({
      apiKey: 'k',
      model: 'llm-x',
      endpointUrl: 'https://example.com/v1/chat/completions',
      failureLabel: 'Test edit plan',
      fallback: createMockEditPlanProvider(),
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({
          choices: [
            {
              message: {
                content: '{"cuts":[{"start":1,"end":2}],"summary":"ai"}'
              }
            }
          ]
        })
      })
    });

    const result = await provider.plan({
      prompt: 'ตัดให้หน่อย',
      durationSeconds: 10,
      segments: []
    });

    expect(result.model).toBe('llm-x');
    expect(result.cuts).toEqual([{ start: 1, end: 2 }]);
  });

  it('turns scattered LLM highlights into one coherent target-length range', async () => {
    const provider = createOpenAiCompatibleEditPlanProvider({
      apiKey: 'k',
      model: 'llm-x',
      endpointUrl: 'https://example.com/v1/chat/completions',
      failureLabel: 'Test edit plan',
      fallback: createMockEditPlanProvider(),
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({
          choices: [
            {
              message: {
                content:
                  '{"cuts":[{"start":0,"end":10},{"start":20,"end":50},{"start":60,"end":90}],"summary":"ai"}'
              }
            }
          ]
        })
      })
    });

    const result = await provider.plan({
      durationSeconds: 100,
      targetDurationSeconds: 45,
      segments: [
        { text: 'ช่วงเรื่องที่ต่อเนื่องและน่าสนใจ', start: 10, end: 55 },
        { text: 'ช่วงสรุป', start: 90, end: 100 }
      ]
    });

    expect(result.cuts).toEqual([
      { start: 0, end: 10 },
      { start: 55, end: 100 }
    ]);
  });

  it('falls back to the mock when the chat call fails', async () => {
    const provider = createOpenAiCompatibleEditPlanProvider({
      apiKey: 'k',
      model: 'llm-x',
      endpointUrl: 'https://example.com/v1/chat/completions',
      failureLabel: 'Test edit plan',
      fallback: createMockEditPlanProvider(),
      fetchImpl: async () => ({ ok: false, status: 500, json: async () => ({}) })
    });

    const result = await provider.plan({
      prompt: 'เหลือ 5 วิ',
      durationSeconds: 10,
      segments: []
    });

    // Mock fallback handled the target-length trim.
    expect(result.model).toBe('mock-rule');
    expect(result.cuts).toEqual([{ start: 5, end: 10 }]);
  });
});
