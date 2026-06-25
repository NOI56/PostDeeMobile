-- CreateTable
CREATE TABLE "AiEditUsage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "monthKey" TEXT NOT NULL,
    "minutes" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AiEditUsage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AiEditUsage_userId_monthKey_idx" ON "AiEditUsage"("userId", "monthKey");

-- AddForeignKey
ALTER TABLE "AiEditUsage" ADD CONSTRAINT "AiEditUsage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
