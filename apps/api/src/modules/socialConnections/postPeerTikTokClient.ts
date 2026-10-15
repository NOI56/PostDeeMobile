import { isTikTokPrivacyLevel, type TikTokPrivacyLevel } from '../posts/platformSettings.js';

export type { TikTokPrivacyLevel } from '../posts/platformSettings.js';
export type TikTokCreatorInfo = {
  creatorAvatarUrl: string;
  creatorUsername: string;
  creatorNickname: string;
  privacyLevelOptions: readonly TikTokPrivacyLevel[];
  commentDisabled: boolean;
  duetDisabled: boolean;
  stitchDisabled: boolean;
  maxVideoPostDurationSec: number;
};

export class TikTokPublishingError extends Error {
  constructor(readonly code: string, readonly statusCode: number, message: string) {
    super(message);
    this.name = 'TikTokPublishingError';
  }
}

export type PostPeerTikTokClient = {
  getCreatorInfo: (input: { accountId: string }) => Promise<TikTokCreatorInfo>;
};
type FetchImpl = (url: string, init: RequestInit) => Promise<{
  ok: boolean;
  body?: ReadableStream<Uint8Array> | null;
  text?: () => Promise<string>;
}>;
const maxPayloadBytes = 32_768;
const unavailable = () => new TikTokPublishingError(
  'TIKTOK_CREATOR_INFO_UNAVAILABLE', 503,
  'TikTok publishing options could not be checked. Please try again.'
);
const invalid = () => new TikTokPublishingError(
  'TIKTOK_CREATOR_INFO_INVALID', 502,
  'TikTok publishing options could not be verified. Please try again.'
);
const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
const text = (value: unknown, maxLength: number) =>
  typeof value === 'string' && value.trim() && value.length <= maxLength
    ? value.trim() : undefined;

const parseCreatorInfo = (payload: unknown): TikTokCreatorInfo => {
  const envelope = record(payload);
  const data = record(envelope.data);
  const creatorAvatarUrl = text(data.creatorAvatarUrl, 2048);
  const creatorUsername = text(data.creatorUsername, 256);
  const creatorNickname = text(data.creatorNickname, 256);
  let avatar: URL;
  try { avatar = new URL(creatorAvatarUrl ?? ''); } catch { throw invalid(); }
  const options = data.privacyLevelOptions;
  const duration = data.maxVideoPostDurationSec;
  if (
    envelope.success !== true || !creatorAvatarUrl || !creatorUsername || !creatorNickname ||
    avatar.protocol !== 'https:' || avatar.username || avatar.password ||
    !Array.isArray(options) || options.length < 1 || options.length > 4 ||
    !options.every(isTikTokPrivacyLevel) || new Set(options).size !== options.length ||
    typeof data.commentDisabled !== 'boolean' || typeof data.duetDisabled !== 'boolean' ||
    typeof data.stitchDisabled !== 'boolean' ||
    typeof duration !== 'number' || !Number.isSafeInteger(duration) || duration <= 0
  ) throw invalid();
  return {
    creatorAvatarUrl, creatorUsername, creatorNickname, privacyLevelOptions: options,
    commentDisabled: data.commentDisabled, duetDisabled: data.duetDisabled,
    stitchDisabled: data.stitchDisabled, maxVideoPostDurationSec: duration
  };
};

export const createPostPeerTikTokClient = ({
  apiKey, baseUrl, fetchImpl = fetch as FetchImpl, timeoutMs = 5000
}: {
  apiKey?: string;
  baseUrl: string;
  fetchImpl?: FetchImpl;
  timeoutMs?: number;
}): PostPeerTikTokClient => ({
  getCreatorInfo: async ({ accountId }) => {
    if (!apiKey) throw new TikTokPublishingError(
      'TIKTOK_PUBLISHING_UNAVAILABLE', 503, 'TikTok publishing options are not available.'
    );
    if (!accountId.trim()) throw invalid();
    const controller = new AbortController();
    let timeout: ReturnType<typeof setTimeout> | undefined;
    const operation = async () => {
      const response = await fetchImpl(
        `${baseUrl.replace(/\/+$/, '')}/v1/tiktok/creator-info?accountId=${encodeURIComponent(accountId)}`,
        { method: 'GET', headers: { 'x-access-key': apiKey }, redirect: 'error', signal: controller.signal }
      );
      if (!response.ok) throw unavailable();
      let raw: string;
      if (response.body) {
        const reader = response.body.getReader();
        const chunks: Uint8Array[] = [];
        let length = 0;
        try {
          while (true) {
            const next = await reader.read();
            if (next.done) break;
            length += next.value.byteLength;
            if (length > maxPayloadBytes) {
              controller.abort();
              void reader.cancel().catch(() => undefined);
              throw invalid();
            }
            chunks.push(next.value);
          }
        } finally { reader.releaseLock(); }
        const bytes = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
        raw = new TextDecoder().decode(bytes);
      } else {
        raw = response.text ? await response.text() : '';
        if (Buffer.byteLength(raw) > maxPayloadBytes) throw invalid();
      }
      let payload: unknown;
      try { payload = JSON.parse(raw); } catch { throw invalid(); }
      return parseCreatorInfo(payload);
    };
    try {
      return await Promise.race([
        operation(),
        new Promise<never>((_resolve, reject) => {
          timeout = setTimeout(() => { controller.abort(); reject(unavailable()); }, Math.max(1, Math.min(timeoutMs, 10_000)));
        })
      ]);
    } catch (error) {
      if (error instanceof TikTokPublishingError) throw error;
      throw unavailable();
    } finally { if (timeout) clearTimeout(timeout); }
  }
});
