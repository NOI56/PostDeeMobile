import { Buffer } from 'node:buffer';

import type { ServerConfig } from '../../config/env.js';
import type { RealClipMediaPart } from '../captions/realClipCaptionProvider.js';
import {
  parseLlmEditPlan,
  trimToTarget,
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
  'speech sentences and chronological order. Return ONLY JSON: ' +
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

const fileResourceUrl = (fileName: string, apiKey: string) => {
  const url = new URL(
    `https://generativelanguage.googleapis.com/v1beta/${fileName}`
  );
  url.searchParams.set('key', apiKey);
  return url.toString();
};

export const createGeminiVisualEditPlanProvider = ({
  apiKey,
  model,
  fetchImpl = fetch as unknown as FetchImpl,
  sleep = (ms: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, ms)),
  maxPollAttempts = 30
}: {
  apiKey: string;
  model: string;
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

    const startUrl = new URL(
      'https://generativelanguage.googleapis.com/upload/v1beta/files'
    );
    startUrl.searchParams.set('key', apiKey);
    const startResponse = await fetchImpl(startUrl.toString(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': String(input.video.data.length),
        'X-Goog-Upload-Header-Content-Type': input.video.mimeType
      },
      body: JSON.stringify({ file: { displayName: 'postdee-visual-proxy' } })
    });
    if (!startResponse.ok) {
      throw new Error(
        `Visual edit Files API start failed with status ${startResponse.status ?? 'unknown'}`
      );
    }
    const uploadUrl = startResponse.headers.get('x-goog-upload-url');
    if (!uploadUrl) {
      throw new Error('Visual edit Files API did not return an upload URL');
    }

    let uploadedFile: GeminiFile | undefined;
    try {
      const uploadResponse = await fetchImpl(uploadUrl, {
        method: 'POST',
        headers: {
          'Content-Length': String(input.video.data.length),
          'X-Goog-Upload-Offset': '0',
          'X-Goog-Upload-Command': 'upload, finalize'
        },
        body: Buffer.from(input.video.data)
      });
      if (!uploadResponse.ok) {
        throw new Error(
          `Visual edit Files API upload failed with status ${uploadResponse.status ?? 'unknown'}`
        );
      }
      uploadedFile = readGeminiFile(await uploadResponse.json());

      for (
        let attempt = 0;
        uploadedFile.state === 'PROCESSING' && attempt < maxPollAttempts;
        attempt += 1
      ) {
        await sleep(1000);
        const fileResponse = await fetchImpl(
          fileResourceUrl(uploadedFile.name, apiKey),
          { method: 'GET' }
        );
        if (!fileResponse.ok) {
          throw new Error(
            `Visual edit Files API status failed with ${fileResponse.status ?? 'unknown'}`
          );
        }
        uploadedFile = readGeminiFile(await fileResponse.json());
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
        cuts: trimToTarget(
          parsed.cuts,
          input.durationSeconds,
          input.targetDurationSeconds
        ),
        model: `${model}-visual`
      };
    } finally {
      if (uploadedFile?.name) {
        try {
          await fetchImpl(fileResourceUrl(uploadedFile.name, apiKey), {
            method: 'DELETE'
          });
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
