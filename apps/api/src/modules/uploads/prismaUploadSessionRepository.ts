import {
  UploadSessionConflictError,
  type CreateUploadSessionInput,
  type UploadOwnerStatus,
  type UploadSession,
  type UploadSessionStatus,
  type UploadSessionStore
} from './uploadSessionStore.js';

type PrismaUploadOwner = {
  ownerId: string;
  status: UploadOwnerStatus;
};

type PrismaUploadSession = {
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
  expiresAt: Date;
  operationStartedAt: Date | null;
  completedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

type UploadOwnerDelegate = {
  upsert: (args: {
    where: { ownerId: string };
    create: { ownerId: string; status: UploadOwnerStatus };
    update: Record<string, never>;
  }) => Promise<PrismaUploadOwner>;
  findUnique: (args: { where: { ownerId: string } }) => Promise<PrismaUploadOwner | null>;
  update: (args: {
    where: { ownerId: string };
    data: { status: UploadOwnerStatus };
  }) => Promise<PrismaUploadOwner>;
};

type UploadSessionDelegate = {
  create: (args: {
    data: Omit<CreateUploadSessionInput, 'expiresAt'> & {
      status: 'UPLOADING';
      expiresAt: Date;
    };
  }) => Promise<PrismaUploadSession>;
  findFirst: (args: {
    where: { id?: string; ownerId: string; videoS3Key?: string };
  }) => Promise<PrismaUploadSession | null>;
  findUnique: (args: { where: { id: string } }) => Promise<PrismaUploadSession | null>;
  findMany: (args: {
    where: {
      ownerId: string;
      status: { in: UploadSessionStatus[] };
    };
    orderBy: { createdAt: 'asc' };
  }) => Promise<PrismaUploadSession[]>;
  update: (args: {
    where: { id: string };
    data: {
      status: UploadSessionStatus;
      operationStartedAt?: Date | null;
      completedAt?: Date;
    };
  }) => Promise<PrismaUploadSession>;
  deleteMany: (args: { where: { ownerId: string } }) => Promise<{ count: number }>;
};

type PrismaUploadSessionTransaction = {
  managedUploadOwner: UploadOwnerDelegate;
  managedUploadSession: UploadSessionDelegate;
};

export type PrismaUploadSessionClient = PrismaUploadSessionTransaction & {
  $transaction: <T>(
    action: (transaction: PrismaUploadSessionTransaction) => Promise<T>,
    options: {
      isolationLevel: 'Serializable';
      maxWait: number;
      timeout: number;
    }
  ) => Promise<T>;
};

const mapSession = (session: PrismaUploadSession): UploadSession => ({
  id: session.id,
  ownerId: session.ownerId,
  storageUploadId: session.storageUploadId,
  videoS3Key: session.videoS3Key,
  fileName: session.fileName,
  contentType: session.contentType,
  sizeBytes: session.sizeBytes,
  partSizeBytes: session.partSizeBytes,
  partCount: session.partCount,
  status: session.status,
  expiresAt: session.expiresAt.toISOString(),
  operationStartedAt: session.operationStartedAt?.toISOString(),
  completedAt: session.completedAt?.toISOString(),
  createdAt: session.createdAt.toISOString(),
  updatedAt: session.updatedAt.toISOString()
});

const readErrorCode = (error: unknown) =>
  typeof error === 'object' &&
  error !== null &&
  'code' in error &&
  typeof error.code === 'string'
    ? error.code
    : undefined;

const runSerializable = async <T>(
  prisma: PrismaUploadSessionClient,
  action: (transaction: PrismaUploadSessionTransaction) => Promise<T>
) => {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await prisma.$transaction(action, {
        isolationLevel: 'Serializable',
        maxWait: 5_000,
        timeout: 10_000
      });
    } catch (error) {
      if (readErrorCode(error) !== 'P2034' || attempt === 2) {
        throw error;
      }
    }
  }

  throw new Error('Serializable upload transaction retry was exhausted');
};

const assertOwnerActive = (owner: PrismaUploadOwner | null) => {
  if (owner?.status !== 'ACTIVE') {
    throw new UploadSessionConflictError(
      'ACCOUNT_DELETION_IN_PROGRESS',
      'Account deletion is in progress. New uploads are disabled.'
    );
  }
};

const sessionNotActive = () =>
  new UploadSessionConflictError(
    'UPLOAD_SESSION_NOT_ACTIVE',
    'Upload session is no longer active.'
  );

const completionInProgress = () =>
  new UploadSessionConflictError(
    'UPLOAD_COMPLETION_IN_PROGRESS',
    'Upload completion is still in progress.'
  );

const assertNotExpired = (session: PrismaUploadSession, now: string) => {
  if (session.expiresAt.getTime() <= Date.parse(now)) {
    throw new UploadSessionConflictError(
      'UPLOAD_SESSION_EXPIRED',
      'Upload session has expired.'
    );
  }
};

