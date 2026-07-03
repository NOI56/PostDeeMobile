import type { EditPlanCut, EditPlanResult } from './editPlanProvider.js';
import type {
  TranscriptSegment,
  TranscriptWord,
  TranscriptionResult
} from './transcriptionProvider.js';

export const aiEditCapabilityKeys = [
  'subtitle',
  'silence',
  'filler',
  'hook',
  'beatsync',
  'reframe',
  'zoom',
  'color',
  'sfx',
  'audio',
  'translate',
  'pricetag',
  'cta',
  'watermark'
] as const;

export type AiEditCapabilityKey = (typeof aiEditCapabilityKeys)[number];
export type AiEditCapabilityFlags = Record<AiEditCapabilityKey, boolean>;
export type AiEditCapabilityState = 'applied' | 'hinted' | 'planned' | 'skipped';

export type AiEditCapabilityStatus = {
  enabled: boolean;
  state: AiEditCapabilityState;
  message: string;
};

export type AiEditRecipeSettings = {
  subtitleStyle?: string;
  subtitleColor?: string;
  subtitleWordsPerLine?: number;
  subtitlePosition?: string;
  ctaText?: string;
  ctaDesign?: string;
  priceText?: string;
  watermarkText?: string;
  toneFilter?: string;
  zoomLevel?: string;
};

export type AiEditRecipe = {
  version: 1;
  status: 'ready';
  renderMode: 'mobile-ffmpeg';
  styleId?: string;
  prompt?: string;
  transcript: {
    text: string;
    language: string;
    durationSeconds: number;
    segments: TranscriptSegment[];
    words: TranscriptWord[];
    model: string;
  };
  subtitles: {
    enabled: boolean;
    segments: TranscriptSegment[];
    style: {
      mode: string;
      color: string;
      wordsPerLine: number;
      position: string;
    };
  };
  cutRanges: EditPlanCut[];
  silenceRanges: EditPlanCut[];
  fillerRanges: EditPlanCut[];
  plan: {
    cuts: EditPlanCut[];
    summary: string;
    model: string;
  };
  overlays: {
    cta: { enabled: boolean; text: string; design: string };
    priceTag: { enabled: boolean; text: string };
    watermark: { enabled: boolean; text: string };
  };
  renderHints: {
    hookSeconds?: number;
    toneFilter?: string;
    zoomLevel?: string;
  };
  capabilities: Record<AiEditCapabilityKey, AiEditCapabilityStatus>;
};

const defaultCapabilities: AiEditCapabilityFlags = {
  subtitle: true,
  silence: true,
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
};

const plannedCapabilities = new Set<AiEditCapabilityKey>([
  'beatsync',
  'reframe',
  'sfx',
  'audio',
  'translate'
]);

const fillerWords = ['เอ่อ', 'อ่า', 'แบบว่า', 'คือว่า', 'ประมาณว่า'];

const readString = (value: unknown): string | undefined => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readPositiveInteger = (value: unknown): number | undefined => {
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    return undefined;
  }

  return value;
};

export const readAiEditCapabilities = (value: unknown): AiEditCapabilityFlags => {
  const flags: AiEditCapabilityFlags = { ...defaultCapabilities };

  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return flags;
  }

  const record = value as Record<string, unknown>;

  for (const key of aiEditCapabilityKeys) {
    if (typeof record[key] === 'boolean') {
      flags[key] = record[key];
    }
  }

  return flags;
};

export const readAiEditRecipeSettings = (value: unknown): AiEditRecipeSettings => {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return {};
  }

  const record = value as Record<string, unknown>;

  return {
    subtitleStyle: readString(record.subtitleStyle),
    subtitleColor: readString(record.subtitleColor),
    subtitleWordsPerLine: readPositiveInteger(record.subtitleWordsPerLine),
    subtitlePosition: readString(record.subtitlePosition),
    ctaText: readString(record.ctaText),
    ctaDesign: readString(record.ctaDesign),
    priceText: readString(record.priceText),
    watermarkText: readString(record.watermarkText),
    toneFilter: readString(record.toneFilter),
    zoomLevel: readString(record.zoomLevel)
  };
};

const findSilenceRanges = (segments: TranscriptSegment[], minGapSeconds = 0.6): EditPlanCut[] => {
  if (segments.length < 2) {
    return [];
  }

  const sorted = [...segments].sort((a, b) => a.start - b.start);
  const ranges: EditPlanCut[] = [];

  for (let index = 0; index < sorted.length - 1; index += 1) {
    const current = sorted[index]!;
    const next = sorted[index + 1]!;
    const start = Math.max(0, current.end);
    const end = Math.max(start, next.start);

    if (end - start >= minGapSeconds) {
      ranges.push({ start, end });
    }
  }

  return ranges;
};

const findFillerRanges = (words: TranscriptWord[]): EditPlanCut[] =>
  words
    .filter((word) => fillerWords.some((filler) => word.word.includes(filler)))
    .map((word) => ({ start: word.start, end: word.end }))
    .filter((range) => range.end > range.start);

const inferPriceText = (transcriptText: string): string => {
  const match = transcriptText.match(/(?:ราคา\s*)?(\d[\d,]*(?:\.\d+)?)\s*(บาท|฿)/u);
  if (!match) {
    return '';
  }

  const unit = match[2] === '฿' ? '฿' : 'บาท';
  return `${match[1]} ${unit}`;
};

