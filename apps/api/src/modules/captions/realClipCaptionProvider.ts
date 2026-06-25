import { Buffer } from 'node:buffer';

import { CaptionProviderError } from './captionGeneratorFactory.js';
import type {
  RealClipCaptionContext,
  RealClipCaptionMode,
  RealClipCaptionRequest,
  RealClipCaptionResult
} from './captionService.js';

/** A media blob (the clip audio/video, or a still frame) to send to Gemini. */
export type RealClipMediaPart = {
  data: Uint8Array;
  mimeType: string;
};

export type RealClipCaptionGenerateInput = {
  request: RealClipCaptionRequest;
  mode: RealClipCaptionMode;
  audio: RealClipMediaPart;
  /** Still frames; only sent for the Pro AUDIO_WITH_FRAMES mode. */
  frames?: RealClipMediaPart[];
};

// Same shape the route returns, but `model` is the real provider/model id
// instead of the local template literal.
export type GeneratedRealClipCaption = Omit<RealClipCaptionResult, 'model'> & {
  model: string;
};

export type RealClipCaptionProvider = {
  generate: (input: RealClipCaptionGenerateInput) => Promise<GeneratedRealClipCaption>;
};

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

export type RealClipCaptionRetryOptions = {
  maxAttempts?: number;
  sleep?: (ms: number) => Promise<void>;
  backoffMs?: number;
};

const retryableStatuses = new Set([429, 500, 502, 503, 504]);

const defaultSleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

const affiliateLinkPlaceholder = '[ใส่ลิงก์ Affiliate ที่นี่]';
const fallbackHashtags = ['#PostDee', '#ShortVideo', '#Affiliate', '#ViralClip', '#OnlineSeller'];
const fallbackSeoKeywords = ['short video', 'affiliate seller', 'online shop', 'viral hook', 'product clip'];

const systemPrompt =
  'You are an expert Thai affiliate marketer writing short-video captions. ' +
  'Analyze the clip: listen to the spoken audio (and look at any provided frames). ' +
  'Write in the language actually spoken in the clip. Return ONLY JSON.';

type GeminiResponse = {
  candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
};

const readGeminiText = (payload: unknown) => {
  const response = payload as GeminiResponse;
  const text = (response.candidates?.[0]?.content?.parts ?? [])
    .map((part) => part.text)
    .filter((value): value is string => typeof value === 'string')
    .join('')
    .trim();

  return text.length > 0 ? text : undefined;
};

const readStringList = (value: unknown, limit: number) => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, limit);
};

const readString = (value: unknown) =>
  typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;

const buildInstruction = (input: RealClipCaptionGenerateInput) => {
  const guidance = input.request.guidance
    ? ` Extra direction from the seller: ${input.request.guidance}.`
    : '';
  const sourceNote =
    input.mode === 'AUDIO_WITH_FRAMES'
      ? 'Base the caption on the spoken audio AND the selected frames.'
      : 'Base the caption on the spoken audio.';

  return (
    `${sourceNote}${guidance}\n` +
    'Respond ONLY with a JSON object using exactly these keys:\n' +
    '{"caption": string, "captionOptions": string[3], "hooks": string[3], ' +
    '"hashtags": string[5], "seoKeywords": string[5], "searchTitle": string, ' +
    '"detectedSpokenLanguage": string (ISO code like "th"), ' +
    '"captionLanguage": string, "targetMarket": string}\n' +
    'Write caption, options, hooks and searchTitle in the spoken language. ' +
    'Hashtags must start with #. Do not include any text outside the JSON.'
  );
};

const buildContext = (parsed: Record<string, unknown>): RealClipCaptionContext => {
  const detected = readString(parsed.detectedSpokenLanguage) ?? 'auto';
  const language = readString(parsed.captionLanguage) ?? 'auto';
  const market = readString(parsed.targetMarket) ?? 'auto';

  return {
    selectedCaptionLanguage: language,
    selectedTargetMarket: market,
    selectedTone: 'auto',
    detectedSpokenLanguage: detected,
    suggestedCaptionLanguage: language,
    suggestedTargetMarket: market
  };
};

