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

const realClipHashtags = ['#PostDee', '#ShortVideo', '#Affiliate', '#ViralClip', '#OnlineSeller'];
const defaultSeoKeywords = ['short video', 'affiliate seller', 'online shop', 'viral hook', 'product clip'];

export type RealClipCaptionMode = 'AUDIO_ONLY' | 'AUDIO_WITH_FRAMES';

export type RealClipCaptionRequest = {
  videoS3Key: string;
  guidance?: string;
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

  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 3);
};

const readBoolean = (value: unknown) => value === true;

export const validateRealClipCaptionRequest = (body: unknown) => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const videoS3Key = readRequiredString(payload.videoS3Key);

  if (!videoS3Key) {
    return {
      ok: false as const,
      message: 'videoS3Key is required'
    };
  }

  return {
    ok: true as const,
    request: {
      videoS3Key,
      guidance: readOptionalString(payload.guidance),
      selectedFrameKeys: normalizeStringList(payload.selectedFrameKeys),
      deleteAfterUse: readBoolean(payload.deleteAfterUse)
    }
  };
};

const readClipName = (videoS3Key: string) => {
  const parts = videoS3Key.split(/[\\/]/);
  return parts.at(-1) ?? videoS3Key;
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

const readTranscriptExcerpt = (transcript?: RealClipCaptionTranscriptContext) => {
  const text = transcript?.text.trim();

  if (!text) {
    return undefined;
  }

  return text.length > 180 ? `${text.slice(0, 180)}...` : text;
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
  const clipName = readClipName(request.videoS3Key);
  const modeLabel = mode === 'AUDIO_ONLY' ? 'clip audio' : 'clip audio and selected frames';
  const context = buildRealClipCaptionContext(transcript);
  const guidanceText = request.guidance ? ` Extra direction: ${request.guidance}.` : '';
  const transcriptExcerpt = readTranscriptExcerpt(transcript);
  const transcriptText = transcriptExcerpt ? ` Transcript excerpt: ${transcriptExcerpt}.` : '';
  const globalDirection =
    context.detectedSpokenLanguage === 'auto'
      ? 'Auto-detect caption language and market from the selected clip.'
      : `Detected spoken language: ${context.selectedCaptionLanguage} (${context.detectedSpokenLanguage}). Target market suggestion: ${context.selectedTargetMarket}.`;
  const hooks = [
    `Stop scrolling if this problem sounds familiar: ${clipName}`,
    `Before you buy, watch what this clip shows about ${clipName}`,
    `The quick reason this product clip can convert viewers`
  ];
  const captionOptions = [
    `${hooks[0]}\nThis caption is drafted from ${modeLabel}. ${globalDirection}${transcriptText}${guidanceText}\n${realClipHashtags.join(' ')}`,
    `${hooks[1]}\nUse the strongest moment in ${clipName} as the first line. ${globalDirection}${transcriptText}${guidanceText}\n${realClipHashtags.join(' ')}`,
    `${hooks[2]}\nKeep the CTA simple and send viewers to the bio or product link. ${globalDirection}${transcriptText}${guidanceText}\n${realClipHashtags.join(' ')}`
  ];

  return {
    model: 'local-real-clip-template',
    caption: captionOptions[0],
    captionOptions,
    hooks,
    hashtags: [...realClipHashtags],
    seoKeywords: [...defaultSeoKeywords],
    searchTitle: `Best moments from ${clipName}`,
    affiliateLinkPlaceholder,
    context,
    source: {
      videoS3Key: request.videoS3Key,
      mode,
      selectedFrameCount: mode === 'AUDIO_WITH_FRAMES' ? request.selectedFrameKeys.length : 0
    }
  };
};
