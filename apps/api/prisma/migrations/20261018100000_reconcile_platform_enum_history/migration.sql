-- These values already exist in schema.prisma on the canonical baseline.
-- Reconcile migration-only databases; IF NOT EXISTS also tolerates databases
-- previously synchronized with the schema. This does not enable publishers.
ALTER TYPE "Platform" ADD VALUE IF NOT EXISTS 'SHOPEE_VIDEO';
ALTER TYPE "Platform" ADD VALUE IF NOT EXISTS 'LAZADA_VIDEO';
