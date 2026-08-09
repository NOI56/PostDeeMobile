import type { ServerConfig } from '../../config/env.js';
import type { EditPlanSegment } from './editPlanProvider.js';

export const maxAiSoundEffectsPerVideo = 8;

export const aiSoundEffectCatalog = [
  {
    id: 'soft_pop',
    category: 'accent',
    useWhen: 'light product reveal or a small on-screen emphasis'
  },
  {
    id: 'clean_tap',
    category: 'accent',
    useWhen: 'button, selection, tap, or concise call to action'
  },
  {
    id: 'short_whoosh',
    category: 'transition',
    useWhen: 'quick topic or shot transition'
  },
  {
    id: 'medium_whoosh',
    category: 'transition',
    useWhen: 'clearer or longer topic transition'
  },
  {
    id: 'sparkle',
    category: 'accent',
    useWhen: 'beauty, quality, shine, or premium benefit reveal'
  },
  {
    id: 'success_ding',
    category: 'success',
    useWhen: 'positive result, proof, completion, or strong confirmation'
  },
  {
    id: 'coin_ping',
    category: 'success',
    useWhen: 'price, saving, discount, value, or sales result'
  },
  {
    id: 'soft_impact',
    category: 'accent',
    useWhen: 'important claim, before-after reveal, or strong benefit'
  },
  {
    id: 'short_riser',
    category: 'transition',
    useWhen: 'build-up immediately before an important reveal'
  },
  {
    id: 'attention_boop',
    category: 'attention',
    useWhen: 'hook, warning, reminder, or viewer-attention cue'
  }
] as const;

export type AiSoundEffectId = (typeof aiSoundEffectCatalog)[number]['id'];

export type AiSoundEffectPlacement = {
  soundId: AiSoundEffectId;
  /** Absolute source-video timestamp. Mobile maps it onto the final timeline. */
  sourceSeconds: number;
};

export type SoundEffectPlanRequest = {
  durationSeconds: number;
  /** Strict, reliable transcript segments only. */
  segments: EditPlanSegment[];
};

export type SoundEffectPlanResult = {
  soundEffects: AiSoundEffectPlacement[];
  summary: string;
  model: string;
};

export type SoundEffectPlanProvider = {
  /** Undefined means the analysis was unavailable and must not be metered. */
  plan: (
    request: SoundEffectPlanRequest
  ) => Promise<SoundEffectPlanResult | undefined>;
};

export type SoundEffectTimingAnchor = {
  sourceSeconds: number;
  text: string;
  position: 'start' | 'end';
};

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (
  url: string,
  init?: RequestInit
) => Promise<FetchResponse>;

type GeminiGenerateContentResponse = {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
  }>;
};

type OpenAiChatCompletionResponse = {
  choices?: Array<{ message?: { content?: string } }>;
};

const aiSoundEffectIds = new Set<string>(
  aiSoundEffectCatalog.map((effect) => effect.id)
);

const roundToMilliseconds = (value: number): number =>
  Math.round(value * 1000) / 1000;

const hasOnlyKeys = (
  record: Record<string, unknown>,
  allowedKeys: readonly string[]
): boolean => {
  const allowed = new Set(allowedKeys);
  return Object.keys(record).every((key) => allowed.has(key));
};

/**
 * Builds the only timestamps an external model may select. Invalid or
 * out-of-range transcript ranges never become candidates.
 */
export const buildSoundEffectTimingAnchors = ({
  durationSeconds,
  segments
}: SoundEffectPlanRequest): SoundEffectTimingAnchor[] => {
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return [];
  }

  const anchors: SoundEffectTimingAnchor[] = [];
  const seen = new Set<string>();
  const addAnchor = ({
    seconds,
    text,
    position
  }: {
    seconds: number;
    text: string;
    position: SoundEffectTimingAnchor['position'];
  }) => {
    const sourceSeconds = roundToMilliseconds(seconds);
    if (
      !Number.isFinite(sourceSeconds) ||
      sourceSeconds < 0 ||
      sourceSeconds >= durationSeconds
    ) {
      return;
    }
    const key = `${sourceSeconds}:${position}:${text}`;
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    anchors.push({ sourceSeconds, text, position });
  };

  for (const segment of segments) {
    const text = segment.text.trim();
    if (
      text.length === 0 ||
      !Number.isFinite(segment.start) ||
      !Number.isFinite(segment.end) ||
      segment.start < 0 ||
      segment.end <= segment.start ||
      segment.end > durationSeconds
    ) {
      continue;
    }
    addAnchor({ seconds: segment.start, text, position: 'start' });
    addAnchor({ seconds: segment.end, text, position: 'end' });
  }

  return anchors.sort((left, right) =>
    left.sourceSeconds - right.sourceSeconds ||
    left.position.localeCompare(right.position) ||
    left.text.localeCompare(right.text)
  );
};

