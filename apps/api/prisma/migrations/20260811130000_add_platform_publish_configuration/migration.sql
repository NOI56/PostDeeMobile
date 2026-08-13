CREATE TYPE "DeliveryOutcome" AS ENUM ('LIVE', 'PRIVATE', 'UNLISTED', 'DRAFT');

ALTER TABLE "Post"
ADD COLUMN "platformSettings" JSONB,
ADD COLUMN "platformTargets" JSONB;

ALTER TABLE "PlatformPublish"
ADD COLUMN "deliveryOutcome" "DeliveryOutcome",
ADD COLUMN "providerPostId" TEXT;
