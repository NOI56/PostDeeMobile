import { describe, expect, it } from 'vitest';

import { segmentThaiSubtitleRun } from './thaiSubtitleLexicon.js';

describe('Thai subtitle tokenizer', () => {
  it('keeps colloquial and place words intact where Intl.Segmenter does not', () => {
    expect(
      segmentThaiSubtitleRun(
        'ที่รู้อยู่ว่ากรุงเทพเนี่ยมีรถเยอะเกินไปจนกระทั่ง'
      )
        .filter((part) => part.isWordLike)
        .map((part) => part.segment)
    ).toEqual([
      'ที่',
      'รู้',
      'อยู่',
      'ว่า',
      'กรุงเทพ',
      'เนี่ย',
      'มี',
      'รถ',
      'เยอะ',
      'เกิน',
      'ไป',
      'จน',
      'กระทั่ง'
    ]);
  });

  it('keeps Latin text, numbers, spacing, and punctuation reconstructable', () => {
    const text = 'ขาย PostDee 200 บาท!';
    const parts = segmentThaiSubtitleRun(text);

    expect(parts.map((part) => part.segment).join('')).toBe(text);
    expect(
      parts
        .filter((part) => part.isWordLike)
        .map((part) => part.segment)
    ).toEqual(['ขาย', 'PostDee', '200', 'บาท']);
  });
});
