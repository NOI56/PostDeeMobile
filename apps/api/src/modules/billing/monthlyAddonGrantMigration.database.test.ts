import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Grant migration tests require the dedicated loopback add-on fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl).sequential('add-on grant snapshot migration on populated historical data', () => {
  const schema = `addon_grant_migration_${randomUUID().replaceAll('-', '')}`;
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  const table = `"${schema}"."MonthlyAddonPurchase"`;
  beforeAll(async () => {
    const migration = readFileSync(new URL('../../../prisma/migrations/20261102010000_addon_grant_snapshots/migration.sql', import.meta.url), 'utf8');
    // Each migration DDL statement remains one database operation, including the
    // PL/pgSQL body. The production SQL is exercised rather than copied here.
    const statements = migration.match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;|(?:ALTER TABLE|CREATE TRIGGER)[\s\S]*?;/g) ?? [];
    expect(statements).toHaveLength(3);
    await prisma.$transaction(async transaction => {
      await transaction.$executeRawUnsafe(`CREATE SCHEMA "${schema}"`);
      await transaction.$executeRawUnsafe(`SET LOCAL search_path TO "${schema}", public`);
      await transaction.$executeRawUnsafe('CREATE TABLE "MonthlyAddonPurchase" ("id" TEXT PRIMARY KEY, "productId" TEXT NOT NULL, "revoked" BOOLEAN NOT NULL DEFAULT false, "userId" TEXT)');
      await transaction.$executeRawUnsafe(`INSERT INTO "MonthlyAddonPurchase" ("id", "productId", "revoked") VALUES ('legacy', 'postdee_post100_caption50', false), ('alias', 'historical-configured-alias', false), ('refunded', 'postdee_post100_caption50', true)`);
      for (const statement of statements) await transaction.$executeRawUnsafe(statement);
    });
  });
  afterAll(async () => {
    try { await prisma.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`); }
    finally { await prisma.$disconnect(); }
  });
  it('backfills every historical grant and preserves refunded rows and configured aliases', async () => {
    const rows = await prisma.$queryRawUnsafe<Array<{ id: string; productId: string; revoked: boolean; postUnitsGranted: number; aiCaptionsGranted: number }>>(
      `SELECT "id", "productId", "revoked", "postUnitsGranted", "aiCaptionsGranted" FROM ${table} ORDER BY "id"`);
    expect(rows).toEqual([
      { id: 'alias', productId: 'historical-configured-alias', revoked: false, postUnitsGranted: 100, aiCaptionsGranted: 50 },
      { id: 'legacy', productId: 'postdee_post100_caption50', revoked: false, postUnitsGranted: 100, aiCaptionsGranted: 50 },
      { id: 'refunded', productId: 'postdee_post100_caption50', revoked: true, postUnitsGranted: 100, aiCaptionsGranted: 50 }
    ]);
  });
  it('keeps late legacy writers at 100/50 and stores a different new-SKU grant exactly', async () => {
    await prisma.$executeRawUnsafe(`INSERT INTO ${table} ("id", "productId") VALUES ('late-legacy', 'configured-legacy-alias')`);
    await prisma.$executeRawUnsafe(`INSERT INTO ${table} ("id", "productId", "postUnitsGranted", "aiCaptionsGranted") VALUES ('small', 'postdee_post40_caption25', 40, 25)`);
    const rows = await prisma.$queryRawUnsafe<Array<{ id: string; postUnitsGranted: number; aiCaptionsGranted: number }>>(
      `SELECT "id", "postUnitsGranted", "aiCaptionsGranted" FROM ${table} WHERE "id" IN ('late-legacy', 'small') ORDER BY "id"`);
    expect(rows).toEqual([{ id: 'late-legacy', postUnitsGranted: 100, aiCaptionsGranted: 50 }, { id: 'small', postUnitsGranted: 40, aiCaptionsGranted: 25 }]);
  });
  it('rejects invalid quantities and prevents rewriting grants while permitting revocation and owner tombstones', async () => {
    await expect(prisma.$executeRawUnsafe(`INSERT INTO ${table} ("id", "productId", "postUnitsGranted", "aiCaptionsGranted") VALUES ('negative', 'bad', -1, 25)`)).rejects.toThrow();
    await expect(prisma.$executeRawUnsafe(`INSERT INTO ${table} ("id", "productId", "postUnitsGranted", "aiCaptionsGranted") VALUES ('empty', 'bad', 0, 0)`)).rejects.toThrow();
    await expect(prisma.$executeRawUnsafe(`UPDATE ${table} SET "postUnitsGranted" = 40 WHERE "id" = 'legacy'`)).rejects.toThrow();
    await expect(prisma.$executeRawUnsafe(`UPDATE ${table} SET "aiCaptionsGranted" = 25 WHERE "id" = 'alias'`)).rejects.toThrow();
    await prisma.$executeRawUnsafe(`UPDATE ${table} SET "revoked" = true, "userId" = NULL WHERE "id" = 'legacy'`);
    expect(await prisma.$queryRawUnsafe(`SELECT "revoked", "userId", "postUnitsGranted", "aiCaptionsGranted" FROM ${table} WHERE "id" = 'legacy'`))
      .toEqual([{ revoked: true, userId: null, postUnitsGranted: 100, aiCaptionsGranted: 50 }]);
  });
});
