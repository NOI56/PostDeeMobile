import type { Platform } from '../posts/postStore.js';
import { readCaptionStorageIssue, readPlatformCaptionIssue } from '../posts/platformCaptionValidation.js';

const affiliateLinkPlaceholder = '[ใส่ลิงก์ Affiliate ที่นี่]';
const trendingHashtags = ['#ของดีบอกต่อ', '#ช้อปออนไลน์', '#โปรดีบอกต่อ', '#รีวิวจริง', '#สายช้อป'];
const captionKeywordMaxLength = 80;

export type GeneratedCaption = {
  caption: string;
  hashtags: string[];
  affiliateLinkPlaceholder: string;
  model: 'local-template';
};

const normalizeKeywords = (keywords: unknown) => {
  if (!Array.isArray(keywords)) {
    return [];
  }

  return keywords
    .filter((keyword): keyword is string => typeof keyword === 'string')
    .map((keyword) => keyword.trim())
    .filter(Boolean)
    .slice(0, 3);
};

export const validateCaptionKeywords = (keywords: unknown) => {
  const normalized = normalizeKeywords(keywords);

  if (normalized.length < 1 || normalized.length > 2) {
    return {
      ok: false as const,
      message: 'keywords must contain 1 or 2 non-empty values'
    };
  }

  if (normalized.some((keyword) => keyword.length > captionKeywordMaxLength)) {
    return {
      ok: false as const,
      message: `keywords must be ${captionKeywordMaxLength} characters or fewer`
    };
  }

  return {
    ok: true as const,
    keywords: normalized
  };
};

export const generateLocalAffiliateCaption = (keywords: string[]): GeneratedCaption => {
  const keywordText = keywords.join(' + ');
  const hashtags = [...trendingHashtags];

  return {
    model: 'local-template',
    affiliateLinkPlaceholder,
    hashtags,
    caption: [
      `ของมันต้องมี! ${keywordText} ตัวนี้น่าลองมาก 🔥`,
      'ใครกำลังมองหาไอเทมช่วยให้ชีวิตง่ายขึ้น ห้ามเลื่อนผ่านนะ ✨',
      'รีบเช็กโปรก่อนหมด แล้วค่อยตัดสินใจก็ยังทัน 🛒',
      '',
      hashtags.join(' '),
      '',
      affiliateLinkPlaceholder
    ].join('\n')
  };
};

export type RealClipCaptionMode = 'AUDIO_ONLY' | 'AUDIO_WITH_FRAMES';

export type RealClipCaptionWritingStyle = {
  tone: 'auto' | 'friendly' | 'playful' | 'direct_review' | 'soft_sell';
  length: 'auto' | 'short' | 'medium';
  emoji: 'auto' | 'none' | 'light';
  examples: string[];
};

export type RealClipCaptionRequest = {
  // Clip media key: the extracted M4A when mediaKind is 'audio', else the video.
  videoS3Key: string;
  mediaKind?: 'audio' | 'video';
  platforms?: Platform[];
  guidance?: string;
  writingStyle?: RealClipCaptionWritingStyle;
  selectedFrameKeys: string[];
  deleteAfterUse: boolean;
};

export type RealClipCaptionContext = {
  selectedCaptionLanguage: string;
  selectedTargetMarket: string;
  selectedTone: string;
  detectedSpokenLanguage: string;
  suggestedCaptionLanguage: string;
  suggestedTargetMarket: string;
};

export type RealClipCaptionTranscriptContext = {
  text: string;
  language: string;
  durationSeconds: number;
  model: string;
};

export type RealClipCaptionResult = {
  model: 'local-real-clip-template';
  caption: string;
  captionOptions: string[];
  hooks: string[];
  hashtags: string[];
  platformCaptions?: RealClipPlatformCaptions;
  seoKeywords: string[];
  searchTitle: string;
  affiliateLinkPlaceholder: string;
  context: RealClipCaptionContext;
  source: {
    videoS3Key: string;
    mode: RealClipCaptionMode;
    selectedFrameCount: number;
  };
};

export type RealClipPlatformCaptions = Partial<Record<Platform, { caption: string; hashtags: string[] }>>;

const captionPlatforms: readonly Platform[] = ['TIKTOK', 'YOUTUBE_SHORTS', 'INSTAGRAM_REELS', 'FACEBOOK_REELS'];

