-- Never resolve ownership conflicts by deleting or moving user data. The owner
-- must run social-linking-preflight.sql and resolve any duplicates first.
BEGIN;
LOCK TABLE "SocialConnection" IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM "SocialConnection" WHERE "externalAccountId" IS NOT NULL
    GROUP BY "platform", "externalAccountId" HAVING COUNT(*) > 1
  ) OR EXISTS (
    SELECT 1 FROM "SocialConnection"
    GROUP BY "postPeerAccountId" HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Social account duplicates exist. Run social-linking-preflight.sql and resolve ownership before deploying; no connections were changed.'
      USING ERRCODE = '23505';
  END IF;
END $$;

CREATE UNIQUE INDEX "SocialConnection_platform_externalAccountId_key" ON "SocialConnection"("platform", "externalAccountId");
CREATE UNIQUE INDEX "SocialConnection_postPeerAccountId_key" ON "SocialConnection"("postPeerAccountId");

CREATE TABLE "SocialConnectAttempt" (
  "userId" TEXT NOT NULL,
  "platform" "Platform" NOT NULL,
  "profileId" TEXT NOT NULL,
  "nonceHash" TEXT NOT NULL,
  "baselineIntegrationIds" TEXT[] NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SocialConnectAttempt_pkey" PRIMARY KEY ("userId", "platform")
);
CREATE UNIQUE INDEX "SocialConnectAttempt_nonceHash_key" ON "SocialConnectAttempt"("nonceHash");
ALTER TABLE "SocialConnectAttempt" ADD CONSTRAINT "SocialConnectAttempt_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;
