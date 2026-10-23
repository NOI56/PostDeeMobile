-- Read-only preflight for 20261023010000_bind_social_connect_attempts.
-- Run against each target database before deploying the migration. Both result
-- sets must be empty. Review duplicates with the affected owners and PostPeer;
-- do not delete or reassign connections automatically.
BEGIN TRANSACTION READ ONLY;

SELECT "platform", "externalAccountId", COUNT(*) AS "connectionCount",
       COUNT(DISTINCT "userId") AS "ownerCount", ARRAY_AGG("id") AS "connectionIds"
FROM "SocialConnection"
WHERE "externalAccountId" IS NOT NULL
GROUP BY "platform", "externalAccountId"
HAVING COUNT(*) > 1;

-- Includes same-owner/cross-platform duplicates, since provider integration IDs
-- identify one integration globally rather than one integration per platform.
SELECT "postPeerAccountId", COUNT(*) AS "connectionCount",
       COUNT(DISTINCT "userId") AS "ownerCount", ARRAY_AGG("id") AS "connectionIds"
FROM "SocialConnection"
GROUP BY "postPeerAccountId"
HAVING COUNT(*) > 1;

COMMIT;
