import type { ServerConfig } from '../../config/env.js';
import { isReliableTranscriptSegment } from './transcriptionProvider.js';

export type EditPlanSegment = {
  text: string;
  start: number;
  end: number;
  avgLogprob?: number;
  noSpeechProbability?: number;
  compressionRatio?: number;
};
export type EditPlanCut = { start: number; end: number };

export type EditPlanRequest = {
  segments: EditPlanSegment[];
  durationSeconds: number;
  targetDurationSeconds?: number;
  styleId?: string;
  prompt?: string;
};

export type EditPlanResult = {
  /** Absolute-second ranges to remove from the clip. */
  cuts: EditPlanCut[];
  /** Short human-readable explanation of what the plan did. */
  summary: string;
  /** Identifies the brain that produced the plan (mock vs a future LLM). */
  model: string;
};

export type EditPlanProvider = {
  plan: (request: EditPlanRequest) => Promise<EditPlanResult>;
};

type FetchResponse = {
  ok: boolean;
  status?: number;
  json: () => Promise<unknown>;
};

type FetchImpl = (url: string, init: RequestInit) => Promise<FetchResponse>;

type OpenAiChatCompletionResponse = {
  choices?: Array<{ message?: { content?: string } }>;
};

/** Per-style keyword keep config, mirroring the mobile edit styles. */
const styleKeepConfig: Record<
  string,
  { keepKeywords: string[]; keepFollowing: boolean }
> = {
  flash_sale: {
    keepKeywords: ['ราคา', 'ลด', 'บาท', 'โปร', 'ส่วนลด', 'ฟรี', 'ถูก', 'คุ้ม', 'แถม', 'ส่งฟรี'],
    keepFollowing: false
  },
  before_after: {
    keepKeywords: ['ก่อน', 'หลัง', 'เคย', 'เดิม', 'ตอนนี้', 'เปลี่ยน', 'ผลลัพธ์'],
    keepFollowing: false
  },
  tutorial: {
    keepKeywords: ['ขั้นตอน', 'ก่อน', 'จากนั้น', 'ต่อไป', 'เสร็จ', 'วิธี'],
    keepFollowing: false
  },
  qa: {
    keepKeywords: ['ไหม', 'มั้ย', 'อะไร', 'ยังไง', 'ทำไม', 'เท่าไหร่', 'กี่', 'หรือเปล่า'],
    keepFollowing: true
  },
  comedy: {
    keepKeywords: ['5555', '555', 'ฮ่า', 'ฮา', 'ขำ'],
    keepFollowing: false
  }
};

const profanityWords = [
  'เหี้ย',
  'สัส',
  'สัด',
  'ควย',
  'เย็ด',
  'แม่ง',
  'ระยำ',
  'ชิบหาย',
  'ฉิบหาย',
  'มึง',
  'กู',
  'เชี่ย',
  'หี',
  'อีดอก',
  'สถุล',
  'ตอแหล',
  'ไอ้สัตว์'
];

export const matchesAnyKeyword = (text: string, keywords: string[]): boolean => {
  const haystack = text.toLowerCase();
  return keywords.some((keyword) => {
    const needle = keyword.trim().toLowerCase();
    return needle.length > 0 && haystack.includes(needle);
  });
};

const highlightSignals: Array<{ keywords: string[]; weight: number }> = [
  {
    keywords: ['หยุด', 'รู้ไหม', 'ต้องดู', 'ปัญหา', 'ใครที่', 'ห้ามพลาด'],
    weight: 5
  },
  {
    keywords: [
      'ช่วย',
      'ดี',
      'คุ้ม',
      'ง่าย',
      'สะดวก',
      'ประหยัด',
      'เร็ว',
      'แก้',
      'ลดเวลา'
    ],
    weight: 4
  },
  {
    keywords: ['ผลลัพธ์', 'ก่อน', 'หลัง', 'รีวิว', 'ขายดี', 'จริง', 'ลองแล้ว'],
    weight: 5
  },
  {
    keywords: ['ราคา', 'บาท', 'ลด', 'โปร', 'ส่วนลด', 'ส่งฟรี', 'ฟรี', 'แถม'],
    weight: 6
  },
  {
    keywords: ['กด', 'สั่ง', 'ซื้อ', 'ตะกร้า', 'ลิงก์', 'ทัก', 'วันนี้'],
    weight: 6
  }
];

