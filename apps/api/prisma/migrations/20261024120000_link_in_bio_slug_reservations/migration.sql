-- Released Link in Bio slugs stay unavailable to other owners for 30 days.
-- Additive only: existing profiles keep their slugs and no reservation is
-- backfilled for slugs released before this migration.
CREATE TABLE "LinkInBioSlugReservation" (
    "slug" TEXT NOT NULL,
    "ownerId" TEXT,
    "releasedAt" TIMESTAMP(3) NOT NULL,
    "reservedUntil" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LinkInBioSlugReservation_pkey" PRIMARY KEY ("slug")
);

CREATE INDEX "LinkInBioSlugReservation_ownerId_releasedAt_idx" ON "LinkInBioSlugReservation"("ownerId", "releasedAt");
