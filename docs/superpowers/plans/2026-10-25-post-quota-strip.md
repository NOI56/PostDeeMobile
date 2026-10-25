# Compact post quota after clip selection — 2026-10-25

## Request and baseline

The user wants the remaining posting quota visible after selecting a clip, in
a compact strip like the approved AI quota display. Work on the existing
`codex/caption-credit-per-channel` candidate in the `caption-quota-main`
worktree, based on verified fresh `origin/main` `b7fb8533`. Preserve all pending
per-channel caption changes and the unrelated dirty original checkout.

## Existing contract and presentation

- Show the strip in the uploader's clip-selection step only after a clip is
  selected, including an initial clip handed to the composer. Keep a small
  effective-plan badge, monthly remaining/limit in `หน่วย`, used units and a
  thin remaining progress bar. A paid user's nonempty purchased post bank gets
  one short conditional line; do not expand this into another dashboard.
- Reuse the existing authenticated `GET /billing/subscription` response and
  `SubscriptionStatusResult` through optional `UploaderScreen.loadPostQuota`.
  Its default calls the session-bound client's `loadCurrentSubscription`;
  keep this background loader separate from imperative `loadSubscription`
  preflight sequences. No client DTO/API change is needed.
  `monthlyPostLimit`, `usedPostsThisMonth` and
  `remainingPostsThisMonth` describe included monthly quota; `addonPostUnits`
  describes the retained purchased balance and `availablePostUnits` the usable
  total. Basic's retained bank is not usable until paid membership resumes.
- Explain Basic's phone gate using `requiresPhoneVerification`; the existing
  `canUseFreePostQuota` eligibility rule remains authoritative. A
  gated monthly remainder of zero is not evidence that its allowance was spent.
  Keep the server's phone and posting eligibility checks authoritative.
- Capture owner/session/request/clip identity; reuse the existing caption-session
  listener without adding another auth listener. Refresh on selection/reselection,
  initial handed-in clips, app resume, auth-session changes, successful
  in-composer subscription resync and post acceptance/failure or recovery while
  the composer remains open. Billing/phone changes are reread on the next
  supported refresh. Reject late
  results from a different session, clip or superseded request.
- Render numeric quota only when all three monthly fields are valid.
  Distinguish loading, missing fields and failed reads from a confirmed zero;
  offer retry rather than fabricating balances. Reading/presenting quota does
  not reserve or spend a post unit. Selection does not upload, start AI, publish
  or open checkout. The existing GET's legacy canonical-user preparation stays
  intact; this does not change it into a read-only API contract.

Included post allowances remain Basic 3 (phone-gated), Starter 120 and Pro 250.
One selected publishing destination still costs one post unit; included monthly
units are consumed before nonexpiring purchased units. Preserve plan prices,
trial/effective-plan access, publishing/phone/quota guards, the four-step wizard,
caption cost/preview/undo, owner scope and existing refresh behavior. No new
endpoint, response field, backend rule, schema, migration, provider, flag or
dependency is intended.

## Verification and delivery boundary

Plan widget/uploader coverage for selected/unselected and handed-in clips,
selection/reselection refresh, current plan/monthly balances, paid banks,
Basic phone gates, loading/retry/missing fields, session/request races, resume,
auth changes, in-composer resync and post acceptance/failure or recovery. Check
that billing/phone changes appear on the next supported refresh.
Check narrow width, enlarged text and both themes. Run relevant required
Mobile suites, analysis and exact-environment build/smoke, then review the
combined diff without dropping the pending caption work. Record actual results
after execution; no test, installation or deployment claim is made here.

No API deployment or database migration is required for this display because
the existing endpoint already supplies its data. This does not establish that
the Mobile candidate was pushed, installed or deployed; those remain separate
delivery actions with their own verification.

## Verified implementation — 2026-10-25

Completed in
`C:\Users\stopp\.codex\worktrees\caption-quota-main\PostDeeMobile` on
`codex/caption-credit-per-channel`. A final fetch still showed `origin/main`
at `b7fb8533` (no new commits relative to the candidate's baseline). Pending
caption-credit work and the unrelated dirty original checkout were preserved.

Files for this display: modified `apps/mobile/lib/features/uploader/uploader_screen.dart`;
new `post_quota_strip.dart` in that directory; new tests
`post_quota_strip_test.dart`, `uploader_post_quota_test.dart`,
`uploader_post_quota_recovery_test.dart`, `uploader_post_quota_visual_test.dart`;
the four main docs and this plan. No backend/client DTO, price, allowance,
schema/migration, provider, dependency, flag or Android configuration change.

- Full Mobile suite passed **2,968 tests, 6 pre-existing skips**. This includes
  **27 new regressions**: strip 11, uploader 11, recovery 3 and visual 2.
  Coverage includes initial/picked/reselected/replaced clips, missing/invalid
  quota, retry, app resume, different-owner and same-owner/new-session races,
  disposal, paid bank, phone-gated Basic and downgrade usage above the limit.
- A recovery regression first reproduced a stale positive balance after an
  accepted/failed original post was found. Its owner/session-guarded final
  refresh now passes all three recovery cases without upload, publish or
  preflight side effects. The server's current allocation is displayed rather
  than locally deducting or refunding units. Existing AI resync tests and the
  prior per-channel caption regressions remain included in the passing suite.
- Full `flutter analyze --no-pub` passed with no issues. `git diff --check`
  passed; no deleted baseline files. Unrelated auto-generated Windows plugin
  changes from dependency resolution were removed after checking their diff.
- Real-font visual checks passed for light **430x1000** and dark **320x900**
  with **1.7x** text. Current page/card PNGs are in
  `D:\PostDeeMobile\output\playwright\post-quota-strip`. The new strip is
  readable and stays below clip metadata/cover actions; enlarged usage text
  wraps without overflow. Some unrelated toolbar labels use the Flutter test
  font fallback in whole-page captures; no product font change was introduced.
- Exact-source Staging debug APK build passed using
  `staging.local.example.json`: Staging API URL, Firebase auth enabled, local
  mock auth disabled, RevenueCat billing disabled. APK metadata confirms
  `com.postdee.postdee_mobile.staging`, `PostDee Staging`, `0.1.0-staging`
  (version code 1). Debug Firebase configuration targets
  `project-798caf7e-85b8-45e3-af7`. No APK was installed and no real account's
  hosted balance or provider publishing flow was exercised.

The verification above was completed before main delivery. On 2026-10-25 the
user authorized `main/push` for this display and per-channel caption charging.
Main delivery does not deploy Render or install the APK. This display uses the
existing deployed subscription contract; it does not need a new API deployment.
The per-channel caption charging change still requires its coordinated
API/Mobile release, as documented in its own plan.
