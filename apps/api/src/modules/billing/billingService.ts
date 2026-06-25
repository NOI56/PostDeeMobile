import type { PaidSubscriptionPlan } from '../subscriptions/subscriptionStore.js';

type PaidPlanRequestResult =
  | {
      ok: true;
      plan: PaidSubscriptionPlan;
    }
  | {
      ok: false;
      message: string;
    };

export const readPaidPlanRequest = (body: unknown): PaidPlanRequestResult => {
  const payload = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const plan = payload.plan;

  if (plan !== 'STARTER' && plan !== 'PRO') {
    return {
      ok: false as const,
      message: 'plan must be STARTER or PRO'
    };
  }

  return {
    ok: true as const,
    plan
  };
};

export const readProPlanRequest = readPaidPlanRequest;
