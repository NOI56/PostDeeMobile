# API.md

PostDee backend API reference.

This document describes the current Express + TypeScript scaffold in `apps/api`. It is written for local development and integration planning. Production integrations for social publishing, live analytics, Cloudflare R2, real-clip AI captioning, Pro Groq Whisper auto editing, Firebase, Apple App Store, and Google Play still require real credentials and provider-level testing.

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

The backend currently supports safe scaffold flows for:

- Health checks
- Mock or Firebase authentication
- Upload metadata validation, legacy mock/R2/S3 signed upload, managed R2
  multipart sessions, and signed read access scaffolding
- Post creation and queue handoff
- Caption generation through mock, Gemini, or legacy OpenAI providers. The
  product direction is real-clip captioning after a video is selected. Remote
  providers retry transient failures (e.g. a Gemini 503) with backoff and Gemini
  also falls back to a secondary model before `POST /captions/generate` degrades
  to the local template caption.
- Real-clip caption scaffold at `POST /captions/generate-from-clip`, with
  Starter/Pro mode selection, authenticated media-key ownership checks,
  optional temporary AI media cleanup, and monthly quota reservation through
  memory or Prisma-backed usage storage.
- Saved templates
- Pro-only analytics summary
- Store subscription verification scaffold for Apple App Store and Google Play
- Store server notification routes for renewal, cancel, refund, and grace-period handoff

The backend must not publish through shared PostPeer account ids in production
(startup rejects them). Production publishing resolves per-user social
connections. The existing `FACEBOOK_REELS` value maps to PostPeer
`platform: 'facebook'` with `platformSpecificData.contentType: 'reel'` for
Facebook Page Reels only; there is no fallback to a Page feed video. Real
PostPeer publishing must remain disabled until the per-user connect/refresh
flow and a controlled connected-account E2E test are approved.

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

| Feature | Basic | Starter | Pro |
| --- | --- | --- | --- |
| Price | Free | 199 THB/month | 299 THB/month |
| Phone verification | Required for free quota | Not required for quota | Not required for quota |
| Monthly post units | 3 after phone verification | 120 | 250 |
| Real-time posting | Yes | Yes | Yes |
| Cloud scheduling | No | Yes | Yes |
| Calendar for scheduled posts | No | Yes | Yes |
| AI caption from real clip | No | Audio-only, 50 generations/month scaffolded | Audio + selected frames, 120 generations/month scaffolded |
| AI auto editing with Groq Whisper | No | No | 200 minutes/month scaffolded |
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
- Pro users unlock analytics, hashtag radar, AI comment center, team/editor
  access, visual-frame AI captioning, and Groq Whisper auto editing scaffolds.
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

AI edit audio is the only supported audio upload exception. It must set
`"purpose": "ai-edit-audio"`, use an `.m4a` filename and `audio/mp4`, omit
`width`/`height`, and be no larger than 25 MiB. Audio without this purpose is
rejected with `UPLOAD_AI_EDIT_AUDIO_INVALID`.

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

`UPLOAD_PROTOCOL_MODE` defaults to `legacy`. `dual` and `multipart` require
`DATABASE_URL` because managed upload sessions are persisted through Prisma.
Production uses `dual` during the
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

Supported platform values:

```text
TIKTOK
YOUTUBE_SHORTS
INSTAGRAM_REELS
FACEBOOK_REELS
```

`FACEBOOK_REELS` is retained for mobile/API compatibility. The server always
sets PostPeer `platform: 'facebook'` and
`platformSpecificData.contentType: 'reel'` for this destination. It requires a
video and never falls back to a Facebook Page feed video. Real connected-account
E2E must verify the result is a Page Reel before Store claims or production
activation; Page Video duration limits do not establish a Reel duration limit.

There are no new client fields, environment variables, or database migrations.
After deploying the updated publisher, existing queued/scheduled posts carrying
`FACEBOOK_REELS` also use the Page Reels route when they are published.

### `GET /posts`

Returns posts for the authenticated user.

The Home dashboard calls `GET /posts?includeMedia=true&limit=3`. When that
opt-in query is present, each returned post can also contain short-lived,
private-storage download URLs for its source video and optional rendered cover.
An optional positive `limit` returns the newest posts by `createdAt`, is capped
at 50, and is applied before platform-result lookup and media URL signing.

Response:

