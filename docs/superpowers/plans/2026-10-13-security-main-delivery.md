# Security integration into current main — 2026-10-13

## Scope and baseline

The user requested main push/deployment and showed the Android Emulator with
the Staging marker and the current Store link editor. Delivery preparation
targets that Staging app first; Production scope has not been confirmed.

Verified by `git fetch origin main codex/ai-edit-thai-timing-staging --no-tags`:
`origin/main` is `c4e52201a58b556f5f47529027549a2fc16af84c`. A fresh managed
worktree, `security-main-delivery/PostDeeMobile`, and branch
`codex/security-main-delivery` start at that exact commit (merge base matches,
ahead/behind 0/0). The original `D:/PostDeeMobile` worktree and its uncommitted
changes are preserved.

During preparation another authorized main integration advanced the shared
remote from `c4e5220` to `f5dea16f59bfb317c92971c6bbef60d8b742ea5d` (30 commits,
including system-audit reliability fixes and current mobile motion). A second
`git fetch origin main --no-tags` verifies that latest head. Local WIP checkpoint
`b4961e8` preserves the initial port; it has not been pushed. Reconciliation
onto `f5dea16` completed locally at checkpoint `b632b5a`, retaining both sides
intentionally, including content fingerprints,
image protection, device token rotation/unregistration/cold taps, native billing
acknowledgements and all current motion UI. No whole-file older-side resolution.

Earlier audit/remediation artifacts reviewed `0882996` plus a dirty working
tree, not this current main. Their source findings and 50 + 130 unrun added
cases must not be presented as verification of this delivery branch. Replay
only still-applicable behavior; do not copy old files over main or replay an
entire stale branch. Main already has trusted-proxy/IPv6 rate limiting, paid
rescheduling admission, stable mobile identity and per-owner drafts.

## Existing behavior to preserve

- Current Store link UI, website publication, themes, images, compositions,
  contacts and custom links; per-UID drafts and account-deletion cleanup.
- Home, Calendar, account/profile, bottom navigation, the full-screen
  four-step post composer and saved publish drafts.
- Current PostPeer mappings, target/settings validation, idempotent post
  creation/queue repair, `publish-now`, scheduling limits and real receipts.
- Shared API mutation/deletion coordinator, readiness, shutdown and provider
  uncertainty handling; do not create nested owner-lock deadlocks.
- Firebase credential snapshots/UID validation, auth timeouts/disposal and
  existing Thai errors. Billing session cache, pending confirmation and retry
  must not buy twice when an already-dispatched payment needs confirmation.
- Existing configuration, schema/migrations, dependency locks, providers,
  Staging Firebase project and APK signature. No Production/provider activation.

## Selective source integration

1. Final User ensure, Post create/quota/reschedule/publish-now and Subscription
   activation/RevenueCat event writes check and lock an ACTIVE owner marker in
   the same Serializable database transaction. Memory stores share owner
   admission. Keep legacy mode owner checks independently of multipart.
2. Queue admission covers enqueue, ensure-enqueued and reschedule while
   preserving current idempotent semantics, health/close functions and account
   cleanup of owned jobs without post rows. Keep Redis outside SQL transactions.
   Preserve main's acknowledgement/error/SQL rollback boundaries: no generic new
   queue acknowledgement timeout or broad late compensation removes previously
   accepted/idempotent jobs. The independent lifecycle FIFO has a five-second
   admission/drain wait; it does not bound the existing HTTP coordinator's wait
   or the complete DELETE request.
3. Add authenticated `POST /billing/purchase-readiness` returning
   `status: ok`, `purchaseReady: true`, `preparationProtocol: 1`; current mobile
   validates it before RevenueCat buy. Keep legacy GET user preparation during
   this additive rollout, now subject to final owner fencing. This delivery
   stage does not include the earlier stale branch's read-only GET cutover.
4. Add session generations to the existing stable identity/credential store,
   bound HTTP operations and a shared native auth queue for account deletion,
   Apple revocation and phone linking. Retain main's caller/UI timeouts/cleanup,
   while holding the queue until the raw SDK work settles, including both phases
   of Google sign-in. An expired queued attempt must not dispatch later.
5. Preserve billing pending-state behavior while binding preparation, SDK
   configuration/product lookup, buy/restore, reconciliation and entitlement
   polling to their original operation. Never retarget a later account.
6. Clear/filter in-app push history by exact recipient UID and bind token
   registration. Backend publish notifications carry `data.userId`.
7. Retain current rich Store link draft fields and server publication; guard
   delayed operations/modal results on session-generation changes and close
   only routes owned by the affected editor.

## Verification and delivery gates

Add/update regression cases before implementation, review the diff against the
verified main baseline and run the relevant full API/Flutter checks plus exact
Staging APK build/smoke before merge/deployment. Check package/API/Firebase/
entitlement/source SHA and keep the existing signature/session/data when
updating the Emulator; never uninstall or clear data to bypass a signature
mismatch.

Current status: selective source integration and independent source review are
complete in the local branch based on `f5dea16`. Added regression cases: 34 API
and 113 mobile (147 total), all UNRUN. Trusted-parent `git diff --check` passes;
no merge markers remain. This static evidence does not establish runtime behavior.
Tests/build/analyze/Prisma and
Emulator smoke are UNRUN for this branch. The installed security-audit skill
requires a complete OS sandbox for target execution. The host inventory has
no such runner, and the existing Actions workflow is not proof of those
controls. Do not dispatch ordinary target tests or builds while this execution
requirement is unresolved; do not treat old smoke/CI results as new evidence.

Source preparation and independent review are complete in a local branch
(77 changed files: 37 API source/tests, 31 mobile source/tests, 9 documentation).
This record does not claim a push, PR, main merge, deploy, APK build or Emulator update.
Update the exact delivery evidence here when those actions actually happen.

## Remaining limitations

Owner database fences do not make SQL/Redis or multiple API processes atomic.
Already-admitted provider/native operations cannot be canceled by a generation
check; cross-instance late queue adds, crash recovery and draining need separate
work. Existing managed-upload snapshot admission and other account stores are
outside the three-entity final-write guarantee. Main's device token rotation,
authenticated unregistration and cold-start tap handling are preserved. In-app
recipient filtering alone cannot establish backend cleanup or control
OS-displayed background notifications; runtime lifecycle checks remain pending.

Mock auth now uses the configured `AppConfig.mockUserId`, aligning local scope
with the API's development principal. Existing published server profiles reload
under that owner. Older local drafts under `local-mock-user` remain in their
original scope; no automatic draft migration or deletion is included.

Billing rollout: additive endpoint → preparation-aware mobile builds → retire
or independently disable any deployed legacy buying builds → consider a
separate read-only GET cutover. Confirm whether such builds exist before that
last step. Never restore missing-user webhook recreation as a compatibility
fallback. Unsupported/missing preparation must stop before a new SDK buy, while
already-completed payments retain main's pending-confirmation/retry flow.
