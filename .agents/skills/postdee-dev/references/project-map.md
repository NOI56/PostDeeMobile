# PostDee source map

Paths are relative to the repository root. Confirm a path still exists before relying on it; the current code wins over this map.

## Where to start reading

| Work area | Starting points |
| --- | --- |
| Product scope and rules | `AGENTS.md`, then only the relevant sections of `ROADMAP.md` and `README.md` |
| Architecture, API, deployment | `ARCHITECTURE.md`, `API.md`, `docs/STAGING.md`, `docs/GO_LIVE.md`, `FIREBASE_SETUP.md` |
| API composition and configuration | `apps/api/src/app.ts`, `apps/api/src/server.ts`, `apps/api/src/config/env.ts`, `apps/api/package.json` |
| Schema and persistence | `apps/api/prisma/schema.prisma`, `apps/api/prisma/migrations/`, the feature's memory store and Prisma repository |
| Mobile app shell, theme, localization | `apps/mobile/lib/app.dart`, `apps/mobile/lib/features/shell/`, `apps/mobile/lib/core/theme/`, `apps/mobile/lib/core/localization/` |
| Create post: upload, captions, channels, scheduling | `apps/mobile/lib/features/uploader/`, `apps/mobile/lib/features/captions/`, `apps/mobile/lib/features/platforms/`, `apps/mobile/lib/features/posts/`, `apps/mobile/lib/features/calendar/` |
| Mobile networking and sign-in | `apps/mobile/lib/core/network/postdee_api_client.dart`, `apps/mobile/lib/core/auth/`, `apps/mobile/lib/features/auth/` |
| API uploads, captions, connections, publishing | `apps/api/src/modules/uploads/`, `apps/api/src/modules/captions/`, `apps/api/src/modules/socialConnections/`, `apps/api/src/modules/posts/`, `apps/api/src/modules/platformPublishes/`, `apps/api/src/workers/` |
| Billing, quotas, trials | `apps/api/src/modules/subscriptions/`, `apps/api/src/modules/billing/`, `apps/api/src/modules/admin/trialAccess.ts`, `apps/mobile/lib/features/billing/` |
| Store link and account | `apps/api/src/modules/linkInBio/`, `apps/api/src/modules/users/`, `apps/mobile/lib/features/link_in_bio/`, `apps/mobile/lib/features/profile/` |
| Account deletion | `apps/api/src/modules/account/` |
| Admin, support, push, service notices | `apps/api/src/modules/admin/` (UI in `admin/web/`), `apps/api/src/modules/supportChat/`, `apps/api/src/modules/supportBot/`, `apps/api/src/modules/notifications/`, `apps/api/src/modules/devices/`, `apps/api/src/modules/serviceStatus/`, `docs/ADMIN_CONSOLE.md` |
| Mobile support and notices | `apps/mobile/lib/features/support/`, `apps/mobile/lib/features/notifications/`, `apps/mobile/lib/features/home/home_service_status_banner.dart` |
| Shared Mobile widgets | `apps/mobile/lib/features/shared/` |
| Device build helpers | `apps/mobile/tool/` (see `postdee-android-build`) |
| Tests and CI | API tests sit next to the code (`*.test.ts`, `*.database.test.ts`); Mobile tests in `apps/mobile/test/`; CI in `.github/workflows/ci.yml` and `build_ios.yml` |

Retired AI-editing and Clip Review code (`aiEdits`, `clipReviews`, `features/ai_editing`) is compatibility code; see the table in `AGENTS.md` before touching it.

## Contracts with a non-obvious shape

These are pointers to the code that owns each rule, not a frozen specification.

### Publishing

- PostPeer request mapping and result interpretation: `apps/api/src/workers/postPeerPublisher.ts`. Per-platform settings and validation: `apps/api/src/modules/posts/platformSettings.ts`, `platformTargets.ts`, `platformCaptionValidation.ts`, `tikTokDirectSettings.ts`.
- A post stores a snapshot of its targets. A connection removed or changed after review must make the post fail closed, never silently pick another account.
- A connection's existence does not prove it can publish. Readiness comes from `GET /social-connections/publishing-readiness` (`publishingReadinessRoutes.ts`) and `GET /publishing/readiness` (`postRoutes.ts`). Readiness reads must not create provider profiles or repair connections.
- `POST /posts` uses a stable `clientRequestId` for idempotent replay. A lost-response retry must return the same post, and quota must count once.

### Billing, captions, store links

- `apps/api/src/modules/subscriptions/subscriptionStore.ts` separates effective access from `getPurchasedPlan`. A Pro trial unlocks features without proving a purchase; purchase and restore confirmation must use paid evidence.
- Current plan limits live in `apps/api/src/modules/subscriptions/subscriptionEntitlements.ts`. Read them; never copy numbers or prices from old chats or dated docs.
- Caption batches: `apps/api/src/modules/captions/captionRoutes.ts` requires `expectedCredits` to match the server's cost for multi-channel requests; credits are reserved atomically and refunded on failure. Mobile and API must compute the same cost.
- Store links: a plan downgrade keeps saved links and their publication state. Do not delete user data to fit a lower plan.

### Account deletion

- Deleting the `User` row clears the user's data through `onDelete: Cascade` relations (`accountRoutes.ts`). A new user-owned model must cascade from `User` or be handled explicitly in account deletion, with a test.

### Admin and support

- Admins are owners (`ADMIN_OWNER_UIDS`) or viewers (`ADMIN_VIEWER_UIDS`). Owner-only operations answer `403 ADMIN_OWNER_REQUIRED`; decide which role a new operation needs and test both roles. Preview the viewer role with `npm.cmd run admin:preview -- --viewer`.
- Support "waiting for reply" counts and unread counts are different concepts with different triggers.
- Service notices are visible to every customer. Dot (`supportBot`) sends chat text to an external provider when switched on; it is off unless an owner enables it.
- Push text must not reveal a customer's chat content or identity on a lock screen.