// Require every requested channel. Never silently substitute a shared caption
// for a missing AI variant or return a partial set as a successful generation.
export const readRealClipPlatformCaptions = (value: unknown, platforms: readonly Platform[]): RealClipPlatformCaptions | undefined => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const input = value as Record<string, unknown>;
  const captions: RealClipPlatformCaptions = {};
  for (const platform of platforms) {
    const entry = input[platform];
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return undefined;
    const { caption, hashtags } = entry as Record<string, unknown>;
    if (typeof caption !== 'string' || !caption.trim() || !Array.isArray(hashtags) ||
      !hashtags.every((tag) => typeof tag === 'string' && tag.trim().length > 0)) return undefined;
    const normalizedCaption = caption.trim();
    const normalizedHashtags = hashtags.map((tag: string) => tag.trim());
    // Mobile appends the tags after a blank line. Validate that delivered text,
    // including multibyte Thai characters, before accepting a paid AI result.
    const deliveredCaption = [normalizedCaption, normalizedHashtags.join(' ')].filter(Boolean).join('\n\n');
    if (readCaptionStorageIssue(deliveredCaption, [platform]) || readPlatformCaptionIssue(deliveredCaption, [platform])) return undefined;
    captions[platform] = { caption: normalizedCaption, hashtags: normalizedHashtags };
  }
  return captions;
};

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readOptionalString = (value: unknown, maxLength = 240) => {
  const trimmed = readRequiredString(value);
  return trimmed ? trimmed.slice(0, maxLength) : undefined;
};

const normalizeStringList = (value: unknown) => {
  if (!Array.isArray(value)) {
    return [];
  }

  return [...new Set(value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean))]
    .slice(0, 3);
};

// The app uploads caption frames as JPEG stills (frame_N.jpg).
const isCaptionFrameImageKey = (key: string) => /\.(?:jpe?g|png|webp)$/i.test(key);

const readBoolean = (value: unknown) => value === true;

const readStyleEnum = <T extends string>(value: unknown, values: readonly T[]): T | undefined => {
  if (value === undefined) return 'auto' as T;
  return typeof value === 'string' && values.includes(value as T) ? value as T : undefined;
};

const validateWritingStyle = (value: unknown) => {
  if (value === undefined) return { ok: true as const, style: undefined };
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return { ok: false as const, message: 'writingStyle must be an object' };
  }

  const input = value as Record<string, unknown>;
  const tone = readStyleEnum(input.tone, ['auto', 'friendly', 'playful', 'direct_review', 'soft_sell'] as const);
  const length = readStyleEnum(input.length, ['auto', 'short', 'medium'] as const);
  const emoji = readStyleEnum(input.emoji, ['auto', 'none', 'light'] as const);
  if (!tone) return { ok: false as const, message: 'writingStyle.tone is invalid' };
  if (!length) return { ok: false as const, message: 'writingStyle.length is invalid' };
  if (!emoji) return { ok: false as const, message: 'writingStyle.emoji is invalid' };

  const examples = input.examples === undefined ? [] : input.examples;
  if (!Array.isArray(examples) || examples.length > 3) {
    return { ok: false as const, message: 'writingStyle.examples must be an array of at most 3 strings' };
  }
  const normalizedExamples: string[] = [];
  for (const example of examples) {
    if (typeof example !== 'string' || !example.trim() || example.trim().length > 500) {
      return { ok: false as const, message: 'writingStyle.examples must contain non-empty strings of at most 500 characters' };
    }
    normalizedExamples.push(example.trim());
  }

  return { ok: true as const, style: { tone, length, emoji, examples: normalizedExamples } };
};

