import type { SubscriptionPlan } from './subscriptionStore.js';

export const monthlyPostUnitLimits: Record<SubscriptionPlan, number> = {
  BASIC: 3,
  STARTER: 120,
  PRO: 250
};

export const monthlyAiCaptionGenerationLimits: Record<SubscriptionPlan, number> = {
  BASIC: 0,
  STARTER: 50,
  PRO: 120
};

export const maxScheduleAheadDaysByPlan: Record<SubscriptionPlan, number> = {
  BASIC: 0,
  STARTER: 14,
  PRO: 30
};

export type RealClipCaptionEntitlementMode = 'AUDIO_ONLY' | 'AUDIO_WITH_FRAMES';

export const canSchedulePosts = (plan: SubscriptionPlan) => plan !== 'BASIC';

export const readRealClipCaptionMode = (
  plan: SubscriptionPlan
): RealClipCaptionEntitlementMode | undefined => {
  if (plan === 'STARTER') {
    return 'AUDIO_ONLY';
  }

  if (plan === 'PRO') {
    return 'AUDIO_WITH_FRAMES';
  }

  return undefined;
};

export const readPlanLabel = (plan: SubscriptionPlan) => {
  switch (plan) {
    case 'BASIC':
      return 'Basic';
    case 'STARTER':
      return 'Starter';
    case 'PRO':
      return 'Pro';
  }
};
