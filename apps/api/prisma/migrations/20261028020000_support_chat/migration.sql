-- Member support chat. Additive only: two new tables that cascade from User,
-- so account deletion removes a member's whole conversation.
CREATE TABLE "SupportThread" (
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "lastSender" TEXT NOT NULL,
    "lastMessageId" TEXT NOT NULL,
    "lastPreview" TEXT NOT NULL,
    "lastMessageAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SupportThread_pkey" PRIMARY KEY ("userId"),
    CONSTRAINT "SupportThread_status" CHECK ("status" IN ('WAITING_TEAM', 'WAITING_MEMBER', 'CLOSED')),
    CONSTRAINT "SupportThread_lastSender" CHECK ("lastSender" IN ('MEMBER', 'TEAM'))
);

CREATE TABLE "SupportMessage" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "sender" TEXT NOT NULL,
    "authorId" TEXT,
    "body" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SupportMessage_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "SupportMessage_sender" CHECK ("sender" IN ('MEMBER', 'TEAM')),
    CONSTRAINT "SupportMessage_author" CHECK (("sender" = 'TEAM') = ("authorId" IS NOT NULL)),
    CONSTRAINT "SupportMessage_body_length" CHECK (char_length("body") BETWEEN 1 AND 1000)
);

CREATE INDEX "SupportThread_lastMessageAt_userId_idx" ON "SupportThread"("lastMessageAt", "userId");

CREATE INDEX "SupportThread_status_lastMessageAt_idx" ON "SupportThread"("status", "lastMessageAt");

CREATE INDEX "SupportMessage_userId_createdAt_id_idx" ON "SupportMessage"("userId", "createdAt", "id");

CREATE INDEX "SupportMessage_userId_sender_createdAt_idx" ON "SupportMessage"("userId", "sender", "createdAt");

ALTER TABLE "SupportThread" ADD CONSTRAINT "SupportThread_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "SupportThread"("userId") ON DELETE CASCADE ON UPDATE CASCADE;