export const createPrismaUploadSessionRepository = ({
  prisma
}: {
  prisma: PrismaUploadSessionClient;
}): UploadSessionStore => ({
  assertOwnerActive: async (ownerId) => {
    const owner = await prisma.managedUploadOwner.findUnique({ where: { ownerId } });

    if (owner) {
      assertOwnerActive(owner);
    }
  },
  createForActiveOwner: (input) =>
    runSerializable(prisma, async (transaction) => {
      const owner = await transaction.managedUploadOwner.upsert({
        where: { ownerId: input.ownerId },
        create: { ownerId: input.ownerId, status: 'ACTIVE' },
        update: {}
      });
      assertOwnerActive(owner);

      return mapSession(
        await transaction.managedUploadSession.create({
          data: {
            ...input,
            expiresAt: new Date(input.expiresAt),
            status: 'UPLOADING'
          }
        })
      );
    }),
  getForOwner: async (id, ownerId) => {
    const session = await prisma.managedUploadSession.findFirst({
      where: { id, ownerId }
    });
    return session ? mapSession(session) : undefined;
  },
  findForOwnerKey: async (ownerId, videoS3Key) => {
    const session = await prisma.managedUploadSession.findFirst({
      where: { ownerId, videoS3Key }
    });
    return session ? mapSession(session) : undefined;
  },
  getUploadableForOwner: ({ id, ownerId, now }) =>
    runSerializable(prisma, async (transaction) => {
      assertOwnerActive(
        await transaction.managedUploadOwner.findUnique({ where: { ownerId } })
      );
      const session = await transaction.managedUploadSession.findFirst({
        where: { id, ownerId }
      });

      if (!session || session.status !== 'UPLOADING') {
        throw sessionNotActive();
      }

      assertNotExpired(session, now);
      return mapSession(session);
    }),
  beginCompletion: ({ id, ownerId, now }) =>
    runSerializable(prisma, async (transaction) => {
      assertOwnerActive(
        await transaction.managedUploadOwner.findUnique({ where: { ownerId } })
      );
      const session = await transaction.managedUploadSession.findFirst({
        where: { id, ownerId }
      });

      if (!session) {
        throw sessionNotActive();
      }

      if (session.status === 'COMPLETED') {
        return mapSession(session);
      }

      assertNotExpired(session, now);

      if (session.status === 'COMPLETING') {
        throw completionInProgress();
      }

      if (session.status !== 'UPLOADING') {
        throw sessionNotActive();
      }

      return mapSession(
        await transaction.managedUploadSession.update({
          where: { id },
          data: {
            status: 'COMPLETING',
            operationStartedAt: new Date(now)
          }
        })
      );
    }),
  beginAbort: (id, ownerId) =>
    runSerializable(prisma, async (transaction) => {
      assertOwnerActive(
        await transaction.managedUploadOwner.findUnique({ where: { ownerId } })
      );
      const session = await transaction.managedUploadSession.findFirst({
        where: { id, ownerId }
      });

      if (!session) {
        throw sessionNotActive();
      }

      if (session.status === 'COMPLETING') {
        throw completionInProgress();
      }

      if (session.status === 'COMPLETED') {
        throw sessionNotActive();
      }

      if (session.status === 'ABORTED') {
        return mapSession(session);
      }

      return mapSession(
        await transaction.managedUploadSession.update({
          where: { id },
          data: { status: 'ABORTED', operationStartedAt: null }
        })
      );
    }),
  markCompleted: (id, completedAt) =>
    runSerializable(prisma, async (transaction) => {
      const session = await transaction.managedUploadSession.findUnique({ where: { id } });

      if (!session) {
        throw sessionNotActive();
      }

      if (session.status === 'COMPLETED') {
        return mapSession(session);
      }

      if (session.status !== 'COMPLETING') {
        throw sessionNotActive();
      }

      return mapSession(
        await transaction.managedUploadSession.update({
          where: { id },
          data: {
            status: 'COMPLETED',
            operationStartedAt: null,
            completedAt: new Date(completedAt)
          }
        })
      );
    }),
  markAborted: (id) =>
    runSerializable(prisma, async (transaction) => {
      const session = await transaction.managedUploadSession.findUnique({ where: { id } });

      if (!session) {
        return undefined;
      }

      if (session.status === 'ABORTED' || session.status === 'COMPLETED') {
        return mapSession(session);
      }

      return mapSession(
        await transaction.managedUploadSession.update({
          where: { id },
          data: { status: 'ABORTED', operationStartedAt: null }
        })
      );
    }),
  beginOwnerDeletion: (ownerId) =>
    runSerializable(prisma, async (transaction) => {
      const owner = await transaction.managedUploadOwner.upsert({
        where: { ownerId },
        create: { ownerId, status: 'DELETING' },
        update: {}
      });

      if (owner.status === 'DELETED') {
        return 'DELETED';
      }

      if (owner.status === 'DELETING') {
        return 'DELETING';
      }

      return (
        await transaction.managedUploadOwner.update({
          where: { ownerId },
          data: { status: 'DELETING' }
        })
      ).status;
    }),
  listOpenForOwner: async (ownerId) =>
    (
      await prisma.managedUploadSession.findMany({
        where: {
          ownerId,
          status: { in: ['UPLOADING', 'COMPLETING'] }
        },
        orderBy: { createdAt: 'asc' }
      })
    ).map(mapSession),
  finishOwnerDeletion: (ownerId) =>
    runSerializable(prisma, async (transaction) => {
      await transaction.managedUploadSession.deleteMany({ where: { ownerId } });
      const owner = await transaction.managedUploadOwner.upsert({
        where: { ownerId },
        create: { ownerId, status: 'DELETED' },
        update: {}
      });

      if (owner.status !== 'DELETED') {
        await transaction.managedUploadOwner.update({
          where: { ownerId },
          data: { status: 'DELETED' }
        });
      }
    })
});
