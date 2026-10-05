-- Nullable appearance preserves existing profiles and supports older clients.
ALTER TABLE "LinkInBioProfile" ADD COLUMN "appearance" JSONB;

CREATE TABLE "LinkInBioImage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "slot" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "LinkInBioImage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "LinkInBioImage_storageKey_key" ON "LinkInBioImage"("storageKey");
CREATE INDEX "LinkInBioImage_userId_createdAt_idx" ON "LinkInBioImage"("userId", "createdAt");
ALTER TABLE "LinkInBioImage" ADD CONSTRAINT "LinkInBioImage_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
