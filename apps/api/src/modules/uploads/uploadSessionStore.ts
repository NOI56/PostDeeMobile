import { randomUUID } from 'node:crypto';
import { createOwnerOperationQueue, OwnerOperationBusyError, type RunWithActiveOwner } from '../account/ownerOperationQueue.js';
import { createOwnerOperationRunner } from '../account/prismaOwnerOperationCoordinator.js';

export type UploadOwnerStatus = 'ACTIVE' | 'DELETING' | 'DELETED';

export type UploadSessionStatus =
  | 'UPLOADING'
  | 'COMPLETING'
  | 'COMPLETED'
  | 'ABORTED';

export type UploadSession = {
  id: string;
  ownerId: string;
  storageUploadId: string;
  videoS3Key: string;
  fileName: string;
  contentType: string;
  sizeBytes: number;
  partSizeBytes: number;
  partCount: number;
  status: UploadSessionStatus;
  expiresAt: string;
  operationStartedAt?: string;
  completedAt?: string;
  createdAt: string;
  updatedAt: string;
};
export type CreateUploadSessionInput = Omit<
  UploadSession,
  'status' | 'operationStartedAt' | 'completedAt' | 'createdAt' | 'updatedAt'
>;

export type UploadSessionConflictCode =
  | 'ACCOUNT_DELETION_IN_PROGRESS'
  | 'UPLOAD_COMPLETION_IN_PROGRESS'
  | 'UPLOAD_SESSION_EXPIRED'
  | 'UPLOAD_SESSION_LIMIT_REACHED'
  | 'UPLOAD_SESSION_NOT_ACTIVE';

// Unexpired UPLOADING sessions one owner may hold at once. The app uploads one
// video plus a few frames per post, so this only stops abandoned-session floods.
export const maxOpenUploadSessionsPerOwner = 10;

export const uploadSessionLimitError = () =>
  new UploadSessionConflictError(
    'UPLOAD_SESSION_LIMIT_REACHED',
    'Too many uploads are in progress. Finish or wait for them to expire, then try again.'
  );

export class UploadSessionConflictError extends Error {
  constructor(
    readonly code: UploadSessionConflictCode,
    message: string
  ) {
    super(message);
    this.name = 'UploadSessionConflictError';
  }
}

export type UploadSessionStore = {
  assertOwnerActive: (ownerId: string) => Promise<void>;
  runWithActiveOwner: RunWithActiveOwner;
  runWithOwnerLifetime: RunWithActiveOwner;
  acquireOwnerDeletion: (ownerId: string) => Promise<() => Promise<void>>;
  createForActiveOwner: (input: CreateUploadSessionInput) => Promise<UploadSession>;
  getForOwner: (id: string, ownerId: string) => Promise<UploadSession | undefined>;
  findForOwnerKey: (
    ownerId: string,
    videoS3Key: string
  ) => Promise<UploadSession | undefined>;
  getUploadableForOwner: (input: {
    id: string;
    ownerId: string;
    now: string;
  }) => Promise<UploadSession>;
  beginCompletion: (input: {
    id: string;
    ownerId: string;
    now: string;
  }) => Promise<UploadSession>;
  beginAbort: (id: string, ownerId: string) => Promise<UploadSession>;
  markCompleted: (id: string, completedAt: string) => Promise<UploadSession>;
  markAborted: (id: string) => Promise<UploadSession | undefined>;
  getOwnerDeletionAuthorization: (ownerId: string) => Promise<string | undefined>;
  // Called only after confirming a recent Firebase identity, never from a status marker.
  authorizeOwnerDeletion: (ownerId: string, authorizedAt: string) => Promise<void>;
  beginOwnerDeletion: (ownerId: string) => Promise<UploadOwnerStatus>;
  listOpenForOwner: (ownerId: string) => Promise<UploadSession[]>;
  finishOwnerDeletion: (ownerId: string) => Promise<void>;
  // Maintenance only: UPLOADING sessions of any owner that expired at or before
  // `expiredBefore`, oldest first, at most `limit`.
  listExpiredUploading: (input: { expiredBefore: string; limit: number }) => Promise<UploadSession[]>;
  // Compare-and-set UPLOADING -> ABORTED while the session is still expired.
  // Returns false when another path already moved it.
  retireExpired: (input: { id: string; expiredBefore: string }) => Promise<boolean>;
};

const accountDeletingError = () =>
  new UploadSessionConflictError(
    'ACCOUNT_DELETION_IN_PROGRESS',
    'Account deletion is in progress. New uploads are disabled.'
  );

const sessionNotActiveError = () =>
  new UploadSessionConflictError(
    'UPLOAD_SESSION_NOT_ACTIVE',
    'Upload session is no longer active.'
  );

const completionInProgressError = () =>
  new UploadSessionConflictError(
    'UPLOAD_COMPLETION_IN_PROGRESS',
    'Upload completion is still in progress.'
  );