/** Keeps uncertain speech and provider prompt leakage out of highlight scoring. */
export const isReliableHighlightSegment = (
  segment: EditPlanSegment
): boolean => isReliableTranscriptSegment(segment);

const scoreHighlightSegment = (
  segment: EditPlanSegment,
  index: number,
  segmentCount: number
): number => {
  const text = segment.text.toLowerCase();
  const signalScore = highlightSignals.reduce(
    (total, signal) =>
      total +
      signal.keywords.filter((keyword) => text.includes(keyword)).length *
        signal.weight,
    0
  );
  const positionScore = index === 0 ? 1 : index === segmentCount - 1 ? 2 : 0;
  return signalScore + positionScore;
};

const normalizeCuts = (
  cuts: EditPlanCut[],
  durationSeconds: number
): EditPlanCut[] => {
  const normalized: EditPlanCut[] = [];

  for (const cut of [...cuts].sort((a, b) => a.start - b.start)) {
    const start = Math.min(Math.max(cut.start, 0), durationSeconds);
    const end = Math.min(Math.max(cut.end, 0), durationSeconds);
    if (end <= start) continue;

    const previous = normalized[normalized.length - 1];
    if (previous && start <= previous.end + 0.001) {
      previous.end = Math.max(previous.end, end);
    } else {
      normalized.push({ start, end });
    }
  }

  return normalized;
};

const cutsOutsideKeptRanges = (
  keptRanges: EditPlanCut[],
  durationSeconds: number
): EditPlanCut[] => {
  const kept = normalizeCuts(keptRanges, durationSeconds);
  const cuts: EditPlanCut[] = [];
  let cursor = 0;

  for (const range of kept) {
    if (range.start > cursor + 0.001) {
      cuts.push({ start: cursor, end: range.start });
    }
    cursor = Math.max(cursor, range.end);
  }
  if (cursor < durationSeconds - 0.001) {
    cuts.push({ start: cursor, end: durationSeconds });
  }
  return cuts;
};

const overlapSeconds = (
  start: number,
  end: number,
  range: EditPlanCut
): number => Math.max(0, Math.min(end, range.end) - Math.max(start, range.start));

const candidateWindowStarts = (
  ranges: EditPlanCut[],
  segments: EditPlanSegment[],
  durationSeconds: number,
  targetDurationSeconds: number
): number[] => {
  const latestStart = Math.max(0, durationSeconds - targetDurationSeconds);
  const starts = new Set<number>([0, latestStart]);
  const add = (value: number) => {
    starts.add(Math.min(Math.max(value, 0), latestStart));
  };

  for (const range of ranges) {
    add(range.start);
    add(range.end - targetDurationSeconds);
  }
  for (const segment of segments) {
    add(segment.start);
    add(segment.end - targetDurationSeconds);
  }

  return [...starts].sort((a, b) => a - b);
};

/**
 * Converts scattered suggestions into the best single story window. This makes
 * the result predictable for talking-head clips and prevents jump-cut montages.
 */
