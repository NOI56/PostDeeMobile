import type { RequestHandler, Response, Router } from 'express';

import type { TranscriptionProvider } from '../aiEdits/transcriptionProvider.js';
import { readAuthUser } from '../auth/authTypes.js';
import { MediaDownloadError } from '../storage/mediaDownload.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import {
  monthlyAiCaptionGenerationLimits,
  readPlanLabel,
  readRealClipCaptionMode
} from '../subscriptions/subscriptionEntitlements.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { CaptionGenerator } from './captionGeneratorFactory.js';
import {
  generateLocalAffiliateCaption,
  generateLocalRealClipCaption,
  validateCaptionKeywords,
  validateRealClipCaptionRequest,
  type RealClipCaptionResult
} from './captionService.js';
import {
  createInMemoryRealClipCaptionUsageStore,
  readCurrentRealClipCaptionMonthKey,
  type RealClipCaptionUsageReservation,
  type RealClipCaptionUsageStore
} from './captionUsageStore.js';
import type {
  GeneratedRealClipCaption,
  RealClipCaptionProvider,
  RealClipMediaPart
} from './realClipCaptionProvider.js';

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

const sendQuotaReachedResponse = ({
  response,
  plan,
  limit,
  usedThisMonth
}: {
  response: Response;
  plan: Parameters<typeof readPlanLabel>[0];
  limit: number;
  usedThisMonth: number;
}) => {
  response.status(429).json({
    status: 'error',
    code: 'AI_CAPTION_QUOTA_REACHED',
    message: `${readPlanLabel(plan)} is limited to ${limit} real-clip AI caption generations per month`,
    quota: {
      limit,
      usedThisMonth,
      remainingThisMonth: 0
    }
  });
};

const sendKeywordCaptionQuotaReachedResponse = ({
  response,
  plan,
  limit,
  usedThisMonth
}: {
  response: Response;
  plan: Parameters<typeof readPlanLabel>[0];
  limit: number;
  usedThisMonth: number;
}) => {
  response.status(429).json({
    status: 'error',
    code: 'AI_CAPTION_QUOTA_REACHED',
    message: `${readPlanLabel(plan)} is limited to ${limit} AI caption generations per month`,
    quota: {
      limit,
      usedThisMonth,
      remainingThisMonth: 0
    }
  });
};

const readCleanupKeys = ({
  videoS3Key,
  selectedFrameKeys,
  mode,
  deleteAfterUse
}: {
  videoS3Key: string;
  selectedFrameKeys: string[];
  mode: string;
  deleteAfterUse: boolean;
}) => {
  if (!deleteAfterUse) {
    return [];
  }

  return [
    ...new Set([
      videoS3Key,
      ...(mode === 'AUDIO_WITH_FRAMES' ? selectedFrameKeys : [])
    ])
  ];
};

