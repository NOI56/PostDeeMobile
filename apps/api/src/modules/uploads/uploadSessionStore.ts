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
  | 'UPLOAD_SESSION_NOT_ACTIVE';

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
  beginOwnerDeletion: (ownerId: string) => Promise<UploadOwnerStatus>;
  listOpenForOwner: (ownerId: string) => Promise<UploadSession[]>;
  finishOwnerDeletion: (ownerId: string) => Promise<void>;
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
  now = () => new Date().toISOString()
}: {
  now?: () => string;
} = {}): UploadSessionStore => {
  const owners = new Map<string, UploadOwnerStatus>();
  const sessions = new Map<string, UploadSession>();

  return {
    assertOwnerActive: async (ownerId) => {
      assertOwnerActive(owners, ownerId);
    },
    createForActiveOwner: async (input) => {
      assertOwnerActive(owners, input.ownerId);

      const timestamp = now();
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
    beginOwnerDeletion: async (ownerId) => {
      const current = owners.get(ownerId);
      const status = current === 'DELETED' ? 'DELETED' : 'DELETING';
      owners.set(ownerId, status);
      return status;
    },
    listOpenForOwner: async (ownerId) =>
      [...sessions.values()].filter(
        (session) =>
          session.ownerId === ownerId &&
          (session.status === 'UPLOADING' || session.status === 'COMPLETING')
      ),
    finishOwnerDeletion: async (ownerId) => {
      owners.set(ownerId, 'DELETED');

      for (const [id, session] of sessions) {
        if (session.ownerId === ownerId) {
          sessions.delete(id);
        }
      }
    }
  };
};