const buildCoherentHighlightCuts = ({
  suggestedCuts,
  segments,
  durationSeconds,
  targetDurationSeconds
}: {
  suggestedCuts: EditPlanCut[];
  segments: EditPlanSegment[];
  durationSeconds: number;
  targetDurationSeconds: number;
}): EditPlanCut[] => {
  if (
    durationSeconds <= 0 ||
    targetDurationSeconds <= 0 ||
    targetDurationSeconds >= durationSeconds
  ) {
    return [];
  }

  const suggestedKeeps = complement(suggestedCuts, durationSeconds);
  const reliableSegments = segments.filter(isReliableHighlightSegment);
  const unreliableSegments = segments.filter(
    (segment) => !isReliableHighlightSegment(segment)
  );
  const starts = candidateWindowStarts(
    suggestedKeeps,
    reliableSegments,
    durationSeconds,
    targetDurationSeconds
  );

  let bestStart = starts[0] ?? 0;
  let bestScore = Number.NEGATIVE_INFINITY;
  for (const start of starts) {
    const end = start + targetDurationSeconds;
    const suggestedCoverage = suggestedKeeps.reduce(
      (total, range) => total + overlapSeconds(start, end, range),
      0
    );
    const reliableCoverage = reliableSegments.reduce(
      (total, segment) =>
        total + overlapSeconds(start, end, { start: segment.start, end: segment.end }),
      0
    );
    const unreliableCoverage = unreliableSegments.reduce(
      (total, segment) =>
        total + overlapSeconds(start, end, { start: segment.start, end: segment.end }),
      0
    );
    const signalScore = reliableSegments.reduce((total, segment, index) => {
      const overlap = overlapSeconds(start, end, {
        start: segment.start,
        end: segment.end
      });
      return (
        total +
        overlap * scoreHighlightSegment(segment, index, reliableSegments.length)
      );
    }, 0);
    const score =
      suggestedCoverage * 100 +
      reliableCoverage * 5 +
      signalScore -
      unreliableCoverage * 100;

    if (score > bestScore + 0.001) {
      bestScore = score;
      bestStart = start;
    }
  }

  return cutsOutsideKeptRanges(
    [{ start: bestStart, end: bestStart + targetDurationSeconds }],
    durationSeconds
  );
};

/** Selects strong Thai selling moments while preserving their timeline order. */
export const buildHighlightCuts = (
  segments: EditPlanSegment[],
  durationSeconds: number,
  targetDurationSeconds: number
): EditPlanCut[] => {
  if (
    durationSeconds <= 0 ||
    targetDurationSeconds <= 0 ||
    targetDurationSeconds >= durationSeconds
  ) {
    return [];
  }

  const validSegments = segments
    .map((segment, index) => ({
      ...segment,
      index,
      start: Math.min(Math.max(segment.start, 0), durationSeconds),
      end: Math.min(Math.max(segment.end, 0), durationSeconds)
    }))
    .filter(
      (segment) =>
        segment.end > segment.start && isReliableHighlightSegment(segment)
    );

  if (validSegments.length === 0) {
    return trimToTarget([], durationSeconds, targetDurationSeconds);
  }

  return buildCoherentHighlightCuts({
    suggestedCuts: [],
    segments: validSegments,
    durationSeconds,
    targetDurationSeconds
  });
};

/** Gaps in [0, duration] not covered by cuts, merged and sorted. Pure. */
const complement = (cuts: EditPlanCut[], duration: number): EditPlanCut[] => {
  if (cuts.length === 0) {
    return [{ start: 0, end: duration }];
  }

  const sorted = normalizeCuts(cuts, duration);
  const result: EditPlanCut[] = [];
  let cursor = 0;

  for (const cut of sorted) {
    const start = Math.min(Math.max(cut.start, 0), duration);
    const end = Math.min(Math.max(cut.end, 0), duration);
    if (start > cursor) {
      result.push({ start: cursor, end: start });
    }
    if (end > cursor) {
      cursor = end;
    }
  }

  if (cursor < duration) {
    result.push({ start: cursor, end: duration });
  }

  return result;
};

