-- Existing images may still be referenced by offline local drafts.
ALTER TABLE "LinkInBioImage"
ADD COLUMN "draftReferences" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN "legacyRetention" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN "deletionClaimed" BOOLEAN NOT NULL DEFAULT false;
