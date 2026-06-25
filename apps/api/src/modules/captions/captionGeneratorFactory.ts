import type { ServerConfig } from '../../config/env.js';
import { generateLocalAffiliateCaption } from './captionService.js';

export const thaiAffiliateCaptionSystemPrompt =
  'Act as a Thai affiliate marketer. Write an engaging, clickbaity caption in Thai using emojis. Include 5 trending hashtags. Leave a placeholder for an affiliate link at the bottom.';

const affiliateLinkPlaceholder = '[ใส่ลิงก์ Affiliate ที่นี่]';
const fallbackHashtags = ['#ของดีบอกต่อ', '#ช้อปออนไลน์', '#โปรดี', '#รีวิวจริง', '#สายช้อป'];

// Broadly-available Gemini model(s) to try when the configured model is
// overloaded, before the caption route degrades to the local template.
const defaultGeminiFallbackModels = ['gemini-2.0-flash'];

export type CaptionGeneratorResult = {
  caption: string;
  hashtags: string[];
  affiliateLinkPlaceholder: string;
  model: string;
};

export type CaptionGenerator = {
  generate: (keywords: string[]) => Promise<CaptionGeneratorResult>;
};

type CaptionProviderConfig = Pick<
  ServerConfig,
  | 'captionProvider'
  | 'openAiApiKey'
  | 'geminiApiKey'
  | 'openAiCaptionModel'
  | 'geminiCaptionModel'
>;

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

type OpenAiChatCompletionResponse = {
  choices?: Array<{
    message?: {
      content?: string;
    };
  }>;
};

type GeminiGenerateContentResponse = {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
      }>;
    };
  }>;
};

/** Error from a caption provider HTTP call, carrying the HTTP status if any. */
export class CaptionProviderError extends Error {
  constructor(
    message: string,
    readonly status?: number
  ) {
    super(message);
    this.name = 'CaptionProviderError';
  }
}

const retryableStatuses = new Set([429, 500, 502, 503, 504]);

const isRetryableStatus = (status?: number) =>
  status !== undefined && retryableStatuses.has(status);

const defaultSleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

export type CaptionRetryOptions = {
  maxAttempts?: number;
  sleep?: (ms: number) => Promise<void>;
  backoffMs?: number;
};

/**
 * Calls a caption provider, retrying transient failures (network errors and
 * retryable HTTP statuses such as 503 from an overloaded model) with
 * exponential backoff. Client errors like 400/401/403 are not retried — they
 * will not succeed on a repeat and would waste quota.
 */
const requestCaptionContent = async ({
  fetchImpl,
  url,
  init,
  readContent,
  providerName,
  maxAttempts = 3,
  sleep = defaultSleep,
  backoffMs = 300
}: {
  fetchImpl: FetchImpl;
  url: string;
  init: RequestInit;
  readContent: (payload: unknown) => string | undefined;
  providerName: string;
} & CaptionRetryOptions): Promise<string> => {
  let lastError: unknown;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    let response: FetchResponse;

    try {
      response = await fetchImpl(url, init);
    } catch (error) {
      lastError = error;

      if (attempt < maxAttempts) {
        await sleep(backoffMs * 2 ** (attempt - 1));
        continue;
      }

      throw error;
    }

    if (!response.ok) {
      if (isRetryableStatus(response.status) && attempt < maxAttempts) {
        await sleep(backoffMs * 2 ** (attempt - 1));
        continue;
      }

      throw new CaptionProviderError(
        `${providerName} caption request failed with status ${response.status ?? 'unknown'}`,
        response.status
      );
    }

    const content = readContent(await response.json());

    if (!content) {
      throw new CaptionProviderError(
        `${providerName} caption response did not include caption content`
      );
    }

    return content;
  }

  throw lastError instanceof Error
    ? lastError
    : new Error(`${providerName} caption request failed`);
};

