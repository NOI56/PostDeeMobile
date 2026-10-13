-- Existing status markers are not proof that a user recently authorized deletion.
-- Keep legacy rows NULL; authorization is recorded only after identity confirmation.
ALTER TABLE "ManagedUploadOwner" ADD COLUMN "deletionAuthorizedAt" TIMESTAMP(3);