export const validateRealClipCaptionRequest = (body: unknown) => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const audioS3Key = readRequiredString(payload.audioS3Key);
  const requestedVideoS3Key = readRequiredString(payload.videoS3Key);

  if (audioS3Key && requestedVideoS3Key) {
    return {
      ok: false as const,
      message: 'Provide exactly one of audioS3Key or videoS3Key'
    };
  }

  const videoS3Key = audioS3Key ?? requestedVideoS3Key;

  if (!videoS3Key) {
    return {
      ok: false as const,
      message: 'audioS3Key or videoS3Key is required'
    };
  }

  if (audioS3Key && !audioS3Key.toLowerCase().endsWith('.m4a')) {
    return {
      ok: false as const,
      message: 'audioS3Key must identify an M4A file'
    };
  }

  const writingStyle = validateWritingStyle(payload.writingStyle);
  if (!writingStyle.ok) return writingStyle;

  const platforms = payload.platforms;
  if (platforms !== undefined && (!Array.isArray(platforms) || platforms.length < 1 || platforms.length > 4 ||
    platforms.some((platform) => typeof platform !== 'string' || !captionPlatforms.includes(platform as Platform)) ||
    new Set(platforms).size !== platforms.length)) {
    return { ok: false as const, message: 'platforms must contain 1 to 4 unique supported platforms' };
  }

  const selectedFrameKeys = normalizeStringList(payload.selectedFrameKeys);
  if (!selectedFrameKeys.every(isCaptionFrameImageKey)) {
    return {
      ok: false as const,
      code: 'AI_CAPTION_FRAME_INVALID',
      message: 'selectedFrameKeys must reference JPEG, PNG or WebP images'
    };
  }

  return {
    ok: true as const,
    request: {
      videoS3Key,
      ...(audioS3Key ? { mediaKind: 'audio' as const } : {}),
      ...(platforms !== undefined ? { platforms: platforms as Platform[] } : {}),
      guidance: readOptionalString(payload.guidance),
      ...(writingStyle.style ? { writingStyle: writingStyle.style } : {}),
      selectedFrameKeys,
      deleteAfterUse: readBoolean(payload.deleteAfterUse)
    }
  };
};

const languageProfiles: Record<string, { language: string; market: string }> = {
  ar: { language: 'Arabic', market: 'Middle East' },
  de: { language: 'German', market: 'Germany' },
  en: { language: 'English', market: 'Global' },
  es: { language: 'Spanish', market: 'Spanish-speaking markets' },
  fr: { language: 'French', market: 'France' },
  hi: { language: 'Hindi', market: 'India' },
  id: { language: 'Indonesian', market: 'Indonesia' },
  ja: { language: 'Japanese', market: 'Japan' },
  ko: { language: 'Korean', market: 'South Korea' },
  ms: { language: 'Malay', market: 'Malaysia' },
  pt: { language: 'Portuguese', market: 'Brazil' },
  th: { language: 'Thai', market: 'Thailand' },
  vi: { language: 'Vietnamese', market: 'Vietnam' },
  zh: { language: 'Chinese', market: 'Chinese-speaking markets' }
};

const normalizeLanguageCode = (language: string) =>
  language.trim().toLowerCase().split(/[-_]/)[0] || 'auto';

const readLanguageProfile = (language: string) => {
  const languageCode = normalizeLanguageCode(language);

  return {
    code: languageCode,
    ...(languageProfiles[languageCode] ?? {
      language: languageCode === 'auto' ? 'auto' : languageCode,
      market: 'Global'
    })
  };
};

const buildRealClipCaptionContext = (
  transcript?: RealClipCaptionTranscriptContext
): RealClipCaptionContext => {
  if (!transcript) {
    return {
      selectedCaptionLanguage: 'auto',
      selectedTargetMarket: 'auto',
      selectedTone: 'auto',
      detectedSpokenLanguage: 'auto',
      suggestedCaptionLanguage: 'auto',
      suggestedTargetMarket: 'auto'
    };
  }

  const profile = readLanguageProfile(transcript.language);

  return {
    selectedCaptionLanguage: profile.language,
    selectedTargetMarket: profile.market,
    selectedTone: 'auto',
    detectedSpokenLanguage: profile.code,
    suggestedCaptionLanguage: profile.language,
    suggestedTargetMarket: profile.market
  };
};

export const generateLocalRealClipCaption = ({
  request,
  mode,
  transcript
}: {
  request: RealClipCaptionRequest;
  mode: RealClipCaptionMode;
  transcript?: RealClipCaptionTranscriptContext;
}): RealClipCaptionResult => {
  const context = buildRealClipCaptionContext(transcript);
  // A local template cannot verify the current media. Keep both shared and
  // advanced fallbacks visibly blank instead of inventing a sales caption.
  const caption = '[เขียนเรื่องที่เห็นจริงในคลิปของคุณที่นี่]';
  return {
    model: 'local-real-clip-template',
    caption,
    captionOptions: [caption],
    hooks: [],
    hashtags: [],
    ...(request.platforms ? { platformCaptions: Object.fromEntries(request.platforms.map(platform =>
      [platform, { caption, hashtags: [] }])) as RealClipPlatformCaptions } : {}),
    seoKeywords: [],
    searchTitle: '',
    affiliateLinkPlaceholder,
    context,
    source: {
      videoS3Key: request.videoS3Key,
      mode,
      selectedFrameCount: mode === 'AUDIO_WITH_FRAMES' ? request.selectedFrameKeys.length : 0
    }
  };
};
