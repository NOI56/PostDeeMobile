-- Operator account deletions survive the deleted User row, so no foreign key.
CREATE TABLE "AdminAccountDeletion" (
    "requestId" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "intentHash" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "lastErrorCode" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "AdminAccountDeletion_pkey" PRIMARY KEY ("requestId"),
    CONSTRAINT "AdminAccountDeletion_status" CHECK ("status" IN ('PENDING', 'COMPLETED')),
    CONSTRAINT "AdminAccountDeletion_completion" CHECK (("status" = 'COMPLETED') = ("completedAt" IS NOT NULL))
);

CREATE INDEX "AdminAccountDeletion_createdAt_requestId_idx" ON "AdminAccountDeletion"("createdAt", "requestId");

CREATE INDEX "AdminAccountDeletion_userId_createdAt_idx" ON "AdminAccountDeletion"("userId", "createdAt");
