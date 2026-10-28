-- Dot, the AI support helper. Additive only: a per-thread switch (existing
-- threads keep the bot on, but nothing answers until the global switch is on),
-- a global switch row, and BOT as a third message sender.
ALTER TABLE "SupportThread" ADD COLUMN "botEnabled" BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE "SupportBotSetting" (
    "id" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL,
    "updatedBy" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SupportBotSetting_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "SupportBotSetting_single_row" CHECK ("id" = 'global')
);

-- Bot replies have no administrator author, which SupportMessage_author already allows.
ALTER TABLE "SupportMessage" DROP CONSTRAINT "SupportMessage_sender";
ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_sender" CHECK ("sender" IN ('MEMBER', 'TEAM', 'BOT'));

ALTER TABLE "SupportThread" DROP CONSTRAINT "SupportThread_lastSender";
ALTER TABLE "SupportThread" ADD CONSTRAINT "SupportThread_lastSender" CHECK ("lastSender" IN ('MEMBER', 'TEAM', 'BOT'));
