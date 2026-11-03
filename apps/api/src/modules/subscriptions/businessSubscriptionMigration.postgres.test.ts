import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PrismaClient } from '@prisma/client';
import { afterAll, describe, expect, it } from 'vitest';

const databaseUrl = process.env.POSTDEE_TEST_DATABASE_URL;
if (databaseUrl) {
  const url = new URL(databaseUrl);
  if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55441' || url.pathname !== '/postdee_addon_test') {
    throw new Error('Business migration tests require the dedicated loopback fixture on port 55441');
  }
}

describe.skipIf(!databaseUrl)('Business enum migration on populated PostgreSQL tables', () => {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl ?? 'postgresql://unused@127.0.0.1:55441/postdee_addon_test' } } });
  // This random schema belongs only to this test, inside the guarded throwaway DB.
  const schema = `business_migration_${randomUUID().replaceAll('-', '')}`;
  afterAll(async () => {
    await prisma.$executeRawUnsafe(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await prisma.$disconnect();
  });

  it('preserves existing subscription/trial values, then accepts Business after the migration commits', async () => {
    await prisma.$executeRawUnsafe(`CREATE SCHEMA "${schema}"`);
    await prisma.$executeRawUnsafe(`CREATE TYPE "${schema}"."SubscriptionPlan" AS ENUM ('BASIC', 'STARTER', 'PRO')`);
    await prisma.$executeRawUnsafe(`CREATE TABLE "${schema}"."Subscription" (id text PRIMARY KEY, plan "${schema}"."SubscriptionPlan" NOT NULL, status text NOT NULL)`);
    await prisma.$executeRawUnsafe(`CREATE TABLE "${schema}"."AdminTrialAccess" (id text PRIMARY KEY, plan "${schema}"."SubscriptionPlan" NOT NULL, CONSTRAINT "AdminTrialAccess_paid_plan" CHECK (plan IN ('STARTER','PRO')))`);
    await prisma.$executeRawUnsafe(`INSERT INTO "${schema}"."Subscription" VALUES ('basic','BASIC','ACTIVE'), ('starter','STARTER','ACTIVE'), ('pro','PRO','ACTIVE'), ('expired','PRO','CANCELED')`);
    await prisma.$executeRawUnsafe(`INSERT INTO "${schema}"."AdminTrialAccess" VALUES ('existing-trial','PRO')`);
    const readSubscriptions = () => prisma.$queryRawUnsafe(`SELECT id, plan::text, status FROM "${schema}"."Subscription" ORDER BY id`);
    const before = await readSubscriptions();
    const migration = await readFile(new URL('../../../prisma/migrations/20261102020000_business_subscription_plan/migration.sql', import.meta.url), 'utf8');

    await prisma.$transaction(async tx => {
      await tx.$executeRawUnsafe(`SET LOCAL search_path TO "${schema}"`);
      const statements = migration.match(/ALTER TYPE[\s\S]*?;|ALTER TABLE[\s\S]*?;/g) ?? [];
      expect(statements.length).toBeGreaterThan(1);
      for (const statement of statements) await tx.$executeRawUnsafe(statement);
    });

    expect(await readSubscriptions()).toEqual(before);
    expect(await prisma.$queryRawUnsafe(`SELECT id, plan::text FROM "${schema}"."AdminTrialAccess"`))
      .toEqual([{ id: 'existing-trial', plan: 'PRO' }]);
    await prisma.$executeRawUnsafe(`INSERT INTO "${schema}"."Subscription" VALUES ('business','BUSINESS','ACTIVE')`);
    await prisma.$executeRawUnsafe(`INSERT INTO "${schema}"."AdminTrialAccess" VALUES ('business-trial','BUSINESS')`);
    await prisma.$executeRawUnsafe(`UPDATE "${schema}"."Subscription" SET plan='STARTER' WHERE id='business'`);
    expect(await prisma.$queryRawUnsafe(`SELECT id, plan::text, status FROM "${schema}"."Subscription" WHERE id='business'`))
      .toEqual([{ id: 'business', plan: 'STARTER', status: 'ACTIVE' }]);
    expect(await prisma.$queryRawUnsafe(`SELECT id, plan::text FROM "${schema}"."AdminTrialAccess" WHERE id='business-trial'`))
      .toEqual([{ id: 'business-trial', plan: 'BUSINESS' }]);
    await expect(prisma.$executeRawUnsafe(`INSERT INTO "${schema}"."AdminTrialAccess" VALUES ('invalid-basic-trial','BASIC')`))
      .rejects.toThrow(/AdminTrialAccess_paid_plan/);
  });
});
