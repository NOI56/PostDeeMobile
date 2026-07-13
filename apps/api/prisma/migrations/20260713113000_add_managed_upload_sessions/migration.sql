CREATE TYPE "ManagedUploadOwnerStatus" AS ENUM ('ACTIVE', 'DELETING', 'DELETED');

CREATE TYPE "ManagedUploadSessionStatus" AS ENUM ('UPLOADING', 'COMPLETING', 'COMPLETED', 'ABORTED');

CREATE TABLE "ManagedUploadOwner" (
    "ownerId" TEXT NOT NULL,
    "status" "ManagedUploadOwnerStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ManagedUploadOwner_pkey" PRIMARY KEY ("ownerId")
);

CREATE TABLE "ManagedUploadSession" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "storageUploadId" TEXT NOT NULL,
    "videoS3Key" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "partSizeBytes" INTEGER NOT NULL,
    "partCount" INTEGER NOT NULL,
    "status" "ManagedUploadSessionStatus" NOT NULL DEFAULT 'UPLOADING',
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "operationStartedAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ManagedUploadSession_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ManagedUploadSession_storageUploadId_key" ON "ManagedUploadSession"("storageUploadId");
CREATE UNIQUE INDEX "ManagedUploadSession_videoS3Key_key" ON "ManagedUploadSession"("videoS3Key");
CREATE INDEX "ManagedUploadSession_ownerId_status_idx" ON "ManagedUploadSession"("ownerId", "status");
CREATE INDEX "ManagedUploadSession_expiresAt_status_idx" ON "ManagedUploadSession"("expiresAt", "status");

ALTER TABLE "ManagedUploadSession"
ADD CONSTRAINT "ManagedUploadSession_ownerId_fkey"
FOREIGN KEY ("ownerId") REFERENCES "ManagedUploadOwner"("ownerId")
ON DELETE CASCADE ON UPDATE CASCADE;
