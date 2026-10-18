# PostDee administrator console and trial access

## Authorization and baseline

The user approved implementation of the seven Thai administrator views and the
recommended roles, environment labeling, usage reports and time-limited trial
grants. Freshly fetched canonical main is `c813eef72d1bc98e958b86ae2928e80a20939f8a`.
Implementation uses the clean `codex/admin-trial-console` worktree. Existing
generated Windows modifications and unrelated artifacts remain in their worktrees.
This scope does not authorize deployment, changing actual account privileges,
granting real customer access, sending social posts, refunds or paid purchases.

## Chosen boundary

The console uses the existing Express deployment, Firebase identity, PostgreSQL
and paid subscription rules. A separate, expiring PostDee trial ledger augments
effective access without editing store purchases or RevenueCat subscriptions.
This avoids replacing a paid Starter/Pro record with a temporary promotion.
All API and worker entitlement checks use the higher active paid/trial plan;
expiration/revocation preserves existing paid access and never resets usage.
No recurring charge or store subscription is created by a trial grant.

The administrator surface is disabled by default. Owner/viewer Firebase UIDs are
configured server-side, never selected by email or supplied in browser claims.
Only owners with a recent authenticated session can change trial access. The
browser never receives a service account key, database URL or provider secret.
Writes require a same-origin JSON request, explicit review, a reason, immutable
request identity, optimistic version and a durable audit in the same transaction.
Target-account deletion barriers and cascading data removal must remain intact.

## Views and limits

- Overview: observed member, trial and publication counts.
- Members: bounded search, purchased plan, separate trial and channel details.
- Posts: bounded status/platform/date search with redacted failure summaries;
  no publication/retry/delete action.
- Trials: registered-account grant, extension and revocation. Presets 7/14/30
  days; extension is bounded to 90 days ahead. No lifetime grant.
- Channels: stored connection identities/status; no delegated OAuth or raw tokens.
- Reports: trial/usage cohorts and CSV export. Estimated costs require explicitly
  configured unit rates and are labeled estimates, not invoices. A paid plan
  observed after a trial is not automatically attributed as a conversion.
- Audit: actor, target, reason, immutable intent and before/after trial state.

Static client assets follow the existing Express HTML delivery convention to
avoid adding a separate hosting service or frontend dependency/build pipeline.
Layout follows the ImageGen member-table/trial-drawer concept with semantic HTML,
responsive navigation, shared tokens/components and reduced-motion support.

## Preservation and verification gates

Preserve Firebase session ownership, all paid-package rules and quotas, RevenueCat
ordering/restore behavior, scheduled publishing, AI gates, account deletion,
retained owner operations, R2 uploads, mobile and public shop pages.
Add regression tests before implementation; verify owner/viewer isolation,
disabled-by-default behavior, forged roles, expired sessions, stale/double writes,
trial expiry, paid/trial overlap and CSV safety with dummy identities. Run API
tests/typecheck/build/schema validation and browser workflows against a local
fixture server. No live account grant or external provider call belongs to QA.

The additive migration must precede enabling trial access or the admin console.
Actual administrator UID, public Firebase web configuration and HTTPS origin are
deployment configuration; no user is granted administrator access by this source.
