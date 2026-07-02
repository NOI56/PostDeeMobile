CREATE TABLE "PostPeerProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "profileId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PostPeerProfile_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PostPeerProfile_userId_key" ON "PostPeerProfile"("userId");

ALTER TABLE "PostPeerProfile" ADD CONSTRAINT "PostPeerProfile_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
