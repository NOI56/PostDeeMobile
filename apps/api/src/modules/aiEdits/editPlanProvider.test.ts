import { describe, expect, it } from 'vitest';

import {
  buildCoherentHighlightCuts,
  buildHighlightCuts,
  buildKeywordKeepCuts,
  createEditPlanProviderFromConfig,
  createGeminiEditPlanProvider,
  createMockEditPlanProvider,
  createOpenAiCompatibleEditPlanProvider,
  hasWeakThaiOpening,
  isReliableHighlightSegment,
  matchesAnyKeyword,
  opensDuringContinuousSpeech,
  parseLlmEditPlan,
  parsePromptInstruction,
  trimToTarget
} from './editPlanProvider.js';
import { readServerConfig } from '../../config/env.js';

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

  it('recognizes Thai fragments that should not lead a short clip', () => {
    expect(hasWeakThaiOpening('แต่ไม่ได้ช่วยเรื่องนี้')).toBe(true);
    expect(hasWeakThaiOpening('แล้วเราค่อยไปขั้นตอนถัดไป')).toBe(true);
    expect(hasWeakThaiOpening('ของมาจากตลาดใกล้บ้าน')).toBe(true);
    expect(hasWeakThaiOpening('อาฮะเราก็เลยลองวิธีนี้')).toBe(true);
    expect(hasWeakThaiOpening('อะฮะเราก็เลยลองวิธีนี้')).toBe(true);
    expect(hasWeakThaiOpening('วิธีนี้ช่วยประหยัดเวลาได้จริง')).toBe(false);
  });

  it('prefers a complete Thai opening when highlight strength is close', () => {
    const cuts = buildHighlightCuts(
      [
        { text: 'เกริ่นนำทั่วไป', start: 0, end: 10 },
        { text: 'แต่ไม่ได้ช่วยให้เข้าใจง่ายขึ้น', start: 10, end: 20 },
        {
          text: 'วิธีนี้ช่วยประหยัดเวลาและใช้งานได้จริง',
          start: 20,
          end: 30
        },
        { text: 'รายละเอียดทั่วไป', start: 30, end: 40 }
      ],
      40,
      20
    );

    expect(cuts).toEqual([{ start: 0, end: 20 }]);
  });

  it('nudges a visual suggestion to the next complete Thai sentence', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'เกริ่นนำ', start: 0, end: 10 },
        { text: 'แต่ไม่ได้', start: 10, end: 12 },
        { text: 'ประโยคนี้เริ่มเรื่องใหม่ครบถ้วน', start: 12, end: 20 },
        { text: 'รายละเอียดต่อเนื่อง', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts).toEqual([
      { start: 0, end: 12 },
      { start: 30, end: 40 }
    ]);
  });

  it('does not open on a cue that continues uninterrupted Thai speech', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'เนื้อหาก่อนหน้า', start: 8, end: 10 },
        { text: 'ตามที่เรา', start: 10, end: 12 },
        {
          text: 'ประโยคใหม่ที่เริ่มหลังจังหวะพัก',
          start: 12.5,
          end: 20
        },
        { text: 'รายละเอียดที่เล่าต่อ', start: 20, end: 30 },
        { text: 'ช่วงปิดของประโยคใหม่', start: 30, end: 32.5 },
        { text: 'บทสรุป', start: 32.5, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts).toEqual([
      { start: 0, end: 12.5 },
      { start: 32.5, end: 40 }
    ]);
  });

  it('backs the live Thai opening up to a nearby sentence boundary', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 110.183 },
        { start: 140.183, end: 150 }
      ],
      segments: [
        {
          text: 'เป็นเหมือนกับเป็นเอ่อโบ๊ทบัสแบบนี้ค่ะ',
          start: 105.344,
          end: 108.166
        },
        { text: 'แล้วก็ไปแล้ว', start: 108.166, end: 109.03 },
        {
          text: 'ก็ตีตั๋วครั้งนึงแล้ว',
          start: 109.03,
          end: 110.182
        },
        { text: 'ก็นั่งล่อง', start: 110.183, end: 110.895 },
        { text: 'เรือไปเรื่อยๆ', start: 110.895, end: 112.081 },
        { text: 'ถ่ายรูปนะ', start: 112.081, end: 112.912 },
        { text: 'คะเก็บชีวิ', start: 112.912, end: 113.742 },
        { text: 'ตสองข้าง', start: 113.742, end: 114.531 },
        {
          text: 'ระหว่างทางพอหิวก็หยุดหาอาหาร',
          start: 114.531,
          end: 138.166
        },
        { text: 'ช่วงท้ายของเรื่องนี้', start: 138.166, end: 140.183 },
        { text: 'บทสรุป', start: 140.183, end: 150 }
      ],
      durationSeconds: 150,
      targetDurationSeconds: 30,
      weakOpeningPenalty: 300
    });

    expect(cuts).toEqual([
      { start: 0, end: 108.166 },
      { start: 138.166, end: 150 }
    ]);
  });

  it('moves a live Thai list fragment forward to the next paused sentence', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 79.322 },
        { start: 139.322, end: 150.635 }
      ],
      segments: [
        { text: 'บริบทก่อนหน้า', start: 70, end: 75.151 },
        { text: 'ของของมาจาก', start: 75.151, end: 76.107 },
        { text: 'เชียงใหม่ของ', start: 76.107, end: 77.094 },
        { text: 'มาจากภูเก็ตมาจาก', start: 77.094, end: 78.477 },
        { text: 'สมุยมาจาก', start: 78.477, end: 79.322 },
        { text: 'ทุกๆที่ในเมือง', start: 79.322, end: 80.378 },
        { text: 'ไทยมารวมที่จตุจักร', start: 80.378, end: 81.857 },
        // A real 620 ms pause marks the next spoken sentence. Repairing to
        // this cue is boundary cleanup, not the separate three-second hook.
        { text: 'ถ้าคนที่เคย', start: 82.477, end: 90 },
        { text: 'ไปรับรองว่าหนึ่งวันไม่พอ', start: 90, end: 100 },
        { text: 'ต้องกลับมาอีกเพื่อหาของ', start: 100, end: 110 },
        { text: 'ที่ตัวเองต้องการ', start: 110, end: 120 },
        { text: 'เพราะจะมีของมาใหม่', start: 120, end: 130 },
        { text: 'ตลอดทั้งสัปดาห์', start: 130, end: 139.322 },
        { text: 'ประโยคปิดช่วงที่เลือก', start: 139.322, end: 142.477 },
        { text: 'บริบทถัดไป', start: 142.477, end: 150.635 }
      ],
      durationSeconds: 150.635,
      targetDurationSeconds: 60,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(82.477);
  });

  it('keeps the selected window when no earlier sentence boundary is nearby',
      () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'previous uninterrupted context', start: 0, end: 10 },
        { text: 'ก็นั่งล่อง', start: 10, end: 12 },
        { text: 'เรือไปเรื่อยๆ', start: 12, end: 14 },
        {
          text: 'รายละเอียดช่วงหลักที่ยังอยู่ในเรื่องเดียวกัน',
          start: 14,
          end: 30
        },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it.each([
    {
      name: 'natural interview',
      opening: {
        text: 'สนามฟุตบอลเหมือน',
        start: 10,
        end: 11.136
      },
      nextThought: {
        text: 'ทุกวันนี้มันก็',
        start: 11.136,
        end: 11.809
      }
    },
    {
      name: 'noisy interview',
      opening: {
        text: 'กันก่อนเมื่อก่อน',
        start: 10,
        end: 10.756
      },
      nextThought: {
        text: 'ทีนี้เขาก็',
        start: 11.317,
        end: 12.055
      }
    }
  ])(
    'moves a mid-answer $name opening forward to the next complete thought',
    ({ opening, nextThought }) => {
      const cuts = buildCoherentHighlightCuts({
        suggestedCuts: [
          { start: 0, end: 10 },
          { start: 30, end: 40 }
        ],
        segments: [
          opening,
          nextThought,
          {
            text: 'เล่าใจความสำคัญต่อจนจบประโยค',
            start: nextThought.end,
            end: 20
          },
          { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
          { text: 'บทสรุป', start: 30, end: 40 }
        ],
        durationSeconds: 40,
        targetDurationSeconds: 20,
        weakOpeningPenalty: 300
      });

      expect(cuts[0]?.end).toBe(nextThought.start);
    }
  );

  it('does not move a strong hook forward when it is the first available cue',
      () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'หยุดก่อน', start: 10, end: 10.8 },
        { text: 'ทีนี้เขาก็เริ่มอธิบาย', start: 10.8, end: 12 },
        { text: 'ใจความสำคัญ', start: 12, end: 20 },
        { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it('keeps a complete opening that happens to begin with กันก่อน', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'กันก่อน แล้วค่อยลงมือ', start: 10, end: 11 },
        { text: 'ตอนนี้เราเริ่มอธิบาย', start: 11, end: 12 },
        { text: 'ใจความสำคัญ', start: 12, end: 20 },
        { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it('does not mistake a complete Thai word ending in ที่ for a fragment',
      () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'สถานที่', start: 10, end: 11 },
        { text: 'ตอนนี้เราเริ่มอธิบาย', start: 11, end: 12 },
        { text: 'ใจความสำคัญ', start: 12, end: 20 },
        { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it('does not replace a fragment opening with another incomplete cue', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'สนามฟุตบอลเหมือน', start: 10, end: 11 },
        { text: 'สำหรับ', start: 11, end: 12 },
        { text: 'ผู้ที่กำลังเลือกสินค้า', start: 12, end: 20 },
        { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).not.toBe(11);
  });

  it('does not skip more than three seconds to repair a fragment opening',
      () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'สนามฟุตบอลเหมือน', start: 10, end: 11 },
        { text: 'คำอธิบายที่พูดต่อเนื่อง', start: 11, end: 13.1 },
        { text: 'ทุกวันนี้มันก็เริ่มเรื่องใหม่', start: 13.1, end: 15 },
        { text: 'ใจความสำคัญ', start: 15, end: 20 },
        { text: 'รายละเอียดประกอบ', start: 20, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it('does not turn paused-boundary repair into a distant hook search', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'เนื้อหาก่อนหน้า', start: 8, end: 10 },
        { text: 'ทุกๆที่ในเมือง', start: 10, end: 11 },
        { text: 'ไทยมารวมที่นี่', start: 11, end: 13.5 },
        { text: 'ถ้าคนที่เคย', start: 15, end: 16 },
        { text: 'ประโยคใหม่ที่พูดต่อ', start: 16, end: 25 },
        { text: 'รายละเอียดประกอบ', start: 25, end: 30 },
        { text: 'บทสรุป', start: 30, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).toBe(10);
  });

  it('does not grant an opening-repair bonus beyond three seconds', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 33.1, end: 50 }
      ],
      segments: [
        { text: 'สนามฟุตบอลเหมือน', start: 10, end: 11 },
        { text: 'คำอธิบายที่พูดต่อเนื่อง', start: 11, end: 13.1 },
        { text: 'ทุกวันนี้มันก็เริ่มเรื่องใหม่', start: 13.1, end: 15 },
        { text: 'ใจความสำคัญ', start: 15, end: 30 },
        { text: 'รายละเอียดประกอบ', start: 30, end: 33.1 },
        { text: 'บทสรุป', start: 33.1, end: 50 }
      ],
      durationSeconds: 50,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts[0]?.end).not.toBe(13.1);
  });

  it('prefers a nearby complete opening over a closer weak conjunction', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 50 }
      ],
      segments: [
        { text: 'เรื่องก่อนหน้า.', start: 0, end: 7 },
        { text: 'วิธีนี้เริ่มเรื่องใหม่', start: 7, end: 8 },
        { text: 'แล้วค่อยเล่าต่อ', start: 8.5, end: 9.2 },
        { text: 'บริบทก่อนหน้า', start: 9.2, end: 10 },
        { text: 'ก็นั่งล่อง', start: 10, end: 12 },
        { text: 'รายละเอียดหนึ่ง', start: 12, end: 14 },
        { text: 'รายละเอียดสอง', start: 14, end: 16 },
        { text: 'รายละเอียดสาม', start: 16, end: 18 },
        { text: 'รายละเอียดสี่', start: 18, end: 20 },
        { text: 'รายละเอียดห้า', start: 20, end: 22 },
        { text: 'รายละเอียดหก', start: 22, end: 24 },
        { text: 'รายละเอียดเจ็ด', start: 24, end: 26 },
        { text: 'รายละเอียดแปด', start: 26, end: 28 },
        { text: 'รายละเอียดเก้า', start: 28, end: 30 },
        { text: 'บทสรุป', start: 30, end: 50 }
      ],
      durationSeconds: 50,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 100
    });

    expect(cuts[0]?.end).toBe(7);
  });

  it('keeps a complete short hook even when previous speech is close', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'เนื้อหาก่อนหน้า', start: 8, end: 10 },
        { text: 'หยุดก่อน', start: 10, end: 12 },
        { text: 'ประโยคสำรองหลังจังหวะพัก', start: 12.5, end: 20 },
        { text: 'รายละเอียดที่เล่าต่อ', start: 20, end: 30 },
        { text: 'ช่วงปิดของประโยคสำรอง', start: 30, end: 32.5 },
        { text: 'บทสรุป', start: 32.5, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 300
    });

    expect(cuts).toEqual([
      { start: 0, end: 10 },
      { start: 30, end: 40 }
    ]);
  });

  it('handles timing jitter and safe boundaries for short openings', () => {
    const previous = { text: 'เนื้อหาก่อนหน้า', start: 8, end: 10.01 };
    const fragment = { text: 'ตามที่เรา', start: 10, end: 12 };

    expect(
      opensDuringContinuousSpeech(fragment, [fragment, previous])
    ).toBe(true);
    const ambiguousContinuation = {
      text: 'ต้องดูแลต่อเนื่อง',
      start: 10,
      end: 12
    };
    expect(
      opensDuringContinuousSpeech(ambiguousContinuation, [
        previous,
        ambiguousContinuation
      ])
    ).toBe(true);
    const completeHook = { text: 'หยุดก่อน!', start: 10, end: 12 };
    expect(
      opensDuringContinuousSpeech(completeHook, [previous, completeHook])
    ).toBe(false);
    const politeContinuation = {
      text: 'มันช่วยได้จริงค่ะ',
      start: 10,
      end: 12
    };
    expect(
      opensDuringContinuousSpeech(politeContinuation, [
        {
          text: 'สิ่งที่อยากบอกก็คือ',
          start: 8,
          end: 10
        },
        politeContinuation
      ])
    ).toBe(true);
    expect(
      opensDuringContinuousSpeech(fragment, [
        { text: 'จบประโยคก่อนหน้า.', start: 8, end: 10 },
        fragment
      ])
    ).toBe(false);
    expect(
      opensDuringContinuousSpeech(fragment, [
        { text: 'มีจังหวะพัก', start: 8, end: 9.649 },
        fragment
      ])
    ).toBe(false);
    const longOpening = { text: 'ประโยคสมบูรณ์', start: 10, end: 12.501 };
    expect(
      opensDuringContinuousSpeech(longOpening, [previous, longOpening])
    ).toBe(false);
  });

  it('does not start or end the kept clip inside a transcript cue', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 112.762 },
        { start: 142.762, end: 150.649 }
      ],
      segments: [
        {
          text: 'opening cue from the live Thai clip',
          start: 112.081,
          end: 112.912
        },
        {
          text: 'closing cue from the live Thai clip',
          start: 142.2,
          end: 143.1
        }
      ],
      durationSeconds: 150.649,
      targetDurationSeconds: 30
    });

    expect(cuts).toEqual([
      { start: 0, end: 113.1 },
      { start: 143.1, end: 150.649 }
    ]);
  });

  it('repairs a Thai word split before accepting a shared segment boundary', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 113.742 },
        { start: 123.742, end: 130 }
      ],
      segments: [
        { text: 'คะเก็บชีวิ', start: 112.912, end: 113.742 },
        { text: 'ตสองข้าง', start: 113.742, end: 114.531 },
        { text: 'ประโยคถัดไป', start: 114.531, end: 123.742 }
      ],
      durationSeconds: 130,
      targetDurationSeconds: 10
    });

    expect(cuts[0]?.end).not.toBe(113.742);
    expect(cuts[0]?.end).toBe(114.531);
  });

  it('rejects a snapped candidate that keeps only a silent gap', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [
        { text: 'first complete cue', start: 0, end: 20 },
        { text: 'second complete cue', start: 21, end: 40 }
      ],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 0
    });

    expect(cuts).toEqual([{ start: 0, end: 20 }]);
  });

  it('keeps the exact target as fallback when one cue exceeds the target', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 40 }
      ],
      segments: [{ text: 'one long complete cue', start: 0, end: 40 }],
      durationSeconds: 40,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 0
    });

    expect(cuts).toEqual([
      { start: 0, end: 10 },
      { start: 30, end: 40 }
    ]);
  });

  it('rejects a suggested window with negligible speech when a meaningful alternative exists', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [
        { start: 0, end: 10 },
        { start: 30, end: 60 }
      ],
      segments: [
        { text: 'tiny speech fragment', start: 29.99, end: 30 },
        { text: 'complete spoken alternative', start: 40, end: 42 }
      ],
      durationSeconds: 60,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 0
    });

    expect(cuts).toEqual([
      { start: 0, end: 22 },
      { start: 42, end: 60 }
    ]);
  });

  it('does not count duplicate overlapping cues as extra spoken time', () => {
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [{ start: 30, end: 60 }],
      segments: [
        { text: 'duplicate cue one', start: 10, end: 12 },
        { text: 'duplicate cue two', start: 10, end: 12 },
        { text: 'meaningful alternative', start: 40, end: 43 }
      ],
      durationSeconds: 60,
      targetDurationSeconds: 30,
      weakOpeningPenalty: 0
    });

    expect(cuts).toEqual([
      { start: 0, end: 13 },
      { start: 43, end: 60 }
    ]);
  });

  it('does not let duplicate highlight signals change the chosen window', () => {
    const firstHighlight = { text: 'ราคา', start: 0, end: 5 };
    const strongerHighlight = { text: 'ราคากด', start: 20, end: 25 };
    const request = {
      suggestedCuts: [],
      durationSeconds: 30,
      targetDurationSeconds: 10,
      weakOpeningPenalty: 0
    };
    const withoutDuplicate = buildCoherentHighlightCuts({
      ...request,
      segments: [firstHighlight, strongerHighlight]
    });
    const withDuplicate = buildCoherentHighlightCuts({
      ...request,
      segments: [firstHighlight, { ...firstHighlight }, strongerHighlight]
    });

    expect(withDuplicate).toEqual(withoutDuplicate);
  });

  it('prefers an exact safe target over a much shorter suggested window', () => {
    const boundaries = [0, 12, 22, 32, 42, 52, 60];
    const cuts = buildCoherentHighlightCuts({
      suggestedCuts: [{ start: 20, end: 60 }],
      segments: boundaries.slice(0, -1).map((start, index) => ({
        text: `complete cue ${index + 1}`,
        start,
        end: boundaries[index + 1]!
      })),
      durationSeconds: 60,
      targetDurationSeconds: 20,
      weakOpeningPenalty: 0
    });

    expect(cuts).toEqual([
      { start: 0, end: 12 },
      { start: 32, end: 60 }
    ]);
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
    expect(
      isReliableHighlightSegment({
        text: 'Т็อปปิงต่างๆ จากเชียงใหม่',
        start: 12,
        end: 16,
        avgLogprob: -0.2
      })
    ).toBe(false);
    expect(
      isReliableHighlightSegment({
        text: 'ไป Weekend Market กันค่ะ',
        start: 16,
        end: 20,
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

  it('uses Gemini to plan from the timestamped transcript', async () => {
    let requestedUrl = '';
    let requestedBody: Record<string, unknown> | undefined;
    const provider = createGeminiEditPlanProvider({
      apiKey: 'gemini-key',
      model: 'gemini-3.5-flash-lite',
      fallback: createMockEditPlanProvider(),
      fetchImpl: async (url, init) => {
        requestedUrl = url;
        requestedBody = JSON.parse(String(init.body)) as Record<string, unknown>;
        return {
          ok: true,
          json: async () => ({
            candidates: [
              {
                content: {
                  parts: [
                    {
                      text:
                        '{"cuts":[{"start":0,"end":5}],"summary":"เลือกช่วงขายที่ชัดที่สุด"}'
                    }
                  ]
                }
              }
            ]
          })
        };
      }
    });

    const result = await provider.plan({
      durationSeconds: 30,
      targetDurationSeconds: 25,
      segments: [
        { text: 'ประโยคเปิดที่น่าสนใจ', start: 5, end: 10 },
        { text: 'อธิบายจุดเด่นของสินค้า', start: 10, end: 30 }
      ]
    });

    expect(requestedUrl).toContain(
      '/models/gemini-3.5-flash-lite:generateContent'
    );
    expect(requestedUrl).toContain('key=gemini-key');
    expect(requestedBody?.generationConfig).toEqual({
      responseMimeType: 'application/json'
    });
    expect(requestedBody?.generationConfig).not.toHaveProperty('temperature');
    expect(result.model).toBe('gemini-3.5-flash-lite');
    expect(result.cuts).toEqual([{ start: 0, end: 5 }]);
  });

  it('selects Gemini from config and falls back to PostDee rules', async () => {
    const config = readServerConfig({
      EDIT_PLAN_PROVIDER: 'gemini',
      GEMINI_API_KEY: 'gemini-key',
      GEMINI_EDIT_PLAN_MODEL: 'gemini-3.5-flash-lite'
    });
    const provider = createEditPlanProviderFromConfig({
      config,
      fetchImpl: async () => ({
        ok: false,
        status: 503,
        json: async () => ({})
      })
    });

    const result = await provider.plan({
      durationSeconds: 10,
      targetDurationSeconds: 5,
      segments: []
    });

    expect(result.model).toBe('mock-highlight-rule');
    expect(result.cuts).toEqual([{ start: 5, end: 10 }]);
  });

  it.each([
    { label: 'empty', payload: { candidates: [] } },
    {
      label: 'malformed',
      payload: {
        candidates: [{ content: { parts: [{ text: 'not-json' }] } }]
      }
    }
  ])('falls back to PostDee rules for a $label Gemini response', async ({
    payload
  }) => {
    const provider = createGeminiEditPlanProvider({
      apiKey: 'gemini-key',
      model: 'gemini-2.5-flash-lite',
      fallback: createMockEditPlanProvider(),
      fetchImpl: async () => ({
        ok: true,
        json: async () => payload
      })
    });

    const result = await provider.plan({
      durationSeconds: 10,
      targetDurationSeconds: 5,
      segments: []
    });

    expect(result.model).toBe('mock-highlight-rule');
    expect(result.cuts).toEqual([{ start: 5, end: 10 }]);
  });

  it('requires a Gemini key when Gemini edit planning is selected', () => {
    const config = readServerConfig({ EDIT_PLAN_PROVIDER: 'gemini' });

    expect(() => createEditPlanProviderFromConfig({ config })).toThrow(
      'GEMINI_API_KEY is required when EDIT_PLAN_PROVIDER is gemini'
    );
  });
});
