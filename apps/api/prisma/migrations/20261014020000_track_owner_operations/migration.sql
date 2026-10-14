CREATE TABLE "ManagedOwnerOperation" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ManagedOwnerOperation_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ManagedOwnerDeletionRun" (
    "ownerId" TEXT NOT NULL,
    "runId" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ManagedOwnerDeletionRun_pkey" PRIMARY KEY ("ownerId")
);

CREATE INDEX "ManagedOwnerOperation_ownerId_idx" ON "ManagedOwnerOperation"("ownerId");
CREATE UNIQUE INDEX "ManagedOwnerDeletionRun_runId_key" ON "ManagedOwnerDeletionRun"("runId");
ALTER TABLE "ManagedOwnerOperation" ADD CONSTRAINT "ManagedOwnerOperation_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "ManagedUploadOwner"("ownerId") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ManagedOwnerDeletionRun" ADD CONSTRAINT "ManagedOwnerDeletionRun_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "ManagedUploadOwner"("ownerId") ON DELETE RESTRICT ON UPDATE CASCADE;
