-- Customer-facing service notices from the admin console. Additive only:
-- no existing table changes, and no User relation because notices are
-- broadcast and created by administrators, not members.
CREATE TABLE "ServiceIncident" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "platforms" "Platform"[],
    "stage" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "createdBy" TEXT NOT NULL,
    "updatedBy" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "ServiceIncident_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ServiceIncident_stage" CHECK ("stage" IN ('INVESTIGATING', 'IDENTIFIED', 'MONITORING', 'RESOLVED')),
    CONSTRAINT "ServiceIncident_resolution" CHECK (("stage" = 'RESOLVED') = ("resolvedAt" IS NOT NULL)),
    CONSTRAINT "ServiceIncident_version" CHECK ("version" >= 1)
);

CREATE INDEX "ServiceIncident_startedAt_id_idx" ON "ServiceIncident"("startedAt", "id");

CREATE INDEX "ServiceIncident_resolvedAt_startedAt_idx" ON "ServiceIncident"("resolvedAt", "startedAt");
