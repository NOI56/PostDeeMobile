-- Nullable cursor fields keep existing users valid while making RevenueCat
-- webhook ordering and retry detection durable.
ALTER TABLE "User"
ADD COLUMN "lastRevenueCatEventTimestampMs" BIGINT,
ADD COLUMN "lastRevenueCatEventId" TEXT;
