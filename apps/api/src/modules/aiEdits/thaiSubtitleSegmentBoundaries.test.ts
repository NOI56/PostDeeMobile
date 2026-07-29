import { describe, expect, it } from 'vitest';

import { repairThaiSubtitleSegmentBoundaries } from './thaiSubtitleSegmentBoundaries.js';

describe('Thai subtitle segment boundary repair', () => {
  it('merges adjacent provider fragments split inside one Thai word', () => {
    expect(
      repairThaiSubtitleSegmentBoundaries(
        [
          { text: 'ชีวิ', start: 0, end: 1 },
          { text: 'ต', start: 1.04, end: 1.4 }
        ],
        'th',
        'ชีวิต'
      )
    ).toEqual([{ text: 'ชีวิต', start: 0, end: 1.4 }]);
  });

  it('does not merge Thai fragments separated by a long silence', () => {
    expect(
      repairThaiSubtitleSegmentBoundaries(
        [
          { text: 'ชีวิ', start: 0, end: 1 },
          { text: 'ต', start: 10, end: 11 }
        ],
        'th',
        'ชีวิต'
      )
    ).toEqual([
      { text: 'ชีวิ', start: 0, end: 1 },
      { text: 'ต', start: 10, end: 11 }
    ]);
  });

  it('repairs the real Thai mid-word fragments seen in a rendered clip', () => {
    expect(
      repairThaiSubtitleSegmentBoundaries(
        [
          { text: 'คะเก็บชีวิตส', start: 0, end: 1 },
          { text: 'องข้างทาง', start: 1.04, end: 2 },
          { text: 'แต่จะเป็นอาหา', start: 2.04, end: 3 },
          { text: 'รข้างทางต่าง', start: 3.05, end: 4 },
          { text: 'ๆเป็นบะหมี่ ขนม', start: 4.08, end: 5.5 }
        ],
        'th',
        'คะเก็บชีวิตสองข้างทางแต่จะเป็นอาหารข้างทางต่างๆเป็นบะหมี่ ขนม'
      )
    ).toEqual([
      { text: 'คะเก็บชีวิตสองข้างทาง', start: 0, end: 2 },
      {
        text: 'แต่จะเป็นอาหารข้างทางต่างๆเป็นบะหมี่ ขนม',
        start: 2.04,
        end: 5.5
      }
    ]);
  });

  it.each([
    {
      text: 'ดุ๊กดิ๊ก',
      fragments: [
        { text: 'ดุ๊', start: 0, end: 0.45 },
        { text: 'กดิ๊ก', start: 0.45, end: 1 }
      ]
    },
    {
      text: 'ซุปเปอร์สตาร์',
      fragments: [
        { text: 'ซุปเปอร์ส', start: 0, end: 0.75 },
        { text: 'ตาร์', start: 0.75, end: 1.2 }
      ]
    },
    {
      text: 'สวนสัตว์เขาเขียว',
      fragments: [
        { text: 'สวน', start: 0, end: 0.35 },
        { text: 'สัตว์เขาเขียว', start: 0.35, end: 1.2 }
      ]
    }
  ])(
    'keeps the real Thai term $text intact across provider fragments',
    ({ text, fragments }) => {
      expect(
        repairThaiSubtitleSegmentBoundaries(fragments, 'th', text)
      ).toEqual([{
        text,
        start: fragments[0]!.start,
        end: fragments.at(-1)!.end
      }]);
    }
  );

  it('keeps adjacent segments separate at a real Thai word boundary', () => {
    expect(
      repairThaiSubtitleSegmentBoundaries(
        [
          { text: 'วันนี้', start: 0, end: 0.5 },
          { text: 'ไปตลาด', start: 0.55, end: 1.3 }
        ],
        'th',
        'วันนี้ไปตลาด'
      )
    ).toEqual([
      { text: 'วันนี้', start: 0, end: 0.5 },
      { text: 'ไปตลาด', start: 0.55, end: 1.3 }
    ]);
  });
});
