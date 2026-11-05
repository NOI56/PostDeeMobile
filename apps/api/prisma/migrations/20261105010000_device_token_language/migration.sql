-- Nullable so existing tokens retain their legacy Thai push language.
ALTER TABLE "DeviceToken" ADD COLUMN "language" TEXT;
