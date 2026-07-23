import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
import type { RealClipMediaPart } from '../captions/realClipCaptionProvider.js';
import { MediaDownloadError } from '../storage/mediaDownload.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import {
  aiEditMonthlyMinuteLimit,
  readCurrentAiEditMonthKey,
  type AiEditUsageStore
} from './aiEditUsageStore.js';
import {
  buildAiEditRecipe,
  readAiEditCapabilities,
  readAiEditRecipeSettings
} from './aiEditRecipe.js';
import type {
  EditPlanProvider,
  EditPlanSegment
} from './editPlanProvider.js';
import type {
  TranscriptionProvider,
  TranscriptionResult
} from './transcriptionProvider.js';
import type { VisualEditPlanProvider } from './visualEditPlanProvider.js';

const readRequiredString = (value: unknown) => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

const readPositiveNumber = (value: unknown) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return undefined;
  }

  return value;
};

const readVisualProxyKey = (value: unknown) => {
  if (value === undefined) {
    return { ok: true as const, key: undefined };
  }

  const key = readRequiredString(value);
  if (!key || !key.toLowerCase().endsWith('.mp4')) {
    return {
      ok: false as const,
      message: 'visualProxyS3Key must identify an MP4 file'
    };
  }

  return { ok: true as const, key };
};

type AiEditMediaPart = {
  key: string;
  kind: 'audio' | 'legacy-video';
  startSeconds: number;
};

type AiEditMedia = {
  parts: AiEditMediaPart[];
  deleteAfterUse: boolean;
};

type ReadAiEditMediaResult =
  | { ok: true; media: AiEditMedia }
  | { ok: false; code: string; message: string };

const readAiEditMedia = (body: unknown): ReadAiEditMediaResult => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const audioS3Key = readRequiredString(payload.audioS3Key);
  const rawAudioChunks = payload.audioChunks;
  const videoS3Key = readRequiredString(payload.videoS3Key);
  const hasAudioChunks = Array.isArray(rawAudioChunks) && rawAudioChunks.length > 0;
  const mediaSourceCount =
    (audioS3Key ? 1 : 0) + (hasAudioChunks ? 1 : 0) + (videoS3Key ? 1 : 0);

  if (mediaSourceCount > 1) {
    return {
      ok: false,
      code: 'AI_EDIT_MEDIA_AMBIGUOUS',
      message: 'Provide exactly one of audioS3Key, audioChunks, or videoS3Key'
    };
  }

  if (rawAudioChunks !== undefined && !hasAudioChunks) {
    return {
      ok: false,
      code: 'AI_EDIT_AUDIO_CHUNKS_INVALID',
      message: 'audioChunks must contain at least one ordered M4A chunk'
    };
  }

  if (mediaSourceCount === 0) {
    return {
      ok: false,
      code: 'AI_EDIT_MEDIA_REQUIRED',
      message: 'audioS3Key, audioChunks, or videoS3Key is required'
    };
  }

  if (audioS3Key) {
    if (!audioS3Key.toLowerCase().endsWith('.m4a')) {
      return {
        ok: false,
        code: 'AI_EDIT_AUDIO_KEY_INVALID',
        message: 'audioS3Key must identify an M4A file'
      };
    }

    return {
      ok: true,
      media: {
        parts: [{ key: audioS3Key, kind: 'audio', startSeconds: 0 }],
        deleteAfterUse: true
      }
    };
  }

  if (hasAudioChunks) {
    if (rawAudioChunks.length > 40) {
      return {
        ok: false,
        code: 'AI_EDIT_AUDIO_CHUNKS_INVALID',
        message: 'audioChunks exceeds the supported limit'
      };
    }

    const chunks: AiEditMediaPart[] = [];
    let previousStart = -1;
    const keys = new Set<string>();
    for (const item of rawAudioChunks) {
      if (typeof item !== 'object' || item === null) {
        return {
          ok: false,
          code: 'AI_EDIT_AUDIO_CHUNKS_INVALID',
          message: 'Each audio chunk must include an M4A key and startSeconds'
        };
      }

      const record = item as Record<string, unknown>;
      const key = readRequiredString(record.audioS3Key);
      const startSeconds = record.startSeconds;
      if (
        !key ||
        !key.toLowerCase().endsWith('.m4a') ||
        typeof startSeconds !== 'number' ||
        !Number.isFinite(startSeconds) ||
        startSeconds < 0 ||
        startSeconds <= previousStart ||
        keys.has(key)
      ) {
        return {
          ok: false,
          code: 'AI_EDIT_AUDIO_CHUNKS_INVALID',
          message: 'audioChunks must be unique, ordered M4A chunks'
        };
      }

      chunks.push({ key, kind: 'audio', startSeconds });
      keys.add(key);
      previousStart = startSeconds;
    }

    if (chunks[0]?.startSeconds !== 0) {
      return {
        ok: false,
        code: 'AI_EDIT_AUDIO_CHUNKS_INVALID',
        message: 'The first audio chunk must start at zero'
      };
    }

    return {
      ok: true,
      media: { parts: chunks, deleteAfterUse: true }
    };
  }

  return {
    ok: true,
    media: {
      parts: [
        {
          key: videoS3Key as string,
          kind: 'legacy-video',
          startSeconds: 0
        }
      ],
      deleteAfterUse: false
    }
  };
};

