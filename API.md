# API.md

PostDee backend API reference.

This document describes the current Express + TypeScript API in `apps/api`.
Implemented adapters remain mock-safe for local development, while production
readiness for social publishing, live analytics, Cloudflare R2, real-clip AI
captioning, Pro ElevenLabs + Gemini auto editing, Firebase, Apple App Store, and
Google Play still depends on the provider/device release gates listed below.

## Base URL

Local default:

```text
http://localhost:4000
```

Backend path:

```text
apps/api
```

## Current Status

The backend currently supports:

- Health checks
- Mock or Firebase authentication
- Upload metadata validation, legacy mock/R2/S3 signed upload, managed R2
  multipart sessions, and signed read access scaffolding
- Authenticated config-only publishing preflight, post creation, and queue handoff
- Caption generation through mock, Gemini, or legacy OpenAI providers. The
  product direction is real-clip captioning after a video is selected. Remote
  providers retry transient failures (e.g. a Gemini 503) with backoff. Gemini
  uses the configured primary `gemini-2.5-flash-lite`, then
  `POST /captions/generate` degrades directly to the local template caption;
  no secondary Gemini model is attempted.
- Real-clip caption flow at `POST /captions/generate-from-clip`, with
  Starter/Pro mode selection, authenticated media-key ownership checks,
  optional temporary AI media cleanup, and monthly quota reservation through
  memory or Prisma-backed usage storage.
- Saved templates
- Pro-only analytics summary
- Store subscription verification scaffold for Apple App Store and Google Play
- Store server notification routes for renewal, cancel, refund, and grace-period handoff

The backend must not publish through shared PostPeer account ids in production
(startup rejects them). Production publishing resolves per-user social
connections. The internal `FACEBOOK_REELS` value currently maps to PostPeer's
Facebook Page Video capability, not Facebook Reels. Provider-level approval is
still blocked on broader per-user platform, scheduling, failure-recovery, and
Production tests. One controlled Staging YouTube Shorts Private immediate E2E
passed on 2026-08-10 with a real non-mock external reference; this is not launch
approval for other paths. The repository's Production Blueprint nevertheless
selects `SOCIAL_PUBLISHER=postpeer`; treat that mismatch as a configuration risk,
not evidence that the deployed environment is ready. This change does not alter
the Production Blueprint.

## Authentication

### Mock Auth

Default local mode:

```env
AUTH_PROVIDER="mock"
MOCK_USER_ID="local-dev-user"
```

`AUTH_PROVIDER=mock` is rejected at startup when `NODE_ENV=production`.

Development headers:

| Header | Purpose |
| --- | --- |
| `x-postdee-user-id` | Override the mock user id |
| `x-postdee-email` | Optional mock email |
| `x-postdee-display-name` | Optional mock display name |
| `x-postdee-subscription-plan` | Simulate `BASIC`, `STARTER`, or `PRO` in memory mode |
| `x-postdee-phone-verified` | Use `true` to simulate phone verification |
| `x-postdee-phone-number` | Optional mock phone number |

### Firebase Auth

Production direction:

```env
AUTH_PROVIDER="firebase"
FIREBASE_PROJECT_ID="your-firebase-project-id"
```

Authenticated requests must include:

```http
Authorization: Bearer <firebase-id-token>
```

The backend reads `phone_number` from the verified Firebase ID token and treats it as phone verification for the Basic free quota.

## Plans And Entitlements

This table records the intended package contract, not a claim that every listed
benefit is production-ready. The active paywall must advertise only features
whose complete provider/device flow has passed its release gate.

| Feature | Basic | Starter | Pro |
| --- | --- | --- | --- |
| Price | Free | 199 THB/month | 299 THB/month |
| Phone verification | Required for free quota | Not required for quota | Not required for quota |
| Monthly post units | 3 after phone verification | 120 | 250 |
| Real-time posting | Yes | Yes | Yes |
| Cloud scheduling | No | Yes | Yes |
| Calendar for scheduled posts | No | Yes | Yes |
| AI caption from real clip | No | Audio-only, 50 generations/month implemented; production provider/device verification remains | Audio + selected frames, 120 generations/month implemented; production provider/device verification remains |
| AI auto editing with ElevenLabs + Gemini | No | No | 200 minutes/month implemented; physical-device and provider acceptance remains |
| AI audio review as a separate feature | No | No | No |
| Unified Analytics | No | No | Yes |
| Hashtag radar and AI comment center | No | No | Yes |
| Team and editor access | No | No | Yes |

Important rules:

- Basic users must verify a phone number before using the 3-post free quota.
- Basic users can only post in real time.
- Post units count by platform. One video posted to four platforms uses four
  units.
- Starter users can post immediately, schedule posts, use the calendar, and use
  real-clip AI captioning from audio after a selected clip.
- Pro users currently unlock implemented analytics, visual-frame AI captioning,
  and the ElevenLabs + Gemini auto-editing flow subject to their listed release
  gates. Hashtag radar, AI comment center, and team/editor access remain planned
  package benefits and must not appear as active paywall promises yet.
- Prompt-only caption generation may still exist in the API while the app
  transitions, but it should not be the main paid package promise.
- Secret provider keys must stay on the backend, never inside the Flutter app.

## Standard Error Shape

Most errors follow this format:

```json
{
  "status": "error",
  "code": "PAID_PLAN_REQUIRED",
  "message": "Cloud Scheduling requires the Starter or Pro plan"
}
```

Some validation errors include only `status` and `message`.

## Endpoints

### `GET /health`

Checks whether the API process is running.

Response:

```json
{
  "status": "ok",
  "service": "postdee-api"
}
```

### `GET /publishing/readiness`

Authenticated, side-effect-free configuration gate used before a client starts
new social-post media work.

When the API process is accepting new posts:

```json
{
  "status": "ok",
  "acceptingPosts": true,
  "platformSettingsVersion": 1
}
```

This `200` response means only that `SOCIAL_PUBLISHER` is not `disabled` for
this API process. `platformSettingsVersion: 1` advertises support for the exact
per-platform request shapes documented under `POST /posts`; it is not a provider
capability version. It does not call or verify PostPeer, R2/S3, the publish queue,
a separate BullMQ worker, or the authenticated user's platform connections. It
must not be used as provider-level or launch-readiness evidence.

Deployment order is API-first: apply migration
`20260811130000_add_platform_publish_configuration`, deploy the API, verify this
field is `1`, and only then release a Mobile build that sends the new settings.
Current Mobile checks both `acceptingPosts` and an integer version of at least
`1`; a missing, malformed, or older value fails closed before upload.

When `SOCIAL_PUBLISHER=disabled`, the response is:

```json
{
  "status": "error",
  "code": "SOCIAL_PUBLISHING_UNAVAILABLE",
  "message": "Social publishing is temporarily unavailable. Please try again later."
}
```

The status is `503`. Current mobile clients call this route before watermarking
or `POST /uploads`, but `POST /posts`, `PATCH /posts/:id`, and
`POST /posts/:id/publish-now` repeat the same authoritative check to close the
race between preflight and mutation.

Both the accepting `200` response and disabled `503` response include:

```http
Cache-Control: private, no-store
```

This prevents readiness responses from being stored for reuse. It is defensive
and does not identify caching as the cause of any earlier result.

### `GET /auth/me`

Returns the current authenticated user.

Response:

```json
{
  "status": "ok",
  "user": {
    "id": "local-dev-user",
    "provider": "mock",
    "email": "seller@example.com",
    "displayName": "PostDee Seller",
    "phoneVerified": true
  }
}
```

## Uploads

### `POST /uploads`

Creates either a legacy signed-`PUT` upload or a managed multipart session.
Requires authentication. Uploads are scoped to the current authenticated user;
unauthenticated Firebase-mode requests return `401`.

Request:

```json
{
  "fileName": "demo-video.mp4",
  "contentType": "video/mp4",
  "sizeBytes": 12345678,
  "width": 1080,
  "height": 1920,
  "uploadProtocol": "multipart-v1"
}
```

Validation:

- `fileName` is required.
- `contentType` must start with `video/` or `image/`.
- `sizeBytes` must be positive and no larger than `UPLOAD_MAX_SIZE_BYTES` (default `524288000`, or 500 MiB).
- If `width` and `height` are provided, the media must be vertical 9:16 within a 2 percent tolerance.
- `uploadProtocol`, when present, must be `multipart-v1`.

Mock response:

