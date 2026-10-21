# Usability review fixes — 2026-10-21

## Baseline and authorization

The user requested implementation after the review of 100 synthetic scenarios.
This is not a study of 100 human participants or a concurrent-user load test.
Remote `main` was checked at `ca4f215a51bf0dd4df7d513175341e49076a9c10`.
Candidate branch `codex/ux-review-improvements` reuses the attached
`platform-consent-preserve` worktree at that exact base. Three pre-existing
generated Windows line-ending changes are preserved and excluded from delivery.
The stale `D:/PostDeeMobile` source is not used for implementation.

## Implemented scope

- Exact owned single-post read, refresh/poll/re-entry in detail, direct lookup
  for result/recovery/notification routes, truthful missing-record behavior,
  cancellation reconciliation, and safe remote preview when owned media exists.
- Search/status/platform/date filters and visible channel/date metadata in
  history; lazy list construction and refresh after detail return.
- Visible channel validation with a route to the relevant settings, caption
  preflight before progress, policy-launch fallback, foreground guidance and
  at least 48dp schedule targets. Preserve selected smooth progress motion,
  fresh consent, current platform readiness, original request IDs and recovery.
- Explicit disconnect confirmation, store selection when purchase provenance is
  unknown, prepaid-balance warning before account deletion, pending-purchase
  help without another checkout, and undo for local-draft link deletion.
- Consistent post units and optional monthly quota reset time; bank eligibility,
  nonexpiry, monthly-first accounting, price and disabled sales gate unchanged.
- Scrollable small-screen onboarding with accessible text and persistent
  navigation, darker secondary/action text colors, per-item notification read
  state and a route from session-only notifications to actual post history.
- Analytics is created only when explicitly opened and keyed to the owner.
  Fresh sign-ins recreate its session binding; disposal or account changes stop
  late subscription checks from starting another analytics request.

## Changed files

- Backend: `apps/api/src/modules/posts/{postRoutes,postStore,prismaPostRepository}.ts`,
  new `postReadRoutes.test.ts` and `prismaPostOwnedRead.test.ts`, and
  `apps/api/src/modules/billing/billingRoutes{,.test}.ts`.
- Client/shared presentation: `apps/mobile/lib/core/network/postdee_api_client.dart`,
  `core/theme/app_theme.dart`, `features/shell/postdee_shell.dart`,
  `features/onboarding/onboarding_flow.dart`, and
  `features/notifications/{notifications_screen,push_notification}.dart`.
- Publishing: `features/posts/{post_detail_screen,posts_screen}.dart`,
  `features/calendar/calendar_screen.dart`, and
  `features/uploader/{uploader_screen,publish_flow_screen,publish_review_screen,post_video_preview_screen,tiktok_publishing_settings_sheet}.dart`.
- Account: `features/platforms/connections_screen.dart`,
  `features/profile/profile_screen.dart`, `features/billing/paywall_screen.dart`,
  `features/link_in_bio/link_in_bio_screen.dart`, and
  `features/analytics/analytics_screen.dart`.
- Mobile tests cover those flows under `apps/mobile/test/`, including new
  `ux_accessibility_regression_test.dart`, `billing_quota_reset_test.dart`,
  `post_detail_live_state_test.dart`, `post_read_api_test.dart` and
  `calendar_cancel_recovery_test.dart`. Existing tests were extended for
  notifications, onboarding/shell, uploader/settings/scheduling, connections,
  profile, paywall, link management, analytics, preview and post history.
- Documentation: `README.md`, `ROADMAP.md`, `API.md`, `ARCHITECTURE.md`, this
  record and the historical publishing-motion plan's follow-up link.

## Contracts and release order

Deploy API first, Mobile second. `GET /posts/:id` returns only an exact owned
record and optionally safe signed media; `404 POST_NOT_FOUND` is distinguishable
from an old deployment's generic route 404. `monthlyQuotaResetsAt` is optional
and uses the next UTC calendar-month boundary, displayed in device-local time.
Legacy post lists, publishing contracts, migrations, credentials and feature
flags remain unchanged. This task does not authorize a real post, purchase,
account deletion, main integration, push, deployment or emulator update.

## Verification record

Evidence is under `D:/PostDeeMobile/artifacts/ux-fixes-20261021`.
Regression tests were added and run against the baseline before implementation:
API exact-read tests failed as expected (9 cases); uploader/root and account/post
Mobile tests also failed at the missing contracts/behaviors. Existing tests that
were unaffected continued to run. Additional red probes covered a late analytics
preflight, FAILED result navigation, media signing during polling and 2x text in
the connection confirmation. Intermediate red/partial integrations remain in the
evidence directory and are not delivery results.

- Final Mobile full suite: **2,654 passed, 6 optional image-export previews
  skipped**, exit 0 (`mobile-full-final.log`, 199.1s).
- Final focused regression pass: **193/193**, exit 0; final `flutter analyze`
  reports **No issues found**. This includes large Thai text, old editing/image
  flows, owner/session changes, draft/receipt retention and no duplicate publish.
- API full rerun: **2,399 passed, 18 optional admin-database tests skipped**,
  exit 0. A first run under simultaneous compilation timed out in an unchanged
  database tombstone test; the isolated six-test DB file and a complete rerun
  passed without relaxing its timeout or changing the test.
- API typecheck, build, Prisma validation, seed-helper compilation and migration
  status pass. The dedicated loopback fixture has all 22 existing migrations;
  no new migration. User/purchase/upload-owner fixture row counts are zero after
  cleanup and its PostgreSQL server was stopped.
- Exact source manifests cover **577 Mobile/shared inputs** and **452 API/shared
  inputs**. Both source and D-drive verification snapshot match; lib/test file
  sets match exactly (307 paths). No source deletion or unrelated generated
  Windows change is delivered.
- A separate rendering harness passes using local synthetic history/partial
  results and actual Anuphan onboarding at 320dp/2x text. PNGs are fixture
  evidence, not native acceptance; host-test image decoding and fallback fonts
  are not evidence of an Android logo/font regression.
- Staging debug APK **12034**, x86_64, builds successfully. Inspection verifies
  package/version, the existing signing certificate, 16KiB alignment, Firebase
  and Google app identities, the existing public billing SDK key, new compiled
  UX contracts and retained defaults/progress/pending-purchase code. Its SHA-256
  is `225b0da11ff936b7e23054a6f111977d0d206766571dd066feb012302f9fd496`;
  see `apk-verification-12034.json`. The prior 12032/12033 delivery APKs remain
  preserved. No emulator update or hosted release occurs. The existing plugins'
  Kotlin Gradle migration warning concerns a future Flutter upgrade; the current
  build succeeds and dependency/runtime configuration is unchanged.

## Explicit remaining limits

- No real provider publishing, store checkout/refund, OAuth or native assistive
  technology acceptance is performed.
- Session-only notification history remains honestly labeled; persistent or
  cross-device history is not invented. Legacy full history is not replaced by
  server cursor pagination in this backward-compatible patch.
- Full localization, physical-device FPS/RAM/load profiling and changes to the
  approved center icon-only design need separate product/user evidence.
- Review items HOME-F03/04/05 remain design/localization follow-ups: the existing
  bottom-label 1.3x cap is unchanged, no untested center-button redesign is
  introduced, and this patch does not claim full English localization.
  HOME-F06 is partly addressed by lazy, session-bound analytics and lazy history
  rows; history pagination and physical-device measurements remain open.
- No standard-compliance claim for every custom status color or provider asset;
  contrast checks cover the shared text/primary-action surfaces changed here.
- No production, Render, RevenueCat configuration or real user data is changed.
