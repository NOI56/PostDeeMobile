-- Every historical transaction (including configured legacy aliases and refund
-- tombstones) represented 100/50. Defaults preserve that contract for old
-- writers while new verified SKUs explicitly persist their own grant snapshot.
ALTER TABLE "MonthlyAddonPurchase"
  ADD COLUMN "postUnitsGranted" INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN "aiCaptionsGranted" INTEGER NOT NULL DEFAULT 50,
  ADD CONSTRAINT "MonthlyAddonPurchase_grant_quantities"
    CHECK ("postUnitsGranted" >= 0 AND "aiCaptionsGranted" >= 0
      AND ("postUnitsGranted" > 0 OR "aiCaptionsGranted" > 0));

CREATE OR REPLACE FUNCTION "preserveMonthlyAddonGrantSnapshot"()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW."postUnitsGranted" IS DISTINCT FROM OLD."postUnitsGranted"
    OR NEW."aiCaptionsGranted" IS DISTINCT FROM OLD."aiCaptionsGranted" THEN
    RAISE EXCEPTION 'Purchased add-on grant snapshots are immutable' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "MonthlyAddonPurchase_immutable_grant"
BEFORE UPDATE OF "postUnitsGranted", "aiCaptionsGranted" ON "MonthlyAddonPurchase"
FOR EACH ROW EXECUTE FUNCTION "preserveMonthlyAddonGrantSnapshot"();