/** Keep only segments matching keywords (plus the next one), cut the rest. */
export const buildKeywordKeepCuts = (
  segments: EditPlanSegment[],
  durationSeconds: number,
  keepKeywords: string[],
  keepFollowing: boolean
): EditPlanCut[] => {
  if (keepKeywords.length === 0 || segments.length === 0 || durationSeconds <= 0) {
    return [];
  }

  const keep = new Set<number>();
  segments.forEach((segment, index) => {
    if (matchesAnyKeyword(segment.text, keepKeywords)) {
      keep.add(index);
      if (keepFollowing && index + 1 < segments.length) {
        keep.add(index + 1);
      }
    }
  });

  if (keep.size === 0) {
    return [];
  }

  const merged: Array<[number, number]> = [];
  for (const index of [...keep].sort((a, b) => a - b)) {
    const { start, end } = segments[index]!;
    const last = merged[merged.length - 1];
    if (last && start <= last[1] + 0.001) {
      last[1] = Math.max(last[1], end);
    } else {
      merged.push([start, end]);
    }
  }

  const cuts: EditPlanCut[] = [];
  let cursor = 0;
  for (const [start, end] of merged) {
    const keptStart = Math.min(Math.max(start, 0), durationSeconds);
    if (keptStart > cursor + 0.05) {
      cuts.push({ start: cursor, end: keptStart });
    }
    cursor = Math.min(Math.max(end, 0), durationSeconds);
  }
  if (durationSeconds > cursor + 0.05) {
    cuts.push({ start: cursor, end: durationSeconds });
  }

  return cuts;
};

/** Adds a tail cut so the kept (non-cut) length fits targetSeconds. */
export const trimToTarget = (
  cuts: EditPlanCut[],
  durationSeconds: number,
  targetSeconds: number
): EditPlanCut[] => {
  if (targetSeconds <= 0 || durationSeconds <= 0) {
    return cuts;
  }

  const normalizedCuts = normalizeCuts(cuts, durationSeconds);
  const kept = complement(normalizedCuts, durationSeconds);
  let accumulated = 0;
  let keepUntil: number | undefined;

  for (const interval of kept) {
    const length = interval.end - interval.start;
    if (accumulated + length >= targetSeconds) {
      keepUntil = interval.start + (targetSeconds - accumulated);
      break;
    }
    accumulated += length;
  }

  if (keepUntil !== undefined && keepUntil < durationSeconds) {
    return normalizeCuts(
      [...normalizedCuts, { start: keepUntil, end: durationSeconds }],
      durationSeconds
    );
  }

  return normalizedCuts;
};

export const parsePromptInstruction = (
  prompt: string
): { targetSeconds?: number; removeProfanity: boolean } => {
  const text = prompt.toLowerCase();

  let targetSeconds: number | undefined;
  const match = text.match(/(\d+(?:[.,]\d+)?)\s*(วินาที|วิ|นาที|min|sec)/);
  if (match) {
    const value = Number.parseFloat(match[1]!.replace(',', '.'));
    if (Number.isFinite(value) && value > 0) {
      const isMinutes = match[2] === 'นาที' || match[2] === 'min';
      targetSeconds = isMinutes ? value * 60 : value;
    }
  }

  const removeProfanity =
    text.includes('หยาบ') ||
    text.includes('ไม่สุภาพ') ||
    text.includes('เซ็นเซอร์') ||
    text.includes('censor');

  return { targetSeconds, removeProfanity };
};

/**
 * Rule-based stand-in for a future LLM edit planner. It understands the same
 * primitives the mobile app does (keyword keep per style, comedy laughter
 * markers, prompt target length + profanity removal) so the API contract is
 * exercised today and an LLM can replace the brain without touching callers.
 */