const buildCapabilityStatus = ({
  key,
  enabled,
  state,
  message
}: {
  key: AiEditCapabilityKey;
  enabled: boolean;
  state?: AiEditCapabilityState;
  message?: string;
}): AiEditCapabilityStatus => {
  if (!enabled) {
    return { enabled, state: 'skipped', message: 'ไม่ได้เลือกใน UI' };
  }

  if (plannedCapabilities.has(key)) {
    return {
      enabled,
      state: 'planned',
      message: 'รับค่าไว้ใน recipe แล้ว แต่ต้องใช้การวิเคราะห์เสียง/ภาพขั้นต่อไปก่อนทำจริง'
    };
  }

  return {
    enabled,
    state: state ?? 'hinted',
    message: message ?? 'ส่งเป็นคำแนะนำให้ mobile renderer ใช้ตอน export'
  };
};

const sortRanges = (ranges: EditPlanCut[]) =>
  [...ranges].sort((a, b) => a.start - b.start || a.end - b.end);

export const buildAiEditRecipe = ({
  transcript,
  capabilities,
  settings,
  styleId,
  prompt,
  plan
}: {
  transcript: TranscriptionResult;
  capabilities: AiEditCapabilityFlags;
  settings: AiEditRecipeSettings;
  styleId?: string;
  prompt?: string;
  plan?: EditPlanResult;
}): AiEditRecipe => {
  const subtitleSegments = capabilities.subtitle ? transcript.segments : [];
  const silenceRanges = capabilities.silence ? findSilenceRanges(transcript.segments) : [];
  const fillerRanges = capabilities.filler ? findFillerRanges(transcript.words) : [];
  const planCuts = plan?.cuts ?? [];
  const priceText = settings.priceText ?? inferPriceText(transcript.text);
  const ctaText = settings.ctaText ?? 'กดตะกร้าเลย';
  const watermarkText = settings.watermarkText ?? 'PostDee';

  return {
    version: 1,
    status: 'ready',
    renderMode: 'mobile-ffmpeg',
    styleId,
    prompt,
    transcript: {
      text: transcript.text,
      language: transcript.language,
      durationSeconds: transcript.durationSeconds,
      segments: transcript.segments,
      words: transcript.words,
      model: transcript.model
    },
    subtitles: {
      enabled: capabilities.subtitle,
      segments: subtitleSegments,
      style: {
        mode: settings.subtitleStyle ?? 'bold',
        color: settings.subtitleColor ?? '#FFFFFF',
        wordsPerLine: settings.subtitleWordsPerLine ?? 2,
        position: settings.subtitlePosition ?? 'bottom'
      }
    },
    cutRanges: sortRanges([...planCuts, ...silenceRanges, ...fillerRanges]),
    silenceRanges,
    fillerRanges,
    plan: {
      cuts: planCuts,
      summary: plan?.summary ?? '',
      model: plan?.model ?? 'none'
    },
    overlays: {
      cta: {
        enabled: capabilities.cta,
        text: capabilities.cta ? ctaText : '',
        design: settings.ctaDesign ?? 'button'
      },
      priceTag: {
        enabled: capabilities.pricetag,
        text: capabilities.pricetag ? priceText : ''
      },
      watermark: {
        enabled: capabilities.watermark,
        text: capabilities.watermark ? watermarkText : ''
      }
    },
    renderHints: {
      hookSeconds: capabilities.hook ? 3 : undefined,
      toneFilter: capabilities.color ? settings.toneFilter ?? 'auto-bright' : undefined,
      zoomLevel: capabilities.zoom ? settings.zoomLevel ?? 'subtle' : undefined
    },
    capabilities: {
      subtitle: buildCapabilityStatus({
        key: 'subtitle',
        enabled: capabilities.subtitle,
        state: 'applied',
        message: 'ถอดเสียงเป็นซับพร้อมเวลาให้ mobile renderer แล้ว'
      }),
      silence: buildCapabilityStatus({
        key: 'silence',
        enabled: capabilities.silence,
        state: 'applied',
        message: 'หาช่วงเงียบจากช่องว่างของ transcript แล้ว'
      }),
      filler: buildCapabilityStatus({
        key: 'filler',
        enabled: capabilities.filler,
        state: fillerRanges.length > 0 ? 'applied' : 'hinted',
        message: fillerRanges.length > 0
          ? 'พบคำฟุ่มเฟือยจาก word timing แล้ว'
          : 'รับค่าไว้แล้ว แต่ยังไม่พบคำฟุ่มเฟือยจาก transcript รอบนี้'
      }),
      hook: buildCapabilityStatus({ key: 'hook', enabled: capabilities.hook }),
      beatsync: buildCapabilityStatus({ key: 'beatsync', enabled: capabilities.beatsync }),
      reframe: buildCapabilityStatus({ key: 'reframe', enabled: capabilities.reframe }),
      zoom: buildCapabilityStatus({ key: 'zoom', enabled: capabilities.zoom }),
      color: buildCapabilityStatus({ key: 'color', enabled: capabilities.color }),
      sfx: buildCapabilityStatus({ key: 'sfx', enabled: capabilities.sfx }),
      audio: buildCapabilityStatus({ key: 'audio', enabled: capabilities.audio }),
      translate: buildCapabilityStatus({ key: 'translate', enabled: capabilities.translate }),
      pricetag: buildCapabilityStatus({ key: 'pricetag', enabled: capabilities.pricetag }),
      cta: buildCapabilityStatus({ key: 'cta', enabled: capabilities.cta }),
      watermark: buildCapabilityStatus({ key: 'watermark', enabled: capabilities.watermark })
    }
  };
};