-- Optional stable source-media identity allows safe retries after reupload.
ALTER TABLE "Post" ADD COLUMN "mediaContentFingerprint" TEXT;
