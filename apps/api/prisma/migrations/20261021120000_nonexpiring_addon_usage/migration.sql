-- The add-on store remains gated until configured and verified. Existing
-- included-quota records keep zero purchased-credit allocation.
ALTER TABLE "Post" ADD COLUMN "addonPostUnits" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Post" ADD CONSTRAINT "Post_addonPostUnits_bounds"
  CHECK ("addonPostUnits" >= 0 AND "addonPostUnits" <= cardinality("selectedPlatforms"));
ALTER TABLE "RealClipCaptionUsage" ADD COLUMN "usesAddonCredit" BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX "Post_userId_addonPostUnits_idx" ON "Post"("userId", "addonPostUnits");
CREATE INDEX "RealClipCaptionUsage_userId_usesAddonCredit_idx" ON "RealClipCaptionUsage"("userId", "usesAddonCredit");
