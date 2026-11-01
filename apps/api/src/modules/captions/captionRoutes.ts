import type { RequestHandler, Response, Router } from 'express';
import type { MonthlyAddonStore } from '../billing/monthlyAddonStore.js';
import { reportMonitoringError } from '../../monitoring/sentryMonitoring.js';

import type { TranscriptionProvider } from '../aiEdits/transcriptionProvider.js';
import { readAuthUser } from '../auth/authTypes.js';
import {
  MediaDownloadError,
  aiCaptionFrameMaxBytes,
  aiMediaDownloadMaxBytes,
  realClipCaptionClipMaxBytes,
  type AiMediaFetchOptions
} from '../storage/mediaDownload.js';
import { isStorageKeyOwnedByUser } from '../storage/storageKeyPolicy.js';
import {
  monthlyAiCaptionGenerationLimits,
  readPlanLabel,
  readRealClipCaptionMode
} from '../subscriptions/subscriptionEntitlements.js';
import type { SubscriptionStore } from '../subscriptions/subscriptionStore.js';
import type { UserStore } from '../users/userStore.js';
import type { CaptionGenerator } from './captionGeneratorFactory.js';
import {
  generateLocalAffiliateCaption,
  generateLocalRealClipCaption,
  readRealClipPlatformCaptions,
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
import { CaptionInsufficientEvidenceError } from './realClipCaptionProvider.js';

const defaultMaxConcurrentMediaRequests = 2;
const defaultCaptionGenerationTimeoutMs = 90_000;

class CaptionRequestInterruptedError extends Error {
  constructor(readonly disconnected: boolean) {
    super(disconnected ? 'Caption client disconnected' : 'Caption generation timed out');
  }
}

const createCaptionRequestDeadline = (response: Response, timeoutMs: number) => {
  const controller = new AbortController();
  const abort = (disconnected: boolean) => {
    if (!controller.signal.aborted) controller.abort(new CaptionRequestInterruptedError(disconnected));
  };
  const timer = setTimeout(() => abort(false), timeoutMs);
  const onClose = () => { if (!response.writableFinished) abort(true); };
  const dispose = () => {
    clearTimeout(timer);
    response.off('close', onClose);
    response.off('finish', dispose);
  };
  response.once('close', onClose);
  response.once('finish', dispose);
  return {
    signal: controller.signal,
    dispose,
    // Race only provider/download/read work. A late result from an adapter
    // ignoring AbortSignal cannot continue into the next stage or charge again.
    run: async <T>(operation: () => Promise<T>): Promise<T> => {
      controller.signal.throwIfAborted();
      let onAbort!: () => void;
      const interrupted = new Promise<never>((_resolve, reject) => {
        onAbort = () => reject(controller.signal.reason);
        controller.signal.addEventListener('abort', onAbort, { once: true });
      });
      try { return await Promise.race([operation(), interrupted]); }
      finally { controller.signal.removeEventListener('abort', onAbort); }
    }
  };
};

const sendMediaBusyResponse = (response: Response) => {
  response.set('Retry-After', '1').status(503).json({
    status: 'error',
    code: 'AI_MEDIA_BUSY',
    message: 'AI caption is busy right now. Please try again in a moment.'
  });
};

const sendForbiddenMediaKeyResponse = (response: Response) => {
  response.status(403).json({
    status: 'error',
    code: 'MEDIA_KEY_FORBIDDEN',
    message: 'Selected media does not belong to the authenticated user'
  });
};

const releaseFailedCaptionUsage = async (
  store: RealClipCaptionUsageStore,
  reservation?: RealClipCaptionUsageReservation
) => {
  if (!reservation?.ok) return false;
  try {
    if (reservation.records && reservation.records.length > 1) {
      return store.releaseMany ? await store.releaseMany(reservation.records) : false;
    }
    return store.release ? await store.release(reservation.record) : false;
  } catch (error) {
    console.error('Could not release failed AI caption usage:', error);
    return false;
  }
};

const readUsageAfterFallback = async (
  store: RealClipCaptionUsageStore,
  input: { userId: string; monthKey: string },
  released: boolean,
  reservedCount: number
) => {
  if (!released) return { usedThisMonth: reservedCount };
  try {
    return { usedThisMonth: await store.countForMonth(input) };
  } catch (error) {
    // The refund is already committed. Keep the caption usable and show the
    // last known conservative count until the next subscription refresh.
    console.error('Could not refresh AI caption usage after refund:', error);
    return { usedThisMonth: reservedCount, usageRefreshPending: true };
  }
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
  usedThisMonth,
  addonRemaining,
  requiredCredits
}: {
  response: Response;
  plan: Parameters<typeof readPlanLabel>[0];
  limit: number;
  usedThisMonth: number;
  addonRemaining: number;
  requiredCredits: number;
}) => {
  const remainingThisMonth = Math.max(limit - usedThisMonth, 0);
  response.status(429).json({
    status: 'error',
    code: 'AI_CAPTION_QUOTA_REACHED',
    message: `${readPlanLabel(plan)} has insufficient AI caption credits for ${requiredCredits} selected channel(s)`,
    quota: {
      limit,
      usedThisMonth,
      remainingThisMonth,
      addonRemaining,
      availableGenerations: remainingThisMonth + addonRemaining,
      requiredCredits
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
      remainingThisMonth: 0,
      addonRemaining: 0,
      availableGenerations: 0
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
  fetchClipMedia?: (videoS3Key: string, options?: AiMediaFetchOptions) => Promise<RealClipMediaPart>,
  deleteClipMedia?: (videoS3Key: string) => Promise<void>,
  userStore?: UserStore,
  options: {
    monthlyAddonStore?: Pick<MonthlyAddonStore, 'readCredits'>;
    billingAddonsEnabled?: boolean;
    now?: () => Date;
    maxConcurrentMediaRequests?: number;
    captionGenerationTimeoutMs?: number;
  } = {}
) => {
  // Both Gemini and legacy transcription hold media in this shared process.
  // Admit only a few requests at once, before downloading or reserving usage.
  const maxConcurrentMediaRequests = options.maxConcurrentMediaRequests ?? defaultMaxConcurrentMediaRequests;
  let activeMediaRequests = 0;
  const acquireMediaSlot = () => {
    if (activeMediaRequests >= maxConcurrentMediaRequests) return undefined;
    activeMediaRequests += 1;
    return () => { activeMediaRequests -= 1; };
  };
  const readAddonRemaining = async (userId: string, now: string) => {
    const [grants, used] = await Promise.all([
      options.monthlyAddonStore?.readCredits({ userId, now }),
      realClipCaptionUsageStore.countAddonUsages({ userId })
    ]);
    return Math.max(0, (grants?.aiCaptions ?? 0) - used);
  };
  const readFinalAddonRemaining = async (userId: string, now: string, fallback: number) => {
    try { return await readAddonRemaining(userId, now); }
    catch { return Math.max(0, fallback); }
  };
  router.get('/captions/quota', authMiddleware, async (_request, response) => {
    const authUser = readAuthUser(response.locals);

    if (!authUser) {
      response.status(401).json({
        status: 'error',
        message: 'Authenticated user is required'
      });
      return;
    }

    const plan = await subscriptionStore.getPlan(authUser);
    const now = (options.now?.() ?? new Date()).toISOString();
    const monthKey = readCurrentRealClipCaptionMonthKey(new Date(now));
    const limit = monthlyAiCaptionGenerationLimits[plan];
    const [usedThisMonth, addonRemaining] = await Promise.all([
      realClipCaptionUsageStore.countForMonth({ userId: authUser.id, monthKey }),
      readAddonRemaining(authUser.id, now)
    ]);
    const remainingThisMonth = Math.max(limit - usedThisMonth, 0);

    response.set('Cache-Control', 'no-store').json({
      status: 'ok',
      plan,
      quota: {
        limit,
        usedThisMonth,
        remainingThisMonth,
        addonRemaining,
        availableGenerations: plan === 'BASIC' ? 0 : remainingThisMonth + addonRemaining
      }
    });
  });

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

    const now = (options.now?.() ?? new Date()).toISOString();
    const monthKey = readCurrentRealClipCaptionMonthKey(new Date(now));
    const baseLimit = monthlyAiCaptionGenerationLimits[plan];
    const includeMonthlyAddons = true;
    const addonRemaining = await readAddonRemaining(authUser.id, now);
    const limit = baseLimit;
    await userStore?.ensure(authUser);
    const reservation = await realClipCaptionUsageStore.reserve({
      userId: authUser.id,
      monthKey,
      limit: baseLimit,
      ...(includeMonthlyAddons ? { includeMonthlyAddons: true, now } : {})
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
    let isFallback = false;
    let releasedFallbackUsage = false;

    try {
      caption = await generator.generate(validation.keywords);
    } catch (error) {
      reportMonitoringError(error, { operation: 'captions.provider' });
      // Fall back to the local template caption so a transient provider
      // outage (e.g. Gemini returning 503 under high demand) still returns a
      // usable caption instead of surfacing a 500 to the user. Log it so a
      // persistently broken provider/key is visible in ops and Sentry
      // instead of silently degrading to template captions forever.
      console.error(
        'Caption generation failed; using local fallback:',
        error instanceof Error ? error.message : error
      );
      caption = generateLocalAffiliateCaption(validation.keywords);
      isFallback = true;
      releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
    }

    const finalUsage = await readUsageAfterFallback(realClipCaptionUsageStore,
      { userId: authUser.id, monthKey }, releasedFallbackUsage, reservation.usedThisMonth);
    const finalAddonRemaining = await readFinalAddonRemaining(authUser.id, now,
      addonRemaining - (reservation.record.usesAddonCredit && !releasedFallbackUsage ? 1 : 0));
    response.json({
      status: 'ok',
      ...caption,
      ...(isFallback ? { isFallback: true } : {}),
      quota: {
        limit,
        ...finalUsage,
        remainingThisMonth: Math.max(limit - finalUsage.usedThisMonth, 0),
        addonRemaining: finalAddonRemaining,
        availableGenerations: Math.max(limit - finalUsage.usedThisMonth, 0) + finalAddonRemaining,
        ...(isFallback ? { charged: !releasedFallbackUsage } : {})
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
        ...('code' in validation ? { code: validation.code } : {}),
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
    let cleanupPromise: Promise<void> | undefined;
    const cleanupRequestedMedia = () => cleanupPromise ??= (async () => {
      if (!deleteClipMedia || cleanupKeys.length === 0) {
        return;
      }

      const cleanup = Promise.allSettled(
        cleanupKeys.map((videoS3Key) => Promise.resolve().then(() => deleteClipMedia(videoS3Key)))
      ).then(results => {
        for (const result of results) {
          if (result.status === 'rejected') {
            console.error(
              'AI caption media cleanup failed:',
              result.reason instanceof Error ? result.reason.message : result.reason
            );
          }
        }
      });
      let timer!: ReturnType<typeof setTimeout>;
      try {
        await Promise.race([cleanup, new Promise<void>(resolve => { timer = setTimeout(resolve, 5000); })]);
      } finally { clearTimeout(timer); }
    })();

    // The server derives price from validated channels. Old apps displaying one
    // credit must acknowledge the new price before any multi-channel debit.
    const requiredCredits = validation.request.platforms?.length ?? 1;
    const expectedCredits: unknown = request.body?.expectedCredits;
    if ((requiredCredits > 1 || expectedCredits !== undefined) && expectedCredits !== requiredCredits) {
      await cleanupRequestedMedia();
      response.status(409).json({
        status: 'error',
        code: 'AI_CAPTION_COST_CONFIRMATION_REQUIRED',
        message: 'Please update the app to confirm the AI caption credit cost.',
        quota: { requiredCredits, chargedCredits: 0 }
      });
      return;
    }

    const now = (options.now?.() ?? new Date()).toISOString();
    const monthKey = readCurrentRealClipCaptionMonthKey(new Date(now));
    const baseLimit = monthlyAiCaptionGenerationLimits[plan];
    const includeMonthlyAddons = true;
    const addonRemaining = await readAddonRemaining(authUser.id, now);
    const limit = baseLimit;
    const usedThisMonth = await realClipCaptionUsageStore.countForMonth({
      userId: authUser.id,
      monthKey
    });

    if (Math.max(limit - usedThisMonth, 0) + addonRemaining < requiredCredits) {
      await cleanupRequestedMedia();
      sendQuotaReachedResponse({
        response,
        plan,
        limit,
        usedThisMonth,
        addonRemaining,
        requiredCredits
      });
      return;
    }

    let caption: GeneratedRealClipCaption | RealClipCaptionResult;
    let reservation: RealClipCaptionUsageReservation | undefined;
    let isFallback = false;
    let releasedFallbackUsage = false;
    let fallbackReason: 'INSUFFICIENT_EVIDENCE' | 'PROVIDER_UNAVAILABLE' | undefined;
    const deadline = createCaptionRequestDeadline(response, options.captionGenerationTimeoutMs ?? defaultCaptionGenerationTimeoutMs);
    const handleInterruption = async (error: unknown) => {
      if (!(error instanceof CaptionRequestInterruptedError)) return false;
      if (!releasedFallbackUsage) releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
      // Deleting temporary media is best effort and must not hold a timed-out
      // request or its account operation ticket open behind a stuck storage API.
      void cleanupRequestedMedia();
      deadline.dispose();
      const charged = Boolean(reservation?.ok && !releasedFallbackUsage);
      if (error.disconnected) {
        // End the handler even with a dead socket: owner-operation lifetime is
        // released by end/finish only after the reservation refund has settled.
        if (charged) response.status(500);
        response.end();
      } else {
        response.status(504).json({ status: 'error', code: 'CAPTION_GENERATION_TIMEOUT',
          message: 'Caption generation took too long. Please try again.',
          quota: { requestedCredits: requiredCredits, chargedCredits: charged ? requiredCredits : 0, charged } });
      }
      return true;
    };
    const reserveUsageOrRespond = async () => {
      deadline.signal.throwIfAborted();
      if (reservation) {
        return reservation;
      }

      await userStore?.ensure(authUser);
      deadline.signal.throwIfAborted();
      const nextReservation = await realClipCaptionUsageStore.reserve({
        userId: authUser.id,
        monthKey,
        limit: baseLimit,
        ...(requiredCredits > 1 ? { units: requiredCredits } : {}),
        ...(includeMonthlyAddons ? { includeMonthlyAddons: true, now } : {})
      });

      // Do not race a durable reservation: if its write completes after the
      // deadline, retain its exact rows so the caller can refund before ending.
      if (nextReservation.ok) reservation = nextReservation;
      deadline.signal.throwIfAborted();

      if (!nextReservation.ok) {
        await deadline.run(cleanupRequestedMedia);
        sendQuotaReachedResponse({
          response,
          plan,
          limit,
          usedThisMonth: nextReservation.usedThisMonth,
          addonRemaining: await deadline.run(() => readFinalAddonRemaining(authUser.id, now, 0)),
          requiredCredits
        });
        return undefined;
      }

      reservation = nextReservation;
      return reservation;
    };

    try {
      if (realClipCaptionProvider && fetchClipMedia) {
        // Primary path: Gemini listens to the clip (Starter) and also looks at
        // selected frames (Pro) to write the caption — no Whisper here.
        const releaseMediaSlot = acquireMediaSlot();
        if (!releaseMediaSlot) {
          await deadline.run(cleanupRequestedMedia);
          sendMediaBusyResponse(response);
          return;
        }

        try {
          try {
            if (!(await reserveUsageOrRespond())) {
              return;
            }

            const audio = await deadline.run(() => fetchClipMedia(validation.request.videoS3Key, {
              kind: validation.request.mediaKind ?? 'video',
              maxBytes: realClipCaptionClipMaxBytes,
              signal: deadline.signal
            })).catch((error: unknown) => {
              // A legacy full video this large was always rejected by Gemini and
              // fell back to the template; keep that outcome without the download.
              // Beyond the general AI media limit it stays a 413 as before.
              if (
                validation.request.mediaKind !== 'audio' &&
                error instanceof MediaDownloadError &&
                error.code === 'AI_MEDIA_TOO_LARGE' &&
                (error.declaredSizeBytes ?? 0) <= aiMediaDownloadMaxBytes
              ) {
                throw new Error('Clip exceeds the Gemini inline caption budget');
              }

              throw error;
            });
            let frames: RealClipMediaPart[] | undefined;

            if (
              mode === 'AUDIO_WITH_FRAMES' &&
              validation.request.selectedFrameKeys.length > 0
            ) {
              frames = await deadline.run(() => Promise.all(
                validation.request.selectedFrameKeys.map((key) =>
                  fetchClipMedia(key, { kind: 'frame', maxBytes: aiCaptionFrameMaxBytes, signal: deadline.signal })
                )
              ));
            }

            caption = await deadline.run(() => realClipCaptionProvider.generate({
              request: validation.request,
              mode,
              audio,
              frames,
              signal: deadline.signal
            }));
            if (validation.request.platforms) {
              const platformCaptions = readRealClipPlatformCaptions(caption.platformCaptions, validation.request.platforms);
              if (!platformCaptions) {
                throw new Error('Real-clip AI provider returned incomplete or invalid platform captions');
              }
              caption = { ...caption, platformCaptions };
            }
          } catch (error) {
            if (await handleInterruption(error)) return;
            if (error instanceof MediaDownloadError) {
              releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
              await deadline.run(cleanupRequestedMedia);
              sendMediaDownloadErrorResponse(response, error);
              return;
            }

            if (!(await reserveUsageOrRespond())) {
              return;
            }

            // Keep a visibly editable fallback when AI cannot produce grounded
            // copy. Provider outages remain visible in ops and Sentry.
            if (!(error instanceof CaptionInsufficientEvidenceError)) {
              reportMonitoringError(error, { operation: 'captions.provider' });
              console.error(
                'Real-clip AI caption failed; using local template:',
                error instanceof Error ? error.message : error
              );
            }
            caption = generateLocalRealClipCaption({ request: validation.request, mode });
            isFallback = true;
            fallbackReason = error instanceof CaptionInsufficientEvidenceError ? 'INSUFFICIENT_EVIDENCE' : 'PROVIDER_UNAVAILABLE';
            releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
          }
        } finally {
          releaseMediaSlot();
        }
      } else if (transcriptionProvider) {
        // Legacy path: transcription -> local template.
        let transcript;
        const releaseMediaSlot = acquireMediaSlot();
        if (!releaseMediaSlot) {
          await deadline.run(cleanupRequestedMedia);
          sendMediaBusyResponse(response);
          return;
        }

        try {
          if (!(await reserveUsageOrRespond())) {
            return;
          }

          transcript = await deadline.run(() => transcriptionProvider.transcribe({
            mediaS3Key: validation.request.videoS3Key,
            mediaKind: validation.request.mediaKind === 'audio' ? 'audio' : 'legacy-video'
          }));
        } catch (error) {
          if (await handleInterruption(error)) return;
          releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
          if (error instanceof MediaDownloadError) {
            await deadline.run(cleanupRequestedMedia);
            sendMediaDownloadErrorResponse(response, error);
            return;
          }

          await deadline.run(cleanupRequestedMedia);
          reportMonitoringError(error, { operation: 'ai.transcription' });
          response.status(502).json({
            status: 'error',
            code: 'AI_CAPTION_TRANSCRIPTION_FAILED',
            message: 'Could not read audio from the selected clip'
          });
          return;
        } finally {
          releaseMediaSlot();
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

      if (caption.model === 'local-real-clip-template' && !isFallback) {
        isFallback = true;
        fallbackReason = 'PROVIDER_UNAVAILABLE';
        releasedFallbackUsage = await releaseFailedCaptionUsage(realClipCaptionUsageStore, reservation);
      }

      await deadline.run(cleanupRequestedMedia);

      const finalUsage = await deadline.run(() => readUsageAfterFallback(realClipCaptionUsageStore,
        { userId: authUser.id, monthKey }, releasedFallbackUsage,
        reservation?.usedThisMonth ?? usedThisMonth));
      const chargedAddonCredits = reservation?.ok && !releasedFallbackUsage
        ? (reservation.records ?? [reservation.record]).filter(record => record.usesAddonCredit).length : 0;
      const finalAddonRemaining = await deadline.run(() => readFinalAddonRemaining(authUser.id, now,
        addonRemaining - chargedAddonCredits));
      response.json({
        status: 'ok',
        ...caption,
        ...(isFallback ? { isFallback: true } : {}),
        ...(fallbackReason ? { fallbackReason } : {}),
        quota: {
          limit,
          ...finalUsage,
          remainingThisMonth: Math.max(limit - finalUsage.usedThisMonth, 0),
          addonRemaining: finalAddonRemaining,
          availableGenerations: Math.max(limit - finalUsage.usedThisMonth, 0) + finalAddonRemaining,
          requestedCredits: requiredCredits,
          chargedCredits: releasedFallbackUsage ? 0 : requiredCredits,
          ...(isFallback ? { charged: !releasedFallbackUsage } : {})
        }
      });
    } catch (error) {
      if (!(await handleInterruption(error))) throw error;
    } finally {
      deadline.dispose();
    }
  });
};
