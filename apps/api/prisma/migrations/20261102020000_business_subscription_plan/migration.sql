-- Add the new monthly plan without rewriting existing subscriptions or trials.
ALTER TYPE "SubscriptionPlan" ADD VALUE 'BUSINESS';

-- The trial ledger shares this enum. Keep its paid-only rule while admitting
-- Business; text comparison avoids using a new enum label before commit.
ALTER TABLE "AdminTrialAccess" DROP CONSTRAINT "AdminTrialAccess_paid_plan";
ALTER TABLE "AdminTrialAccess" ADD CONSTRAINT "AdminTrialAccess_paid_plan"
  CHECK ("plan"::text IN ('STARTER', 'PRO', 'BUSINESS'));
