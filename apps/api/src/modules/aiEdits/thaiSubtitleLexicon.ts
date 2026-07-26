import thaiWordcut from 'thai-wordcut-js';

export type ThaiSubtitleTextPart = {
  segment: string;
  isWordLike: boolean;
};

const fallbackThaiWordSegmenter = new Intl.Segmenter('th', {
  granularity: 'word'
});
let thaiWordcutReady = false;

try {
  thaiWordcut.init();
  thaiWordcutReady = true;
} catch {
  // ICU remains available if the bundled dictionary cannot initialize.
}

const segmentWithIntl = (value: string): ThaiSubtitleTextPart[] =>
  Array.from(fallbackThaiWordSegmenter.segment(value), (part) => ({
    segment: part.segment.normalize('NFC'),
    isWordLike: Boolean(part.isWordLike)
  }));

/**
 * Segments Thai with the bundled dictionary and keeps every source character.
 * ICU is the safe fallback for unsupported or malformed dictionary output.
 */
export const segmentThaiSubtitleRun = (
  value: string
): ThaiSubtitleTextPart[] => {
  const normalized = value.normalize('NFC');

  return normalized
    .split(/(\s+|\p{Script_Extensions=Thai}+)/u)
    .filter(Boolean)
    .flatMap((run): ThaiSubtitleTextPart[] => {
      if (/^\s+$/u.test(run)) {
        return [{ segment: run, isWordLike: false }];
      }
      if (
        !/^\p{Script_Extensions=Thai}+$/u.test(run) ||
        !thaiWordcutReady
      ) {
        return segmentWithIntl(run);
      }

      try {
        const parts = thaiWordcut.cutIntoRanges(run).map((range) => {
          const segment = (range.text ?? run.slice(range.s, range.e))
            .normalize('NFC');
          return {
            segment,
            isWordLike: /[\p{L}\p{N}]/u.test(segment)
          };
        });
        return parts.length > 0 &&
          parts.map((part) => part.segment).join('') === run
          ? parts
          : segmentWithIntl(run);
      } catch {
        return segmentWithIntl(run);
      }
    });
};

/**
 * Thai semantic units that ICU intentionally tokenizes as multiple words but
 * viewers read as one compound. Subtitle cues must not put a boundary inside
 * these values.
 *
 * Keep this evidence-based and shared by provider normalization and recipe
 * generation so their word boundaries cannot disagree.
 */
export const protectedThaiSubtitleCompounds = [
  'ซุปเปอร์สตาร์',
  'ซูเปอร์สตาร์',
  'นักท่องเที่ยว',
  'เพราะฉะนั้น',
  'ความแตกต่าง',
  'เจ้าหน้าที่',
  'ผู้เสียหาย',
  'ที่ผ่านมา',
  'เนื่องจาก',
  'รูปลักษณ์',
  'ร้านอาหาร',
  'สวนสัตว์',
  'เมืองหลวง',
  'เขาเขียว',
  'เพศเมีย',
  'ดังกล่าว',
  'เท่าไหร่',
  'ส่วนมาก',
  'ชาวบ้าน',
  'ต่างๆ',
  'ฟุตบอล',
  'ทั่วไป',
  'วันนี้',
  'ยุ่นเพียร',
  'วรภพ'
] as const;
