-- CreateTable
CREATE TABLE "RealClipCaptionUsage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "monthKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RealClipCaptionUsage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "RealClipCaptionUsage_userId_monthKey_idx" ON "RealClipCaptionUsage"("userId", "monthKey");

-- CreateIndex
CREATE INDEX "RealClipCaptionUsage_createdAt_idx" ON "RealClipCaptionUsage"("createdAt");

-- AddForeignKey
ALTER TABLE "RealClipCaptionUsage" ADD CONSTRAINT "RealClipCaptionUsage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