const shiftTranscriptionResult = (
  result: TranscriptionResult,
  startSeconds: number,
  endSeconds?: number
): TranscriptionResult => {
  const shiftAndClipRanges = <T extends { start: number; end: number }>(
    ranges: T[]
  ): T[] =>
    ranges.flatMap((range) => {
      const start = Math.max(startSeconds, startSeconds + range.start);
      const shiftedEnd = startSeconds + range.end;
      const end =
        endSeconds === undefined ? shiftedEnd : Math.min(shiftedEnd, endSeconds);
      if (end <= start) {
        return [];
      }
      return [{ ...range, start, end }];
    });

  return {
    ...result,
    durationSeconds: endSeconds ?? startSeconds + result.durationSeconds,
    segments: shiftAndClipRanges(result.segments),
    words: shiftAndClipRanges(result.words)
  };
};

const mergeChunkedTranscriptions = (
  chunks: Array<{ startSeconds: number; transcript: TranscriptionResult }>
): TranscriptionResult => {
  if (chunks.length === 1 && chunks[0]?.startSeconds === 0) {
    return chunks[0].transcript;
  }

  const shifted = chunks.map(({ startSeconds, transcript }, index) =>
    shiftTranscriptionResult(
      transcript,
      startSeconds,
      chunks[index + 1]?.startSeconds
    )
  );
  return {
    text: shifted
      .map((chunk) => chunk.text.trim())
      .filter(Boolean)
      .join(' '),
    language: shifted.find((chunk) => chunk.language.trim())?.language ?? 'th',
    durationSeconds: Math.max(
      0,
      ...shifted.map((chunk) => chunk.durationSeconds)
    ),
    segments: shifted.flatMap((chunk) => chunk.segments),
    words: shifted.flatMap((chunk) => chunk.words),
    model: shifted.find((chunk) => chunk.model.trim())?.model ?? ''
  };
};

const readSegments = (value: unknown): EditPlanSegment[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((item) => {
    if (typeof item !== 'object' || item === null) {
      return [];
    }

    const record = item as Record<string, unknown>;
    const start = record.start;
    const end = record.end;

    if (typeof start !== 'number' || typeof end !== 'number') {
      return [];
    }

    return [
      {
        text: typeof record.text === 'string' ? record.text : '',
        start,
        end,
        ...(typeof record.avgLogprob === 'number'
          ? { avgLogprob: record.avgLogprob }
          : {}),
        ...(typeof record.noSpeechProbability === 'number'
          ? { noSpeechProbability: record.noSpeechProbability }
          : {}),
        ...(typeof record.compressionRatio === 'number'
          ? { compressionRatio: record.compressionRatio }
          : {})
      }
    ];
  });
};

const buildQuota = (usedMinutes: number) => ({
  limitMinutes: aiEditMonthlyMinuteLimit,
  usedMinutes,
  remainingMinutes: Math.max(0, aiEditMonthlyMinuteLimit - usedMinutes)
});

const sendAiEditMediaErrorResponse = (
  response: Response,
  result: Extract<ReadAiEditMediaResult, { ok: false }>
) => {
  response.status(400).json({
    status: 'error',
    code: result.code,
    message: result.message
  });
};

const sendForbiddenMediaKeyResponse = (response: Response) => {
  response.status(403).json({
    status: 'error',
    code: 'MEDIA_KEY_FORBIDDEN',
    message: 'Selected media does not belong to the authenticated user'
  });
};

