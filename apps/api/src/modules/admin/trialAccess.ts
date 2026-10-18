import { createHash } from 'node:crypto';
import type { PaidSubscriptionPlan, SubscriptionPlan, SubscriptionStore } from '../subscriptions/subscriptionStore.js';

export type TrialAccess = { userId: string; plan: PaidSubscriptionPlan; startsAt: string;
  expiresAt: string; revokedAt: string | null; version: number };
export type TrialCommand = { requestId: string; actorId: string; userId: string;
  expectedEmail?: string;
  action: 'GRANT' | 'EXTEND' | 'REVOKE'; plan: PaidSubscriptionPlan; days: number;
  expectedVersion: number; reason: string };
export type TrialAudit = TrialCommand & { intentHash: string; before: TrialAccess | null;
  after: TrialAccess; createdAt: string };
export type TrialAccessStore = {
  find: (userId: string) => Promise<TrialAccess | null>;
  mutate: (command: TrialCommand) => Promise<TrialAccess>;
  history: () => Promise<TrialAudit[]>;
};
export class AdminError extends Error {
  constructor(readonly code: string, readonly status = 409) { super(code); }
}
const rank: Record<SubscriptionPlan, number> = { BASIC: 0, STARTER: 1, PRO: 2 };
export const activeTrial = (trial: TrialAccess | null, now = new Date()): TrialAccess | null =>
  trial && !trial.revokedAt && Date.parse(trial.startsAt) <= now.getTime() &&
    Date.parse(trial.expiresAt) > now.getTime() ? trial : null;
export const trialIntentHash = (c: TrialCommand) => createHash('sha256').update(JSON.stringify([
  c.actorId, c.userId, c.action, c.plan, c.days, c.expectedVersion, c.reason, c.expectedEmail ?? null
])).digest('hex');
export const applyTrialCommand = (previous: TrialAccess | null, c: TrialCommand, now: Date): TrialAccess => {
  if (!['GRANT', 'EXTEND', 'REVOKE'].includes(c.action) ||
      !['STARTER', 'PRO'].includes(c.plan) || ![7, 14, 30].includes(c.days) ||
      !Number.isSafeInteger(c.expectedVersion) || c.expectedVersion < 0 ||
      c.reason.trim().length < 3 || c.reason.length > 500 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(c.reason)) {
    throw new AdminError('ADMIN_TRIAL_INVALID', 400);
  }
  if ((previous?.version ?? 0) !== c.expectedVersion) throw new AdminError('ADMIN_TRIAL_CHANGED');
  const current = activeTrial(previous, now);
  if (c.action === 'GRANT' && current) throw new AdminError('ADMIN_TRIAL_ALREADY_ACTIVE');
  if (c.action !== 'GRANT' && !current) throw new AdminError('ADMIN_TRIAL_NOT_ACTIVE');
  if (current && c.action !== 'GRANT' && c.plan !== current.plan) throw new AdminError('ADMIN_TRIAL_CHANGED');
  const expiresAt = c.action === 'EXTEND'
    ? new Date(Date.parse(current!.expiresAt) + c.days * 86400000)
    : new Date(now.getTime() + c.days * 86400000);
  if (c.action !== 'REVOKE' && expiresAt.getTime() > now.getTime() + 90 * 86400000) {
    throw new AdminError('ADMIN_TRIAL_EXTENSION_LIMIT', 400);
  }
  return { userId: c.userId, plan: current?.plan ?? c.plan,
    startsAt: c.action === 'GRANT' ? now.toISOString() : current!.startsAt,
    expiresAt: c.action === 'REVOKE' ? current!.expiresAt : expiresAt.toISOString(),
    revokedAt: c.action === 'REVOKE' ? now.toISOString() : null,
    version: (previous?.version ?? 0) + 1 };
};
export const createMemoryTrialAccessStore = ({ now = () => new Date() }: { now?: () => Date } = {}): TrialAccessStore => {
  const rows = new Map<string, TrialAccess>();
  const audits = new Map<string, TrialAudit>();
  return {
    find: async id => rows.has(id) ? structuredClone(rows.get(id)!) : null,
    history: async () => structuredClone([...audits.values()].reverse()),
    mutate: async c => {
      const intentHash = trialIntentHash(c);
      const replay = audits.get(c.requestId);
      if (replay) {
        if (replay.intentHash !== intentHash) throw new AdminError('ADMIN_REQUEST_CONFLICT');
        return structuredClone(replay.after);
      }
      const before = rows.get(c.userId) ?? null;
      const time = now();
      const after = applyTrialCommand(before, c, time);
      rows.set(c.userId, after);
      audits.set(c.requestId, { ...c, intentHash, before, after, createdAt: time.toISOString() });
      return structuredClone(after);
    }
  };
};
export const withTrialAccess = (paid: SubscriptionStore, trials: Pick<TrialAccessStore, 'find'>,
  now: () => Date = () => new Date()): SubscriptionStore => ({
  ...paid,
  getPlan: async user => {
    const purchased = await paid.getPlan(user);
    const trial = activeTrial(await trials.find(user.id), now());
    return trial && rank[trial.plan] > rank[purchased] ? trial.plan : purchased;
  }
});