const assertOwnerActive = (
  owners: Map<string, UploadOwnerStatus>,
  ownerId: string
) => {
  const status = owners.get(ownerId) ?? 'ACTIVE';

  if (status !== 'ACTIVE') {
    throw accountDeletingError();
  }

  owners.set(ownerId, status);
};

const assertNotExpired = (session: UploadSession, now: string) => {
  if (Date.parse(session.expiresAt) <= Date.parse(now)) {
    throw new UploadSessionConflictError(
      'UPLOAD_SESSION_EXPIRED',
      'Upload session has expired.'
    );
  }
};

export const createInMemoryUploadSessionStore = ({
  now = () => new Date().toISOString(), ownerOperationOptions
}: {
  now?: () => string;
  ownerOperationOptions?: { maxWaitMs?: number; pollIntervalMs?: number };
} = {}): UploadSessionStore => {
  const owners = new Map<string, UploadOwnerStatus>();
  const deletionAuthorizations = new Map<string, string>();
  const sessions = new Map<string, UploadSession>();
  const maxWaitMs = ownerOperationOptions?.maxWaitMs ?? 5000;
  const pollIntervalMs = ownerOperationOptions?.pollIntervalMs ?? 25;
  if (!Number.isFinite(maxWaitMs) || maxWaitMs < 0 || !Number.isFinite(pollIntervalMs) || pollIntervalMs <= 0) throw new Error('Invalid owner operation drain limits');
  const runOwnerOperation = createOwnerOperationQueue({ maxWaitMs });
  const operations = new Map<string, string>();
  const deletionRuns = new Map<string, string>();
  const assertDrained = (ownerId: string) => {
    if ([...operations.values()].some((owner) => owner === ownerId)) throw new OwnerOperationBusyError();
  };
  const lifetime = {
    admit: async (ownerId) => {
      assertOwnerActive(owners, ownerId);
      const id = randomUUID(); operations.set(id, ownerId); return id;
    },
    release: async (ownerId, id) => { if (operations.get(id) === ownerId) operations.delete(id); }
  } satisfies Pick<Parameters<typeof createOwnerOperationRunner>[0], 'admit' | 'release'>;
  const runWithActiveOwner = createOwnerOperationRunner({ ...lifetime, runOwnerOperation });
  const runWithOwnerLifetime = createOwnerOperationRunner({
    ...lifetime, runOwnerOperation: async (_ownerId, operation) => operation()
  });

  return {
    runWithActiveOwner,
    runWithOwnerLifetime,
    acquireOwnerDeletion: async (ownerId) => {
      const deadline = Date.now() + maxWaitMs;
      for (;;) {
        try {
          if (!owners.has(ownerId) || owners.get(ownerId) === 'ACTIVE' || deletionRuns.has(ownerId)) throw new OwnerOperationBusyError();
          assertDrained(ownerId);
          const runId = randomUUID(); deletionRuns.set(ownerId, runId);
          return async () => { if (deletionRuns.get(ownerId) === runId) deletionRuns.delete(ownerId); };
        } catch (error) {
          if (!(error instanceof OwnerOperationBusyError) || Date.now() >= deadline) throw error;
          await new Promise((resolve) => setTimeout(resolve, Math.min(pollIntervalMs, Math.max(1, deadline - Date.now()))));
        }
      }
    },
    assertOwnerActive: async (ownerId) => {
      assertOwnerActive(owners, ownerId);
    },
    createForActiveOwner: async (input) => {
      assertOwnerActive(owners, input.ownerId);

      const timestamp = now();
      const openSessions = [...sessions.values()].filter((session) =>
        session.ownerId === input.ownerId &&
        session.status === 'UPLOADING' &&
        Date.parse(session.expiresAt) > Date.parse(timestamp)
      );
      if (openSessions.length >= maxOpenUploadSessionsPerOwner) {
        throw uploadSessionLimitError();
      }
      const session: UploadSession = {
        ...input,
        status: 'UPLOADING',
        createdAt: timestamp,
        updatedAt: timestamp
      };

      sessions.set(session.id, session);
      return session;
    },
    getForOwner: async (id, ownerId) => {
      const session = sessions.get(id);
      return session?.ownerId === ownerId ? session : undefined;
    },
    findForOwnerKey: async (ownerId, videoS3Key) =>
      [...sessions.values()].find(
        (session) =>
          session.ownerId === ownerId && session.videoS3Key === videoS3Key
      ),
    getUploadableForOwner: async ({ id, ownerId, now: currentTime }) => {
      assertOwnerActive(owners, ownerId);
      const session = sessions.get(id);

      if (!session || session.ownerId !== ownerId) {
        throw sessionNotActiveError();
      }

      assertNotExpired(session, currentTime);

      if (session.status !== 'UPLOADING') {
        throw sessionNotActiveError();
      }

      return session;
    },
    beginCompletion: async ({ id, ownerId, now: currentTime }) => {
      assertOwnerActive(owners, ownerId);
      const session = sessions.get(id);

      if (!session || session.ownerId !== ownerId) {
        throw sessionNotActiveError();
      }

      if (session.status === 'COMPLETED') {
        return session;
      }

      assertNotExpired(session, currentTime);

      if (session.status === 'COMPLETING') {
        throw completionInProgressError();
      }

      if (session.status !== 'UPLOADING') {
        throw sessionNotActiveError();
      }

      const updated = {
        ...session,
        status: 'COMPLETING' as const,
        operationStartedAt: session.operationStartedAt ?? currentTime,
        updatedAt: currentTime
      };
      sessions.set(id, updated);
      return updated;
    },
    beginAbort: async (id, ownerId) => {
      assertOwnerActive(owners, ownerId);
      const session = sessions.get(id);

      if (!session || session.ownerId !== ownerId) {
        throw sessionNotActiveError();
      }

      if (session.status === 'COMPLETING') {
        throw completionInProgressError();
      }

      if (session.status === 'COMPLETED') {
        throw sessionNotActiveError();
      }

      if (session.status === 'ABORTED') {
        return session;
      }

      const timestamp = now();
      const updated = {
        ...session,
        status: 'ABORTED' as const,
        operationStartedAt: undefined,
        updatedAt: timestamp
      };
      sessions.set(id, updated);
      return updated;
    },
    markCompleted: async (id, completedAt) => {
      const session = sessions.get(id);

      if (!session) {
        throw sessionNotActiveError();
      }

      if (session.status === 'COMPLETED') {
        return session;
      }

      if (session.status !== 'COMPLETING') {
        throw sessionNotActiveError();
      }

      const updated = {
        ...session,
        status: 'COMPLETED' as const,
        operationStartedAt: undefined,
        completedAt,
        updatedAt: completedAt
      };
      sessions.set(id, updated);
      return updated;
    },
    markAborted: async (id) => {
      const session = sessions.get(id);

      if (!session) {
        return undefined;
      }

      if (session.status === 'ABORTED') {
        return session;
      }

      if (session.status === 'COMPLETED') {
        return session;
      }

      const timestamp = now();
      const updated = {
        ...session,
        status: 'ABORTED' as const,
        operationStartedAt: undefined,
        updatedAt: timestamp
      };
      sessions.set(id, updated);
      return updated;
    },
    getOwnerDeletionAuthorization: async (ownerId) => {
      const status = owners.get(ownerId);
      const authorizedAt = deletionAuthorizations.get(ownerId);
      if ((status !== 'DELETING' && status !== 'DELETED') || !authorizedAt) {
        return undefined;
      }
      const timestamp = new Date(authorizedAt);
      return Number.isFinite(timestamp.getTime()) ? timestamp.toISOString() : undefined;
    },
    authorizeOwnerDeletion: async (ownerId, authorizedAt) => {
      const timestamp = new Date(authorizedAt);
      if (!Number.isFinite(timestamp.getTime())) {
        throw new Error('Invalid account deletion authorization timestamp.');
      }
      await runOwnerOperation(ownerId, async () => {
        owners.set(ownerId, owners.get(ownerId) === 'DELETED' ? 'DELETED' : 'DELETING');
        if (!deletionAuthorizations.has(ownerId)) {
          deletionAuthorizations.set(ownerId, timestamp.toISOString());
        }
      });
    },
    beginOwnerDeletion: (ownerId) => runOwnerOperation(ownerId, async () => {
      const current = owners.get(ownerId);
      const status = current === 'DELETED' ? 'DELETED' : 'DELETING';
      owners.set(ownerId, status);
      return status;
    }),
    listOpenForOwner: async (ownerId) =>
      [...sessions.values()].filter(
        (session) =>
          session.ownerId === ownerId &&
          (session.status === 'UPLOADING' || session.status === 'COMPLETING')
      ),
    finishOwnerDeletion: (ownerId) => runOwnerOperation(ownerId, async () => {
      if (!owners.has(ownerId) || owners.get(ownerId) === 'ACTIVE') throw new OwnerOperationBusyError();
      assertDrained(ownerId);
      owners.set(ownerId, 'DELETED');

      for (const [id, session] of sessions) {
        if (session.ownerId === ownerId) {
          sessions.delete(id);
        }
      }
    }),
    listExpiredUploading: async ({ expiredBefore, limit }) =>
      [...sessions.values()]
        .filter(
          (session) =>
            session.status === 'UPLOADING' &&
            Date.parse(session.expiresAt) <= Date.parse(expiredBefore)
        )
        .sort((left, right) => Date.parse(left.expiresAt) - Date.parse(right.expiresAt))
        .slice(0, limit),
    retireExpired: async ({ id, expiredBefore }) => {
      const session = sessions.get(id);

      if (
        session?.status !== 'UPLOADING' ||
        Date.parse(session.expiresAt) > Date.parse(expiredBefore)
      ) {
        return false;
      }

      sessions.set(id, {
        ...session,
        status: 'ABORTED',
        operationStartedAt: undefined,
        updatedAt: now()
      });
      return true;
    }
  };
};
