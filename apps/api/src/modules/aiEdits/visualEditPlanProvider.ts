import { GoogleGenAI } from '@google/genai';

import type { ServerConfig } from '../../config/env.js';
import type { RealClipMediaPart } from '../captions/realClipCaptionProvider.js';
import {
  buildCoherentHighlightCuts,
  parseLlmEditPlan,
  type EditPlanResult,
  type EditPlanSegment
} from './editPlanProvider.js';

export type VisualEditPlanInput = {
  durationSeconds: number;
  targetDurationSeconds: number;
  segments: EditPlanSegment[];
  video: RealClipMediaPart;
};

export type VisualEditPlanProvider = {
  plan: (input: VisualEditPlanInput) => Promise<EditPlanResult>;
};

type FetchHeaders = {
  get: (name: string) => string | null;
};

type FetchResponse = {
  ok: boolean;
  status?: number;
  headers: FetchHeaders;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init?: RequestInit) => Promise<FetchResponse>;

type GeminiFilesClient = {
  upload: (input: {
    file: string | Blob;
    config?: { displayName?: string; mimeType?: string };
  }) => Promise<unknown>;
  get: (input: { name: string }) => Promise<unknown>;
  delete: (input: { name: string }) => Promise<unknown>;
};

type GeminiFile = {
  name: string;
  uri: string;
  mimeType: string;
  state?: 'PROCESSING' | 'ACTIVE' | 'FAILED';
};

type GeminiResponse = {
  candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
};

const visualEditSystemPrompt =
  'You are a precise short-video editor for Thai sellers. Watch the entire ' +
  'video and use the timestamped transcript. Select the strongest coherent ' +
  'story window for the requested duration. Prefer a clear hook, visible ' +
  'product, demonstration, benefit, proof, offer, and call to action. Reject ' +
  'blurry, empty, duplicate, or visually confusing moments. Keep complete ' +
  'speech sentences and chronological order. Do not open with a Thai sentence ' +
  'fragment such as "แต่", "แล้ว", "โดย", "ซึ่ง", or "ของมาจาก" when a ' +
  'complete nearby sentence is available. Return ONLY JSON: ' +
  '{"cuts":[{"start":<sec>,"end":<sec>}],"summary":"<short Thai summary>"}. ' +
  'Cuts are time ranges to REMOVE and must stay within the clip duration.';

const readGeminiText = (payload: unknown) => {
  const response = payload as GeminiResponse;
  const text = (response.candidates?.[0]?.content?.parts ?? [])
    .map((part) => part.text)
    .filter((value): value is string => typeof value === 'string')
    .join('')
    .trim();
  return text.length > 0 ? text : undefined;
};

const readGeminiFile = (payload: unknown): GeminiFile => {
  const root = payload as { file?: Partial<GeminiFile> } & Partial<GeminiFile>;
  const file = root.file ?? root;
  if (
    typeof file.name !== 'string' ||
    typeof file.uri !== 'string' ||
    typeof file.mimeType !== 'string'
  ) {
    throw new Error('Visual edit Files API returned invalid file metadata');
  }
  return file as GeminiFile;
};

export const createGeminiVisualEditPlanProvider = ({
  apiKey,
  model,
  filesClient = new GoogleGenAI({ apiKey }).files,
  fetchImpl = fetch as unknown as FetchImpl,
  sleep = (ms: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, ms)),
  maxPollAttempts = 30
}: {
  apiKey: string;
  model: string;
  filesClient?: GeminiFilesClient;
  fetchImpl?: FetchImpl;
  sleep?: (ms: number) => Promise<void>;
  maxPollAttempts?: number;
}): VisualEditPlanProvider => ({
  plan: async (input) => {
    if (input.video.data.length === 0) {
      throw new Error('Visual edit plan requires a non-empty video proxy');
    }
    if (!input.video.mimeType.toLowerCase().startsWith('video/')) {
      throw new Error('Visual edit plan requires a video MIME type');
    }

    let uploadedFile: GeminiFile | undefined;
    try {
      uploadedFile = readGeminiFile(
        await filesClient.upload({
          file: new Blob([Uint8Array.from(input.video.data)], {
            type: input.video.mimeType
          }),
          config: {
            displayName: 'postdee-visual-proxy',
            mimeType: input.video.mimeType
          }
        })
      );

      for (
        let attempt = 0;
        uploadedFile.state === 'PROCESSING' && attempt < maxPollAttempts;
        attempt += 1
      ) {
        await sleep(1000);
        uploadedFile = readGeminiFile(
          await filesClient.get({ name: uploadedFile.name })
        );
      }
      if (uploadedFile.state !== 'ACTIVE') {
        throw new Error(
          uploadedFile.state === 'FAILED'
            ? 'Visual edit Files API processing failed'
            : 'Visual edit Files API processing timed out'
        );
      }

      const generateUrl = new URL(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
          model
        )}:generateContent`
      );
      generateUrl.searchParams.set('key', apiKey);
      const generateResponse = await fetchImpl(generateUrl.toString(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: visualEditSystemPrompt }] },
          contents: [
            {
              role: 'user',
              parts: [
                {
                  fileData: {
                    mimeType: uploadedFile.mimeType,
                    fileUri: uploadedFile.uri
                  }
                },
                {
                  text: JSON.stringify({
                    durationSeconds: input.durationSeconds,
                    targetDurationSeconds: input.targetDurationSeconds,
                    transcriptSegments: input.segments
                  })
                }
              ]
            }
          ],
          generationConfig: {
            temperature: 0.2,
            responseMimeType: 'application/json'
          }
        })
      });
      if (!generateResponse.ok) {
        throw new Error(
          `Visual edit plan provider failed with status ${generateResponse.status ?? 'unknown'}`
        );
      }

      const content = readGeminiText(await generateResponse.json());
      if (!content) {
        throw new Error('Visual edit plan provider returned no content');
      }
      const parsed = parseLlmEditPlan(content, input.durationSeconds, model);
      return {
        ...parsed,
        cuts: buildCoherentHighlightCuts({
          suggestedCuts: parsed.cuts,
          segments: input.segments,
          durationSeconds: input.durationSeconds,
          targetDurationSeconds: input.targetDurationSeconds,
          // Gemini's selected window remains the strongest signal, but allow a
          // short nudge to the next transcript boundary for a complete opener.
          weakOpeningPenalty: 300
        }),
        model: `${model}-visual`
      };
    } finally {
      if (uploadedFile?.name) {
        try {
          await filesClient.delete({ name: uploadedFile.name });
        } catch {
          // Gemini files expire automatically; cleanup is best-effort.
        }
      }
    }
  }
});

export const createVisualEditPlanProviderFromConfig = ({
  config
}: {
  config: ServerConfig;
}): VisualEditPlanProvider | undefined => {
  if (!config.geminiApiKey) {
    return undefined;
  }
  return createGeminiVisualEditPlanProvider({
    apiKey: config.geminiApiKey,
    model: config.geminiCaptionModel
  });
};