export const registerCaptionRoutes = (
  router: Router,
  generator: CaptionGenerator,
  authMiddleware: RequestHandler,
  subscriptionStore: SubscriptionStore,
  transcriptionProvider?: TranscriptionProvider,
  realClipCaptionUsageStore: RealClipCaptionUsageStore = createInMemoryRealClipCaptionUsageStore(),
  realClipCaptionProvider?: RealClipCaptionProvider,
  fetchClipMedia?: (videoS3Key: string) => Promise<RealClipMediaPart>,
  deleteClipMedia?: (videoS3Key: string) => Promise<void>
) => {
  router.post('/captions/generate', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const plan = await subscriptionStore.getPlan(authUser);

    if (plan === 'BASIC') {
      response.status(402).json({
        status: 'error',
        code: 'PRO_REQUIRED',
        message: 'AI Caption Assistant requires a paid plan'
      });
      return;
    }

    const validation = validateCaptionKeywords(request.body?.keywords);

    if (!validation.ok) {
      response.status(400).json({
        status: 'error',
        message: validation.message
      });
      return;
    }

    const monthKey = readCurrentRealClipCaptionMonthKey();
    const limit = monthlyAiCaptionGenerationLimits[plan];
    const reservation = await realClipCaptionUsageStore.reserve({
      userId: authUser.id,
      monthKey,
      limit
    });

    if (!reservation.ok) {
      sendKeywordCaptionQuotaReachedResponse({
        response,
        plan,
        limit,
        usedThisMonth: reservation.usedThisMonth
      });
      return;
    }

    let caption;

    try {
      caption = await generator.generate(validation.keywords);
    } catch (error) {
      // Fall back to the local template caption so a transient provider
      // outage (e.g. Gemini returning 503 under high demand) still returns a
      // usable caption instead of surfacing a 500 to the user. Log it so a
      // persistently broken provider/key is visible in ops (and later Sentry)
      // instead of silently degrading to template captions forever.
      console.error(
        'Caption generation failed; using local fallback:',
        error instanceof Error ? error.message : error
      );
      caption = generateLocalAffiliateCaption(validation.keywords);
    }

    response.json({
      status: 'ok',
      ...caption,
      quota: {
        limit,
        usedThisMonth: reservation.usedThisMonth,
        remainingThisMonth: Math.max(limit - reservation.usedThisMonth, 0)
      }
    });
  });

  router.post('/captions/generate-from-clip', authMiddleware, async (request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const plan = await subscriptionStore.getPlan(authUser);
    const mode = readRealClipCaptionMode(plan);

    if (!mode) {
      response.status(402).json({
        status: 'error',
        code: 'PAID_PLAN_REQUIRED',
        message: 'AI caption from a real clip requires Starter or Pro'
      });
      return;
    }

    const validation = validateRealClipCaptionRequest(request.body);

    if (!validation.ok) {
      response.status(400).json({
        status: 'error',
        message: validation.message
      });
      return;
    }

    if (
      !isStorageKeyOwnedByUser({
        videoS3Key: validation.request.videoS3Key,
        userId: authUser.id
      })
    ) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    if (
      mode === 'AUDIO_WITH_FRAMES' &&
      validation.request.selectedFrameKeys.some(
        (videoS3Key) => !isStorageKeyOwnedByUser({ videoS3Key, userId: authUser.id })
      )
    ) {
      sendForbiddenMediaKeyResponse(response);
      return;
    }

    const cleanupKeys = readCleanupKeys({
      videoS3Key: validation.request.videoS3Key,
      selectedFrameKeys: validation.request.selectedFrameKeys,
      mode,
      deleteAfterUse: validation.request.deleteAfterUse
    });
    const cleanupRequestedMedia = async () => {
      if (!deleteClipMedia || cleanupKeys.length === 0) {
        return;
      }

      const results = await Promise.allSettled(
        cleanupKeys.map((videoS3Key) => deleteClipMedia(videoS3Key))
      );

      for (const result of results) {
        if (result.status === 'rejected') {
          console.error(
            'AI caption media cleanup failed:',
            result.reason instanceof Error ? result.reason.message : result.reason
          );
        }
      }
    };

    const monthKey = readCurrentRealClipCaptionMonthKey();
    const limit = monthlyAiCaptionGenerationLimits[plan];
    const usedThisMonth = await realClipCaptionUsageStore.countForMonth({
      userId: authUser.id,
      monthKey
    });

    if (usedThisMonth >= limit) {
      await cleanupRequestedMedia();
      sendQuotaReachedResponse({
        response,
        plan,
        limit,
        usedThisMonth
      });
      return;
    }

    let caption: GeneratedRealClipCaption | RealClipCaptionResult;
    let reservation: RealClipCaptionUsageReservation | undefined;
    const reserveUsageOrRespond = async () => {
      if (reservation) {
        return reservation;
      }

      const nextReservation = await realClipCaptionUsageStore.reserve({
        userId: authUser.id,
        monthKey,
        limit
      });

      if (!nextReservation.ok) {
        await cleanupRequestedMedia();
        sendQuotaReachedResponse({
          response,
          plan,
          limit,
          usedThisMonth: nextReservation.usedThisMonth
        });
        return undefined;
      }

      reservation = nextReservation;
      return reservation;
    };

    if (realClipCaptionProvider && fetchClipMedia) {
      // Primary path: Gemini listens to the clip (Starter) and also looks at
      // selected frames (Pro) to write the caption — no Whisper here.
      try {
        const audio = await fetchClipMedia(validation.request.videoS3Key);
        let frames: RealClipMediaPart[] | undefined;

        if (
          mode === 'AUDIO_WITH_FRAMES' &&
          validation.request.selectedFrameKeys.length > 0
        ) {
          frames = await Promise.all(
            validation.request.selectedFrameKeys.map((key) => fetchClipMedia(key))
          );
        }

        if (!(await reserveUsageOrRespond())) {
          return;
        }

        caption = await realClipCaptionProvider.generate({
          request: validation.request,
          mode,
          audio,
          frames
        });
      } catch (error) {
        if (error instanceof MediaDownloadError) {
          await cleanupRequestedMedia();
          sendMediaDownloadErrorResponse(response, error);
          return;
        }

        if (!(await reserveUsageOrRespond())) {
          return;
        }

        // Fall back to the local template so an AI/provider outage still returns
        // a usable caption. Logged so a broken provider is visible in ops.
        console.error(
          'Real-clip AI caption failed; using local template:',
          error instanceof Error ? error.message : error
        );
        caption = generateLocalRealClipCaption({ request: validation.request, mode });
      }
    } else if (transcriptionProvider) {
      // Legacy path: Whisper transcript -> local template.
      let transcript;

      try {
        if (!(await reserveUsageOrRespond())) {
          return;
        }

        transcript = await transcriptionProvider.transcribe({
          mediaS3Key: validation.request.videoS3Key,
          mediaKind: 'legacy-video'
        });
      } catch (error) {
        if (error instanceof MediaDownloadError) {
          await cleanupRequestedMedia();
          sendMediaDownloadErrorResponse(response, error);
          return;
        }

        await cleanupRequestedMedia();
        response.status(502).json({
          status: 'error',
          code: 'AI_CAPTION_TRANSCRIPTION_FAILED',
          message: 'Could not read audio from the selected clip'
        });
        return;
      }

      caption = generateLocalRealClipCaption({
        request: validation.request,
        mode,
        transcript
      });
    } else {
      if (!(await reserveUsageOrRespond())) {
        return;
      }

      caption = generateLocalRealClipCaption({ request: validation.request, mode });
    }

    await cleanupRequestedMedia();

    response.json({
      status: 'ok',
      ...caption,
      quota: {
        limit,
        usedThisMonth: reservation?.usedThisMonth ?? usedThisMonth,
        remainingThisMonth: Math.max(limit - (reservation?.usedThisMonth ?? usedThisMonth), 0)
      }
    });
  });
};
