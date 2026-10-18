CREATE TABLE "AdminTrialAccess" (
  "userId" TEXT NOT NULL PRIMARY KEY,
  "plan" "SubscriptionPlan" NOT NULL,
  "startsAt" TIMESTAMP(3) NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),
  "version" INTEGER NOT NULL,
  CONSTRAINT "AdminTrialAccess_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "AdminTrialAccess_paid_plan" CHECK ("plan" IN ('STARTER','PRO')),
  CONSTRAINT "AdminTrialAccess_valid_range" CHECK ("expiresAt" > "startsAt" AND "version" > 0)
);
CREATE INDEX "AdminTrialAccess_expiresAt_revokedAt_idx" ON "AdminTrialAccess"("expiresAt", "revokedAt");
CREATE TABLE "AdminTrialAudit" (
  "requestId" TEXT NOT NULL PRIMARY KEY,
  "actorId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "plan" "SubscriptionPlan" NOT NULL,
  "days" INTEGER NOT NULL,
  "reason" TEXT NOT NULL,
  "intentHash" TEXT NOT NULL,
  "before" JSONB,
  "after" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminTrialAudit_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "AdminTrialAudit_createdAt_requestId_idx" ON "AdminTrialAudit"("createdAt", "requestId");
CREATE INDEX "AdminTrialAudit_userId_createdAt_idx" ON "AdminTrialAudit"("userId", "createdAt");
