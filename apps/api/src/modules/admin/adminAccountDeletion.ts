import { createHash } from 'node:crypto';
import { AdminError } from './trialAccess.js';

// Audit of operator-run account deletions (for example a request sent to the
// public deletion page by email). It outlives the deleted account, so it holds
// the Firebase UID, actor and reason only, never the member's email or name.
export type AdminAccountDeletion = { requestId: string; actorId: string; userId: string; reason: string;
  intentHash: string; status: 'PENDING' | 'COMPLETED'; lastErrorCode: string | null;
  createdAt: string; completedAt: string | null };
export type AdminAccountDeletionStart = Pick<AdminAccountDeletion, 'requestId' | 'actorId' | 'userId' | 'reason' | 'intentHash'>;
export type AdminAccountDeletionStore = {
  find: (requestId: string) => Promise<AdminAccountDeletion | null>;
  /** Inserts a PENDING record, or returns the record already stored for this request id. */
  start: (record: AdminAccountDeletionStart) => Promise<AdminAccountDeletion>;
  complete: (requestId: string) => Promise<AdminAccountDeletion>;
  fail: (requestId: string, code: string) => Promise<void>;
  history: () => Promise<AdminAccountDeletion[]>;
};

export const accountDeletionIntentHash = (c: Pick<AdminAccountDeletion, 'actorId' | 'userId' | 'reason'>) =>
  createHash('sha256').update(JSON.stringify(['account-deletion', c.actorId, c.userId, c.reason])).digest('hex');

// The record is retained after deletion, so refuse reasons that would keep an
// email address; the public deletion page promises none is kept.
export const readAccountDeletionReason = (value: unknown): string => {
  const reason = typeof value === 'string' ? value.trim() : '';
  if (reason.length < 3 || reason.length > 500 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(reason) || reason.includes('@')) {
    throw new AdminError('ADMIN_DELETION_INVALID', 400);
  }
  return reason;
};

export const createMemoryAdminAccountDeletionStore = ({ now = () => new Date() }: { now?: () => Date } = {}): AdminAccountDeletionStore => {
  const rows = new Map<string, AdminAccountDeletion>();
  const read = (requestId: string) => {
    const row = rows.get(requestId);
    if (!row) throw new AdminError('ADMIN_ACCOUNT_DELETION_UNAVAILABLE', 503);
    return row;
  };
  return {
    find: async requestId => rows.has(requestId) ? structuredClone(rows.get(requestId)!) : null,
    start: async record => {
      if (!rows.has(record.requestId)) {
        rows.set(record.requestId, { ...record, status: 'PENDING', lastErrorCode: null,
          createdAt: now().toISOString(), completedAt: null });
      }
      return structuredClone(rows.get(record.requestId)!);
    },
    complete: async requestId => {
      const row = read(requestId);
      if (row.status !== 'COMPLETED') rows.set(requestId, { ...row, status: 'COMPLETED', lastErrorCode: null, completedAt: now().toISOString() });
      return structuredClone(rows.get(requestId)!);
    },
    fail: async (requestId, code) => {
      const row = read(requestId);
      if (row.status === 'PENDING') rows.set(requestId, { ...row, lastErrorCode: code });
    },
    history: async () => structuredClone([...rows.values()].reverse())
  };
};