```json
{
  "status": "ok",
  "posts": [
    {
      "id": "post-1",
      "videoUrl": "https://private-media.example/signed/video",
      "coverImageUrl": "https://private-media.example/signed/cover",
      "platformResults": [
        {
          "postId": "post-1",
          "platform": "TIKTOK",
          "status": "PUBLISHED",
          "externalPostId": "https://www.tiktok.com/@seller/video/123",
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

`videoUrl` and `coverImageUrl` are optional and appear only when
`includeMedia=true` and the configured storage adapter can issue signed
downloads. URLs are created only after the post list is scoped to the
authenticated user and limited to the requested recent rows. Mobile prefers
`coverImageUrl`; if no cover exists (for example, an older YouTube Shorts post),
it displays a paused frame from `videoUrl`. The video preview is released when
Home is no longer active. Both fields remain absent with mock storage, and the
UI falls back to the play placeholder when media is missing or cannot be loaded.

### `POST /posts`

Creates a queued post and hands it to the publish queue. Caption limits depend
on the selected platforms and are checked before any post quota is used (the
mobile app checks the same rules before uploading):

- Any platform other than YouTube: at most 2,200 Unicode code points
  (Instagram's limit, the strictest of them).
- YouTube: the caption is sent as the video description, which the YouTube Data
  API caps at 5,000 UTF-8 **bytes** (about 1,660 Thai characters) and which may
  not contain `<` or `>`. A YouTube-only post may therefore exceed 2,200
  characters in plain Latin text.

Too long returns `400 CAPTION_TOO_LONG`; `<`/`>` with YouTube selected returns
`400 CAPTION_INVALID_FOR_YOUTUBE`.

Request:

```json
{
  "caption": "Try this product today. #PostDee",
  "youtubeTitle": "Try this product today",
  "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
  "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
  "coverFrameTimeMs": 4200,
  "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
  "scheduledAt": "2026-06-06T10:00:00.000Z"
}
```

Rules:

- `caption` (a string), `videoS3Key`, and at least one valid platform are required.
  The caption must be nonempty except for a YouTube-only post with a nonempty
  custom `youtubeTitle`.
- `youtubeTitle` is an optional string override for YouTube Shorts. A nonempty
  override requires `YOUTUBE_SHORTS` among the selected platforms, is trimmed,
  must be at most 100 Unicode code points, and must not contain `<` or `>`.
  Omitting it or sending whitespace selects automatic title generation. The
  optional override is stored as a nullable field and is carried through the
  queue/worker; old requests without this field remain supported.
- Without an override, the YouTube title strips `<` and `>` before taking the
  first sentence of the first nonempty caption line, limited to 100 Unicode
  code points. This cleanup affects only the generated title: the full caption
  remains the YouTube description; other destinations keep the shared caption.
  The mobile client omits `youtubeTitle` in automatic mode so the backend
  derives the title using the same rule as the live preview.
- `videoS3Key` must be an upload key owned by the authenticated user, using the `uploads/<user-id>/<upload-id>/<file>` shape returned by `POST /uploads`.
- `coverImageS3Key` is optional. When present it must be an owner-scoped JPEG
  or PNG upload belonging to the same authenticated user and no larger than
  2 MiB. `coverFrameTimeMs` is an optional integer from `0` through
  `2147483647` containing the selected frame time in the source video.
- A managed multipart upload must have status `COMPLETED` before its
  `videoS3Key` or `coverImageS3Key` can be used. Legacy owner-scoped keys remain
  accepted for videos while the server is in `legacy` or `dual` rollout mode.
  Because cover support is new, cover keys require managed confirmation in
  `dual` and `multipart` modes; only pure `legacy` mode keeps the old fallback.
- If `scheduledAt` is present, the user must be Starter or Pro.
- `scheduledAt` must be a valid ISO-8601 time strictly after the server's
  current time; invalid or past values are rejected instead of being published
  immediately.
- `scheduledAt` cannot be more than 30 days after the server's current time.
- Basic users must have a verified phone number before using the free quota.
- Basic is limited to 3 post units per month after phone verification.
- Starter is limited to 120 post units per month.
- Pro is limited to 250 post units per month.
- Post units count selected platforms, not post rows.
- Repeated platform values are collapsed before quota accounting, persistence,
  and queueing. The quota check and post creation are one atomic store operation
  so concurrent requests cannot overspend the monthly allowance.

Worker behavior:

- YouTube receives the stored custom `youtubeTitle` when present, otherwise
  the title derived from the caption. The title and full description are sent
  as separate fields; scheduled jobs preserve the same title choice.
- The publish worker claims a post by moving it from `QUEUED` to `PUBLISHING`
  before calling the platform publisher.
- PostPeer `202 pending/publishing` is not treated as success. The adapter polls
  `GET /v1/posts/{postId}` for roughly two minutes and records `PUBLISHED` only
  when the selected platform has a real `platformPostUrl` or `platformPostId`.
  It never fabricates an external id. Each PostPeer request times out after 60
  seconds: a timed-out create is an unknown outcome (never resubmitted), and a
  timed-out status check counts as one unanswered poll.
- A provider call is retried only for an explicitly safe error proving that no
  external post was accepted. A network/timeout or uncertain PostPeer outcome is
  not submitted again; clients must check the platform before a manual retry.
- Retry or duplicate jobs are skipped when the post is already `PUBLISHING`,
  `PUBLISHED`, `PARTIAL_PUBLISHED`, or `FAILED`.
- The in-process scheduler publishes up to 4 due posts at once, and ticks may
  overlap, so one slow provider publish does not delay posts that become due
  later. Each post is started at most once per process; the atomic claim still
  guards across instances.
- The in-process scheduler fails posts left `PUBLISHING` for over 30 minutes
  (for example after a restart or deploy killed their worker), checked at most
  once a minute. Platforms without a saved result get the "result could not be
  confirmed" error and the owner gets a `FAILED` push. These posts are never
  published again automatically, because the provider may have accepted them.
- Stale scheduled jobs are skipped when the job `runAt` no longer matches the
  post's current `scheduledAt`, such as after a reschedule.
- Optional R2/S3 cleanup after a fully successful publish is best-effort. A
  cleanup failure is returned in the worker result, but the post stays
  `PUBLISHED`.
- If the publish queue is unavailable while creating or rescheduling a post,
  the API returns `503` with `PUBLISH_QUEUE_UNAVAILABLE` and keeps the post
  store from advancing ahead of the queue.
- Cover delivery is capability-aware: Instagram receives the signed cover
  image (or the selected frame offset when no image is available). Facebook
  Page Reels requests retain `contentType: 'reel'` and optionally send the signed
  image as `videoThumbnailUrl` on a best-effort basis. Its display on a Reel is
  not verified; the provider may choose the cover. TikTok Direct Post receives
  only the selected frame time. YouTube Shorts does not
  receive a custom thumbnail because YouTube requires Shorts cover selection
  to be completed in the YouTube mobile app.

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
    "youtubeTitle": "Try this product today",
    "videoS3Key": "uploads/local-dev-user/upload-id/demo-video.mp4",
    "coverImageS3Key": "uploads/local-dev-user/cover-upload-id/post-cover.jpg",
    "coverFrameTimeMs": 4200,
    "platforms": ["TIKTOK", "YOUTUBE_SHORTS"],
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
the publish queue cannot be rescheduled. The new time must be a valid future
ISO-8601 value and cannot be more than 30 days after the server's current time.
The current server-resolved plan must be Starter or Pro. Basic, including an
expired or canceled paid subscription, receives `402 PAID_PLAN_REQUIRED`
before either the queue or post is changed. A body `subscriptionPlan` hint
cannot grant scheduling access.

### `DELETE /posts/:id`

Deletes an authenticated user's scheduled/queued post and removes its publish
job. Returns `{ "status": "ok" }` or `404` when no user-owned post is found.

## Devices And Social Connections

### `POST /devices`

Registers the authenticated user's FCM token. Body:
`{ "token": "...", "platform": "IOS|ANDROID|WEB" }`; `platform` is optional.
Each account keeps only its 10 most recently registered tokens; older ones are
deleted. Tokens FCM reports as unregistered or invalid after a send are removed
for their owner, and sends are batched at 500 tokens.

Publish-result pushes include `data: { postId, type: "publish_result", userId }`,
where `userId` is the same owner used to select device tokens. Mobile clears its
in-app notification list on a session change and accepts messages only for the
current UID. Older payloads without a recipient UID are ignored. This filter
does not control OS-displayed background notifications or detach device tokens
already registered with the backend.

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

TikTok native authorization is proposed only, pending developer registration.
The runtime does not expose native authorization metadata or a native
completion endpoint. Its draft contract and security requirements are in the
[TikTok setup and design plan](docs/superpowers/plans/2026-10-21-tiktok-native-connection.md);
they are not a current API contract.

### `POST /social-connections/refresh`

Polls the user's PostPeer profile integrations after the browser OAuth flow,
then upserts connected platforms and removes stale local connections. PostPeer
does not call a signed-state callback in the current implementation.

Mobile calls this same authenticated endpoint automatically when a pending
connection leaves the app and the original signed-in session returns to the
foreground. Manual refresh remains available. Opening or closing a Custom Tab
does not establish connection success; the provider integrations returned by
the backend determine status. This trial adds no API fields, mobile callback
endpoint, or `redirectUri` contract. See the
[mobile connection trial](docs/superpowers/plans/2026-10-25-postpeer-mobile-connection-trial.md).

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

Behavior:

- Marks the owner as deleting before cleanup starts, including in legacy upload
  mode. Whenever Prisma is active, the existing `ManagedUploadOwner` table
  persists this marker; otherwise the marker is process-local. Later mutation
  admission is rejected and the publish worker checks it before claiming a job.
- User creation, post creation/quota/rescheduling, subscription activation and
  RevenueCat event writes lock an ACTIVE owner marker inside the same
  Serializable database transaction as their final write. Memory stores use a
  shared owner FIFO. These operations reject a deleting/deleted owner with
  `409 ACCOUNT_DELETION_IN_PROGRESS` even if admitted before deletion.
- Drains same-process publish queue admission, then cancels owned queued jobs,
  including jobs whose post row has already been rolled back or deleted.
  An unfinished admission returns `503 ACCOUNT_WRITE_DRAIN_FAILED`; a queue
  cleanup failure returns `503 ACCOUNT_PUBLISH_CLEANUP_FAILED`. Retry deletion.
  SQL and Redis are not atomic: cross-instance late adds, process crashes and
  already-admitted provider calls still need reconciliation/draining. Templates,
  device tokens and social data do not yet have these final-write fences.
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
- When Firebase auth is used, `FIREBASE_AUTH_DELETE_ENABLED=true` and
  `FIREBASE_SERVICE_ACCOUNT_JSON` are required. Firebase identity is deleted
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
- Mobile deletion consent is bound to the session that opened the confirmation.
  Readiness, token refresh, Apple revocation and deletion stop if that session
  changes. Native login/logout and Apple deletion revocation share a queue;
  a late response cannot log out or show deletion feedback to the next account.

Success response:

```json
{
  "status": "ok"
}
```

## Captions

### `GET /captions/quota`

Reads the authenticated user's current plan and monthly AI caption quota.
This is read-only: it does not generate captions, reserve quota, or upload media.

- The plan comes from the subscription store and usage is scoped to the
  authenticated user, not a user or plan supplied in the query/body.
- Counts the current UTC calendar month in the shared caption usage ledger
  used by both `/captions/generate` and `/captions/generate-from-clip`.
- Returns `200` for Basic, Starter, and Pro. Limits are `0`, `50`, and `120`
  respectively. Basic has no AI generation entitlement; this read endpoint
  does not unlock generation.
- `usedThisMonth` retains recorded usage, including after a downgrade.
  `remainingThisMonth` is `max(limit - usedThisMonth, 0)`.
- Missing authentication returns `401`.

Example response:

```json
{
  "status": "ok",
  "plan": "STARTER",
  "quota": {
    "limit": 50,
    "usedThisMonth": 12,
    "remainingThisMonth": 38
  }
}
```

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
- It uses exactly one of `audioS3Key` or `videoS3Key`, optional `guidance`,
  optional `selectedFrameKeys`, and optional `deleteAfterUse`. Sending both, or
  neither, returns `400`.
- `audioS3Key` is the current mobile path: the app extracts the clip's audio
  on device (M4A, `audio/mp4`, 64 kbps mono) and uploads it with
  `"purpose": "ai-edit-audio"`. The key must end in `.m4a` (`400` otherwise)
  and the stored object must be `audio/mp4` (`415
  AI_CAPTION_MEDIA_TYPE_INVALID` otherwise). `videoS3Key` remains for older
  app versions that upload the full clip. The response `source.videoS3Key`
  echoes whichever clip key was used.
- `audioS3Key`/`videoS3Key` and any `selectedFrameKeys` must be upload keys
  owned by the authenticated user, using the
  `uploads/<user-id>/<upload-id>/<file>` shape returned by `POST /uploads`.
- When the mobile app uploads media only for AI captioning, it sends
  `"deleteAfterUse": true`; the backend then attempts to delete the clip and
  selected frames after the request. Cleanup failures are logged but do not
  block a successful caption response.
- Usage is reserved before the AI provider is called so simultaneous requests
  cannot exceed the monthly quota within the configured usage store.
- Gemini rejects inline requests over 20 MB, so caption media is capped before
  the body is read: the clip (audio or legacy video) at 10 MiB, returning
  `413 AI_MEDIA_TOO_LARGE` above it, and each frame at 1 MiB. Frames that are
  oversized or not `image/jpeg`/`image/png` are skipped rather than failing the
  caption. The caps also bound how much memory one request holds.
- When `CAPTION_PROVIDER=gemini`, this endpoint sends the clip to Gemini to
  listen and write the caption directly (Starter = audio only; Pro =
  `AUDIO_WITH_FRAMES`, also sending the `selectedFrameKeys` images). Gemini
  retries transient failures and falls back to a secondary model, then to the
  local template caption if it still fails, so a caption is always returned.
- When no Gemini provider is configured, it falls back to the legacy path: the
  configured `TRANSCRIPTION_PROVIDER` (e.g. Groq Whisper) transcribes the clip
  and a local template builds the caption.
- Note: Groq Whisper is otherwise reserved for the auto-editing/subtitle flow
  (which needs accurate timestamps); the caption path prefers Gemini.
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
  "audioS3Key": "uploads/local-dev-user/upload-id/postdee-ai-edit-audio.m4a",
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
- The current product plan sells real-clip captioning and future Pro Groq Whisper
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
(otherwise `402` with `code: "PRO_REQUIRED"`). `GET /ai-edits/quota` and the
idempotent temporary-audio cleanup endpoint are available to any authenticated
user.

### `POST /ai-edits/transcribe`

Transcribes an uploaded clip (Thai). Meters usage against a monthly minute quota
(`200` min); returns `402` `AI_EDIT_QUOTA_EXCEEDED` when exhausted. The client
`durationSeconds` estimate is reserved atomically **before** the paid
transcription call, so parallel requests near the limit are rejected without
reaching the provider. After transcription the reservation is re-priced to the
real transcribed minutes; if those do not fit the remaining quota the request
returns `402` and the estimate stays charged (the provider call already
happened), so under-reporting duration gains nothing. A failed transcription
releases the reservation. New clients send exactly one owned M4A
audio key:
`{ "audioS3Key": "uploads/<user-id>/<upload-id>/clip.m4a", "durationSeconds": 18 }`.
Existing deployed clients may temporarily send `videoS3Key` instead. Sending
both keys returns `400 AI_EDIT_MEDIA_AMBIGUOUS`; sending neither returns
`400 AI_EDIT_MEDIA_REQUIRED`. Response includes `transcript` (text, language,
durationSeconds, segments[], words[]) and `quota`.

Audio downloads require `audio/mp4` and are capped at 25 MiB. Legacy video
downloads retain the 200 MiB ceiling. Owned temporary audio is deleted after
every accepted attempt, including plan/quota rejection and provider failure;
legacy video is never automatically deleted by these endpoints.
The Groq adapter sends `language=th` and requests both `word` and `segment`
timestamp granularities. It also sends the concise Thai spelling context
`PostDee` → `โพสต์ดี` through Groq's transcription prompt; the OpenAI adapter
does not receive this provider-specific prompt.
Validated word timing is preferred for subtitle timing and silence-gap cuts,
while segments remain the conservative fallback when timing coverage is partial
or Groq returns Thai character-level tokens that are not readable subtitle words.
Whitespace-only/punctuation-only timing tokens are ignored, while invalid tokens
that contain transcript text invalidate word-level timing and trigger fallback.

### `POST /ai-edits/audio/cleanup`

Best-effort recovery cleanup for an uploaded temporary M4A when the edit request
or response is interrupted. Request:
`{ "audioS3Key": "uploads/<user-id>/<upload-id>/clip.m4a" }`. The key must be an
owned `.m4a`; cross-user keys return `403 MEDIA_KEY_FORBIDDEN`. Deletion is
idempotent, so retrying the same request returns `{ "status": "ok" }`.

### `GET /ai-edits/quota`

Reports `{ limitMinutes, usedMinutes, remainingMinutes }` for the current month.

### `POST /ai-edits/prepare`

Builds the UI-facing mobile render recipe for the AI editing screen. This is the
backend contract for the Claude Design flow: the app sends the selected clip,
the requested result length in `targetDurationSeconds`, optional style/prompt,
and capability toggles such as `subtitle`, `silence`,
`filler`, `hook`, `zoom`, `color`, `cta`, `pricetag`, and `watermark`.

This endpoint is Pro-gated and minute-metered like `/ai-edits/transcribe`: the
client `durationSeconds` estimate is reserved before transcription, re-priced to
the real transcribed minutes, and only then is the edit plan and recipe built.
If transcription or a configured live edit planner fails (`502` with
`code: "AI_EDIT_PLAN_PROVIDER_FAILED"`), the reservation is released, so that
failed prepare attempt does not consume the user's minute quota. A `prompt`
longer than 500 characters returns `400 AI_EDIT_PROMPT_TOO_LONG` before any
minutes are reserved. It does **not** render
video on the server; mobile still renders/exports with FFmpeg.

Request:

```json
{
  "audioS3Key": "uploads/local-dev-user/upload-id/analysis.m4a",
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
    "fillerWords": ["เอ่อ", "อ่า", "แบบว่า", "คือว่า", "ประมาณว่า"],
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

Response includes:

- `recipe.renderMode: "mobile-ffmpeg"`
- `recipe.transcript` with text, language, duration, segments, words, and model
- `recipe.subtitles` for mobile subtitle burn-in
- `recipe.cutRanges`, `silenceRanges`, and `fillerRanges`
- `recipe.plan`, whose cuts select the strongest transcript moments within
  `targetDurationSeconds` while preserving chronological order. The first
  production version scores spoken hooks, benefits, proof, offers, and calls to
  action. LLM cut ranges are clamped, sorted, and merged before duration math or
  mobile rendering; visual highlight selection still requires a future visual
  proxy.
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

Production mobile enables only `subtitle`, `silence`, `filler`, and `color`,
because those four have a real local renderer. The setup UI locks auto-reframe,
zoom, and audio cleanup as `เร็ว ๆ นี้`. Subtitle translation, price tag, CTA,
and the AI-page watermark are hidden from the customer UI while deferred and
are still sent as `false` for compatibility.

Capabilities that need future analysis or rendering, including beat sync, the
opening hook/highlight, auto-reframe, zoom, SFX/music choice, audio cleanup,
subtitle translation, price tag, CTA, and the AI-page watermark, are accepted
from older/internal clients but marked `planned` so the UI can stay honest.

`settings.silencePreset` accepts three values and changes the minimum gap
between validated word timings that becomes a silence range. The recipe falls
back to transcript segment gaps when word timing is missing or incomplete. It
also returns qualifying leading and trailing silence; trailing silence requires
a finite `transcript.durationSeconds`:

- `natural`: 1.0 second
- `balanced`: 0.6 second (also used when the field is missing or invalid)
- `compact`: 0.4 second

`settings.fillerWords` is an exact allowlist. Supported values are `เอ่อ`,
`อ่า`, `แบบว่า`, `คือว่า`, and `ประมาณว่า`. The backend normalizes NFC and
removes surrounding whitespace, punctuation, and symbols before comparing a
normal transcript word; `เออ` is an exact transcription alias for `เอ่อ` but a
longer token such as `เออแล้ว` does not match. When Groq returns a validated Thai
character-token stream, the backend may conservatively reassemble adjacent
fragments that equal an allowlisted filler. Reassembly cannot cross a timing
gap and requires a real gap or verified Thai word/text boundaries; short
prefixes remain stricter. Omitting the field preserves legacy behavior and checks all
five words. Sending `[]`, a non-array value, or
an array that sanitizes to no supported values fails closed and produces no
filler ranges; it does not fall back to the legacy list.

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

After result review, mobile may pass the accepted local render to Upload/Post.
PostDee has no built-in manual timeline editor. Users may separately choose an
external editor such as CapCut, but the API exposes no CapCut integration,
export target, or share-handoff endpoint. This product-scope decision does not
change the AI edit request/response schema or any backend endpoint.

Mobile derives the review's detected counts from `silenceRanges.length` and
`fillerRanges.length`, then merges overlapping/clamped ranges before displaying
the detected time.
That summary describes pre-render detections and must not be presented as the
exact duration removed from the exported clip.

### `POST /ai-edits/plan`

Returns a structured cut plan for an auto-edit style or a free-form prompt,
computed from an already-transcribed clip. Pro-gated but **not** minute-metered,
so its client input is capped: `prompt` up to 500 characters
(`400 AI_EDIT_PROMPT_TOO_LONG`) and at most 600 `segments` of up to 300
characters each (`400 AI_EDIT_SEGMENTS_TOO_LARGE`). Live planner calls time out
after 45 seconds and return the `502` provider error below.

`EDIT_PLAN_PROVIDER=mock` explicitly selects the rule-based test planner and
returns `model: "mock-rule"`; mobile must label that result as test mode. The
`openai` and `groq` values call their configured live LLM. A live provider
network error, non-success response, empty response, or invalid JSON returns
`502` with `code: "AI_EDIT_PLAN_PROVIDER_FAILED"`; it never silently falls
back to `mock-rule`.

Request (one of `styleId` or `prompt` is required):

```json
{
  "styleId": "flash_sale",
  "prompt": "เธ•เธฑเธ”เธเธณเธซเธขเธฒเธเธญเธญเธเนเธฅเนเธงเน€เธซเธฅเธทเธญ 15 เธงเธด",
  "durationSeconds": 30,
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

`cuts` are absolute-second ranges to remove; the client feeds them into the same
on-device render pipeline used by silence/segment cuts. Returns `400` when
`durationSeconds` is missing or neither `styleId` nor `prompt` is provided.

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

Creates a saved text template for the authenticated user. `title` may be at
most 80 and `body` at most 2,200 Unicode code points (`400 TEMPLATE_TOO_LONG`);
the body shares the post caption limit because templates are inserted into
captions. Each account can save up to 30 templates (`409
TEMPLATE_LIMIT_REACHED`); deleting one frees its slot.

### `DELETE /templates/:id`

Deletes one of the authenticated user's templates. Returns `{ "status": "ok" }`,
or `404` when the template does not exist or belongs to another user. The mobile
Templates screen asks for confirmation before calling it.

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
This endpoint is read-only and does not create or recreate a `User` row.
RevenueCat clients must prepare the authenticated account before opening a
purchase, using the endpoint below.

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

### `POST /billing/purchase-readiness`

Authenticated purchase preparation. Send `{}` before calling the RevenueCat
purchase SDK. The account-aware mutation middleware rejects deleting/deleted
owners and ensures the canonical user for the authenticated principal; body
user selectors cannot choose another user. Success returns
`200 { "status": "ok", "purchaseReady": true, "preparationProtocol": 1 }`.
Missing authentication returns `401`; a deletion barrier returns
`409 ACCOUNT_DELETION_IN_PROGRESS`. No payment, entitlement activation or
provider read occurs. A failed preparation must prevent the SDK purchase.
The mobile app also stops before buy if its session changes while awaiting SDK
availability or preparation. RevenueCat configuration, product lookup and the
SDK buy/restore callback share a queue across gateway instances and retain the
original UID/session. Default readiness, resync and entitlement-poll requests
use bound auth headers; changed sessions and mismatched response owners cannot
produce subscription success. Already-dispatched native payment/configuration
cannot be canceled by these checks and still needs device validation.

Coordinate API/mobile rollout: older clients that depended on GET creating the
user need this preparation step before the read-only GET change is deployed.
The existing webhook missing-user protection remains required.
Current mobile clients require that explicit protocol-1 acknowledgement.
`404`, `501`, a status-only response or an unsupported acknowledgement shows
"ระบบสมาชิกยังไม่พร้อมสำหรับแอปเวอร์ชันนี้ กรุณาลองใหม่ภายหลัง" and prevents SDK
purchase and subsequent subscription polling. Authentication, deletion and
service errors retain their normal error handling. Older clients that already
await this POST can ignore the additive response fields.

Release sequence: introduce the additive preparation endpoint, release mobile
clients that await it, retire or independently disable purchase on builds that
never call it, then deploy read-only GET. This branch contains the GET cutover
already; do not deploy it while those legacy builds can still buy. They can buy
after a failed GET, so a new endpoint/server error cannot remotely disable their
purchase flow. Keep webhook missing-user protection; do not restore GET writes.

### `POST /billing/revenuecat/webhooks`

Receives RevenueCat subscription lifecycle events when
`BILLING_PROVIDER=revenuecat`.

This endpoint requires:

```http
Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>
```

The token (and the Google Play notification token) is compared in constant
time over SHA-256 digests, so response timing reveals neither its length nor a
matching prefix.

RevenueCat `app_user_id` must match the PostDee user id. In production this
should be the Firebase uid used by the mobile app. The backend maps RevenueCat
entitlement ids or product ids to PostDee plans, stores the billing id as
`revenuecat:<app_user_id>`, and keeps `GET /billing/subscription` as the single
app-facing entitlement endpoint.

Example request:

```json
{
  "event": {
    "id": "revenuecat-event-id",
    "type": "INITIAL_PURCHASE",
    "app_user_id": "firebase-user-id",
    "product_id": "postdee_pro_monthly",
    "entitlement_ids": ["pro"],
    "event_timestamp_ms": 1780444800000,
    "expiration_at_ms": 1780531200000
  }
}
```

Every event that activates or expires an entitlement must include a non-empty
`event.id` and a positive integer `event_timestamp_ms`; missing or invalid
ordering metadata returns `400 REVENUECAT_WEBHOOK_INVALID` without changing the
subscription. The server persists the latest cursor per user. A retry with the
same event id, or an event whose timestamp is not newer, returns `200` with
`ignored: true` so delayed webhooks cannot overwrite newer entitlement state.

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
`CANCELLATION`, `SUBSCRIPTION_PAUSED`, and `BILLING_ISSUE` are acknowledged
without revoking access immediately because the subscription can still be active
until the paid period actually expires. Unknown product or entitlement ids return
`202` with `ignored: true`.

`TRANSFER` (a purchase moved to another App User ID, e.g. a restore while signed
in to a different account) carries no `app_user_id` or product. It requires
`id`, `event_timestamp_ms`, and a non-empty `transferred_from` list (`400`
otherwise). Each existing PostDee user in `transferred_from` (and not in
`transferred_to`) has their RevenueCat-bound subscription set to `CANCELED`,
using the same per-user event ordering as other events; anonymous or unknown ids
are skipped. The response lists `revokedUserIds`. The receiving account gains
access through `POST /billing/revenuecat/resync` after restore, or its next
RevenueCat event.

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
For an empty RevenueCat result, top-level `plan` is `BASIC` so the client does
not report a successful Restore; `effectivePlan` separately reports any access
that remains active from another provider.

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
publish queue job. Once the in-process scheduler publishes or fails a post, its
job is removed, so the list only shows posts still waiting to publish.

Response:

```json
{
  "status": "ok",
  "jobs": []
}
```

The checked-in Render deployment currently uses `PUBLISH_QUEUE=memory`,
`POST_STORE=prisma`, and one API instance. Starting the API also starts its
in-process scheduler, which reads due posts from PostgreSQL. Queue entries
remain in memory; persisted posts and the scheduler are separate from the
`GET /queue/jobs` diagnostic listing. This is a description of source
configuration, not a new live-deployment check.

Optional Redis/BullMQ deployment for scaling:

```env
PUBLISH_QUEUE="bullmq"
POST_STORE="prisma"
DATABASE_URL="postgresql://..."
REDIS_URL="redis://localhost:6379"
```

`PUBLISH_QUEUE=bullmq` requires `POST_STORE=prisma` and `DATABASE_URL` because
the API and worker run in separate processes and must share post state through
PostgreSQL. It also needs `REDIS_URL` and a separately running publish worker.
Migrate and verify that path before increasing the API instance count.

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
| `FIREBASE_AUTH_DELETE_ENABLED` | `false`, `true` | Enables complete Firebase account deletion and revoked/deleted-token checks; requires the Firebase service account |
| `PUSH_SENDER` | `mock`, `firebase` | Push sender adapter; keep `mock` until the Firebase sender is verified with the installed Admin SDK |
| `VIDEO_STORAGE` | `mock`, `r2`, `s3` | Temporary video storage adapter |
| `CLOUDFLARE_R2_BUCKET` | `postdee-video-temp` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | `...` | Cloudflare account id |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | `...` | R2 S3-compatible access key id |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | `...` | R2 S3-compatible secret access key |
| `CLOUDFLARE_R2_ENDPOINT` | `https://<account>.r2.cloudflarestorage.com` | Optional custom R2 endpoint |
| `CLOUDFLARE_R2_UPLOAD_EXPIRES_SECONDS` | `300` | Signed upload URL lifetime; legacy retries request one fresh URL after explicit expiry, while multipart retries refresh only the affected part URL |
| `UPLOAD_PROTOCOL_MODE` | `legacy`, `dual`, `multipart` | Upload rollout mode; `dual`/`multipart` require `DATABASE_URL`; defaults to `legacy`, production uses `dual` during client migration, and strict `multipart` rejects old clients without the opt-in |
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
| `OPENAI_API_KEY` | `...` | Legacy OpenAI API key |
| `OPENAI_CAPTION_MODEL` | `gpt-4o-mini` | Legacy OpenAI caption model |
| `TRANSCRIPTION_PROVIDER` | `mock`, `openai`, `groq` | AI caption language detection and AI edit transcription provider |
| `GROQ_API_KEY` | `...` | Groq API key for AI caption detection and AI edit transcription |
| `GROQ_TRANSCRIPTION_MODEL` | `whisper-large-v3` | Groq transcription model |
| `WHISPER_MODEL` | `whisper-1` | Legacy OpenAI transcription model |
| `EDIT_PLAN_PROVIDER` | `mock`, `openai`, `groq` | Brain for AI edit planning; `mock` is explicit rule-based test mode, while live OpenAI/Groq failures return `502 AI_EDIT_PLAN_PROVIDER_FAILED` without a mock fallback |
| `OPENAI_EDIT_PLAN_MODEL` | `gpt-4o-mini` | OpenAI chat model for edit planning |
| `GROQ_EDIT_PLAN_MODEL` | `llama-3.3-70b-versatile` | Groq chat model for edit planning |
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
| `ANALYTICS_STORE` | `memory`, `prisma` | Analytics persistence; `prisma` requires `POST_STORE=prisma` |
| `CAPTION_USAGE_STORE` | `memory`, `prisma` | Real-clip AI caption monthly usage persistence |
| `AI_EDIT_USAGE_STORE` | `memory`, `prisma` | AI editing monthly minute usage persistence |
| `PUBLISH_QUEUE` | `memory`, `bullmq` | Current Render config uses `memory` with an in-process scheduler, Prisma posts, and one API instance. Optional `bullmq` requires `POST_STORE=prisma`, `DATABASE_URL`, `REDIS_URL`, and a separate worker. |
| `SOCIAL_PUBLISHER` | `mock`, `disabled`, `postpeer` | Local fake success, explicit fail-closed staging/maintenance mode, or real PostPeer publishing |
| `POSTPEER_API_KEY` | `...` | PostPeer API key for real social publishing |
| `POSTPEER_API_BASE_URL` | `https://api.postpeer.dev` | Optional PostPeer API host override |
| `POSTPEER_LEGACY_RECOVERY_FINGERPRINT` | 64 hex characters | Temporary one-user repair proof: `HMAC-SHA256(POSTPEER_API_KEY, "postdee-legacy-recovery:<firebase-user-id>")`; must be paired with the exact profile id and removed after refresh succeeds |
| `POSTPEER_LEGACY_RECOVERY_PROFILE_ID` | `...` | Exact PostPeer profile id allowed for the temporary legacy repair; must be paired with the fingerprint |
| `POSTPEER_TIKTOK_ACCOUNT_ID` | `abc123` | Operator PostPeer TikTok integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_YOUTUBE_ACCOUNT_ID` | `abc123` | Operator PostPeer YouTube Shorts integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_INSTAGRAM_ACCOUNT_ID` | `abc123` | Operator PostPeer Instagram Reels integration id used only when no per-user connection resolver is wired; forbidden in production |
| `POSTPEER_FACEBOOK_ACCOUNT_ID` | `abc123` | Operator PostPeer Facebook Page integration id for `FACEBOOK_REELS` (Page Reels only via `contentType: 'reel'`) used only when no per-user connection resolver is wired; forbidden in production |
| `MOCK_USER_ID` | `local-dev-user` | Default mock user id |

## Production Gaps

The following work is still required before production launch:

- Verify the per-user PostPeer connect/refresh and full publish-result flow with
  connected test accounts before enabling production user publishing; do not
  use shared `POSTPEER_*_ACCOUNT_ID` values in production. Controlled-first
  requests currently force YouTube `private` and TikTok `SELF_ONLY` direct
  publishing; add explicit user privacy controls before public rollout.
- Store social access tokens securely only if direct platform APIs replace the
  PostPeer provider later.
- Complete full mobile-to-worker R2 upload/cleanup and slow-network testing.
  Earlier disposable-account production API smoke results cover legacy and
  managed multipart paths, not every device/provider flow.
- Test real-clip caption transcription with real R2 videos and Groq before
  production launch. Mobile frame extraction/upload (up to 3 frames) is
  implemented and still needs real-device/provider verification.
- Apply and verify the Prisma `RealClipCaptionUsage` migration in production
  before selling paid AI caption quotas.
- Keep legacy AI review compatibility flags false while building real-clip AI
  captioning and Pro Groq Whisper editing.
- Pro AI auto editing already has Groq Whisper transcription, minute-metered
  prepare recipes, on-device FFmpeg render/review, and continuation to
  Upload/Post. Remaining work includes persistent job/session recovery,
  top-up handling, and real-device/provider verification. A built-in manual
  timeline editor is outside the current app scope.
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