const extractHashtags = (caption: string) => {
  const hashtags = caption.match(/#[\p{L}\p{M}\p{N}_]+/gu) ?? [];
  const uniqueHashtags = [...new Set(hashtags)];

  return uniqueHashtags.length > 0 ? uniqueHashtags.slice(0, 5) : [...fallbackHashtags];
};

const readCaptionContent = (payload: unknown) => {
  const response = payload as OpenAiChatCompletionResponse;
  return response.choices?.[0]?.message?.content?.trim();
};

const readGeminiCaptionContent = (payload: unknown) => {
  const response = payload as GeminiGenerateContentResponse;
  const parts = response.candidates?.[0]?.content?.parts ?? [];
  const caption = parts
    .map((part) => part.text)
    .filter((text): text is string => typeof text === 'string')
    .join('')
    .trim();

  return caption.length > 0 ? caption : undefined;
};

const createLocalCaptionGenerator = (): CaptionGenerator => ({
  generate: async (keywords) => generateLocalAffiliateCaption(keywords)
});

export const createOpenAiCaptionGenerator = ({
  apiKey,
  model,
  fetchImpl = fetch,
  ...retryOptions
}: {
  apiKey: string;
  model: string;
  fetchImpl?: FetchImpl;
} & CaptionRetryOptions): CaptionGenerator => ({
  generate: async (keywords) => {
    const caption = await requestCaptionContent({
      fetchImpl,
      url: 'https://api.openai.com/v1/chat/completions',
      init: {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model,
          messages: [
            {
              role: 'system',
              content: thaiAffiliateCaptionSystemPrompt
            },
            {
              role: 'user',
              content: `Keywords: ${keywords.join(', ')}`
            }
          ],
          temperature: 0.8
        })
      },
      readContent: readCaptionContent,
      providerName: 'OpenAI',
      ...retryOptions
    });

    return {
      model,
      caption,
      hashtags: extractHashtags(caption),
      affiliateLinkPlaceholder
    };
  }
});

export const createGeminiCaptionGenerator = ({
  apiKey,
  model,
  fallbackModels = [],
  fetchImpl = fetch,
  ...retryOptions
}: {
  apiKey: string;
  model: string;
  // Models to try, in order, if the primary stays unavailable (e.g. 503 from an
  // overloaded model). Falls through to these before the route's local template.
  fallbackModels?: string[];
  fetchImpl?: FetchImpl;
} & CaptionRetryOptions): CaptionGenerator => ({
  generate: async (keywords) => {
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
        const caption = await requestCaptionContent({
          fetchImpl,
          url: url.toString(),
          init: {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              systemInstruction: {
                parts: [
                  {
                    text: thaiAffiliateCaptionSystemPrompt
                  }
                ]
              },
              contents: [
                {
                  role: 'user',
                  parts: [
                    {
                      text: `Keywords: ${keywords.join(', ')}`
                    }
                  ]
                }
              ],
              generationConfig: {
                temperature: 0.8
              }
            })
          },
          readContent: readGeminiCaptionContent,
          providerName: 'Gemini',
          ...retryOptions
        });

        return {
          model: candidateModel,
          caption,
          hashtags: extractHashtags(caption),
          affiliateLinkPlaceholder
        };
      } catch (error) {
        lastError = error;

        // A rejected key/permission won't be fixed by another model, so stop.
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
      : new Error('Gemini caption request failed');
  }
});

export const createCaptionGeneratorFromConfig = ({
  config,
  fetchImpl
}: {
  config: CaptionProviderConfig;
  fetchImpl?: FetchImpl;
}): CaptionGenerator => {
  if (config.captionProvider === 'openai') {
    if (!config.openAiApiKey) {
      throw new Error('OPENAI_API_KEY is required when CAPTION_PROVIDER is openai');
    }

    return createOpenAiCaptionGenerator({
      apiKey: config.openAiApiKey,
      model: config.openAiCaptionModel,
      fetchImpl
    });
  }

  if (config.captionProvider === 'gemini') {
    if (!config.geminiApiKey) {
      throw new Error('GEMINI_API_KEY is required when CAPTION_PROVIDER is gemini');
    }

    return createGeminiCaptionGenerator({
      apiKey: config.geminiApiKey,
      model: config.geminiCaptionModel,
      // Try a different, broadly-available model before degrading to the local
      // template when the primary model is overloaded (503).
      fallbackModels: defaultGeminiFallbackModels.filter(
        (fallbackModel) => fallbackModel !== config.geminiCaptionModel
      ),
      fetchImpl
    });
  }

  return createLocalCaptionGenerator();
};