const mapResult = (
  rawJson: string,
  input: RealClipCaptionGenerateInput,
  model: string
): GeneratedRealClipCaption => {
  let parsed: Record<string, unknown>;

  try {
    parsed = JSON.parse(rawJson) as Record<string, unknown>;
  } catch {
    throw new CaptionProviderError('Gemini real-clip caption returned invalid JSON');
  }

  const caption = readString(parsed.caption);

  if (!caption) {
    throw new CaptionProviderError('Gemini real-clip caption is missing a caption');
  }

  const captionOptions = readStringList(parsed.captionOptions, 3);
  const hooks = readStringList(parsed.hooks, 3);
  const hashtags = readStringList(parsed.hashtags, 5);
  const seoKeywords = readStringList(parsed.seoKeywords, 5);

  return {
    model,
    caption,
    captionOptions: captionOptions.length > 0 ? captionOptions : [caption],
    hooks,
    hashtags: hashtags.length > 0 ? hashtags : [...fallbackHashtags],
    seoKeywords: seoKeywords.length > 0 ? seoKeywords : [...fallbackSeoKeywords],
    searchTitle: readString(parsed.searchTitle) ?? caption,
    affiliateLinkPlaceholder,
    context: buildContext(parsed),
    source: {
      videoS3Key: input.request.videoS3Key,
      mode: input.mode,
      selectedFrameCount:
        input.mode === 'AUDIO_WITH_FRAMES' ? (input.frames?.length ?? 0) : 0
    }
  };
};

const toInlineData = (part: RealClipMediaPart) => ({
  inlineData: {
    mimeType: part.mimeType,
    data: Buffer.from(part.data).toString('base64')
  }
});

export const createGeminiRealClipCaptionProvider = ({
  apiKey,
  model,
  fallbackModels = [],
  fetchImpl = fetch,
  maxAttempts = 3,
  sleep = defaultSleep,
  backoffMs = 300
}: {
  apiKey: string;
  model: string;
  fallbackModels?: string[];
  fetchImpl?: FetchImpl;
} & RealClipCaptionRetryOptions): RealClipCaptionProvider => ({
  generate: async (input) => {
    const parts: unknown[] = [toInlineData(input.audio)];

    if (input.mode === 'AUDIO_WITH_FRAMES') {
      for (const frame of input.frames ?? []) {
        parts.push(toInlineData(frame));
      }
    }

    parts.push({ text: buildInstruction(input) });

    const body = JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: 'user', parts }],
      generationConfig: { temperature: 0.8, responseMimeType: 'application/json' }
    });

    const models = [model, ...fallbackModels];
    let lastError: unknown;

    for (const candidateModel of models) {
      const url = new URL(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
          candidateModel
        )}:generateContent`
      );
      url.searchParams.set('key', apiKey);

      try {
        let rawText: string | undefined;

        for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
          let response: FetchResponse;

          try {
            response = await fetchImpl(url.toString(), {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body
            });
          } catch (error) {
            if (attempt < maxAttempts) {
              await sleep(backoffMs * 2 ** (attempt - 1));
              continue;
            }
            throw error;
          }

          if (!response.ok) {
            if (
              response.status !== undefined &&
              retryableStatuses.has(response.status) &&
              attempt < maxAttempts
            ) {
              await sleep(backoffMs * 2 ** (attempt - 1));
              continue;
            }
            throw new CaptionProviderError(
              `Gemini real-clip caption failed with status ${response.status ?? 'unknown'}`,
              response.status
            );
          }

          rawText = readGeminiText(await response.json());

          if (!rawText) {
            throw new CaptionProviderError('Gemini real-clip caption returned no content');
          }

          break;
        }

        return mapResult(rawText as string, input, candidateModel);
      } catch (error) {
        lastError = error;

        // A rejected key/permission will not be fixed by another model.
        if (
          error instanceof CaptionProviderError &&
          (error.status === 401 || error.status === 403)
        ) {
          throw error;
        }
      }
    }

    throw lastError instanceof Error
      ? lastError
      : new Error('Gemini real-clip caption request failed');
  }
});

/**
 * Builds the Gemini real-clip caption provider when CAPTION_PROVIDER=gemini and
 * a key is set. Returns undefined otherwise, so the caption route falls back to
 * its legacy/local behavior.
 */
export const createRealClipCaptionProviderFromConfig = ({
  config,
  fetchImpl
}: {
  config: {
    captionProvider: string;
    geminiApiKey?: string;
    geminiCaptionModel: string;
  };
  fetchImpl?: FetchImpl;
}): RealClipCaptionProvider | undefined => {
  if (config.captionProvider !== 'gemini' || !config.geminiApiKey) {
    return undefined;
  }

  return createGeminiRealClipCaptionProvider({
    apiKey: config.geminiApiKey,
    model: config.geminiCaptionModel,
    fallbackModels: ['gemini-2.0-flash'].filter(
      (fallbackModel) => fallbackModel !== config.geminiCaptionModel
    ),
    fetchImpl
  });
};
