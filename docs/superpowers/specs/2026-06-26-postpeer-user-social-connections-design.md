# PostPeer User Social Connections Design

## Goal

Let each PostDee user connect their own TikTok, YouTube Shorts, Instagram Reels, and Facebook Reels accounts through PostPeer from inside the mobile app. Publishing must use the connected account owned by the post's authenticated user, not a shared environment-level account id.

## Scope

This design covers backend routes, storage, PostPeer adapter boundaries, publish-time account lookup, and the mobile profile connection UI. It keeps the existing environment account ids as an operator-only fallback for early smoke tests, but user-owned connections take priority whenever a post belongs to a user with stored connections.

Shopee Video and Lazada Video stay out of scope until the provider supports them through the same connection model. Direct TikTok, YouTube, Instagram, or Facebook OAuth integrations stay out of scope; PostPeer remains the only social publishing provider for this phase.

## Architecture

The backend gains a `SocialConnection` data model scoped by `userId` and `platform`. Each row stores the PostPeer integration/account id, display metadata safe to show in the app, connection status, and timestamps. In-memory and Prisma-backed stores expose the same interface so tests and local development continue to work.

The API exposes authenticated routes under `/social-connections`. The mobile app calls `POST /social-connections/:platform/connect` to request a provider authorize URL, opens that URL outside the app, and then refreshes `GET /social-connections` after the user returns. PostPeer sends the completion result to a backend callback, where the API validates a short-lived state token before saving the returned account id to the correct user and platform.

Because the currently verified PostPeer API only exposes `GET /v1/connect/integrations`, the provider-specific connect URL creation is isolated behind a `PostPeerConnectClient`. The client reads its create-link path and callback secret from config. If Render does not yet have the provider create-link path configured, the API returns a clear unavailable response instead of pretending the account is connected.

## Backend Components

- `prisma/schema.prisma`: add `SocialConnection` with a unique `(userId, platform)` constraint and cascade deletion through `User`.
- `apps/api/src/modules/socialConnections/socialConnectionStore.ts`: define the store interface and in-memory implementation.
- `apps/api/src/modules/socialConnections/prismaSocialConnectionRepository.ts`: Prisma implementation.
- `apps/api/src/modules/socialConnections/socialConnectionRoutes.ts`: register status, connect start, callback, and disconnect routes.
- `apps/api/src/modules/socialConnections/postPeerConnectClient.ts`: call PostPeer to create authorize URLs and normalize callback/integration payloads.
- `apps/api/src/workers/postPeerPublisher.ts`: accept an async account-id resolver using `userId` and `platform`.
- `apps/api/src/workers/publishWorker.ts`: pass `userId` into platform publishing input.
- `apps/api/src/workers/platformPublisherFactory.ts`: prefer user-owned connection lookup and fall back to env account ids only when no store is available.
- `apps/api/src/app.ts` and `apps/api/src/workers/publishWorkerRunner.ts`: wire the social connection store into API and worker creation.

## API Contract

`GET /social-connections` returns the authenticated user's supported platforms with `connected`, `displayName`, `externalAccountId` when safe, and `connectedAt`.

`POST /social-connections/:platform/connect` validates the platform, creates a signed state tied to the authenticated user and platform, asks PostPeer for an authorize URL, and returns `{ connectUrl, expiresAt }`. If the provider create-link endpoint is not configured, it returns `503` with a message that account linking is not available yet.

`GET /social-connections/postpeer/callback` and `POST /social-connections/postpeer/callback` both run the same callback handler so the backend can support either browser redirects or server-to-server provider callbacks. The handler validates the callback signature or shared secret when present, validates the state token, maps the PostPeer platform to a PostDee platform, and upserts the connection for the original user. The callback never trusts a user id sent directly by the provider unless it matches the signed state.

`DELETE /social-connections/:platform` removes the saved PostDee connection for the authenticated user. Provider-side revocation is best-effort and may be added later if PostPeer exposes a revoke endpoint.

## Mobile Components

The existing profile connected-platforms card becomes live. It loads `GET /social-connections`, shows connected counts, and provides a button per supported platform. Tapping connect calls the backend, opens the returned URL with a browser-capable launcher, and refreshes status when the app resumes or the user taps refresh.

The mobile client adds typed models for social connection status and connect URL responses. UI errors should be plain and action-oriented: not signed in, provider not configured, connect failed, or refresh failed. The app must not store PostPeer API keys or account ids as secrets; all sensitive provider calls stay on the backend.

## Publish Flow

1. User signs in with Firebase or the local mock auth path.
2. User connects a social platform through the profile screen.
3. PostPeer completes OAuth and calls the backend callback.
4. Backend stores the PostPeer account id under that `userId` and platform.
5. User creates or schedules a post.
6. Worker publishes each selected platform using the post owner's stored connection.
7. If a selected platform is not connected, only that platform result fails with a clear error; other connected platforms may still publish.

## Security And Data Ownership

The state token must include `userId`, platform, expiry, and a random nonce, signed with a backend-only secret. Callback handling must reject expired, tampered, reused, or platform-mismatched states. Social connections are deleted by account deletion through Prisma cascade or memory-store cleanup.

The mobile app receives only safe display metadata. PostPeer API keys, callback secrets, and connect-client configuration stay in Render environment variables. Logs must not print provider access keys, callback signatures, or full callback payloads when they may contain tokens.

## Error Handling

Unsupported platforms return `400`. Unauthenticated calls return `401`. Missing provider config returns `503`. Provider failures return `502` for connect start. Missing user-owned account ids at publish time become per-platform publish failures so one unconnected platform does not hide the status of connected platforms.

## Testing

Backend tests cover store behavior, route auth/user scoping, callback state validation, connect unavailable/configured cases, account deletion cleanup, and publish-time lookup. Existing post publish tests should gain at least one case proving user A cannot publish with user B's account id.

Mobile tests cover the profile card loading state, connected count, connect button behavior, provider-unavailable message, and refresh after returning from the browser. Verification commands are backend `npm.cmd run test`, `npm.cmd run build`, Prisma validation, and mobile `flutter analyze` / `flutter test` when Flutter is available.
