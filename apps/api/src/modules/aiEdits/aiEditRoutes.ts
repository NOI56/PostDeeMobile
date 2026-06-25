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

export const registerAiEditRoutes = (
  router: Router,
  transcriptionProvider: TranscriptionProvider,
  authMiddleware: RequestHandler,
  subscriptionStore: SubscriptionStore,
  aiEditUsageStore: AiEditUsageStore,
  editPlanProvider: EditPlanProvider
) => {
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

    const videoS3Key = readRequiredString(request.body?.videoS3Key);

    if (!videoS3Key) {
      response.status(400).json({
        status: 'error',
        message: 'videoS3Key is required'
      });
      return;
    }

    const plan = await subscriptionStore.getPlan(authUser);

    if (plan !== 'PRO') {
      response.status(402).json({
        status: 'error',
        code: 'PRO_REQUIRED',
        message: 'AI auto editing requires the Pro plan'
      });
      return;
    }

    if (!isStorageKeyOwnedByUser({ videoS3Key, userId: authUser.id })) {
      sendForbiddenMediaKeyResponse(response);
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
      response.status(402).json({
        status: 'error',
        code: 'AI_EDIT_QUOTA_EXCEEDED',
        message: `AI editing is limited to ${aiEditMonthlyMinuteLimit} minutes per month`
      });
      return;
    }

    let transcript;

    try {
      transcript = await transcriptionProvider.transcribe({ videoS3Key });
    } catch (error) {
      if (error instanceof MediaDownloadError) {
        sendMediaDownloadErrorResponse(response, error);
        return;
      }

      throw error;
    }

    // Meter the real transcribed duration, not the client estimate.
    const billedMinutes =
      transcript.durationSeconds > 0
        ? Math.ceil(transcript.durationSeconds / 60)
        : estimatedMinutes;

    await aiEditUsageStore.record({
      userId: authUser.id,
      monthKey,
      minutes: billedMinutes
    });

    response.json({
      status: 'ok',
      transcript,
      quota: buildQuota(usedMinutes + billedMinutes)
    });
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
