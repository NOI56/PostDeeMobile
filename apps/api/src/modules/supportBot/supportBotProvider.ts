import type { SupportBotProviderKind } from '../../config/env.js';
import {
  supportBotChatMessages, supportBotSystemPrompt, type SupportBotContext, type SupportBotTurn
} from './supportBotKnowledge.js';

export type SupportBotAnswer = { reply: string; handoff: boolean };
export type SupportBotProvider = {
  kind: Exclude<SupportBotProviderKind, 'off'>;
  answer: (input: { conversation: SupportBotTurn[]; context: SupportBotContext }) => Promise<SupportBotAnswer>;
};
type FetchImpl = typeof fetch;

const isAnswer = (value: unknown): value is SupportBotAnswer => typeof value === 'object' && value !== null &&
  typeof (value as SupportBotAnswer).reply === 'string' && typeof (value as SupportBotAnswer).handoff === 'boolean';

/**
 * Dot backed by OpenAI chat completions. It has no tools: the model only
 * writes text from the facts and member data in the prompt. Any network,
 * status or format problem throws, and the caller hands off to the team.
 */
export const createOpenAiSupportBotProvider = ({ apiKey, model, fetchImpl = fetch, timeoutMs = 20_000 }: {
  apiKey: string; model: string; fetchImpl?: FetchImpl; timeoutMs?: number;
}): SupportBotProvider => ({
  kind: 'openai',
  answer: async ({ conversation, context }) => {
    const response = await fetchImpl('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: supportBotSystemPrompt(context) }, ...supportBotChatMessages(conversation)],
        response_format: { type: 'json_object' },
        temperature: 0.2,
        max_tokens: 500
      }),
      signal: AbortSignal.timeout(timeoutMs)
    });
    if (!response.ok) throw new Error(`OpenAI support bot request failed with ${response.status}`);
    const payload = await response.json() as { choices?: { message?: { content?: string } }[] };
    const content = payload.choices?.[0]?.message?.content;
    const answer: unknown = content ? JSON.parse(content) : undefined;
    if (!isAnswer(answer)) throw new Error('OpenAI support bot response was not a reply');
    return answer;
  }
});

// Local and test helper only (refused in production): answers from open
// service notices, then automatic signals, and hands everything else to the team.
export const createMockSupportBotProvider = (): SupportBotProvider => ({
  kind: 'mock',
  answer: async ({ context }) => context.incidents.length
    ? { reply: `ตอนนี้ทีมงานทราบปัญหานี้แล้วค่ะ: ${context.incidents.map(i => i.title).join(', ')}\n${context.incidents[0].message}`,
      handoff: false }
    : context.automaticSignals.length
      ? { reply: `ช่วงนี้ระบบตรวจพบข้อผิดพลาดใน${context.automaticSignals.map(s => s.area).join(', ')}ค่ะ `
        + 'ลองรอสักครู่ และตรวจโพสต์บนช่องทางก่อนส่งซ้ำนะคะ', handoff: false }
      : { reply: 'ขอส่งเรื่องนี้ให้ทีมงาน PostDee ช่วยดูนะคะ ทีมงานจะตอบในแชทนี้โดยเร็วที่สุดค่ะ', handoff: true }
});
