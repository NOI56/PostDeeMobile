# Consolidated package categories and top-ups

## Approved scope and baseline

The owner authorized one consolidated draft PR for package categories and the
three approved replacement consumables, without merging or opening sales.
Fresh remote review confirmed main `f658f9089b14f0d66d900d89fbc1c8bbfddff437`.
PR #50 head remains `11cd65a5af6a70f6266ac252f02adb1f6d77bc22`, #51 remains
`99e945b433c3ea22055f971747c928417859c01b`, #52 remains
`03f1f457c4ef4928840c12eac43c9eb047ee9f12` and #53 remains
`e488a4f1f6ec33947e0a908768e7e013c29921f6`; all were open and unmerged.

The dedicated `codex/packages-consolidated` branch starts from that exact main.
The previous local integration `9153ecb3ea23787a3696e10f6553dda7efee2585` is
verification evidence, not a wholesale parent: it inherited unrelated PR #50
work. Only the 37 billing paths plus four existing paywall test files are ported,
with current-scope documentation updated and this record added (42 paths).

## Included behavior and excluded dependencies

- Thai/English Main plans and Add-ons categories, preserving Basic/Starter/Pro.
- Relevant PR #50 paywall safeguards: main-only per-channel unit explanation;
  hide unsold add-ons only after a completed disabled catalog with neither owned
  credits nor a pending receipt; retain loading/errors/retry/balance/recovery.
- New catalogs use their own offer flags instead of the legacy scalar sale flag.
- Small `postdee_post40_caption25`: 40 post units / 25 caption credits, THB 49
  reference. Medium `postdee_post90_caption50`: 90/50, THB 99. Large
  `postdee_post190_caption100`: 190/100, THB 199. Payable prices always come from
  the exact native store product. Repeat purchases remain supported; no best-value
  or discount claim is made.
- Historical `postdee_post100_caption50`, configured legacy aliases and v1 pending
  receipts retain 100/50. Immutable per-purchase grants, receipt namespaces,
  duplicate/refund handling, shared locks, eligibility, non-expiry and separate
  monthly-first post/caption banks remain unchanged.

PR #50 auth, home, profile, shell and uploader changes and their tests are
excluded and match main. PR #51 is untouched. No new runtime dependency is
needed; PostDeeNotice already exists on main. This PR has no dependency on merging
the unrelated portions of PR #50. If #50 is later integrated, preserve the shared
paywall decisions and resolve its overlapping hunks deliberately. PR #52/#53
remain open and unchanged for review/history; this draft consolidates their
package scope without closing or modifying their branches.

## Equivalence and validation strategy

Independent review verified the six paywall source/test files are byte-identical
to tested `9153ecb3`. API, mobile core/config/models, add-on service and pending
storage are byte-identical to `e488a4f1`. Excluded PR #50 source and tests match
fresh main. Documentation changes do not alter those source comparisons.

Fresh local checks on the scoped branch: five-file paywall suite 138 passed /
1 optional legacy-preview skipped, including fixture rendering; full Flutter
analyze found no issues (13.4s). The Thai and English fixture PNGs exactly match
the previously reviewed images, so the existing Library fixture is reused.

The full earlier integration test count is not claimed as a full pass for this
scoped tree: removing unrelated PR #50 work changes the wider app. Fresh focused
paywall checks, full Flutter analyze and the supported guarded Staging build are
run on this branch; its PR CI runs both complete Mobile and API suites against
the final candidate. Exact terminal counts, commit/tree, logs and APK digest are
recorded in PR checks/body and the task verification artifact.

Valid unchanged API evidence also includes 3,297 API tests and 19 affected real
local PostgreSQL tests, including populated legacy migration, late legacy writer
defaults, immutable grants, duplicate/refund behavior and separate quota use.
This equivalence does not replace the new consolidated full CI result. The
disposable fixture database is stopped; no hosted database is used.

## Rollout and remaining release checks

`BILLING_ADDON_TIERS_ENABLED` stays false by default, additionally requiring the
existing global add-on gate and provider readiness. This draft does not create
store products, change production settings, migrate a hosted database, activate
sales, approve/merge PRs or deploy.

1. Separately authorize the additive `20261102010000_addon_grant_snapshots`
   migration and compatible API on every instance before selling new-sized SKUs.
2. Configure the three exact consumable IDs in the stores and RevenueCat under
   separate authorization; verify country prices through native store quotes.
3. Verify native sandbox purchase, repeat purchase, interrupted/pending recovery
   and refund flows, including historical customers. Widget fixtures and APK
   builds do not establish native checkout success.
4. Decide separately when to retire new legacy SKU sales, retaining its receipt
   history and fulfillment. Keep modern pending recovery through Mobile rollback
   and snapshot-aware API readers after any new-sized transaction exists.
5. Enable sales or deliver Production only with separate authorization.

The latest observed device inventory had no connected Android device or configured
AVD. No owner device is overwritten, cleared or installed in this task. The
existing Library screenshot is an offline widget fixture with selected Add-ons
and all three tiers, not native-device or sandbox-purchase proof.