/**
 * Strictly validates the complete provider response. One invalid placement
 * rejects the whole result; values are never clamped, repaired, or partially
 * accepted.
 */
export const parseLlmSoundEffectPlan = (
  content: string,
  request: SoundEffectPlanRequest,
  model: string
): SoundEffectPlanResult => {
  const parsed = JSON.parse(content) as unknown;
  if (
    typeof parsed !== 'object' ||
    parsed === null ||
    Array.isArray(parsed)
  ) {
    throw new Error('Sound-effect provider returned a non-object result');
  }

  const record = parsed as Record<string, unknown>;
  if (
    !hasOnlyKeys(record, ['soundEffects', 'summary']) ||
    !Array.isArray(record.soundEffects) ||
    typeof record.summary !== 'string' ||
    record.summary.length > 500 ||
    record.soundEffects.length > maxAiSoundEffectsPerVideo
  ) {
    throw new Error('Sound-effect provider returned an invalid result shape');
  }

  const anchors = buildSoundEffectTimingAnchors(request);
  const allowedSourceSeconds = new Set(
    anchors.map((anchor) => anchor.sourceSeconds)
  );
  const soundEffects: AiSoundEffectPlacement[] = [];
  const seen = new Set<string>();

  for (const value of record.soundEffects) {
    if (
      typeof value !== 'object' ||
      value === null ||
      Array.isArray(value)
    ) {
      throw new Error('Sound-effect provider returned an invalid placement');
    }
    const placement = value as Record<string, unknown>;
    if (
      !hasOnlyKeys(placement, ['soundId', 'sourceSeconds']) ||
      typeof placement.soundId !== 'string' ||
      !aiSoundEffectIds.has(placement.soundId) ||
      typeof placement.sourceSeconds !== 'number' ||
      !Number.isFinite(placement.sourceSeconds)
    ) {
      throw new Error('Sound-effect provider returned an unsafe placement');
    }

    const sourceSeconds = roundToMilliseconds(placement.sourceSeconds);
    if (
      Math.abs(sourceSeconds - placement.sourceSeconds) > 0.000001 ||
      !allowedSourceSeconds.has(sourceSeconds)
    ) {
      throw new Error('Sound-effect provider selected an untrusted timestamp');
    }

    const key = String(sourceSeconds);
    if (seen.has(key)) {
      throw new Error('Sound-effect provider stacked effects at one timestamp');
    }
    seen.add(key);
    soundEffects.push({
      soundId: placement.soundId as AiSoundEffectId,
      sourceSeconds
    });
  }

  soundEffects.sort((left, right) =>
    left.sourceSeconds - right.sourceSeconds ||
    left.soundId.localeCompare(right.soundId)
  );
  return {
    soundEffects,
    summary: record.summary.trim(),
    model
  };
};

/** Re-validates an injected/internal provider before its result reaches a recipe. */
export const validateSoundEffectPlanResult = (
  value: unknown,
  request: SoundEffectPlanRequest
): SoundEffectPlanResult | undefined => {
  if (
    typeof value !== 'object' ||
    value === null ||
    Array.isArray(value)
  ) {
    return undefined;
  }
  const record = value as Record<string, unknown>;
  if (
    !hasOnlyKeys(record, ['soundEffects', 'summary', 'model']) ||
    typeof record.model !== 'string' ||
    record.model.trim().length === 0
  ) {
    return undefined;
  }
  try {
    return parseLlmSoundEffectPlan(
      JSON.stringify({
        soundEffects: record.soundEffects,
        summary: record.summary
      }),
      request,
      record.model.trim()
    );
  } catch {
    return undefined;
  }
};