export const createMockEditPlanProvider = (): EditPlanProvider => ({
  plan: async ({
    segments,
    durationSeconds,
    targetDurationSeconds,
    styleId,
    prompt
  }) => {
    if (
      targetDurationSeconds !== undefined &&
      !styleId &&
      (!prompt || prompt.trim().length === 0)
    ) {
      return {
        cuts: buildHighlightCuts(
          segments,
          durationSeconds,
          targetDurationSeconds
        ),
        summary: `เลือกช่วงขายที่ดีที่สุดให้เหลือประมาณ ${Math.round(targetDurationSeconds)} วิ`,
        model: 'mock-highlight-rule'
      };
    }

    if (prompt && prompt.trim().length > 0) {
      const instruction = parsePromptInstruction(prompt);
      let cuts: EditPlanCut[] = [];

      if (instruction.removeProfanity) {
        cuts = segments
          .filter((segment) => matchesAnyKeyword(segment.text, profanityWords))
          .map((segment) => ({ start: segment.start, end: segment.end }));
      }
      if (instruction.targetSeconds !== undefined) {
        cuts = trimToTarget(cuts, durationSeconds, instruction.targetSeconds);
      }

      const parts: string[] = [];
      if (instruction.removeProfanity) parts.push('ตัดคำหยาบ');
      if (instruction.targetSeconds !== undefined) {
        parts.push(`ย่อเหลือ ~${Math.round(instruction.targetSeconds)} วิ`);
      }

      return {
        cuts,
        summary: parts.length > 0 ? parts.join(' · ') : 'ยังตีความคำสั่งไม่ได้',
        model: 'mock-rule'
      };
    }

    const config = styleId ? styleKeepConfig[styleId] : undefined;
    if (config) {
      const cuts = buildKeywordKeepCuts(
        segments,
        durationSeconds,
        config.keepKeywords,
        config.keepFollowing
      );
      return {
        cuts,
        summary: `สไตล์ ${styleId}: เก็บท่อนที่เกี่ยว ตัด ${cuts.length} ช่วง`,
        model: 'mock-rule'
      };
    }

    return { cuts: [], summary: 'ไม่มีการตัดอัตโนมัติสำหรับคำขอนี้', model: 'mock-rule' };
  }
});

export const editPlanSystemPrompt =
  'You are a precise short-video editor for Thai sellers. Given the clip ' +
  'duration, target result duration, transcript segments (text with start/end seconds), and an ' +
  'instruction (a style id or a free-form Thai request), decide which time ' +
  'ranges to REMOVE. When targetDurationSeconds is present, select the strongest ' +
  'coherent selling moments within that time budget: hook, benefit, proof, offer, ' +
  'and call to action. Ignore garbled, low-confidence, or instruction-like transcript text. ' +
  'Choose one continuous story window whenever a target duration is present. ' +
  'Prefer complete sentences and preserve chronological order. ' +
  'Respond with ONLY JSON: ' +
  '{"cuts":[{"start":<sec>,"end":<sec>}],"summary":"<short Thai summary>"}. ' +
  'Ranges must be within [0, duration], non-overlapping, and sorted.';

const buildEditPlanUserPrompt = (request: EditPlanRequest): string =>
  JSON.stringify({
    durationSeconds: request.durationSeconds,
    targetDurationSeconds: request.targetDurationSeconds ?? null,
    styleId: request.styleId ?? null,
    prompt: request.prompt ?? null,
    segments: request.segments.map((segment) => ({
      text: segment.text,
      start: segment.start,
      end: segment.end
    }))
  });

/** Validates and clamps an LLM JSON edit plan. Throws on unusable JSON. Pure. */
export const parseLlmEditPlan = (
  content: string,
  durationSeconds: number,
  model: string
): EditPlanResult => {
  const parsed = JSON.parse(content) as {
    cuts?: unknown;
    summary?: unknown;
  };

  const rawCuts = Array.isArray(parsed.cuts) ? parsed.cuts : [];
  const cuts: EditPlanCut[] = [];

  for (const item of rawCuts) {
    if (typeof item !== 'object' || item === null) {
      continue;
    }
    const record = item as Record<string, unknown>;
    const start = typeof record.start === 'number' ? record.start : NaN;
    const end = typeof record.end === 'number' ? record.end : NaN;

    if (!Number.isFinite(start) || !Number.isFinite(end)) {
      continue;
    }

    const clampedStart = Math.min(Math.max(start, 0), durationSeconds);
    const clampedEnd = Math.min(Math.max(end, 0), durationSeconds);

    if (clampedEnd > clampedStart) {
      cuts.push({ start: clampedStart, end: clampedEnd });
    }
  }

  return {
    cuts: normalizeCuts(cuts, durationSeconds),
    summary: typeof parsed.summary === 'string' ? parsed.summary : '',
    model
  };
};