```json
{
  "status": "ok",
  "upload": {
    "id": "upload-id",
    "fileName": "demo-video.mp4",
    "contentType": "video/mp4",
    "sizeBytes": 12345678,
    "width": 1080,
    "height": 1920,
    "aspectRatio": "9:16",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "storageProvider": "private",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

The legacy R2 or S3 response may also include:

```json
{
  "uploadUrl": "https://signed-upload-url.example",
  "uploadMethod": "PUT",
  "uploadHeaders": {
    "Content-Type": "video/mp4"
  },
  "uploadExpiresAt": "2026-06-05T08:15:00.000Z"
}
```

The legacy R2 signed `PUT` URL signs `Content-Type` and `Content-Length` so the
uploaded object must match the declared metadata. Clients should upload the
same file whose byte length was sent as `sizeBytes`.

When `UPLOAD_PROTOCOL_MODE=dual|multipart` and the client requests
`multipart-v1`, the response instead contains a managed session:

```json
{
  "status": "ok",
  "upload": {
    "id": "opaque-session-id",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "fileName": "demo-video.mp4",
    "contentType": "video/mp4",
    "sizeBytes": 12345678,
    "uploadProtocol": "multipart-v1",
    "partSizeBytes": 16777216,
    "partCount": 1,
    "sessionExpiresAt": "2026-06-05T09:00:00.000Z",
    "storageProvider": "private"
  }
}
```

`UPLOAD_PROTOCOL_MODE` defaults to `legacy`. Production uses `dual` during the
client rollout, so opted-in clients receive managed multipart sessions while
old clients keep receiving the legacy response. In strict `multipart` mode, a
request without the opt-in returns `426 UPLOAD_CLIENT_UPGRADE_REQUIRED`.

### `POST /uploads/:uploadId/parts/:partNumber`

Returns a short-lived signed `PUT` URL for one part of an owned, unexpired
managed session. The server calculates the exact byte length; the response
includes `partNumber`, `sizeBytes`, `uploadUrl`, `uploadMethod`,
`uploadHeaders`, and `uploadExpiresAt`. The client must upload that exact byte
range and retain the storage ETag.

### `POST /uploads/:uploadId/complete`

Completes the managed upload. Every part must be present once, using consecutive
part numbers and the lowercase API field `etag`:

```json
{
  "parts": [
    { "partNumber": 1, "etag": "\"part-etag\"" }
  ]
}
```

Successful completion changes the session to `COMPLETED` and returns the upload
metadata. Only then may its `videoS3Key` be used to create a post.

### `GET /uploads/:uploadId`

Returns the authenticated owner's managed upload metadata and `sessionStatus`
(`UPLOADING`, `COMPLETING`, `COMPLETED`, or `ABORTED`). Clients use this to
resolve an ambiguous completion response without starting a second session. If
R2 completed the object but the database acknowledgement failed, the API checks
the object's exact byte size and safely reconciles the session to `COMPLETED`.

### `DELETE /uploads/:uploadId`

Aborts an owned unfinished multipart session. Account deletion also blocks new
sessions, returns `409 ACCOUNT_UPLOADS_DRAINING` while a fresh completion gets
its drain window, and aborts persisted and R2 orphan multipart uploads before
sweeping the owner's stored objects. Completion and abort state changes use
compare-and-set rules so neither terminal result can overwrite the other.

Legacy signed `PUT` remains available during `legacy`/`dual` rollout and still
has a replay window until strict `multipart` mode is enabled for all clients.

## Posts

Mobile publish drafts are local files, not API resources. The app copies the
draft video, optional cover, and manifest to app-owned Application Support
storage under a stable authenticated user ID (the Firebase UID with real
authentication). Saving a draft does not call this API,
R2, PostPeer/social providers, the publish queue, or post-quota accounting. The
backend therefore has no `PostStatus.DRAFT`; `GET /posts` exposes only server-side
post lifecycle records. Local drafts do not sync between devices and may be
included in an operating-system backup according to device settings.

Do not confuse that local draft with a provider draft. TikTok
`INBOX_DRAFT` and Facebook `PAGE_DRAFT` are delivery choices executed only after
the user presses Post. They perform readiness/upload/post/queue/provider work and
consume a post unit, then leave the resulting media as a draft at that provider.

Migration `20260811130000_add_platform_publish_configuration` adds nullable
`Post.platformSettings` and internal `Post.platformTargets` JSONB snapshots,
plus nullable `PlatformPublish.deliveryOutcome` and internal
`PlatformPublish.providerPostId`. Nullable columns keep existing rows readable;
their compatibility rules are described below.

Supported platform values:

```text
TIKTOK
YOUTUBE_SHORTS
INSTAGRAM_REELS
FACEBOOK_REELS
```

`FACEBOOK_REELS` is retained for mobile/API compatibility. With the current
PostPeer adapter it publishes a Facebook Page Video; it must not be presented as
Facebook Reels in Store copy.

### `GET /posts`

Returns posts for the authenticated user.

Response:

```json
{
  "status": "ok",
  "posts": [
    {
      "id": "post-1",
      "platformResults": [
        {
          "postId": "post-1",
          "platform": "TIKTOK",
          "status": "PUBLISHED",
          "externalPostId": "https://www.tiktok.com/@seller/video/123",
          "deliveryOutcome": "PRIVATE",
          "publishedAt": "2026-07-15T04:00:00.000Z",
          "views": 0,
          "likes": 0
        }
      ]
    }
  ]
}
```

`platformResults` is assembled only from results belonging to the authenticated
user's returned post ids. A failed platform result can contain `errorMessage`;
the response does not expose another user's publish records.

### `POST /posts`

Creates a queued post and hands it to the publish queue.

Request:

```json
{
  "caption": "Try this product today. #PostDee",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
  "coverFrameTimeMs": 4200,
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "scheduledAt": "2026-06-06T10:00:00.000Z"
}
```

Rules:

- When `SOCIAL_PUBLISHER=disabled`, the route returns `503` with
  `SOCIAL_PUBLISHING_UNAVAILABLE` before managed-upload readiness checks,
  subscription/quota reads, user/post persistence, or queue enqueue.
- `caption`, `videoS3Key`, and at least one valid platform are required.
- `videoS3Key` must be an upload key owned by the authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape returned by `POST /uploads`.
- `coverImageS3Key` is optional. When present, it must be an owner-scoped
  completed JPEG or PNG managed upload no larger than 2 MiB.
- `coverFrameTimeMs` is optional and must be a non-negative 32-bit integer. It
  records the selected source-video frame in milliseconds.
- A managed multipart upload must have status `COMPLETED` before its
  `videoS3Key` or `coverImageS3Key` can be used. Legacy owner-scoped video keys
  remain accepted only while the server is in `legacy` or `dual` rollout mode.
- If `scheduledAt` is present, it must use the RFC 3339 shape
  `YYYY-MM-DDTHH:mm:ss(.fraction)?(Z|±HH:mm)` with a valid calendar date and
  timezone. The API normalizes it to UTC. It must be strictly after the server's
  current time, cannot be more than 30 days ahead, and the user must be Starter
  or Pro.
- Basic users must have a verified phone number before using the free quota.
- Basic is limited to 3 post units per month after phone verification.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Repeated platform values are collapsed before quota accounting, persistence,
  and queueing. Post units count unique selected platforms, not post rows.
- The monthly-unit check and post insert are one atomic store operation; Prisma
  uses a serializable transaction and retries write conflicts before rechecking.

Worker behavior:

- The publish worker claims a post by moving it from `QUEUED` to `PUBLISHING`
  before calling the platform publisher.
- PostPeer `202 pending/publishing` is not treated as success. The adapter polls
  `GET /v1/posts/{postId}` for roughly two minutes and records `PUBLISHED` only
  when the selected platform has a real `platformPostUrl` or `platformPostId`.
  It never fabricates an external id.
- A provider call is retried only for an explicitly safe error proving that no
  external post was accepted. A network/timeout or uncertain PostPeer outcome is
  not submitted again; clients must check the platform before a manual retry.
- Retry or duplicate jobs are skipped when the post is already `PUBLISHING`,
  `PUBLISHED`, `PARTIAL_PUBLISHED`, or `FAILED`.
- Stale scheduled jobs are skipped when the job `runAt` no longer matches the
  post's current `scheduledAt`, such as after a reschedule.
- Optional R2/S3 cleanup after a fully successful publish is best-effort. A
  cleanup failure is returned in the worker result, but the post stays
  `PUBLISHED`.
- Cover delivery follows platform capability: Instagram receives the signed
  cover image or frame offset, Facebook Page Video receives the signed image,
  TikTok Direct Post receives the selected frame time, and YouTube Shorts does
  not receive a custom thumbnail.
- Create is database-first. The API commits one deterministic, owner-scoped
  `QUEUED` post for a supplied `clientRequestId`, then enqueues it. If enqueue
  fails, the API returns `503 PUBLISH_QUEUE_UNAVAILABLE` but deliberately keeps
  that durable post row. A later request with the same key and matching intent
  finds the row and calls `ensureEnqueued` to repair a missing/unhealthy job.
  It does not create or charge a second post.
- Reschedule and publish-now also update the owned `QUEUED` row first with a
  compare-and-set guard, then replace the queue job. A queue failure attempts a
  conditional rollback only while the persisted schedule still equals the
  transition made by that request; it never overwrites a state that has already
  advanced.
- The mobile readiness preflight normally prevents a new upload while social
  publishing is disabled. An old client or a configuration race can still have
  uploaded media before this route returns `503`; the route does not delete that
  pre-existing object, so the temporary-media cleanup policy must remove it.

Local-only request override:

```json
{
  "subscriptionPlan": "PRO"
}
```

This override is accepted only in local mock development. In `NODE_ENV=production`,
the backend rejects request-body plan overrides with
`SUBSCRIPTION_PLAN_OVERRIDE_DISABLED`.

Production should use the subscription store, not request-body overrides.

Success response:

```json
{
  "status": "ok",
  "post": {
    "id": "post-id",
    "userId": "local-dev-user",
    "caption": "Try this product today. #PostDee",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
    "coverFrameTimeMs": 4200,
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "platformSettings": {
      "TIKTOK": { "publishMode": "INBOX_DRAFT" },
      "YOUTUBE_SHORTS": {
        "title": "Launch walkthrough",
        "visibility": "private",
        "madeForKids": false,
        "containsSyntheticMedia": false,
        "communityGuidelinesCertified": true
      }
    },
    "scheduledAt": "2026-06-06T10:00:00.000Z",
    "status": "QUEUED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  },
  "publishJob": {
    "id": "job-id",
    "queueName": "publish-posts",
    "postId": "post-id",
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
    "runAt": "2026-06-06T10:00:00.000Z",
    "status": "SCHEDULED",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

The first successful request returns HTTP `201`. A retry with the same supplied
`clientRequestId` and matching publishing intent returns HTTP `200`, includes
`"idempotentReplay": true`, and returns the already-persisted post (plus a
repaired/current job when the post is still `QUEUED`). Reusing a committed key
for a different recognized publishing intent, including changed platform
settings, returns HTTP `409` with
`IDEMPOTENCY_KEY_REUSED`. Replaying a post that has already reached terminal
`FAILED` returns HTTP `409` with `IDEMPOTENT_POST_FAILED` and its `postId`; it is not
reported as newly queued. The social-publishing kill switch remains
authoritative and returns `503` without repairing a replay while disabled.

This protects the post row and quota count, not uploaded objects. The local
draft currently persists the request ID but not completed remote video/cover
keys. After a lost response, Mobile can upload replacement objects before the
API returns the existing post; those unused objects require an explicit
temporary-media cleanup/lifecycle policy before production.

Legacy Post rows whose new JSON columns are null normalize to the historical
settings above. Legacy queued rows with no target snapshot still resolve the
current connected account at execution time, so inspect or drain that backlog
before activating Phase 2/PostPeer; they do not gain immutable-target safety
retroactively. Existing platform results with null `deliveryOutcome` remain
readable but cannot prove whether the old delivery was live, private, unlisted,
or a provider draft.

Basic user without phone verification:

```json
{
  "status": "error",
  "code": "PHONE_VERIFICATION_REQUIRED",
  "message": "Phone verification is required to use the Basic free post quota"
}
```

Post limit reached:

```json
{
  "status": "error",
  "code": "POST_LIMIT_REACHED",
  "message": "Basic plan is limited to 3 post units per month"
}
```

### `PATCH /posts/:id`

Reschedules an authenticated user's queued post. Body:
`{ "scheduledAt": "<ISO-8601 date>" }`. The route returns the updated `post`,
returns `404` for a missing/non-queued user-owned post, and returns `503` when
the publish queue cannot be rescheduled. The timestamp uses the same strict RFC
3339 contract as post creation, must be in the future, and must be no more than
30 days after the server's current time. When social publishing is disabled it
returns `503 SOCIAL_PUBLISHING_UNAVAILABLE` before reading or changing the post
or queue schedule.

### `DELETE /posts/:id`

Deletes an authenticated user's scheduled/queued post and removes its publish
job. Returns `{ "status": "ok" }` or `404` when no user-owned post is found.
This cancellation route remains available while social publishing is disabled,
so queued or scheduled records can be removed safely.

## Devices And Social Connections

### `POST /devices`

Registers the authenticated user's FCM token. Body:
`{ "token": "...", "platform": "IOS|ANDROID|WEB" }`; `platform` is optional.

### `GET /social-connections`

Lists the authenticated user's saved PostPeer connections.

### `POST /social-connections/:platform/connect`

Creates/loads the user's PostPeer profile and returns `{ connectUrl }` for the
requested supported platform.

For a new Firebase identity, the API ensures the local `User` row before saving
the foreign-keyed PostPeer profile. Profile creation sends PostPeer a required,
stable HMAC-derived pseudonymous name and does not send the Firebase UID, email,
phone, or display name. Concurrent same-user profile creations are coalesced
inside one API instance. New profiles use a versioned 128-bit HMAC name. A
single legacy 40-bit profile can be repaired only with the temporary,
operator-supplied fingerprint and exact profile id described below; legacy
profiles are never selected by the short name alone. The database exclusively
claims each PostPeer profile id for one user. A conflicting claim returns
`409 SOCIAL_CONNECTION_CONFLICT` without exposing either user's identity or
the provider profile id. If competing requests create different provider
profiles for the same user, the previously claimed database mapping remains
authoritative.

### `POST /social-connections/refresh`

Polls the user's PostPeer profile integrations after the browser OAuth flow,
then upserts connected platforms and removes stale local connections. PostPeer
does not call a signed-state callback in the current implementation.

### `DELETE /social-connections/:platform`

Disconnects the authenticated user's platform using the stored, user-scoped
PostPeer integration id. The provider integration is removed first and the
local record is deleted only after provider success; provider `404` and a
repeated request with no local record are treated as successful idempotent
cleanup. If provider cleanup is unavailable or fails, the route returns
`503 SOCIAL_CONNECTION_UNAVAILABLE` or `502 SOCIAL_CONNECTION_FAILED` and
keeps the local record so a refresh cannot silently recreate a connection the
user believed was removed.

## Account

### `GET /account/deletion-readiness`

Checks that Firebase identity deletion, owner-prefix media cleanup, and any
stored PostPeer profile cleanup are configured before the mobile app starts
Apple reauthentication. Returns
`{ "status": "ok", "identityAlreadyDeleted": false }` or a retryable `503`
without changing account data. `identityAlreadyDeleted=true` lets the mobile
app finish an idempotent retry without repeating Apple reauthentication.
If a stored PostPeer profile exists but provider cleanup is not configured,
the endpoint returns `503 ACCOUNT_SOCIAL_CLEANUP_UNAVAILABLE`.

### `DELETE /account`

Permanently deletes the authenticated user's account, owned upload objects,
Firebase identity, and user-scoped application data. This backs the App Store /
Google Play required "Delete Account" flow in the profile screen.

Production currently keeps `FIREBASE_AUTH_DELETE_ENABLED=false`; the endpoint
therefore fails closed before cleanup. The behavior below documents the
controlled/test path and must not be treated as launch readiness until the
durable full-user mutation barrier and drain are implemented.

Behavior:

- Marks the managed-upload owner as deleting before cleanup starts. This marker
  is durable for the managed-upload prefix, while the current process-local
  coordinator serializes authenticated API mutations and RevenueCat webhook
  application only inside one API process. A mutation already running in another
  process can pass the durable-marker check before deletion starts and commit
  afterward. The
  publish worker atomically claims a due job, then checks the marker before
  calling a provider without a lease spanning that call. This endpoint is not
  production-safe until the full mutation-drain gap below is closed.
- Cancels any queued or scheduled publish jobs for the user's posts.
- Lists every paginated integration in the user's PostPeer profile and
  disconnects each one through the provider before deleting local records.
  This includes integration ids for platforms PostDee does not yet recognize.
  Provider cleanup failure returns `503 ACCOUNT_SOCIAL_CLEANUP_FAILED` so the
  request can retry without losing local account data.
- A fresh multipart completion gets a short drain window and returns
  `409 ACCOUNT_UPLOADS_DRAINING` so the caller can retry. A stale completion is
  reconciled against the R2 object's exact size before persisted and orphan
  multipart sessions are aborted.
  Another upload cleanup failure returns `503 ACCOUNT_MEDIA_CLEANUP_FAILED`.
- Deletes every object under the exact owner prefix
  `uploads/<encoded-firebase-uid>/` before deleting database records. A storage
  cleanup failure returns `503 ACCOUNT_MEDIA_CLEANUP_FAILED`, leaving the
  account records available for retry. Cleanup attempts every listed object;
  because external object deletion is not transactional, some objects may
  already be gone when a retryable error is returned.
- With Prisma stores, deletes the `User` row; `onDelete: Cascade` removes every
  related row in one step.
- With in-memory stores, each store drops the user's records.
- When Firebase auth is used in a controlled environment,
  `FIREBASE_AUTH_DELETE_ENABLED=true` and `FIREBASE_SERVICE_ACCOUNT_JSON` are
  required. Firebase identity is deleted
  last. Active identities must present an ID token whose `auth_time` is no more
  than five minutes old or receive `403 ACCOUNT_REAUTHENTICATION_REQUIRED`.
- `auth/user-not-found` is treated as an idempotent success. Other Firebase
  failures return `503 ACCOUNT_IDENTITY_DELETE_FAILED`; retrying the same
  request completes identity deletion after the already-idempotent data cleanup.
  The account-only verifier accepts a still-valid signed token when (and only
  when) Firebase Admin confirms that the UID is already missing; revoked tokens
  remain rejected.
- If Firebase identity deletion is not enabled, the endpoint returns
  `503 ACCOUNT_DELETION_UNAVAILABLE` before changing any data.
- On iOS/macOS, the mobile flow calls the readiness endpoint, reauthenticates
  Apple-linked users, and calls Firebase `revokeTokenWithAuthorizationCode`
  before deletion. Apple Sign-In must remain unavailable on Android/web until a
  server-side Apple token revocation flow is implemented there.
- Late active RevenueCat webhooks are acknowledged and ignored when the
  PostDee user row no longer exists, so a renewal cannot recreate a deleted
  account.

Success response:

```json
{
  "status": "ok"
}
```

## Captions

### `POST /captions/generate`

Generates a Thai affiliate-style caption from 1 or 2 keywords.

Requires Starter or Pro. Each keyword must be 80 characters or fewer. Successful
generations reserve one monthly AI caption generation from the Starter/Pro
quota; quota exhaustion returns `429` with code `AI_CAPTION_QUOTA_REACHED`.

Current note: this endpoint is still the legacy prompt/keyword caption
scaffold. New UI should prefer `POST /captions/generate-from-clip` after a
clip is selected. Optional user text should become extra guidance after clip
selection, not the main sold workflow.

Request:

```json
{
  "keywords": ["skincare", "sensitive skin"]
}
```

Response:

```json
{
  "status": "ok",
  "caption": "Generated caption text",
  "hashtags": ["#PostDee", "#Affiliate"],
  "affiliateLinkPlaceholder": "[Affiliate link placeholder]",
  "model": "gemini-2.5-flash-lite",
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49
  }
}
```

Current providers:

```env
CAPTION_PROVIDER="mock"
CAPTION_PROVIDER="gemini"
CAPTION_PROVIDER="openai"
```

Gemini production direction:

```env
CAPTION_PROVIDER="gemini"
GEMINI_API_KEY="..."
GEMINI_CAPTION_MODEL="gemini-2.5-flash-lite"
```

### `POST /captions/generate-from-clip`

Generates a mock-safe AI caption package from a selected clip key.

Requires Starter or Pro.

- Starter uses `AUDIO_ONLY` mode and is limited to 50 generations/month.
- Pro uses `AUDIO_WITH_FRAMES` mode and is limited to 120 generations/month.
- Each successful generate/change request counts as one generation.
- Local development can keep quota usage in memory with
  `CAPTION_USAGE_STORE=memory`. Production should use
  `CAPTION_USAGE_STORE=prisma` so monthly usage survives API restarts.
- It uses `videoS3Key`, optional `guidance`, optional `selectedFrameKeys`, and
  optional `deleteAfterUse`.
- `videoS3Key` and any `selectedFrameKeys` must be upload keys owned by the
  authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape
  returned by `POST /uploads`.
- When the mobile app uploads media only for AI captioning, it sends
  `"deleteAfterUse": true`; the backend then attempts to delete the clip and
  selected frames after the request. Cleanup failures are logged but do not
  block a successful caption response.
- Usage is reserved before the AI provider is called so simultaneous requests
  cannot exceed the monthly quota within the configured usage store.
- Media downloaded for AI processing is capped to protect API memory.
- When `CAPTION_PROVIDER=gemini`, this endpoint sends the clip to Gemini to
  listen and write the caption directly (Starter = audio only; Pro =
  `AUDIO_WITH_FRAMES`, also sending the `selectedFrameKeys` images). Gemini
  retries transient failures on configured-primary `gemini-2.5-flash-lite`,
  then falls back directly to the local template caption, so a caption is
  always returned. No secondary Gemini model is attempted.
- When no Gemini caption provider is configured, it falls back to the legacy path:
  the configured `TRANSCRIPTION_PROVIDER` (ElevenLabs or legacy OpenAI) transcribes the clip
  and a local template builds the caption.
- The auto-editing/subtitle flow uses ElevenLabs because it needs accurate
  timestamps; the caption path prefers Gemini.
- Frame sampling itself (extracting `selectedFrameKeys` from the video) is done
  by the mobile app via FFmpeg, which uploads the frames as images before
  calling this endpoint. Pending real-device verification.
- The active customer flow should not require manual language or market
  selection. Spoken language is inferred from the clip, while `guidance`
  remains the simple override path when a seller wants a specific language,
  market, or style.

Request:

```json
{
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "guidance": "focus on the opening hook",
  "selectedFrameKeys": [
    "uploads/local-dev-user/frame-upload-1/demo-1.jpg",
    "uploads/local-dev-user/frame-upload-2/demo-2.jpg"
  ],
  "deleteAfterUse": true
}
```

Starter response example:

```json
{
  "status": "ok",
  "model": "local-real-clip-template",
  "caption": "Caption option A",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"],
  "hooks": ["Hook A", "Hook B", "Hook C"],
  "hashtags": ["#PostDee", "#ShortVideo"],
  "seoKeywords": ["short video", "affiliate seller"],
  "searchTitle": "Best moments from demo-video.mp4",
  "context": {
    "selectedCaptionLanguage": "Thai",
    "selectedTargetMarket": "Thailand",
    "selectedTone": "auto",
    "detectedSpokenLanguage": "th",
    "suggestedCaptionLanguage": "Thai",
    "suggestedTargetMarket": "Thailand"
  },
  "source": {
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "mode": "AUDIO_ONLY",
    "selectedFrameCount": 0
  },
  "quota": {
    "limit": 50,
    "usedThisMonth": 1,
    "remainingThisMonth": 49
  }
}
```

Quota reached:

```json
{
  "status": "error",
  "code": "AI_CAPTION_QUOTA_REACHED",
  "message": "Starter is limited to 50 real-clip AI caption generations per month",
  "quota": {
    "limit": 50,
    "usedThisMonth": 50,
    "remainingThisMonth": 0
  }
}
```

Production direction:

The paid caption flow should return SEO fields in the same AI call where
possible:

```json
{
  "seoKeywords": ["keyword 1", "keyword 2", "keyword 3"],
  "searchTitle": "Search-friendly short video title",
  "captionOptions": ["Caption option A", "Caption option B", "Caption option C"]
}
```

These SEO fields are returned by the new mock-safe real-clip scaffold, but the
AI provider still needs real clip audio/frame inputs before production launch.

## Removed Legacy AI Clip Review Endpoint

`POST /clip-reviews` is no longer mounted in the app.

Reason:

- It overlapped with AI caption from the real clip.
- It exposed confusing package flags such as AI audio review and AI video review.
- The current product plan sells real-clip captioning and Pro ElevenLabs + Gemini
  auto editing instead.

Current behavior:

- Requests to `/clip-reviews` return `404`.
- `canUseAiAudioReview` and `canUseAiVideoReview` are kept as compatibility
  fields in subscription responses, but they are always `false`.
- The old route, UI, config, and internal mock/provider files have been
  removed.

Future SEO direction: Starter real-clip captioning should be based on audio
understanding. Pro real-clip captioning should combine audio and selected visual
frames where useful.

## AI Auto Editing

All `/ai-edits/*` endpoints require auth. `POST /ai-edits/transcribe`,
`POST /ai-edits/prepare`, and `POST /ai-edits/plan` require the `PRO` plan
(otherwise `402` with `code: "PRO_REQUIRED"`); `GET /ai-edits/quota` is
available to any authenticated user.

### `POST /ai-edits/transcribe`

Transcribes uploaded analysis audio (Thai). Meters usage against a monthly minute quota
(`200` min); returns `402` `AI_EDIT_QUOTA_EXCEEDED` when exhausted. The client
`durationSeconds` is the client-probed media duration used for pre-check and
timeline recovery. Before returning success, the backend reserves minutes from
the longer valid value between media and provider-transcript duration, so an
early provider endpoint cannot reduce usage and concurrent requests cannot push
usage past the configured store limit. The response still reports the raw
provider transcript duration. Current clients send ordered
`audioChunks`; legacy clients may send one `audioS3Key` or `videoS3Key`.
Exactly one of those three media forms is required. Response includes
`transcript` (text, language, durationSeconds, segments[], words[]) and `quota`.
The ElevenLabs adapter requests word-level timing plus non-speech audio-event
tags and sends no free-form spelling prompt. Segment responses retain optional `avgLogprob`,
`noSpeechProbability`, and `compressionRatio` quality signals when the provider
returns them.
Provider timing is audited as one complete timeline before AI editing may use it.
The API can retain a valid display subset for diagnostics, but one malformed,
missing, overlapping, backwards, or out-of-range timed event marks the complete
timeline untrusted. Partial evidence must not authorize subtitles, highlight
planning, repeated-speech cleanup, or silence removal.

If the configured transcription provider is unavailable, both this endpoint and
`POST /ai-edits/prepare` return `502` JSON without reserving quota:

```json
{
  "status": "error",
  "code": "AI_TRANSCRIPTION_PROVIDER_FAILED",
  "message": "AI transcription is temporarily unavailable"
}
```

Provider response details and credentials are never included in the client
response. A temporary uploaded analysis-audio object is still cleaned up by the
route's normal `finally` path.

### `GET /ai-edits/quota`

Reports `{ limitMinutes, usedMinutes, remainingMinutes }` for the current month.

### `POST /ai-edits/prepare`

Builds the UI-facing mobile render recipe for the AI editing screen. This is the
backend contract for the Claude Design flow: the app sends the selected clip,
chosen style/prompt, and capability toggles such as `subtitle`, `silence`,
`filler`, `hook`, `zoom`, `color`, `cta`, `pricetag`, and `watermark`.
Current mobile clients start every optional capability off and explicitly send
`false` for capabilities the user did not enable. A request with every optional
capability disabled remains valid when the user wants only target-length
shortening; recipe consumers must not infer subtitle, silence, repeated-speech,
or colour work from provider data when its matching toggle is false.

This endpoint is Pro-gated and minute-metered like `/ai-edits/transcribe`: the
client `durationSeconds` is the media timeline estimate, the backend transcribes
the stored clip and builds the requested edit plan/recipe. It atomically reserves
minutes from the longer valid media/transcript duration only when at least one
requested analysis outcome is usable. Repeat-only, subtitle-only, or
silence-only requests whose timing evidence is unavailable return a diagnostic
recipe without consuming minutes. A safe silence analysis is successful even
when it finds no candidate. Failed planners and invalid recipes do not consume
quota; the final conditional reservation still prevents concurrent requests
from exceeding the monthly limit. That same longer duration is used by the
planner and `recipe.transcript.durationSeconds`, while word/segment endpoints
retain their provider timestamps. It does **not** render video on the server;
mobile still renders/export with FFmpeg.

Current mobile clients split source audio into balanced chunks no longer than
30 seconds. Every chunk is created through `POST /uploads` with `.m4a`,
`audio/mp4`, `purpose=ai-edit-audio`, no dimensions, and a maximum size of
25 MiB. The client sends ordered `audioChunks` with the source-relative start
time of every chunk. The first start must be zero; keys must be unique,
user-owned, ordered, and limited to 40 chunks. The backend transcribes chunks
sequentially and shifts their local word/segment timestamps onto the source
timeline. If shifting would clip or drop any timing at a chunk boundary, the
merged timeline is marked untrusted instead of treating the clipped subset as
safe editing evidence. The route still cleans every temporary chunk, and any
successful metered prepare reserves usage at most once for the combined request.
`durationSeconds` must describe the source clip for the quota
pre-check, not the requested output length. It is currently supplied by the
official client and combined with the provider timeline; server-side media
probing and an API-side 600-second ceiling remain required before public
tamper-resistant billing. All owned chunks are deleted in the cleanup path even if a later
provider call fails. Legacy clients may send exactly one `audioS3Key` or one
`videoS3Key`; legacy video objects are not auto-deleted. Sending multiple media
forms or no media form is rejected.

`targetDurationSeconds` is an optional positive desired result length. It is
separate from `durationSeconds`, which is the source-duration/quota estimate.
Current mobile clients accept sources up to 10 minutes and use one slider from
5 seconds to at most 3 minutes (or from 1 second when the source is shorter than
5 seconds), capped by the source length. They omit the target at the rightmost
“keep original” position. When a target is present, the edit planner selects
one strongest continuous story window from reliable transcript segments and
returns the complementary ranges to remove. Provider prompt leakage and segments
that cross the configured provider/segment quality thresholds are
excluded from highlight scoring and from rendered subtitle lines. Their timing
still remains available to silence detection so uncertain speech is not mistaken
for a silent gap. Thai-first transcripts containing clearly unexpected scripts
(for example Cyrillic/Hangul/Han replacement noise) are rejected by the same gate,
while ordinary Latin product or place names remain allowed.

Request:

```json
{
  "audioChunks": [
    {
      "audioS3Key": "uploads/local-dev-user/upload-id/postdee-ai-edit-audio-000.m4a",
      "startSeconds": 0
    },
    {
      "audioS3Key": "uploads/local-dev-user/upload-id/postdee-ai-edit-audio-001.m4a",
      "startSeconds": 25
    }
  ],
  "durationSeconds": 65,
  "targetDurationSeconds": 30,
  "styleId": "flash_sale",
  "prompt": "เหลือ 45 วิ เน้นตอนพูดราคา",
  "capabilities": {
    "subtitle": true,
    "silence": true,
    "filler": true,
    "hook": false,
    "beatsync": false,
    "reframe": false,
    "zoom": false,
    "color": true,
    "sfx": false,
    "audio": false,
    "translate": false,
    "pricetag": false,
    "cta": false,
    "watermark": false
  },
  "settings": {
    "silencePreset": "balanced",
    "speechReductionMode": "auto",
    "subtitleWordsPerLine": 3,
    "subtitleColor": "#FFFFFF",
    "subtitleOutlineColor": "#000000",
    "subtitleNormalizedX": 0.5,
    "subtitleNormalizedY": 0.88,
    "ctaText": "กดตะกร้าเลย",
    "priceText": "99 บาท",
    "watermarkText": "Meena Shop",
    "toneFilter": "warm",
    "zoomLevel": "medium",
    "music": {
      "source": "original",
      "beatIntensity": "balanced",
      "volume": 0.25,
      "ducking": {
        "enabled": true,
        "musicVolumeDuringSpeech": 0.12
      }
    }
  }
}
```

If a client loses the prepare response after uploading analysis audio, it may
call `POST /ai-edits/audio/cleanup` with `{ "audioS3Key": "..." }`. Cleanup is
authenticated, owner-scoped, and idempotent. Chunked clients call it once for
each orphaned chunk.

When a client explicitly supplies capabilities but selects neither planning,
subtitles, silence analysis, nor repeated-speech analysis, the endpoint stops
before transcription and returns `400`:

```json
{
  "status": "error",
  "code": "AI_EDIT_NO_ANALYSIS_REQUESTED",
  "message": "เลือกงาน AI ที่ต้องการก่อนเริ่มวิเคราะห์"
}
```

This includes explicit empty and colour-only requests. Color-only edits at
original duration render locally for Pro users and do not consume AI editing
minutes. After checking the local Pro entitlement, the official mobile client
routes only that colour adjustment to `localRenderOnly`. It builds a cut-free,
full-duration recipe and renders the original source without extracting audio,
uploading media, calling `/ai-edits/prepare`, or changing the minute balance.
Colour plus a shortened target, subtitles, silence cleanup, or repeated-speech
cleanup stays on the normal audio/API route. Any unknown enabled capability
fails closed before these side effects. A local retry repeats only rendering,
and accepted source A remains active if a source B render fails. The output name
uses `_subtitled.mp4` only when real subtitle content exists; otherwise it uses
`_edited.mp4`. Temporary owned audio is still cleaned on the API rejection path.
A legacy request that omits the entire `capabilities` field remains metered for
backward compatibility. Output codec, FPS, file size, audio peak, and A/V sync
are phone-renderer acceptance evidence and remain pending device-matrix checks;
the API response does not claim those measurements are complete.

When a style, prompt, or target length needs transcript timing but that timing
cannot be verified, the endpoint stops before planning, recipe creation, or
quota reservation and returns `422`:

```json
{
  "status": "error",
  "code": "AI_EDIT_TIMING_EVIDENCE_UNAVAILABLE",
  "message": "Transcript timing evidence is unavailable"
}
```

`settings.subtitleWordsPerLine` accepts an explicit integer from 1 through 5;
the current setup presets use 1, 3, and 5. Text and outline colours must be
`#RRGGBB`. `subtitleNormalizedX` and `subtitleNormalizedY` are optional but must
be sent together as finite values from 0 through 1. The normalized position is
the canonical subtitle centre and takes precedence over legacy
`subtitlePosition`. Invalid explicit subtitle settings return HTTP `400` with
`code: "INVALID_AI_EDIT_SETTINGS"` before transcription or quota reservation.

Response includes:

- `recipe.renderMode: "mobile-ffmpeg"`
- `recipe.transcript` with text, language, duration, raw `segments`, `words`,
  repaired `boundarySegments`, and model. Current responses always include the
  boundary array; it is built only from the complete strict/reliable transcript
  timeline and stays empty when that evidence cannot be proven.
- `recipe.subtitles` for mobile subtitle burn-in. When subtitles are enabled,
  current responses may also include optional `variants` keyed by `"1"`,
  `"3"`, and `"5"`. All three variants are built from the same validated
  transcript in one prepare request; `segments` remains the selected variant
  for backward compatibility.
- `recipe.cutRanges` with executable planner/repeated-speech cuts,
  `silenceRanges` as internal transcript-gap candidates, and legacy-compatible
  `fillerRanges`. Transcript gaps are silence candidates only. The Android/iOS
  client confirms each candidate against the source waveform before rendering;
  failed or ambiguous verification keeps the original audio. Candidates are
  never folded into `cutRanges` by the API. The client intersects them with
  FFmpeg waveform silence, applies safety padding, rejects source edges and
  protected speech, and sends only verified intersections to its local renderer.
- optional `recipe.speechReduction` with stable repeated-word groups,
  occurrences, recommendations, and `defaultCutRanges`
- `recipe.analysisOutcomes`, with `plan`, `subtitle`, `silence`, and
  `speechReduction` set to `not-requested`, `succeeded`, or `unavailable` from
  the actual result. The API uses this field for its quota decision; clients
  must not infer billing from enabled toggles alone. The legacy fixed-filler
  path counts as succeeded only when it produces a real safe filler range.
- `recipe.plan`, including transcript-selected cuts, a short summary, and the
  planner model identifier
- `recipe.overlays` for future CTA, price tag, and watermark processors; the
  current production mobile renderer does not apply these hints.
- `recipe.renderHints` for tone and future zoom settings. Hook removal is not
  emitted by the current recipe builder yet.
- `recipe.music` with the validated source (`auto`, `library`, `device`, or
  `original`), optional genre/library track reference, beat intensity, volume,
  and voice-ducking preferences
- `recipe.capabilities`, where each requested UI capability is marked
  `applied`, `hinted`, `planned`, or `skipped`
- `quota` with `{ limitMinutes, usedMinutes, remainingMinutes }`

`recipe.transcript.boundarySegments` is independent of
`recipe.subtitles.segments`: it provides source-timeline sentence boundaries
for cut alignment and does not enable or render subtitles. Mobile can therefore
align a shortened result while the subtitle capability is off. Older payloads
without this field are parsed as an empty boundary list, never as raw
`transcript.segments`. When boundaries are missing or rejected, mobile preserves
the planner cut unchanged and shows a warning instead of inventing a new cut.
Valid raw segments, global words, and validated segment words remain separate
conservative protected-speech evidence.

Each `recipe.subtitles.segments[]` keeps the compatibility fields `text`,
`start`, and `end`, and may also contain authoritative `words[]`. Every word is
`{ word, start, end }` on the source timeline. An absent `words` field means a
legacy response; a present empty array means the server deliberately rejected
word timing; a non-empty array is used only after every item and the complete
cue reconstruction pass validation. Reconstruction is exact and case-sensitive
after removing only untimed whitespace, punctuation, and symbols; canonically
different Unicode text fails closed to `words: []`. Clients must not invent
active-word timing when the authoritative array is empty or malformed.
For Thai recipes, provider tokens are expanded at semantic word boundaries and
each multi-token final server cue is limited to at most five semantic words and
20 graphemes. One indivisible brand name, URL, or other token may exceed 20
graphemes rather than being split mid-token; it is emitted as its own cue and is
never merged with neighboring tokens. Minimum-readable-duration and tail merges
may keep a short cue rather than exceed either multi-token limit.

Current mobile builds convert `recipe.subtitles`, transcript metadata, and cut
ranges into a local versioned `SubtitleProject` for Subtitle Studio. Editing,
autosave, live preview, local preview render, reopen, and export reuse this
prepare response; they require no additional API endpoint and consume no extra
AI-edit minutes. Mobile renders and opens result review first; Subtitle Studio
opens only from the explicit review action. Validated cue words drive active-word
preview/export. The response style can carry `outlineColor` and paired
`normalizedX`/`normalizedY`; older responses without them use the legacy
white/black and top/middle/bottom mapping. Edited or unsafe cues use a static
one-line fallback.

Production mobile lets sellers select `subtitle`, `silence`, `filler` (shown as
repeated-speech cleanup), and `sfx`. Every optional switch starts `false`;
target-only shortening remains valid with all optional capabilities off. The
seller-facing `color` and `audio` cards are hidden while their API and
legacy-render compatibility remain intact. `sfx=true` requests a dedicated AI
sound-design analysis in `/ai-edits/prepare`; it is not a manual/local-only
capability.

An executable recipe may contain
`soundEffects: [{"soundId": "coin_ping", "sourceSeconds": 4.0}]`.
`soundId` must be one of the ten bundled PostDee procedural assets and
`sourceSeconds` must exactly match an allowlisted boundary from trusted source
timing. The provider receives only catalog metadata and transcript anchors—no
WAV, asset path, URL, or volume. The complete response is validated atomically,
sorted, and capped at eight; any unknown field, asset, timestamp, duplicate,
malformed JSON, provider failure, or unsafe timing makes the SFX
analysis unavailable with an empty executable list. A valid empty list is a
completed analysis. Mobile assigns the fixed 25% volume and maps source anchors
through the final accepted cuts before local FFmpeg rendering. There is no
seller-facing manual sound picker or placement editor.

Capabilities that need future analysis or rendering, including beat sync, the
opening hook/highlight, auto-reframe, zoom, music choice, audio cleanup,
subtitle translation, price tag, CTA, and the AI-page watermark, are accepted
from older/internal clients but marked `planned` so the UI can stay honest.

`settings.silencePreset` accepts three values and changes the minimum internal
gap between validated word timings that becomes a silence candidate. A complete
reliable segment timeline is used only when safe word evidence is unavailable.
Leading and trailing gaps are excluded. The mobile verifier is the final
authority: successful verification, including an empty result, is cached for
the exact source and timing evidence; failures are not cached. Its retry action
runs only the local waveform probe and local render, without extracting audio,
uploading media, calling this endpoint, or reserving more minutes:

- `natural`: 1.0 second
- `balanced`: 0.6 second (also used when the field is missing or invalid)
- `compact`: 0.4 second

Current mobile has local `AI เลือกให้` and `เลือกเอง` selection modes. Both send
`settings.speechReductionMode: "auto"` and no fixed word list, allowing the same
analysis to be reused without another metered transcription. For a validated
Thai word timeline, the response adds:

- `speechReduction.status`: `ready` or `unavailable`; unavailable timing is
  fail-closed and creates no automatic cuts.
- `groups[]`: the repeated word/phrase and all stable occurrence IDs.
- `occurrences[]`: source start/end, context, repetition kind, recommendation,
  and whether the occurrence is safe to remove.
- `defaultCutRanges[]`: only safe adjacent repeats selected by default.

For Thai repeated-speech detection, character fragments are reconstructed only
when their text matches exact NFC-normalized semantic words in raw provider
order, every fragment stays inside the same reliable segment, and each internal
fragment gap is at most 0.15 seconds. The reconstructed timing is private to
repeat detection and never replaces subtitle word timing. The detector does not
sort damaged evidence, cross an unreliable segment, or bridge a timed audio
event. If any boundary cannot be proven, `speechReduction.status` is
`unavailable`, `unavailableReason` is `fragmented-word-timing` or
`unsafe-word-timing`, and `defaultCutRanges` is empty.

The automatic detector checks repeated one-to-three-word phrases whose two
occurrences are no more than 0.35 seconds apart, removes earlier occurrences,
and preserves the final occurrence. A word found at least three times but
spread through separate sentences is reported as `frequent-only` and kept by
default. Negation, `ๆ`, numbers/prices, sentence boundaries, Thai fragments that
cannot be reconstructed exactly, and incomplete timing are never cut
automatically. AI mode initially
selects `defaultCutRanges`; manual mode initially selects no occurrence. The
mobile review can keep or remove each safe occurrence; unknown or non-removable
IDs are discarded fail-closed. Manual mode also ignores legacy-only
`fillerRanges` so it cannot remove speech before the user chooses.
The mobile build-time repeat rollback keeps these detection groups visible but
read-only, sends no selected occurrence IDs through initial render, review,
subtitle re-render, or export, and applies no legacy or structured repeat cut.
This rollback does not change the API request/response contract.

`settings.fillerWords` is the legacy-client exact allowlist. Supported values are `เอ่อ`,
`อ่า`, `อาฮะ`, `แบบว่า`, `คือว่า`, and `ประมาณว่า`. The backend normalizes NFC and
removes surrounding whitespace, punctuation, and symbols before comparing a
normal transcript word; `เออ` and `อะฮะ` are exact transcription aliases for
`เอ่อ` and `อาฮะ`, but a
longer token such as `เออแล้ว` does not match. When a provider returns a validated Thai
character-token stream, the backend may conservatively reassemble adjacent
fragments that equal an allowlisted filler. Reassembly cannot cross a timing
gap and requires a real gap or verified Thai word/text boundaries; short
prefixes remain stricter. Omitting `speechReductionMode` preserves legacy
behavior and checks the original five words when `fillerWords` is also absent.
Sending `[]`, a non-array value, or
an array that sanitizes to no supported values fails closed and produces no
filler ranges; it does not fall back to the legacy list.
Mobile fits and aligns `recipe.plan.cuts` to the requested story duration first
and only then unions silence and selected repeated-speech cleanup without
shrinking it. The rendered
clip can therefore be slightly shorter than `targetDurationSeconds`, but a
selected cleanup occurrence is never restored merely to fill the requested
duration. When subtitles are enabled, mobile removes the same validated timed
word from subtitle cues before burn-in. If a selected range cannot map to a
complete subtitle word, both the subtitle change and media cut are rejected.
The setup source is pending state, separate from the accepted source/recipe used
by review and export. Mobile commits the active source, duration, recipe,
verified-silence result, subtitle project, capabilities, repeat selection, and
rendered result together only after a successful render. A failed new-source
render therefore cannot pair an old recipe or project with the new file.

Production mobile builds send `hook: false` because
`ENABLE_EXPERIMENTAL_AI_HOOK` defaults to `false`. If an internal or legacy
client sends `hook: true`, the response still marks it `planned`, emits no hook
render hint, and mobile does not reorder the first three seconds. The compile-time
flag exposes setup UI only; it does not enable a renderer.

`settings.music` is additive and optional. Requests that omit it default to
`source: "original"`. A library track is referenced only by an opaque `trackId`.
The current API validates and passes this reference through; a production
catalog resolver with ownership/licensing checks is still required before a
library track can be rendered.
Clients must never send a storage key or absolute device file path to this API.
Receiving music settings does not mean the current renderer has mixed music or
cut on detected beats.

The response is an editable review recipe, not a final server-rendered video.
Mobile may disable recipe capabilities and re-render locally from the original
clip before the user accepts the result. That review loop must reuse the
successful recipe instead of calling this minute-metered endpoint again.
Capabilities marked `planned`, `hinted`, or `skipped` must not be presented as
already applied to the preview.

Mobile derives the review's repeated-speech count from `speechReduction.groups`
and the user's selected occurrence IDs, then merges selected/clamped cleanup
ranges before displaying the detected time.
That summary describes pre-render detections and must not be presented as the
exact duration removed from the exported clip.

After one successful metered prepare, mobile keeps the transcript in memory for
the selected source and settings. Changing only the duration slider calls the
non-metered `/ai-edits/plan` endpoint with that transcript and does not upload
or transcribe the audio again. Changing analysis settings or selecting another
source still requires a new metered prepare.

When the target is shorter than the transcript, current mobile builds create a
whole-duration 360 px MP4 proxy at 1 fps with mono 16 kHz AAC. The upload
must use `purpose=ai-edit-visual-proxy`, `video/mp4`, an `.mp4` name, no client
dimensions, and at most 50 MiB. This is a low-bandwidth representation of the
entire timeline, not a small set of selected still frames. The original source
remains on the device for rendering.

### `POST /ai-edits/plan`

Returns a structured cut plan for an auto-edit style or a free-form prompt,
computed from an already-transcribed clip. Pro-gated but **not** minute-metered.

Local mode uses the rule-based mock (`model: "mock-rule"`). Staging/production
uses `gemini-3.5-flash-lite` for transcript planning and falls back to the
PostDee rules on provider failure. Both transcript and visual GenerateContent
requests require structured JSON and use provider-default sampling without an
explicit `generationConfig.temperature`.

If `visualProxyS3Key` is present, owned by the authenticated user, and a Gemini
key is configured, the API downloads the proxy, uploads it to Gemini Files API,
waits until it is active, and asks Gemini to watch the complete proxy together
with the timestamped transcript. The returned cuts are still clamped to the
requested duration. Any visual download/upload/processing/generation failure
falls back to the configured audio/transcript planner so an otherwise valid edit
does not fail. The R2 proxy and Gemini file are temporary and cleaned
best-effort. Upload, processing-state polling, and deletion use Google's
official `@google/genai` Files client; the edit request still uses the validated
file URI only after Gemini reports the proxy as active.

Request (one of `styleId`, `prompt`, or `targetDurationSeconds` is required):

```json
{
  "styleId": "flash_sale",
  "prompt": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธเธญเธญเธเนเธฅเนเธงเน€เธซเธฅเธทเธญ 15 เธงเธด",
  "durationSeconds": 30,
  "targetDurationSeconds": 15,
  "visualProxyS3Key": "uploads/local-dev-user/upload-id/postdee-visual-proxy.mp4",
  "segments": [{ "text": "เธฃเธฒเธเธฒ 99 เธเธฒเธ—", "start": 3, "end": 6 }]
}
```

- `styleId` โ€” a mobile edit-style id (e.g. `flash_sale`, `qa`, `before_after`,
  `tutorial`, `comedy`); keeps keyword-relevant segments, cuts the rest.
- `prompt` โ€” free-form Thai instruction. The mock understands a target length
  ("เน€เธซเธฅเธทเธญ 45 เธงเธด") and profanity removal ("เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ").

Response:

```json
{
  "status": "ok",
  "plan": {
    "cuts": [{ "start": 10, "end": 12 }, { "start": 17, "end": 30 }],
    "summary": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธ ยท เธขเนเธญเน€เธซเธฅเธทเธญ ~15 เธงเธด",
    "model": "mock-rule"
  }
}
```

`visualProxyS3Key` is optional for old clients and audio-only fallback. A key
outside the authenticated user's upload namespace returns `403`; a non-MP4 key
returns `400`. If upload succeeds but the planning request cannot be sent, the
client may call `POST /ai-edits/visual-proxy/cleanup` with
`{ "visualProxyS3Key": "..." }`.

Visual planning converts Gemini suggestions into one continuous target-length
window and uses timestamped transcript boundaries to avoid opening on common
Thai continuation fragments when a nearby complete sentence has comparable
editorial value. This is a soft ranking rule, not a forbidden-word filter.

`cuts` are absolute-second ranges to remove; the client feeds them into the same
on-device render pipeline used by silence/segment cuts. Returns `400` when
`durationSeconds` is missing or none of `styleId`, `prompt`, or
`targetDurationSeconds` is provided.

## Templates

### `GET /templates`

Returns saved text templates for the authenticated user.

Response:

```json
{
  "status": "ok",
  "templates": []
}
```

### `POST /templates`

Creates a saved text template for the authenticated user.

Request:

```json
{
  "title": "Affiliate disclaimer",
  "body": "This post may contain an affiliate link."
}
```

Response:

```json
{
  "status": "ok",
  "template": {
    "id": "template-id",
    "title": "Affiliate disclaimer",
    "body": "This post may contain an affiliate link.",
    "createdAt": "2026-06-05T08:00:00.000Z"
  }
}
```

## Analytics

### `GET /analytics/summary?range=30d`

Returns a unified analytics summary for the authenticated user.

Requires Pro.

Supported `range` values are `today`, `7d`, `30d`, `90d`, and `year`.
The default is `30d`. Platform publish metrics are filtered by their publish
time (falling back to record creation time) and grouped into UTC date buckets.
The `daily` series therefore attributes the current synchronized totals to the
day each platform publish was created/published; it is not a provider-level
hourly history or a synthetic trend.

Response:

```json
{
  "status": "ok",
  "summary": {
    "range": "30d",
    "totalViews": 0,
    "totalLikes": 0,
    "platforms": [
      {
        "platform": "TIKTOK",
        "label": "TikTok",
        "views": 0,
        "likes": 0
      }
    ],
    "daily": [
      {
        "date": "2026-07-10",
        "views": 0,
        "likes": 0
      }
    ]
  }
}
```

If the user is not Pro:

```json
{
  "status": "error",
  "code": "PRO_REQUIRED",
  "message": "Unified Analytics requires the Pro plan"
}
```

An unsupported range returns `400 INVALID_ANALYTICS_RANGE`.

## Billing And Subscriptions

### `GET /billing/subscription`

Returns the current user's plan and feature flags.

Basic response example:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "BASIC",
    "status": "INACTIVE",
    "monthlyPostLimit": 3,
    "usedPostsThisMonth": 0,
    "remainingPostsThisMonth": 0,
    "phoneVerified": false,
    "requiresPhoneVerification": true,
    "canUseFreePostQuota": false,
    "canSchedule": false,
    "canUseAiCaptions": false,
    "canUseAnalytics": false,
    "canUseAiAudioReview": false,
    "canUseAiVideoReview": false
  }
}
```

After Basic phone verification:

```json
{
  "phoneVerified": true,
  "requiresPhoneVerification": false,
  "canUseFreePostQuota": true,
  "monthlyPostLimit": 3,
  "remainingPostsThisMonth": 3
}
```

Starter response sets:

```json
{
  "plan": "STARTER",
  "status": "ACTIVE",
  "monthlyPostLimit": 120,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 120,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": false,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

Pro response sets:

```json
{
  "plan": "PRO",
  "status": "ACTIVE",
  "monthlyPostLimit": 250,
  "usedPostsThisMonth": 0,
  "remainingPostsThisMonth": 250,
  "canUseAiCaptions": true,
  "canSchedule": true,
  "canUseAnalytics": true,
  "canUseAiAudioReview": false,
  "canUseAiVideoReview": false
}
```

`canUseAiAudioReview` and `canUseAiVideoReview` are legacy compatibility flags
for older clients, but the active API keeps them false. Package copy should use
"AI caption from real clip" instead.

### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when
`BILLING_PROVIDER=revenuecat`.

This endpoint requires:

```http
Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>
```

RevenueCat `app_user_id` must match the PostDee user id. In production this
should be the Firebase uid used by the mobile app. The backend maps RevenueCat
entitlement ids or product ids to PostDee plans, stores the billing id as
`revenuecat:<app_user_id>`, and keeps `GET /billing/subscription` as the single
app-facing entitlement endpoint.

Example request:

```json
{
  "event": {
    "id": "event-id-from-revenuecat",
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "event_timestamp_ms": 1780444800000,
    "expiration_at_ms": 1780531200000
  }
}
```

Success response:

```json
{
  "status": "ok",
  "ignored": false,
  "eventType": "INITIAL_PURCHASE",
  "subscription": {
    "userId": "firebase-user-id",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

Supported active event types include `INITIAL_PURCHASE`, `RENEWAL`,
`PRODUCT_CHANGE`, `UNCANCELLATION`, and `NON_RENEWING_PURCHASE`. `EXPIRATION`
cancels the existing RevenueCat-bound subscription and removes paid access.
Actionable events must include a non-empty event `id` and positive integer
`event_timestamp_ms`. The subscription update and per-user ordering cursor are
committed atomically. A retried event id or a timestamp that is not newer is
acknowledged with `ignored: true` and cannot overwrite newer entitlement state.
`CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE` are acknowledged
without revoking access immediately because the subscription can still be active
until the paid period actually expires. Unknown product or entitlement ids return
`202` with `ignored: true`.

### `POST /billing/revenuecat/resync`

Reconciles a user-initiated RevenueCat restore with PostDee's subscription
store when `BILLING_PROVIDER=revenuecat`. This authenticated endpoint accepts an
empty JSON body and always uses the authenticated PostDee/Firebase uid as
RevenueCat `app_user_id`; any user id
in the request body is ignored. The mobile flow calls RevenueCat
`restorePurchases` first, then calls this endpoint.

The backend requests the subscriber from RevenueCat API v1 using the server-only
`REVENUECAT_REST_API_V1_KEY`. It maps active Starter/Pro entitlements or products,
prefers Pro if both are active, preserves a lifetime entitlement, and respects
entitlement/subscription grace-period expiry. When RevenueCat returns no active
entitlement, only the matching `revenuecat:<uid>` subscription is deactivated;
paid access from another provider is left unchanged. An active but unmapped
entitlement is treated as configuration drift and never downgrades the user.
The subscriber response's positive integer `request_date_ms` advances the same
per-user ordering cursor used by webhooks, in the same serializable transaction
as the subscription change. A snapshot older than, or equal to, the stored
cursor is ignored and the response reports the effective stored plan instead of
claiming that stale snapshot was applied.
For an empty RevenueCat result, top-level `plan` is `BASIC` so the client does
not report a successful Restore; `effectivePlan` separately reports any access
that remains active from another provider. If an empty snapshot is stale,
top-level `plan` also reports that effective stored plan.

If RevenueCat omits `request_date_ms`, the client records the local API receipt
time as the observation timestamp. This fallback requires synchronized server
clocks: clock skew can temporarily make a legitimate webhook appear older.
Distinct observations with the same millisecond timestamp are deliberately
treated as equal, so the later arrival does not overwrite the committed state.

Request:

```http
POST /billing/revenuecat/resync
Authorization: Bearer <Firebase ID token>
Content-Type: application/json

{}
```

Paid response example:

```json
{
  "status": "ok",
  "plan": "PRO",
  "subscription": {
    "userId": "firebase-user-id",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

The route has a fixed per-IP limit of 10 requests per 10 minutes. Errors are:

- `401` when the user is not authenticated.
- `409 REVENUECAT_ENTITLEMENT_NOT_MAPPED` when RevenueCat reports active access
  that does not match the configured Starter/Pro ids; the existing plan is kept.
- `429` when the restore/resync limit is exceeded.
- `501 REVENUECAT_RESYNC_NOT_CONFIGURED` when the server REST key is absent.
- `502 REVENUECAT_RESYNC_FAILED` when RevenueCat cannot be queried or returns an
  invalid response. A provider failure leaves the existing local plan unchanged.

This route is distinct from the webhook: the webhook handles provider lifecycle
events, while resync repairs or confirms state after an explicit user Restore.

### `POST /billing/store/verify`

Legacy direct Apple/Google store verifier. It verifies a mobile store purchase
and activates Starter or Pro when `BILLING_PROVIDER=store` or in local mock
mode. Production should use RevenueCat webhooks instead of this custom verifier.

Default product ids:

```env
STORE_STARTER_MONTHLY_PRODUCT_ID="postdee_starter_monthly"
STORE_PRO_MONTHLY_PRODUCT_ID="postdee_pro_monthly"
```

Android request:

```json
{
  "platform": "ANDROID",
  "productId": "postdee_starter_monthly",
  "purchaseToken": "google-play-purchase-token"
}
```

iOS request:

```json
{
  "platform": "IOS",
  "productId": "postdee_pro_monthly",
  "transactionId": "app-store-transaction-id"
}
```

Response:

```json
{
  "status": "ok",
  "purchase": {
    "provider": "mock-store",
    "platform": "ANDROID",
    "productId": "postdee_starter_monthly",
    "purchaseToken": "google-play-purchase-token",
    "verifiedAt": "2026-06-05T08:00:00.000Z"
  },
  "subscription": {
    "userId": "local-dev-user",
    "plan": "STARTER",
    "status": "ACTIVE"
  }
}
```

The backend stores a provider-neutral billing id:

- Android: `google-play:<purchaseToken>`
- iOS: `apple-app-store:<originalTransactionId>` when available, otherwise `apple-app-store:<transactionId>`

### `POST /billing/mock-success`

Activates Starter or Pro for local scaffold testing.
This endpoint is disabled in `NODE_ENV=production` and when `BILLING_PROVIDER`
is not `mock`.
`BILLING_PROVIDER=mock` is also rejected at startup when `NODE_ENV=production`.

Request:

```json
{
  "plan": "PRO"
}
```

Response:

```json
{
  "status": "ok",
  "subscription": {
    "userId": "local-dev-user",
    "plan": "PRO",
    "status": "ACTIVE"
  }
}
```

This endpoint is for local development only.

## Store Server Notifications

These endpoints support the legacy direct Apple/Google verifier path. The
preferred production billing path is RevenueCat.

### `POST /billing/google-play/notifications`

Receives Google Play Real-time Developer Notifications through a Pub/Sub push payload.

Requires `Authorization: Bearer <GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN>`.

Supported scaffold event types:

- `subscriptionNotification`
- `testNotification`
- `voidedPurchaseNotification`

The scaffold maps clear subscription events to entitlement state only when the purchase token was previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "google-play",
    "eventType": "SUBSCRIPTION_NOTIFICATION",
    "notificationId": "message-id",
    "notificationType": "4",
    "productId": "postdee_pro_monthly",
    "purchaseToken": "purchase-token"
  }
}
```

### `POST /billing/apple/notifications`

Receives App Store Server Notification V2 payloads.

Request:

```json
{
  "signedPayload": "apple-signed-notification-payload"
}
```

The scaffold verifies the signed payload when Apple root certificates and app config are present, extracts transaction ids, and updates subscriptions that were previously bound through `POST /billing/store/verify`.

Response:

```json
{
  "status": "ok",
  "event": {
    "provider": "apple-app-store",
    "eventType": "DID_RENEW",
    "notificationId": "notification-uuid",
    "notificationType": "DID_RENEW",
    "subtype": null,
    "transactionId": "transaction-id",
    "originalTransactionId": "original-transaction-id"
  }
}
```

Current notification mapping highlights:

- Apple `DID_RENEW` activates the subscription.
- Apple `EXPIRED` expires the subscription.
- Apple `REFUND` expires the subscription.
- Apple `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD` keeps the subscription active.
- Apple `DID_FAIL_TO_RENEW` without grace period marks the subscription as past due.
- Google Play cancellation, expiration, revocation, and voided purchase events can downgrade or expire known subscriptions.

## Queue

### `GET /queue/jobs`

Returns queued publish jobs for the authenticated user in local memory mode.
Canceling or rescheduling a queued post also removes or replaces the matching
publish queue job.

Response:

```json
{
  "status": "ok",
  "jobs": []
}
```

Production direction:

```env
PUBLISH_QUEUE="bullmq"
POST_STORE="prisma"
DATABASE_URL="postgresql://..."
REDIS_URL="redis://localhost:6379"
```

`PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` because
the API and worker run in separate processes and must share post state through
PostgreSQL.

## Environment Variables

| Variable | Example | Purpose |
| --- | --- | --- |
| `NODE_ENV` | `production` | Runtime environment; production disables local mock shortcuts |
| `PORT` | `4000` | API port |
| `DATABASE_URL` | `postgresql://...` | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis connection string for BullMQ |
| `AUTH_PROVIDER` | `mock`, `firebase` | Auth adapter |
| `FIREBASE_PROJECT_ID` | `postdee-prod` | Firebase project id |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | `{...}` | Firebase Admin service account JSON for account deletion and revoked-token checks; keep secret |
| `FIREBASE_AUTH_DELETE_ENABLED` | `false`, `true` | Enables the current Firebase identity/account cleanup path and revoked/deleted-token checks; requires the service account. Keep account deletion disabled in Production until the full durable user-mutation barrier/drain gap is closed |
| `PUSH_SENDER` | `mock`, `firebase` | Push sender adapter; keep `mock` until the Firebase sender is verified with the installed Admin SDK |
| `VIDEO_STORAGE` | `mock`, `r2`, `s3` | Temporary video storage adapter |
| `CLOUDFLARE_R2_BUCKET` | `postdee-video-temp` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | `...` | Cloudflare account id |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | `...` | R2 S3-compatible access key id |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | `...` | R2 S3-compatible secret access key |
| `CLOUDFLARE_R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` | Optional custom R2 endpoint |
| `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS` | `300` | Signed upload URL lifetime; legacy retries request one fresh URL after explicit expiry, while multipart retries refresh only the affected part URL |
| `UPLOAD_PROTOCOL_MODE` | `legacy`, `dual`, `multipart` | Upload rollout mode; defaults to `legacy`, production uses `dual` during client migration, and strict `multipart` rejects old clients without the opt-in |
| `MULTIPART_UPLOAD_PART_SIZE_BYTES` | `16777216` | Server-selected managed multipart part size in bytes (16 MiB default) |
| `MULTIPART_UPLOAD_SESSION_EXPIRES_SECONDS` | `3600` | Managed multipart session lifetime in seconds |
| `UPLOAD_MAX_SIZE_BYTES` | `524288000` | Maximum declared upload size accepted by `POST /uploads` |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Per-IP rate limit window in milliseconds |
| `RATE_LIMIT_MAX_REQUESTS` | `300` | Max requests per IP per window; exceeding returns `429` with code `RATE_LIMITED` (`GET /health` is exempt). Tighter fixed per-IP buckets also cover `/auth` (30/10min), `/uploads` (60/hr), `/captions` + `/ai-edits` (60/hr), and `/social-connections` (20/10min) |
| `AWS_REGION` | `ap-southeast-1` | Legacy S3 region |
| `AWS_S3_BUCKET` | `postdee-video-temp` | Legacy S3 bucket |
| `AWS_S3_UPLOAD_EXPIRES_SECONDS` | `900` | Legacy S3 signed upload URL lifetime |
| `CAPTION_PROVIDER` | `mock`, `gemini`, `openai` | Caption provider |
| `GEMINI_API_KEY` | `...` | Gemini API key |
| `GEMINI_CAPTION_MODEL` | `gemini-2.5-flash-lite` | Gemini caption model |
| `GEMINI_EDIT_PLAN_MODEL` | `gemini-3.5-flash-lite` | Gemini visual/transcript edit-planning model |
| `OPENAI_API_KEY` | `...` | Legacy OpenAI API key |
| `OPENAI_CAPTION_MODEL` | `gpt-4o-mini` | Legacy OpenAI caption model |
| `TRANSCRIPTION_PROVIDER` | `mock`, `openai`, `elevenlabs` | AI caption language detection and AI edit transcription provider |
| `ELEVENLABS_API_KEY` | `...` | Server-only ElevenLabs Speech-to-Text API key |
| `ELEVENLABS_TRANSCRIPTION_MODEL` | `scribe_v2` | ElevenLabs batch transcription model |
| `ELEVENLABS_TRANSCRIPTION_KEYTERMS` | empty | Optional comma/newline-separated brand terms; blank avoids the provider keyterm surcharge |
| `WHISPER_MODEL` | `whisper-1` | Legacy OpenAI transcription model |
| `EDIT_PLAN_PROVIDER` | `mock`, `openai`, `gemini` | Brain for `POST /ai-edits/plan`; `mock` is rule-based, the others call an LLM and fall back to mock on failure |
| `OPENAI_EDIT_PLAN_MODEL` | `gpt-4o-mini` | OpenAI chat model for edit planning |
| `BILLING_PROVIDER` | `mock`, `store`, `revenuecat` | Billing verifier adapter |
| `REVENUECAT_WEBHOOK_AUTH_TOKEN` | `...` | Bearer token required by the RevenueCat webhook endpoint |
| `REVENUECAT_REST_API_V1_KEY` | `...` | Server-only secret used to read a subscriber during authenticated restore/resync |
| `REVENUECAT_STARTER_ENTITLEMENT_ID` | `starter` | RevenueCat entitlement mapped to Starter |
| `REVENUECAT_PRO_ENTITLEMENT_ID` | `pro` | RevenueCat entitlement mapped to Pro |
| `REVENUECAT_STARTER_PRODUCT_ID` | `postdee_starter_monthly` | RevenueCat product mapped to Starter |
| `REVENUECAT_PRO_PRODUCT_ID` | `postdee_pro_monthly` | RevenueCat product mapped to Pro |
| `STORE_STARTER_MONTHLY_PRODUCT_ID` | `postdee_starter_monthly` | Starter store product id |
| `STORE_PRO_MONTHLY_PRODUCT_ID` | `postdee_pro_monthly` | Pro store product id |
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.postdee.postdee_mobile` | Android package name |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY_JSON` | `{...}` | Google Play verifier service account JSON |
| `GOOGLE_PLAY_ACCESS_TOKEN` | `...` | Optional Google Play access token |
| `GOOGLE_PLAY_NOTIFICATION_AUTH_TOKEN` | `...` | Bearer token required by the Google Play RTDN endpoint |
| `APPLE_APP_BUNDLE_ID` | `com.postdee.postdeeMobile` | iOS bundle id |
| `APPLE_APP_STORE_ISSUER_ID` | `...` | App Store Server API issuer id |
| `APPLE_APP_STORE_KEY_ID` | `...` | App Store Server API key id |
| `APPLE_APP_STORE_PRIVATE_KEY` | `...` | App Store Server API private key |
| `APPLE_APP_STORE_ROOT_CERTIFICATES_BASE64` | `...` | Root certificates for notification verification |
| `APPLE_APP_APPLE_ID` | `1234567890` | Apple app id |
| `APPLE_APP_STORE_ENVIRONMENT` | `sandbox`, `production` | App Store environment |
| `TEMPLATE_STORE` | `memory`, `prisma` | Template persistence |
| `POST_STORE` | `memory`, `prisma` | Post persistence |
| `SUBSCRIPTION_STORE` | `memory`, `prisma` | Subscription persistence |
| `ANALYTICS_STORE` | `memory`, `prisma` | Analytics persistence |
| `CAPTION_USAGE_STORE` | `memory`, `prisma` | Real-clip AI caption monthly usage persistence |
| `AI_EDIT_USAGE_STORE` | `memory`, `prisma` | AI editing monthly minute usage persistence |
| `PUBLISH_QUEUE` | `memory`, `bullmq` | Publish queue adapter; `bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` |
| `SOCIAL_PUBLISHER` | `mock`, `disabled`, `postpeer` | Local fake success, explicit fail-closed staging/maintenance mode, or real PostPeer publishing. `disabled` makes readiness, post create, post reschedule, and publish-now return `503 SOCIAL_PUBLISHING_UNAVAILABLE`; cancel remains available |
| `SOCIAL_PUBLISH_REQUIRE_EMPTY_BACKLOG` | `false`, `true` | Optional `PUBLISH_QUEUE=memory` activation guard. With `postpeer`, startup runs one atomic global aggregate count with status in `QUEUED` or `PUBLISHING` (including future schedules) before starting the scheduler or listening; a non-zero total or inspection failure blocks startup. Defaults to `false`; Staging sets `true` and Production is unchanged |
| `POSTPEER_API_KEY` | `...` | PostPeer API key for real social publishing |
| `POSTPEER_API_BASE_URL` | `https://api.postpeer.dev` | Optional PostPeer API host override |
| `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` | 64 hex characters | Temporary one-user repair proof: `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`; must be paired with the exact profile id and removed after refresh succeeds |
| `POSTPEER_LEGACY_RECOVERY_PROFILE_ID` | `...` | Exact PostPeer profile id allowed for the temporary legacy repair; must be paired with the fingerprint |
| `POSTPEER_TIKTOK_ACCOUNT_ID` | `abc123` | Operator PostPeer TikTok integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_YOUTUBE_ACCOUNT_ID` | `abc123` | Operator PostPeer YouTube Shorts integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_INSTAGRAM_ACCOUNT_ID` | `abc123` | Operator PostPeer Instagram Reels integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_FACEBOOK_ACCOUNT_ID` | `abc123` | Operator PostPeer Facebook Page Video integration id (internal `FACEBOOK_REELS` compatibility value) used only when no per-user connection resolver is wired; forbidden in production |
| `MOCK_USER_ID` | `local-dev-user` | Default mock user id |

## Production Gaps

The following work is still required before production launch:

- Verify the per-user PostPeer connect/refresh and full publish-result flow with
  connected test accounts before enabling production user publishing; do not
  use shared `POSTPEER_*_ACCOUNT_ID` values in production. Apply the Phase 2
  migration/API first, verify `platformSettingsVersion: 1`, and inspect or drain
  queued legacy-null rows before releasing Mobile.
- Keep TikTok `DIRECT_POST` disabled until creator-info is loaded immediately
  before posting, the account's current privacy/interaction choices and consent
  are represented, and TikTok audit approval is complete. Run controlled
  provider E2E for TikTok `INBOX_DRAFT` and Facebook `PAGE_DRAFT`; confirm the
  provider id/final state without exposing internal ids to clients.
- Complete YouTube compliance/provider verification for title, made-for-kids,
  synthetic-media disclosure, certification, and Private/Unlisted/Public. The
  platform may keep non-private uploads Private until its API audit allows the
  requested visibility.
- Prove immutable target snapshots on immediate and scheduled posts: connection
  replacement/disconnect between review, commit, and worker execution must fail
  closed, while public APIs/logs must redact provider account/post ids.
- Store social access tokens securely only if direct platform APIs replace the
  PostPeer provider later.
- Complete provider-level R2 upload and cleanup testing.
- Close the completed-upload orphan path: a lost create-post response can make
  Mobile upload a new video/cover before an idempotent replay returns the old
  post. Persist/reuse completed remote keys or delete superseded objects, and
  verify the lifecycle rule against real R2 before launch.
- Account deletion is not production-safe: the current process-local coordinator
  cannot drain an authenticated mutation already running in another API instance,
  and the worker does not hold a lease across the provider call. Add a
  durable repository owner barrier/lease (or equivalent transactional
  outbox/claim-and-drain protocol) across every user mutation family. It must
  atomically reject new writes,
  drain in-flight work before the cleanup snapshot, and span worker
  claim/provider critical sections. Test same-process and separate-process races
  before enabling Production deletion, multi-instance API, or a real separate
  worker.
- Run the local-draft, stable-request replay, explicit destination, truthful
  status, future/30-day, and publish-now matrix on physical Android and iPhone
  release candidates and through controlled Staging provider E2E.
- Replace the in-app Privacy Policy and Terms working drafts with finalized,
  hosted legal text, and make Android/iOS backup plus Data Safety/App Privacy
  disclosures match app-owned draft video/cover storage.
- Test real-clip caption/transcription with real R2 videos, Gemini, and ElevenLabs before
  production launch. Mobile frame extraction/upload (up to 3 frames) is
  implemented and still needs real-device/provider verification.
- Apply and verify the Prisma `RealClipCaptionUsage` migration in production
  before selling paid AI caption quotas.
- Keep legacy AI review compatibility flags false while validating real-clip AI
  captioning and Pro ElevenLabs + Gemini editing.
- Validate Pro AI auto editing with ElevenLabs transcription, Gemini planning,
  minute quotas, top-up handling, mobile FFmpeg export, retries, and failure handling.
- Complete Firebase Google Sign-In and Phone Auth device testing.
- RevenueCat Test Store purchase and true Restore/resync E2E pass on the Android
  Emulator after the current backend was deployed and
  `REVENUECAT_REST_API_V1_KEY` was configured in Render Staging.
- The RevenueCat dashboard now has a Play Store app, Starter/Pro products,
  entitlements, the default offering, and a production Android public SDK key;
  a signed AAB is also ready. Still create the Play Console app/subscriptions,
  configure Google service credentials, open an internal-testing track, and run
  a real Google Play purchase/restore. Those steps are blocked until Play Console
  access is verified with a physical Android device; an Emulator is not accepted.
- Add full RevenueCat renewal, cancel, refund, billing-issue, and notification
  replay coverage.
- Replace mock analytics with real platform analytics fetchers.
- Add audit logging and production monitoring (per-IP rate limiting is live via
  `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX_REQUESTS`).