export const soundEffectPlanSystemPrompt =
  'You are a restrained sound designer for short Thai seller videos. Choose ' +
  'zero or more sound effects only from the supplied PostDee catalog and only ' +
  'at exact sourceSeconds values present in the supplied transcript anchors. ' +
  'Use transcript meaning and anchor position to choose natural accents, ' +
  'transitions, success cues, or attention cues. Do not add a sound merely to ' +
  'fill space, do not stack effects at the same time, and never invent ' +
  'an asset, URL, path, timestamp, or volume. An empty soundEffects array is a ' +
  'valid answer when the clip should remain clean. Return ONLY one JSON object ' +
  'with this exact shape: ' +
  '{"soundEffects":[{"soundId":"<catalog id>","sourceSeconds":<exact anchor>}],' +
  '"summary":"<short Thai summary>"}. Use no more than 8 placements.';

const buildSoundEffectPlanUserPrompt = (
  request: SoundEffectPlanRequest
): string => JSON.stringify({
  durationSeconds: request.durationSeconds,
  catalog: aiSoundEffectCatalog,
  transcriptAnchors: buildSoundEffectTimingAnchors(request)
});

const readGeminiText = (payload: unknown): string | undefined => {
  const response = payload as GeminiGenerateContentResponse;
  const content = response.candidates?.[0]?.content?.parts
    ?.map((part) => part.text ?? '')
    .join('')
    .trim();
  return content && content.length > 0 ? content : undefined;
};

export const createGeminiSoundEffectPlanProvider = ({
  apiKey,
  model,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  fetchImpl?: FetchImpl;
}): SoundEffectPlanProvider => ({
  plan: async (request) => {
    if (buildSoundEffectTimingAnchors(request).length === 0) {
      return undefined;
    }
    try {
      const endpointUrl =
        `https://generativelanguage.googleapis.com/v1beta/models/` +
        `${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
      const response = await fetchImpl(endpointUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{ text: soundEffectPlanSystemPrompt }]
          },
          contents: [{
            role: 'user',
            parts: [{ text: buildSoundEffectPlanUserPrompt(request) }]
          }],
          generationConfig: { responseMimeType: 'application/json' }
        })
      });
      if (!response.ok) {
        return undefined;
      }
      const content = readGeminiText(await response.json());
      return content
        ? parseLlmSoundEffectPlan(content, request, model)
        : undefined;
    } catch {
      return undefined;
    }
  }
});

const createOpenAiCompatibleSoundEffectPlanProvider = ({
  apiKey,
  model,
  endpointUrl,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  endpointUrl: string;
  fetchImpl?: FetchImpl;
}): SoundEffectPlanProvider => ({
  plan: async (request) => {
    if (buildSoundEffectTimingAnchors(request).length === 0) {
      return undefined;
    }
    try {
      const response = await fetchImpl(endpointUrl, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model,
          response_format: { type: 'json_object' },
          temperature: 0.2,
          messages: [
            { role: 'system', content: soundEffectPlanSystemPrompt },
            { role: 'user', content: buildSoundEffectPlanUserPrompt(request) }
          ]
        })
      });
      if (!response.ok) {
        return undefined;
      }
      const payload = await response.json() as OpenAiChatCompletionResponse;
      const content = payload.choices?.[0]?.message?.content?.trim();
      return content
        ? parseLlmSoundEffectPlan(content, request, model)
        : undefined;
    } catch {
      return undefined;
    }
  }
});

export const createUnavailableSoundEffectPlanProvider =
  (): SoundEffectPlanProvider => ({
    plan: async () => undefined
  });

/** Uses the existing edit-planner provider choice; no new credential is added. */
export const createSoundEffectPlanProviderFromConfig = ({
  config,
  fetchImpl
}: {
  config: Pick<
    ServerConfig,
    | 'editPlanProvider'
    | 'openAiApiKey'
    | 'geminiApiKey'
    | 'openAiEditPlanModel'
    | 'geminiEditPlanModel'
  >;
  fetchImpl?: FetchImpl;
}): SoundEffectPlanProvider => {
  if (config.editPlanProvider === 'gemini' && config.geminiApiKey) {
    return createGeminiSoundEffectPlanProvider({
      apiKey: config.geminiApiKey,
      model: config.geminiEditPlanModel,
      fetchImpl
    });
  }
  if (config.editPlanProvider === 'openai' && config.openAiApiKey) {
    return createOpenAiCompatibleSoundEffectPlanProvider({
      apiKey: config.openAiApiKey,
      model: config.openAiEditPlanModel,
      endpointUrl: 'https://api.openai.com/v1/chat/completions',
      fetchImpl
    });
  }
  return createUnavailableSoundEffectPlanProvider();
};