/**
 * Edit planner backed by an OpenAI-compatible chat API (OpenAI or Groq). Any
 * network/parse failure transparently falls back to [fallback] (the rule-based
 * mock) so the endpoint stays resilient.
 */
export const createOpenAiCompatibleEditPlanProvider = ({
  apiKey,
  model,
  endpointUrl,
  failureLabel,
  fallback,
  fetchImpl = fetch as unknown as FetchImpl
}: {
  apiKey: string;
  model: string;
  endpointUrl: string;
  failureLabel: string;
  fallback: EditPlanProvider;
  fetchImpl?: FetchImpl;
}): EditPlanProvider => ({
  plan: async (request) => {
    try {
      const planningRequest =
        request.targetDurationSeconds !== undefined
          ? {
              ...request,
              segments: request.segments.filter(isReliableHighlightSegment)
            }
          : request;
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
            { role: 'system', content: editPlanSystemPrompt },
            { role: 'user', content: buildEditPlanUserPrompt(planningRequest) }
          ]
        })
      });

      if (!response.ok) {
        throw new Error(
          `${failureLabel} failed with status ${response.status ?? 'unknown'}`
        );
      }

      const payload = (await response.json()) as OpenAiChatCompletionResponse;
      const content = payload.choices?.[0]?.message?.content;

      if (!content) {
        throw new Error(`${failureLabel} returned no content`);
      }

      const result = parseLlmEditPlan(content, request.durationSeconds, model);
      return request.targetDurationSeconds !== undefined &&
        !request.styleId &&
        (!request.prompt || request.prompt.trim().length === 0)
        ? {
            ...result,
            cuts: buildCoherentHighlightCuts({
              suggestedCuts: result.cuts,
              segments: request.segments,
              durationSeconds: request.durationSeconds,
              targetDurationSeconds: request.targetDurationSeconds
            })
          }
        : request.targetDurationSeconds !== undefined
          ? {
              ...result,
              cuts: trimToTarget(
                result.cuts,
                request.durationSeconds,
                request.targetDurationSeconds
              )
            }
          : result;
    } catch {
      return fallback.plan(request);
    }
  }
});

export const createEditPlanProviderFromConfig = ({
  config,
  fetchImpl
}: {
  config: Pick<
    ServerConfig,
    | 'editPlanProvider'
    | 'openAiApiKey'
    | 'groqApiKey'
    | 'openAiEditPlanModel'
    | 'groqEditPlanModel'
  >;
  fetchImpl?: FetchImpl;
}): EditPlanProvider => {
  const fallback = createMockEditPlanProvider();

  if (config.editPlanProvider === 'openai') {
    if (!config.openAiApiKey) {
      throw new Error('OPENAI_API_KEY is required when EDIT_PLAN_PROVIDER is openai');
    }

    return createOpenAiCompatibleEditPlanProvider({
      apiKey: config.openAiApiKey,
      model: config.openAiEditPlanModel,
      endpointUrl: 'https://api.openai.com/v1/chat/completions',
      failureLabel: 'OpenAI edit plan',
      fallback,
      fetchImpl
    });
  }

  if (config.editPlanProvider === 'groq') {
    if (!config.groqApiKey) {
      throw new Error('GROQ_API_KEY is required when EDIT_PLAN_PROVIDER is groq');
    }

    return createOpenAiCompatibleEditPlanProvider({
      apiKey: config.groqApiKey,
      model: config.groqEditPlanModel,
      endpointUrl: 'https://api.groq.com/openai/v1/chat/completions',
      failureLabel: 'Groq edit plan',
      fallback,
      fetchImpl
    });
  }

  return fallback;
};
