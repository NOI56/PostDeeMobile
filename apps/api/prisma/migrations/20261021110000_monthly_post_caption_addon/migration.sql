CREATE TABLE "MonthlyAddonPurchase" (
  "id" TEXT NOT NULL,
  "userId" TEXT,
  "ownerHash" TEXT NOT NULL,
  "productId" TEXT NOT NULL,
  "store" TEXT NOT NULL,
  "environment" TEXT NOT NULL,
  "transactionId" TEXT NOT NULL,
  "purchasedAt" TIMESTAMP(3) NOT NULL,
  "revoked" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MonthlyAddonPurchase_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "MonthlyAddonPurchase_store_environment_transactionId_key" ON "MonthlyAddonPurchase"("store", "environment", "transactionId");
CREATE INDEX "MonthlyAddonPurchase_userId_revoked_purchasedAt_idx" ON "MonthlyAddonPurchase"("userId", "revoked", "purchasedAt");
ALTER TABLE "MonthlyAddonPurchase" ADD CONSTRAINT "MonthlyAddonPurchase_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