const sendMediaDownloadErrorResponse = (response: Response, error: MediaDownloadError) => {
  response.status(error.statusCode).json({
    status: 'error',
    code: error.code,
    message: error.message
  });
};

const sendTranscriptionProviderErrorResponse = (
  response: Response,
  error: unknown
) => {
  console.error(
    'AI transcription provider failed:',
    error instanceof Error ? error.message : error
  );
  response.status(502).json({
    status: 'error',
    code: 'AI_TRANSCRIPTION_PROVIDER_FAILED',
    message: 'AI transcription is temporarily unavailable'
  });
};

const sendAiEditQuotaExceededResponse = (response: Response) => {
  response.status(402).json({
    status: 'error',
    code: 'AI_EDIT_QUOTA_EXCEEDED',
    message: `AI editing is limited to ${aiEditMonthlyMinuteLimit} minutes per month`
  });
};

export const registerAiEditRoutes = (
  router: Router,
  transcriptionProvider: TranscriptionProvider,
  authMiddleware: RequestHandler,
  subscriptionStore: SubscriptionStore,
  aiEditUsageStore: AiEditUsageStore,
  editPlanProvider: EditPlanProvider,
  deleteMedia: (mediaS3Key: string) => Promise<void>,
  visualEditPlanProvider?: VisualEditPlanProvider,
  fetchVisualMedia?: (videoS3Key: string) => Promise<RealClipMediaPart>
) => {
  const cleanupTemporaryAudio = async (media: AiEditMedia) => {
    if (!media.deleteAfterUse) {
      return;
    }

    for (const part of media.parts) {
      try {
        await deleteMedia(part.key);
      } catch (error) {
        console.error(
          'AI edit temporary audio cleanup failed:',
          error instanceof Error ? error.message : error
        );
      }
    }
  };

  const mediaBelongsToUser = (media: AiEditMedia, userId: string) =>
    media.parts.every((part) =>
      isStorageKeyOwnedByUser({ videoS3Key: part.key, userId })
    );

  const transcribeMedia = async (
    media: AiEditMedia
  ): Promise<TranscriptionResult> => {
    const chunks: Array<{
      startSeconds: number;
      transcript: TranscriptionResult;
    }> = [];
    for (const part of media.parts) {
      chunks.push({
        startSeconds: part.startSeconds,
        transcript: await transcriptionProvider.transcribe({
          mediaS3Key: part.key,
          mediaKind: part.kind
        })
      });
    }
    return mergeChunkedTranscriptions(chunks);
  };

  router.post('/ai-edits/audio/cleanup', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const audioS3Key = readRequiredString(request.body?.audioS3Key);

    if (!audioS3Key || !audioS3Key.toLowerCase().endsWith('.m4a')) {
      response.status(400).json({
        status: 'error',
        code: 'AI_EDIT_AUDIO_KEY_INVALID',
        message: 'audioS3Key must identify an M4A file'
      });
      return;
    }

    if (!isStorageKeyOwnedByUser({ videoS3Key: audioS3Key, userId: authUser.id })) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    try {
      await deleteMedia(audioS3Key);
      response.json({ status: 'ok' });
    } catch (error) {
      console.error(
        'AI edit explicit audio cleanup failed:',
        error instanceof Error ? error.message : error
      );
      response.status(502).json({
        status: 'error',
        code: 'AI_EDIT_AUDIO_CLEANUP_FAILED',
        message: 'Temporary audio cleanup failed'
      });
    }
  });

  router.post(
    '/ai-edits/visual-proxy/cleanup',
    authMiddleware,
    async (request, response) => {
      const authUser = readAuthUser(response.locals);
      if (!authUser) {
        response.status(401).json({
          status: 'error',
          message: 'Authenticated user is required'
        });
        return;
      }

      const visualProxyResult = readVisualProxyKey(
        request.body?.visualProxyS3Key
      );
      if (!visualProxyResult.ok || !visualProxyResult.key) {
        response.status(400).json({
          status: 'error',
          code: 'AI_EDIT_VISUAL_PROXY_KEY_INVALID',
          message:
            visualProxyResult.ok
              ? 'visualProxyS3Key is required'
              : visualProxyResult.message
        });
        return;
      }
      const visualProxyS3Key = visualProxyResult.key;
      if (!isStorageKeyOwnedByUser({
        videoS3Key: visualProxyS3Key,
        userId: authUser.id
      })) {
        sendForbiddenMediaKeyResponse(response);
        return;
      }

      try {
        await deleteMedia(visualProxyS3Key);
      } catch (error) {
        console.error(
          'AI edit visual proxy cleanup failed:',
          error instanceof Error ? error.message : error
        );
        response.status(502).json({
          status: 'error',
          code: 'AI_EDIT_VISUAL_PROXY_CLEANUP_FAILED',
          message: 'Temporary visual proxy cleanup failed'
        });
        return;
      }
      response.json({ status: 'ok' });
    }
  );

  router.get('/ai-edits/quota', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const usedMinutes = await aiEditUsageStore.sumMinutesForMonth({
      userId: authUser.id,
      monthKey: readCurrentAiEditMonthKey()
    });

    response.json({ status: 'ok', quota: buildQuota(usedMinutes) });
  });

  router.post('/ai-edits/transcribe', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const mediaResult = readAiEditMedia(request.body);

    if (!mediaResult.ok) {
      sendAiEditMediaErrorResponse(response, mediaResult);
      return;
    }

    const media = mediaResult.media;

    if (!mediaBelongsToUser(media, authUser.id)) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    try {
      const plan = await subscriptionStore.getPlan(authUser);

      if (plan !== 'PRO') {
        response.status(402).json({
          status: 'error',
          code: 'PRO_REQUIRED',
          message: 'AI auto editing requires the Pro plan'
        });
        return;
      }

    // Client-provided duration is only a pre-check estimate to reject obviously
    // over-quota requests before spending a transcription call. Actual metering
    // (below) uses the real clip duration the provider returns, so a client
    // cannot under-report duration to bypass the monthly limit.
    const estimatedMinutes = Math.max(
      1,
      Math.ceil((readPositiveNumber(request.body?.durationSeconds) ?? 60) / 60)
    );
    const monthKey = readCurrentAiEditMonthKey();
    const usedMinutes = await aiEditUsageStore.sumMinutesForMonth({
      userId: authUser.id,
      monthKey
    });

    if (usedMinutes + estimatedMinutes > aiEditMonthlyMinuteLimit) {
      sendAiEditQuotaExceededResponse(response);
      return;
    }

    let transcript;

    try {
      transcript = await transcribeMedia(media);
    } catch (error) {
      if (error instanceof MediaDownloadError) {
        sendMediaDownloadErrorResponse(response, error);
        return;
      }

      sendTranscriptionProviderErrorResponse(response, error);
      return;
    }

    // Meter the real transcribed duration, not the client estimate.
    const billedMinutes =
      transcript.durationSeconds > 0
        ? Math.ceil(transcript.durationSeconds / 60)
        : estimatedMinutes;

    const reservation = await aiEditUsageStore.reserve({
      userId: authUser.id,
      monthKey,
      minutes: billedMinutes,
      limit: aiEditMonthlyMinuteLimit
    });

    if (!reservation.ok) {
      sendAiEditQuotaExceededResponse(response);
      return;
    }

      response.json({
        status: 'ok',
        transcript,
        quota: buildQuota(reservation.usedMinutes)
      });
    } finally {
      await cleanupTemporaryAudio(media);
    }
  });

  // Builds the UI-facing edit recipe in one call: transcript, cut suggestions,
  // overlays, render hints, and capability status for the mobile FFmpeg editor.
  router.post('/ai-edits/prepare', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const mediaResult = readAiEditMedia(request.body);

    if (!mediaResult.ok) {
      sendAiEditMediaErrorResponse(response, mediaResult);
      return;
    }

    const media = mediaResult.media;

    if (!mediaBelongsToUser(media, authUser.id)) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    try {
      const userPlan = await subscriptionStore.getPlan(authUser);

      if (userPlan !== 'PRO') {
        response.status(402).json({
          status: 'error',
          code: 'PRO_REQUIRED',
          message: 'AI auto editing requires the Pro plan'
        });
        return;
      }

    const estimatedDurationSeconds = readPositiveNumber(request.body?.durationSeconds) ?? 60;
    const estimatedMinutes = Math.max(1, Math.ceil(estimatedDurationSeconds / 60));
    const monthKey = readCurrentAiEditMonthKey();
    const usedMinutes = await aiEditUsageStore.sumMinutesForMonth({
      userId: authUser.id,
      monthKey
    });

    if (usedMinutes + estimatedMinutes > aiEditMonthlyMinuteLimit) {
      sendAiEditQuotaExceededResponse(response);
      return;
    }

    let transcript;

    try {
      transcript = await transcribeMedia(media);
    } catch (error) {
      if (error instanceof MediaDownloadError) {
        sendMediaDownloadErrorResponse(response, error);
        return;
      }

      sendTranscriptionProviderErrorResponse(response, error);
      return;
    }

    const billedMinutes =
      transcript.durationSeconds > 0
        ? Math.ceil(transcript.durationSeconds / 60)
        : estimatedMinutes;

    const reservation = await aiEditUsageStore.reserve({
      userId: authUser.id,
      monthKey,
      minutes: billedMinutes,
      limit: aiEditMonthlyMinuteLimit
    });

    if (!reservation.ok) {
      sendAiEditQuotaExceededResponse(response);
      return;
    }

    const styleId = readRequiredString(request.body?.styleId);
    const prompt = readRequiredString(request.body?.prompt);
    const targetDurationSeconds = readPositiveNumber(
      request.body?.targetDurationSeconds
    );
    const durationSeconds =
      transcript.durationSeconds > 0 ? transcript.durationSeconds : estimatedDurationSeconds;
    const editPlan =
      styleId || prompt || targetDurationSeconds
        ? await editPlanProvider.plan({
            segments: transcript.segments,
            durationSeconds,
            targetDurationSeconds,
            styleId,
            prompt
          })
        : undefined;

    const recipe = buildAiEditRecipe({
      transcript,
      capabilities: readAiEditCapabilities(request.body?.capabilities),
      settings: readAiEditRecipeSettings(request.body?.settings),
      styleId,
      prompt,
      plan: editPlan
    });

      response.json({
        status: 'ok',
        recipe,
        quota: buildQuota(reservation.usedMinutes)
      });
    } finally {
      await cleanupTemporaryAudio(media);
    }
  });
  // Returns a structured cut plan for a style or a free-form prompt. Operates on
  // an already-transcribed clip, so it is Pro-gated but does not meter minutes.
  router.post('/ai-edits/plan', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const userPlan = await subscriptionStore.getPlan(authUser);

    if (userPlan !== 'PRO') {
      response.status(402).json({
        status: 'error',
        code: 'PRO_REQUIRED',
        message: 'AI auto editing requires the Pro plan'
      });
      return;
    }

    const durationSeconds = readPositiveNumber(request.body?.durationSeconds);

    if (durationSeconds === undefined) {
      response.status(400).json({
        status: 'error',
        message: 'durationSeconds is required'
      });
      return;
    }

    const styleId = readRequiredString(request.body?.styleId);
    const prompt = readRequiredString(request.body?.prompt);
    const targetDurationSeconds = readPositiveNumber(
      request.body?.targetDurationSeconds
    );
    const visualProxyResult = readVisualProxyKey(
      request.body?.visualProxyS3Key
    );

    if (!visualProxyResult.ok) {
      response.status(400).json({
        status: 'error',
        code: 'AI_EDIT_VISUAL_PROXY_KEY_INVALID',
        message: visualProxyResult.message
      });
      return;
    }
    const visualProxyS3Key = visualProxyResult.key;
    if (
      visualProxyS3Key &&
      !isStorageKeyOwnedByUser({
        videoS3Key: visualProxyS3Key,
        userId: authUser.id
      })
    ) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    if (!styleId && !prompt && !targetDurationSeconds) {
      response.status(400).json({
        status: 'error',
        message: 'styleId, prompt, or targetDurationSeconds is required'
      });
      return;
    }

    const segments = readSegments(request.body?.segments);
    const fallbackPlan = () =>
      editPlanProvider.plan({
        segments,
        durationSeconds,
        targetDurationSeconds,
        styleId,
        prompt
      });

    try {
      let plan;
      if (
        visualProxyS3Key &&
        targetDurationSeconds !== undefined &&
        visualEditPlanProvider &&
        fetchVisualMedia
      ) {
        try {
          const video = await fetchVisualMedia(visualProxyS3Key);
          plan = await visualEditPlanProvider.plan({
            video,
            segments,
            durationSeconds,
            targetDurationSeconds
          });
        } catch (error) {
          console.error(
            'AI visual edit planning failed; falling back to audio:',
            error instanceof Error ? error.message : error
          );
          plan = await fallbackPlan();
        }
      } else {
        plan = await fallbackPlan();
      }

      response.json({ status: 'ok', plan });
    } finally {
      if (visualProxyS3Key) {
        await Promise.allSettled([deleteMedia(visualProxyS3Key)]);
      }
    }
  });
};
