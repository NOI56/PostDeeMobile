import type { RequestHandler, Response, Router } from 'express';

import { readAuthUser } from '../auth/authTypes.js';
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
import type { TranscriptionProvider } from './transcriptionProvider.js';

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

type AiEditMedia =
  | { key: string; kind: 'audio'; deleteAfterUse: true }
  | { key: string; kind: 'legacy-video'; deleteAfterUse: false };

type ReadAiEditMediaResult =
  | { ok: true; media: AiEditMedia }
  | { ok: false; code: string; message: string };

const readAiEditMedia = (body: unknown): ReadAiEditMediaResult => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const audioS3Key = readRequiredString(payload.audioS3Key);
  const videoS3Key = readRequiredString(payload.videoS3Key);

  if (audioS3Key && videoS3Key) {
    return {
      ok: false,
      code: 'AI_EDIT_MEDIA_AMBIGUOUS',
      message: 'Provide exactly one of audioS3Key or videoS3Key'
    };
  }

  if (!audioS3Key && !videoS3Key) {
    return {
      ok: false,
      code: 'AI_EDIT_MEDIA_REQUIRED',
      message: 'audioS3Key or videoS3Key is required'
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
      media: { key: audioS3Key, kind: 'audio', deleteAfterUse: true }
    };
  }

  return {
    ok: true,
    media: { key: videoS3Key as string, kind: 'legacy-video', deleteAfterUse: false }
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
        end
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
  deleteMedia: (mediaS3Key: string) => Promise<void>
) => {
  const cleanupTemporaryAudio = async (media: AiEditMedia) => {
    if (!media.deleteAfterUse) {
      return;
    }

    try {
      await deleteMedia(media.key);
    } catch (error) {
      console.error(
        'AI edit temporary audio cleanup failed:',
        error instanceof Error ? error.message : error
      );
    }
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

    if (!isStorageKeyOwnedByUser({ videoS3Key: media.key, userId: authUser.id })) {
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
      transcript = await transcriptionProvider.transcribe({
        mediaS3Key: media.key,
        mediaKind: media.kind
      });
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

    if (!isStorageKeyOwnedByUser({ videoS3Key: media.key, userId: authUser.id })) {
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
      transcript = await transcriptionProvider.transcribe({
        mediaS3Key: media.key,
        mediaKind: media.kind
      });
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
    const durationSeconds =
      transcript.durationSeconds > 0 ? transcript.durationSeconds : estimatedDurationSeconds;
    const editPlan =
      styleId || prompt
        ? await editPlanProvider.plan({
            segments: transcript.segments,
            durationSeconds,
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

    if (!styleId && !prompt) {
      response.status(400).json({
        status: 'error',
        message: 'styleId or prompt is required'
      });
      return;
    }

    const plan = await editPlanProvider.plan({
      segments: readSegments(request.body?.segments),
      durationSeconds,
      styleId,
      prompt
    });

    response.json({ status: 'ok', plan });
  });
};
